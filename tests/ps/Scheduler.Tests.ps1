BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/Catalog.ps1"
    . "$(Get-TianRoot)/wizard/lib/McpConfigurator.ps1"

    $script:TempSchedDir = New-TestTempDir
    $_tmpSchedFile = Join-Path $script:TempSchedDir "schedules.json"

    # Stub Write-* so scheduler doesn't need full CLI context
    function global:Write-Ok   { param($t) }
    function global:Write-Info { param($t) }
    function global:Write-Warn { param($t) }
    function global:Write-Fail { param($t) throw $t }

    . "$(Get-TianRoot)/cli/scheduler.ps1"
    # Restore to temp path (scheduler.ps1 overwrote the local var when dot-sourced)
    $global:TIAN_SCHEDULES_FILE = $_tmpSchedFile
}
AfterAll { Remove-Item $script:TempSchedDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe "Get-TaskName" {
    It "prefixes with TIAN_" {
        Get-TaskName "mysched" | Should -Be "TIAN_mysched"
    }
    It "replaces spaces and special chars with underscores" {
        Get-TaskName "my task!" | Should -Be "TIAN_my_task_"
    }
    It "preserves alphanumeric, hyphen, underscore" {
        Get-TaskName "daily-report_v2" | Should -Be "TIAN_daily-report_v2"
    }
}

Describe "Read-Schedules / Save-Schedules round-trip" {
    BeforeEach { Remove-Item $global:TIAN_SCHEDULES_FILE -ErrorAction SilentlyContinue }

    It "returns empty array when file does not exist" {
        $items = @(Read-Schedules)
        $items.Count | Should -Be 0
    }
    It "normalises single-item array" {
        Ensure-ScheduleFile
        '[{"name":"s1","prompt":"p"}]' | Set-Content $global:TIAN_SCHEDULES_FILE -Encoding UTF8
        $items = @(Read-Schedules)
        $items.Count | Should -Be 1
    }
    It "round-trips multi-item array" {
        $entries = @(
            [PSCustomObject]@{ name = "a"; prompt = "pa"; time = "08:00"; repeat = "daily" },
            [PSCustomObject]@{ name = "b"; prompt = "pb"; time = "09:00"; repeat = "weekly" }
        )
        Save-Schedules $entries
        $result = Read-Schedules
        $result.Count | Should -Be 2
        $result[0].name | Should -Be "a"
        $result[1].name | Should -Be "b"
    }
}

Describe "Add-Schedule" {
    BeforeEach {
        Remove-Item $global:TIAN_SCHEDULES_FILE -ErrorAction SilentlyContinue
        # Mock Start-Process so schtasks/launchctl never runs
        Mock Start-Process     { [PSCustomObject]@{ ExitCode = 0 } }
        Mock Invoke-Launchctl  { }
    }

    It "fails when Name is missing" {
        { Add-Schedule -Name "" -Prompt "test" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
    }
    It "fails when Prompt is missing" {
        { Add-Schedule -Name "test" -Prompt "" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
    }
    It "defaults Time to 08:00 when not provided" {
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduler integration is not implemented" }
        Add-Schedule -Name "n1" -Prompt "p" -TianDir (Get-TianRoot) -Repeat "daily"
        $s = Read-Schedules | Where-Object { $_.name -eq "n1" }
        $s.time | Should -Be "08:00"
    }
    It "rejects duplicate schedule names" {
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduler integration is not implemented" }
        Add-Schedule -Name "dup" -Prompt "first" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot)
        { Add-Schedule -Name "dup" -Prompt "second" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
    }
    It "persists entry to schedules.json" {
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduler integration is not implemented" }
        Add-Schedule -Name "persist-test" -Prompt "do something" -Time "10:00" -Repeat "daily" -TianDir (Get-TianRoot)
        $s = Read-Schedules | Where-Object { $_.name -eq "persist-test" }
        $s | Should -Not -BeNullOrEmpty
        $s.prompt | Should -Be "do something"
        $s.time   | Should -Be "10:00"
    }
    It "fails on Linux because scheduler integration is not implemented" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux-only expectation" }
        { Add-Schedule -Name "linux-test" -Prompt "do something" -Time "10:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
    }

    Context "Windows schtasks argument construction" {
        BeforeEach {
            if ($IsMacOS) { return }
            $script:CapturedArgs = $null
            Mock Start-Process {
                param($FilePath, $ArgumentList)
                $script:CapturedArgs = $ArgumentList
                [PSCustomObject]@{ ExitCode = 0 }
            }
        }

        It "uses ONCE for once repeat" {
            if (-not $IsWindows) { Set-ItResult -Skipped -Because "Windows only" }
            Add-Schedule -Name "once-test" -Prompt "p" -Time "08:00" -Repeat "once" -TianDir (Get-TianRoot)
            $script:CapturedArgs | Should -Contain "ONCE"
        }
        It "uses HOURLY for hourly repeat" {
            if (-not $IsWindows) { Set-ItResult -Skipped -Because "Windows only" }
            Add-Schedule -Name "hourly-test" -Prompt "p" -Time "08:00" -Repeat "hourly" -TianDir (Get-TianRoot)
            $script:CapturedArgs | Should -Contain "HOURLY"
        }
        It "uses DAILY for daily repeat" {
            if (-not $IsWindows) { Set-ItResult -Skipped -Because "Windows only" }
            Add-Schedule -Name "daily-test" -Prompt "p" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot)
            $script:CapturedArgs | Should -Contain "DAILY"
        }
        It "uses WEEKLY and includes /D for weekly repeat with day" {
            if (-not $IsWindows) { Set-ItResult -Skipped -Because "Windows only" }
            Add-Schedule -Name "weekly-test" -Prompt "p" -Time "09:00" -Repeat "weekly" -DayOfWeek "MON" -TianDir (Get-TianRoot)
            $script:CapturedArgs | Should -Contain "WEEKLY"
            $script:CapturedArgs | Should -Contain "/D"
            $script:CapturedArgs | Should -Contain "MON"
        }
    }
}

Describe "Remove-Schedule" {
    BeforeEach {
        Remove-Item $global:TIAN_SCHEDULES_FILE -ErrorAction SilentlyContinue
        Mock Start-Process     { [PSCustomObject]@{ ExitCode = 0 } }
        Mock Invoke-Launchctl  { }
        # Pre-populate two schedules
        Save-Schedules @(
            [PSCustomObject]@{ name = "keep";   taskName = "TIAN_keep";   prompt = "p1"; time = "08:00"; repeat = "daily" },
            [PSCustomObject]@{ name = "remove"; taskName = "TIAN_remove"; prompt = "p2"; time = "09:00"; repeat = "daily" }
        )
    }

    It "removes only the matching entry" {
        Remove-Schedule -Name "remove" -TianDir (Get-TianRoot)
        $remaining = Read-Schedules
        $remaining.Count | Should -Be 1
        $remaining[0].name | Should -Be "keep"
    }
    It "fails gracefully when name does not exist" {
        { Remove-Schedule -Name "nonexistent" -TianDir (Get-TianRoot) } | Should -Throw
    }
    It "fails when Name is empty" {
        { Remove-Schedule -Name "" -TianDir (Get-TianRoot) } | Should -Throw
    }
}
