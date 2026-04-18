BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/SkillInstaller.ps1"
    $script:LogMessages = @()
}

Describe "Install-Skills" {
    BeforeEach {
        $script:TempDir = New-TestTempDir
        $script:SkillsDir = Join-Path $script:TempDir "skills"
        $script:TianDir   = Join-Path $script:TempDir "tian"
        $script:LogMessages = @()

        # Create a fake skill prompt file inside faux TianDir
        New-Item -ItemType Directory -Path (Join-Path $script:TianDir "skills") -Force | Out-Null
        "# Email Skill" | Set-Content (Join-Path $script:TianDir "skills/email-assistant.md")

        # Override skills dir so real function writes to our temp
        $env:USERPROFILE = $script:TempDir
        $env:HOME        = $script:TempDir
    }
    AfterEach {
        Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "skips when selected skills is empty and logs info" {
        Install-Skills -SelectedSkills @() -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar)
        $script:LogMessages | Should -Contain "No skills selected — skipping."
    }
    It "skips when selected skills is null" {
        { Install-Skills -SelectedSkills $null -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar) } | Should -Not -Throw
    }
    It "copies builtin skill to skills directory" {
        $skill = [PSCustomObject]@{
            id         = "email-assistant"
            displayName = "Email Assistant"
            source      = "builtin"
            promptFile  = "skills/email-assistant.md"
        }
        Install-Skills -SelectedSkills @($skill) -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar)
        $dest = Join-Path $script:TempDir ".tian/skills/email-assistant.md"
        Test-Path $dest | Should -BeTrue
    }
    It "creates skills directory if it does not exist" {
        $skill = [PSCustomObject]@{
            id = "email-assistant"; displayName = "EA"
            source = "builtin"; promptFile = "skills/email-assistant.md"
        }
        Install-Skills -SelectedSkills @($skill) -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar)
        Test-Path (Join-Path $script:TempDir ".tian/skills") | Should -BeTrue
    }
    It "logs a warning when builtin skill file does not exist" {
        $skill = [PSCustomObject]@{
            id = "missing-skill"; displayName = "Missing"
            source = "builtin"; promptFile = "skills/does-not-exist.md"
        }
        Install-Skills -SelectedSkills @($skill) -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar)
        $script:LogMessages | Where-Object { $_ -match "not found" } | Should -Not -BeNullOrEmpty
    }
    It "installs multiple skills" {
        "# Meeting Skill" | Set-Content (Join-Path $script:TianDir "skills/meeting-notes.md")
        $skills = @(
            [PSCustomObject]@{ id = "email-assistant"; displayName = "Email"; source = "builtin"; promptFile = "skills/email-assistant.md" },
            [PSCustomObject]@{ id = "meeting-notes";   displayName = "Meeting"; source = "builtin"; promptFile = "skills/meeting-notes.md" }
        )
        Install-Skills -SelectedSkills $skills -TianDir $script:TianDir -LogBox $null -ProgressBar (New-FakeProgressBar)
        Test-Path (Join-Path $script:TempDir ".tian/skills/email-assistant.md") | Should -BeTrue
        Test-Path (Join-Path $script:TempDir ".tian/skills/meeting-notes.md")   | Should -BeTrue
    }
}
