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
    Append-Log $LogBox "Setting $varName environment variable..." "info"

    [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "User")
    $env:($varName) = $ApiKey.Trim()

    Append-Log $LogBox "$varName saved to your user environment." "success"
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
