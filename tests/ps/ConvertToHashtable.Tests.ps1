BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/McpConfigurator.ps1"
}

Describe "ConvertTo-Hashtable" {
    It "converts null to empty hashtable" {
        $result = ConvertTo-Hashtable $null
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
    It "converts a flat PSCustomObject" {
        $obj = [PSCustomObject]@{ name = "test"; value = 42 }
        $result = ConvertTo-Hashtable $obj
        $result | Should -BeOfType [hashtable]
        $result["name"] | Should -Be "test"
        $result["value"] | Should -Be 42
    }
    It "recursively converts nested objects" {
        $json = '{"outer":{"inner":{"deep":"value"}}}' | ConvertFrom-Json
        $result = ConvertTo-Hashtable $json
        $result["outer"] | Should -BeOfType [hashtable]
        $result["outer"]["inner"] | Should -BeOfType [hashtable]
        $result["outer"]["inner"]["deep"] | Should -Be "value"
    }
    It "preserves arrays of primitive values" {
        $json = '{"args":["-y","package"]}' | ConvertFrom-Json
        $result = ConvertTo-Hashtable $json
        $result["args"].Count | Should -Be 2
        $result["args"][0] | Should -Be "-y"
    }
    It "preserves arrays of objects" {
        $json = '{"items":[{"id":"a"},{"id":"b"}]}' | ConvertFrom-Json
        $result = ConvertTo-Hashtable $json
        $result["items"].Count | Should -Be 2
        $result["items"][0]["id"] | Should -Be "a"
    }
    It "passes through string leaf values unchanged" {
        $result = ConvertTo-Hashtable "hello"
        $result | Should -Be "hello"
    }
    It "passes through integer leaf values unchanged" {
        $result = ConvertTo-Hashtable 99
        $result | Should -Be 99
    }
    It "passes through boolean leaf values unchanged" {
        $result = ConvertTo-Hashtable $true
        $result | Should -Be $true
    }
    It "is idempotent when given a hashtable" {
        $ht = @{ key = "val" }
        $result = ConvertTo-Hashtable $ht
        $result["key"] | Should -Be "val"
    }
    It "handles unicode values" {
        $obj = [PSCustomObject]@{ label = "天" }
        $result = ConvertTo-Hashtable $obj
        $result["label"] | Should -Be "天"
    }
}
