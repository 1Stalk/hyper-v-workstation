@echo off
title Hyper-V Workstation
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scripts\HyperV-Workstation.ps1"
if %errorlevel% neq 0 (
    echo.
    echo An error occurred while running Hyper-V Workstation.
    pause
)