<#
.SYNOPSIS
    Prepares and stages host NVIDIA drivers, Virtual Display Driver, and Sunshine for guest VM injection.
.DESCRIPTION
    Extracts active NVIDIA host driver packages (DriverStore, System32, SysWOW64),
    configures Virtual Display Driver with 720p @ 60Hz default, and prepares
    guest setup tools ready for offline injection into the VM VHDX.
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

# 4. Configure Virtual Display Driver with 720p 60Hz default
Write-Host "[+] Configuring Virtual Display Driver (720p @ 60Hz default)..." -ForegroundColor Cyan
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

# 7. Create guest auto-configuration script (install_guest_tools.ps1)
Write-Host "[+] Creating guest setup automation script (install_guest_tools.ps1)..." -ForegroundColor Cyan
$guestScript = @'
# Guest Automated Setup Script executed on first logon
$ErrorActionPreference = "Continue"

Start-Transcript -Path "C:\Setup\guest_install.log" -Append

Write-Host "=== Starting Guest Environment Initialization ===" -ForegroundColor Cyan

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
    # Set default admin credentials (admin / admin1234)
    & $sunshineExe --creds admin admin1234
    
    # Configure auto-start service
    $serviceBat = "C:\Program Files\LizardByte\Sunshine\scripts\install-service.bat"
    if (Test-Path $serviceBat) {
        & cmd.exe /c "`"$serviceBat`""
    } else {
        # Fallback sc.exe
        sc.exe create SunshineService binPath= "\"C:\Program Files\LizardByte\Sunshine\tools\sunshinesvc.exe\"" start= auto DisplayName= "Sunshine Service"
        sc.exe start SunshineService
    }
}

# 5. Open Sunshine Firewall Ports in Guest
Write-Host "[+] Adding Firewall Rules for Sunshine..."
New-NetFirewallRule -DisplayName "Sunshine TCP" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 47984,47989,47990,48010 -Profile Any -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Sunshine UDP" -Direction Inbound -Action Allow -Protocol UDP -LocalPort 47998,47999,48000,48002,48010 -Profile Any -ErrorAction SilentlyContinue | Out-Null

# 6. Set Static Network IP (Configured by Unattend or Fallback)
Write-Host "[+] Setting up Static IP..."
$netAdapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -or $_.Name -like "*Ethernet*" } | Select-Object -First 1
if ($netAdapter) {
    # Read target IP if saved in C:\Setup\ip.txt
    $ip = "192.168.100.11"
    if (Test-Path "C:\Setup\ip.txt") {
        $ip = (Get-Content "C:\Setup\ip.txt").Trim()
    }
    
    Get-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceIndex $netAdapter.ifIndex -IPAddress $ip -PrefixLength 24 -DefaultGateway "192.168.100.1" -ErrorAction SilentlyContinue | Out-Null
    Set-DnsClientServerAddress -InterfaceIndex $netAdapter.ifIndex -ServerAddresses ("1.1.1.1", "8.8.8.8") -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[+] Configured IP: $ip"
}

# 7. Enable Remote Desktop
Write-Host "[+] Enabling Remote Desktop..."
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# 8. Set High Performance Power Plan
Write-Host "[+] Setting High Performance Power Plan..."
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

Write-Host "=== Guest Initialization Finished ===" -ForegroundColor Green
Stop-Transcript
'@
Set-Content -Path "$guestSetupStaging\install_guest_tools.ps1" -Value $guestScript -Encoding UTF8

Write-Host "=== Staging Complete! ===" -ForegroundColor Green
