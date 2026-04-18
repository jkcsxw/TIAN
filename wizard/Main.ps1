param([string]$TianDir = (Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent))

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Load lib modules
$libDir = Join-Path $PSScriptRoot "lib"
. "$libDir\UiHelpers.ps1"
. "$libDir\Catalog.ps1"
. "$libDir\NodeInstaller.ps1"
. "$libDir\BackendInstaller.ps1"
. "$libDir\EnvManager.ps1"
. "$libDir\McpConfigurator.ps1"
. "$libDir\SkillInstaller.ps1"

# Load pages
$pagesDir = Join-Path $PSScriptRoot "pages"
. "$pagesDir\Page-Welcome.ps1"
. "$pagesDir\Page-Backend.ps1"
. "$pagesDir\Page-ApiKey.ps1"
. "$pagesDir\Page-McpServers.ps1"
. "$pagesDir\Page-Skills.ps1"
. "$pagesDir\Page-Install.ps1"
. "$pagesDir\Page-Done.ps1"

# Load catalog
$catalog = Get-Catalog -TianDir $TianDir

# Shared session state
$state = @{
    SelectedBackend    = $null
    ApiKey             = ""
    ExtraEnvVars       = @{}
    SelectedMcpServers = @()
    SelectedSkills     = @()
}

# Nav state (shared reference across page callbacks via closure)
$navState = @{
    Direction      = "Next"
    InstallSuccess = $true
    Form           = $null
}

# Page sequence: ordered list of function names
$pages = @(
    "Welcome",
    "Backend",
    "ApiKey",
    "McpServers",
    "Skills",
    "Install",
    "Done"
)

$currentPage = 0

# Build main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Tian Setup — Talking Is All you Need"
$form.Size = New-Object System.Drawing.Size(580, 500)
$form.MinimumSize = New-Object System.Drawing.Size(580, 500)
$form.MaximumSize = New-Object System.Drawing.Size(580, 500)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $UI_COLOR_BG
$form.AutoScroll = $false
$navState.Form = $form

# Header bar
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 8
$headerPanel.BackColor = $UI_COLOR_ACCENT
$form.Controls.Add($headerPanel)

# Progress indicator label (step X of Y)
$stepLabel = New-Object System.Windows.Forms.Label
$stepLabel.Font = $UI_FONT_SMALL
$stepLabel.ForeColor = $UI_COLOR_MUTED
$stepLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$stepLabel.Size = New-Object System.Drawing.Size(120, 20)
$stepLabel.Location = New-Object System.Drawing.Point(440, 452)
$form.Controls.Add($stepLabel)

# Page container panel
$pageContainer = New-Object System.Windows.Forms.Panel
$pageContainer.Location = New-Object System.Drawing.Point(0, 8)
$pageContainer.Size = New-Object System.Drawing.Size(560, 444)
$pageContainer.BackColor = $UI_COLOR_BG
$form.Controls.Add($pageContainer)

function Show-CurrentPage {
    $pageContainer.Controls.Clear()
    $pageName = $pages[$currentPage]

    # Show / hide Install page back button
    $isInstall = ($pageName -eq "Install")
    $isDone    = ($pageName -eq "Done")

    $panel = New-Panel -X 0 -Y 0 -Width 560 -Height 444
    $pageContainer.Controls.Add($panel)

    $showTotal = $pages.Count - 2  # don't count Install and Done
    $showCurrent = [Math]::Min($currentPage + 1, $showTotal)
    if ($isDone -or $isInstall) {
        $stepLabel.Text = ""
    } else {
        $stepLabel.Text = "Step $showCurrent of $showTotal"
    }

    $invokeArgs = @($panel, $navState, $state, $catalog, $TianDir)

    switch ($pageName) {
        "Welcome"    { Show-Page-Welcome    $panel $navState }
        "Backend"    { Show-Page-Backend    $panel $navState $state $catalog }
        "ApiKey"     { Show-Page-ApiKey     $panel $navState $state }
        "McpServers" { Show-Page-McpServers $panel $navState $state $catalog }
        "Skills"     { Show-Page-Skills     $panel $navState $state $catalog }
        "Install"    { Show-Page-Install    $panel $navState $state $catalog $TianDir }
        "Done"       { Show-Page-Done       $panel $navState $state $TianDir }
    }

    $pageContainer.Refresh()
}

# Navigation loop — each page is shown in a modal-like DialogResult loop
Show-CurrentPage

while ($true) {
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::Cancel -or $form.IsDisposed) {
        break
    }

    if ($navState.Direction -eq "Next") {
        if ($currentPage -lt $pages.Count - 1) {
            $currentPage++
        } else {
            break
        }
    } elseif ($navState.Direction -eq "Back") {
        if ($currentPage -gt 0) {
            $currentPage--
        }
    } else {
        break
    }

    $navState.Direction = ""
    $form.DialogResult = [System.Windows.Forms.DialogResult]::None

    Show-CurrentPage
}

if (-not $form.IsDisposed) {
    $form.Close()
    $form.Dispose()
}
