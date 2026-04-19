@echo off
:: TIAN Test Runner — Windows
:: Runs all Pester (PowerShell) tests
setlocal EnableDelayedExpansion

echo.
echo ============================================================
echo  TIAN Test Runner  (Windows / Pester)
echo ============================================================
echo.

:: Ensure Pester v5 is available
powershell -NoProfile -Command "if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0')) { Write-Host 'Installing Pester v5...'; Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser }"

:: Run all .Tests.ps1 files under tests/ps/
powershell -NoProfile -STA -Command ^
  "Set-Location '%~dp0..'; ^
   Import-Module Pester -MinimumVersion 5.0; ^
   $config = New-PesterConfiguration; ^
   $config.Run.Path = '%~dp0ps'; ^
   $config.Run.Exit = $true; ^
   $config.Output.Verbosity = 'Detailed'; ^
   $config.TestResult.Enabled = $true; ^
   $config.TestResult.OutputPath = '%~dp0results-windows.xml'; ^
   Invoke-Pester -Configuration $config"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [FAIL] Some tests failed. See output above.
    exit /b 1
) else (
    echo.
    echo [PASS] All tests passed.
    exit /b 0
)
