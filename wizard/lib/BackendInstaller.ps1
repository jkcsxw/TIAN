function Install-Backend {
    param(
        $Backend,
        $LogBox,
        $ProgressBar
    )

    $installType = if ($Backend.installType) { $Backend.installType } else { "cli" }

    if ($installType -eq "desktop-app") {
        Append-Log $LogBox "Opening Claude Desktop download page..." "info"
        Start-Process $Backend.downloadUrl
        Append-Log $LogBox "Please install Claude Desktop from the opened page, then return here." "warn"
        $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 20, 100)
        return $true
    }

    if ($installType -eq "local-cli") {
        $cmd = Get-Command $Backend.cliCommand -ErrorAction SilentlyContinue
        if ($cmd) {
            Append-Log $LogBox "$($Backend.displayName) is already available on PATH." "success"
        } else {
            Append-Log $LogBox "$($Backend.displayName) was not found on PATH." "warn"
            if ($Backend.downloadUrl) {
                Append-Log $LogBox "Opening setup page..." "info"
                Start-Process $Backend.downloadUrl
            }
            if ($Backend.setupNote) {
                Append-Log $LogBox $Backend.setupNote "warn"
            }
        }
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
        $LogBox
    )

    $isMac = [bool]$IsMacOS
    $launchCommand = if ($Backend.launchCommand) { $Backend.launchCommand } else { $Backend.cliCommand }

    if ($isMac) {
        $launcherPath = Join-Path $TianDir "launcher.sh"
        if ($Backend.installType -eq "desktop-app") {
            $content = "#!/usr/bin/env bash`necho 'Opening Claude...'`nopen -a Claude 2>/dev/null || open '$($Backend.downloadUrl)'`n"
        } else {
            $content = "#!/usr/bin/env bash`nsource `"`$HOME/.zshrc`" 2>/dev/null || source `"`$HOME/.bash_profile`" 2>/dev/null || true`necho 'Starting $($Backend.displayName)...'`n$launchCommand`n"
        }
        Set-Content -Path $launcherPath -Value $content -Encoding UTF8
        & chmod +x $launcherPath
        Append-Log $LogBox "Launcher created: launcher.sh" "success"
    } else {
        $launcherPath = Join-Path $TianDir "launcher.bat"
        if ($Backend.installType -eq "desktop-app") {
            $content = "@echo off`r`necho Opening Claude Desktop...`r`nstart `"`" `"%LOCALAPPDATA%\AnthropicClaude\Claude.exe`"`r`n"
        } else {
            $content = "@echo off`r`ntitle TIAN - $($Backend.displayName)`r`necho Starting $($Backend.displayName)...`r`necho.`r`n$launchCommand`r`n"
        }
        Set-Content -Path $launcherPath -Value $content -Encoding ASCII
        Append-Log $LogBox "Launcher created: launcher.bat" "success"
    }
}
