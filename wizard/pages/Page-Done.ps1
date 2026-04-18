function Show-Page-Done {
    param($Panel, $NavState, $State, $TianDir)

    $success = $NavState.InstallSuccess -ne $false

    if ($success) {
        $icon  = "OK"
        $titleText = "You're all set!"
        $titleColor = $UI_COLOR_SUCCESS
        $msgText = "Your AI assistant is ready. Here's a summary of what was installed:"
    } else {
        $icon  = "X"
        $titleText = "Setup completed with errors"
        $titleColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
        $msgText = "Some items may not have installed correctly. You can re-run setup.bat to try again."
    }

    $title = New-Label -Text $titleText -X 50 -Y 40 -Width 460 -Height 40 -Font $UI_FONT_TITLE -ForeColor $titleColor
    $Panel.Controls.Add($title)

    $msg = New-Label -Text $msgText -X 50 -Y 82 -Width 460 -Height 36 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($msg)

    $sep = New-Separator -X 50 -Y 128 -Width 460
    $Panel.Controls.Add($sep)

    # Summary
    $y = 144
    $summaryItems = @()
    if ($State.SelectedBackend) {
        $summaryItems += "AI Backend:  $($State.SelectedBackend.displayName)"
    }
    if ($State.SelectedMcpServers -and $State.SelectedMcpServers.Count -gt 0) {
        $names = ($State.SelectedMcpServers | ForEach-Object { $_.displayName }) -join ", "
        $summaryItems += "MCP Tools:   $names"
    }
    if ($State.SelectedSkills -and $State.SelectedSkills.Count -gt 0) {
        $names = ($State.SelectedSkills | ForEach-Object { $_.displayName }) -join ", "
        $summaryItems += "Skills:      $names"
    }

    foreach ($item in $summaryItems) {
        $lbl = New-Label -Text $item -X 50 -Y $y -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_TEXT -Wrap $true
        $Panel.Controls.Add($lbl)
        $y += 26
    }

    $sep2 = New-Separator -X 50 -Y ($y + 6) -Width 460
    $Panel.Controls.Add($sep2)

    $tipTitle = New-Label -Text "What to do next:" -X 50 -Y ($y + 20) -Width 460 -Height 22 -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($tipTitle)

    $tips = @(
        "1. Click 'Launch Now' below to start chatting",
        "2. You can also double-click launcher.bat any time",
        "3. Re-run setup.bat to add more tools or skills"
    )
    $ty = $y + 44
    foreach ($tip in $tips) {
        $lbl = New-Label -Text $tip -X 50 -Y $ty -Width 460 -Height 20 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
        $Panel.Controls.Add($lbl)
        $ty += 22
    }

    # Footer buttons
    $btnFolder = New-Button -Text "Open Folder" -X 50 -Y 400 -Width 130 -Height 36
    $btnFolder.Add_Click({ Start-Process "explorer.exe" $TianDir })
    $Panel.Controls.Add($btnFolder)

    if ($success -and $State.SelectedBackend.cliCommand) {
        $launcherPath = Join-Path $TianDir "launcher.bat"
        $btnLaunch = New-Button -Text "Launch Now" -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
        $btnLaunch.Add_Click({
            if (Test-Path $launcherPath) {
                Start-Process cmd.exe -ArgumentList "/k `"$launcherPath`""
            } else {
                Start-Process cmd.exe -ArgumentList "/k $($State.SelectedBackend.cliCommand)"
            }
        })
        $Panel.Controls.Add($btnLaunch)
    }

    $btnClose = New-Button -Text "Close" -X 220 -Y 400 -Width 100 -Height 36
    $btnClose.Add_Click({ $NavState.Form.Close() })
    $Panel.Controls.Add($btnClose)
}
