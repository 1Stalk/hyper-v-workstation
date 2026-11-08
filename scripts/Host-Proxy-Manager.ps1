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

$Script:RootDir = Split-Path -Parent $PSScriptRoot
$Script:ConfigDir = Join-Path $Script:RootDir "config"
$Script:ProfilesFile = Join-Path $Script:ConfigDir "proxy-profiles.json"
$Script:SingBoxDir = Join-Path $Script:RootDir "tools\sing-box"
$Script:SingBoxExe = Join-Path $Script:SingBoxDir "sing-box.exe"
$Script:SingBoxCfg = Join-Path $Script:ConfigDir "sing-box.json"
$Script:SingBoxLog = Join-Path $Script:SingBoxDir "sing-box.log"
$Script:GuestWatchdog = Join-Path $PSScriptRoot "guest\ensure_static_ip.ps1"

# Default VM Static IPs mapping
$Script:VMIPMap = @{
    "Gaming-VM1" = "192.168.100.11"
    "Gaming-VM2" = "192.168.100.12"
    "Gaming-VM3" = "192.168.100.13"
    "Gaming-VM4" = "192.168.100.14"
    "Gaming-VM5" = "192.168.100.15"
    "Gaming-VM6" = "192.168.100.16"
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
    
    $exampleFile = Join-Path $Script:ConfigDir "proxy-profiles.example.json"
    if (Test-Path $exampleFile) {
        try {
            Copy-Item -Path $exampleFile -Destination $Script:ProfilesFile -Force
            return Get-Content $Script:ProfilesFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {}
    }

    # Default clean configuration if template is absent
    $defaultCfg = [PSCustomObject]@{
        profiles = @()
        assignments = [PSCustomObject]@{}
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

    # Base DNS server: direct (for host / local subnets, NO detour property)
    $dnsServers += [PSCustomObject]@{
        type = "udp"
        tag = "dns-direct"
        server = "1.1.1.1"
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

                    # Remote DNS over SOCKS5 proxy via DoH (port 443, Zero DNS Leak!)
                    $dnsServers += [PSCustomObject]@{
                        type = "https"
                        tag = $dnsTag
                        server = "1.1.1.1"
                        server_port = 443
                        path = "/dns-query"
                        detour = $outboundTag
                        tls = [PSCustomObject]@{
                            enabled = $true
                            server_name = "cloudflare-dns.com"
                        }
                    }

                    # VM IP
                    $vmIp = $null
                    if ($assign.ip) {
                        $vmIp = $assign.ip
                    } elseif ($Script:VMIPMap -and $Script:VMIPMap.ContainsKey($vmName)) {
                        $vmIp = $Script:VMIPMap[$vmName]
                    } else {
                        $vmIp = "192.168.100." + ($activeRules.Count + 11)
                    }

                    # DNS Rule: queries originating from this VM use its dedicated DoH-over-SOCKS5 endpoint
                    $dnsRules += [PSCustomObject]@{
                        source_ip_cidr = @("$vmIp/32")
                        server = $dnsTag
                    }

                    # Route Rule: all TCP/UDP traffic from this VM routes to its SOCKS5 proxy
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
        # Local subnets (LAN, Moonlight streaming, localhost) ALWAYS direct
        [PSCustomObject]@{
            ip_cidr = @("192.168.100.0/24", "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12")
            outbound = "direct"
        }
    )
    $routeRules += $activeRules

    # Full sing-box config object (Sing-box 1.14+ compliant)
    $singBoxObj = [PSCustomObject]@{
        log = [PSCustomObject]@{
            level = "info"
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
    # 1. Disable forwarding on physical Ethernet adapters so outbound sockets do not loop back into TUN
    try {
        Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*VM-Gaming-Switch*" -and $_.Forwarding -eq "Enabled" } | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Forwarding Disabled -ErrorAction SilentlyContinue
        }
        # 2. Ensure forwarding is enabled on the internal VM switch
        Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*VM-Gaming-Switch*" } | ForEach-Object {
            Set-NetIPInterface -InterfaceIndex $_.ifIndex -Forwarding Enabled -ErrorAction SilentlyContinue
        }
        # 3. CRITICAL: Remove any NetNat on 192.168.100.0/24 which would mask VM source IPs
        Get-NetNat -ErrorAction SilentlyContinue | Where-Object { $_.InternalIPInterfaceAddressPrefix -like "192.168.100*" } | Remove-NetNat -Confirm:$false -ErrorAction SilentlyContinue
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

    if (-not (Test-Path $Script:SingBoxExe)) {
        throw "Sing-box executable not found at '$Script:SingBoxExe'! Run 'scripts\00-Download-Tools.ps1' or place sing-box.exe in '$Script:SingBoxDir'."
    }

    # Validate configuration syntax
    & $Script:SingBoxExe check -c $Script:SingBoxCfg 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Sing-box config validation failed! Check $Script:SingBoxCfg"
    }

    # Ensure background system task exists and runs elevated under SYSTEM
    $taskName = "SingBox-Proxy-Engine"
    $action = New-ScheduledTaskAction -Execute $Script:SingBoxExe -Argument "run -c `"$Script:SingBoxCfg`""
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -Priority 3
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

    # Stop any existing running instance
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Get-Process sing-box -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600

    Write-Host "[+] Starting Sing-box Transparent Routing Engine via System Task..." -ForegroundColor Green
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2

    $checkProc = Get-Process sing-box -ErrorAction SilentlyContinue
    if (-not $checkProc) {
        Write-Warning "Sing-box process exited unexpectedly. Check $Script:SingBoxLog"
    }
}

function Stop-ProxyEngine {
    Write-Host "[*] Stopping Sing-box Transparent Routing Engine..." -ForegroundColor Yellow
    Stop-ScheduledTask -TaskName "SingBox-Proxy-Engine" -ErrorAction SilentlyContinue
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

    # Start or update the transparent routing engine first so endpoints are immediately alive
    Start-ProxyEngine

    # Hyper-V Hardware Kill-Switch:
    # When Enabled: Disconnect Internet adapter on Default Switch (Physically blocks direct host internet leak!)
    # When Disabled: Connect Internet adapter to Default Switch
    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($vm) {
            $inetAdapter = Get-VMNetworkAdapter -VMName $VMName | Where-Object { 
                $_.Name -eq "Internet" -or $_.SwitchName -eq "Default Switch" -or $_.Name -like "*Internet*" 
            } | Select-Object -First 1

            if ($inetAdapter) {
                if ($Enabled) {
                    Write-Host "[*] Hardware Kill-Switch: Disconnecting direct Internet adapter on $VMName..." -ForegroundColor Yellow
                    Disconnect-VMNetworkAdapter -VMNetworkAdapter $inetAdapter -ErrorAction SilentlyContinue
                } else {
                    Write-Host "[*] Restoring direct Internet adapter to Default Switch on $VMName..." -ForegroundColor Green
                    Connect-VMNetworkAdapter -VMNetworkAdapter $inetAdapter -SwitchName "Default Switch" -ErrorAction SilentlyContinue
                }
            }

            # Configure Guest Network Settings via single atomic PowerShell Direct call if VM is running
            if ($vm.State -eq 'Running') {
                $watchdogCode = if (Test-Path $Script:GuestWatchdog) { Get-Content -Path $Script:GuestWatchdog -Raw -Encoding UTF8 } else { "" }
                $cred = New-Object System.Management.Automation.PSCredential("Gamer", (New-Object System.Security.SecureString))

                Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                    param($code, $isProxyMode)
                    
                    # 1. Update persistent watchdog script inside VM
                    if ($code) {
                        try {
                            if (-not (Test-Path "C:\Setup")) { New-Item -ItemType Directory -Path "C:\Setup" -Force | Out-Null }
                            [System.IO.File]::WriteAllText("C:\Setup\ensure_static_ip.ps1", $code, [System.Text.UTF8Encoding]::new($true))
                        } catch {}
                    }

                    if ($isProxyMode) {
                        # PROXY MODE:
                        # 2. Disable Internet NIC if present to prevent DNS/gateway leakage and delays
                        $inetNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                            $_.MacAddress -like "00-15-5D*" -or $_.Name -like "*Internet*" 
                        } | Select-Object -First 1
                        if ($inetNic) {
                            Disable-NetAdapter -Name $inetNic.Name -Confirm:$false -ErrorAction SilentlyContinue
                        }

                        # 3. Configure Gaming NIC
                        $gamingNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                            $ip -like "192.168.100.*"
                        } | Select-Object -First 1
                        if ($gamingNic) {
                            $gw = Get-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
                            if (-not $gw) {
                                route add 0.0.0.0 mask 0.0.0.0 192.168.100.1 metric 1 -p | Out-Null
                            }
                            Set-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -ServerAddresses @("1.1.1.1", "8.8.8.8") -ErrorAction SilentlyContinue
                            Clear-DnsClientCache
                        }
                    } else {
                        # DIRECT MODE:
                        # 2. Re-enable Internet NIC
                        $inetNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                            $_.MacAddress -like "00-15-5D*" -or $_.Name -like "*Internet*" 
                        } | Select-Object -First 1
                        if ($inetNic) {
                            Enable-NetAdapter -Name $inetNic.Name -Confirm:$false -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 1
                            & cmd.exe /c "ipconfig /renew `"$($inetNic.Name)`"" | Out-Null
                        }

                        # 3. Reset Gaming NIC: remove gateway so it doesn't conflict
                        $gamingNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                            $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                            $ip -like "192.168.100.*"
                        } | Select-Object -First 1
                        if ($gamingNic) {
                            Remove-NetRoute -InterfaceIndex $gamingNic.ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
                            Set-DnsClientServerAddress -InterfaceIndex $gamingNic.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
                            Clear-DnsClientCache
                        }
                    }
                } -ArgumentList $watchdogCode, $Enabled -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-Warning "Hyper-V adapter adjustment note: $_"
    }
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

function Remove-ProxyProfile {
    param(
        [Parameter(Mandatory=$true)][string]$ProfileId
    )

    $cfg = Get-ProxyConfig
    $targetProf = $cfg.profiles | Where-Object { $_.id -eq $ProfileId } | Select-Object -First 1
    if (-not $targetProf) { return $null }

    $unboundVMs = @()

    # 1. Safely unbind and restore direct internet on any VM currently using this profile
    if ($cfg.assignments) {
        foreach ($prop in $cfg.assignments.PSObject.Properties) {
            $vmName = $prop.Name
            $assign = $prop.Value
            if ($assign.profileId -eq $ProfileId) {
                if ($assign.enabled) {
                    Write-Host "[*] Profile '$ProfileId' is active on $vmName. Switching $vmName to direct internet..." -ForegroundColor Yellow
                    Set-VMProxyRouting -VMName $vmName -Enabled $false
                    $unboundVMs += $vmName
                } else {
                    $assign.profileId = $null
                }
            }
        }
    }

    # 2. Reload config (in case Set-VMProxyRouting modified it), remove profile, clear lingering references and save
    $cfg = Get-ProxyConfig
    $cfg.profiles = @($cfg.profiles | Where-Object { $_.id -ne $ProfileId })
    if ($cfg.assignments) {
        foreach ($prop in $cfg.assignments.PSObject.Properties) {
            if ($prop.Value.profileId -eq $ProfileId) {
                $prop.Value.profileId = $null
                $prop.Value.enabled = $false
            }
        }
    }
    Save-ProxyConfig $cfg

    # 3. Reload sing-box engine with updated config
    Start-ProxyEngine

    return [PSCustomObject]@{
        Success = $true
        Profile = $targetProf
        UnboundVMs = $unboundVMs
    }
}

function Update-VHDSetupFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$VHDPath,
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string]$Content
    )
    if (-not (Test-Path $VHDPath)) { throw "VHD path does not exist: $VHDPath" }

    # Clean up any stale attachment if already attached
    $vhdCheck = Get-VHD -Path $VHDPath -ErrorAction SilentlyContinue
    if ($vhdCheck -and $vhdCheck.Attached) {
        Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Milliseconds 600
    }

    # Mount VHD with retry against temporary file locks
    $disk = $null
    $mountAttempts = 4
    while (-not $disk -and $mountAttempts -gt 0) {
        try {
            $disk = Mount-VHD -Path $VHDPath -Passthru -ErrorAction Stop
        } catch {
            $mountAttempts--
            if ($mountAttempts -le 0) { throw $_ }
            Start-Sleep -Seconds 1
        }
    }

    $assignedTempLetter = $null
    $winPart = $null
    try {
        Start-Sleep -Seconds 1
        $winPart = Get-Partition -DiskNumber $disk.DiskNumber | Where-Object { $_.Type -like "*Basic*" -or $_.GptType -eq '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' } | Sort-Object Size -Descending | Select-Object -First 1
        if (-not $winPart) {
            throw "Failed to locate Windows partition on disk $($disk.DiskNumber)"
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
                    Set-Partition -DiskNumber $disk.DiskNumber -PartitionNumber $winPart.PartitionNumber -NewDriveLetter $freeLetter -ErrorAction SilentlyContinue | Out-Null
                    $winLetter = $freeLetter
                    $assignedTempLetter = $freeLetter
                } else {
                    $winLetter = ($winPart | Add-PartitionAccessPath -AssignDriveLetter -PassThru -ErrorAction SilentlyContinue).DriveLetter
                }
            }
        }

        if (-not $winLetter) {
            throw "Failed to assign drive letter for disk $($disk.DiskNumber)"
        }

        $setupDir = "${winLetter}:\Setup"
        if (-not (Test-Path $setupDir)) {
            New-Item -ItemType Directory -Path $setupDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        Set-Content -Path "$setupDir\$FileName" -Value $Content -Encoding ASCII
        Write-Host "    -> Updated $FileName inside $VHDPath with value '$Content'" -ForegroundColor Gray
    } finally {
        if ($assignedTempLetter -and $winPart) {
            Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $winPart.PartitionNumber -AccessPath "${assignedTempLetter}:\" -ErrorAction SilentlyContinue | Out-Null
        }
        $dismountSuccess = $false
        for ($i = 0; $i -lt 5; $i++) {
            try {
                Dismount-VHD -Path $VHDPath -ErrorAction Stop | Out-Null
                $dismountSuccess = $true
                break
            } catch {
                Start-Sleep -Milliseconds 800
            }
        }
        if (-not $dismountSuccess) {
            Dismount-VHD -Path $VHDPath -ErrorAction SilentlyContinue | Out-Null
        }
        Start-Sleep -Milliseconds 500
    }
}

function Set-VMHardwareConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$VMName,
        [int]$CPUCount = 0,
        [int64]$RAMBytes = 0,
        [int]$VRAMMB = -1,
        [switch]$ForceStop
    )

    $vm = Get-VM -Name $VMName -ErrorAction Stop

    $needsStop = $false
    if ($CPUCount -gt 0 -and $CPUCount -ne $vm.ProcessorCount) { $needsStop = $true }
    if ($RAMBytes -gt 0 -and $RAMBytes -ne $vm.MemoryStartup) { $needsStop = $true }
    if ($VRAMMB -ge 0) {
        $gpu = Get-VMGpuPartitionAdapter -VMName $VMName -ErrorAction SilentlyContinue
        $currentMB = 0
        if ($gpu -and $gpu.MaxPartitionVRAM) {
            $currentMB = [math]::Round(($gpu.MaxPartitionVRAM / 1000000000) * 4096)
        }
        if ($VRAMMB -ne $currentMB) { $needsStop = $true }
    }

    if ($needsStop -and $vm.State -ne 'Off') {
        if (-not $ForceStop) {
            throw "Виртуальная машина '$VMName' должна быть выключена для изменения аппаратной конфигурации (CPU, RAM, GPU-PV)."
        }
        Write-Host "[*] Stopping VM '$VMName' for hardware reconfiguration..." -ForegroundColor Yellow
        Stop-VM -Name $VMName -TurnOff -Force -ErrorAction Stop
        $timeout = 20
        while ((Get-VM -Name $VMName).State -ne 'Off' -and $timeout -gt 0) {
            Start-Sleep -Seconds 1
            $timeout--
        }
        if ((Get-VM -Name $VMName).State -ne 'Off') {
            throw "Не удалось остановить виртуальную машину '$VMName'."
        }
    }

    # 1. CPU
    if ($CPUCount -gt 0 -and $CPUCount -ne $vm.ProcessorCount) {
        $maxCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
        if ($CPUCount -lt 1 -or $CPUCount -gt $maxCores) {
            throw "Количество ядер CPU ($CPUCount) должно быть в диапазоне от 1 до $maxCores."
        }
        Write-Host "[+] Setting vCPU count for ${VMName}: $CPUCount cores..." -ForegroundColor Green
        Set-VMProcessor -VMName $VMName -Count $CPUCount -ErrorAction Stop
    }

    # 2. RAM
    if ($RAMBytes -gt 0 -and $RAMBytes -ne $vm.MemoryStartup) {
        if ($RAMBytes -lt 512MB) {
            throw "Объем оперативной памяти должен быть не менее 512 МБ."
        }
        $maxRam = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        if ($RAMBytes -gt $maxRam) {
            throw "Объем оперативной памяти ($([math]::Round($RAMBytes / 1GB, 1)) ГБ) превышает объем физической памяти хоста ($([math]::Round($maxRam / 1GB, 1)) ГБ)."
        }
        Write-Host "[+] Setting Startup Memory for ${VMName}: $([math]::Round($RAMBytes / 1GB, 1)) GB..." -ForegroundColor Green
        Set-VMMemory -VMName $VMName -StartupBytes $RAMBytes -DynamicMemoryEnabled $false -ErrorAction Stop
    }

    # 3. GPU-PV VRAM
    if ($VRAMMB -ge 0) {
        if ($VRAMMB -gt 4096) {
            throw "Размер видеопамяти GPU-PV ($VRAMMB MB) превышает максимум хостовой видеокарты (4096 MB)."
        }
        $existingGpu = Get-VMGpuPartitionAdapter -VMName $VMName -ErrorAction SilentlyContinue
        $currentMB = 0
        if ($existingGpu -and $existingGpu.MaxPartitionVRAM) {
            $currentMB = [math]::Round(($existingGpu.MaxPartitionVRAM / 1000000000) * 4096)
        }

        if ($VRAMMB -ne $currentMB -or (-not $existingGpu -and $VRAMMB -gt 0)) {
            if ($VRAMMB -eq 0) {
                if ($existingGpu) {
                    Write-Host "[+] Removing GPU-PV partition adapter from $VMName..." -ForegroundColor Yellow
                    Remove-VMGpuPartitionAdapter -VMName $VMName -Confirm:$false -ErrorAction Stop
                }
            } else {
                if (-not $existingGpu) {
                    Write-Host "[+] Adding GPU-PV partition adapter to $VMName..." -ForegroundColor Green
                    Add-VMGpuPartitionAdapter -VMName $VMName -ErrorAction Stop
                }
                $vramUnits = [uint64]([double]$VRAMMB / 4096.0 * 1000000000.0)
                Write-Host "[+] Configuring GPU-PV VRAM: $VRAMMB MB ($vramUnits units) on $VMName..." -ForegroundColor Green
                Set-VMGpuPartitionAdapter -VMName $VMName `
                    -MinPartitionVRAM 1 `
                    -MaxPartitionVRAM $vramUnits `
                    -OptimalPartitionVRAM $vramUnits `
                    -MinPartitionCompute 1 `
                    -MaxPartitionCompute $vramUnits `
                    -OptimalPartitionCompute $vramUnits `
                    -MinPartitionDecode 1 `
                    -MaxPartitionDecode $vramUnits `
                    -OptimalPartitionDecode $vramUnits `
                    -MinPartitionEncode 1 `
                    -MaxPartitionEncode 18446744073709551615 `
                    -OptimalPartitionEncode 18446744073709551615 `
                    -ErrorAction Stop
            }
        }
    }

    $updatedVM = Get-VM -Name $VMName
    $updatedGpu = Get-VMGpuPartitionAdapter -VMName $VMName -ErrorAction SilentlyContinue
    $finalVRAM = 0
    if ($updatedGpu -and $updatedGpu.MaxPartitionVRAM) {
        $finalVRAM = [math]::Round(($updatedGpu.MaxPartitionVRAM / 1000000000) * 4096)
    }

    return [PSCustomObject]@{
        Success = $true
        VMName = $VMName
        ProcessorCount = $updatedVM.ProcessorCount
        MemoryStartupGB = [math]::Round($updatedVM.MemoryStartup / 1GB, 1)
        VRAMMB = $finalVRAM
    }
}

function Rename-GamingVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$OldVMName,
        [Parameter(Mandatory=$true)][string]$NewVMName
    )

    $OldVMName = $OldVMName.Trim()
    $NewVMName = $NewVMName.Trim()

    if ($OldVMName -eq $NewVMName) {
        return [PSCustomObject]@{ Success = $true; OldVMName = $OldVMName; NewVMName = $NewVMName; NoChange = $true }
    }

    if ([string]::IsNullOrWhiteSpace($NewVMName)) {
        throw "Новое имя виртуальной машины не может быть пустым."
    }

    if ($NewVMName -match '[\\/:*?"<>|]') {
        throw "Имя виртуальной машины содержит недопустимые символы (\ / : * ? `"` < > |)."
    }

    $targetVM = Get-VM -Name $OldVMName -ErrorAction SilentlyContinue
    if (-not $targetVM) {
        throw "Виртуальная машина '$OldVMName' не найдена в Hyper-V."
    }

    $existing = Get-VM -Name $NewVMName -ErrorAction SilentlyContinue
    if ($existing) {
        throw "Виртуальная машина с именем '$NewVMName' уже существует."
    }

    Write-Host "[+] Renaming Hyper-V VM from '$OldVMName' to '$NewVMName'..." -ForegroundColor Green
    Rename-VM -Name $OldVMName -NewName $NewVMName -ErrorAction Stop

    # Update proxy-profiles.json
    $cfg = Get-ProxyConfig
    if (-not $cfg.assignments) {
        $cfg | Add-Member -MemberType NoteProperty -Name "assignments" -Value ([PSCustomObject]@{}) -Force
    }
    $oldAssign = $cfg.assignments.$OldVMName
    $assignedIP = if ($oldAssign -and $oldAssign.ip) {
        $oldAssign.ip
    } elseif ($Script:VMIPMap -and $Script:VMIPMap.ContainsKey($OldVMName)) {
        $Script:VMIPMap[$OldVMName]
    } else {
        $null
    }
    $newAssign = [PSCustomObject]@{
        enabled   = if ($oldAssign) { [bool]$oldAssign.enabled } else { $false }
        profileId = if ($oldAssign) { $oldAssign.profileId } else { $null }
        ip        = $assignedIP
    }
    $cfg.assignments | Add-Member -MemberType NoteProperty -Name $NewVMName -Value $newAssign -Force
    if ($oldAssign) {
        $cfg.assignments.PSObject.Properties.Remove($OldVMName)
    }
    Save-ProxyConfig $cfg

    # Update $Script:VMIPMap
    if ($Script:VMIPMap) {
        if ($assignedIP) {
            $Script:VMIPMap[$NewVMName] = $assignedIP
        } elseif ($Script:VMIPMap.ContainsKey($OldVMName)) {
            $Script:VMIPMap[$NewVMName] = $Script:VMIPMap[$OldVMName]
        }
        if ($Script:VMIPMap.ContainsKey($OldVMName)) {
            $Script:VMIPMap.Remove($OldVMName)
        }
    }

    # Update guest C:\Setup\vmname.txt
    $vm = Get-VM -Name $NewVMName
    if ($vm.State -eq 'Running') {
        try {
            $cred = New-Object System.Management.Automation.PSCredential("Gamer", (New-Object System.Security.SecureString))
            Invoke-Command -VMName $NewVMName -Credential $cred -ScriptBlock {
                param($name)
                try {
                    if (-not (Test-Path "C:\Setup")) { New-Item -ItemType Directory -Path "C:\Setup" -Force | Out-Null }
                    Set-Content -Path "C:\Setup\vmname.txt" -Value $name -Encoding ASCII
                    Rename-Computer -NewName $name -Force -ErrorAction SilentlyContinue
                } catch {}
            } -ArgumentList $NewVMName -ErrorAction SilentlyContinue
        } catch {}
    } else {
        try {
            $vhd = (Get-VMHardDiskDrive -VMName $NewVMName -ErrorAction SilentlyContinue | Select-Object -First 1).Path
            if ($vhd -and (Test-Path $vhd)) {
                Update-VHDSetupFile -VHDPath $vhd -FileName "vmname.txt" -Content $NewVMName
            }
        } catch {
            Write-Warning "Offline vmname.txt update note: $_"
        }
    }

    # Rebuild Sing-box configuration
    Build-SingBoxConfig
    if (Get-Process sing-box -ErrorAction SilentlyContinue) {
        Start-ProxyEngine
    }

    return [PSCustomObject]@{
        Success = $true
        OldVMName = $OldVMName
        NewVMName = $NewVMName
    }
}

function Set-VMStaticIP {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$VMName,
        [Parameter(Mandatory=$true)][string]$IPAddress
    )

    $VMName = $VMName.Trim()
    $IPAddress = $IPAddress.Trim()

    if ($IPAddress -notmatch '^192\.168\.100\.(\d+)$') {
        throw "IP адрес '$IPAddress' не принадлежит сети 192.168.100.x (допустимый диапазон 192.168.100.2 - 192.168.100.254)."
    }

    $octet = [int]$Matches[1]
    if ($octet -lt 2 -or $octet -gt 254) {
        throw "Последний октет IP адреса ($octet) должен быть в диапазоне от 2 до 254 (1 зарезервирован под шлюз хоста)."
    }

    # Check for IP collisions across all configs, maps, and live adapters
    $cfg = Get-ProxyConfig
    $usedIps = @{}
    if ($cfg -and $cfg.assignments) {
        foreach ($prop in $cfg.assignments.PSObject.Properties) {
            if ($prop.Name -ne $VMName -and $prop.Value -and $prop.Value.ip) {
                $usedIps[$prop.Value.ip] = $prop.Name
            }
        }
    }
    if ($Script:VMIPMap) {
        foreach ($k in $Script:VMIPMap.Keys) {
            if ($k -ne $VMName -and $Script:VMIPMap[$k]) {
                if (-not $usedIps.ContainsKey($Script:VMIPMap[$k])) {
                    $usedIps[$Script:VMIPMap[$k]] = $k
                }
            }
        }
    }
    $allVMs = Get-VM -ErrorAction SilentlyContinue
    foreach ($v in $allVMs) {
        if ($v.Name -ne $VMName) {
            $liveIps = $v.NetworkAdapters.IPAddresses | Where-Object { $_ -like "192.168.100.*" }
            foreach ($lip in $liveIps) {
                if (-not $usedIps.ContainsKey($lip)) {
                    $usedIps[$lip] = $v.Name
                }
            }
        }
    }

    if ($usedIps.ContainsKey($IPAddress)) {
        throw "IP адрес '$IPAddress' уже используется виртуальной машиной '$($usedIps[$IPAddress])'."
    }

    Write-Host "[+] Configuring static IP '$IPAddress' for $VMName..." -ForegroundColor Green

    # Update guest filesystem and adapter
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State -eq 'Running') {
        try {
            $cred = New-Object System.Management.Automation.PSCredential("Gamer", (New-Object System.Security.SecureString))
            Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($newIp)
                try {
                    if (-not (Test-Path "C:\Setup")) { New-Item -ItemType Directory -Path "C:\Setup" -Force | Out-Null }
                    Set-Content -Path "C:\Setup\ip.txt" -Value $newIp -Encoding ASCII
                    $gamingNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                        $ips = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
                        $ips -like "192.168.100.*"
                    } | Select-Object -First 1
                    if (-not $gamingNic) {
                        $gamingNic = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.MacAddress -notlike "00-15-5D*" -and $_.Name -notlike "*Internet*" } | Select-Object -First 1
                    }
                    if ($gamingNic) {
                        & netsh interface ipv4 set address name="$($gamingNic.Name)" static $newIp 255.255.255.0 192.168.100.1 1
                    }
                } catch {}
            } -ArgumentList $IPAddress -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "PowerShell Direct guest IP update note: $_"
        }
    } else {
        $vhd = (Get-VMHardDiskDrive -VMName $VMName -ErrorAction Stop | Select-Object -First 1).Path
        if ($vhd -and (Test-Path $vhd)) {
            Update-VHDSetupFile -VHDPath $vhd -FileName "ip.txt" -Content $IPAddress
        }
    }

    # Update proxy-profiles.json
    if (-not $cfg.assignments) {
        $cfg | Add-Member -MemberType NoteProperty -Name "assignments" -Value ([PSCustomObject]@{}) -Force
    }
    if (-not $cfg.assignments.$VMName) {
        $newAssign = [PSCustomObject]@{ enabled = $false; profileId = $null; ip = $IPAddress }
        $cfg.assignments | Add-Member -MemberType NoteProperty -Name $VMName -Value $newAssign -Force
    } else {
        if (-not ($cfg.assignments.$VMName.PSObject.Properties['ip'])) {
            $cfg.assignments.$VMName | Add-Member -MemberType NoteProperty -Name "ip" -Value $IPAddress -Force
        } else {
            $cfg.assignments.$VMName.ip = $IPAddress
        }
    }
    Save-ProxyConfig $cfg

    # Update $Script:VMIPMap
    if ($Script:VMIPMap) {
        $Script:VMIPMap[$VMName] = $IPAddress
    }

    # Rebuild Sing-box configuration
    Build-SingBoxConfig
    if (Get-Process sing-box -ErrorAction SilentlyContinue) {
        Start-ProxyEngine
    }

    return [PSCustomObject]@{
        Success = $true
        VMName = $VMName
        IP = $IPAddress
    }
}

if ($MyInvocation.MyCommand.CommandType -eq 'Script' -and $ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Get-ProxyConfig, Save-ProxyConfig, Test-ProxyEndpoint, Build-SingBoxConfig, `
                                Start-ProxyEngine, Stop-ProxyEngine, Set-VMProxyRouting, Get-VMProxyState, Remove-ProxyProfile, `
                                Set-VMHardwareConfig, Rename-GamingVM, Set-VMStaticIP, Update-VHDSetupFile -ErrorAction SilentlyContinue
}
