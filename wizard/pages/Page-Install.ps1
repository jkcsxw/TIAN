function Show-Page-Install {
    param($Panel, $NavState, $State, $Catalog, $TianDir)

    $title = New-Label -Text "Installing..." -X 50 -Y 20 -Width 460 -Height 38 -Font $UI_FONT_TITLE -ForeColor $UI_COLOR_ACCENT
    $Panel.Controls.Add($title)

    $sub = New-Label -Text "Please wait while Tian sets everything up. This may take a few minutes." -X 50 -Y 58 -Width 460 -Height 22 -Font $UI_FONT_BODY -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($sub)

    $sep = New-Separator -X 50 -Y 88 -Width 460
    $Panel.Controls.Add($sep)

    $progressBar = New-ProgressBar -X 50 -Y 100 -Width 460 -Height 18
    $Panel.Controls.Add($progressBar)

    $statusLbl = New-Label -Text "Preparing..." -X 50 -Y 124 -Width 460 -Height 20 -Font $UI_FONT_SMALL -ForeColor $UI_COLOR_MUTED
    $Panel.Controls.Add($statusLbl)

    $logBox = New-RichTextBox -X 50 -Y 150 -Width 460 -Height 232
    $Panel.Controls.Add($logBox)

    # Run installation once the page is shown
    $Panel.Add_VisibleChanged({
        if (-not $Panel.Visible) { return }
        if ($Panel.Tag -eq "done") { return }
        $Panel.Tag = "done"

        $NavState.InstallSuccess = $true

        try {
            # Step 1: Node.js
            $statusLbl.Text = "Step 1/5: Checking Node.js..."
            [System.Windows.Forms.Application]::DoEvents()
            $ok = Install-Node -LogBox $logBox -ProgressBar $progressBar
            if (-not $ok) { throw "Node.js installation failed." }

            # Step 2: AI backend
            $statusLbl.Text = "Step 2/5: Installing $($State.SelectedBackend.displayName)..."
            [System.Windows.Forms.Application]::DoEvents()
            $ok = Install-Backend -Backend $State.SelectedBackend -LogBox $logBox -ProgressBar $progressBar
            if (-not $ok) { throw "Backend installation failed." }

            # Step 3: API key
            $statusLbl.Text = "Step 3/5: Saving API key..."
            [System.Windows.Forms.Application]::DoEvents()
            Set-ApiKey -Backend $State.SelectedBackend -ApiKey $State.ApiKey -LogBox $logBox
            if ($State.ExtraEnvVars) {
                foreach ($kvp in $State.ExtraEnvVars.GetEnumerator()) {
                    if ($kvp.Value) {
                        Set-ExtraEnvVar -Name $kvp.Key -Value $kvp.Value -LogBox $logBox
                    }
                }
            }
            $progressBar.Value = [Math]::Min($progressBar.Value + 10, 100)

            # Step 4: MCP servers
            $statusLbl.Text = "Step 4/5: Configuring MCP tools..."
            [System.Windows.Forms.Application]::DoEvents()
            Set-McpServers -Backend $State.SelectedBackend -SelectedServers $State.SelectedMcpServers -LogBox $logBox -ProgressBar $progressBar

            # Step 5: Skills
            $statusLbl.Text = "Step 5/5: Installing skills..."
            [System.Windows.Forms.Application]::DoEvents()
            Install-Skills -SelectedSkills $State.SelectedSkills -TianDir $TianDir -LogBox $logBox -ProgressBar $progressBar

            # Write launcher
            Write-Launcher -Backend $State.SelectedBackend -TianDir $TianDir -LogBox $logBox

            $progressBar.Value = 100
            $statusLbl.Text = "Installation complete!"
            $statusLbl.ForeColor = $UI_COLOR_SUCCESS
            Append-Log $logBox "" "normal"
            Append-Log $logBox "=== All done! ===" "success"

        } catch {
            $NavState.InstallSuccess = $false
            $statusLbl.Text = "Installation encountered an error."
            $statusLbl.ForeColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
            Append-Log $logBox "ERROR: $_" "error"
        }

        # Auto-advance after a short delay
        Start-Sleep -Milliseconds 800
        $NavState.Direction = "Next"
        $NavState.Form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    })
}
