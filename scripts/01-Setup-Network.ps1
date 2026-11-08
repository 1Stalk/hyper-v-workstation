<#
.SYNOPSIS
    Configures the Hyper-V internal virtual switch and NAT networking for gaming VMs.
.DESCRIPTION
    Creates 'VM-Gaming-Switch' (Internal) if missing, assigns static gateway IP 192.168.100.1/24,
    and creates NetNat 'VM-Gaming-NAT' (192.168.100.0/24) to provide internet access to VMs
    while maintaining predictable static IPs for Moonlight streaming.
#>

[CmdletBinding()]
param(
    [string]$SwitchName = "VM-Gaming-Switch",
    [string]$GatewayIP = "192.168.100.1",
    [int]$PrefixLength = 24,
    [string]$NatSubnet = "192.168.100.0/24",
    [string]$NatName = "VM-Gaming-NAT"
)

$ErrorActionPreference = "Stop"

# Auto-elevate or require Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "01-Setup-Network.ps1 must be run in an elevated PowerShell session (as Administrator)."
}

Write-Host "=== Setting up Hyper-V Gaming Network ===" -ForegroundColor Cyan

# 1. Check or Create Virtual Switch
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    Write-Host "[+] Creating Internal VMSwitch '$SwitchName'..." -ForegroundColor Green
    New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    Start-Sleep -Seconds 2
} else {
    Write-Host "[*] VMSwitch '$SwitchName' already exists." -ForegroundColor Yellow
}

# 2. Locate the Host Virtual Adapter
$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*$SwitchName*" -or $_.Name -like "*$SwitchName*" }
if (-not $adapter) {
    # Fallback search by vEthernet name
    $adapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
}

if (-not $adapter) {
    throw "Unable to find host network adapter for switch '$SwitchName'"
}

Write-Host "[*] Host Adapter identified: $($adapter.Name) (Index: $($adapter.ifIndex))" -ForegroundColor Gray

# 3. Assign Gateway IP
$currentIP = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -eq $GatewayIP }

if (-not $currentIP) {
    # Remove any existing IPv4 configuration on this adapter to avoid conflicts
    Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    Write-Host "[+] Assigning IP $GatewayIP/$PrefixLength to $($adapter.Name)..." -ForegroundColor Green
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $GatewayIP -PrefixLength $PrefixLength | Out-Null
} else {
    Write-Host "[*] IP $GatewayIP/$PrefixLength already assigned to $($adapter.Name)." -ForegroundColor Yellow
}

# 4. Check or Create WinNAT
$existingNat = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if (-not $existingNat) {
    # Check if any NAT overlapping exists
    $allNats = Get-NetNat
    $overlap = $allNats | Where-Object { $_.InternalIPInterfaceAddressPrefix -eq $NatSubnet }
    if ($overlap) {
        Write-Host "[*] NAT network with prefix $NatSubnet already exists ($($overlap.Name))." -ForegroundColor Yellow
    } else {
        Write-Host "[+] Creating NetNat '$NatName' for subnet $NatSubnet..." -ForegroundColor Green
        New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $NatSubnet | Out-Null
    }
} else {
    Write-Host "[*] NetNat '$NatName' already exists." -ForegroundColor Yellow
}

# 5. Enable Host Routing / Firewall Access for Sunshine / Moonlight Ports
Write-Host "[+] Verifying Windows Firewall rules for Moonlight/Sunshine streaming..." -ForegroundColor Cyan
$ruleName = "HyperV-Gaming-Sunshine-Moonlight"
$existingRule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
if (-not $existingRule) {
    # Sunshine uses TCP 47984, 47989, 47990, 48010 and UDP 47998-48010
    New-NetFirewallRule -Name $ruleName -DisplayName "Hyper-V Sunshine / Moonlight Stream Ports" `
        -Direction Inbound -Action Allow -Protocol TCP -LocalPort 47984, 47989, 47990, 48010 `
        -Profile Any | Out-Null
    New-NetFirewallRule -Name "$ruleName-UDP" -DisplayName "Hyper-V Sunshine / Moonlight Stream UDP" `
        -Direction Inbound -Action Allow -Protocol UDP -LocalPort 47998-48010 `
        -Profile Any | Out-Null
    Write-Host "[+] Firewall rules created." -ForegroundColor Green
} else {
    Write-Host "[*] Firewall rules already configured." -ForegroundColor Yellow
}

Write-Host "=== Hyper-V Gaming Network Configured Successfully ===" -ForegroundColor Green
