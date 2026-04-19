function Set-ApiKey {
    param(
        $Backend,
        [string]$ApiKey,
        $LogBox
    )

    if (-not $Backend.apiKeyEnvVar -or $Backend.apiKeyEnvVar.Trim() -eq "") {
        Append-Log $LogBox "Backend does not require an API key — skipping." "info"
        return
    }

    if (-not $ApiKey -or $ApiKey.Trim() -eq "") {
        Append-Log $LogBox "No API key provided — skipping." "warn"
        return
    }

    $varName = $Backend.apiKeyEnvVar
    $platform = if ($PSVersionTable.Platform -eq 'Unix') { uname } else { "" }
    $runningOnMac = $IsMacOS -or ($platform -eq 'Darwin')

    Append-Log $LogBox "Setting $varName environment variable..." "info"

    if ($runningOnMac) {
        $profile = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bash_profile" }
        $existing = Get-Content $profile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^export $varName=" }
        ($existing + "export $varName=`"$($ApiKey.Trim())`"") | Set-Content $profile -Encoding UTF8
        [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "Process")
    } else {
        [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "User")
        [System.Environment]::SetEnvironmentVariable($varName, $ApiKey.Trim(), "Process")
    }

    Append-Log $LogBox "$varName saved." "success"
}

function Set-ExtraEnvVar {
    param(
        [string]$Name,
        [string]$Value,
        $LogBox
    )

    if (-not $Value -or $Value.Trim() -eq "") { return }

    [System.Environment]::SetEnvironmentVariable($Name, $Value.Trim(), "User")
    [System.Environment]::SetEnvironmentVariable($Name, $Value.Trim(), "Process")
    Append-Log $LogBox "$Name saved." "success"
}
