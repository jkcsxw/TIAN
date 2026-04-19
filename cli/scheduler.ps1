# Scheduler — wraps Windows Task Scheduler (schtasks) to run TIAN tasks on a timed basis
# Schedule definitions stored in ~/.tian/schedules.json

$_tianHome           = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$global:TIAN_SCHEDULES_FILE = Join-Path $_tianHome ".tian" "schedules.json"
$TIAN_DIR_ENV        = $TianDir  # inherited from tian.ps1 scope

function Ensure-ScheduleFile {
    $dir = Split-Path $global:TIAN_SCHEDULES_FILE -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $global:TIAN_SCHEDULES_FILE)) { '[]' | Set-Content $global:TIAN_SCHEDULES_FILE -Encoding UTF8 }
}

function Read-Schedules {
    Ensure-ScheduleFile
    $raw = Get-Content $global:TIAN_SCHEDULES_FILE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '' -or $raw.Trim() -eq '[]') { return [array]@() }
    $parsed = $raw | ConvertFrom-Json
    if ($null -eq $parsed)         { return [array]@() }
    if ($parsed -isnot [array])    { return [array]@($parsed) }
    return [array]$parsed
}

function Save-Schedules {
    param([array]$Schedules)
    Ensure-ScheduleFile
    if ($null -eq $Schedules -or $Schedules.Count -eq 0) {
        '[]' | Set-Content $global:TIAN_SCHEDULES_FILE -Encoding UTF8
    } else {
        ConvertTo-Json $Schedules -Depth 5 | Set-Content $global:TIAN_SCHEDULES_FILE -Encoding UTF8
    }
}

function Invoke-Launchctl {
    param([string]$Action, [string]$PlistFile)
    & launchctl $Action $PlistFile 2>&1
}

function Get-TaskName {
    param([string]$Name)
    return "TIAN_$($Name -replace '[^a-zA-Z0-9_-]','_')"
}

function Add-Schedule {
    param(
        [string]$Name,
        [string]$Prompt,
        [string]$Time,
        [string]$Repeat,
        [string]$DayOfWeek,
        [string]$TianDir
    )

    if (-not $Name)   { Write-Fail "缺少定时任务名称，请使用 --name <名称>。/ Missing schedule name. Use --name <name>"; return }
    if (-not $Prompt) { Write-Fail "缺少任务提示词，请使用 --task \"您的提示词\"。/ Missing task prompt. Use --task \"your prompt\""; return }
    if (-not $Time)   { $Time = "08:00" }
    if (-not $Repeat) { $Repeat = "daily" }

    $schedules = Read-Schedules
    if ($schedules | Where-Object { $_.name -eq $Name }) {
        Write-Fail "名为 '$Name' 的定时任务已存在，请先删除：tian-cli schedule remove $Name / A schedule named '$Name' already exists."
        return
    }

    $platform = if ($PSVersionTable.Platform -eq 'Unix') { uname } else { "" }
    $isMac = $IsMacOS -or ($platform -eq 'Darwin')
    $isLinux = $IsLinux -or ($platform -eq 'Linux')

    if ($isMac) {
        # ── launchd (macOS) ──────────────────────────────────────────────────
        $plistDir   = "$env:HOME/Library/LaunchAgents"
        $plistLabel = "com.tian.$Name"
        $plistFile  = "$plistDir/$plistLabel.plist"
        $cliPath    = Join-Path $TianDir "tian-cli.sh"
        New-Item -ItemType Directory -Path $plistDir -Force | Out-Null

        $hour   = [int]($Time -split ':')[0]
        $minute = [int]($Time -split ':')[1]

        $intervalXml = switch ($Repeat.ToLower()) {
            "hourly" { "<key>StartInterval</key>`n    <integer>3600</integer>" }
            "weekly" { "<key>StartCalendarInterval</key>`n    <dict>`n        <key>Weekday</key><integer>1</integer>`n        <key>Hour</key><integer>$hour</integer>`n        <key>Minute</key><integer>$minute</integer>`n    </dict>" }
            default  { "<key>StartCalendarInterval</key>`n    <dict>`n        <key>Hour</key><integer>$hour</integer>`n        <key>Minute</key><integer>$minute</integer>`n    </dict>" }
        }

        $plistContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plistLabel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$cliPath</string>
        <string>run</string>
        <string>$($Prompt -replace '"','&quot;')</string>
        <string>--background</string>
    </array>
    <key>StandardOutPath</key>
    <string>$env:HOME/.tian/tasks/schedule-$Name.log</string>
    <key>StandardErrorPath</key>
    <string>$env:HOME/.tian/tasks/schedule-$Name.err</string>
    $intervalXml
</dict>
</plist>
"@
        Set-Content -Path $plistFile -Value $plistContent -Encoding UTF8
        Invoke-Launchctl -Action 'load' -PlistFile $plistFile
        Write-Ok "定时任务 '$Name' 已注册到 launchd。/ Schedule '$Name' registered with launchd."

        $entry = [PSCustomObject]@{
            name      = $Name; prompt = $Prompt; time = $Time
            repeat    = $Repeat; plistFile = $plistFile
            createdAt = [System.DateTime]::Now.ToString("o")
        }
    } elseif ($isLinux) {
        Write-Fail "Linux scheduling is not available in the built-in CLI yet. Use 'tian-cli run' directly, or install PowerShell Core only after Linux scheduler support lands."
        return
    } else {
        # ── Windows Task Scheduler ────────────────────────────────────────────
        $taskName = Get-TaskName $Name
        $cliPath  = Join-Path $TianDir "tian-cli.bat"
        $action   = "`"$cliPath`" run `"$($Prompt -replace '"','\"')`" --background --yes"

        $schArgs = @("/Create", "/F", "/TN", $taskName, "/TR", $action, "/ST", $Time)
        switch ($Repeat.ToLower()) {
            "once"   { $schArgs += @("/SC", "ONCE") }
            "hourly" { $schArgs += @("/SC", "HOURLY") }
            "daily"  { $schArgs += @("/SC", "DAILY") }
            "weekly" { $schArgs += @("/SC", "WEEKLY"); if ($DayOfWeek) { $schArgs += @("/D", $DayOfWeek) } }
            default  { $schArgs += @("/SC", "DAILY") }
        }

        $result = Start-Process schtasks -ArgumentList $schArgs -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -ne 0) {
            Write-Fail "创建Windows定时任务失败（退出码 $($result.ExitCode)）。/ Failed to create Windows scheduled task."
            Write-Warn "请以管理员身份运行 tian-cli。/ Try running tian-cli as Administrator."
            return
        }

        $entry = [PSCustomObject]@{
            name      = $Name; taskName = $taskName; prompt = $Prompt
            time      = $Time; repeat = $Repeat; dayOfWeek = $DayOfWeek
            createdAt = [System.DateTime]::Now.ToString("o")
        }
    }

    $schedules += $entry
    Save-Schedules $schedules
    Write-Ok "定时任务 '$Name' 已创建 — $Repeat 每天 $Time 执行。/ Schedule '$Name' created — $Repeat at $Time."
    Write-Info "查看结果 / Results : tian-cli jobs  (首次运行后 / after first run)"
}

function Remove-Schedule {
    param([string]$Name, [string]$TianDir)
    if (-not $Name) { Write-Fail "用法 / Usage: tian-cli schedule remove <名称 name>"; return }

    $schedules = Read-Schedules
    $entry = $schedules | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $entry) { Write-Fail "未找到名为 '$Name' 的定时任务。/ No schedule named '$Name'."; return }

    $platform = if ($PSVersionTable.Platform -eq 'Unix') { uname } else { "" }
    $isMac = $IsMacOS -or ($platform -eq 'Darwin')
    $isLinux = $IsLinux -or ($platform -eq 'Linux')

    if ($isMac) {
        if ($entry.plistFile -and (Test-Path $entry.plistFile)) {
            Invoke-Launchctl -Action 'unload' -PlistFile $entry.plistFile
            Remove-Item $entry.plistFile -ErrorAction SilentlyContinue
        }
    } elseif ($isLinux) {
        # Linux does not have a scheduler integration yet, but stale entries can still be cleaned up.
    } else {
        $result = Start-Process schtasks -ArgumentList "/Delete", "/F", "/TN", $entry.taskName -Wait -PassThru -NoNewWindow
        if ($result.ExitCode -ne 0) { Write-Warn "无法删除Windows定时任务（可能已被删除）。/ Could not remove Windows task (may have already been deleted)." }
    }

    $keep = @($schedules | Where-Object { $_.name -ne $Name })
    Save-Schedules $keep
    Write-Ok "定时任务 '$Name' 已删除。/ Schedule '$Name' removed."
}

function Show-Schedules {
    $schedules = Read-Schedules
    if (-not $schedules -or $schedules.Count -eq 0) {
        Write-Info "暂无定时任务。创建方式：tian-cli schedule add --name <名称> --task \"提示词\" --time 08:00 / No schedules found."
        return
    }

    Write-Header "定时任务列表 / Scheduled Tasks"
    Write-Rule
    foreach ($s in $schedules) {
        Write-Color "  $($s.name.PadRight(22))" Cyan -NoNewline
        Write-Color " $($s.repeat.PadRight(8))" Yellow -NoNewline
        Write-Color " at $($s.time)   " White -NoNewline
        if ($s.dayOfWeek) { Write-Color "($($s.dayOfWeek))  " Gray -NoNewline }
        Write-Host ""
        $preview = ($s.prompt -replace "`n"," ").Substring(0, [Math]::Min(70, $s.prompt.Length))
        Write-Color "  $(" " * 22) $preview" DarkGray
        Write-Host ""
    }
    Write-Rule
    Write-Color "  tian-cli schedule run <name>     run immediately" DarkGray
    Write-Color "  tian-cli schedule remove <name>  delete schedule" DarkGray
    Write-Host ""
}

function Invoke-ScheduleNow {
    param([string]$Name, [string]$TianDir)
    if (-not $Name) { Write-Fail "Usage: tian-cli schedule run <name>"; return }

    $schedules = Read-Schedules
    $entry = $schedules | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $entry) { Write-Fail "No schedule named '$Name'."; return }

    Write-Info "Running scheduled task '$Name' now..."
    Invoke-Task -Prompt $entry.prompt -TianDir $TianDir -Background -JobName $Name
}
