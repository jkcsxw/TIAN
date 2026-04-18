function Install-Node {
    param(
        [System.Windows.Forms.RichTextBox]$LogBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    Append-Log $LogBox "Checking for Node.js..." "info"

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $version = & node --version 2>&1
        $major = [int]($version -replace 'v(\d+)\..*','$1')
        if ($major -ge 18) {
            Append-Log $LogBox "Node.js $version is already installed." "success"
            $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 15, 100)
            return $true
        }
        Append-Log $LogBox "Node.js $version found but version 18+ is required. Upgrading..." "warn"
    }

    $isMac = $IsMacOS -or ($PSVersionTable.Platform -eq 'Unix')
    Append-Log $LogBox "Installing Node.js LTS..." "info"

    if ($isMac) {
        # Try Homebrew first
        $brew = Get-Command brew -ErrorAction SilentlyContinue
        if ($brew) {
            Append-Log $LogBox "Using Homebrew..." "info"
            $result = Start-Process brew -ArgumentList "install node@20" -Wait -PassThru -NoNewWindow
            if ($result.ExitCode -eq 0) {
                Start-Process brew -ArgumentList "link node@20 --force --overwrite" -Wait -NoNewWindow
                Refresh-Path
                Append-Log $LogBox "Node.js installed via Homebrew." "success"
                $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 15, 100)
                return $true
            }
        }
        # Fallback: pkg installer
        Append-Log $LogBox "Downloading Node.js pkg installer..." "info"
        $nodeUrl = "https://nodejs.org/dist/v20.18.0/node-v20.18.0.pkg"
        $installerPath = "/tmp/node-lts.pkg"
        try {
            Invoke-WebRequest -Uri $nodeUrl -OutFile $installerPath
            $result = Start-Process sudo -ArgumentList "installer -pkg $installerPath -target /" -Wait -PassThru -NoNewWindow
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            if ($result.ExitCode -eq 0) {
                Refresh-Path
                Append-Log $LogBox "Node.js installed via pkg." "success"
                $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 15, 100)
                return $true
            }
            Append-Log $LogBox "pkg installer failed (exit $($result.ExitCode))." "error"
            return $false
        } catch {
            Append-Log $LogBox "Failed to download Node.js: $_" "error"
            return $false
        }
    }

    # Windows: try winget first
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Append-Log $LogBox "Using Windows Package Manager (winget)..." "info"
        $result = Start-Process winget -ArgumentList "install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements" -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -eq 0) {
            Refresh-Path
            Append-Log $LogBox "Node.js installed via winget." "success"
            $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 15, 100)
            return $true
        }
        Append-Log $LogBox "winget failed, falling back to direct download..." "warn"
    }

    # Windows fallback: MSI
    Append-Log $LogBox "Downloading Node.js installer..." "info"
    $nodeUrl = "https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi"
    $installerPath = "$env:TEMP\node-lts-installer.msi"
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($nodeUrl, $installerPath)
        Append-Log $LogBox "Running Node.js installer (this may take a minute)..." "info"
        $result = Start-Process msiexec -ArgumentList "/i `"$installerPath`" /quiet /norestart" -Wait -PassThru
        if ($result.ExitCode -eq 0) {
            Refresh-Path
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            Append-Log $LogBox "Node.js installed successfully." "success"
            $ProgressBar.Value = [Math]::Min($ProgressBar.Value + 15, 100)
            return $true
        }
        Append-Log $LogBox "Installer exited with code: $($result.ExitCode)" "error"
        return $false
    } catch {
        Append-Log $LogBox "Failed to download Node.js: $_" "error"
        return $false
    }
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}
