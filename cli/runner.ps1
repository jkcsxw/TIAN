# Task runner — executes a prompt against the configured backend
# Stores results in ~/.tian/tasks/

$_tianHome       = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$global:TIAN_TASKS_DIR  = Join-Path $_tianHome ".tian" "tasks"
$global:TIAN_JOBS_FILE  = Join-Path $_tianHome ".tian" "jobs.json"

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

function Invoke-Task {
    param(
        [string]$Prompt,
        [string]$TianDir,
        [switch]$Background,
        [string]$JobName = ""
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

    $meta = @{
        id        = $jobId
        name      = if ($JobName) { $JobName } else { $jobId }
        prompt    = $Prompt
        backend   = $backend.id
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

    $cmdLine = "$($backend.cliCommand) $($backend.nonInteractiveFlag) `"$($Prompt -replace '"','\"')`""

    if ($Background) {
        # Launch detached process; output redirected to file
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName  = "powershell"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$cmdLine | Out-File -FilePath '$outputFile' -Encoding UTF8`""
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)

        # Update status to running with PID
        $meta.pid = $proc.Id
        $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8

        Write-Ok "任务已在后台启动。/ Task started in background."
        Write-Info "任务ID / Job ID : $jobId"
        Write-Info "查看结果 / Check result with:  tian-cli jobs result $jobId"
        return $jobId
    } else {
        # Foreground — stream output directly, also save to file
        Write-Info "正在使用 $($backend.displayName) 执行任务... / Running task with $($backend.displayName)..."
        Write-Rule
        $output = Invoke-Expression $cmdLine 2>&1
        $output | Out-File -FilePath $outputFile -Encoding UTF8
        $output | ForEach-Object { Write-Host $_ }
        Write-Rule

        # Mark complete
        $meta.status    = "done"
        $meta.finishedAt = [System.DateTime]::Now.ToString("o")
        $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8

        $jobs = Read-Jobs
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
                            $meta.status = "done"
                            $finishedAt  = [System.DateTime]::Now.ToString("o")
                            if (-not ($meta.PSObject.Properties['finishedAt'])) {
                                $meta | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
                            } else { $meta.finishedAt = $finishedAt }
                            $meta | ConvertTo-Json | Set-Content $metaFile -Encoding UTF8
                            $job.status = "done"
                            if (-not ($job.PSObject.Properties['finishedAt'])) {
                                $job | Add-Member -NotePropertyName 'finishedAt' -NotePropertyValue $finishedAt
                            } else { $job.finishedAt = $finishedAt }
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

function Show-Jobs {
    param([int]$Last = 20)
    $jobs = Sync-JobStatuses | Select-Object -Last $Last
    if (-not $jobs -or $jobs.Count -eq 0) {
        Write-Info "暂无任务记录。运行任务：tian-cli run \"您的任务提示词\" / No jobs found. Run a task with: tian-cli run \"your task\""
        return
    }
    Write-Header "后台任务（最近 $Last 条）/ Background Jobs (last $Last)"
    Write-Rule
    $statusColor = @{ running="Yellow"; done="Green"; error="Red"; scheduled="Cyan" }
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
