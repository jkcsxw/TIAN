BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/Catalog.ps1"

    # Point runner storage to a temp dir
    $script:TempRunnerDir = New-TestTempDir
    $script:OrigTasksDir  = $null  # overridden below

    # Dot-source runner but override storage paths
    $TIAN_TASKS_DIR = Join-Path $script:TempRunnerDir "tasks"
    $TIAN_JOBS_FILE = Join-Path $script:TempRunnerDir "jobs.json"

    . "$(Get-TianRoot)/cli/runner.ps1"

    # Redirect module-level vars to temp
    Set-Variable -Name TIAN_TASKS_DIR -Value $TIAN_TASKS_DIR -Scope Global
    Set-Variable -Name TIAN_JOBS_FILE -Value $TIAN_JOBS_FILE -Scope Global
}
AfterAll { Remove-Item $script:TempRunnerDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe "New-JobId" {
    It "matches expected format yyyyMMdd-HHmmss-xxxxxx" {
        $id = New-JobId
        $id | Should -Match '^\d{8}-\d{6}-[a-z0-9]{6}$'
    }
    It "two rapid calls produce different IDs" {
        $id1 = New-JobId
        Start-Sleep -Milliseconds 10
        $id2 = New-JobId
        $id1 | Should -Not -Be $id2
    }
}

Describe "Read-Jobs / Save-Jobs round-trip" {
    BeforeEach {
        Remove-Item $TIAN_JOBS_FILE -ErrorAction SilentlyContinue
        $TIAN_TASKS_DIR | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force } }
    }

    It "returns empty array when file does not exist" {
        $result = Read-Jobs
        $result | Should -BeOfType [array]
        $result.Count | Should -Be 0
    }
    It "returns empty array for empty file" {
        Ensure-TaskDirs
        "" | Set-Content $TIAN_JOBS_FILE
        $result = Read-Jobs
        $result.Count | Should -Be 0
    }
    It "normalises single-item array from ConvertFrom-Json" {
        Ensure-TaskDirs
        '[{"id":"abc","status":"done"}]' | Set-Content $TIAN_JOBS_FILE -Encoding UTF8
        $result = Read-Jobs
        $result | Should -BeOfType [array]
        $result.Count | Should -Be 1
        $result[0].id | Should -Be "abc"
    }
    It "round-trips multi-item array without data loss" {
        Ensure-TaskDirs
        $jobs = @(
            [PSCustomObject]@{ id = "job1"; status = "done";    prompt = "first" },
            [PSCustomObject]@{ id = "job2"; status = "running"; prompt = "second" }
        )
        Save-Jobs $jobs
        $result = Read-Jobs
        $result.Count | Should -Be 2
        $result[0].id | Should -Be "job1"
        $result[1].id | Should -Be "job2"
    }
}

Describe "Get-JobStatus" {
    BeforeEach { Ensure-TaskDirs }

    It "returns null for unknown job ID" {
        Get-JobStatus -JobId "nonexistent-id" | Should -BeNullOrEmpty
    }
    It "returns correct metadata when meta file exists" {
        $id   = New-JobId
        $meta = @{ id = $id; status = "done"; prompt = "test prompt"; backend = "claude-code" }
        $meta | ConvertTo-Json | Set-Content (Join-Path $TIAN_TASKS_DIR "$id.meta.json") -Encoding UTF8
        $result = Get-JobStatus -JobId $id
        $result.id     | Should -Be $id
        $result.status | Should -Be "done"
        $result.prompt | Should -Be "test prompt"
    }
}

Describe "Sync-JobStatuses" {
    BeforeEach {
        Remove-Item $TIAN_JOBS_FILE -ErrorAction SilentlyContinue
        Ensure-TaskDirs
    }

    It "marks running job as done when PID is no longer alive" {
        $id  = New-JobId
        $fakeDeadPid = 999999
        $meta = @{ id = $id; status = "running"; pid = $fakeDeadPid; prompt = "p"; createdAt = [DateTime]::Now.ToString("o") }
        $meta | ConvertTo-Json | Set-Content (Join-Path $TIAN_TASKS_DIR "$id.meta.json") -Encoding UTF8
        "" | Set-Content (Join-Path $TIAN_TASKS_DIR "$id.txt")
        Save-Jobs @([PSCustomObject]$meta)

        Mock Get-Process { $null } -ParameterFilter { $Id -eq $fakeDeadPid }
        $result = Sync-JobStatuses
        ($result | Where-Object { $_.id -eq $id }).status | Should -Be "done"
    }
    It "does not mutate already-done jobs" {
        $id  = New-JobId
        $meta = @{ id = $id; status = "done"; prompt = "p"; createdAt = [DateTime]::Now.ToString("o") }
        Save-Jobs @([PSCustomObject]$meta)
        $result = Sync-JobStatuses
        ($result | Where-Object { $_.id -eq $id }).status | Should -Be "done"
    }
}

Describe "Clear-Jobs" {
    BeforeEach {
        Remove-Item $TIAN_JOBS_FILE -ErrorAction SilentlyContinue
        if (Test-Path $TIAN_TASKS_DIR) { Remove-Item $TIAN_TASKS_DIR -Recurse -Force }
        Ensure-TaskDirs
    }

    It "removes completed jobs and their files, keeps running jobs" {
        $doneId    = New-JobId
        $runningId = New-JobId
        "" | Set-Content (Join-Path $TIAN_TASKS_DIR "$doneId.txt")
        "" | Set-Content (Join-Path $TIAN_TASKS_DIR "$runningId.txt")
        Save-Jobs @(
            [PSCustomObject]@{ id = $doneId;    status = "done";    prompt = "d" },
            [PSCustomObject]@{ id = $runningId; status = "running"; prompt = "r" }
        )

        Clear-Jobs
        $remaining = Read-Jobs
        $remaining.Count | Should -Be 1
        $remaining[0].id | Should -Be $runningId
        Test-Path (Join-Path $TIAN_TASKS_DIR "$doneId.txt") | Should -BeFalse
    }
    It "-All removes all jobs including running ones" {
        $id = New-JobId
        "" | Set-Content (Join-Path $TIAN_TASKS_DIR "$id.txt")
        Save-Jobs @([PSCustomObject]@{ id = $id; status = "running"; prompt = "r" })
        Clear-Jobs -All
        $remaining = Read-Jobs
        $remaining.Count | Should -Be 0
    }
}
