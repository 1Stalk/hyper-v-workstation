<#
.SYNOPSIS
    Verify-HWID.ps1 - Audit utility for hardware and system identifiers on Windows 11.
    Displays what anti-cheat, anti-fraud, and system profiling software observes.
#>

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "               HWID & SYSTEM AUDIT (WINDOWS 11)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. BIOS & SMBIOS
$bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
$csp = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue

Write-Host "`n[+] 1. SYSTEM IDENTIFIERS (SMBIOS / DMI):" -ForegroundColor Yellow
Write-Host "    Manufacturer:       $($cs.Manufacturer)"
Write-Host "    Model:              $($cs.Model)"
Write-Host "    BIOS Vendor:        $($bios.Manufacturer)"
Write-Host "    BIOS Version:       $($bios.SMBIOSBIOSVersion)"
Write-Host "    BIOS SerialNumber:  $($bios.SerialNumber)"
Write-Host "    Board SerialNumber: $($board.SerialNumber)"
Write-Host "    System UUID:        $($csp.UUID)"

# 2. Storage & Disks
Write-Host "`n[+] 2. STORAGE (DISKS & VOLUMES):" -ForegroundColor Yellow
Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "    Disk Model:         $($_.Model)"
    Write-Host "    Disk SerialNumber:  $($_.SerialNumber)"
    Write-Host "    Interface:          $($_.InterfaceType)"
    Write-Host "    DeviceID:           $($_.DeviceID)"
}

$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
Write-Host "    C: Volume Serial:   $($vol.VolumeSerialNumber)"

# 3. GPU (GPU-PV)
Write-Host "`n[+] 3. GRAPHICS ADAPTERS (GPU / GPU-PV):" -ForegroundColor Yellow
Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "    GPU Name:           $($_.Name)"
    Write-Host "    Driver Version:     $($_.DriverVersion)"
    Write-Host "    PNP Device ID:      $($_.PNPDeviceID)"
}

# 4. Network Adapters
Write-Host "`n[+] 4. NETWORK ADAPTERS (MAC & IP CONFIG):" -ForegroundColor Yellow
Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -or $_.HardwareInterface } | ForEach-Object {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $ipList = ($ipConfig | Select-Object -ExpandProperty IPAddress) -join ", "
    Write-Host "    Adapter:            $($_.Name)"
    Write-Host "    MAC Address:        $($_.MacAddress)"
    Write-Host "    IPv4 Address:       $ipList"
    Write-Host "    InterfaceDesc:      $($_.InterfaceDescription)"
    Write-Host "    Status:             $($_.Status)"
}

# 5. Windows Registry Identifiers
Write-Host "`n[+] 5. WINDOWS REGISTRY IDENTIFIERS:" -ForegroundColor Yellow
$machineGuid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
$hwProfile = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" -Name HwProfileGuid -ErrorAction SilentlyContinue).HwProfileGuid
$productId = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductId -ErrorAction SilentlyContinue).ProductId

Write-Host "    MachineGuid:        $machineGuid"
Write-Host "    HardwareProfileGuid:$hwProfile"
Write-Host "    ProductId:          $productId"
Write-Host "    ComputerName:       $($env:COMPUTERNAME)"

# 6. Sunshine Streaming & Network Health
Write-Host "`n[+] 6. SERVICES & CONNECTIVITY STATUS:" -ForegroundColor Yellow
$sunSvc = Get-Service "SunshineService" -ErrorAction SilentlyContinue
if ($sunSvc) {
    Write-Host "    Sunshine Service:   $($sunSvc.Status) (Startup: $($sunSvc.StartType))" -ForegroundColor Green
} else {
    Write-Host "    Sunshine Service:   Not installed / Not found" -ForegroundColor DarkGray
}

# Internet connectivity check
$gwPing = Test-Connection -ComputerName "192.168.100.1" -Count 1 -Quiet -ErrorAction SilentlyContinue
$dnsPing = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue
Write-Host "    Gateway Reachable:  $($gwPing)"
Write-Host "    Internet Reachable: $($dnsPing)"

Write-Host "`n================================================================" -ForegroundColor Cyan
