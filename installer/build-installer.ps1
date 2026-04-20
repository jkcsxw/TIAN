# Build the TIAN Windows installer (.exe)
# Requires Inno Setup 6 - https://jrsoftware.org/isdl.php
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1
#
# Options:
#   -Version "1.2.3"            Override the version embedded in the installer
#   -Sign                       Code-sign the output exe
#   -CertificatePath "cert.pfx" Path to a PFX file used by signtool
#   -CertificatePassword "..."  Password for the PFX file
#   -TimestampUrl "http://..."  RFC 3161 timestamp URL (defaults to DigiCert)

param(
    [string]$Version,
    [switch]$Sign,
    [string]$CertificatePath,
    [string]$CertificatePassword,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Locate Inno Setup compiler

function Find-Iscc {
    # 1. Already on PATH
    $onPath = Get-Command iscc -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # 2. Default install locations
    $candidates = @(
        "$env:ProgramFiles\Inno Setup 6\iscc.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\iscc.exe",
        "$env:ProgramFiles\Inno Setup 5\iscc.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Find-SignTool {
    $onPath = Get-Command signtool -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\signtool.exe",
        "$env:ProgramFiles\Windows Kits\10\bin\x64\signtool.exe",
        "$env:ProgramFiles(x86)\Windows Kits\10\bin\x64\signtool.exe",
        "$env:ProgramFiles\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe",
        "$env:ProgramFiles(x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    return $null
}

# Extract version from .iss file

function Get-IssVersion {
    param([string]$IssFile)
    $content = Get-Content $IssFile -Raw -ErrorAction SilentlyContinue
    if ($content -match '#define AppVersion\s+"([^"]+)"') { return $Matches[1] }
    return "1.0.0"
}

# Main build logic

function Invoke-Build {
    param(
        [string]$BuildVersion,
        [switch]$BuildSign,
        [string]$BuildCertificatePath,
        [string]$BuildCertificatePassword,
        [string]$BuildTimestampUrl = 'http://timestamp.digicert.com',
        [string]$ScriptRoot = $PSScriptRoot
    )

    $IssFile = Join-Path $ScriptRoot "tian-setup.iss"
    $DistDir = Join-Path $ScriptRoot "dist"

    $iscc = Find-Iscc
    if (-not $iscc) {
        Write-Host ""
        Write-Host "Inno Setup 6 not found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Install it with winget:"
        Write-Host "  winget install JRSoftware.InnoSetup" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Or download from: https://jrsoftware.org/isdl.php" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }

    Write-Host "Inno Setup compiler: $iscc" -ForegroundColor DarkGray

    if (-not $BuildVersion) { $BuildVersion = Get-IssVersion $IssFile }

    Write-Host "Building TIAN installer v$BuildVersion ..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

    $compileArgs = @(
        "/DAppVersion=$BuildVersion",
        "/O$DistDir",
        $IssFile
    )

    Push-Location $ScriptRoot
    try {
        & $iscc @compileArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "iscc exited with code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }

    $exePath = Join-Path $DistDir "tian-setup-$BuildVersion.exe"
    if (-not (Test-Path $exePath)) {
        Write-Host "Expected output not found: $exePath" -ForegroundColor Red
        exit 1
    }

    if ($BuildSign) {
        $signtool = Find-SignTool
        if (-not $signtool) {
            Write-Host "signtool not found - cannot sign installer." -ForegroundColor Red
            exit 1
        }

        $signArgs = @(
            'sign',
            '/tr', $BuildTimestampUrl,
            '/td', 'sha256',
            '/fd', 'sha256'
        )

        if ($BuildCertificatePath) {
            if (-not (Test-Path $BuildCertificatePath)) {
                Write-Host "Certificate file not found: $BuildCertificatePath" -ForegroundColor Red
                exit 1
            }
            $signArgs += @('/f', $BuildCertificatePath)
            if ($BuildCertificatePassword) {
                $signArgs += @('/p', $BuildCertificatePassword)
            }
        } else {
            $signArgs += '/a'
        }

        $signArgs += $exePath

        Write-Host "Signing $exePath ..." -ForegroundColor Cyan
        & $signtool @signArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Signing failed (exit $LASTEXITCODE)." -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "Signed successfully." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Installer built successfully:" -ForegroundColor Green
    Write-Host "  $exePath" -ForegroundColor White
    Write-Host ""
    Write-Host "To test: double-click the .exe, or run it from an elevated prompt."
}

# Only execute when run directly - not when dot-sourced for testing
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Build `
        -BuildVersion $Version `
        -BuildSign:$Sign `
        -BuildCertificatePath $CertificatePath `
        -BuildCertificatePassword $CertificatePassword `
        -BuildTimestampUrl $TimestampUrl `
        -ScriptRoot $PSScriptRoot
}
