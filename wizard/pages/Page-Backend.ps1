function Show-Page-Backend {
    param($Panel, $NavState, $State, $Catalog)

    $title = New-Label -Text (T "backend.title") -X 50 -Y 30 -Width 460 -Height 38 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $sub = New-Label -Text (T "backend.subtitle") -X 50 -Y 70 -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($sub)

    $sep = New-Separator -X 50 -Y 100 -Width 460
    $Panel.Controls.Add($sep)

    $radioButtons = @()
    $y = 116
    $defaultId = if ($State.SelectedBackend) { $State.SelectedBackend.id } else { $Catalog.backends[0].id }

    foreach ($backend in $Catalog.backends) {
        $isSelected = ($backend.id -eq $defaultId)

        $rb = New-RadioButton -Text (Get-DisplayName $backend) -X 50 -Y $y -Width 420 -Height 22 -Checked $isSelected
        $rb.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $rb.Tag = $backend.id
        $Panel.Controls.Add($rb)
        $radioButtons += $rb

        $descLbl = New-Label -Text (Get-Description $backend) -X 72 -Y ($y + 22) -Width 420 -Height 36 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED -Wrap $true
        $Panel.Controls.Add($descLbl)

        if ($backend.apiKeyUrl) {
            $link = New-LinkLabel -Text (T "btn.get_key_link") -X 72 -Y ($y + 58) -Width 140 -Height 18 -Url $backend.apiKeyUrl
            $Panel.Controls.Add($link)
        }

        $y += 90

        $lineSep = New-Separator -X 50 -Y $y -Width 460
        $Panel.Controls.Add($lineSep)
        $y += 10
    }

    $btnBack = New-Button -Text (T "btn.back") -X 260 -Y 400 -Width 100 -Height 36
    $btnBack.Add_Click({ $NavState.Direction = "Back"; $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK })
    $Panel.Controls.Add($btnBack)

    $btnNext = New-Button -Text (T "btn.next") -X 370 -Y 400 -Width 140 -Height 36 -Primary $true
    $btnNext.Add_Click({
        $selected = $radioButtons | Where-Object { $_.Checked } | Select-Object -First 1
        if ($selected) {
            $State.SelectedBackend = $Catalog.backends | Where-Object { $_.id -eq $selected.Tag } | Select-Object -First 1
        }
        $NavState.Direction = "Next"
        $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
    $Panel.Controls.Add($btnNext)
}
