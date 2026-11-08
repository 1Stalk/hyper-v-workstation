# Hyper-V Workstation

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2011%20%7C%20Server-0078d4.svg)](https://microsoft.com)
[![Hyper-V](https://img.shields.io/badge/Hyper--V-GPU--PV-success.svg)](https://learn.microsoft.com/virtualization/hyper-v-on-windows/)

A lightweight, automated management platform for high-performance Windows 11 virtual machines on **Hyper-V GPU Partitioning (GPU-PV)**.

---

## Features

- **VMware-style GUI Console**: Built-in management interface with 1-click VM actions (Power, Reset, HW settings, VM rename).
- **Moonlight Streaming**: Windowed 60 FPS, ultra-low latency desktop streaming with raw mouse input capture.
- **Fast Differencing Cloning**: Deploy new ready-to-use virtual machines in ~20 seconds using VHDX differencing disks.
- **Anti-VM Hardware Spoofing**: Built-in randomizer for SMBIOS, Motherboard/Chassis serials, System UUID, MAC addresses, SCSI disk IDs, and Windows registry identifiers.
- **Host-Side SOCKS5 Proxy Router**: Per-VM transparent routing via Sing-box with DNS leak prevention and hardware kill-switch.
- **Dynamic Guest Provisioning**: Automatic deployment of software installers (`software/desktop/`) to guest public desktops without manual copying.

---

## Repository Structure

```text
hyper-v-workstation/
├── config/
│   ├── proxy-profiles.example.json   # Template for SOCKS5 proxy configurations
│   └── README.md                     # Proxy subsystem notes
├── docs/
│   ├── hardware-spoofing-research.md # Hyper-V GPU-PV anti-detection research
│   ├── plan.md                       # Resource calculations and architecture plan
│   └── prompt.md                     # Project background notes
├── iso/
│   ├── .gitkeep
│   └── README.md                     # Place Windows 11 ISO here
├── scripts/
│   ├── guest/                        # In-guest maintenance scripts
│   │   ├── ensure_static_ip.ps1      # Network watchdog and LSA auth service
│   │   ├── Guest-HyperV-CleanID.ps1  # In-guest identifier randomizer
│   │   ├── Verify-HWID.ps1           # HWID audit and verification script
│   │   └── README.md                 # Guest utilities documentation
│   ├── 00-Download-Tools.ps1         # Automated prerequisite downloader
│   ├── 01-Setup-Network.ps1          # Virtual switch and WinNAT setup
│   ├── 02-Prepare-Drivers.ps1        # GPU driver staging & VDD/Sunshine setup
│   ├── 03-Build-GamingVM.ps1         # Offline DISM builder for master VHDX (150 GB)
│   ├── 04-Configure-GPU-PV.ps1       # Deploys Gaming-VM1 (Differencing VHDX + GPU slice)
│   ├── 05-Clone-VM.ps1               # Fast cloning script for additional VMs
│   ├── Host-HyperV-Randomize.ps1     # Host-side hardware spoofing engine
│   ├── Host-Proxy-Manager.ps1        # Host-side SOCKS5 proxy router manager
│   └── HyperV-Workstation.ps1        # WPF management GUI
├── software/
│   └── desktop/
│       ├── .gitkeep
│       └── README.md                 # Place guest desktop installers here
├── staging/
│   ├── .gitkeep
│   └── README.md                     # Temporary staging folder for driver injection
├── tools/
│   └── sing-box/
│       ├── LICENSE
│       └── README.md                 # Sing-box binary instructions
├── .gitignore                        # Strict rules excluding binaries, ISOs, and secrets
├── LICENSE                           # MIT License
├── README.md                         # Project documentation
├── Start-HyperV-Workstation.cmd      # Primary launcher shortcut
└── Start-HyperV-Workstation.bat      # Fallback launcher script
```

---

## Requirements

- **Host OS**: Windows 11 Pro / Enterprise / Education (24H2/25H2) or Windows Server 2022/2025.
- **Virtualization**: Intel VT-x / VT-d or AMD-V / IOMMU enabled in BIOS/UEFI.
- **CPU**: Support for POPCNT and SSE4.2 instructions (required by Windows 11 24H2+).
- **GPU**: NVIDIA GPU with WDDM driver supporting GPU Partitioning (`Get-VMHostPartitionableGpu`).
- **Memory**: 16 GB RAM minimum (32–64 GB recommended for multiple concurrent VMs).

---

## Quick Start

Run PowerShell as **Administrator**:

### 1. Clone the repository
```powershell
git clone https://github.com/1Stalk/hyper-v-workstation.git
cd hyper-v-workstation
```

### 2. Download dependencies
```powershell
powershell -ExecutionPolicy Bypass -File scripts\00-Download-Tools.ps1
```
This automatically fetches `sing-box`, `sunshine`, `Virtual Display Driver (VDD)`, `nefcon`, and `VolumeId`.

### 3. Add Windows 11 ISO & Desktop Software
- Place your Windows 11 ISO (Pro/Business edition) into `iso/`.
- *(Optional)* Place application installers (Chrome, RustDesk, RealVNC, etc.) into `software/desktop/`.

### 4. Setup Host Network
```powershell
powershell -ExecutionPolicy Bypass -File scripts\01-Setup-Network.ps1
```
Configures internal switch `VM-Gaming-Switch` (`192.168.100.1/24`) and WinNAT.

### 5. Stage GPU Drivers
```powershell
powershell -ExecutionPolicy Bypass -File scripts\02-Prepare-Drivers.ps1
```
Extracts host NVIDIA drivers and prepares the guest installer package.

### 6. Build Master Image & Deploy First VM
```powershell
# Create master VHDX via offline DISM (takes ~3-5 mins)
powershell -ExecutionPolicy Bypass -File scripts\03-Build-GamingVM.ps1

# Provision first VM (Gaming-VM1) with 1 GB VRAM slice
powershell -ExecutionPolicy Bypass -File scripts\04-Configure-GPU-PV.ps1
```

### 7. Launch Console
Double-click `Start-HyperV-Workstation.cmd` or run:
```powershell
powershell -ExecutionPolicy Bypass -STA -File scripts\HyperV-Workstation.ps1
```

---

## License

This project is licensed under the [MIT License](LICENSE). Third-party tools (`sing-box`, `Sunshine`, `Virtual Display Driver`, `nefcon`, `VolumeId`) retain their original licenses.
