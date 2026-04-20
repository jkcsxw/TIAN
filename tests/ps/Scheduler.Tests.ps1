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
    function global:Invoke-Task { param($Prompt, $TianDir, [switch]$Background, $JobName, $ScheduleName) }

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
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduling is intentionally unsupported" }
        Add-Schedule -Name "n1" -Prompt "p" -TianDir (Get-TianRoot) -Repeat "daily"
        $s = Read-Schedules | Where-Object { $_.name -eq "n1" }
        $s.time | Should -Be "08:00"
    }
    It "rejects duplicate schedule names" {
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduling is intentionally unsupported" }
        Add-Schedule -Name "dup" -Prompt "first" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot)
        { Add-Schedule -Name "dup" -Prompt "second" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
    }
    It "persists entry to schedules.json" {
        if ($IsLinux) { Set-ItResult -Skipped -Because "Linux scheduling is intentionally unsupported" }
        Add-Schedule -Name "persist-test" -Prompt "do something" -Time "10:00" -Repeat "daily" -TianDir (Get-TianRoot)
        $s = Read-Schedules | Where-Object { $_.name -eq "persist-test" }
        $s | Should -Not -BeNullOrEmpty
        $s.prompt | Should -Be "do something"
        $s.time   | Should -Be "10:00"
    }

    It "creates schedule on Linux via crontab when crontab is available" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux only" }
        Mock Get-Command { param($Name) if ($Name -eq "crontab") { return [PSCustomObject]@{ Name = "crontab" } } } -ParameterFilter { $Name -eq "crontab" }
        Mock Add-LinuxCrontabEntry { $true }
        Add-Schedule -Name "linux-test" -Prompt "p" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot)
        $s = Read-Schedules | Where-Object { $_.name -eq "linux-test" }
        $s | Should -Not -BeNullOrEmpty
    }

    It "uses schedule run indirection on Linux so schedules carry their own names" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux only" }
        Mock Get-Command { param($Name) if ($Name -eq "crontab") { return [PSCustomObject]@{ Name = "crontab" } } } -ParameterFilter { $Name -eq "crontab" }
        Mock Add-LinuxCrontabEntry { param($Name, $CrontabLine) $script:CapturedCronLine = $CrontabLine; $true }
        Add-Schedule -Name "linux-test" -Prompt "p" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot)
        $script:CapturedCronLine | Should -Match 'schedule run --name "linux-test"'
    }

    It "fails on Linux when crontab update cannot be written" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux only" }
        Mock Get-Command { param($Name) if ($Name -eq "crontab") { return [PSCustomObject]@{ Name = "crontab" } } } -ParameterFilter { $Name -eq "crontab" }
        Mock Add-LinuxCrontabEntry { $false }

        { Add-Schedule -Name "linux-fail" -Prompt "p" -Time "08:00" -Repeat "daily" -TianDir (Get-TianRoot) } | Should -Throw
        (Read-Schedules | Where-Object { $_.name -eq "linux-fail" }) | Should -BeNullOrEmpty
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
        Mock Remove-LinuxCrontabEntry { $true }
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

    It "keeps the schedule when Linux crontab removal fails" {
        if (-not $IsLinux) { Set-ItResult -Skipped -Because "Linux only" }
        Mock Remove-LinuxCrontabEntry { $false }

        { Remove-Schedule -Name "remove" -TianDir (Get-TianRoot) } | Should -Throw

        $remaining = Read-Schedules
        ($remaining | Where-Object { $_.name -eq "remove" }) | Should -Not -BeNullOrEmpty
    }
}

Describe "Convert-DayNameToInt" {
    It "converts MON to 1" { Convert-DayNameToInt "MON" | Should -Be 1 }
    It "converts SUN to 0" { Convert-DayNameToInt "SUN" | Should -Be 0 }
    It "converts SAT to 6" { Convert-DayNameToInt "SAT" | Should -Be 6 }
    It "is case-insensitive" { Convert-DayNameToInt "wed" | Should -Be 3 }
    It "throws on unknown day" { { Convert-DayNameToInt "XYZ" } | Should -Throw }
}

Describe "Build-LaunchdWeeklyXml" {
    It "emits single dict for single day" {
        $xml = Build-LaunchdWeeklyXml -DayOfWeek "MON" -Hour 8 -Minute 30
        $xml | Should -Match "<key>Weekday</key><integer>1</integer>"
        $xml | Should -Match "<key>Hour</key><integer>8</integer>"
        $xml | Should -Match "<key>Minute</key><integer>30</integer>"
        $xml | Should -Not -Match "<array>"
    }
    It "emits array for multiple days" {
        $xml = Build-LaunchdWeeklyXml -DayOfWeek "MON,WED,FRI" -Hour 9 -Minute 0
        $xml | Should -Match "<array>"
        $xml | Should -Match "<integer>1</integer>"
        $xml | Should -Match "<integer>3</integer>"
        $xml | Should -Match "<integer>5</integer>"
    }
    It "defaults to Monday when DayOfWeek is empty" {
        $xml = Build-LaunchdWeeklyXml -DayOfWeek "" -Hour 8 -Minute 0
        $xml | Should -Match "<key>Weekday</key><integer>1</integer>"
    }
}

Describe "Get-CrontabEntry" {
    It "returns daily cron expression" {
        $line = Get-CrontabEntry -Repeat "daily" -Time "08:30" -DayOfWeek "" -Command "echo hi"
        $line | Should -Match "^30 8 \* \* \*"
    }
    It "returns hourly cron expression" {
        $line = Get-CrontabEntry -Repeat "hourly" -Time "00:30" -DayOfWeek "" -Command "echo hi"
        $line | Should -Match "^30 \* \* \* \*"
    }
    It "uses first day for weekly" {
        $line = Get-CrontabEntry -Repeat "weekly" -Time "09:00" -DayOfWeek "FRI" -Command "echo hi"
        $line | Should -Match "^0 9 \* \* 5"
    }
    It "defaults weekly to Monday (1) when no day specified" {
        $line = Get-CrontabEntry -Repeat "weekly" -Time "07:00" -DayOfWeek "" -Command "echo hi"
        $line | Should -Match "^0 7 \* \* 1"
    }
}

Describe "Invoke-ScheduleNow" {
    It "passes schedule metadata into Invoke-Task" {
        Mock Invoke-Task {}
        Save-Schedules @([PSCustomObject]@{ name = "brief"; prompt = "p"; time = "08:00"; repeat = "daily" })

        Invoke-ScheduleNow -Name "brief" -TianDir (Get-TianRoot)

        Should -Invoke Invoke-Task -Times 1 -ParameterFilter {
            $Prompt -eq "p" -and $Background -and $JobName -eq "brief" -and $ScheduleName -eq "brief"
        }
    }
}
