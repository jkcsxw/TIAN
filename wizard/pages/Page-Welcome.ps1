function Show-Page-Welcome {
    param($Panel, $NavState)

    # Header
    $title = New-Label -Text "Welcome to Tian" -X 50 -Y 60 -Width 460 -Height 45 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $tagline = New-Label -Text "Talking Is All you Need" -X 50 -Y 108 -Width 460 -Height 28 -Font $UI_FONT_SUBTITLE -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($tagline)

    $sep = New-Separator -X 50 -Y 148 -Width 460
    $Panel.Controls.Add($sep)

    $desc = New-Label -Text "This wizard will set up a powerful AI assistant on your computer.`n`nNo coding knowledge required. Just follow the steps, and you will be chatting with AI in minutes." -X 50 -Y 162 -Width 460 -Height 72 -Font $UI_FONT_BODY -Wrap $true
    $Panel.Controls.Add($desc)

    $whatTitle = New-Label -Text "What will be installed:" -X 50 -Y 248 -Width 460 -Height 24 -Font (New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold))
    $Panel.Controls.Add($whatTitle)

    $items = @(
        "  Your chosen AI assistant (Claude, Codex, or others)",
        "  Tools that let your AI access files, the web, and more",
        "  Skill presets for your daily use or business"
    )
    $y = 274
    foreach ($item in $items) {
        $lbl = New-Label -Text $item -X 50 -Y $y -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
        $Panel.Controls.Add($lbl)
        $y += 24
    }

    $note = New-Label -Text "Estimated time: 3-10 minutes depending on your internet speed." -X 50 -Y 360 -Width 460 -Height 22 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($note)

    # Footer buttons
    $btnNext = New-Button -Text "Get Started" -X 390 -Y 400 -Width 120 -Height 36 -Primary $true
    $btnNext.Add_Click({ $NavState.Direction = "Next"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnNext)
}
