function Show-Page-Done {
    param($Panel, $NavState, $State, $TianDir)

    $success = $NavState.InstallSuccess -ne $false

    if ($success) {
        $titleText  = T "done.title_ok"
        $titleColor = $UI_COLOR_SUCCESS
        $msgText    = T "done.msg_ok"
    } else {
        $titleText  = T "done.title_err"
        $titleColor = [System.Drawing.Color]::FromArgb(200, 60, 60)
        $msgText    = T "done.msg_err"
    }

    $title = New-Label -Text $titleText -X 50 -Y 40 -Width 460 -Height 40 -Font $UI_FONT_TITLE -ForeColor $titleColor
    $Panel.Controls.Add($title)

    $msg = New-Label -Text $msgText -X 50 -Y 82 -Width 460 -Height 36 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED -Wrap $true
    $Panel.Controls.Add($msg)

    $sep = New-Separator -X 50 -Y 128 -Width 460
    $Panel.Controls.Add($sep)

    $y = 144
    $summaryItems = @()
    if ($State.SelectedBackend) {
        $summaryItems += TF "done.summary_backend" $State.SelectedBackend.displayName
    }
    if ($State.SelectedMcpServers -and $State.SelectedMcpServers.Count -gt 0) {
        $names = ($State.SelectedMcpServers | ForEach-Object { Get-DisplayName $_ }) -join ", "
        $summaryItems += TF "done.summary_mcp" $names
    }
    if ($State.SelectedSkills -and $State.SelectedSkills.Count -gt 0) {
        $names = ($State.SelectedSkills | ForEach-Object { Get-DisplayName $_ }) -join ", "
        $summaryItems += TF "done.summary_skills" $names
    }

    foreach ($item in $summaryItems) {
        $lbl = New-Label -Text $item -X 50 -Y $y -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_TEXT -Wrap $true
        $Panel.Controls.Add($lbl)
        $y += 26
    }

    $sep2 = New-Separator -X 50 -Y ($y + 6) -Width 460
    $Panel.Controls.Add($sep2)

    $tipTitle = New-Label -Text (T "done.next_title") -X 50 -Y ($y + 20) -Width 460 -Height 22 -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($tipTitle)

    $tips = @( (T "done.tip1"), (T "done.tip2"), (T "done.tip3") )
    $ty = $y + 44
    foreach ($tip in $tips) {
        $lbl = New-Label -Text $tip -X 50 -Y $ty -Width 460 -Height 20 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
        $Panel.Controls.Add($lbl)
        $ty += 22
    }

    $btnFolder = New-Button -Text (T "btn.open_folder") -X 50 -Y 400 -Width 130 -Height 36
    $btnFolder.Add_Click({ Start-Process "explorer.exe" $TianDir })
    $Panel.Controls.Add($btnFolder)

    if ($success -and $State.SelectedBackend.cliCommand) {
        $launcherPath = Join-Path $TianDir "launcher.bat"
        $btnLaunch = New-Button -Text (T "btn.launch") -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
        $btnLaunch.Add_Click({
            if (Test-Path $launcherPath) {
                Start-Process cmd.exe -ArgumentList "/k `"$launcherPath`""
            } else {
                $launchCommand = if ($State.SelectedBackend.launchCommand) { $State.SelectedBackend.launchCommand } else { $State.SelectedBackend.cliCommand }
                Start-Process cmd.exe -ArgumentList "/k $launchCommand"
            }
        })
        $Panel.Controls.Add($btnLaunch)
    }

    $btnClose = New-Button -Text (T "btn.close") -X 220 -Y 400 -Width 100 -Height 36
    $btnClose.Add_Click({ $NavState.Form.Close() })
    $Panel.Controls.Add($btnClose)
}
