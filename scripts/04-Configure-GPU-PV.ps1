<#
.SYNOPSIS
    Provisions and configures Gaming-VM1 with GPU-PV and full hardware randomization.
.DESCRIPTION
    Creates differencing disk from Gaming-Base.vhdx, sets unique offline identity (IP 192.168.100.11,
    MachineGuid, ComputerName, SQM MachineId), resets SCSI Disk Identifier, randomizes SMBIOS
    (BIOS, BaseBoard, Chassis, UUID) via Hyper-V WMI v2, assigns realistic vendor MAC address,
    and attaches 1GB GPU partition slice. AntiOS is completely removed and superseded.
#>

[CmdletBinding()]
param(
    [string]$MasterVHDPath = "C:\Hyper-V\VMs\Gaming-Base.vhdx",
    [string]$VMName = "Gaming-VM1",
    [string]$VHDPath = "C:\Hyper-V\VMs\Gaming-VM1.vhdx",
    [string]$GuestIP = "192.168.100.11",
    [string]$SwitchName = "VM-Gaming-Switch",
    [int]$CPUCount = 4,
    [int64]$MemoryBytes = 8GB,
    [uint64]$VRAMUnits = 250000000,
    [string]$DesktopToolsSource = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($DesktopToolsSource)) {
    $defaultSoftwareDir = Join-Path $RepoRoot "software\desktop"
    if (Test-Path $defaultSoftwareDir) {
        $DesktopToolsSource = $defaultSoftwareDir
    } else {
        $DesktopToolsSource = Join-Path $RepoRoot "staging\guest_setup\desktop_tools"
    }
}

# Auto-elevate or require Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "04-Configure-GPU-PV.ps1 must be run in an elevated PowerShell session (as Administrator)."
}

Write-Host "=== Configuring Gaming VM: $VMName ($GuestIP) ===" -ForegroundColor Cyan

# 1. Resolve Master VHDX
if (-not (Test-Path $MasterVHDPath)) {
    throw "Master VHDX not found at: $MasterVHDPath"
}
Write-Host "[*] Master VHDX resolved: $MasterVHDPath" -ForegroundColor Gray

# Ensure master VHDX is marked Read-Only
try {
    [System.IO.File]::SetAttributes($MasterVHDPath, [System.IO.FileAttributes]::ReadOnly)
} catch {
    Write-Host "    [!] Notice: Master VHDX read-only attribute: $($_.Exception.Message)" -ForegroundColor DarkGray
}

# 2. Clean existing VM if present
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "[!] VM '$VMName' already exists. Stopping and removing..." -ForegroundColor Yellow
    if ($existingVM.State -ne 'Off') {
        Stop-VM -Name $VMName -TurnOff -Force
        Start-Sleep -Seconds 2
    }
    Remove-VM -Name $VMName -Force
}

if (Test-Path $VHDPath) {
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 1
    Remove-Item -Path $VHDPath -Force
}

# 3. Create Differencing Disk
Write-Host "[+] Creating Differencing VHDX linked to Master: $VHDPath..." -ForegroundColor Green
New-VHD -ParentPath $MasterVHDPath -Path $VHDPath -Differencing | Out-Null

# 4. Mount Differencing Disk and configure unique identity
Write-Host "[+] Customizing unique guest identity for $VMName (IP: $GuestIP)..." -ForegroundColor Green
$mountedVhd = Mount-VHD -Path $VHDPath -Passthru
$diskNumber = $mountedVhd.DiskNumber
Start-Sleep -Seconds 2

$assignedTempLetter = $null
try {
    $winPart = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -like "*Basic data*" -or $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' } | Sort-Object Size -Descending | Select-Object -First 1
    if (-not $winPart) {
        throw "Failed to locate Windows partition on disk $diskNumber"
    }

    $winLetter = $winPart.DriveLetter
    if (-not $winLetter) {
        $vol = Get-Volume -Partition $winPart -ErrorAction SilentlyContinue
        if ($vol -and $vol.DriveLetter) {
            $winLetter = [string]$vol.DriveLetter
        } else {
            $usedLetters = (Get-Volume | Where-Object { $_.DriveLetter }).DriveLetter
            $freeLetter = 71..89 | ForEach-Object { [char]$_ } | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
            if ($freeLetter) {
                Set-Partition -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $freeLetter -ErrorAction SilentlyContinue | Out-Null
                $winLetter = $freeLetter
                $assignedTempLetter = $freeLetter
            } else {
                $winLetter = ($winPart | Add-PartitionAccessPath -AssignDriveLetter -PassThru -ErrorAction SilentlyContinue).DriveLetter
            }
        }
    }

    if (-not $winLetter) {
        throw "Failed to obtain drive letter for partition on disk $diskNumber"
    }
    Write-Host "    -> Mounted Windows partition at ${winLetter}:" -ForegroundColor Gray

    # Update ip.txt and vmname.txt
    $setupDir = "${winLetter}:\Setup"
    if (-not (Test-Path $setupDir)) {
        New-Item -ItemType Directory -Path $setupDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-Content -Path "$setupDir\ip.txt" -Value $GuestIP -Encoding ASCII
    Set-Content -Path "$setupDir\vmname.txt" -Value $VMName -Encoding ASCII
    Write-Host "    -> Configured target IP ($GuestIP) and target VM name ($VMName)" -ForegroundColor Gray

    # Ensure AntiOS is purged
    Get-ChildItem -Path "${winLetter}:\" -Filter "*AntiOS*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

    # Ensure desktop tools are present on Public Desktop
    $publicDesktop = "${winLetter}:\Users\Public\Desktop"
    New-Item -ItemType Directory -Path $publicDesktop -Force -ErrorAction SilentlyContinue | Out-Null

    # Clean any existing scripts or leftovers from Public Desktop
    Remove-Item -Path "$publicDesktop\*.bat", "$publicDesktop\*.ps1", "$publicDesktop\*AntiOS*" -Force -ErrorAction SilentlyContinue

    # Copy all software installers to Public\Desktop
    if ($DesktopToolsSource -and (Test-Path $DesktopToolsSource)) {
        Get-ChildItem -Path $DesktopToolsSource | Where-Object { $_.Name -notlike ".*" -and $_.Name -notlike "README*" -and $_.Extension -ne ".md" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $publicDesktop -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Clean up any copies from Default\Desktop and Gamer\Desktop to prevent duplicate icons in Windows Explorer
    $duplicateTargets = @("${winLetter}:\Users\Default\Desktop", "${winLetter}:\Users\Gamer\Desktop")
    foreach ($dupDir in $duplicateTargets) {
        if (Test-Path $dupDir) {
            Remove-Item -Path "$dupDir\*.bat", "$dupDir\*.ps1", "$dupDir\*AntiOS*" -Force -ErrorAction SilentlyContinue
        }
    }

    # Stage HWID scripts to C:\Setup (NOT to Desktop!)
    $setupDir = "${winLetter}:\Setup"
    New-Item -ItemType Directory -Path $setupDir -Force -ErrorAction SilentlyContinue | Out-Null
    $verifySrc = Join-Path $PSScriptRoot "guest\Verify-HWID.ps1"
    if (Test-Path $verifySrc) {
        Copy-Item -Path $verifySrc -Destination "$setupDir\Verify-HWID.ps1" -Force -ErrorAction SilentlyContinue
    }
    $cleanIdSrc = Join-Path $PSScriptRoot "guest\Guest-HyperV-CleanID.ps1"
    if (Test-Path $cleanIdSrc) {
        Copy-Item -Path $cleanIdSrc -Destination "$setupDir\Guest-HyperV-CleanID.ps1" -Force -ErrorAction SilentlyContinue
    }

    # Unique MachineGuid and SQM MachineId in offline SOFTWARE hive
    $softwareHive = "${winLetter}:\Windows\System32\config\SOFTWARE"
    if (Test-Path $softwareHive) {
        reg load HKLM\VM1_SOFTWARE "$softwareHive" 2>&1 | Out-Null
        try {
            $newGuid = [guid]::NewGuid().ToString()
            $newSqmGuid = "{$([guid]::NewGuid().ToString())}"
            $cryptoKey = "HKLM:\VM1_SOFTWARE\Microsoft\Cryptography"
            if (-not (Test-Path $cryptoKey)) { New-Item -Path $cryptoKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $cryptoKey -Name "MachineGuid" -Value $newGuid -Force
            $sqmKey = "HKLM:\VM1_SOFTWARE\Microsoft\SQMClient"
            if (-not (Test-Path $sqmKey)) { New-Item -Path $sqmKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $sqmKey -Name "MachineId" -Value $newSqmGuid -Force
            Write-Host "    -> Generated unique MachineGuid: $newGuid" -ForegroundColor Gray

            # Ensure RunOnce for Guest Tools initialization on boot
            $runOnceKey = "HKLM:\VM1_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $runOnceKey -Name "InstallGuestTools" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1" -Force -ErrorAction SilentlyContinue
        } finally {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            reg unload HKLM\VM1_SOFTWARE 2>&1 | Out-Null
        }
    }

    # Unique ComputerName and Hostname in offline SYSTEM hive
    $systemHive = "${winLetter}:\Windows\System32\config\SYSTEM"
    if (Test-Path $systemHive) {
        reg load HKLM\VM1_SYSTEM "$systemHive" 2>&1 | Out-Null
        try {
            $compKey = "HKLM:\VM1_SYSTEM\ControlSet001\Control\ComputerName\ComputerName"
            if (-not (Test-Path $compKey)) { New-Item -Path $compKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $compKey -Name "ComputerName" -Value $VMName -Force -ErrorAction SilentlyContinue

            $activeKey = "HKLM:\VM1_SYSTEM\ControlSet001\Control\ComputerName\ActiveComputerName"
            if (-not (Test-Path $activeKey)) { New-Item -Path $activeKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $activeKey -Name "ComputerName" -Value $VMName -Force -ErrorAction SilentlyContinue

            $tcpKey = "HKLM:\VM1_SYSTEM\ControlSet001\Services\Tcpip\Parameters"
            if (-not (Test-Path $tcpKey)) { New-Item -Path $tcpKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $tcpKey -Name "Hostname" -Value $VMName -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tcpKey -Name "NV Hostname" -Value $VMName -Force -ErrorAction SilentlyContinue
            Write-Host "    -> Configured unique ComputerName and Hostname: $VMName" -ForegroundColor Gray
        } finally {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            reg unload HKLM\VM1_SYSTEM 2>&1 | Out-Null
        }
    }

} finally {
    if (Test-Path "HKLM:\VM1_SOFTWARE") {
        [GC]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload HKLM\VM1_SOFTWARE 2>&1 | Out-Null
    }
    if (Test-Path "HKLM:\VM1_SYSTEM") {
        [GC]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload HKLM\VM1_SYSTEM 2>&1 | Out-Null
    }
    if ($assignedTempLetter -and $winPart) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${assignedTempLetter}:\" -ErrorAction SilentlyContinue | Out-Null
    }
    Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

# 5. Reset SCSI Disk Identifier on VHDX
Write-Host "[+] Resetting SCSI Disk Identifier for $VHDPath..." -ForegroundColor Green
try {
    Set-VHD -Path $VHDPath -ResetDiskIdentifier -Force -Confirm:$false
    Write-Host "    -> Reset SCSI Disk Identifier succeeded." -ForegroundColor Gray
} catch {
    Write-Warning "    [!] Notice resetting disk identifier: $_"
}

# 6. Create and Configure Hyper-V VM
Write-Host "[+] Registering VM '$VMName'..." -ForegroundColor Green
New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryBytes -VHDPath $VHDPath -SwitchName $SwitchName | Out-Null
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
Set-VMProcessor -VMName $VMName -Count $CPUCount
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
Set-VM -VMName $VMName `
    -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 1GB `
    -HighMemoryMappedIoSpace 32GB `
    -AutomaticStopAction TurnOff

# Attach secondary network adapter to Default Switch for high-speed Internet NAT
$defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if ($defaultSwitch) {
    Write-Host "[+] Attaching secondary network adapter connected to 'Default Switch' for Internet..." -ForegroundColor Green
    Add-VMNetworkAdapter -VMName $VMName -SwitchName "Default Switch" -Name "Internet" -ErrorAction SilentlyContinue | Out-Null
}
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue | Out-Null

# 7. Hardware Randomization: SMBIOS via Hyper-V WMI v2
Write-Host "[+] Applying SMBIOS hardware randomization via WMI v2..." -ForegroundColor Green
try {
    function Get-RandomAlphaNum([int]$length) {
        $chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
        -join ($chars | Get-Random -Count $length)
    }
    
    $newBiosSerial    = Get-RandomAlphaNum 12
    $newBoardSerial   = Get-RandomAlphaNum 14
    $newChassisSerial = Get-RandomAlphaNum 10
    $newAssetTag      = "AT-" + (Get-RandomAlphaNum 8)
    $newBiosGuid      = [guid]::NewGuid().ToString().ToUpper()

    $wmiNamespace = "root\virtualization\v2"
    $cs = Get-WmiObject -Namespace $wmiNamespace -Class Msvm_ComputerSystem -Filter "ElementName = '$VMName'"
    if ($cs) {
        $vssd = Get-WmiObject -Namespace $wmiNamespace -Class Msvm_VirtualSystemSettingData | Where-Object { $_.ElementName -eq $VMName -and $_.InstanceID -like "*$($cs.Name)*" }
        if ($vssd) {
            $vssd['BIOSSerialNumber']      = $newBiosSerial
            $vssd['BaseBoardSerialNumber'] = $newBoardSerial
            $vssd['ChassisSerialNumber']   = $newChassisSerial
            $vssd['ChassisAssetTag']       = $newAssetTag
            $vssd['BIOSGUID']              = "{$newBiosGuid}"

            $vmms = Get-WmiObject -Namespace $wmiNamespace -Class Msvm_VirtualSystemManagementService
            $methodParams = $vmms.GetMethodParameters("ModifySystemSettings")
            $methodParams["SystemSettings"] = $vssd.GetText([System.Management.TextFormat]::CimDtd20)
            $res = $vmms.InvokeMethod("ModifySystemSettings", $methodParams, $null)
            if ($res.ReturnValue -eq 0 -or $res.ReturnValue -eq 4096) {
                Write-Host "    -> SMBIOS Serial: $newBiosSerial, Board: $newBoardSerial, UUID: {$newBiosGuid}" -ForegroundColor Gray
            } else {
                Write-Warning "    [!] SMBIOS WMI returned: $($res.ReturnValue)"
            }
        }
    }
} catch {
    Write-Warning "    [!] SMBIOS randomization warning: $_"
}

# 8. Assign Randomized Vendor MAC Address (Intel / Realtek / Dell)
Write-Host "[+] Generating randomized vendor MAC address for $VMName..." -ForegroundColor Green
$vendorOUIList = @("001B21", "00215C", "001E67", "00E04C", "04D9F5", "2C4D54", "1866DA", "B82A72")
$chosenOUI = $vendorOUIList | Get-Random
$nicHex = 1..3 | ForEach-Object { "{0:X2}" -f (Get-Random -Min 0 -Max 256) }
$randomMac = "$chosenOUI$($nicHex -join '')"
Write-Host "    -> Vendor MAC assigned: $randomMac" -ForegroundColor Gray
$gamingNic = Get-VMNetworkAdapter -VMName $VMName | Where-Object { $_.Name -ne "Internet" } | Select-Object -First 1
if ($gamingNic) {
    Set-VMNetworkAdapter -VMNetworkAdapter $gamingNic -StaticMacAddress $randomMac -MacAddressSpoofing On
    Write-Host "    -> Vendor MAC assigned to Gaming Adapter: $randomMac" -ForegroundColor Gray
}

# 9. Attach GPU Partition Adapter
Write-Host "[+] Allocating GPU-PV Partition ($VRAMUnits units VRAM)..." -ForegroundColor Green
Add-VMGpuPartitionAdapter -VMName $VMName
Set-VMGpuPartitionAdapter -VMName $VMName `
    -MinPartitionVRAM 1 `
    -MaxPartitionVRAM $VRAMUnits `
    -OptimalPartitionVRAM $VRAMUnits `
    -MinPartitionCompute 1 `
    -MaxPartitionCompute $VRAMUnits `
    -OptimalPartitionCompute $VRAMUnits `
    -MinPartitionDecode 1 `
    -MaxPartitionDecode $VRAMUnits `
    -OptimalPartitionDecode $VRAMUnits `
    -MinPartitionEncode 1 `
    -MaxPartitionEncode 18446744073709551615 `
    -OptimalPartitionEncode 18446744073709551615

Write-Host "=== Successfully provisioned $VMName! ===" -ForegroundColor Green
