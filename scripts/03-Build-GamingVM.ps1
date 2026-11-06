<#
.SYNOPSIS
    Automated fast provisioning of Windows 11 Pro Gaming VM master disk using DISM.
.DESCRIPTION
    Creates a dynamic VHDX, initializes GPT with UEFI/FAT32 and Windows/NTFS partitions,
    applies Windows 11 Pro (Index 3) directly from the ISO via DISM, configures UEFI boot,
    performs offline DISM debloat of consumer AppX packages (preserving Store and Xbox),
    applies Winhance privacy and UI tweaks (classic context menu, show extensions, disable telemetry),
    deploys desktop tools (Chrome, RealVNC, Winhance, WinRAR, HWID tools) to Desktop,
    injects unattended answer file (Gamer user, autologon, high performance),
    injects host NVIDIA GPU-PV drivers into HostDriverStore, System32, and SysWOW64,
    and stages Virtual Display Driver (1024x768 @ 60Hz) and Sunshine with auto-run scripts.
#>

[CmdletBinding()]
param(
    [string]$VMName = "Gaming-Base",
    [string]$VHDPath = "C:\Hyper-V\VMs\Gaming-Base.vhdx",
    [int]$VHDSizeGB = 150,
    [string]$IsoPath = "C:\Users\server1\Desktop\localserver1\ru-ru_windows_11_business_editions_version_25h2_updated_jan_2026_x64_dvd_d869ebf3.iso",
    [int]$ImageIndex = 3, # Windows 11 Pro
    [string]$GuestIP = "192.168.100.11",
    [string]$StagingRoot = "C:\Users\server1\Desktop\Hyper-V\staging"
)

$ErrorActionPreference = "Stop"

# Auto-elevate or require Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "03-Build-GamingVM.ps1 must be run in an elevated PowerShell session (as Administrator)."
}

Write-Host "=== Starting Build for $VMName ===" -ForegroundColor Cyan

# 1. Validation
if (-not (Test-Path $IsoPath)) {
    throw "Target ISO not found at: $IsoPath"
}
$stagingDrivers = Join-Path $StagingRoot "drivers"
$stagingGuestSetup = Join-Path $StagingRoot "guest_setup"
if (-not (Test-Path $stagingDrivers) -or -not (Test-Path $stagingGuestSetup)) {
    throw "Staged drivers or guest setup not found. Run 02-Prepare-Drivers.ps1 first."
}

# Ensure parent directory for VHDX exists
$vhdDir = Split-Path -Path $VHDPath -Parent
if (-not (Test-Path $vhdDir)) {
    New-Item -ItemType Directory -Path $vhdDir -Force | Out-Null
}

# If VHDX already exists, remove it
if (Test-Path $VHDPath) {
    Write-Host "[!] Existing VHDX found at $VHDPath. Removing..." -ForegroundColor Yellow
    [System.IO.File]::SetAttributes($VHDPath, [System.IO.FileAttributes]::Normal)
    Dismount-DiskImage -ImagePath $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
    Remove-Item -Path $VHDPath -Force
}

# 2. Create Dynamic VHDX
Write-Host "[+] Creating dynamic VHDX ($VHDSizeGB GB) at $VHDPath..." -ForegroundColor Green
New-VHD -Path $VHDPath -SizeBytes ([int64]$VHDSizeGB * 1GB) -Dynamic | Out-Null

# 3. Mount VHDX
Write-Host "[+] Mounting VHDX..." -ForegroundColor Green
$mountedVhd = Mount-VHD -Path $VHDPath -Passthru
$diskNumber = $mountedVhd.DiskNumber
Start-Sleep -Seconds 2

Write-Host "[*] VHDX attached as Disk Number: $diskNumber" -ForegroundColor Gray

# 4. Partition and Format GPT
Write-Host "[+] Initializing GPT disk and creating partitions..." -ForegroundColor Green
Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop

# EFI Partition (100MB FAT32)
$efiPart = New-Partition -DiskNumber $diskNumber -Size 100MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'
$efiVol = Format-Volume -Partition $efiPart -FileSystem FAT32 -NewFileSystemLabel "SYSTEM" -Confirm:$false

# MSR Partition (16MB)
New-Partition -DiskNumber $diskNumber -Size 16MB -GptType '{e3c9e310-0b5e-4965-9774-360f35e3ea8d}' | Out-Null

# Windows Partition (Remaining space, NTFS)
$winPart = New-Partition -DiskNumber $diskNumber -UseMaximumSize
$winVol = Format-Volume -Partition $winPart -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false

# Assign Explicit Free Drive Letters
$usedLetters = (Get-Volume | Where-Object { $_.DriveLetter }).DriveLetter
$availableLetters = 71..89 | ForEach-Object { [char]$_ } | Where-Object { $_ -notin $usedLetters }
$efiLetter = [string]$availableLetters[0]
$winLetter = [string]$availableLetters[1]

Set-Partition -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -NewDriveLetter $efiLetter
Set-Partition -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $winLetter
Start-Sleep -Seconds 1

Write-Host "[*] Partitions ready: EFI -> ${efiLetter}:, Windows -> ${winLetter}:" -ForegroundColor Gray

# 5. Mount ISO and Apply Windows Image via DISM
Write-Host "[+] Mounting ISO: $IsoPath..." -ForegroundColor Green
$isoMount = Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -PassThru
Start-Sleep -Seconds 2
$isoDrive = (Get-Volume -DiskImage $isoMount).DriveLetter
$wimPath = "${isoDrive}:\sources\install.wim"

if (-not (Test-Path $wimPath)) {
    throw "install.wim not found on mounted ISO (${isoDrive}:\sources\install.wim)"
}
Write-Host "[*] ISO mounted at ${isoDrive}: (WIM: $wimPath)" -ForegroundColor Gray

Write-Host "[+] Applying Windows 11 Pro (Index $ImageIndex) to ${winLetter}:\ via DISM..." -ForegroundColor Green
& dism.exe /Apply-Image /ImageFile:"$wimPath" /Index:$ImageIndex /ApplyDir:"${winLetter}:\"
if ($LASTEXITCODE -ne 0) {
    throw "DISM Apply-Image failed with exit code $LASTEXITCODE"
}
Write-Host "[+] Image applied successfully!" -ForegroundColor Green

# 6. Generate Boot Records using bcdboot
Write-Host "[+] Generating UEFI BCD boot records..." -ForegroundColor Green
& bcdboot.exe "${winLetter}:\Windows" /s "${efiLetter}:" /f UEFI
if ($LASTEXITCODE -ne 0) {
    throw "bcdboot failed with exit code $LASTEXITCODE"
}
Write-Host "[+] UEFI Boot records configured." -ForegroundColor Green

# 7. Debloat Consumer AppX Packages Offline via DISM
Write-Host "[+] Performing offline debloat of unwanted AppX packages..." -ForegroundColor Green
$packagesToRemove = @(
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.People",
    "Microsoft.PowerAutomateDesktop",
    "Microsoft.Todos",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsMaps",
    "Microsoft.YourPhone",
    "Microsoft.ZuneVideo",
    "Clipchamp.Clipchamp"
)

foreach ($pkg in $packagesToRemove) {
    Write-Host "    -> Checking package: $pkg" -ForegroundColor Gray
    $installed = & dism.exe /Image:"${winLetter}:\" /Get-ProvisionedAppxPackages | Select-String -Pattern $pkg
    if ($installed) {
        $fullPkgName = ($installed -split "PackageName : ")[1].Trim()
        Write-Host "    -> Removing provisioned package: $fullPkgName..." -ForegroundColor Yellow
        & dism.exe /Image:"${winLetter}:\" /Remove-ProvisionedAppxPackage /PackageName:"$fullPkgName" | Out-Null
    }
}

# 8. Apply Winhance and UI Tweaks to Offline Registry
Write-Host "[+] Applying offline registry tweaks (Winhance optimizations)..." -ForegroundColor Green
reg load HKLM\Offline_SOFTWARE "${winLetter}:\Windows\System32\config\SOFTWARE" 2>&1 | Out-Null
reg load HKLM\Offline_DEFAULT "${winLetter}:\Users\Default\NTUSER.DAT" 2>&1 | Out-Null

try {
    # A. Disable Telemetry in Software Hive
    $telemetryPath = "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $telemetryPath)) { New-Item -Path $telemetryPath -Force | Out-Null }
    Set-ItemProperty -Path $telemetryPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $telemetryPath -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $telemetryPath -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

    # B. Disable Windows Consumer Features / Cloud Content
    $cloudContent = "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cloudContent)) { New-Item -Path $cloudContent -Force | Out-Null }
    Set-ItemProperty -Path $cloudContent -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $cloudContent -Name "DisableSoftLanding" -Value 1 -Type DWord -Force

    # C. Enable Remote Desktop
    $tsKey = "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
    if (-not (Test-Path $tsKey)) { New-Item -Path $tsKey -Force | Out-Null }
    Set-ItemProperty -Path $tsKey -Name "fDenyTSConnections" -Value 0 -Type DWord -Force

    # D. Auto Admin Logon for Gamer
    $winlogonKey = "HKLM:\Offline_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (-not (Test-Path $winlogonKey)) { New-Item -Path $winlogonKey -Force | Out-Null }
    Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value "Gamer" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value "" -Force -ErrorAction SilentlyContinue

    # E. Default User Profile Tweaks: Classic Context Menu, Show Extensions, Show Hidden
    $advKey = "HKLM:\Offline_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
    Set-ItemProperty -Path $advKey -Name "HideFileExt" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $advKey -Name "Hidden" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $advKey -Name "LaunchTo" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $advKey -Name "HideIcons" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    $clsidKey = "HKLM:\Offline_DEFAULT\Software\Classes\CLSID\{86caaa31-5b10-4b0d-8860-e3430144d436}\InprocServer32"
    if (-not (Test-Path $clsidKey)) { New-Item -Path $clsidKey -Force | Out-Null }
    Set-ItemProperty -Path $clsidKey -Name "(default)" -Value "" -Force -ErrorAction SilentlyContinue

} finally {
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    reg unload HKLM\Offline_DEFAULT 2>&1 | Out-Null
    reg unload HKLM\Offline_SOFTWARE 2>&1 | Out-Null
}

# 9. Deploy Desktop Tools to Guest Desktop
Write-Host "[+] Deploying new desktop tools and HWID scripts to Guest Desktop..." -ForegroundColor Green
$desktopToolsSource = "C:\Users\server1\Desktop\localserver1\new_system"
$desktopTargets = @(
    "${winLetter}:\Users\Public\Desktop",
    "${winLetter}:\Users\Default\Desktop"
)
if (Test-Path "${winLetter}:\Users\Gamer") {
    $desktopTargets += "${winLetter}:\Users\Gamer\Desktop"
}
foreach ($targetDir in $desktopTargets) {
    New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $desktopToolsSource) {
        Copy-Item -Path "$desktopToolsSource\*" -Destination $targetDir -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path "C:\Users\server1\Desktop\Hyper-V\.example\Verify-HWID.ps1" -Destination "$targetDir\Verify-HWID.ps1" -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "C:\Users\server1\Desktop\Hyper-V\.example\Guest-HyperV-CleanID.ps1" -Destination "$targetDir\Guest-HyperV-CleanID.ps1" -Force -ErrorAction SilentlyContinue
    
    $hwidBat = "@echo off`r`ntitle Verify-HWID`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\Setup\Verify-HWID.ps1`"`r`npause`r`n"
    [System.IO.File]::WriteAllText("$targetDir\Verify-HWID.bat", $hwidBat, [System.Text.Encoding]::ASCII)
    
    $cleanBat = "@echo off`r`ntitle Guest-CleanID`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\Setup\Guest-HyperV-CleanID.ps1`"`r`npause`r`n"
    [System.IO.File]::WriteAllText("$targetDir\Guest-CleanID.bat", $cleanBat, [System.Text.Encoding]::ASCII)
}

# 10. Inject Unattended Setup XML
Write-Host "[+] Injecting unattend.xml..." -ForegroundColor Green
$unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <settings pass="specialize">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>0409:00000409;0419:00000419</InputLocale>
            <SystemLocale>ru-RU</SystemLocale>
            <UILanguage>ru-RU</UILanguage>
            <UserLocale>ru-RU</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>$VMName</ComputerName>
            <TimeZone>Russian Standard Time</TimeZone>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>0409:00000409;0419:00000419</InputLocale>
            <SystemLocale>ru-RU</SystemLocale>
            <UILanguage>ru-RU</UILanguage>
            <UserLocale>ru-RU</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOEMRegistrationScreens>true</HideOEMRegistrationScreens>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <AutoLogon>
                <Password>
                    <Value></Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>9999999</LogonCount>
                <Username>Gamer</Username>
            </AutoLogon>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Password>
                            <Value></Value>
                            <PlainText>true</PlainText>
                        </Password>
                        <Description>Gamer Virtual Machine User</Description>
                        <DisplayName>Gamer</DisplayName>
                        <Group>Administrators</Group>
                        <Name>Gamer</Name>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
        </component>
    </settings>
</unattend>
"@

$pantherDir = "${winLetter}:\Windows\Panther"
if (-not (Test-Path $pantherDir)) { New-Item -ItemType Directory -Path $pantherDir -Force | Out-Null }
[System.IO.File]::WriteAllText("$pantherDir\unattend.xml", $unattendXml, [System.Text.UTF8Encoding]::new($true))

$sysprepDir = "${winLetter}:\Windows\System32\Sysprep"
if (-not (Test-Path $sysprepDir)) { New-Item -ItemType Directory -Path $sysprepDir -Force | Out-Null }
[System.IO.File]::WriteAllText("$sysprepDir\unattend.xml", $unattendXml, [System.Text.UTF8Encoding]::new($true))

# SetupComplete.cmd
$setupScriptsDir = "${winLetter}:\Windows\Setup\Scripts"
if (-not (Test-Path $setupScriptsDir)) { New-Item -ItemType Directory -Path $setupScriptsDir -Force | Out-Null }
$setupCompleteCmd = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1 >> C:\Setup\setupcomplete.log 2>&1
"@
[System.IO.File]::WriteAllText("$setupScriptsDir\SetupComplete.cmd", $setupCompleteCmd, [System.Text.Encoding]::ASCII)

# 11. Inject Host NVIDIA Drivers
Write-Host "[+] Injecting GPU-PV NVIDIA Drivers..." -ForegroundColor Green
$destHostDriverStore = "${winLetter}:\Windows\System32\HostDriverStore\FileRepository"
New-Item -ItemType Directory -Path $destHostDriverStore -Force | Out-Null

Copy-Item -Path "$stagingDrivers\HostDriverStore\FileRepository\*" -Destination $destHostDriverStore -Recurse -Force
Copy-Item -Path "$stagingDrivers\System32\*" -Destination "${winLetter}:\Windows\System32" -Force
Copy-Item -Path "$stagingDrivers\SysWOW64\*" -Destination "${winLetter}:\Windows\SysWOW64" -Force

# 12. Copy Guest Setup Packages (VDD, NefCon, Sunshine, Script, HWID tools)
Write-Host "[+] Copying Guest Setup packages to ${winLetter}:\Setup..." -ForegroundColor Green
$guestSetupTarget = "${winLetter}:\Setup"
New-Item -ItemType Directory -Path $guestSetupTarget -Force | Out-Null
Copy-Item -Path "$stagingGuestSetup\*" -Destination $guestSetupTarget -Recurse -Force

Set-Content -Path "$guestSetupTarget\ip.txt" -Value $GuestIP -Encoding ASCII
Set-Content -Path "$guestSetupTarget\vmname.txt" -Value $VMName -Encoding ASCII

} finally {
    Write-Host "[+] Cleaning up and dismounting..." -ForegroundColor Cyan
    if (Test-Path "HKLM:\Offline_DEFAULT") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Offline_DEFAULT 2>&1 | Out-Null }
    if (Test-Path "HKLM:\Offline_SOFTWARE") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Offline_SOFTWARE 2>&1 | Out-Null }

    if ($efiLetter) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiLetter}:\" -ErrorAction SilentlyContinue
    }
    if ($isoMount) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

# Set master disk as Read-Only
try {
    [System.IO.File]::SetAttributes($VHDPath, [System.IO.FileAttributes]::ReadOnly)
} catch {}

Write-Host "=== Build Completed Successfully for $VMName ($VHDPath) ===" -ForegroundColor Green
