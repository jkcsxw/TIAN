$UI_FONT_BODY   = New-Object System.Drawing.Font("Segoe UI", 10)
$UI_FONT_TITLE  = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$UI_FONT_SUBTITLE = New-Object System.Drawing.Font("Segoe UI", 11)
$UI_FONT_SMALL  = New-Object System.Drawing.Font("Segoe UI", 9)
$UI_COLOR_BG    = [System.Drawing.Color]::FromArgb(245, 247, 250)
$UI_COLOR_ACCENT = [System.Drawing.Color]::FromArgb(99, 102, 241)
$UI_COLOR_TEXT  = [System.Drawing.Color]::FromArgb(30, 30, 30)
$UI_COLOR_MUTED = [System.Drawing.Color]::FromArgb(100, 100, 120)
$UI_COLOR_SUCCESS = [System.Drawing.Color]::FromArgb(22, 163, 74)
$UI_COLOR_WHITE = [System.Drawing.Color]::White

function New-Panel {
    param(
        [int]$X = 0, [int]$Y = 0,
        [int]$Width = 560, [int]$Height = 420
    )
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size = New-Object System.Drawing.Size($Width, $Height)
    $p.BackColor = $UI_COLOR_BG
    return $p
}

function New-Label {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 460, [int]$Height = 30,
        [System.Drawing.Font]$Font = $UI_FONT_BODY,
        [System.Drawing.Color]$ForeColor = $UI_COLOR_TEXT,
        [bool]$Wrap = $false
    )
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text
    $lbl.Location = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size = New-Object System.Drawing.Size($Width, $Height)
    $lbl.Font = $Font
    $lbl.ForeColor = $ForeColor
    if ($Wrap) { $lbl.AutoSize = $false }
    return $lbl
}

function New-TextBox {
    param(
        [int]$X, [int]$Y,
        [int]$Width = 440, [int]$Height = 32,
        [string]$PlaceholderText = "",
        [bool]$Password = $false
    )
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point($X, $Y)
    $tb.Size = New-Object System.Drawing.Size($Width, $Height)
    $tb.Font = $UI_FONT_BODY
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    if ($Password) { $tb.PasswordChar = [char]0x2022 }
    if ($PlaceholderText) {
        $tb.ForeColor = $UI_COLOR_MUTED
        $tb.Text = $PlaceholderText
        $tb.Add_Enter({
            if ($this.Text -eq $this.Tag) {
                $this.Text = ""
                $this.ForeColor = $UI_COLOR_TEXT
            }
        })
        $tb.Add_Leave({
            if ($this.Text -eq "") {
                $this.Text = $this.Tag
                $this.ForeColor = $UI_COLOR_MUTED
            }
        })
        $tb.Tag = $PlaceholderText
    }
    return $tb
}

function New-Button {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 120, [int]$Height = 36,
        [bool]$Primary = $false
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, $Height)
    $btn.Font = $UI_FONT_BODY
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $btn.BackColor = $UI_COLOR_ACCENT
        $btn.ForeColor = $UI_COLOR_WHITE
        $btn.FlatAppearance.BorderSize = 0
    } else {
        $btn.BackColor = [System.Drawing.Color]::FromArgb(220, 220, 235)
        $btn.ForeColor = $UI_COLOR_TEXT
        $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
    }
    return $btn
}

function New-CheckBox {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 440, [int]$Height = 24,
        [bool]$Checked = $false
    )
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $Text
    $cb.Location = New-Object System.Drawing.Point($X, $Y)
    $cb.Size = New-Object System.Drawing.Size($Width, $Height)
    $cb.Font = $UI_FONT_BODY
    $cb.ForeColor = $UI_COLOR_TEXT
    $cb.Checked = $Checked
    return $cb
}

function New-RadioButton {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 460, [int]$Height = 22,
        [bool]$Checked = $false
    )
    $rb = New-Object System.Windows.Forms.RadioButton
    $rb.Text = $Text
    $rb.Location = New-Object System.Drawing.Point($X, $Y)
    $rb.Size = New-Object System.Drawing.Size($Width, $Height)
    $rb.Font = $UI_FONT_BODY
    $rb.ForeColor = $UI_COLOR_TEXT
    $rb.Checked = $Checked
    return $rb
}

function New-RichTextBox {
    param(
        [int]$X, [int]$Y,
        [int]$Width = 460, [int]$Height = 200
    )
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Location = New-Object System.Drawing.Point($X, $Y)
    $rtb.Size = New-Object System.Drawing.Size($Width, $Height)
    $rtb.Font = New-Object System.Drawing.Font("Consolas", 9)
    $rtb.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 30)
    $rtb.ForeColor = [System.Drawing.Color]::FromArgb(180, 255, 180)
    $rtb.ReadOnly = $true
    $rtb.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    return $rtb
}

function New-ProgressBar {
    param(
        [int]$X, [int]$Y,
        [int]$Width = 460, [int]$Height = 20
    )
    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Location = New-Object System.Drawing.Point($X, $Y)
    $pb.Size = New-Object System.Drawing.Size($Width, $Height)
    $pb.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $pb.Minimum = 0
    $pb.Maximum = 100
    return $pb
}

function New-LinkLabel {
    param(
        [string]$Text,
        [int]$X, [int]$Y,
        [int]$Width = 300, [int]$Height = 22,
        [string]$Url = ""
    )
    $ll = New-Object System.Windows.Forms.LinkLabel
    $ll.Text = $Text
    $ll.Location = New-Object System.Drawing.Point($X, $Y)
    $ll.Size = New-Object System.Drawing.Size($Width, $Height)
    $ll.Font = $UI_FONT_SMALL
    $ll.LinkColor = $UI_COLOR_ACCENT
    if ($Url) {
        $ll.Tag = $Url
        $ll.Add_LinkClicked({ Start-Process $this.Tag })
    }
    return $ll
}

function New-Separator {
    param([int]$X, [int]$Y, [int]$Width = 460)
    $sep = New-Object System.Windows.Forms.Panel
    $sep.Location = New-Object System.Drawing.Point($X, $Y)
    $sep.Size = New-Object System.Drawing.Size($Width, 1)
    $sep.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
    return $sep
}

function New-ScrollPanel {
    param(
        [int]$X, [int]$Y,
        [int]$Width = 460, [int]$Height = 260
    )
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Location = New-Object System.Drawing.Point($X, $Y)
    $pnl.Size = New-Object System.Drawing.Size($Width, $Height)
    $pnl.AutoScroll = $true
    $pnl.BackColor = $UI_COLOR_BG
    return $pnl
}

function Append-Log {
    param(
        [System.Windows.Forms.RichTextBox]$LogBox,
        [string]$Message,
        [string]$Color = "normal"
    )
    $colorMap = @{
        "normal"  = [System.Drawing.Color]::FromArgb(180, 255, 180)
        "info"    = [System.Drawing.Color]::FromArgb(150, 200, 255)
        "success" = [System.Drawing.Color]::FromArgb(100, 255, 100)
        "warn"    = [System.Drawing.Color]::FromArgb(255, 220, 100)
        "error"   = [System.Drawing.Color]::FromArgb(255, 100, 100)
    }
    $LogBox.SelectionStart = $LogBox.TextLength
    $LogBox.SelectionLength = 0
    $LogBox.SelectionColor = $colorMap[$Color]
    $LogBox.AppendText("$Message`n")
    $LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
