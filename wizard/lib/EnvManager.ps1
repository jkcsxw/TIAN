function Set-ApiKey {
    param(
        $Backend,
        [string]$ApiKey,
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    if (-not $ApiKey -or $ApiKey.Trim() -eq "") {
        Append-Log $LogBox "No API key provided — skipping." "warn"
        return
    }

    $varName = $Backend.apiKeyEnvVar
    $isMac   = $IsMacOS -or ($PSVersionTable.Platform -eq 'Unix')

    Append-Log $LogBox "Setting $varName environment variable..." "info"

    if ($isMac) {
        $profile = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bash_profile" }
        $existing = Get-Content $profile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^export $varName=" }
        ($existing + "export $varName=`"$($ApiKey.Trim())`"") | Set-Content $profile -Encoding UTF8
        [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "Process")
    } else {
        [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "User")
        $env:($varName) = $ApiKey.Trim()
    }

    Append-Log $LogBox "$varName saved." "success"
}

function Set-ExtraEnvVar {
    param(
        [string]$Name,
        [string]$Value,
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    if (-not $Value -or $Value.Trim() -eq "") { return }

    [System.Environment]::SetEnvironmentVariable($Name, $Value.Trim(), "User")
    [System.Environment]::SetEnvironmentVariable($Name, $Value.Trim(), "Process")
    Append-Log $LogBox "$Name saved." "success"
}
