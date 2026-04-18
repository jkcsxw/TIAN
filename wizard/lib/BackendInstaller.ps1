function Install-Backend {
    param(
        $Backend,
        [System.Windows.Forms.RichTextBox]$LogBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if ($Backend.installType -eq "desktop-app") {
        Append-Log $LogBox "Opening Claude Desktop download page..." "info"
        Start-Process $Backend.downloadUrl
        Append-Log $LogBox "Please install Claude Desktop from the opened page, then return here." "warn"
        $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 20, 100)
        return $true
    }

    Append-Log $LogBox "Installing $($Backend.displayName)..." "info"
    Append-Log $LogBox "Running: npm install -g $($Backend.npmPackage)" "info"

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Append-Log $LogBox "npm not found. Node.js installation may not have updated PATH yet." "error"
        Append-Log $LogBox "Please close and re-run setup.bat" "warn"
        return $false
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "npm"
    $psi.Arguments = "install -g $($Backend.npmPackage)"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $outputLines = [System.Collections.Generic.List[string]]::new()
    $proc.Add_OutputDataReceived({ if ($Event.SourceEventArgs.Data) { $outputLines.Add($Event.SourceEventArgs.Data) } })
    $proc.Add_ErrorDataReceived({ if ($Event.SourceEventArgs.Data) { $outputLines.Add($Event.SourceEventArgs.Data) } })

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    while (-not $proc.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
    }
    $proc.WaitForExit()

    if ($proc.ExitCode -eq 0) {
        Append-Log $LogBox "$($Backend.displayName) installed successfully." "success"
        $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 20, 100)
        return $true
    }

    Append-Log $LogBox "Installation failed (exit code $($proc.ExitCode)):" "error"
    foreach ($line in $outputLines | Select-Object -Last 10) {
        Append-Log $LogBox "  $line" "error"
    }
    return $false
}

function Write-Launcher {
    param(
        $Backend,
        [string]$TianDir,
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    $launcherPath = Join-Path $TianDir "launcher.bat"

    if ($Backend.installType -eq "desktop-app") {
        $content = @"
@echo off
echo Opening Claude Desktop...
start "" "%LOCALAPPDATA%\AnthropicClaude\Claude.exe"
"@
    } else {
        $content = @"
@echo off
title Tian - $($Backend.displayName)
echo Starting $($Backend.displayName)...
echo Type your message and press Enter. Type 'exit' to quit.
echo.
$($Backend.cliCommand)
"@
    }

    Set-Content -Path $launcherPath -Value $content -Encoding ASCII
    Append-Log $LogBox "Launcher created: launcher.bat" "success"
}
