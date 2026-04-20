BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"

    # Stub external commands that tian.ps1 calls at module level
    function global:Write-Ok   { param($t) }
    function global:Write-Info { param($t) }
    function global:Write-Warn { param($t) }
    function global:Write-Fail { param($t) Write-Error $t }

    $script:TianRoot = Get-TianRoot
    # Use current PowerShell executable so tests work regardless of PATH
    $script:PwshExe  = (Get-Process -Id $PID).MainModule.FileName

    function global:Invoke-Tian {
        param([string[]]$TianArgs)
        & $script:PwshExe -NoProfile -File "$script:TianRoot/cli/tian.ps1" @TianArgs 2>&1
    }
}

Describe "CLI help output" {
    It "prints usage when no arguments given" {
        $out = Invoke-Tian @()
        ($out -join " ") | Should -Match "USAGE|Usage"
    }
    It "prints usage for 'help' command" {
        $out = Invoke-Tian @("help")
        ($out -join " ") | Should -Match "USAGE|Usage"
    }
}

Describe "CLI argument validation" {
    It "rejects unknown command with non-zero exit" {
        Invoke-Tian @("unknown-command") | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }
    It "run command requires --task argument" {
        $out = Invoke-Tian @("run")
        ($out -join " ") | Should -Match "--task|task|prompt"
    }
    It "schedule add requires --name" {
        $out = Invoke-Tian @("schedule", "add")
        ($out -join " ") | Should -Match "Name|name|required|missing|empty"
    }
}

Describe "CLI status command" {
    It "exits 0 for status command" {
        Invoke-Tian @("status") | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}

Describe "CLI jobs command" {
    It "exits 0 for jobs command" {
        Invoke-Tian @("jobs") | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It "exits 0 for 'jobs clear'" {
        Invoke-Tian @("jobs", "clear") | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It "accepts positional job IDs for 'jobs result'" {
        $jobId = "missing-job-$([guid]::NewGuid().ToString('N'))"
        $out = Invoke-Tian @("jobs", "result", $jobId)
        ($out -join " ") | Should -Match "Job '$jobId' not found"
    }
}

Describe "CLI schedule subcommands" {
    It "exits 0 for 'schedule list'" {
        Invoke-Tian @("schedule", "list") | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
    It "schedule remove without --name outputs an error message" {
        $out = Invoke-Tian @("schedule", "remove")
        ($out -join " ") | Should -Match "name|Usage|required"
    }

    It "accepts positional names for 'schedule run'" {
        $scheduleName = "missing-schedule-$([guid]::NewGuid().ToString('N'))"
        $out = Invoke-Tian @("schedule", "run", $scheduleName)
        ($out -join " ") | Should -Match "No schedule named '$scheduleName'"
    }

    It "accepts positional names for 'schedule remove'" {
        $scheduleName = "missing-schedule-$([guid]::NewGuid().ToString('N'))"
        $out = Invoke-Tian @("schedule", "remove", $scheduleName)
        ($out -join " ") | Should -Match "No schedule named '$scheduleName'"
    }
}
