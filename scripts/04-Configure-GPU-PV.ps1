<#
.SYNOPSIS
    Creates and configures Hyper-V VM with GPU Partitioning (GPU-PV) allocating 1GB VRAM.
.DESCRIPTION
    Sets Generation 2, 4 vCPUs, 8GB RAM, Secure Boot Off, MMIO (Low 1GB / High 32GB),
    assigns randomized vendor MAC address (Intel/Realtek/ASUS OUI),
    and assigns GPU Partition Adapter with 250,000,000 VRAM units (1GB out of 4GB GTX 1050 Ti).
#>

[CmdletBinding()]
param(
    [string]$VMName = "Gaming-VM1",
    [string]$VHDPath = "C:\Hyper-V\VMs\Gaming-VM1.vhdx",
    [string]$SwitchName = "VM-Gaming-Switch",
    [int]$CPUCount = 4,
    [int64]$MemoryBytes = 8GB,
    # 250,000,000 units = 25% of 1,000,000,000 = 1024 MB out of 4096 MB physical VRAM
    [uint64]$VRAMUnits = 250000000
)

$ErrorActionPreference = "Stop"

Write-Host "=== Configuring Hyper-V VM and GPU Partitioning for $VMName ===" -ForegroundColor Cyan

# 1. Check or Clean existing VM
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "[!] VM '$VMName' already exists. Stopping and removing old VM definition..." -ForegroundColor Yellow
    if ($existingVM.State -ne 'Off') {
        Stop-VM -Name $VMName -TurnOff -Force
        Start-Sleep -Seconds 2
    }
    Remove-VM -Name $VMName -Force
}

# 2. Create Generation 2 VM
Write-Host "[+] Creating VM '$VMName' (Gen 2, $($MemoryBytes / 1GB)GB RAM)..." -ForegroundColor Green
New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryBytes -VHDPath $VHDPath -SwitchName $SwitchName | Out-Null

# 3. Configure VM Memory & Processor
Write-Host "[+] Configuring Memory (Static) & Processor ($CPUCount vCPUs)..." -ForegroundColor Green
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $false
Set-VMProcessor -VMName $VMName -Count $CPUCount

# 4. Firmware & MMIO Configuration for GPU Partitioning
Write-Host "[+] Disabling Secure Boot and configuring MMIO & Guest-Controlled Cache..." -ForegroundColor Green
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off
Set-VM -VMName $VMName `
    -GuestControlledCacheTypes $true `
    -LowMemoryMappedIoSpace 1GB `
    -HighMemoryMappedIoSpace 32GB `
    -AutomaticStopAction TurnOff

# 5. Assign Randomized Vendor MAC Address (Intel / Realtek / ASUS)
Write-Host "[+] Generating randomized vendor MAC address for $VMName..." -ForegroundColor Green
$vendorOUIList = @("001B21", "001517", "001E67", "00E04C", "04D9F5", "2C4D54")
$chosenOUI = $vendorOUIList | Get-Random
$nicHex = 1..3 | ForEach-Object { "{0:X2}" -f (Get-Random -Min 0 -Max 256) }
$randomMac = "$chosenOUI$($nicHex -join '')"
Write-Host "    -> Vendor MAC assigned: $randomMac" -ForegroundColor Gray
Set-VMNetworkAdapter -VMName $VMName -StaticMacAddress $randomMac -MacAddressSpoofing On

# 6. Add and Configure GPU Partition Adapter
Write-Host "[+] Attaching GPU Partition Adapter with 1GB VRAM limit ($VRAMUnits units)..." -ForegroundColor Green
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

Write-Host "=== VM Configuration Completed Successfully! ===" -ForegroundColor Green
Get-VMGpuPartitionAdapter -VMName $VMName | Select-Object VMName, MinPartitionVRAM, MaxPartitionVRAM, OptimalPartitionVRAM | Format-Table
