Your task research what is best way to set up a gaming Virtual Machine with GPU Partitioning (GPU-PV) on this host system. 

SYSTEM CONTEXT:
- Host CPU: Xeon E5-2696v3 (Haswell).
- Host OS: Windows 11 Enterprise (25H2). Intel VT-x, VT-d, and SR-IOV are already ENABLED in BIOS. `Get-VMHostPartitionableGpu` successfully detects the GTX 1050 Ti.
- Target Guest OS: Windows 11 Pro (25H2).
- iso for Guest OS if needed: Windows 11 Business Editions 25H2 x64 ISO placed in `iso/` directory.

I need share just 1GB VRAM of my GPU to virtual machine

I need some a convenient way to open a virtual machine view, similar to VMware Workstation. In the future, the plan is to launch another 4 or 5 virtual machines with some VRAM of host gpu shared as well.

Save plan.md after research is complete in `docs/plan.md`.