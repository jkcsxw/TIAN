@echo off
setlocal EnableDelayedExpansion

set "TIAN_DIR=%~dp0"
set "TIAN_DIR=%TIAN_DIR:~0,-1%"

where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: PowerShell is required but was not found.
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TIAN_DIR%\cli\tian.ps1" -TianDir "%TIAN_DIR%" %*
