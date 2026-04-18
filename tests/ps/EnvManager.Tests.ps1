BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/EnvManager.ps1"
    $script:LogMessages = @()
}

Describe "Set-ApiKey" {
    BeforeEach {
        $script:LogMessages = @()
        $script:Backend = [PSCustomObject]@{ apiKeyEnvVar = "TIAN_TEST_KEY_$(([System.Guid]::NewGuid().ToString('N').Substring(0,6)))" }
        # Clean up any previous test variable
        [System.Environment]::SetEnvironmentVariable($script:Backend.apiKeyEnvVar, $null, "User")
        [System.Environment]::SetEnvironmentVariable($script:Backend.apiKeyEnvVar, $null, "Process")
    }
    AfterEach {
        [System.Environment]::SetEnvironmentVariable($script:Backend.apiKeyEnvVar, $null, "User")
        [System.Environment]::SetEnvironmentVariable($script:Backend.apiKeyEnvVar, $null, "Process")
    }

    It "skips empty API key and logs a warning" {
        Set-ApiKey -Backend $script:Backend -ApiKey "" -LogBox $null
        $script:LogMessages | Should -Contain "No API key provided — skipping."
    }
    It "skips whitespace-only API key" {
        Set-ApiKey -Backend $script:Backend -ApiKey "   " -LogBox $null
        $script:LogMessages | Should -Contain "No API key provided — skipping."
    }
    It "sets the process-level environment variable immediately" {
        Set-ApiKey -Backend $script:Backend -ApiKey "sk-test-abc123" -LogBox $null
        [System.Environment]::GetEnvironmentVariable($script:Backend.apiKeyEnvVar, "Process") | Should -Be "sk-test-abc123"
    }
    It "trims leading and trailing whitespace from the key" {
        Set-ApiKey -Backend $script:Backend -ApiKey "  sk-trimmed  " -LogBox $null
        [System.Environment]::GetEnvironmentVariable($script:Backend.apiKeyEnvVar, "Process") | Should -Be "sk-trimmed"
    }

    Context "Mac path (shell profile)" {
        BeforeAll {
            if (-not $IsMacOS) { return }
            $script:TempHome = New-TestTempDir
            $script:FakeProfile = Join-Path $script:TempHome ".zshrc"
            "# existing content" | Set-Content $script:FakeProfile
        }
        AfterAll {
            if ($script:TempHome) { Remove-Item $script:TempHome -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It "appends export line to shell profile on Mac" {
            if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac only" }
            $env:HOME = $script:TempHome
            Set-ApiKey -Backend $script:Backend -ApiKey "sk-mac-key" -LogBox $null
            $content = Get-Content $script:FakeProfile -Raw
            $content | Should -Match "export $($script:Backend.apiKeyEnvVar)=`"sk-mac-key`""
        }
        It "replaces existing key line instead of duplicating it" {
            if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac only" }
            $env:HOME = $script:TempHome
            Set-ApiKey -Backend $script:Backend -ApiKey "sk-first" -LogBox $null
            Set-ApiKey -Backend $script:Backend -ApiKey "sk-second" -LogBox $null
            $lines = Get-Content $script:FakeProfile | Where-Object { $_ -match $script:Backend.apiKeyEnvVar }
            $lines.Count | Should -Be 1
            $lines[0] | Should -Match "sk-second"
        }
    }
}

Describe "Set-ExtraEnvVar" {
    BeforeEach { $script:LogMessages = @() }

    It "skips empty value silently" {
        { Set-ExtraEnvVar -Name "TIAN_EXTRA_TEST" -Value "" -LogBox $null } | Should -Not -Throw
        $script:LogMessages.Count | Should -Be 0
    }
    It "sets the named variable in process scope" {
        $varName = "TIAN_EXTRA_$(([System.Guid]::NewGuid().ToString('N').Substring(0,6)))"
        Set-ExtraEnvVar -Name $varName -Value "testval" -LogBox $null
        [System.Environment]::GetEnvironmentVariable($varName, "Process") | Should -Be "testval"
        [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
        [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
    }
}
