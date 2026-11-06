<#
.SYNOPSIS
    Host-Proxy-Manager.ps1 - External SOCKS5 Proxy & DNS Leak-Free Routing Manager for Hyper-V Gaming VMs.
.DESCRIPTION
    Provides host-side transparent SOCKS5 proxy routing via sing-box (WFP + gVisor TUN).
    Ensures 100% clean guest VM without any installed proxy software.
    Guarantees hardware-level kill-switch by disconnecting the direct internet vSwitch adapter,
    and prevents DNS leaks by enforcing remote DNS resolution via SOCKS5 proxy endpoints.
#>

[CmdletBinding()]
param()

$Script:RootDir = "C:\Users\server1\Desktop\Hyper-V"
$Script:ConfigDir = Join-Path $Script:RootDir "config"
$Script:ProfilesFile = Join-Path $Script:ConfigDir "proxy-profiles.json"
$Script:SingBoxDir = Join-Path $Script:RootDir "tools\sing-box"
$Script:SingBoxExe = Join-Path $Script:SingBoxDir "sing-box.exe"
$Script:SingBoxCfg = Join-Path $Script:ConfigDir "sing-box.json"
$Script:SingBoxLog = Join-Path $Script:SingBoxDir "sing-box.log"

# Default VM Static IPs mapping
$Script:VMIPMap = @{
    "Gaming-VM1" = "192.168.100.11"
    "Gaming-VM2" = "192.168.100.12"
    "Gaming-VM3" = "192.168.100.13"
    "Gaming-VM4" = "192.168.100.14"
    "Gaming-VM5" = "192.168.100.15"
}

function Ensure-Directories {
    if (-not (Test-Path $Script:ConfigDir)) { New-Item -ItemType Directory -Path $Script:ConfigDir -Force | Out-Null }
    if (-not (Test-Path $Script:SingBoxDir)) { New-Item -ItemType Directory -Path $Script:SingBoxDir -Force | Out-Null }
}

function Get-ProxyConfig {
    Ensure-Directories
    if (Test-Path $Script:ProfilesFile) {
        try {
            return Get-Content $Script:ProfilesFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse $Script:ProfilesFile : $_"
        }
    }
    
    # Default initial configuration
    $defaultCfg = [PSCustomObject]@{
        profiles = @(
            [PSCustomObject]@{
                id = "proxy-1"
                name = "Bouygues Telecom FR 1 (Marseille)"
                server = "198.51.100.1"
                port = 47095
                username = "REDACTED_USER"
                password = "REDACTED_PASSWORD"
                country = "FR"
                city = "Marseille"
                isp = "Bouygues Telecom SA"
            },
            [PSCustomObject]@{
                id = "proxy-2"
                name = "Bouygues Telecom FR 2 (Marseille)"
                server = "198.51.100.1"
                port = 46791
                username = "REDACTED_USER"
                password = "REDACTED_PASSWORD"
                country = "FR"
                city = "Marseille"
                isp = "Bouygues Telecom SA"
            }
        )
        assignments = [PSCustomObject]@{
            "Gaming-VM1" = [PSCustomObject]@{ enabled = $true; profileId = "proxy-1" }
            "Gaming-VM2" = [PSCustomObject]@{ enabled = $true; profileId = "proxy-2" }
        }
    }
    Save-ProxyConfig $defaultCfg
    return $defaultCfg
}

function Save-ProxyConfig($configObj) {
    Ensure-Directories
    $json = $configObj | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($Script:ProfilesFile, $json, [System.Text.UTF8Encoding]::new($true))
}

function Test-ProxyEndpoint {
    param(
        [Parameter(Mandatory=$true)][string]$Server,
        [Parameter(Mandatory=$true)][int]$Port,
        [string]$Username,
        [string]$Password,
        [int]$TimeoutSec = 6
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = [PSCustomObject]@{
        Success = $false
        IP = $null
        Country = $null
        City = $null
        ISP = $null
        LatencyMs = 0
        Error = $null
    }

    try {
        # 1. TCP Socket Ping
        $client = New-Object System.Net.Sockets.TcpClient
        $connectTask = $client.ConnectAsync($Server, $Port)
        if (-not $connectTask.Wait($TimeoutSec * 1000)) {
            $client.Close()
            throw "Connection timed out after ${TimeoutSec}s to $Server ($Port)"
        }
        $sw.Stop()
        $result.LatencyMs = [int]$sw.ElapsedMilliseconds
        $client.Close()

        # 2. Curl HTTP / GeoIP via socks5h (remote DNS resolve at proxy endpoint)
        $proxyUrl = if ($Username -and $Password) {
            "socks5h://" + $Username + ":" + $Password + "@" + $Server + ":" + $Port
        } else {
            "socks5h://" + $Server + ":" + $Port
        }

        $curlCmd = "curl.exe -s --max-time $TimeoutSec -x $proxyUrl https://ipinfo.io/json"
        $rawJson = Invoke-Expression $curlCmd 2>$null
        if ($rawJson) {
            $info = $rawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($info -and $info.ip) {
                $result.Success = $true
                $result.IP = $info.ip
                $result.Country = $info.country
                $result.City = $info.city
                $result.ISP = $info.org
            }
        }
        if (-not $result.Success) {
            # Fallback simple ip query
            $curlIp = Invoke-Expression "curl.exe -s --max-time $TimeoutSec -x $proxyUrl https://api.ipify.org" 2>$null
            if ($curlIp -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                $result.Success = $true
                $result.IP = $curlIp.Trim()
            } else {
                throw "Failed to retrieve external IP through proxy"
            }
        }
    } catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}

function Build-SingBoxConfig {
    $cfg = Get-ProxyConfig
    
    # Find active VM assignments
    $activeRules = @()
    $dnsServers = @()
    $dnsRules = @()
    $outbounds = @()

    # Base Outbounds: direct and block
    $outbounds += [PSCustomObject]@{
        type = "direct"
        tag = "direct"
    }
    $outbounds += [PSCustomObject]@{
        type = "block"
        tag = "block"
    }

    # Base DNS server: direct (for host / non-proxied subnets)
    $dnsServers += [PSCustomObject]@{
        type = "udp"
        tag = "dns-direct"
        server = "1.1.1.1"
        detour = "direct"
    }

    # Check each VM assignment
    $hasAnyProxiedVM = $false
    if ($cfg.assignments) {
        foreach ($prop in $cfg.assignments.PSObject.Properties) {
            $vmName = $prop.Name
            $assign = $prop.Value
            if ($assign.enabled) {
                $profile = $cfg.profiles | Where-Object { $_.id -eq $assign.profileId } | Select-Object -First 1
                if ($profile) {
                    $hasAnyProxiedVM = $true
                    $outboundTag = "socks_$vmName"
                    $dnsTag = "dns_$vmName"
                    
                    # Outbound SOCKS5 definition
                    $socksOutbound = [PSCustomObject]@{
                        type = "socks"
                        tag = $outboundTag
                        server = $profile.server
                        server_port = [int]$profile.port
                        version = "5"
                    }
                    if ($profile.username -and $profile.password) {
                        $socksOutbound | Add-Member -MemberType NoteProperty -Name "username" -Value $profile.username
                        $socksOutbound | Add-Member -MemberType NoteProperty -Name "password" -Value $profile.password
                    }
                    $outbounds += $socksOutbound

                    # Remote DNS over SOCKS5 proxy (Zero DNS Leak!)
                    $dnsServers += [PSCustomObject]@{
                        type = "tcp"
                        tag = $dnsTag
                        server = "1.1.1.1"
                        detour = $outboundTag
                    }

                    # VM IP
                    $vmIp = $Script:VMIPMap[$vmName]
                    if (-not $vmIp) {
                        # Dynamic fallback
                        $vmIp = "192.168.100." + ($activeRules.Count + 11)
                    }

                    # DNS Rule: queries from this VM IP use the remote DNS detour
                    $dnsRules += [PSCustomObject]@{
                        source_ip_cidr = @("$vmIp/32")
                        server = $dnsTag
                    }

                    # Route Rule: traffic from this VM IP routes to the proxy
                    $activeRules += [PSCustomObject]@{
                        source_ip_cidr = @("$vmIp/32")
                        outbound = $outboundTag
                    }
                }
            }
        }
    }

    # Route Rules assembly
    $routeRules = @(
        [PSCustomObject]@{
            action = "hijack-dns"
            protocol = "dns"
        },
        [PSCustomObject]@{
            action = "hijack-dns"
            port = 53
        },
        # Local communication (Moonlight streaming / Sunshine host-to-guest) NEVER proxied!
        [PSCustomObject]@{
            ip_cidr = @("192.168.100.0/24", "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12")
            outbound = "direct"
        }
    )
    $routeRules += $activeRules

    # Full sing-box config object (Sing-box 1.14+ compliant)
    $singBoxObj = [PSCustomObject]@{
        log = [PSCustomObject]@{
            level = "warn"
            output = $Script:SingBoxLog
            timestamp = $true
        }
        dns = [PSCustomObject]@{
            servers = $dnsServers
            rules = $dnsRules
            final = "dns-direct"
            strategy = "prefer_ipv4"
        }
        inbounds = @(
            [PSCustomObject]@{
                type = "tun"
                tag = "tun-in"
                interface_name = "singbox-tun"
                address = @("172.19.0.1/30")
                auto_route = $true
                strict_route = $true
                stack = "gvisor"
            }
        )
        outbounds = $outbounds
        route = [PSCustomObject]@{
            auto_detect_interface = $true
            default_domain_resolver = "dns-direct"
            rules = $routeRules
            final = "direct"
        }
    }

    $json = $singBoxObj | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Script:SingBoxCfg, $json, [System.Text.Encoding]::ASCII)
    return $hasAnyProxiedVM
}

function Ensure-HostForwardingSafeguard {
    # CRITICAL: Disable forwarding on physical Ethernet so Windows socket binding doesn't loop sing-box outbound into TUN
    try {
        Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*VM-Gaming-Switch*" -and $_.Forwarding -eq "Enabled" } | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Forwarding Disabled -ErrorAction SilentlyContinue
        }
        # Ensure forwarding is enabled on the internal VM switch
        Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*VM-Gaming-Switch*" } | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Forwarding Enabled -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Start-ProxyEngine {
    Ensure-Directories
    Ensure-HostForwardingSafeguard

    $hasProxied = Build-SingBoxConfig
    if (-not $hasProxied) {
        Write-Host "[*] No active proxy assignments. Sing-box engine not required." -ForegroundColor Yellow
        Stop-ProxyEngine
        return
    }

    # Validate configuration syntax
    & $Script:SingBoxExe check -c $Script:SingBoxCfg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Sing-box config validation failed! Check $Script:SingBoxCfg"
    }

    # Check if sing-box is already running
    $running = Get-Process sing-box -ErrorAction SilentlyContinue
    if ($running) {
        # Restart cleanly with new configuration
        Stop-Process -Id $running.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 600
    }

    Write-Host "[+] Starting Sing-box Transparent Routing Engine..." -ForegroundColor Green
    $startArgs = "-NoProfile -ExecutionPolicy Bypass -Command `"& '$Script:SingBoxExe' run -c '$Script:SingBoxCfg'`""
    Start-Process powershell.exe -ArgumentList $startArgs -WindowStyle Hidden -Verb RunAs
    Start-Sleep -Seconds 2
}

function Stop-ProxyEngine {
    Write-Host "[*] Stopping Sing-box Transparent Routing Engine..." -ForegroundColor Yellow
    Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Set-VMProxyRouting {
    param(
        [Parameter(Mandatory=$true)][string]$VMName,
        [Parameter(Mandatory=$true)][bool]$Enabled,
        [string]$ProfileId
    )

    $cfg = Get-ProxyConfig
    if (-not $cfg.assignments) {
        $cfg | Add-Member -MemberType NoteProperty -Name "assignments" -Value ([PSCustomObject]@{})
    }

    $currentAssign = $cfg.assignments.$VMName
    if (-not $currentAssign) {
        $currentAssign = [PSCustomObject]@{ enabled = $false; profileId = $null }
        $cfg.assignments | Add-Member -MemberType NoteProperty -Name $VMName -Value $currentAssign
    }

    $currentAssign.enabled = $Enabled
    if ($ProfileId) {
        $currentAssign.profileId = $ProfileId
    }

    Save-ProxyConfig $cfg

    # Hyper-V Hypervisor Hardware Kill-Switch:
    # When Enabled: Disconnect Internet adapter on Default Switch (Physically closes direct host internet leak!)
    # When Disabled: Connect Internet adapter to Default Switch
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm) {
            $inetAdapter = Get-VMNetworkAdapter -VMName $VMName | Where-Object { $_.Name -eq "Internet" -or $_.SwitchName -eq "Default Switch" } | Select-Object -First 1
            if ($inetAdapter) {
                if ($Enabled) {
                    Write-Host "[*] Hardware Kill-Switch: Disconnecting direct Internet adapter on $VMName..." -ForegroundColor Yellow
                    Disconnect-VMNetworkAdapter -VMNetworkAdapter $inetAdapter -ErrorAction SilentlyContinue
                } else {
                    Write-Host "[*] Restoring direct Internet adapter to Default Switch on $VMName..." -ForegroundColor Green
                    Connect-VMNetworkAdapter -VMNetworkAdapter $inetAdapter -SwitchName "Default Switch" -ErrorAction SilentlyContinue
                }
            }

            # Configure Guest Default Gateway via PowerShell Direct if VM is running
            if ($vm.State -eq 'Running') {
                $vmIp = $Script:VMIPMap[$VMName]
                if (-not $vmIp) { $vmIp = "192.168.100.11" }

                # Pass credentials (user 'Gamer' blank password or admin)
                $cred = New-Object System.Management.Automation.PSCredential("Gamer", (New-Object System.Security.SecureString))
                
                if ($Enabled) {
                    # Inject gateway 192.168.100.1 and DNS 1.1.1.1
                    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                        param($targetIp)
                        $gamingNic = Get-NetAdapter | Where-Object { 
                            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                            $ip -like "192.168.100.*"
                        } | Select-Object -First 1
                        if ($gamingNic) {
                            $gw = Get-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                            if (-not $gw) {
                                New-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -NextHop "192.168.100.1" -RouteMetric 10 -ErrorAction SilentlyContinue | Out-Null
                            }
                            Set-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -ServerAddresses @("1.1.1.1", "8.8.8.8") -ErrorAction SilentlyContinue
                        }
                    } -ArgumentList $vmIp -ErrorAction SilentlyContinue
                } else {
                    # Remove default route on gaming nic
                    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                        $gamingNic = Get-NetAdapter | Where-Object { 
                            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                            $ip -like "192.168.100.*"
                        } | Select-Object -First 1
                        if ($gamingNic) {
                            Remove-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                        }
                    } -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {
        Write-Warning "Hyper-V adapter adjustment note: $_"
    }

    # Reload sing-box engine
    Start-ProxyEngine
}

function Get-VMProxyState {
    param([Parameter(Mandatory=$true)][string]$VMName)
    $cfg = Get-ProxyConfig
    $assign = if ($cfg.assignments) { $cfg.assignments.$VMName } else { $null }
    
    $res = [PSCustomObject]@{
        VMName = $VMName
        Enabled = if ($assign) { [bool]$assign.enabled } else { $false }
        ProfileId = if ($assign) { $assign.profileId } else { $null }
        ProfileName = "Без прокси (Прямое подключение)"
        Server = $null
        Port = 0
        Country = $null
        City = $null
        KillSwitchActive = $false
    }

    if ($res.Enabled -and $res.ProfileId) {
        $p = $cfg.profiles | Where-Object { $_.id -eq $res.ProfileId } | Select-Object -First 1
        if ($p) {
            $res.ProfileName = $p.name
            $res.Server = $p.server
            $res.Port = $p.port
            $res.Country = $p.country
            $res.City = $p.city
            $res.KillSwitchActive = $true
        }
    }

    return $res
}

if ($MyInvocation.MyCommand.CommandType -eq 'Script' -and $ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Get-ProxyConfig, Save-ProxyConfig, Test-ProxyEndpoint, Build-SingBoxConfig, `
                               Start-ProxyEngine, Stop-ProxyEngine, Set-VMProxyRouting, Get-VMProxyState -ErrorAction SilentlyContinue
}
