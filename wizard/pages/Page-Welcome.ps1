function Show-Page-Welcome {
    param($Panel, $NavState)

    $title = New-Label -Text (T "welcome.title") -X 50 -Y 60 -Width 460 -Height 45 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $tagline = New-Label -Text (T "welcome.tagline") -X 50 -Y 108 -Width 460 -Height 28 -Font $UI_FONT_SUBTITLE -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($tagline)

    $sep = New-Separator -X 50 -Y 148 -Width 460
    $Panel.Controls.Add($sep)

    $desc = New-Label -Text (T "welcome.desc") -X 50 -Y 162 -Width 460 -Height 72 -Font $UI_FONT_BODY -Wrap $true
    $Panel.Controls.Add($desc)

    $whatTitle = New-Label -Text (T "welcome.what_installed") -X 50 -Y 248 -Width 460 -Height 24 -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($whatTitle)

    $items = @( (T "welcome.item1"), (T "welcome.item2"), (T "welcome.item3") )
    $y = 274
    foreach ($item in $items) {
        $lbl = New-Label -Text $item -X 50 -Y $y -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
        $Panel.Controls.Add($lbl)
        $y += 24
    }

    $note = New-Label -Text (T "welcome.est_time") -X 50 -Y 360 -Width 460 -Height 22 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($note)

    $btnNext = New-Button -Text (T "btn.get_started") -X 390 -Y 400 -Width 120 -Height 36 -Primary $true
    $btnNext.Add_Click({ $NavState.Direction = "Next"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnNext)
}
