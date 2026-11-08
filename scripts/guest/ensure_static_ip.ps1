# Ensure-GamingNetwork.ps1
# Automated Network Watchdog & Maintenance Task for Hyper-V GPU-PV Gaming VMs

$ErrorActionPreference = "Continue"

# 1. Determine target static IP for Gaming Switch
$setupDir = "C:\Setup"
$targetIp = "192.168.100.11"
if (Test-Path "$setupDir\ip.txt") {
    $val = (Get-Content "$setupDir\ip.txt" -Raw).Trim()
    if ($val -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $targetIp = $val }
}

# 2. Fix LSA LimitBlankPasswordUse to allow PowerShell Direct with empty password
try {
    $lsaKey = "HKLM:\System\CurrentControlSet\Control\Lsa"
    if (-not (Test-Path $lsaKey)) { New-Item -Path $lsaKey -Force | Out-Null }
    Set-ItemProperty -Path $lsaKey -Name "LimitBlankPasswordUse" -Value 0 -Type DWord -Force
} catch {}

# 3. Purge all AntiOS leftovers if present on desktop
try {
    Remove-Item -Path "C:\Users\Public\Desktop\*AntiOS*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Users\Default\Desktop\*AntiOS*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Users\*\Desktop\*AntiOS*" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Setup\*AntiOS*" -Force -Recurse -ErrorAction SilentlyContinue
} catch {}

# 4. Network Adapter Configuration (Dual-Adapter Architecture)
# NIC A: VM-Gaming-Switch -> Static IP $targetIp/24
# NIC B: Default Switch (Internet) -> DHCP enabled, default gateway 172.x

$allAdapters = Get-NetAdapter -ErrorAction SilentlyContinue

# Identify Internet NIC: Hyper-V Default Switch MAC begins with 00-15-5D or has IP 172.*
$internetNic = $allAdapters | Where-Object { $_.MacAddress -like "00-15-5D*" -or $_.Name -like "*Internet*" } | Select-Object -First 1

# Identify Gaming NIC: the adapter with the randomized MAC / not the internet NIC
$gamingNic = $allAdapters | Where-Object { 
    if ($internetNic) { $_.ifIndex -ne $internetNic.ifIndex } else { $true }
} | Select-Object -First 1

if (-not $gamingNic -and $allAdapters.Count -eq 1) {
    $gamingNic = $allAdapters[0]
}

# Determine Mode:
# If Internet NIC is present, Enabled, Status is Up, AND Hyper-V cable is connected:
# (Note: when Hyper-V disconnects adapter, Status becomes 'Disconnected')
$isDirectMode = ($internetNic -and $internetNic.Status -eq 'Up')

if (-not $isDirectMode) {
    # PROXY MODE:
    # 1. Disable Internet NIC if present and not already disabled to prevent DNS delays
    if ($internetNic -and $internetNic.Status -ne 'Disabled') {
        Disable-NetAdapter -Name $internetNic.Name -Confirm:$false -ErrorAction SilentlyContinue
    }

    # 2. Configure Gaming NIC: Static IP + Gateway 192.168.100.1 + DNS 1.1.1.1
    if ($gamingNic) {
        $currentIP = (Get-NetIPAddress -InterfaceIndex $gamingNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($currentIP -notcontains $targetIp) {
            & netsh interface ipv4 set address name="$($gamingNic.Name)" static $targetIp 255.255.255.0 192.168.100.1 1
            Set-NetIPInterface -InterfaceIndex $gamingNic.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
        }

        # Ensure default route exists via 192.168.100.1
        $gwRoute = Get-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if (-not $gwRoute) {
            route add 0.0.0.0 mask 0.0.0.0 192.168.100.1 metric 1 -p | Out-Null
        }

        # Ensure DNS is set to 1.1.1.1, 8.8.8.8
        $currentDns = (Get-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        if ($currentDns -notcontains "1.1.1.1") {
            Set-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -ServerAddresses @("1.1.1.1", "8.8.8.8") -ErrorAction SilentlyContinue
            Clear-DnsClientCache
        }
    }
} else {
    # DIRECT MODE:
    # 1. Internet NIC is Up: Ensure DHCP is enabled and active
    if ($internetNic) {
        $ipInt = Get-NetIPInterface -InterfaceIndex $internetNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipInt.Dhcp -ne "Enabled") {
            Set-NetIPInterface -InterfaceIndex $internetNic.ifIndex -Dhcp Enabled -InterfaceMetric 10 -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $internetNic.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            & netsh interface ipv4 set address name="$($internetNic.Name)" dhcp
            & netsh interface ipv4 set dns name="$($internetNic.Name)" dhcp
            Start-Sleep -Seconds 2
        }

        # Check if interface has a valid routable IP (NOT APIPA 169.254.*)
        $ipv4List = (Get-NetIPAddress -InterfaceIndex $internetNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        $validIpv4 = $ipv4List | Where-Object { $_ -notlike "169.254.*" -and $_ -notlike "127.*" }
        $hasDefaultRoute = (Get-NetRoute -InterfaceIndex $internetNic.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue)

        if (-not $validIpv4 -or -not $hasDefaultRoute) {
            & cmd.exe /c "ipconfig /renew `"$($internetNic.Name)`""
            Start-Sleep -Seconds 2
        }
    }

    # 2. Gaming NIC: Ensure Static IP, but NO default gateway
    if ($gamingNic) {
        $currentIP = (Get-NetIPAddress -InterfaceIndex $gamingNic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        if ($currentIP -notcontains $targetIp) {
            & netsh interface ipv4 set address name="$($gamingNic.Name)" static $targetIp 255.255.255.0 none
            Set-NetIPInterface -InterfaceIndex $gamingNic.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
        }

        # Remove default route if present
        $gamingGw = Get-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($gamingGw) {
            Remove-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
            Set-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            Clear-DnsClientCache
        }
    }
}

# 5. Verify Internet Connectivity & Diagnostics
$dnsRes = $null
try {
    $dnsRes = (Resolve-DnsName -Name google.com -Type A -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPAddress -First 1)
} catch {}

$webRes = $null
try {
    $webRes = (Invoke-WebRequest -Uri https://www.google.com -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue).StatusCode
} catch {}

$diag = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    VMName = $env:COMPUTERNAME
    TargetIP = $targetIp
    Mode = if ($isDirectMode) { "DIRECT (Default Switch)" } else { "PROXIED (VM-Gaming-Switch)" }
    GamingNic = if ($gamingNic) { "$($gamingNic.Name) ($($gamingNic.MacAddress))" } else { "None" }
    InternetNic = if ($internetNic) { "$($internetNic.Name) ($($internetNic.MacAddress))" } else { "None" }
    DnsGoogle = $dnsRes
    WebStatusCode = $webRes
    AllIPs = (Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object { "$($_.InterfaceAlias): $($_.IPAddress)" }) -join "; "
}
$diag | Format-List | Out-File "C:\Setup\net_status.txt" -Encoding UTF8

# 6. Publish Status to Sunshine apps.json so it is externally visible via API
$sunshineApps = "C:\Program Files\Sunshine\config\apps.json"
if (Test-Path $sunshineApps) {
    try {
        $json = Get-Content $sunshineApps -Raw | ConvertFrom-Json
        $statApp = $json.apps | Where-Object { $_.name -like "SystemStatus*" }
        $statusStr = "SystemStatus [IP: $targetIp | Internet: $(if ($webRes -eq 200) { 'ONLINE' } else { 'OFFLINE' }) | DNS: $dnsRes]"
        if (-not $statApp) {
            $json.apps += [PSCustomObject]@{
                name = $statusStr
                "image-path" = "desktop.png"
            }
        } else {
            $statApp.name = $statusStr
        }
        $json | ConvertTo-Json -Depth 5 | Set-Content $sunshineApps -Encoding UTF8
    } catch {}
}
