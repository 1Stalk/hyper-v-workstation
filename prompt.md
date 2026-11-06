Your task research what is best way to set up a gaming Virtual Machine with GPU Partitioning (GPU-PV) on this host system. 

SYSTEM CONTEXT:
- Host CPU: Xeon E5-2696v3 (Haswell).
- Host OS: Windows 11 Enterprise (25H2). Intel VT-x, VT-d, and SR-IOV are already ENABLED in BIOS. `Get-VMHostPartitionableGpu` successfully detects the GTX 1050 Ti.
- Target Guest OS: Windows 11 Pro (25H2).
- iso for Guest OS if needed `C:\Users\server1\Desktop\localserver1\ru-ru_windows_11_business_editions_version_25h2_updated_jan_2026_x64_dvd_d869ebf3.iso`

I need share just 1GB VRAM of my GPU to virtual machine

I need some a convenient way to open a virtual machine view, similar to VMware Workstation. In the future, the plan is to launch another 4 or 5 virtual machines with some VRAM of host gpu shared as well.

Save plan.md after research is complete here C:\Users\server1\Desktop\Hyper-V