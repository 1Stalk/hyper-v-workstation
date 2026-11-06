<#
.SYNOPSIS
    Automated fast provisioning of Windows 11 Pro Gaming VM disk using DISM.
.DESCRIPTION
    Creates a dynamic VHDX, initializes GPT with UEFI/FAT32 and Windows/NTFS partitions,
    applies Windows 11 Pro (Index 3) directly from the ISO via DISM, configures UEFI boot,
    performs offline DISM debloat of consumer AppX packages (preserving Store and Xbox),
    applies Winhance privacy and UI tweaks (classic context menu, show extensions, disable telemetry),
    deploys AntiOS.exe utility to Desktop,
    injects unattended answer file (Gamer user, autologon, high performance),
    injects host NVIDIA GPU-PV drivers into HostDriverStore, System32, and SysWOW64,
    and stages Virtual Display Driver (720p/1080p 60Hz) and Sunshine with auto-run scripts.
#>

[CmdletBinding()]
param(
    [string]$VMName = "Gaming-VM1",
    [string]$VHDPath = "C:\Hyper-V\VMs\Gaming-VM1.vhdx",
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
Write-Host "[+] Mounting ISO: $IsoPath..." -ForegroundColor Cyan
$isoMount = Mount-DiskImage -ImagePath $IsoPath -PassThru
Start-Sleep -Seconds 2
$isoLetter = (Get-DiskImage -ImagePath $IsoPath | Get-Volume).DriveLetter
if (-not $isoLetter) {
    throw "Failed to get drive letter for mounted ISO $IsoPath"
}
$wimPath = "${isoLetter}:\sources\install.wim"
Write-Host "[*] ISO mounted at ${isoLetter}: (WIM: $wimPath)" -ForegroundColor Gray

try {
    Write-Host "[+] Applying Windows 11 Pro (Index $ImageIndex) to ${winLetter}:\ via DISM..." -ForegroundColor Green
    $dismArgs = @(
        "/Apply-Image",
        "/ImageFile:$wimPath",
        "/Index:$ImageIndex",
        "/ApplyDir:$($winLetter):\"
    )
    $process = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "DISM failed with exit code $($process.ExitCode)"
    }
    Write-Host "[+] Image applied successfully!" -ForegroundColor Green

    # 6. Configure UEFI Bootloader
    Write-Host "[+] Generating UEFI BCD boot records..." -ForegroundColor Green
    $bcdbootExe = "${winLetter}:\Windows\System32\bcdboot.exe"
    $bcdArgs = @(
        "$($winLetter):\Windows",
        "/s",
        "$($efiLetter):",
        "/f",
        "UEFI"
    )
    $process = Start-Process -FilePath $bcdbootExe -ArgumentList $bcdArgs -Wait -NoNewWindow -PassThru
    if ($process.ExitCode -ne 0) {
        throw "BCDBoot failed with exit code $($process.ExitCode)"
    }
    Write-Host "[+] UEFI Boot records configured." -ForegroundColor Green

    # 7. Debloat Windows 11: Offline removal of consumer AppX bloatware
    Write-Host "[+] Debloating offline image (removing consumer AppX bloatware)..." -ForegroundColor Green
    $bloatPatterns = @(
        "*BingSearch*", "*BingNews*", "*BingWeather*", "*Cortana*", "*549981C3F5F10*",
        "*MSTeams*", "*Teams*", "*SolitaireCollection*", "*FeedbackHub*", "*WindowsMaps*",
        "*GetHelp*", "*Getstarted*", "*Todos*", "*YourPhone*", "*Copilot*",
        "*Clipchamp*", "*DevHome*", "*MicrosoftFamily*", "*QuickAssist*", "*SkypeApp*",
        "*OfficeHub*", "*OutlookForWindows*", "*PowerAutomateDesktop*", "*People*",
        "*Microsoft3DViewer*", "*MixedReality.Portal*", "*ZuneMusic*", "*ZuneVideo*",
        "*OneNote*"
    )

    $provisionedPkgs = Get-AppxProvisionedPackage -Path "${winLetter}:\" -ErrorAction SilentlyContinue
    $removedCount = 0
    foreach ($pkg in $provisionedPkgs) {
        # Strictly preserve Windows Store, Xbox gaming services, and core UI runtimes
        if ($pkg.DisplayName -like "Microsoft.WindowsStore*" -or
            $pkg.DisplayName -like "Microsoft.StorePurchaseApp*" -or
            $pkg.DisplayName -like "Microsoft.Xbox*" -or
            $pkg.DisplayName -like "Microsoft.GamingApp*" -or
            $pkg.DisplayName -like "*AppInstaller*" -or
            $pkg.DisplayName -like "*VCLibs*" -or
            $pkg.DisplayName -like "*UI.Xaml*") {
            Write-Host "    [KEEP] $($pkg.DisplayName)" -ForegroundColor DarkGreen
            continue
        }

        $isBloat = $false
        foreach ($pattern in $bloatPatterns) {
            if ($pkg.DisplayName -like $pattern -or $pkg.PackageName -like $pattern) {
                $isBloat = $true
                break
            }
        }

        if ($isBloat) {
            Write-Host "    [-] Removing bloatware: $($pkg.DisplayName)..." -ForegroundColor Yellow
            Remove-AppxProvisionedPackage -Path "${winLetter}:\" -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
            $removedCount++
        }
    }
    Write-Host "[+] Bloatware removal complete. Removed $removedCount provisioned packages (Store & Xbox preserved)." -ForegroundColor Green

    # 8. Apply Winhance Privacy & UI Tweaks
    Write-Host "[+] Applying offline privacy and UI tweaks..." -ForegroundColor Green
    $offlineSoftwareHive = "${winLetter}:\Windows\System32\config\SOFTWARE"
    $offlineDefaultHive  = "${winLetter}:\Users\Default\NTUSER.DAT"

    reg load HKLM\Offline_SOFTWARE "$offlineSoftwareHive" 2>&1 | Out-Null
    reg load HKLM\Offline_DEFAULT  "$offlineDefaultHive" 2>&1 | Out-Null

    try {
        # A. Disable Telemetry & Diagnostics Policies
        $polPaths = @(
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\DataCollection",
            "HKLM:\Offline_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection",
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo",
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\System",
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\Windows Search",
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting",
            "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\AppCompat"
        )
        foreach ($p in $polPaths) {
            if (-not (Test-Path $p)) { New-Item -Path $p -Force -ErrorAction SilentlyContinue | Out-Null }
        }

        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Offline_SOFTWARE\Policies\Microsoft\Windows\AppCompat" -Name "AITEnable" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        # B. OOBE Bypass Flags
        $oobeKey = "HKLM:\Offline_SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"
        if (-not (Test-Path $oobeKey)) { New-Item -Path $oobeKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $oobeKey -Name "BypassNRO" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $oobeKey -Name "SkipUserOOBE" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $oobeKey -Name "SkipMachineOOBE" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $oobeKey -Name "HideLooseKeyboardSetup" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

        # C. RunOnce Guest Tools
        $runOnceKey = "HKLM:\Offline_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
        if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $runOnceKey -Name "InstallGuestTools" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1" -Force -ErrorAction SilentlyContinue

        # D. Auto Admin Logon for Gamer
        $winlogonKey = "HKLM:\Offline_SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
        if (-not (Test-Path $winlogonKey)) { New-Item -Path $winlogonKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $winlogonKey -Name "AutoAdminLogon" -Value "1" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $winlogonKey -Name "DefaultUserName" -Value "Gamer" -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $winlogonKey -Name "DefaultPassword" -Value "" -Force -ErrorAction SilentlyContinue

        # E. Default User Profile Tweaks: Classic Context Menu, Show File Extensions, Show Hidden Files
        $advKey = "HKLM:\Offline_DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $advKey -Name "HideFileExt" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $advKey -Name "Hidden" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $advKey -Name "LaunchTo" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $advKey -Name "HideIcons" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

        # Classic Context Menu for Windows 11
        $clsidKey = "HKLM:\Offline_DEFAULT\Software\Classes\CLSID\{86caaa31-5b10-4b0d-8860-e3430144d436}\InprocServer32"
        if (-not (Test-Path $clsidKey)) { New-Item -Path $clsidKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $clsidKey -Name "(default)" -Value "" -Force -ErrorAction SilentlyContinue

    } finally {
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        reg unload HKLM\Offline_DEFAULT 2>&1 | Out-Null
        reg unload HKLM\Offline_SOFTWARE 2>&1 | Out-Null
    }

    # 9. Deploy AntiOS utility to Guest Desktop
    Write-Host "[+] Deploying AntiOS.exe utility to Guest Desktop..." -ForegroundColor Green
    $antiOsSource = "C:\Users\server1\Desktop\localserver1\new_system\AntiOS.exe"
    if (-not (Test-Path $antiOsSource)) {
        $antiOsSource = Join-Path $stagingGuestSetup "AntiOS.exe"
    }

    if (Test-Path $antiOsSource) {
        $desktopTargets = @(
            "${winLetter}:\Users\Public\Desktop",
            "${winLetter}:\Users\Default\Desktop"
        )
        if (Test-Path "${winLetter}:\Users\Gamer") {
            $desktopTargets += "${winLetter}:\Users\Gamer\Desktop"
        }
        foreach ($targetDir in $desktopTargets) {
            New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path $antiOsSource -Destination "$targetDir\AntiOS.exe" -Force
            Write-Host "    -> Placed AntiOS.exe at $targetDir\AntiOS.exe" -ForegroundColor Gray
        }
    } else {
        Write-Host "    [!] Warning: AntiOS.exe not found at $antiOsSource" -ForegroundColor Yellow
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
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v SkipUserOOBE /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v SkipMachineOOBE /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
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
            <AutoLogon>
                <Password>
                    <Value></Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>999</LogonCount>
                <Username>Gamer</Username>
            </AutoLogon>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
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
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1</CommandLine>
                    <Description>Initialize GPU-PV Display and Sunshine</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
"@
    $pantherDir = "${winLetter}:\Windows\Panther"
    $sysprepDir = "${winLetter}:\Windows\System32\Sysprep"
    New-Item -ItemType Directory -Path $pantherDir -Force | Out-Null
    New-Item -ItemType Directory -Path $sysprepDir -Force | Out-Null
    Set-Content -Path "$pantherDir\unattend.xml" -Value $unattendXml -Encoding UTF8
    Set-Content -Path "$sysprepDir\unattend.xml" -Value $unattendXml -Encoding UTF8

    # Also configure SetupComplete.cmd as fallback execution
    $setupScriptsDir = "${winLetter}:\Windows\Setup\Scripts"
    New-Item -ItemType Directory -Path $setupScriptsDir -Force | Out-Null
    $setupCompleteCmd = @"
@echo off
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1 >> C:\Setup\setupcomplete.log 2>&1
"@
    Set-Content -Path "$setupScriptsDir\SetupComplete.cmd" -Value $setupCompleteCmd -Encoding ASCII

    # 11. Inject Host NVIDIA Drivers
    Write-Host "[+] Injecting GPU-PV NVIDIA Drivers..." -ForegroundColor Green
    $destHostDriverStore = "${winLetter}:\Windows\System32\HostDriverStore\FileRepository"
    New-Item -ItemType Directory -Path $destHostDriverStore -Force | Out-Null

    Write-Host "    -> Copying HostDriverStore\FileRepository..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\HostDriverStore\FileRepository\*" -Destination $destHostDriverStore -Recurse -Force

    Write-Host "    -> Copying System32 NVIDIA libraries..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\System32\*" -Destination "${winLetter}:\Windows\System32" -Force

    Write-Host "    -> Copying SysWOW64 NVIDIA libraries..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\SysWOW64\*" -Destination "${winLetter}:\Windows\SysWOW64" -Force

    # 12. Copy Guest Setup Packages (VDD, NefCon, Sunshine, Script, AntiOS)
    Write-Host "[+] Copying Guest Setup packages to ${winLetter}:\Setup..." -ForegroundColor Green
    $guestSetupTarget = "${winLetter}:\Setup"
    New-Item -ItemType Directory -Path $guestSetupTarget -Force | Out-Null
    Copy-Item -Path "$stagingGuestSetup\*" -Destination $guestSetupTarget -Recurse -Force

    # Record Target IP
    Set-Content -Path "$guestSetupTarget\ip.txt" -Value $GuestIP -Encoding ASCII

} finally {
    # Clean up mounts and unload hives if any remain
    Write-Host "[+] Cleaning up and dismounting..." -ForegroundColor Cyan

    if (Test-Path "HKLM:\Offline_DEFAULT") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Offline_DEFAULT 2>&1 | Out-Null }
    if (Test-Path "HKLM:\Offline_SOFTWARE") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Offline_SOFTWARE 2>&1 | Out-Null }

    # Remove EFI drive letter
    if ($efiLetter) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $efiPart.PartitionNumber -AccessPath "${efiLetter}:\" -ErrorAction SilentlyContinue
    }
    # Dismount ISO
    if ($isoMount) {
        Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null
    }
    # Dismount VHD
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

Write-Host "=== Build Completed Successfully for $VMName ($VHDPath) ===" -ForegroundColor Green
