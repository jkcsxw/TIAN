function Show-Page-ApiKey {
    param($Panel, $NavState, $State)

    $backend = $State.SelectedBackend

    $title = New-Label -Text "Connect to Your AI Account" -X 50 -Y 16 -Width 460 -Height 38 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $sub = New-Label -Text "Think of an API key like a password that lets TIAN talk to your AI. You only need to do this once." -X 50 -Y 54 -Width 460 -Height 36 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($sub)

    $sep = New-Separator -X 50 -Y 96 -Width 460
    $Panel.Controls.Add($sep)

    # Step-by-step guide box
    $guidePanel = New-Object System.Windows.Forms.Panel
    $guidePanel.Location = New-Object System.Drawing.Point(50, 106)
    $guidePanel.Size = New-Object System.Drawing.Size(460, 112)
    $guidePanel.BackColor = [System.Drawing.Color]::FromArgb(235, 240, 255)
    $Panel.Controls.Add($guidePanel)

    $howTitle = New-Label -Text "How to get your key (takes about 2 minutes):" -X 10 -Y 8 -Width 440 -Height 20 -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)) -ForeColor $UI_COLOR_ACCENT
    $guidePanel.Controls.Add($howTitle)

    $steps = @(
        "1.  Click the blue button below — it opens the website in your browser",
        "2.  Sign up for a free account (or log in if you already have one)",
        "3.  Click 'Create Key', then copy the key shown on screen",
        "4.  Come back here and paste it into the box below"
    )
    $sy = 30
    foreach ($step in $steps) {
        $lbl = New-Label -Text $step -X 10 -Y $sy -Width 440 -Height 18 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_TEXT
        $guidePanel.Controls.Add($lbl)
        $sy += 19
    }

    # Open browser button — prominent
    if ($backend.apiKeyUrl) {
        $btnOpen = New-Button -Text "Open website to get my key" -X 50 -Y 224 -Width 240 -Height 34 -Primary $true
        $btnOpen.Add_Click({ Start-Process $backend.apiKeyUrl })
        $Panel.Controls.Add($btnOpen)

        $orLbl = New-Label -Text "— then paste it below —" -X 300 -Y 232 -Width 180 -Height 18 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
        $Panel.Controls.Add($orLbl)
    }

    # Key input
    $keyLabel = New-Label -Text "$($backend.apiKeyLabel):" -X 50 -Y 266 -Width 300 -Height 20 -Font (New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($keyLabel)

    $hintLbl = New-Label -Text $backend.apiKeyHint -X 355 -Y 268 -Width 155 -Height 18 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($hintLbl)

    $keyBox = New-TextBox -X 50 -Y 288 -Width 380 -Height 32 -Password $true
    if ($State.ApiKey) { $keyBox.Text = $State.ApiKey }
    $Panel.Controls.Add($keyBox)

    $showCb = New-CheckBox -Text "Show" -X 438 -Y 294 -Width 70 -Height 20
    $showCb.Add_CheckedChanged({
        $keyBox.PasswordChar = if ($showCb.Checked) { [char]0 } else { [char]0x2022 }
    })
    $Panel.Controls.Add($showCb)

    $privNote = New-Label -Text "Your key is saved only on this computer. It is never sent anywhere else." -X 50 -Y 324 -Width 460 -Height 18 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($privNote)

    $errorLbl = New-Label -Text "" -X 50 -Y 346 -Width 460 -Height 20 -Font $UI_FONT_SMALL -ForeColor ([System.Drawing.Color]::FromArgb(220, 60, 60))
    $Panel.Controls.Add($errorLbl)

    # Extra env vars required by selected MCP servers
    $extraVarBoxes = @{}
    if ($State.SelectedMcpServers) {
        $allRequired = $State.SelectedMcpServers | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars }
        $yExtra = 370
        foreach ($ev in $allRequired) {
            $evLabel = New-Label -Text "$($ev.label):" -X 50 -Y $yExtra -Width 300 -Height 18 -Font $UI_FONT_SMALL
            $Panel.Controls.Add($evLabel)
            if ($ev.url) {
                $evLink = New-LinkLabel -Text "Get it here" -X 360 -Y $yExtra -Width 100 -Height 18 -Url $ev.url
                $Panel.Controls.Add($evLink)
            }
            $yExtra += 20
            $evBox = New-TextBox -X 50 -Y $yExtra -Width 460 -Height 26 -Password $true
            $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
            if ($existing) { $evBox.Text = $existing }
            $evBox.Tag = $ev.name
            $Panel.Controls.Add($evBox)
            $extraVarBoxes[$ev.name] = $evBox
            $yExtra += 30
        }
    }

    # Footer buttons
    $btnBack = New-Button -Text "Back" -X 260 -Y 400 -Width 100 -Height 36
    $btnBack.Add_Click({ $NavState.Direction = "Back"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnBack)

    $btnNext = New-Button -Text "Next" -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
    $btnNext.Add_Click({
        $val = $keyBox.Text.Trim()
        if ($val -eq "" -or $val -eq $keyBox.Tag) {
            $errorLbl.Text = "Please paste your API key into the box above."
            return
        }
        $State.ApiKey = $val
        foreach ($kvp in $extraVarBoxes.GetEnumerator()) {
            $State.ExtraEnvVars[$kvp.Key] = $kvp.Value.Text.Trim()
        }
        $NavState.Direction = "Next"
        $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $Panel.Controls.Add($btnNext)
}
