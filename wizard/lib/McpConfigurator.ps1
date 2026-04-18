function Get-McpConfigPath {
    param($Backend)

    switch ($Backend.mcpConfigTarget) {
        "claude_desktop" {
            return "$env:APPDATA\Claude\claude_desktop_config.json"
        }
        "claude_code" {
            return "$env:USERPROFILE\.claude\settings.json"
        }
        default {
            if ($Backend.mcpConfigPath) {
                return [System.Environment]::ExpandEnvironmentVariables($Backend.mcpConfigPath)
            }
            return "$env:USERPROFILE\.tian\mcp_config.json"
        }
    }
}

function Set-McpServers {
    param(
        $Backend,
        [array]$SelectedServers,
        [System.Windows.Forms.RichTextBox]$LogBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not $SelectedServers -or $SelectedServers.Count -eq 0) {
        Append-Log $LogBox "No MCP servers selected — skipping." "info"
        return
    }

    $configPath = Get-McpConfigPath $Backend
    $configDir = Split-Path $configPath -Parent

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Load existing config or start fresh
    $config = @{}
    if (Test-Path $configPath) {
        try {
            $existing = Get-Content $configPath -Raw | ConvertFrom-Json
            $config = ConvertTo-Hashtable $existing
        } catch {
            Append-Log $LogBox "Could not parse existing config, starting fresh." "warn"
        }
    }

    if (-not $config.ContainsKey("mcpServers")) {
        $config["mcpServers"] = @{}
    }

    $step = [Math]::Floor(15 / [Math]::Max($SelectedServers.Count, 1))

    foreach ($server in $SelectedServers) {
        Append-Log $LogBox "Configuring MCP: $($server.displayName)..." "info"
        $schema = ConvertTo-Hashtable $server.configSchema
        $config["mcpServers"][$server.configKey] = $schema
        $ProgressBar.Value = [Math]::Min($ProgressBar.Value + $step, 100)
        Append-Log $LogBox "$($server.displayName) added to config." "success"
    }

    $json = $config | ConvertTo-Json -Depth 10
    Set-Content -Path $configPath -Value $json -Encoding UTF8

    Append-Log $LogBox "MCP config written to: $configPath" "success"
}

function ConvertTo-Hashtable {
    param($InputObject)

    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [System.Collections.Hashtable]) { return $InputObject }
    if ($InputObject -is [string] -or $InputObject -is [int] -or $InputObject -is [bool]) { return $InputObject }
    if ($InputObject -is [array]) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
    }

    $ht = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
        $ht[$_.Name] = ConvertTo-Hashtable $_.Value
    }
    return $ht
}
