@echo off
:: Build the TIAN Windows installer
:: Delegates to build-installer.ps1 — see that file for full options.
setlocal

echo.
echo  Building TIAN installer...
echo.

powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%~dp0build-installer.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo [FAIL] Build failed. See output above.
    pause
    exit /b 1
)
