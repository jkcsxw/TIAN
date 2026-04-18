BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/BackendInstaller.ps1"
    $script:LogMessages = @()
}

Describe "Write-Launcher" {
    BeforeEach {
        $script:TempDir = New-TestTempDir
        $script:LogMessages = @()
    }
    AfterEach { Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue }

    Context "Windows" {
        BeforeAll { if ($IsMacOS) { return } }

        It "creates launcher.bat on Windows" {
            if ($IsMacOS) { Set-ItResult -Skipped -Because "Windows only" }
            $backend = [PSCustomObject]@{ installType = "cli"; cliCommand = "claude"; displayName = "Claude" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            Test-Path (Join-Path $script:TempDir "launcher.bat") | Should -BeTrue
        }
        It "launcher.bat contains the cliCommand" {
            if ($IsMacOS) { Set-ItResult -Skipped -Because "Windows only" }
            $backend = [PSCustomObject]@{ installType = "cli"; cliCommand = "claude"; displayName = "Claude" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            $content = Get-Content (Join-Path $script:TempDir "launcher.bat") -Raw
            $content | Should -Match "claude"
        }
        It "desktop-app launcher references Claude.exe on Windows" {
            if ($IsMacOS) { Set-ItResult -Skipped -Because "Windows only" }
            $backend = [PSCustomObject]@{ installType = "desktop-app"; cliCommand = $null; displayName = "Claude Desktop"; downloadUrl = "https://example.com" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            $content = Get-Content (Join-Path $script:TempDir "launcher.bat") -Raw
            $content | Should -Match "Claude\.exe"
        }
    }

    Context "Mac" {
        It "creates launcher.sh on Mac" {
            if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac only" }
            $backend = [PSCustomObject]@{ installType = "cli"; cliCommand = "claude"; displayName = "Claude" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            Test-Path (Join-Path $script:TempDir "launcher.sh") | Should -BeTrue
        }
        It "launcher.sh is executable on Mac" {
            if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac only" }
            $backend = [PSCustomObject]@{ installType = "cli"; cliCommand = "claude"; displayName = "Claude" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            $info = Get-Item (Join-Path $script:TempDir "launcher.sh")
            ($info.UnixFileMode -band [System.IO.UnixFileMode]::UserExecute) | Should -Not -Be 0
        }
        It "desktop-app launcher uses 'open -a Claude' on Mac" {
            if (-not $IsMacOS) { Set-ItResult -Skipped -Because "Mac only" }
            $backend = [PSCustomObject]@{ installType = "desktop-app"; cliCommand = $null; displayName = "Claude Desktop"; downloadUrl = "https://example.com" }
            Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
            $content = Get-Content (Join-Path $script:TempDir "launcher.sh") -Raw
            $content | Should -Match "open -a Claude"
        }
    }

    It "logs 'Launcher created' message" {
        $backend = [PSCustomObject]@{ installType = "cli"; cliCommand = "claude"; displayName = "Claude" }
        Write-Launcher -Backend $backend -TianDir $script:TempDir -LogBox $null
        $script:LogMessages | Where-Object { $_ -match "Launcher created" } | Should -Not -BeNullOrEmpty
    }
}
