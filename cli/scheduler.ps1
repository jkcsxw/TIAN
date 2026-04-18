# Scheduler — wraps Windows Task Scheduler (schtasks) to run TIAN tasks on a timed basis
# Schedule definitions stored in ~/.tian/schedules.json

$TIAN_SCHEDULES_FILE = "$env:USERPROFILE\.tian\schedules.json"
$TIAN_DIR_ENV        = $TianDir  # inherited from tian.ps1 scope

function Ensure-ScheduleFile {
    $dir = Split-Path $TIAN_SCHEDULES_FILE -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $TIAN_SCHEDULES_FILE)) { '[]' | Set-Content $TIAN_SCHEDULES_FILE -Encoding UTF8 }
}

function Read-Schedules {
    Ensure-ScheduleFile
    $raw = Get-Content $TIAN_SCHEDULES_FILE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '') { return @() }
    $parsed = $raw | ConvertFrom-Json
    if ($parsed -isnot [array]) { return @($parsed) }
    return $parsed
}

function Save-Schedules {
    param([array]$Schedules)
    Ensure-ScheduleFile
    $Schedules | ConvertTo-Json -Depth 5 | Set-Content $TIAN_SCHEDULES_FILE -Encoding UTF8
}

function Get-TaskName {
    param([string]$Name)
    return "TIAN_$($Name -replace '[^a-zA-Z0-9_-]','_')"
}

function Add-Schedule {
    param(
        [string]$Name,
        [string]$Prompt,
        [string]$Time,        # e.g. "08:00"
        [string]$Repeat,      # once | daily | weekly | hourly
        [string]$DayOfWeek,   # MON,TUE,... (weekly only)
        [string]$TianDir
    )

    if (-not $Name)   { Write-Fail "Missing schedule name. Use --name <name>"; return }
    if (-not $Prompt) { Write-Fail "Missing task prompt. Use --task `"your prompt`""; return }
    if (-not $Time)   { $Time = "08:00" }
    if (-not $Repeat) { $Repeat = "daily" }

    $schedules = Read-Schedules
    if ($schedules | Where-Object { $_.name -eq $Name }) {
        Write-Fail "A schedule named '$Name' already exists. Remove it first with: tian-cli schedule remove $Name"
        return
    }

    $taskName  = Get-TaskName $Name
    $cliPath   = Join-Path $TianDir "tian-cli.bat"
    $action    = "`"$cliPath`" run `"$($Prompt -replace '"','\"')`" --background --yes"

    # Build schtasks arguments
    $schArgs = @(
        "/Create", "/F",
        "/TN", $taskName,
        "/TR", $action,
        "/ST", $Time
    )

    switch ($Repeat.ToLower()) {
        "once"    { $schArgs += @("/SC", "ONCE") }
        "hourly"  { $schArgs += @("/SC", "HOURLY") }
        "daily"   { $schArgs += @("/SC", "DAILY") }
        "weekly"  {
            $schArgs += @("/SC", "WEEKLY")
            if ($DayOfWeek) { $schArgs += @("/D", $DayOfWeek) }
        }
        default   { $schArgs += @("/SC", "DAILY") }
    }

    $result = Start-Process schtasks -ArgumentList $schArgs -Wait -PassThru -NoNewWindow
    if ($result.ExitCode -ne 0) {
        Write-Fail "Failed to create Windows scheduled task (exit $($result.ExitCode))."
        Write-Warn "Try running tian-cli as Administrator."
        return
    }

    $entry = [PSCustomObject]@{
        name      = $Name
        taskName  = $taskName
        prompt    = $Prompt
        time      = $Time
        repeat    = $Repeat
        dayOfWeek = $DayOfWeek
        createdAt = [System.DateTime]::Now.ToString("o")
    }
    $schedules += $entry
    Save-Schedules $schedules

    Write-Ok "Schedule '$Name' created."
    Write-Info "Task    : $Prompt"
    Write-Info "Runs    : $Repeat at $Time"
    Write-Info "Results : tian-cli jobs  (after first run)"
}

function Remove-Schedule {
    param([string]$Name, [string]$TianDir)
    if (-not $Name) { Write-Fail "Usage: tian-cli schedule remove <name>"; return }

    $schedules = Read-Schedules
    $entry = $schedules | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $entry) { Write-Fail "No schedule named '$Name'."; return }

    $result = Start-Process schtasks -ArgumentList "/Delete", "/F", "/TN", $entry.taskName -Wait -PassThru -NoNewWindow
    if ($result.ExitCode -ne 0) {
        Write-Warn "Could not remove Windows task (may have already been deleted)."
    }

    $keep = @($schedules | Where-Object { $_.name -ne $Name })
    Save-Schedules $keep
    Write-Ok "Schedule '$Name' removed."
}

function Show-Schedules {
    $schedules = Read-Schedules
    if (-not $schedules -or $schedules.Count -eq 0) {
        Write-Info "No schedules found. Create one with: tian-cli schedule add --name <n> --task `"prompt`" --time 08:00"
        return
    }

    Write-Header "Scheduled Tasks"
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
