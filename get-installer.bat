@echo off
setlocal EnableDelayedExpansion

title TIAN — Download Installer

echo.
echo  ============================================================
echo   TIAN — Talk Is All you Need
echo   Downloading the Windows installer...
echo  ============================================================
echo.

:: Destination for the downloaded installer
set "DEST=%TEMP%\tian-setup.exe"

:: Download the latest release installer using PowerShell (built into Windows 7+)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { " ^
  "  $url = 'https://github.com/jkcsxw/TIAN/releases/latest/download/tian-setup.exe'; " ^
  "  Write-Host '  Connecting to GitHub...'; " ^
  "  Invoke-WebRequest -Uri $url -OutFile '%DEST%' -UseBasicParsing; " ^
  "  Write-Host '  Download complete.'; " ^
  "} catch { " ^
  "  Write-Host ('  ERROR: ' + $_.Exception.Message) -ForegroundColor Red; " ^
  "  exit 1 " ^
  "}"

if %ERRORLEVEL% neq 0 (
    echo.
    echo  Could not download the installer automatically.
    echo.
    echo  Please visit the link below and download the installer manually:
    echo.
    echo    https://github.com/jkcsxw/TIAN/releases/latest
    echo.
    pause
    :: Try to open the releases page in the browser as a fallback
    start "" "https://github.com/jkcsxw/TIAN/releases/latest"
    exit /b 1
)

echo.
echo  Launching installer...
echo.

:: Run the downloaded installer
start /wait "" "%DEST%"

:: Clean up temp file after installer exits
del /f /q "%DEST%" >nul 2>&1

exit /b 0
