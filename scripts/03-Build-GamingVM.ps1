<#
.SYNOPSIS
    Automated fast provisioning of Windows 11 Pro Gaming VM disk using DISM.
.DESCRIPTION
    Creates a dynamic VHDX, initializes GPT with UEFI/FAT32 and Windows/NTFS partitions,
    applies Windows 11 Pro (Index 3) directly from the ISO via DISM, configures UEFI boot,
    injects unattended answer file (Gamer user, autologon, high performance),
    injects host NVIDIA GPU-PV drivers into HostDriverStore, System32, and SysWOW64,
    and stages Virtual Display Driver (720p 60Hz) and Sunshine with auto-run scripts.
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
    # Make sure it's dismounted first
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

    # 7. Inject Unattended Setup XML
    Write-Host "[+] Injecting unattend.xml..." -ForegroundColor Green
    $unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>ru-RU</UILanguage>
            </SetupUILanguage>
            <InputLocale>0409:00000409;0419:00000419</InputLocale>
            <SystemLocale>ru-RU</SystemLocale>
            <UILanguage>ru-RU</UILanguage>
            <UserLocale>ru-RU</UserLocale>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>$VMName</ComputerName>
            <TimeZone>Russian Standard Time</TimeZone>
        </component>
    </settings>
    <settings pass="oobeSystem">
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

    # 8. Inject Host NVIDIA Drivers
    Write-Host "[+] Injecting GPU-PV NVIDIA Drivers..." -ForegroundColor Green
    $destHostDriverStore = "${winLetter}:\Windows\System32\HostDriverStore\FileRepository"
    New-Item -ItemType Directory -Path $destHostDriverStore -Force | Out-Null

    Write-Host "    -> Copying HostDriverStore\FileRepository..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\HostDriverStore\FileRepository\*" -Destination $destHostDriverStore -Recurse -Force

    Write-Host "    -> Copying System32 NVIDIA libraries..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\System32\*" -Destination "${winLetter}:\Windows\System32" -Force

    Write-Host "    -> Copying SysWOW64 NVIDIA libraries..." -ForegroundColor Gray
    Copy-Item -Path "$stagingDrivers\SysWOW64\*" -Destination "${winLetter}:\Windows\SysWOW64" -Force

    # 9. Copy Guest Setup Packages (VDD, NefCon, Sunshine, Script)
    Write-Host "[+] Copying Guest Setup packages to ${winLetter}:\Setup..." -ForegroundColor Green
    $guestSetupTarget = "${winLetter}:\Setup"
    New-Item -ItemType Directory -Path $guestSetupTarget -Force | Out-Null
    Copy-Item -Path "$stagingGuestSetup\*" -Destination $guestSetupTarget -Recurse -Force

    # Record Target IP
    Set-Content -Path "$guestSetupTarget\ip.txt" -Value $GuestIP -Encoding ASCII

} finally {
    # 10. Clean up mounts
    Write-Host "[+] Cleaning up and dismounting..." -ForegroundColor Cyan

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
