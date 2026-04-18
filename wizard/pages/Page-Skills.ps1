function Show-Page-Skills {
    param($Panel, $NavState, $State, $Catalog)

    $title = New-Label -Text "Choose Skills" -X 50 -Y 20 -Width 460 -Height 38 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $sub = New-Label -Text "Skills are pre-built prompts that help your AI with specific tasks. Pick what fits your needs." -X 50 -Y 58 -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($sub)

    $sep = New-Separator -X 50 -Y 88 -Width 460
    $Panel.Controls.Add($sep)

    $scrollPanel = New-ScrollPanel -X 50 -Y 96 -Width 460 -Height 280
    $Panel.Controls.Add($scrollPanel)

    $defaults = if ($State.SelectedBackend.defaultSkills) { $State.SelectedBackend.defaultSkills } else { @() }
    $preSelected = if ($State.SelectedSkills) { $State.SelectedSkills | ForEach-Object { $_.id } } else { $defaults }

    $checkBoxes = @{}
    $groups = $Catalog.skills | Group-Object { $_.category }
    $y = 4

    foreach ($group in $groups) {
        $groupLbl = New-Label -Text $group.Name -X 4 -Y $y -Width 440 -Height 22 -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -ForeColor $UI_COLOR_ACCENT
        $scrollPanel.Controls.Add($groupLbl)
        $y += 24

        foreach ($skill in $group.Group) {
            $isChecked = $preSelected -contains $skill.id
            $cb = New-CheckBox -Text $skill.displayName -X 10 -Y $y -Width 200 -Height 22 -Checked $isChecked
            $cb.Tag = $skill.id
            $scrollPanel.Controls.Add($cb)
            $checkBoxes[$skill.id] = $cb

            $descLbl = New-Label -Text $skill.description -X 220 -Y $y -Width 220 -Height 36 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED -Wrap $true
            $scrollPanel.Controls.Add($descLbl)

            $y += 44
        }
        $y += 6
    }

    $noteLbl = New-Label -Text "You can skip all skills and install them later." -X 50 -Y 384 -Width 300 -Height 20 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($noteLbl)

    # Footer buttons
    $btnBack = New-Button -Text "Back" -X 260 -Y 400 -Width 100 -Height 36
    $btnBack.Add_Click({ $NavState.Direction = "Back"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnBack)

    $btnNext = New-Button -Text "Install Now" -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
    $btnNext.Add_Click({
        $State.SelectedSkills = @(
            $Catalog.skills | Where-Object {
                $cb = $checkBoxes[$_.id]
                $cb -and $cb.Checked
            }
        )
        $NavState.Direction = "Next"
        $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $Panel.Controls.Add($btnNext)
}
