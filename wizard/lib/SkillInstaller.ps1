function Install-Skills {
    param(
        [array]$SelectedSkills,
        [string]$TianDir,
        [System.Windows.Forms.RichTextBox]$LogBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar
    )

    if (-not $SelectedSkills -or $SelectedSkills.Count -eq 0) {
        Append-Log $LogBox "No skills selected — skipping." "info"
        return
    }

    $skillsDir = "$env:USERPROFILE\.tian\skills"
    if (-not (Test-Path $skillsDir)) {
        New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
    }

    $step = [Math]::Floor(10 / [Math]::Max($SelectedSkills.Count, 1))

    foreach ($skill in $SelectedSkills) {
        Append-Log $LogBox "Installing skill: $($skill.displayName)..." "info"

        switch ($skill.source) {
            "builtin" {
                $srcPath = Join-Path $TianDir $skill.promptFile
                if (Test-Path $srcPath) {
                    $destPath = Join-Path $skillsDir "$($skill.id).md"
                    Copy-Item $srcPath $destPath -Force
                    Append-Log $LogBox "$($skill.displayName) installed." "success"
                } else {
                    Append-Log $LogBox "Skill file not found: $($skill.promptFile)" "warn"
                }
            }
            "npm" {
                $result = Start-Process npm -ArgumentList "install -g $($skill.npmPackage)" -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -eq 0) {
                    Append-Log $LogBox "$($skill.displayName) installed via npm." "success"
                } else {
                    Append-Log $LogBox "Failed to install $($skill.displayName)." "error"
                }
            }
            "git" {
                $destDir = Join-Path $skillsDir $skill.id
                $result = Start-Process git -ArgumentList "clone $($skill.gitUrl) `"$destDir`"" -Wait -PassThru -NoNewWindow
                if ($result.ExitCode -eq 0) {
                    Append-Log $LogBox "$($skill.displayName) cloned from git." "success"
                } else {
                    Append-Log $LogBox "Failed to clone $($skill.displayName)." "error"
                }
            }
        }

        $ProgressBar.Value = [Math]::Min($ProgressBar.Value + $step, 100)
    }

    Append-Log $LogBox "Skills installed to: $skillsDir" "success"
}
