BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/McpConfigurator.ps1"
    $script:LogMessages = @()
}

Describe "Get-McpConfigPath" {
    It "returns ~/.claude/settings.json for claude_code target" {
        $backend = [PSCustomObject]@{ mcpConfigTarget = "claude_code"; mcpConfigPath = "" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "\.claude[/\\]settings\.json"
    }
    It "returns APPDATA Claude path for claude_desktop on Windows" {
        if ($IsMacOS) { Set-ItResult -Skipped -Because "Windows-only path" }
        $backend = [PSCustomObject]@{ mcpConfigTarget = "claude_desktop"; mcpConfigPath = "" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "Claude[/\\]claude_desktop_config\.json"
    }
    It "returns Library/Application Support path for claude_desktop on Mac" {
        if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac-only path" }
        $backend = [PSCustomObject]@{ mcpConfigTarget = "claude_desktop"; mcpConfigPath = "" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "Library/Application Support/Claude"
    }
    It "returns ~/.config Claude path for claude_desktop on Linux" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux-only path" }
        $backend = [PSCustomObject]@{ mcpConfigTarget = "claude_desktop"; mcpConfigPath = "" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "\.config[/\\]Claude[/\\]claude_desktop_config\.json"
    }
    It "falls back to ~/.tian/mcp_config.json for unknown target" {
        $backend = [PSCustomObject]@{ mcpConfigTarget = "unknown_xyz"; mcpConfigPath = "" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "\.tian[/\\]mcp_config\.json"
    }
    It "uses mcpConfigPath when provided for custom target" {
        $homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
        $backend = [PSCustomObject]@{ mcpConfigTarget = "custom"; mcpConfigPath = "$homeDir/.myapp/config.json" }
        $result = Get-McpConfigPath $backend
        $result | Should -Match "\.myapp[/\\]config\.json"
    }
}

Describe "Set-McpServers" {
    BeforeEach {
        $script:TempDir = New-TestTempDir
        $script:LogMessages = @()
        $script:ProgressBar = New-FakeProgressBar

        $script:Backend = [PSCustomObject]@{
            mcpConfigTarget = "claude_code"
            mcpConfigPath   = ""
        }
        # Override config path to temp dir
        Mock Get-McpConfigPath { return "$script:TempDir/settings.json" }
    }
    AfterEach { Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue }

    It "creates config directory if it does not exist" {
        $subDir = Join-Path $script:TempDir "subdir"
        Mock Get-McpConfigPath { return "$subDir/settings.json" }
        $server = [PSCustomObject]@{
            displayName = "Test"; configKey = "test"
            configSchema = [PSCustomObject]@{ command = "npx"; args = @("test") }
        }
        Set-McpServers -Backend $script:Backend -SelectedServers @($server) -LogBox $null -ProgressBar $script:ProgressBar
        Test-Path $subDir | Should -BeTrue
    }
    It "writes a valid JSON file when config does not exist" {
        $server = [PSCustomObject]@{
            displayName = "FileSystem"; configKey = "filesystem"
            configSchema = [PSCustomObject]@{ command = "npx"; args = @("-y", "server-filesystem") }
        }
        Set-McpServers -Backend $script:Backend -SelectedServers @($server) -LogBox $null -ProgressBar $script:ProgressBar
        $configPath = "$script:TempDir/settings.json"
        Test-Path $configPath | Should -BeTrue
        { Get-Content $configPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
    It "merges new server without removing existing keys" {
        $configPath = "$script:TempDir/settings.json"
        @{ existingKey = "keepMe"; mcpServers = @{ old = @{ command = "old" } } } |
            ConvertTo-Json -Depth 5 | Set-Content $configPath -Encoding UTF8

        $server = [PSCustomObject]@{
            displayName = "New"; configKey = "new"
            configSchema = [PSCustomObject]@{ command = "npx" }
        }
        Set-McpServers -Backend $script:Backend -SelectedServers @($server) -LogBox $null -ProgressBar $script:ProgressBar

        $result = Get-Content $configPath -Raw | ConvertFrom-Json
        $result.existingKey    | Should -Be "keepMe"
        $result.mcpServers.old | Should -Not -BeNullOrEmpty
        $result.mcpServers.new | Should -Not -BeNullOrEmpty
    }
    It "handles empty selected servers list without writing file" {
        Set-McpServers -Backend $script:Backend -SelectedServers @() -LogBox $null -ProgressBar $script:ProgressBar
        Test-Path "$script:TempDir/settings.json" | Should -BeFalse
    }
    It "handles a null selected servers list gracefully" {
        { Set-McpServers -Backend $script:Backend -SelectedServers $null -LogBox $null -ProgressBar $script:ProgressBar } | Should -Not -Throw
    }
    It "handles corrupted config JSON by starting fresh" {
        $configPath = "$script:TempDir/settings.json"
        "{ not valid json" | Set-Content $configPath
        $server = [PSCustomObject]@{
            displayName = "Test"; configKey = "test"
            configSchema = [PSCustomObject]@{ command = "npx" }
        }
        { Set-McpServers -Backend $script:Backend -SelectedServers @($server) -LogBox $null -ProgressBar $script:ProgressBar } | Should -Not -Throw
        $result = Get-Content $configPath -Raw | ConvertFrom-Json
        $result.mcpServers.test | Should -Not -BeNullOrEmpty
    }
    It "increments ProgressBar value" {
        $server = [PSCustomObject]@{
            displayName = "Test"; configKey = "test"
            configSchema = [PSCustomObject]@{ command = "npx" }
        }
        $pb = New-FakeProgressBar
        $pb.Value = 0
        Set-McpServers -Backend $script:Backend -SelectedServers @($server) -LogBox $null -ProgressBar $pb
        $pb.Value | Should -BeGreaterThan 0
    }
}
