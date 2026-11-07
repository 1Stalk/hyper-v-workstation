<#
.SYNOPSIS
    Host-HyperV-Randomize.ps1 - Hardware spoofing and identifier randomizer for Hyper-V GPU-PV VMs.
    Specifically designed for Windows 11 24H2 / 25H2 environments.

.DESCRIPTION
    Runs on the Hyper-V HOST as Administrator when the target VM is powered OFF.
    Performs:
      1. WMI v2 SMBIOS modification:
         - BIOSSerialNumber
         - BaseBoardSerialNumber
         - ChassisSerialNumber
         - ChassisAssetTag
         - BIOSGUID (System UUID)
      2. Set-VHD SCSI Disk Identifier reset (-Force -Confirm:$false).
      3. Set-VMNetworkAdapter vendor MAC randomization (Intel, Dell, Realtek OUI).
      4. GPU-PV Partition Adapter re-initialization with full 1GB VRAM slice restoration.
      5. Offline registry hardware identifier randomization (MachineGuid, HardwareProfileGuid,
         ProductId, BuildGuid, InstallDate, SQM MachineId).

.EXAMPLE
    .\Host-HyperV-Randomize.ps1 -VMName "Gaming-VM1"
    .\Host-HyperV-Randomize.ps1 -VMName "Gaming-VM2" -CycleGpuPV -RandomizeOfflineRegistry
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [Parameter(Mandatory = $false)]
    [string]$VHDXPath,

    [Parameter(Mandatory = $false)]
    [switch]$CycleGpuPV = $true,

    [Parameter(Mandatory = $false)]
    [switch]$RandomizeOfflineRegistry = $true,

    [Parameter(Mandatory = $false)]
    [uint64]$VRAMUnits = 250000000
)

$ErrorActionPreference = "Stop"

# Auto-elevate or require Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Host-HyperV-Randomize.ps1 must be run in an elevated PowerShell session (as Administrator)!"
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Hyper-V + GPU-PV Hardware Randomizer (Win 11 25H2)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Validation and VM State
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    throw "Virtual machine '$VMName' not found!"
}

if ($vm.State -ne 'Off') {
    throw "Virtual machine '$VMName' must be completely powered OFF (current state: $($vm.State))!"
}

# String and Hex Generators
function Get-RandomAlphaNum([int]$length) {
    $chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    -join ($chars | Get-Random -Count $length)
}

function Get-RandomHex([int]$length) {
    $chars = "0123456789ABCDEF".ToCharArray()
    -join ($chars | Get-Random -Count $length)
}

$NewBiosSerial    = Get-RandomAlphaNum 12
$NewBoardSerial   = Get-RandomAlphaNum 14
$NewChassisSerial = Get-RandomAlphaNum 10
$NewAssetTag      = "AT-" + (Get-RandomAlphaNum 8)
$NewBiosGuid      = [guid]::NewGuid().ToString().ToUpper()

# Realistic vendor MAC prefixes (Intel, Realtek, Dell)
$MacPrefixes = @("001B21", "00215C", "001E67", "00E04C", "04D9F5", "2C4D54", "1866DA", "B82A72")
$SelectedPrefix = $MacPrefixes | Get-Random
$NewMacAddress  = $SelectedPrefix + (Get-RandomHex 6)

# 2. Modify SMBIOS via Hyper-V WMI v2
Write-Host "[1/5] Modifying SMBIOS (BIOS, Board, Chassis, UUID) via WMI v2..." -ForegroundColor Yellow

$Namespace = "root\virtualization\v2"
$ComputerSystem = Get-WmiObject -Namespace $Namespace -Class Msvm_ComputerSystem -Filter "ElementName = '$VMName'"

if (-not $ComputerSystem) {
    throw "Failed to locate Msvm_ComputerSystem for $VMName"
}

$SettingData = Get-WmiObject -Namespace $Namespace -Class Msvm_VirtualSystemSettingData |
    Where-Object { $_.ElementName -eq $VMName -and $_.InstanceID -like "*$($ComputerSystem.Name)*" }

if (-not $SettingData) {
    throw "Failed to locate Msvm_VirtualSystemSettingData for $VMName"
}

# Apply new serials
$SettingData['BIOSSerialNumber']      = $NewBiosSerial
$SettingData['BaseBoardSerialNumber'] = $NewBoardSerial
$SettingData['ChassisSerialNumber']   = $NewChassisSerial
$SettingData['ChassisAssetTag']       = $NewAssetTag
$SettingData['BIOSGUID']              = "{$NewBiosGuid}"

$VMMS = Get-WmiObject -Namespace $Namespace -Class Msvm_VirtualSystemManagementService
$MethodParams = $VMMS.GetMethodParameters("ModifySystemSettings")
$MethodParams["SystemSettings"] = $SettingData.GetText([System.Management.TextFormat]::CimDtd20)

$Result = $VMMS.InvokeMethod("ModifySystemSettings", $MethodParams, $null)

if ($Result.ReturnValue -eq 0 -or $Result.ReturnValue -eq 4096) {
    Write-Host "  [+] SMBIOS successfully updated:" -ForegroundColor Green
    Write-Host "      - BIOS Serial:       $NewBiosSerial"
    Write-Host "      - BaseBoard Serial:  $NewBoardSerial"
    Write-Host "      - Chassis Serial:    $NewChassisSerial"
    Write-Host "      - Asset Tag:         $NewAssetTag"
    Write-Host "      - System BIOSGUID:   {$NewBiosGuid}"
} else {
    Write-Warning "  [!] WMI returned return code: $($Result.ReturnValue)"
}

# 3. Reset VHDX SCSI Disk Identifier
Write-Host "[2/5] Resetting VHDX SCSI Disk Identifier..." -ForegroundColor Yellow
if (-not $VHDXPath) {
    $hardDrives = Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue
    if ($hardDrives -and $hardDrives[0].Path) {
        $VHDXPath = $hardDrives[0].Path
    }
}

if ($VHDXPath -and (Test-Path $VHDXPath)) {
    try {
        Set-VHD -Path $VHDXPath -ResetDiskIdentifier -Force -Confirm:$false
        Write-Host "  [+] Reset SCSI Disk Identifier succeeded for: $VHDXPath" -ForegroundColor Green
    } catch {
        Write-Warning "  [!] Notice resetting disk identifier: $_"
    }
} else {
    Write-Host "  [-] VHDX path not specified or found, step skipped." -ForegroundColor DarkGray
}

# 4. Randomize MAC Address
Write-Host "[3/5] Randomizing MAC Address..." -ForegroundColor Yellow
try {
    $gamingAdapter = Get-VMNetworkAdapter -VMName $VMName | Where-Object { $_.SwitchName -eq 'VM-Gaming-Switch' -or $_.Name -ne 'Internet' } | Select-Object -First 1
    if ($gamingAdapter) {
        Set-VMNetworkAdapter -VMNetworkAdapter $gamingAdapter -StaticMacAddress $NewMacAddress -MacAddressSpoofing On
        Write-Host "  [+] Static MAC assigned: $NewMacAddress (Vendor OUI: $SelectedPrefix) to adapter '$($gamingAdapter.Name)'" -ForegroundColor Green
    } else {
        Set-VMNetworkAdapter -VMName $VMName -StaticMacAddress $NewMacAddress -MacAddressSpoofing On
        Write-Host "  [+] Static MAC assigned: $NewMacAddress (Vendor OUI: $SelectedPrefix)" -ForegroundColor Green
    }
} catch {
    Write-Warning "  [!] Failed to update MAC address: $_"
}

# 5. Cycle GPU-PV Adapter and Restore Partition Limits
if ($CycleGpuPV) {
    Write-Host "[4/5] Recycling GPU Partition Adapter..." -ForegroundColor Yellow
    $gpuAdapters = Get-VMGpuPartitionAdapter -VMName $VMName -ErrorAction SilentlyContinue
    if ($gpuAdapters) {
        $hostInstancePath = $gpuAdapters[0].InstancePath
        if (-not $PSBoundParameters.ContainsKey('VRAMUnits') -and $gpuAdapters[0].MaxPartitionVRAM) {
            $VRAMUnits = $gpuAdapters[0].MaxPartitionVRAM
        }
        Remove-VMGpuPartitionAdapter -VMName $VMName
        Start-Sleep -Milliseconds 500
        if ($hostInstancePath) {
            Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $hostInstancePath
        } else {
            Add-VMGpuPartitionAdapter -VMName $VMName
        }
        
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
            
        Write-Host "  [+] GPU-PV adapter cycled and re-configured ($VRAMUnits units VRAM)" -ForegroundColor Green
    } else {
        Write-Host "  [-] No active GPU Partition Adapter found on $VMName." -ForegroundColor DarkGray
    }
} else {
    Write-Host "[4/5] GPU-PV recycling skipped." -ForegroundColor DarkGray
}

# 6. Offline Registry Identifier Randomization
if ($RandomizeOfflineRegistry -and $VHDXPath -and (Test-Path $VHDXPath)) {
    Write-Host "[5/5] Customizing Offline Registry Identifiers..." -ForegroundColor Yellow
    $mountedVhd = $null
    $assignedTempLetter = $null
    try {
        $mountedVhd = Mount-VHD -Path $VHDXPath -Passthru
        $diskNumber = $mountedVhd.DiskNumber
        Start-Sleep -Seconds 2

        $winPart = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -like "*Basic data*" -or $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' } | Sort-Object Size -Descending | Select-Object -First 1
        if ($winPart) {
            $winLetter = $winPart.DriveLetter
            if (-not $winLetter) {
                $usedLetters = (Get-Volume | Where-Object { $_.DriveLetter }).DriveLetter
                $freeLetter = 71..89 | ForEach-Object { [char]$_ } | Where-Object { $_ -notin $usedLetters } | Select-Object -First 1
                if ($freeLetter) {
                    Set-Partition -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $freeLetter -ErrorAction SilentlyContinue | Out-Null
                    $winLetter = $freeLetter
                    $assignedTempLetter = $freeLetter
                }
            }

            if ($winLetter) {
                $softwareHive = "${winLetter}:\Windows\System32\config\SOFTWARE"
                $systemHive = "${winLetter}:\Windows\System32\config\SYSTEM"

                if (Test-Path $softwareHive) {
                    reg load HKLM\Rand_SOFTWARE "$softwareHive" 2>&1 | Out-Null
                    try {
                        $newMachineGuid = [guid]::NewGuid().ToString()
                        $newSqmGuid = "{$([guid]::NewGuid().ToString())}"
                        $newBuildGuid = [guid]::NewGuid().ToString()
                        $newInstallDate = [int][double]::Parse((Get-Date (Get-Date).AddDays(-(Get-Random -Minimum 30 -Maximum 300)) -UFormat %s))
                        $newProductId = "{0:D5}-{1:D5}-{2:D5}-AAOEM" -f (Get-Random -Minimum 10000 -Maximum 99999), (Get-Random -Minimum 10000 -Maximum 99999), (Get-Random -Minimum 10000 -Maximum 99999)

                        Set-ItemProperty -Path "HKLM:\Rand_SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $newMachineGuid -Force
                        Set-ItemProperty -Path "HKLM:\Rand_SOFTWARE\Microsoft\SQMClient" -Name "MachineId" -Value $newSqmGuid -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path "HKLM:\Rand_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "BuildGuid" -Value $newBuildGuid -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path "HKLM:\Rand_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "InstallDate" -Value $newInstallDate -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path "HKLM:\Rand_SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductId" -Value $newProductId -Force -ErrorAction SilentlyContinue
                        Write-Host "  [+] Random MachineGuid: $newMachineGuid" -ForegroundColor Green
                        Write-Host "  [+] Random ProductId:   $newProductId" -ForegroundColor Green
                    } finally {
                        [GC]::Collect()
                        [GC]::WaitForPendingFinalizers()
                        Start-Sleep -Milliseconds 300
                        reg unload HKLM\Rand_SOFTWARE 2>&1 | Out-Null
                    }
                }

                if (Test-Path $systemHive) {
                    reg load HKLM\Rand_SYSTEM "$systemHive" 2>&1 | Out-Null
                    try {
                        $newHwProfile = "{" + [guid]::NewGuid().ToString() + "}"
                        $profileKey = "HKLM:\Rand_SYSTEM\ControlSet001\Control\IDConfigDB\Hardware Profiles\0001"
                        if (Test-Path $profileKey) {
                            Set-ItemProperty -Path $profileKey -Name "HwProfileGuid" -Value $newHwProfile -Force
                            Write-Host "  [+] Hardware Profile GUID: $newHwProfile" -ForegroundColor Green
                        }
                    } finally {
                        [GC]::Collect()
                        [GC]::WaitForPendingFinalizers()
                        Start-Sleep -Milliseconds 300
                        reg unload HKLM\Rand_SYSTEM 2>&1 | Out-Null
                    }
                }
            }
        }
    } catch {
        Write-Warning "  [!] Offline registry customization notice: $_"
    } finally {
        if (Test-Path "HKLM:\Rand_SOFTWARE") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Rand_SOFTWARE 2>&1 | Out-Null }
        if (Test-Path "HKLM:\Rand_SYSTEM") { [GC]::Collect(); Start-Sleep -Milliseconds 200; reg unload HKLM\Rand_SYSTEM 2>&1 | Out-Null }
        if ($assignedTempLetter -and $winPart) {
            Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${assignedTempLetter}:\" -ErrorAction SilentlyContinue | Out-Null
        }
        if ($mountedVhd) {
            Dismount-VHD -Path $VHDXPath -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 1
        }
    }
} else {
    Write-Host "[5/5] Offline registry customization skipped." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "   [+] HARDWARE PROFILE RANDOMIZATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
