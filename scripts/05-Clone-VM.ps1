<#
.SYNOPSIS
    Instantly provisions an additional Gaming VM using Differencing VHDX and GPU-PV.
.DESCRIPTION
    Scales the environment to run multiple virtual machines sharing host GPU resources.
    Uses master parent disk (differencing disk technique), provisions the new VM in ~20 seconds,
    assigns unique static IP, unique MachineGuid, randomized vendor MAC address (Intel/Realtek/ASUS),
    ensures AntiOS.exe is present on Desktop, and attaches a 1GB GPU partition adapter.
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

# Stop master VM if currently running to ensure clean differencing disk state
$masterVM = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.HardDrives.Path -contains $MasterVHDPath } | Select-Object -First 1
if ($masterVM -and $masterVM.State -ne 'Off') {
    Write-Host "[!] Master VM '$($masterVM.Name)' is currently running. Stopping it cleanly before cloning..." -ForegroundColor Yellow
    Stop-VM -Name $masterVM.Name -TurnOff -Force
    Start-Sleep -Seconds 3
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

# 3. Mount Differencing Disk and configure unique identity
Write-Host "[+] Customizing unique guest identity for $NewVMName (IP: $NewGuestIP)..." -ForegroundColor Green
$mountedVhd = Mount-VHD -Path $NewVHDPath -Passthru
$diskNumber = $mountedVhd.DiskNumber
Start-Sleep -Seconds 2

try {
    # Find Windows partition
    $winPart = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.Type -like "*Basic data*" -or $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' } | Sort-Object Size -Descending | Select-Object -First 1
    $winLetter = $winPart.DriveLetter
    if (-not $winLetter) {
        $winLetter = ($winPart | Add-PartitionAccessPath -AssignDriveLetter -PassThru).DriveLetter
    }

    # Update ip.txt
    $ipFile = "${winLetter}:\Setup\ip.txt"
    if (Test-Path (Split-Path $ipFile -Parent)) {
        Set-Content -Path $ipFile -Value $NewGuestIP -Encoding ASCII
        Write-Host "    -> Updated guest IP to $NewGuestIP in $ipFile" -ForegroundColor Gray
    }

    # Ensure AntiOS.exe is present on Desktop
    $publicDesktop = "${winLetter}:\Users\Public\Desktop"
    $gamerDesktop  = "${winLetter}:\Users\Gamer\Desktop"
    $antiOsTarget  = "$publicDesktop\AntiOS.exe"
    $antiOsSource  = "C:\Users\server1\Desktop\localserver1\new_system\AntiOS.exe"
    if (-not (Test-Path $antiOsSource)) {
        $antiOsSource = "C:\Users\server1\Desktop\Hyper-V\staging\guest_setup\AntiOS.exe"
    }
    if (-not (Test-Path $antiOsSource)) {
        $antiOsSource = "${winLetter}:\Setup\AntiOS.exe"
    }
    if (Test-Path $antiOsSource) {
        New-Item -ItemType Directory -Path $publicDesktop -Force -ErrorAction SilentlyContinue | Out-Null
        Copy-Item -Path $antiOsSource -Destination $antiOsTarget -Force
        Write-Host "    -> Deployed AntiOS.exe to $antiOsTarget" -ForegroundColor Gray
        if (Test-Path "${winLetter}:\Users\Gamer") {
            New-Item -ItemType Directory -Path $gamerDesktop -Force -ErrorAction SilentlyContinue | Out-Null
            Copy-Item -Path $antiOsSource -Destination "$gamerDesktop\AntiOS.exe" -Force
            Write-Host "    -> Deployed AntiOS.exe to $gamerDesktop\AntiOS.exe" -ForegroundColor Gray
        }
    }

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

# 5. Assign Randomized Vendor MAC Address (Intel / Realtek / ASUS)
Write-Host "[+] Generating randomized vendor MAC address for $NewVMName..." -ForegroundColor Green
$vendorOUIList = @("001B21", "001517", "001E67", "00E04C", "04D9F5", "2C4D54")
$chosenOUI = $vendorOUIList | Get-Random
$nicHex = 1..3 | ForEach-Object { "{0:X2}" -f (Get-Random -Min 0 -Max 256) }
$randomMac = "$chosenOUI$($nicHex -join '')"
Write-Host "    -> Vendor MAC assigned: $randomMac" -ForegroundColor Gray
Set-VMNetworkAdapter -VMName $NewVMName -StaticMacAddress $randomMac -MacAddressSpoofing On

# 6. Attach GPU Partition Adapter
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
