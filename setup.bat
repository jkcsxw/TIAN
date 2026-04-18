@echo off
setlocal EnableDelayedExpansion

title Tian Setup

:: Check for PowerShell
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: PowerShell is required but was not found.
    echo Please install PowerShell from https://aka.ms/powershell
    pause
    exit /b 1
)

:: Get script directory
set "TIAN_DIR=%~dp0"
set "TIAN_DIR=%TIAN_DIR:~0,-1%"

:: Check PowerShell version (need 5.1+)
powershell -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -lt 5) { exit 1 }" >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: PowerShell 5.1 or later is required.
    echo Your version is too old. Please update Windows or install PowerShell 7.
    echo Download: https://aka.ms/powershell
    pause
    exit /b 1
)

:: Request elevation if not already admin (needed for some installs)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c cd /d \"%TIAN_DIR%\" && \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%TIAN_DIR%"

:: Launch the wizard in STA mode (required for WinForms)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%TIAN_DIR%\wizard\Main.ps1" -TianDir "%TIAN_DIR%"

if %errorlevel% neq 0 (
    echo.
    echo Setup encountered an error. Please check the log above.
    pause
)
