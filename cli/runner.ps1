# Task runner — executes a prompt against the configured backend
# Stores results in ~/.tian/tasks/

$_tianHome       = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$global:TIAN_TASKS_DIR  = Join-Path $_tianHome ".tian" "tasks"
$global:TIAN_JOBS_FILE  = Join-Path $_tianHome ".tian" "jobs.json"

function Get-RunnerShellCommand {
    if ($PSVersionTable.PSEdition -eq "Core") {
        $proc = Get-Process -Id $PID -ErrorAction SilentlyContinue
        if ($proc -and $proc.Path) { return $proc.Path }
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh) { return $pwsh.Source }
    }
    return "powershell"
}

function Start-RunnerBackgroundProcess {
    param(
        [string]$ShellCommand,
        [string]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $ShellCommand
    $psi.Arguments = $Arguments
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Invoke-BackendCommand {
    param(
        [string]$BackendCommand,
        [string]$BackendFlag,
        [string]$Prompt
    )

    $argsList = @()
    if ($BackendFlag) { $argsList += $BackendFlag }
    $argsList += $Prompt

    $output = & $BackendCommand @argsList 2>&1
    $exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
    return [PSCustomObject]@{
        Output   = $output
        ExitCode = $exitCode
    }
}

function Ensure-TaskDirs {
    if (-not (Test-Path $global:TIAN_TASKS_DIR)) { New-Item -ItemType Directory -Path $global:TIAN_TASKS_DIR -Force | Out-Null }
    if (-not (Test-Path $global:TIAN_JOBS_FILE))  { '[]' | Set-Content $global:TIAN_JOBS_FILE -Encoding UTF8 }
}

function Get-ActiveBackend {
    param([string]$TianDir)
    $catalog = Get-Catalog -TianDir $TianDir
    # Find the first backend whose CLI is available on PATH
    foreach ($b in $catalog.backends) {
        if ($b.cliCommand -and (Get-Command $b.cliCommand -ErrorAction SilentlyContinue)) {
            return $b
        }
    }
    return $null
}

function Get-AllAvailableBackends {
    param([string]$TianDir)
    $catalog = Get-Catalog -TianDir $TianDir
    $available = @()
    foreach ($b in $catalog.backends) {
        if ($b.cliCommand -and $b.nonInteractiveFlag -and (Get-Command $b.cliCommand -ErrorAction SilentlyContinue)) {
            $available += $b
        }
    }
    return $available
}

function New-JobId {
    return [System.DateTime]::Now.ToString("yyyyMMdd-HHmmss") + "-" + ([System.Guid]::NewGuid().ToString("N").Substring(0,6))
}

function Read-Jobs {
    Ensure-TaskDirs
    $raw = Get-Content $global:TIAN_JOBS_FILE -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '' -or $raw.Trim() -eq '[]') { return [array]@() }
    $parsed = $raw | ConvertFrom-Json
    # ConvertFrom-Json returns a single object when array has one item — normalise
    if ($null -eq $parsed)      { return [array]@() }
    if ($parsed -isnot [array]) { return [array]@($parsed) }
    return [array]$parsed
}

function Save-Jobs {
    param([array]$Jobs)
    Ensure-TaskDirs
    if ($null -eq $Jobs -or $Jobs.Count -eq 0) {
        '[]' | Set-Content $global:TIAN_JOBS_FILE -Encoding UTF8
    } else {
        ConvertTo-Json $Jobs -Depth 5 | Set-Content $global:TIAN_JOBS_FILE -Encoding UTF8
    }
}

function Test-QuotaExhaustedText {
    param([string]$Text)
    if (-not $Text) { return $false }
    return $Text -match '(?is)(insufficient_quota|quota(?:\s+is)?\s+exhausted|quota_exhausted|rate.limit|rate limit|429|too many requests|overloaded)'
}

function Resolve-ScheduleNameByPrompt {
    param([string]$Prompt)

    $schedulesFile = if (Get-Variable -Name TIAN_SCHEDULES_FILE -Scope Global -ErrorAction SilentlyContinue) {
        $global:TIAN_SCHEDULES_FILE
    } else {
        Join-Path $_tianHome ".tian" "schedules.json"
    }
    if (-not (Test-Path $schedulesFile)) { return $null }

    $raw = Get-Content $schedulesFile -Raw -ErrorAction SilentlyContinue
    if (-not $raw -or $raw.Trim() -eq '' -or $raw.Trim() -eq '[]') { return $null }

    $parsed = $raw | ConvertFrom-Json
    $schedules = if ($parsed -is [array]) { [array]$parsed } elseif ($parsed) { [array]@($parsed) } else { [array]@() }
    $matches = @($schedules | Where-Object { $_.prompt -eq $Prompt })
    if ($matches.Count -eq 1) { return $matches[0].name }
    return $null
}

# Stream a background job's output to the terminal until the job finishes.
# Pressing Ctrl+C exits the watch but the background job keeps running.
function Watch-Job {
    param([string]$JobId)

    $outFile  = Join-Path $global:TIAN_TASKS_DIR "$JobId.txt"
    $metaFile = Join-Path $global:TIAN_TASKS_DIR "$JobId.meta.json"

    # Wait up to 5 s for the background process to create the output file.
    $waited = 0
    while (-not (Test-Path $outFile) -and $waited -lt 20) {
        Start-Sleep -Milliseconds 250
        $waited++
    }
    if (-not (Test-Path $outFile)) {
        Write-Warn "Output file did not appear — job may have failed to start."
        return
    }

    Write-Info "Streaming output (Ctrl+C stops watching; the job continues in background)..."
    Write-Rule

    $position = 0
    $jobDone  = $false

    try {
        while (-not $jobDone) {
            # Read any new bytes written since last iteration.
            if (Test-Path $outFile) {
                $fs = [System.IO.File]::Open(
                    $outFile,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                try {
                    [void]$fs.Seek($position, [System.IO.SeekOrigin]::Begin)
                    while (-not $sr.EndOfStream) { Write-Host ($sr.ReadLine()) }
                    $position = $fs.Position
                } finally {
                    $sr.Dispose()
                    $fs.Dispose()
                }
            }

            # Check whether the job has finished.
            $currentStatus = "running"
            if (Test-Path $metaFile) {
                try {
                    $currentStatus = (Get-Content $metaFile -Raw | ConvertFrom-Json).status
                } catch {}
            }

            if ($currentStatus -ne "running") {
                $jobDone = $true
                # Final flush after a brief pause so the process can finish writing.
                Start-Sleep -Milliseconds 500
                if (Test-Path $outFile) {
                    $fs = [System.IO.File]::Open(
                        $outFile,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite)
                    $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
                    try {
                        [void]$fs.Seek($position, [System.IO.SeekOrigin]::Begin)
                        while (-not $sr.EndOfStream) { Write-Host ($sr.ReadLine()) }
                    } finally { $sr.Dispose(); $fs.Dispose() }
                }
            } else {
                Start-Sleep -Milliseconds 500
            }
        }
    } catch {
        # Ctrl+C or pipeline stop — the background job continues running.
        Write-Host ""
        Write-Rule
        Write-Info "Stopped watching — job $JobId is still running in the background."
        Write-Info "Resume watching with:  tian-cli jobs tail $JobId"
        Write-Info "Read final output with: tian-cli jobs result $JobId"
        return
    }

    Write-Host ""
    Write-Rule

    $finalMeta   = if (Test-Path $metaFile) { try { Get-Content $metaFile -Raw | ConvertFrom-Json } catch { $null } } else { $null }
    $finalStatus = if ($finalMeta) { $finalMeta.status } else { "unknown" }
    switch ($finalStatus) {
        "done"    { Write-Ok "Job $JobId finished successfully." }
        "error"   { Write-Warn "Job $JobId finished with errors. See output above." }
        "stopped" {
            if ($finalMeta -and $finalMeta.stopReason -eq "quota_exhausted") {
                Write-Warn "Job $JobId stopped — quota or rate limit exhausted."
            } else {
                Write-Warn "Job $JobId was stopped."
            }
        }
        default   { Write-Info "Job $JobId status: $finalStatus" }
    }
}

function Invoke-Task {
    param(
        [string]$Prompt,
        [string]$TianDir,
        [switch]$Background,
        [switch]$Watch,
        [string]$JobName = "",
        [string]$ScheduleName = ""
    )

    Ensure-TaskDirs
    $backend = Get-ActiveBackend -TianDir $TianDir
    if (-not $backend) {
        Write-Fail "未在系统中找到AI后端，请先运行 'tian-cli setup'。/ No AI backend found on PATH. Run 'tian-cli setup' first."
        return $null
    }
    if (-not $backend.nonInteractiveFlag) {
        Write-Fail "$($backend.displayName) 不支持非交互式任务执行。/ does not support non-interactive task execution."
        return $null
    }

    $jobId      = New-JobId
    $outputFile = Join-Path $global:TIAN_TASKS_DIR "$jobId.txt"
    $metaFile   = Join-Path $global:TIAN_TASKS_DIR "$jobId.meta.json"
    if (-not $ScheduleName) { $ScheduleName = Resolve-ScheduleNameByPrompt -Prompt $Prompt }
    if (-not $JobName -and $ScheduleName) { $JobName = $ScheduleName }

    $meta = @{
        id        = $jobId
        name      = if ($JobName) { $JobName } else { $jobId }
        prompt    = $Prompt
        backend   = $backend.id
        scheduleName = $ScheduleName
        status    = "running"
        createdAt = [System.DateTime]::Now.ToString("o")
        finishedAt = $null
        outputFile = $outputFile
    }
    $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8

    # Append to jobs registry
    $jobs = Read-Jobs
    $jobs += [PSCustomObject]$meta
    Save-Jobs $jobs

    if ($Background) {
        # Launch detached process; capture output so quota exhaustion can disable schedules automatically.
        $workerFile = Join-Path $global:TIAN_TASKS_DIR "$jobId.worker.ps1"
        $workerScript = @'
param(
    [string]$BackendCommand,
    [string]$BackendFlag,
    [string]$Prompt,
    [string]$OutputFile,
    [string]$JobsFile,
    [string]$MetaFile,
    [string]$JobId,
    [string]$ScheduleName,
    [string]$TianDir,
    [string]$CliScript,
    [string]$ShellCommand
)

function Test-QuotaExhaustedText {
    param([string]$Text)
    if (-not $Text) { return $false }
    return $Text -match '(?is)(insufficient_quota|quota(?:\s+is)?\s+exhausted|quota_exhausted|rate.limit|rate limit|429|too many requests|overloaded)'
}

$argsList = @()
if ($BackendFlag) { $argsList += $BackendFlag }
$argsList += $Prompt
$output = & $BackendCommand @argsList 2>&1
$exitCode = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
$output | Out-File -FilePath $OutputFile -Encoding UTF8
$outputText = if ($output) { ($output | Out-String) } else { "" }
$quotaExhausted = Test-QuotaExhaustedText -Text $outputText
$finishedAt = [System.DateTime]::Now.ToString("o")
$status = if ($quotaExhausted) { "stopped" } elseif ($exitCode -eq 0) { "done" } else { "error" }
$stopReason = if ($quotaExhausted) { "quota_exhausted" } else { $null }

if (Test-Path $MetaFile) {
    $meta = Get-Content $MetaFile -Raw | ConvertFrom-Json
    $meta.status = $status
    $meta.finishedAt = $finishedAt
    if ($stopReason) {
        if (-not ($meta.PSObject.Properties['stopReason'])) {
            $meta | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue $stopReason
        } else { $meta.stopReason = $stopReason }
    }
    ($meta | ConvertTo-Json -Depth 5) | Set-Content $MetaFile -Encoding UTF8
}

if (Test-Path $JobsFile) {
    $jobs = Get-Content $JobsFile -Raw | ConvertFrom-Json
    if ($jobs -and $jobs -isnot [array]) { $jobs = @($jobs) }
    foreach ($job in @($jobs)) {
        if ($job.id -ne $JobId) { continue }
        $job.status = $status
        if (-not ($job.PSObject.Properties['finishedAt'])) {
            $job | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
        } else { $job.finishedAt = $finishedAt }
        if ($stopReason) {
            if (-not ($job.PSObject.Properties['stopReason'])) {
                $job | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue $stopReason
            } else { $job.stopReason = $stopReason }
        }
    }
    ($jobs | ConvertTo-Json -Depth 5) | Set-Content $JobsFile -Encoding UTF8
}

if ($quotaExhausted -and $ScheduleName -and (Test-Path $CliScript)) {
    & $ShellCommand -NoProfile -ExecutionPolicy Bypass -File $CliScript -TianDir $TianDir schedule remove --name $ScheduleName *> $null
}

# Desktop notification on job completion
$notifMsg = if ($quotaExhausted) { "Job $JobId stopped — quota exhausted" } elseif ($exitCode -ne 0) { "Job $JobId failed" } else { "Job $JobId finished" }
try {
    if ($env:OS -eq 'Windows_NT' -or $IsWindows) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.BalloonTipTitle = "TIAN"
        $notify.BalloonTipText = $notifMsg
        $notify.Visible = $true
        $notify.ShowBalloonTip(6000)
        Start-Sleep -Milliseconds 300
        $notify.Dispose()
    } elseif ($IsMacOS) {
        & osascript -e "display notification `"$notifMsg`" with title `"TIAN`"" 2>$null
    }
} catch {}

Remove-Item $PSCommandPath -ErrorAction SilentlyContinue
'@
        Set-Content -Path $workerFile -Value $workerScript -Encoding UTF8

        $shellCommand = Get-RunnerShellCommand
        $cliScript = Join-Path $TianDir "cli" "tian.ps1"
        $quotedArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$workerFile`"",
            "-BackendCommand", "`"$($backend.cliCommand)`"",
            "-BackendFlag", "`"$($backend.nonInteractiveFlag)`"",
            "-Prompt", "`"$($Prompt -replace '"','\"')`"",
            "-OutputFile", "`"$outputFile`"",
            "-JobsFile", "`"$global:TIAN_JOBS_FILE`"",
            "-MetaFile", "`"$metaFile`"",
            "-JobId", "`"$jobId`"",
            "-ScheduleName", "`"$ScheduleName`"",
            "-TianDir", "`"$TianDir`"",
            "-CliScript", "`"$cliScript`"",
            "-ShellCommand", "`"$shellCommand`""
        )
        $proc = Start-RunnerBackgroundProcess -ShellCommand $shellCommand -Arguments ($quotedArgs -join " ")

        # Persist the PID in both metadata stores so stop/status commands read the same state.
        $meta.pid = $proc.Id
        $meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
        $jobs = @([array](Read-Jobs))
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            if ($jobs[$i].id -eq $jobId) {
                $jobs[$i] = [PSCustomObject]$meta
                break
            }
        }
        Save-Jobs $jobs

        Write-Ok "任务已在后台启动。/ Task started in background."
        Write-Info "任务ID / Job ID : $jobId"
        Write-Info "查看结果 / Check result with:  tian-cli jobs result $jobId"

        if ($Watch) {
            Write-Host ""
            Watch-Job -JobId $jobId
        }

        return $jobId
    } else {
        # Foreground — try each installed backend in catalog order, falling back on quota/rate-limit
        $allBackends = @(Get-AllAvailableBackends -TianDir $TianDir)
        if ($allBackends.Count -eq 0) { $allBackends = @($backend) }

        $primaryCmd  = $backend.cliCommand
        $result      = $null
        $outputText  = ""
        $usedBackend = $backend

        foreach ($b in $allBackends) {
            if ($b.cliCommand -ne $primaryCmd) {
                Write-Warn "Falling back to $($b.displayName) (quota/rate-limit on previous backend)..."
            }
            Write-Info "正在使用 $($b.displayName) 执行任务... / Running task with $($b.displayName)..."
            Write-Rule
            $result = Invoke-BackendCommand -BackendCommand $b.cliCommand -BackendFlag $b.nonInteractiveFlag -Prompt $Prompt
            $result.Output | ForEach-Object { Write-Host $_ }
            Write-Rule
            $result.Output | Out-File -FilePath $outputFile -Encoding UTF8
            $outputText  = if ($result.Output) { ($result.Output | Out-String) } else { "" }
            $usedBackend = $b
            if (-not (Test-QuotaExhaustedText -Text $outputText)) { break }
            Write-Warn "$($b.displayName): quota or rate limit — trying next backend..."
        }

        # Mark complete
        $status = if (Test-QuotaExhaustedText -Text $outputText) {
            "stopped"
        } elseif ($result -and $result.ExitCode -eq 0) {
            "done"
        } else {
            "error"
        }
        $meta.status     = $status
        $meta.backend    = $usedBackend.id
        $meta.finishedAt = [System.DateTime]::Now.ToString("o")
        if ($status -eq "stopped") { $meta.stopReason = "quota_exhausted" }
        $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8

        $jobs = @([array](Read-Jobs))
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            if ($jobs[$i].id -eq $jobId) {
                $jobs[$i] = [PSCustomObject]$meta
                break
            }
        }
        Save-Jobs $jobs
        return $jobId
    }
}

function Get-JobStatus {
    param([string]$JobId)
    $metaFile = Join-Path $global:TIAN_TASKS_DIR "$JobId.meta.json"
    if (-not (Test-Path $metaFile)) { return $null }
    return Get-Content $metaFile -Raw | ConvertFrom-Json
}

function Sync-JobStatuses {
    # Check if background jobs have finished by looking at their output files
    $jobs = Read-Jobs
    $changed = $false
    foreach ($job in $jobs) {
        if ($job.status -eq "running") {
            $outputFile = Join-Path $global:TIAN_TASKS_DIR "$($job.id).txt"
            if (Test-Path $outputFile) {
                $metaFile = Join-Path $global:TIAN_TASKS_DIR "$($job.id).meta.json"
                if (Test-Path $metaFile) {
                    $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
                    if ($meta.status -eq "running") {
                        # Check if process is still alive
                        $alive = $false
                        if ($meta.pid) {
                            $alive = Get-Process -Id $meta.pid -ErrorAction SilentlyContinue
                        }
                        if (-not $alive) {
                            $quotaExhausted = $false
                            if (Test-Path $outputFile) {
                                $quotaExhausted = Test-QuotaExhaustedText -Text (Get-Content $outputFile -Raw -ErrorAction SilentlyContinue)
                            }
                            $meta.status = if ($quotaExhausted) { "stopped" } else { "done" }
                            $finishedAt  = [System.DateTime]::Now.ToString("o")
                            if (-not ($meta.PSObject.Properties['finishedAt'])) {
                                $meta | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
                            } else { $meta.finishedAt = $finishedAt }
                            if ($quotaExhausted) {
                                if (-not ($meta.PSObject.Properties['stopReason'])) {
                                    $meta | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue 'quota_exhausted'
                                } else { $meta.stopReason = 'quota_exhausted' }
                            }
                            $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8
                            $job.status = $meta.status
                            if (-not ($job.PSObject.Properties['finishedAt'])) {
                                $job | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
                            } else { $job.finishedAt = $finishedAt }
                            if ($quotaExhausted) {
                                if (-not ($job.PSObject.Properties['stopReason'])) {
                                    $job | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue 'quota_exhausted'
                                } else { $job.stopReason = 'quota_exhausted' }
                                if ($meta.scheduleName -and (Get-Command Remove-Schedule -ErrorAction SilentlyContinue)) {
                                    Remove-Schedule -Name $meta.scheduleName -TianDir ""
                                }
                            }
                            $changed = $true
                        }
                    }
                }
            }
        }
    }
    if ($changed) { Save-Jobs $jobs }
    return $jobs
}

function Stop-Jobs {
    param(
        [string]$JobId,
        [switch]$All,
        [string]$Reason = "stopped_by_user"
    )

    $jobs = Sync-JobStatuses
    $targets = @($jobs | Where-Object {
        $_.status -eq "running" -and ($All -or ($JobId -and $_.id -eq $JobId))
    })

    if (-not $targets -or $targets.Count -eq 0) {
        Write-Info "没有匹配的运行中任务。/ No matching running jobs found."
        return
    }

    $finishedAt = [System.DateTime]::Now.ToString("o")
    foreach ($job in $targets) {
        $meta = Get-JobStatus -JobId $job.id
        if ($meta -and $meta.pid) {
            Stop-Process -Id $meta.pid -Force -ErrorAction SilentlyContinue
        }

        $job.status = "stopped"
        if (-not ($job.PSObject.Properties['finishedAt'])) {
            $job | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
        } else { $job.finishedAt = $finishedAt }
        if (-not ($job.PSObject.Properties['stopReason'])) {
            $job | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue $Reason
        } else { $job.stopReason = $Reason }

        if ($meta) {
            $meta.status = "stopped"
            if (-not ($meta.PSObject.Properties['finishedAt'])) {
                $meta | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
            } else { $meta.finishedAt = $finishedAt }
            if (-not ($meta.PSObject.Properties['stopReason'])) {
                $meta | Add-Member -NotePropertyName 'stopReason' -NotePropertyValue $Reason
            } else { $meta.stopReason = $Reason }
            ($meta | ConvertTo-Json -Depth 5) | Set-Content (Join-Path $global:TIAN_TASKS_DIR "$($job.id).meta.json") -Encoding UTF8
        }

        Write-Ok "已停止任务 $($job.id)。/ Stopped job $($job.id)."
    }

    Save-Jobs $jobs
}

function Show-Jobs {
    param([int]$Last = 20)
    $jobs = Sync-JobStatuses | Select-Object -Last $Last
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Info "暂无任务记录。运行任务：tian-cli run \"您的任务提示词\" / No jobs found. Run a task with: tian-cli run \"your task\""
        return
    }
    Write-Header "后台任务（最近 $Last 条）/ Background Jobs (last $Last)"
    Write-Rule
    $statusColor = @{ running="Yellow"; done="Green"; stopped="DarkYellow"; error="Red"; scheduled="Cyan" }
    foreach ($job in ($jobs | Sort-Object createdAt -Descending)) {
        $col  = $statusColor[$job.status]
        $time = if ($job.createdAt) { ([System.DateTime]::Parse($job.createdAt)).ToString("yyyy-MM-dd HH:mm") } else { "?" }
        Write-Color "  $($job.id.PadRight(28))" Gray -NoNewline
        Write-Color " [$($job.status.ToUpper().PadRight(9))]" $col -NoNewline
        Write-Color "  $time  " Gray -NoNewline
        Write-Color ($job.name) White
        $preview = ($job.prompt -replace "`n"," ").Substring(0, [Math]::Min(60, $job.prompt.Length))
        Write-Color "  $(" " * 28)  $preview..." DarkGray
    }
    Write-Rule
    Write-Color "  tian-cli jobs result <任务ID>   查看输出 / to read output" DarkGray
    $hasQuota = $jobs | Where-Object { $_.stopReason -eq "quota_exhausted" }
    if ($hasQuota) {
        Write-Color "  tian-cli jobs retry <任务ID>    重新执行已停止任务 / re-run a quota-stopped job" DarkYellow
    }
    Write-Host ""
}

function Show-JobResult {
    param([string]$JobId)
    if (-not $JobId) { Write-Fail "Usage: tian-cli jobs result <job-id>"; return }
    $meta = Get-JobStatus $JobId
    if (-not $meta) { Write-Fail "Job '$JobId' not found."; return }

    Write-Header "任务 / Job: $($meta.name)"
    Write-Info "状态 / Status  : $($meta.status)"
    Write-Info "后端 / Backend : $($meta.backend)"
    Write-Info "创建时间 / Created : $($meta.createdAt)"
    if ($meta.finishedAt) { Write-Info "完成时间 / Finished: $($meta.finishedAt)" }
    if ($meta.stopReason) {
        Write-Info "停止原因 / Stop reason: $($meta.stopReason)"
        if ($meta.stopReason -eq "quota_exhausted") {
            Write-Warn "  [!!] This job stopped because the API quota or rate limit was exhausted."
            Write-Color "       Wait for your quota to reset, upgrade your plan, or install a fallback backend (e.g. Ollama)." DarkGray
            Write-Color "       Once ready, retry this job with: tian-cli jobs retry $JobId" DarkGray
        }
    }
    Write-Info "提示词 / Prompt  : $($meta.prompt)"
    Write-Rule

    $outputFile = Join-Path $global:TIAN_TASKS_DIR "$JobId.txt"
    if (Test-Path $outputFile) {
        Get-Content $outputFile | ForEach-Object { Write-Host $_ }
    } elseif ($meta.status -eq "running") {
        Write-Warn "任务仍在执行中，请稍后再查看。/ Task is still running. Check again in a moment."
    } else {
        Write-Warn "输出文件未找到。/ Output file not found."
    }
    Write-Rule
}

function Retry-Job {
    param([string]$JobId, [string]$TianDir)
    if (-not $JobId) { Write-Fail "Usage: tian-cli jobs retry <job-id>"; return }
    $jobs = Read-Jobs
    $job = $jobs | Where-Object { $_.id -eq $JobId } | Select-Object -First 1
    if (-not $job) { Write-Fail "Job '$JobId' not found."; return }
    $origPrompt = $job.prompt
    if (-not $origPrompt) { Write-Fail "Job '$JobId' has no recorded prompt."; return }
    Write-Info "重新执行任务 / Retrying prompt from job $JobId..."
    Invoke-Task -Prompt $origPrompt -TianDir $TianDir -Background:$true `
        -JobName ($job.name) -ScheduleName ($job.scheduleName)
}

function Clear-Jobs {
    param([switch]$All)
    $jobs = Read-Jobs
    if ($All) {
        foreach ($job in $jobs) {
            $base = Join-Path $global:TIAN_TASKS_DIR $job.id
            Remove-Item "$base.txt"  -ErrorAction SilentlyContinue
            Remove-Item "$base.meta.json" -ErrorAction SilentlyContinue
        }
        Save-Jobs @()
        Write-Ok "所有任务已清除。/ All jobs cleared."
    } else {
        $keep = @($jobs | Where-Object { $_.status -eq "running" })
        $remove = @($jobs | Where-Object { $_.status -ne "running" })
        foreach ($job in $remove) {
            $base = Join-Path $global:TIAN_TASKS_DIR $job.id
            Remove-Item "$base.txt"  -ErrorAction SilentlyContinue
            Remove-Item "$base.meta.json" -ErrorAction SilentlyContinue
        }
        Save-Jobs $keep
        Write-Ok "已清除 $($remove.Count) 条已完成任务，保留 $($keep.Count) 条运行中任务。/ Cleared $($remove.Count) completed job(s). $($keep.Count) running job(s) kept."
    }
}
