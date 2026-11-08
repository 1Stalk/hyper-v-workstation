<#
.SYNOPSIS
    00-Download-Tools.ps1 - Automated Prerequisites & Third-Party Binaries Downloader.
.DESCRIPTION
    Prepares a fresh clone of the Hyper-V GPU-PV repository on a new machine.
    Downloads all required external dependencies into their proper project directories:
      1. SagerNet sing-box (host-side transparent proxy router) -> tools\sing-box\
      2. LizardByte Sunshine (guest game streaming host) -> staging\sunshine.msi
      3. MikeTheTech Virtual Display Driver (VDD) -> staging\VDD\VirtualDisplayDriver\
      4. Nefarius nefcon (driver installation CLI) -> staging\nefcon\
      5. Sysinternals VolumeId (NTFS volume serial randomizer) -> staging\Volumeid64.exe
      6. Moonlight Game Streaming Client (optional host client) -> tools\moonlight\
.PARAMETER Force
    Re-download and overwrite existing binaries even if already present.
.PARAMETER CheckOnly
    Only check presence and status of required tools without downloading.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

$RepoRoot = Split-Path $PSScriptRoot -Parent
$StagingDir = Join-Path $RepoRoot "staging"
$ToolsDir = Join-Path $RepoRoot "tools"
$SingBoxDir = Join-Path $ToolsDir "sing-box"
$MoonlightDir = Join-Path $ToolsDir "moonlight"
$IsoDir = Join-Path $RepoRoot "iso"
$SoftwareDir = Join-Path $RepoRoot "software\desktop"
$ConfigDir = Join-Path $RepoRoot "config"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Hyper-V GPU-PV Cluster - Automated Dependencies Downloader    " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Repo Root: $RepoRoot`n" -ForegroundColor Gray

# Ensure directory structure
$requiredDirs = @($StagingDir, $ToolsDir, $SingBoxDir, $MoonlightDir, $IsoDir, $SoftwareDir, $ConfigDir)
foreach ($dir in $requiredDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Ensure config template copy
$exampleConfig = Join-Path $ConfigDir "proxy-profiles.example.json"
$liveConfig = Join-Path $ConfigDir "proxy-profiles.json"
if (-not (Test-Path $liveConfig) -and (Test-Path $exampleConfig)) {
    Write-Host "[+] Initializing proxy configuration from template..." -ForegroundColor Green
    Copy-Item -Path $exampleConfig -Destination $liveConfig -Force
}

function Download-FileWithProgress([string]$url, [string]$destination) {
    Write-Host "    Downloading: $url -> $(Split-Path $destination -Leaf)" -ForegroundColor Gray
    $tempFile = "$destination.tmp"
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) HyperV-Deployment/1.0")
    try {
        $wc.DownloadFile($url, $tempFile)
        Move-Item -Path $tempFile -Destination $destination -Force
        Write-Host "    [OK] Downloaded successfully ($((Get-Item $destination).Length / 1MB | ForEach-Object { '{0:N2} MB' -f $_ }))" -ForegroundColor Green
    } finally {
        $wc.Dispose()
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }
}

# 1. Check / Download sing-box
Write-Host "[1/5] Checking Sing-box proxy engine..." -ForegroundColor Cyan
$singBoxExe = Join-Path $SingBoxDir "sing-box.exe"
if (-not $Force -and (Test-Path $singBoxExe)) {
    Write-Host "    [OK] sing-box.exe is already present." -ForegroundColor Green
} elseif ($CheckOnly) {
    Write-Host "    [MISSING] sing-box.exe is not installed." -ForegroundColor Yellow
} else {
    Write-Host "    Fetching latest sing-box release from GitHub..." -ForegroundColor Yellow
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/SagerNet/sing-box/releases/latest" -UserAgent "PowerShell"
        $asset = $release.assets | Where-Object { $_.name -like "*windows-amd64.zip" } | Select-Object -First 1
        if (-not $asset) { throw "sing-box windows-amd64.zip asset not found in release!" }

        $zipPath = Join-Path $SingBoxDir "sing-box.zip"
        Download-FileWithProgress -url $asset.browser_download_url -destination $zipPath
        
        Write-Host "    Extracting sing-box.exe..." -ForegroundColor Gray
        $extractDir = Join-Path $SingBoxDir "_extracted"
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        
        $foundExe = Get-ChildItem -Path $extractDir -Filter "sing-box.exe" -Recurse -File | Select-Object -First 1
        if ($foundExe) {
            Copy-Item -Path $foundExe.FullName -Destination $singBoxExe -Force
            # Check for any companion DLLs
            Get-ChildItem -Path $extractDir -Filter "*.dll" -Recurse -File | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $SingBoxDir -Force
            }
            Write-Host "    [+] sing-box.exe successfully installed." -ForegroundColor Green
        } else {
            throw "sing-box.exe not found in extracted archive!"
        }
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "    Failed to auto-download sing-box: $_"
        Write-Host "    Please download sing-box manually: https://github.com/SagerNet/sing-box/releases" -ForegroundColor Yellow
    }
}

# 2. Check / Download Sunshine MSI
Write-Host "`n[2/5] Checking Sunshine Game Streaming Host..." -ForegroundColor Cyan
$sunshineMsi = Join-Path $StagingDir "sunshine.msi"
if (-not $Force -and (Test-Path $sunshineMsi)) {
    Write-Host "    [OK] sunshine.msi is already present." -ForegroundColor Green
} elseif ($CheckOnly) {
    Write-Host "    [MISSING] sunshine.msi is not downloaded." -ForegroundColor Yellow
} else {
    Write-Host "    Fetching Sunshine installer from GitHub..." -ForegroundColor Yellow
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" -UserAgent "PowerShell"
        $asset = $release.assets | Where-Object { $_.name -like "Sunshine-Windows-AMD64-installer.msi" -or $_.name -like "*installer.msi" } | Select-Object -First 1
        if (-not $asset) {
            $asset = $release.assets | Where-Object { $_.name -like "*installer.exe" } | Select-Object -First 1
        }
        if (-not $asset) { throw "Sunshine installer asset not found in release!" }

        Download-FileWithProgress -url $asset.browser_download_url -destination $sunshineMsi
        Write-Host "    [+] sunshine.msi successfully staged." -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to auto-download Sunshine: $_"
        Write-Host "    Please download Sunshine manually: https://github.com/LizardByte/Sunshine/releases" -ForegroundColor Yellow
    }
}

# 3. Check / Download Virtual Display Driver (VDD)
Write-Host "`n[3/5] Checking Virtual Display Driver (VDD)..." -ForegroundColor Cyan
$vddDir = Join-Path $StagingDir "VDD\VirtualDisplayDriver"
$vddDll = Join-Path $vddDir "MttVDD.dll"
if (-not $Force -and (Test-Path $vddDll)) {
    Write-Host "    [OK] Virtual Display Driver is already present." -ForegroundColor Green
} elseif ($CheckOnly) {
    Write-Host "    [MISSING] Virtual Display Driver files not found." -ForegroundColor Yellow
} else {
    Write-Host "    Fetching Virtual Display Driver from GitHub..." -ForegroundColor Yellow
    try {
        $zipPath = Join-Path $StagingDir "VirtualDisplayDriver-x64.zip"
        # Download verified v24.10.27 release
        $vddUrl = "https://github.com/itsmikethetech/Virtual-Display-Driver/releases/download/24.10.27/VirtualDisplayDriver-x64.zip"
        Download-FileWithProgress -url $vddUrl -destination $zipPath
        
        Write-Host "    Extracting Virtual Display Driver..." -ForegroundColor Gray
        New-Item -ItemType Directory -Path $vddDir -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $vddDir -Force
        
        # Flatten directory if nested
        $nestedVdd = Get-ChildItem -Path $vddDir -Directory -Filter "VirtualDisplayDriver" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($nestedVdd) {
            Get-ChildItem -Path $nestedVdd.FullName | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $vddDir -Recurse -Force
            }
            Remove-Item -Path $nestedVdd.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "    [+] Virtual Display Driver successfully staged." -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to auto-download VDD: $_"
        Write-Host "    Please download Virtual-Display-Driver manually: https://github.com/itsmikethetech/Virtual-Display-Driver/releases" -ForegroundColor Yellow
    }
}

# 4. Check / Download NefCon
Write-Host "`n[4/5] Checking NefCon driver management CLI..." -ForegroundColor Cyan
$nefconExe = Join-Path $StagingDir "nefcon\x64\nefconw.exe"
if (-not $Force -and (Test-Path $nefconExe)) {
    Write-Host "    [OK] nefconw.exe is already present." -ForegroundColor Green
} elseif ($CheckOnly) {
    Write-Host "    [MISSING] nefconw.exe is not found." -ForegroundColor Yellow
} else {
    Write-Host "    Fetching nefcon release from GitHub..." -ForegroundColor Yellow
    try {
        $nefconZip = Join-Path $StagingDir "nefcon.zip"
        $nefconUrl = "https://github.com/nefarius/nefcon/releases/download/v1.21.0/nefcon_v1.21.0.zip"
        Download-FileWithProgress -url $nefconUrl -destination $nefconZip
        
        Write-Host "    Extracting nefcon..." -ForegroundColor Gray
        $nefconTarget = Join-Path $StagingDir "nefcon"
        New-Item -ItemType Directory -Path $nefconTarget -Force | Out-Null
        Expand-Archive -Path $nefconZip -DestinationPath $nefconTarget -Force
        Write-Host "    [+] nefcon successfully staged." -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to auto-download nefcon: $_"
        Write-Host "    Please download nefcon manually: https://github.com/nefarius/nefcon/releases" -ForegroundColor Yellow
    }
}

# 5. Check / Download Sysinternals VolumeId
Write-Host "`n[5/5] Checking Sysinternals VolumeId..." -ForegroundColor Cyan
$volExe = Join-Path $StagingDir "Volumeid64.exe"
if (-not $Force -and (Test-Path $volExe)) {
    Write-Host "    [OK] Volumeid64.exe is already present." -ForegroundColor Green
} elseif ($CheckOnly) {
    Write-Host "    [MISSING] Volumeid64.exe is not found." -ForegroundColor Yellow
} else {
    Write-Host "    Fetching VolumeId from Microsoft Sysinternals..." -ForegroundColor Yellow
    try {
        $volZip = Join-Path $StagingDir "VolumeId.zip"
        $volUrl = "https://download.sysinternals.com/files/VolumeId.zip"
        Download-FileWithProgress -url $volUrl -destination $volZip
        
        Write-Host "    Extracting Volumeid64.exe..." -ForegroundColor Gray
        $volExtractDir = Join-Path $StagingDir "_vol_tmp"
        Expand-Archive -Path $volZip -DestinationPath $volExtractDir -Force
        
        $foundVol64 = Get-ChildItem -Path $volExtractDir -Filter "Volumeid64.exe" -Recurse -File | Select-Object -First 1
        if ($foundVol64) {
            Copy-Item -Path $foundVol64.FullName -Destination $volExe -Force
            Write-Host "    [+] Volumeid64.exe successfully staged." -ForegroundColor Green
        } else {
            throw "Volumeid64.exe not found in extracted zip!"
        }
        Remove-Item $volExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $volZip -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "    Failed to auto-download VolumeId: $_"
        Write-Host "    Please download VolumeId manually: https://learn.microsoft.com/sysinternals/downloads/volumeid" -ForegroundColor Yellow
    }
}

# Optional Moonlight check on host
Write-Host "`n[*] Checking Moonlight client on host..." -ForegroundColor Gray
$installedMoonlight = "C:\Program Files\Moonlight Game Streaming\Moonlight.exe"
if (Test-Path $installedMoonlight) {
    Write-Host "    [OK] Moonlight installed in Program Files." -ForegroundColor Green
} else {
    Write-Host "    [!] Notice: Moonlight is not installed in standard directory." -ForegroundColor Yellow
    Write-Host "        Download Moonlight client: https://github.com/moonlight-stream/moonlight-qt/releases/latest" -ForegroundColor Gray
}

# Summary and Checklist
Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "                   PROJECT READINESS CHECK                      " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. ISO check
$foundIso = Get-ChildItem -Path $IsoDir -Filter "*.iso" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if ($foundIso) {
    Write-Host "[OK] Windows ISO detected: $($foundIso.Name) ($('{0:N2} GB' -f ($foundIso.Length / 1GB)))" -ForegroundColor Green
} else {
    Write-Host "[!] Action needed: Put your Windows 11 ISO into 'iso/' folder" -ForegroundColor Yellow
}

# 2. Desktop software check
$desktopItems = Get-ChildItem -Path $SoftwareDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike ".*" -and $_.Name -notlike "README*" -and $_.Extension -ne ".md" }
if ($desktopItems) {
    Write-Host "[OK] Desktop software tools ($($desktopItems.Count) item(s)) ready for guest deployment:" -ForegroundColor Green
    foreach ($df in $desktopItems) {
        Write-Host "     - $($df.Name)" -ForegroundColor Gray
    }
} else {
    Write-Host "[!] Recommended: Put installer exes (Chrome, RustDesk, etc.) into 'software\desktop\'" -ForegroundColor Yellow
}

# 3. GPU-PV Host check
$partGpu = Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue
if ($partGpu) {
    Write-Host "[OK] Host Partitionable GPU detected: $($partGpu.Name -join ', ')" -ForegroundColor Green
} else {
    Write-Host "[!] Note: No partitionable GPU detected. Make sure Hyper-V and NVIDIA drivers are installed." -ForegroundColor DarkGray
}

Write-Host "`nPrerequisites preparation complete! Next step: run scripts\01-Setup-Network.ps1" -ForegroundColor Green
