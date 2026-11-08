<#
.SYNOPSIS
    Guest-HyperV-CleanID.ps1 - Guest identifier randomizer for Windows 11 25H2.
    Safely randomizes MachineGuid, HardwareProfileGuid, ProductId, BuildGuid,
    InstallDate, Telemetry MachineId, NTFS VolumeID, and ComputerName.

.DESCRIPTION
    Runs INSIDE THE GUEST VM as Administrator.
    Does NOT touch networking stack or destroy WinNAT static routing.

.EXAMPLE
    .\Guest-HyperV-CleanID.ps1
    .\Guest-HyperV-CleanID.ps1 -NewComputerName "DESKTOP-GAMER01"
#>

param (
    [string]$NewComputerName = ("DESKTOP-" + (-join ((48..57) + (65..90) | Get-Random -Count 7 | ForEach-Object {[char]$_}))),
    [switch]$ChangeVolumeID = $true
)

$ErrorActionPreference = "Continue"

# Check Administrator privileges
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Guest-HyperV-CleanID.ps1 must be run as Administrator!"
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Windows 11 25H2 In-Guest Identifier Cleaner" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. MachineGuid
$newMachineGuid = [guid]::NewGuid().ToString()
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name "MachineGuid" -Value $newMachineGuid -Force
Write-Host "[+] Cryptography MachineGuid:      $newMachineGuid" -ForegroundColor Green

# 2. Hardware Profile GUID
$newHwProfile = "{" + [guid]::NewGuid().ToString() + "}"
$hwKey = "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001"
if (-not (Test-Path $hwKey)) { New-Item -Path $hwKey -Force | Out-Null }
Set-ItemProperty -Path $hwKey -Name "HwProfileGuid" -Value $newHwProfile -Force
Write-Host "[+] HardwareProfileGuid:          $newHwProfile" -ForegroundColor Green

# 3. Windows NT CurrentVersion parameters
$ntPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$newBuildGuid = [guid]::NewGuid().ToString()
$newInstallDate = [int][double]::Parse((Get-Date (Get-Date).AddDays(-(Get-Random -Minimum 30 -Maximum 300)) -UFormat %s))
$newProductId = "{0:D5}-{1:D5}-{2:D5}-AAOEM" -f (Get-Random -Minimum 10000 -Maximum 99999), (Get-Random -Minimum 10000 -Maximum 99999), (Get-Random -Minimum 10000 -Maximum 99999)

Set-ItemProperty -Path $ntPath -Name "BuildGuid" -Value $newBuildGuid -Force
Set-ItemProperty -Path $ntPath -Name "InstallDate" -Value $newInstallDate -Force
Set-ItemProperty -Path $ntPath -Name "ProductId" -Value $newProductId -Force
Write-Host "[+] ProductId:                    $newProductId" -ForegroundColor Green
Write-Host "[+] BuildGuid:                    $newBuildGuid" -ForegroundColor Green

# 4. Telemetry MachineId (SQMClient)
if (Test-Path "HKLM:\SOFTWARE\Microsoft\SQMClient") {
    $newTelemetryId = "{" + [guid]::NewGuid().ToString() + "}"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SQMClient" -Name "MachineId" -Value $newTelemetryId -Force
    Write-Host "[+] Telemetry MachineId:          $newTelemetryId" -ForegroundColor Green
}

# 5. VolumeID of NTFS C: volume
if ($ChangeVolumeID) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $volumeidPath = Join-Path $scriptDir "Volumeid64.exe"
    if (-not (Test-Path $volumeidPath)) {
        $volumeidPath = "C:\Setup\Volumeid64.exe"
    }
    if (-not (Test-Path $volumeidPath)) {
        $volumeidPath = "C:\Windows\System32\Volumeid64.exe"
    }
    
    if (Test-Path $volumeidPath) {
        $chars = "0123456789ABCDEF".ToCharArray()
        $hex1 = -join ($chars | Get-Random -Count 4)
        $hex2 = -join ($chars | Get-Random -Count 4)
        $newVolId = "$hex1-$hex2"
        
        Write-Host "[*] Changing VolumeID for C: to $newVolId..." -ForegroundColor Yellow
        & $volumeidPath /accepteula C: $newVolId | Out-Null
        Write-Host "[+] VolumeID for drive C: changed to: $newVolId (takes effect after reboot)" -ForegroundColor Green
    } else {
        Write-Warning "[!] Volumeid64.exe not found, volume ID change skipped."
    }
}

# 6. ComputerName
Write-Host "[*] Updating ComputerName to $NewComputerName..." -ForegroundColor Yellow
try {
    Rename-Computer -NewName $NewComputerName -Force -ErrorAction Stop
    Write-Host "[+] ComputerName changed to:       $NewComputerName" -ForegroundColor Green
} catch {
    Write-Warning "[!] Computer rename notice: $_"
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   Identifier cleanup complete! Changes will take effect on reboot." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
