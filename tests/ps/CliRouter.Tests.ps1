BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"

    # Stub external commands that tian.ps1 calls at module level
    function global:Write-Ok   { param($t) }
    function global:Write-Info { param($t) }
    function global:Write-Warn { param($t) }
    function global:Write-Fail { param($t) Write-Error $t }

    # Capture invoked sub-commands
    $script:Invoked = @()

    # Stub runner and scheduler to avoid real I/O
    function global:Invoke-Task      { param($p,$b,$bg,$n) $script:Invoked += "run:$p" }
    function global:Show-Jobs        { $script:Invoked += "show-jobs" }
    function global:Clear-Jobs       { param([switch]$All) $script:Invoked += "clear-jobs:$All" }
    function global:Add-Schedule     { param($Name,$Prompt,$Time,$Repeat,$DayOfWeek,$TianDir) $script:Invoked += "add-sched:$Name" }
    function global:Remove-Schedule  { param($Name,$TianDir) $script:Invoked += "rm-sched:$Name" }
    function global:Show-Schedules   { $script:Invoked += "show-scheds" }

    $script:TianRoot = Get-TianRoot
}

Describe "CLI help output" {
    It "prints usage when no arguments given" {
        $out = & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" 2>&1
        $out | Should -Match "Usage"
    }
    It "prints usage for 'help' command" {
        $out = & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" help 2>&1
        $out | Should -Match "Usage"
    }
}

Describe "CLI argument validation" {
    It "rejects unknown command with non-zero exit" {
        & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" unknown-command 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }
    It "run command requires --task argument" {
        $out = & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" run 2>&1
        ($out -join " ") | Should -Match "--task|task"
    }
    It "schedule add requires --name and --task" {
        $out = & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" schedule add 2>&1
        ($out -join " ") | Should -Match "--name|--task|required"
    }
}

Describe "CLI status command" {
    It "exits 0 for status command" {
        & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" status 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe "CLI jobs command" {
    It "exits 0 for jobs command" {
        & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" jobs 2>&1
        $LASTEXITCODE | Should -Be 0
    }
    It "exits 0 for 'jobs clear'" {
        & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" jobs clear 2>&1
        $LASTEXITCODE | Should -Be 0
    }
}

Describe "CLI schedule subcommands" {
    It "exits 0 for 'schedule list'" {
        & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" schedule list 2>&1
        $LASTEXITCODE | Should -Be 0
    }
    It "schedule remove requires --name" {
        $out = & pwsh -NoProfile -File "$script:TianRoot/cli/tian.ps1" schedule remove 2>&1
        ($out -join " ") | Should -Match "--name|required"
    }
}
