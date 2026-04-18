function Show-Page-ApiKey {
    param($Panel, $NavState, $State)

    $backend = $State.SelectedBackend

    $title = New-Label -Text "Enter Your API Key" -X 50 -Y 30 -Width 460 -Height 38 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $sub = New-Label -Text "Your API key connects the AI assistant to your account. It is stored only on your computer." -X 50 -Y 70 -Width 460 -Height 36 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($sub)

    $sep = New-Separator -X 50 -Y 114 -Width 460
    $Panel.Controls.Add($sep)

    $keyLabel = New-Label -Text "$($backend.apiKeyLabel):" -X 50 -Y 134 -Width 460 -Height 22 -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($keyLabel)

    $keyBox = New-TextBox -X 50 -Y 160 -Width 460 -Height 32 -Password $true
    if ($State.ApiKey) { $keyBox.Text = $State.ApiKey }
    $Panel.Controls.Add($keyBox)

    $hintLbl = New-Label -Text $backend.apiKeyHint -X 50 -Y 196 -Width 460 -Height 20 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($hintLbl)

    if ($backend.apiKeyUrl) {
        $helpLink = New-LinkLabel -Text "Don't have a key? Get one here (free to start)" -X 50 -Y 220 -Width 340 -Height 20 -Url $backend.apiKeyUrl
        $Panel.Controls.Add($helpLink)
    }

    # Show / hide toggle
    $showCb = New-CheckBox -Text "Show key" -X 50 -Y 250 -Width 120 -Height 22
    $showCb.Add_CheckedChanged({
        $keyBox.PasswordChar = if ($showCb.Checked) { [char]0 } else { [char]0x2022 }
    })
    $Panel.Controls.Add($showCb)

    $privNote = New-Label -Text "Your key is saved only to your Windows user environment.`nIt never leaves your computer." -X 50 -Y 282 -Width 460 -Height 40 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($privNote)

    # Extra env vars for selected MCP servers that need them
    $extraVarBoxes = @{}
    if ($State.SelectedMcpServers) {
        $allRequired = $State.SelectedMcpServers | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars } | Select-Object -Unique
        $yExtra = 334
        foreach ($ev in $allRequired) {
            $evLabel = New-Label -Text "$($ev.label):" -X 50 -Y $yExtra -Width 460 -Height 20 -Font $UI_FONT_SMALL
            $Panel.Controls.Add($evLabel)
            $yExtra += 20
            $evBox = New-TextBox -X 50 -Y $yExtra -Width 460 -Height 28 -Password $true
            if ([System.Environment]::GetEnvironmentVariable($ev.name, "User")) {
                $evBox.Text = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
            }
            $evBox.Tag = $ev.name
            $Panel.Controls.Add($evBox)
            $extraVarBoxes[$ev.name] = $evBox
            $yExtra += 34
        }
    }

    $errorLbl = New-Label -Text "" -X 50 -Y 370 -Width 460 -Height 22 -Font $UI_FONT_SMALL -ForeColor ([System.Drawing.Color]::FromArgb(220, 60, 60))
    $Panel.Controls.Add($errorLbl)

    # Footer buttons
    $btnBack = New-Button -Text "Back" -X 260 -Y 400 -Width 100 -Height 36
    $btnBack.Add_Click({ $NavState.Direction = "Back"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnBack)

    $btnNext = New-Button -Text "Next" -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
    $btnNext.Add_Click({
        $val = $keyBox.Text.Trim()
        if ($val -eq "" -or $val -eq $keyBox.Tag) {
            $errorLbl.Text = "Please enter your API key to continue."
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
