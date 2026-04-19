BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/Catalog.ps1"
    $script:RealCatalogPath = Join-Path (Get-TianRoot) "config/catalog.json"
}

Describe "Get-Catalog" {
    Context "valid catalog" {
        BeforeAll { $script:catalog = Get-Catalog -TianDir (Get-TianRoot) }

        It "returns an object with backends array" {
            $script:catalog.backends | Should -Not -BeNullOrEmpty
        }
        It "returns an object with mcpServers array" {
            $script:catalog.mcpServers | Should -Not -BeNullOrEmpty
        }
        It "returns an object with skills array" {
            $script:catalog.skills | Should -Not -BeNullOrEmpty
        }
        It "includes expected backend IDs" {
            $ids = $script:catalog.backends | ForEach-Object { $_.id }
            $ids | Should -Contain "claude-code"
            $ids | Should -Contain "openai-codex"
            $ids | Should -Contain "ollama-qwen-local"
            $ids | Should -Contain "claude-desktop"
        }
        It "every MCP server has required fields" {
            foreach ($s in $script:catalog.mcpServers) {
                $s.id         | Should -Not -BeNullOrEmpty -Because "MCP server missing id"
                $s.configKey  | Should -Not -BeNullOrEmpty -Because "MCP server '$($s.id)' missing configKey"
                $s.configSchema | Should -Not -BeNullOrEmpty -Because "MCP server '$($s.id)' missing configSchema"
            }
        }
        It "every skill has required fields" {
            foreach ($s in $script:catalog.skills) {
                $s.id     | Should -Not -BeNullOrEmpty -Because "skill missing id"
                $s.source | Should -Not -BeNullOrEmpty -Because "skill '$($s.id)' missing source"
            }
        }
        It "builtin skills point to existing prompt files" {
            foreach ($s in ($script:catalog.skills | Where-Object { $_.source -eq "builtin" })) {
                $fullPath = Join-Path (Get-TianRoot) $s.promptFile
                $fullPath | Should -Exist -Because "skill '$($s.id)' promptFile not found"
            }
        }
        It "backend IDs are unique" {
            $ids = $script:catalog.backends | ForEach-Object { $_.id }
            ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        }
        It "MCP server IDs are unique" {
            $ids = $script:catalog.mcpServers | ForEach-Object { $_.id }
            ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        }
        It "skill IDs are unique" {
            $ids = $script:catalog.skills | ForEach-Object { $_.id }
            ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
        }
        It "each backend with a cliCommand has nonInteractiveFlag" {
            foreach ($b in ($script:catalog.backends | Where-Object { $_.cliCommand })) {
                $b.nonInteractiveFlag | Should -Not -BeNullOrEmpty -Because "backend '$($b.id)' has cliCommand but no nonInteractiveFlag"
            }
        }
    }

    Context "error cases" {
        It "throws when catalog file is missing" {
            $tmpDir = New-TestTempDir
            { Get-Catalog -TianDir $tmpDir } | Should -Throw
            Remove-Item $tmpDir -Recurse -Force
        }
        It "throws on malformed JSON" {
            $tmpDir = New-TestTempDir
            $configDir = Join-Path $tmpDir "config"
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            "{ not valid json" | Set-Content (Join-Path $configDir "catalog.json")
            { Get-Catalog -TianDir $tmpDir } | Should -Throw
            Remove-Item $tmpDir -Recurse -Force
        }
    }
}
