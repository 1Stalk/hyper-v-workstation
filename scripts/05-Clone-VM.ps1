<#
.SYNOPSIS
    Instantly provisions an additional Gaming VM using Differencing VHDX and GPU-PV with full hardware randomization.
.DESCRIPTION
    Scales the environment to run multiple virtual machines sharing host GPU resources.
    Uses master parent disk (differencing disk technique), provisions the new VM in ~20 seconds,
    assigns unique static IP, unique MachineGuid, unique ComputerName, randomized SMBIOS serials,
    randomized SCSI Disk Identifier, randomized vendor MAC address (Intel/Realtek/Dell),
    ensures new desktop tools are present on Desktop, and attaches a 1GB GPU partition adapter.
    AntiOS is completely removed and superseded.
#>

[CmdletBinding()]
param(
    [string]$MasterVHDPath = "C:\Hyper-V\VMs\Gaming-Base.vhdx",
    [string]$NewVMName = "Gaming-VM2",
    [string]$NewVHDPath = "C:\Hyper-V\VMs\Gaming-VM2.vhdx",
    [string]$NewGuestIP = "192.168.100.12",
    [string]$SwitchName = "VM-Gaming-Switch",
    [int]$CPUCount = 4,
    [int64]$MemoryBytes = 8GB,
    # 250,000,000 = 1GB (up to 4 VMs). For 5 VMs, use 200,000,000 (~800MB each)
    [uint64]$VRAMUnits = 250000000
)

$ErrorActionPreference = "Stop"

# Auto-elevate or require Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "05-Clone-VM.ps1 must be run in an elevated PowerShell session (as Administrator)."
}

Write-Host "=== Cloning Gaming VM: $NewVMName from Master ===" -ForegroundColor Cyan

# 1. Resolve Master VHDX
if (-not (Test-Path $MasterVHDPath)) {
    if (Test-Path "C:\Hyper-V\VMs\Gaming-Base.vhdx") {
        $MasterVHDPath = "C:\Hyper-V\VMs\Gaming-Base.vhdx"
    } elseif (Test-Path "C:\Hyper-V\VMs\Gaming-VM1.vhdx") {
        $MasterVHDPath = "C:\Hyper-V\VMs\Gaming-VM1.vhdx"
    } else {
        throw "Master VHDX not found at: $MasterVHDPath"
    }
}
Write-Host "[*] Master VHDX resolved: $MasterVHDPath" -ForegroundColor Gray

# Stop master VM if currently running to ensure clean differencing disk state
$masterVM = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.HardDrives.Path -contains $MasterVHDPath } | Select-Object -First 1
if ($masterVM -and $masterVM.State -ne 'Off') {
    Write-Host "[!] Master VM '$($masterVM.Name)' is currently running. Stopping it cleanly before cloning..." -ForegroundColor Yellow
    Stop-VM -Name $masterVM.Name -TurnOff -Force
    Start-Sleep -Seconds 3
}

# Ensure master VHDX is marked Read-Only to prevent accidental write lock or corruption
try {
    [System.IO.File]::SetAttributes($MasterVHDPath, [System.IO.FileAttributes]::ReadOnly)
} catch {
    Write-Host "    [!] Notice: Master VHDX read-only attribute note: $($_.Exception.Message)" -ForegroundColor DarkGray
}

# 2. Clean existing VM if present
$existingVM = Get-VM -Name $NewVMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "[!] VM '$NewVMName' already exists. Stopping and removing..." -ForegroundColor Yellow
    if ($existingVM.State -ne 'Off') {
        Stop-VM -Name $NewVMName -TurnOff -Force
        Start-Sleep -Seconds 2
    }
    Remove-VM -Name $NewVMName -Force
}

if (Test-Path $NewVHDPath) {
    Dismount-VHD -Path $NewVHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 1
    Remove-Item -Path $NewVHDPath -Force
}

# 3. Create Differencing Disk
Write-Host "[+] Creating Differencing VHDX linked to Master: $NewVHDPath..." -ForegroundColor Green
New-VHD -ParentPath $MasterVHDPath -Path $NewVHDPath -Differencing | Out-Null

# 4. Mount Differencing Disk and configure unique identity
Write-Host "[+] Customizing unique guest identity for $NewVMName (IP: $NewGuestIP)..." -ForegroundColor Green
$mountedVhd = Mount-VHD -Path $NewVHDPath -Passthru
$diskNumber = $mountedVhd.DiskNumber
Start-Sleep -Seconds 2

$assignedTempLetter = $null
try {
    # Find Windows partition
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
    Set-Content -Path "$setupDir\ip.txt" -Value $NewGuestIP -Encoding ASCII
    Set-Content -Path "$setupDir\vmname.txt" -Value $NewVMName -Encoding ASCII
    Write-Host "    -> Configured target IP ($NewGuestIP) and target VM name ($NewVMName)" -ForegroundColor Gray

    # Ensure AntiOS is purged
    Get-ChildItem -Path "${winLetter}:\" -Filter "*AntiOS*" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

    # Ensure desktop tools are present strictly on Public Desktop (Strict 4 installers, no duplicates)
    $desktopToolsSource = "C:\Users\server1\Desktop\localserver1\new_system"
    $publicDesktop = "${winLetter}:\Users\Public\Desktop"
    New-Item -ItemType Directory -Path $publicDesktop -Force -ErrorAction SilentlyContinue | Out-Null

    # Clean any existing scripts or leftovers from Public Desktop
    Remove-Item -Path "$publicDesktop\*.bat", "$publicDesktop\*.ps1", "$publicDesktop\*AntiOS*" -Force -ErrorAction SilentlyContinue

    # Copy exactly the 4 required installers to Public\Desktop only
    if (Test-Path $desktopToolsSource) {
        $allowedPatterns = @("ChromeSetup*", "RealVNC*", "Winhance*", "winrar*")
        foreach ($pattern in $allowedPatterns) {
            Get-ChildItem -Path $desktopToolsSource -Filter $pattern | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $publicDesktop -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Clean up any copies from Default\Desktop and Gamer\Desktop to prevent duplicate icons in Windows Explorer
    $duplicateTargets = @("${winLetter}:\Users\Default\Desktop", "${winLetter}:\Users\Gamer\Desktop")
    foreach ($dupDir in $duplicateTargets) {
        if (Test-Path $dupDir) {
            Remove-Item -Path "$dupDir\ChromeSetup*" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$dupDir\RealVNC*" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$dupDir\Winhance*" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$dupDir\winrar*" -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$dupDir\*.bat", "$dupDir\*.ps1", "$dupDir\*AntiOS*" -Force -ErrorAction SilentlyContinue
        }
    }

    # Stage HWID scripts to C:\Setup (NOT to Desktop!)
    $setupDir = "${winLetter}:\Setup"
    New-Item -ItemType Directory -Path $setupDir -Force -ErrorAction SilentlyContinue | Out-Null
    Copy-Item -Path "C:\Users\server1\Desktop\Hyper-V\.example\Verify-HWID.ps1" -Destination "$setupDir\Verify-HWID.ps1" -Force -ErrorAction SilentlyContinue
    Copy-Item -Path "C:\Users\server1\Desktop\Hyper-V\.example\Guest-HyperV-CleanID.ps1" -Destination "$setupDir\Guest-HyperV-CleanID.ps1" -Force -ErrorAction SilentlyContinue

    # Unique MachineGuid and SQM MachineId in offline SOFTWARE hive
    $softwareHive = "${winLetter}:\Windows\System32\config\SOFTWARE"
    if (Test-Path $softwareHive) {
        reg load HKLM\Clone_SOFTWARE "$softwareHive" 2>&1 | Out-Null
        try {
            $newGuid = [guid]::NewGuid().ToString()
            $newSqmGuid = "{$([guid]::NewGuid().ToString())}"
            $cryptoKey = "HKLM:\Clone_SOFTWARE\Microsoft\Cryptography"
            if (-not (Test-Path $cryptoKey)) { New-Item -Path $cryptoKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $cryptoKey -Name "MachineGuid" -Value $newGuid -Force
            $sqmKey = "HKLM:\Clone_SOFTWARE\Microsoft\SQMClient"
            if (-not (Test-Path $sqmKey)) { New-Item -Path $sqmKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $sqmKey -Name "MachineId" -Value $newSqmGuid -Force
            Write-Host "    -> Generated unique MachineGuid: $newGuid" -ForegroundColor Gray

            # Re-register RunOnce for Guest Tools initialization on clone boot
            $runOnceKey = "HKLM:\Clone_SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            if (-not (Test-Path $runOnceKey)) { New-Item -Path $runOnceKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $runOnceKey -Name "InstallGuestTools" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\install_guest_tools.ps1" -Force -ErrorAction SilentlyContinue
            Write-Host "    -> Re-registered RunOnce guest initialization" -ForegroundColor Gray
        } finally {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            reg unload HKLM\Clone_SOFTWARE 2>&1 | Out-Null
        }
    }

    # Unique ComputerName and Hostname in offline SYSTEM hive
    $systemHive = "${winLetter}:\Windows\System32\config\SYSTEM"
    if (Test-Path $systemHive) {
        reg load HKLM\Clone_SYSTEM "$systemHive" 2>&1 | Out-Null
        try {
            $compKey = "HKLM:\Clone_SYSTEM\ControlSet001\Control\ComputerName\ComputerName"
            if (-not (Test-Path $compKey)) { New-Item -Path $compKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $compKey -Name "ComputerName" -Value $NewVMName -Force -ErrorAction SilentlyContinue

            $activeKey = "HKLM:\Clone_SYSTEM\ControlSet001\Control\ComputerName\ActiveComputerName"
            if (-not (Test-Path $activeKey)) { New-Item -Path $activeKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $activeKey -Name "ComputerName" -Value $NewVMName -Force -ErrorAction SilentlyContinue

            $tcpKey = "HKLM:\Clone_SYSTEM\ControlSet001\Services\Tcpip\Parameters"
            if (-not (Test-Path $tcpKey)) { New-Item -Path $tcpKey -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $tcpKey -Name "Hostname" -Value $NewVMName -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $tcpKey -Name "NV Hostname" -Value $NewVMName -Force -ErrorAction SilentlyContinue
            Write-Host "    -> Configured unique ComputerName and Hostname: $NewVMName" -ForegroundColor Gray
        } finally {
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds 500
            reg unload HKLM\Clone_SYSTEM 2>&1 | Out-Null
        }
    }

    # Update ComputerName in unattend.xml if present
    $pantherXml = "${winLetter}:\Windows\Panther\unattend.xml"
    $sysprepXml = "${winLetter}:\Windows\System32\Sysprep\unattend.xml"
    foreach ($xmlPath in @($pantherXml, $sysprepXml)) {
        if (Test-Path $xmlPath) {
            $xmlContent = [System.IO.File]::ReadAllText($xmlPath)
            $xmlContent = $xmlContent -replace '<ComputerName>.*?</ComputerName>', "<ComputerName>$NewVMName</ComputerName>"
            [System.IO.File]::WriteAllText($xmlPath, $xmlContent, [System.Text.UTF8Encoding]::new($true))
        }
    }

} finally {
    if (Test-Path "HKLM:\Clone_SOFTWARE") {
        [GC]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload HKLM\Clone_SOFTWARE 2>&1 | Out-Null
    }
    if (Test-Path "HKLM:\Clone_SYSTEM") {
        [GC]::Collect()
        Start-Sleep -Milliseconds 200
        reg unload HKLM\Clone_SYSTEM 2>&1 | Out-Null
    }
    if ($assignedTempLetter -and $winPart) {
        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${assignedTempLetter}:\" -ErrorAction SilentlyContinue | Out-Null
    }
    Dismount-VHD -Path $NewVHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

# 5. Reset SCSI Disk Identifier on Differencing VHDX
Write-Host "[+] Resetting SCSI Disk Identifier for $NewVHDPath..." -ForegroundColor Green
try {
    Set-VHD -Path $NewVHDPath -ResetDiskIdentifier -Force -Confirm:$false
    Write-Host "    -> Reset SCSI Disk Identifier succeeded." -ForegroundColor Gray
} catch {
    Write-Warning "    [!] Notice resetting disk identifier: $_"
}

# 6. Create and Configure Hyper-V VM
Write-Host "[+] Registering VM '$NewVMName'..." -ForegroundColor Green
New-VM -Name $NewVMName -Generation 2 -MemoryStartupBytes $MemoryBytes -VHDPath $NewVHDPath -SwitchName $SwitchName | Out-Null
Set-VMMemory -VMName $NewVMName -DynamicMemoryEnabled $false
Set-VMProcessor -VMName $NewVMName -Count $CPUCount
Set-VMFirmware -VMName $NewVMName -EnableSecureBoot Off
Set-VM -VMName $NewVMName `
    -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 1GB `
    -HighMemoryMappedIoSpace 32GB `
    -AutomaticStopAction TurnOff

# Attach secondary network adapter to Default Switch for high-speed Internet NAT
$defaultSwitch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if ($defaultSwitch) {
    Write-Host "[+] Attaching secondary network adapter connected to 'Default Switch' for Internet..." -ForegroundColor Green
    Add-VMNetworkAdapter -VMName $NewVMName -SwitchName "Default Switch" -Name "Internet" -ErrorAction SilentlyContinue | Out-Null
}
Enable-VMIntegrationService -VMName $NewVMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue | Out-Null

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
    $cs = Get-WmiObject -Namespace $wmiNamespace -Class Msvm_ComputerSystem -Filter "ElementName = '$NewVMName'"
    if ($cs) {
        $vssd = Get-WmiObject -Namespace $wmiNamespace -Class Msvm_VirtualSystemSettingData | Where-Object { $_.ElementName -eq $NewVMName -and $_.InstanceID -like "*$($cs.Name)*" }
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
Write-Host "[+] Generating randomized vendor MAC address for $NewVMName..." -ForegroundColor Green
$vendorOUIList = @("001B21", "00215C", "001E67", "00E04C", "04D9F5", "2C4D54", "1866DA", "B82A72")
$chosenOUI = $vendorOUIList | Get-Random
$nicHex = 1..3 | ForEach-Object { "{0:X2}" -f (Get-Random -Min 0 -Max 256) }
$randomMac = "$chosenOUI$($nicHex -join '')"
Write-Host "    -> Vendor MAC assigned: $randomMac" -ForegroundColor Gray
Set-VMNetworkAdapter -VMName $NewVMName -StaticMacAddress $randomMac -MacAddressSpoofing On

# 9. Attach GPU Partition Adapter
Write-Host "[+] Allocating GPU-PV Partition ($VRAMUnits units VRAM)..." -ForegroundColor Green
Add-VMGpuPartitionAdapter -VMName $NewVMName
Set-VMGpuPartitionAdapter -VMName $NewVMName `
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

Write-Host "=== Successfully provisioned $NewVMName in under 30 seconds! ===" -ForegroundColor Green
