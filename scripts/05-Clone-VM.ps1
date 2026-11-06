<#
.SYNOPSIS
    Instantly provisions an additional Gaming VM using Differencing VHDX and GPU-PV.
.DESCRIPTION
    Scales the environment to run 4 or 5 virtual machines sharing host GPU resources.
    Uses a master parent disk (differencing disk technique), provisions the new VM in ~20 seconds,
    assigns unique static IP, and attaches a 1GB GPU partition adapter.
#>

[CmdletBinding()]
param(
    [string]$MasterVHDPath = "C:\Hyper-V\VMs\Gaming-VM1.vhdx",
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

Write-Host "=== Cloning Gaming VM: $NewVMName from $MasterVHDPath ===" -ForegroundColor Cyan

if (-not (Test-Path $MasterVHDPath)) {
    throw "Master VHDX not found at: $MasterVHDPath"
}

# 1. Clean existing VM if present
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
    Remove-Item -Path $NewVHDPath -Force
}

# 2. Create Differencing Disk
Write-Host "[+] Creating Differencing VHDX linked to Master: $NewVHDPath..." -ForegroundColor Green
New-VHD -ParentPath $MasterVHDPath -Path $NewVHDPath -Differencing | Out-Null

# 3. Mount Differencing Disk and inject new IP
Write-Host "[+] Customizing unique guest IP ($NewGuestIP)..." -ForegroundColor Green
$mountedVhd = Mount-VHD -Path $NewVHDPath -Passthru
$diskNumber = $mountedVhd.DiskNumber
Start-Sleep -Seconds 2

try {
    # Find Windows partition
    $winPart = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -like "*Basic data*" -or $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' } | Sort-Object Size -Descending | Select-Object -First 1
    $winLetter = ($winPart | Add-PartitionAccessPath -AssignDriveLetter -PassThru).DriveLetter
    
    # Update ip.txt
    $ipFile = "${winLetter}:\Setup\ip.txt"
    if (Test-Path (Split-Path $ipFile -Parent)) {
        Set-Content -Path $ipFile -Value $NewGuestIP -Encoding ASCII
        Write-Host "[+] Updated guest IP to $NewGuestIP in $ipFile" -ForegroundColor Gray
    }
} finally {
    Dismount-VHD -Path $NewVHDPath -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 2
}

# 4. Create and Configure Hyper-V VM
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

# 5. Attach GPU Partition Adapter
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
