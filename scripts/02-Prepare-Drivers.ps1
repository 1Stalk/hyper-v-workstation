<#
.SYNOPSIS
    Prepares and stages host NVIDIA drivers, Virtual Display Driver, Sunshine, and Anti-VM HWID Spoofing tools.
.DESCRIPTION
    Extracts active NVIDIA host driver packages (DriverStore, System32, SysWOW64),
    configures Virtual Display Driver with 1024x768 @ 60Hz default, stages new desktop tools
    (Chrome, RealVNC, Winhance, WinRAR), Volumeid64, and HWID audit/spoofing scripts ready for
    offline injection into VM VHDX. AntiOS is completely removed and superseded.
#>

[CmdletBinding()]
param(
    [string]$StagingRoot = "C:\Users\server1\Desktop\Hyper-V\staging"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Staging GPU-PV Drivers and Guest Packages ===" -ForegroundColor Cyan

$driverStaging = Join-Path $StagingRoot "drivers"
$guestSetupStaging = Join-Path $StagingRoot "guest_setup"

New-Item -ItemType Directory -Path "$driverStaging\HostDriverStore\FileRepository" -Force | Out-Null
New-Item -ItemType Directory -Path "$driverStaging\System32" -Force | Out-Null
New-Item -ItemType Directory -Path "$driverStaging\SysWOW64" -Force | Out-Null
New-Item -ItemType Directory -Path $guestSetupStaging -Force | Out-Null

# 1. Locate NVIDIA DriverStore repositories on host
Write-Host "[+] Scanning DriverStore for NVIDIA display drivers..." -ForegroundColor Cyan
$nvRepos = Get-ChildItem "C:\Windows\System32\DriverStore\FileRepository" -Directory -Filter "nv_disp*"
if (-not $nvRepos) {
    throw "No NVIDIA display driver found in DriverStore\FileRepository!"
}

foreach ($repo in $nvRepos) {
    Write-Host "[+] Staging DriverStore repository: $($repo.Name)" -ForegroundColor Green
    $dest = Join-Path "$driverStaging\HostDriverStore\FileRepository" $repo.Name
    Copy-Item -Path $repo.FullName -Destination $dest -Recurse -Force
}

# 2. Copy System32 NVIDIA files
Write-Host "[+] Staging System32 NVIDIA libraries (nv*.*)..." -ForegroundColor Cyan
$sys32NvFiles = Get-ChildItem "C:\Windows\System32\nv*.*" -File -ErrorAction SilentlyContinue
foreach ($f in $sys32NvFiles) {
    Copy-Item -Path $f.FullName -Destination "$driverStaging\System32\$($f.Name)" -Force
}
Write-Host "    Staged $($sys32NvFiles.Count) System32 files." -ForegroundColor Gray

# 3. Copy SysWOW64 NVIDIA files
Write-Host "[+] Staging SysWOW64 NVIDIA libraries (nv*.*)..." -ForegroundColor Cyan
$syswowNvFiles = Get-ChildItem "C:\Windows\SysWOW64\nv*.*" -File -ErrorAction SilentlyContinue
foreach ($f in $syswowNvFiles) {
    Copy-Item -Path $f.FullName -Destination "$driverStaging\SysWOW64\$($f.Name)" -Force
}
Write-Host "    Staged $($syswowNvFiles.Count) SysWOW64 files." -ForegroundColor Gray

# 4. Configure Virtual Display Driver with 1024x768 60Hz default
Write-Host "[+] Configuring Virtual Display Driver (1024x768 @ 60Hz default)..." -ForegroundColor Cyan
$vddSource = Join-Path $StagingRoot "VDD\VirtualDisplayDriver"
if (-not (Test-Path $vddSource)) {
    throw "VDD source folder not found at $vddSource"
}

$vddTarget = Join-Path $guestSetupStaging "VDD"
New-Item -ItemType Directory -Path $vddTarget -Force | Out-Null
Copy-Item -Path "$vddSource\*" -Destination $vddTarget -Recurse -Force

# Write customized vdd_settings.xml with 1024x768 @ 60Hz default
$vddXml = @"
<?xml version='1.0' encoding='utf-8'?>
<vdd_settings>
    <monitors>
        <count>1</count>
    </monitors>
    <gpu>
        <friendlyname>default</friendlyname>
    </gpu>
    <resolutions>
        <resolution>
            <width>1024</width>
            <height>768</height>
            <refresh_rate>60</refresh_rate>
        </resolution>
        <resolution>
            <width>1280</width>
            <height>720</height>
            <refresh_rate>60</refresh_rate>
        </resolution>
        <resolution>
            <width>1920</width>
            <height>1080</height>
            <refresh_rate>60</refresh_rate>
        </resolution>
    </resolutions>
    <options>
        <CustomEdid>false</CustomEdid>
        <PreventSpoof>false</PreventSpoof>
        <EdidCeaOverride>false</EdidCeaOverride>
        <HardwareCursor>true</HardwareCursor>
        <SDR10bit>false</SDR10bit>
        <HDRPlus>false</HDRPlus>
        <logging>false</logging>
        <debuglogging>false</debuglogging>
    </options>
</vdd_settings>
"@
Set-Content -Path "$vddTarget\vdd_settings.xml" -Value $vddXml -Encoding UTF8

# 5. Copy NefCon to guest setup
Write-Host "[+] Staging NefCon..." -ForegroundColor Cyan
$nefconSource = Join-Path $StagingRoot "nefcon"
$nefconTarget = Join-Path $guestSetupStaging "nefcon"
New-Item -ItemType Directory -Path $nefconTarget -Force | Out-Null
Copy-Item -Path "$nefconSource\*" -Destination $nefconTarget -Recurse -Force

# 6. Copy Sunshine MSI to guest setup
Write-Host "[+] Staging Sunshine installer..." -ForegroundColor Cyan
$sunshineMsiSource = Join-Path $StagingRoot "sunshine.msi"
Copy-Item -Path $sunshineMsiSource -Destination "$guestSetupStaging\sunshine.msi" -Force

# 7. Stage new desktop tools from new_system
Write-Host "[+] Staging new desktop tools from new_system..." -ForegroundColor Cyan
$sourceNewSystem = "C:\Users\server1\Desktop\localserver1\new_system"
$destDesktopTools = Join-Path $guestSetupStaging "desktop_tools"
New-Item -ItemType Directory -Path $destDesktopTools -Force | Out-Null
if (Test-Path $sourceNewSystem) {
    Copy-Item -Path "$sourceNewSystem\*" -Destination $destDesktopTools -Force
    Write-Host "    Staged desktop tools from $sourceNewSystem" -ForegroundColor Gray
}

# 8. Stage Sysinternals Volumeid64 and HWID Spoofing/Verification scripts
Write-Host "[+] Staging Sysinternals Volumeid64 and HWID scripts..." -ForegroundColor Cyan
$volSource = Join-Path $StagingRoot "Volumeid64.exe"
if (Test-Path $volSource) {
    Copy-Item -Path $volSource -Destination "$guestSetupStaging\Volumeid64.exe" -Force
}
$verifyScript = "C:\Users\server1\Desktop\Hyper-V\.example\Verify-HWID.ps1"
if (Test-Path $verifyScript) {
    Copy-Item -Path $verifyScript -Destination "$guestSetupStaging\Verify-HWID.ps1" -Force
}
$cleanIdScript = "C:\Users\server1\Desktop\Hyper-V\.example\Guest-HyperV-CleanID.ps1"
if (Test-Path $cleanIdScript) {
    Copy-Item -Path $cleanIdScript -Destination "$guestSetupStaging\Guest-HyperV-CleanID.ps1" -Force
}

# 9. Create ensure_static_ip.ps1
$ensureNetScript = @'
# Ensure-GamingNetwork - Guaranteed static IP watchdog for Hyper-V WinNAT
$setupDir = "C:\Setup"
$targetIp = "192.168.100.11"
if (Test-Path "$setupDir\ip.txt") {
    $val = (Get-Content "$setupDir\ip.txt" -Raw).Trim()
    if ($val -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $targetIp = $val }
}
$gateway = "192.168.100.1"

$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.HardwareInterface }
foreach ($nic in $adapters) {
    $ipv4 = Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $targetIp }
    if (-not $ipv4) {
        & netsh interface ipv4 set address name="$($nic.Name)" static $targetIp 255.255.255.0 $gateway 1
        & netsh interface ipv4 set dns name="$($nic.Name)" static 1.1.1.1 primary
        & netsh interface ipv4 add dns name="$($nic.Name)" 8.8.8.8 index=2
        Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
    }
}
'@
[System.IO.File]::WriteAllText("$guestSetupStaging\ensure_static_ip.ps1", $ensureNetScript, [System.Text.UTF8Encoding]::new($true))

# 10. Create guest auto-configuration script (install_guest_tools.ps1)
Write-Host "[+] Creating guest setup automation script (install_guest_tools.ps1)..." -ForegroundColor Cyan
$guestScript = @'
# Guest Automated Setup Script executed on first logon
$ErrorActionPreference = "Continue"

# Auto-elevate if not running as Administrator
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Start-Transcript -Path "C:\Setup\guest_install.log" -Append

Write-Host "=== Starting Guest Environment Initialization ===" -ForegroundColor Cyan

# 0. Sync ComputerName if target saved in C:\Setup\vmname.txt
if (Test-Path "C:\Setup\vmname.txt") {
    $targetName = (Get-Content "C:\Setup\vmname.txt").Trim()
    if ($targetName -and $env:COMPUTERNAME -ne $targetName) {
        Write-Host "[+] Setting ComputerName to $targetName..."
        Rename-Computer -NewName $targetName -Force -ErrorAction SilentlyContinue
    }
}

# 1. Install VDD Driver Certificates
Write-Host "[+] Installing VDD Certificates..."
if (Test-Path "C:\Setup\VDD\Virtual_Display_Driver.cer") {
    certutil -addstore "Root" "C:\Setup\VDD\Virtual_Display_Driver.cer"
    certutil -addstore "TrustedPublisher" "C:\Setup\VDD\Virtual_Display_Driver.cer"
}

# 2. Install VDD Device using NefCon
Write-Host "[+] Installing Virtual Display Driver Device..."
$nefcon = "C:\Setup\nefcon\x64\nefconw.exe"
if (Test-Path $nefcon) {
    & $nefcon install "C:\Setup\VDD\MttVDD.inf" "Root\MttVDD"
    Start-Sleep -Seconds 5
}

# Copy vdd_settings.xml to standard locations
New-Item -ItemType Directory -Path "C:\VirtualDisplayDriver" -Force -ErrorAction SilentlyContinue | Out-Null
Copy-Item -Path "C:\Setup\VDD\vdd_settings.xml" -Destination "C:\VirtualDisplayDriver\vdd_settings.xml" -Force -ErrorAction SilentlyContinue

# 3. Install Sunshine
Write-Host "[+] Installing Sunshine..."
$sunshineMsi = "C:\Setup\sunshine.msi"
if (Test-Path $sunshineMsi) {
    Start-Process msiexec.exe -ArgumentList "/i `"$sunshineMsi`" /qn /norestart" -Wait
    Start-Sleep -Seconds 5
}

# 4. Configure Sunshine Credentials and Service
Write-Host "[+] Configuring Sunshine Service and Admin Credentials..."
$sunshineExe = "C:\Program Files\LizardByte\Sunshine\sunshine.exe"
if (Test-Path $sunshineExe) {
    & $sunshineExe --creds admin admin1234
    
    $serviceBat = "C:\Program Files\LizardByte\Sunshine\scripts\install-service.bat"
    if (Test-Path $serviceBat) {
        & cmd.exe /c "`"$serviceBat`""
    } else {
        sc.exe create SunshineService binPath= "\"C:\Program Files\LizardByte\Sunshine\tools\sunshinesvc.exe\"" start= auto DisplayName= "Sunshine Service"
        sc.exe start SunshineService
    }
}

# 5. Open Sunshine Firewall Ports in Guest
Write-Host "[+] Adding Firewall Rules for Sunshine..."
New-NetFirewallRule -DisplayName "Sunshine TCP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 47984,47989,47990,48010 -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Sunshine UDP" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 47998,47999,48000,48002,48010 -Profile Any -ErrorAction SilentlyContinue | Out-Null

# 6. Set Static Network IP and register watchdog
Write-Host "[+] Configuring Static Network IP..."
$ip = "192.168.100.11"
if (Test-Path "C:\Setup\ip.txt") {
    $ip = (Get-Content "C:\Setup\ip.txt").Trim()
}

$netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.HardwareInterface } | Select-Object -First 1
if ($netAdapter) {
    Enable-NetAdapter -Name $netAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    & netsh interface ipv4 set address name="$($netAdapter.Name)" static $ip 255.255.255.0 192.168.100.1 1
    & netsh interface ipv4 set dns name="$($netAdapter.Name)" static 1.1.1.1 primary
    & netsh interface ipv4 add dns name="$($netAdapter.Name)" 8.8.8.8 index=2
    Set-NetIPInterface -InterfaceIndex $netAdapter.ifIndex -Dhcp Disabled -ErrorAction SilentlyContinue
    Write-Host "[+] Configured IP: $ip"
}

# Register network watchdog task
try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\Setup\ensure_static_ip.ps1"
    $triggerBoot = New-ScheduledTaskTrigger -AtStartup
    $triggerRepeat = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "Ensure-GamingNetwork" -Action $action -Trigger @($triggerBoot, $triggerRepeat) -Principal $taskPrincipal -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[+] Registered Ensure-GamingNetwork scheduled task"
} catch {
    Write-Warning "Could not register network watchdog task: $_"
}

# 7. Enable Remote Desktop
Write-Host "[+] Enabling Remote Desktop..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# 8. Set High Performance Power Plan & Disable Sleep/Hibernation
Write-Host "[+] Setting High Performance Power Plan & Disabling Sleep/Hibernation..."
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
powercfg /change monitor-timeout-ac 0 2>$null
powercfg /change standby-timeout-ac 0 2>$null
powercfg /change hibernate-timeout-ac 0 2>$null
powercfg -h off 2>$null

# 9. Purge any AntiOS leftovers and deploy tools to Desktop
Write-Host "[+] Cleaning AntiOS leftovers if any..."
Get-ChildItem -Path "C:\Users" -Recurse -Filter "*AntiOS*" -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Setup" -Filter "*AntiOS*" -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

$desktopTargets = @(
    "C:\Users\Public\Desktop",
    "C:\Users\Default\Desktop"
)
if (Test-Path "C:\Users\Gamer") {
    $desktopTargets += "C:\Users\Gamer\Desktop"
}
$userDesktop = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Desktop)
if ($userDesktop -and ($desktopTargets -notcontains $userDesktop)) {
    $desktopTargets += $userDesktop
}

foreach ($targetDir in $desktopTargets) {
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path "C:\Setup\desktop_tools") {
        Copy-Item -Path "C:\Setup\desktop_tools\*" -Destination $targetDir -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "C:\Setup\Verify-HWID.ps1") {
        Copy-Item -Path "C:\Setup\Verify-HWID.ps1" -Destination "$targetDir\Verify-HWID.ps1" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "C:\Setup\Guest-HyperV-CleanID.ps1") {
        Copy-Item -Path "C:\Setup\Guest-HyperV-CleanID.ps1" -Destination "$targetDir\Guest-HyperV-CleanID.ps1" -Force -ErrorAction SilentlyContinue
    }
    $hwidBat = "@echo off`r`ntitle Verify-HWID`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\Setup\Verify-HWID.ps1`"`r`npause`r`n"
    [System.IO.File]::WriteAllText("$targetDir\Verify-HWID.bat", $hwidBat, [System.Text.Encoding]::ASCII)
    
    $cleanBat = "@echo off`r`ntitle Guest-CleanID`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\Setup\Guest-HyperV-CleanID.ps1`"`r`npause`r`n"
    [System.IO.File]::WriteAllText("$targetDir\Guest-CleanID.bat", $cleanBat, [System.Text.Encoding]::ASCII)
}

# 10. VolumeID Randomization
$volExe = "C:\Setup\Volumeid64.exe"
if (Test-Path $volExe) {
    try {
        $chars = "0123456789ABCDEF".ToCharArray()
        $h1 = -join ($chars | Get-Random -Count 4)
        $h2 = -join ($chars | Get-Random -Count 4)
        $newVol = "$h1-$h2"
        Write-Host "[+] Randomizing C: Volume ID to $newVol..."
        & $volExe /accepteula C: $newVol 2>&1 | Out-Null
    } catch {
        Write-Warning "Volumeid execution notice: $_"
    }
}

# 11. Apply Winhance UI & Privacy Tweaks
Write-Host "[+] Applying UI and Privacy Tweaks..."
New-Item -Path "HKCU:\Software\Classes\CLSID\{86caaa31-5b10-4b0d-8860-e3430144d436}\InprocServer32" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Classes\CLSID\{86caaa31-5b10-4b0d-8860-e3430144d436}\InprocServer32" -Name "(default)" -Value "" -Force -ErrorAction SilentlyContinue

New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideIcons" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "MaxTelemetryAllowed" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

Get-Service "DiagTrack" -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
Get-Service "WerSvc" -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
Get-Service "SysMain" -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue

Write-Host "=== Guest Initialization Finished ===" -ForegroundColor Green
Stop-Transcript
'@
[System.IO.File]::WriteAllText("$guestSetupStaging\install_guest_tools.ps1", $guestScript, [System.Text.UTF8Encoding]::new($true))

Write-Host "=== Staging Complete! ===" -ForegroundColor Green
