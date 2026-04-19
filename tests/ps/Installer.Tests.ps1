BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"

    # Dot-source build-installer.ps1 — the InvocationName guard prevents Invoke-Build from running
    . "$(Get-TianRoot)/installer/build-installer.ps1"

    $script:IssFile      = "$(Get-TianRoot)/installer/tian-setup.iss"
    $script:IssContent   = Get-Content $script:IssFile -Raw
    $script:GetInstaller = "$(Get-TianRoot)/get-installer.bat"
    $script:InstallerDir = "$(Get-TianRoot)/installer"
    $script:TianRoot     = Get-TianRoot
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "Find-Iscc" {

    It "returns null when iscc is not on PATH and no default paths exist" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'iscc' }
        Mock Test-Path   { $false }
        Find-Iscc | Should -BeNullOrEmpty
    }

    It "returns the Source path when iscc is found on PATH" {
        Mock Get-Command {
            [PSCustomObject]@{ Source = 'C:\tools\iscc.exe' }
        } -ParameterFilter { $Name -eq 'iscc' }
        Find-Iscc | Should -Be 'C:\tools\iscc.exe'
    }

    It "returns first matching default candidate when not on PATH" {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'iscc' }
        Mock Test-Path {
            param($Path)
            $Path -like '*Inno Setup 6\iscc.exe'
        }
        $result = Find-Iscc
        $result | Should -BeLike '*Inno Setup 6\iscc.exe'
    }

    It "prefers PATH over default candidate" {
        Mock Get-Command {
            [PSCustomObject]@{ Source = 'C:\custom\iscc.exe' }
        } -ParameterFilter { $Name -eq 'iscc' }
        Mock Test-Path { $true }
        Find-Iscc | Should -Be 'C:\custom\iscc.exe'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "Get-IssVersion" {

    It "extracts version from real tian-setup.iss" {
        $ver = Get-IssVersion $script:IssFile
        $ver | Should -Match '^\d+\.\d+\.\d+$'
    }

    It "returns 1.0.0 fallback when file is missing" {
        Get-IssVersion "nonexistent.iss" | Should -Be "1.0.0"
    }

    It "extracts version from inline content" {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "test_$([guid]::NewGuid().ToString('N')).iss"
        '#define AppVersion "2.3.4"' | Set-Content $tmp -Encoding UTF8
        try   { Get-IssVersion $tmp | Should -Be "2.3.4" }
        finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "tian-setup.iss — required fields" {

    It "defines AppName" {
        $script:IssContent | Should -Match '#define AppName\s+"[^"]+"'
    }
    It "defines AppVersion as semver" {
        $script:IssContent | Should -Match '#define AppVersion\s+"\d+\.\d+\.\d+"'
    }
    It "defines AppGUID" {
        $script:IssContent | Should -Match '#define AppGUID\s+"'
    }
    It "AppGUID contains a GUID-shaped value" {
        $script:IssContent | Should -Match '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
    }
    It "sets MinVersion to Windows 10" {
        $script:IssContent | Should -Match 'MinVersion\s*=\s*10\.0'
    }
    It "requires admin privileges" {
        $script:IssContent | Should -Match 'PrivilegesRequired\s*=\s*admin'
    }
    It "uses lzma compression" {
        $script:IssContent | Should -Match 'Compression\s*=\s*lzma'
    }
    It "has OutputBaseFilename defined" {
        $script:IssContent | Should -Match 'OutputBaseFilename\s*='
    }
    It "has [Files] section" {
        $script:IssContent | Should -Match '\[Files\]'
    }
    It "has [Icons] section" {
        $script:IssContent | Should -Match '\[Icons\]'
    }
    It "has [Run] postinstall entry" {
        $script:IssContent | Should -Match '\[Run\]'
        $script:IssContent | Should -Match 'postinstall'
    }
    It "has [Code] section with PATH management" {
        $script:IssContent | Should -Match '\[Code\]'
        $script:IssContent | Should -Match 'AddToPath'
        $script:IssContent | Should -Match 'RemoveFromPath'
    }
    It "handles uninstall PATH cleanup" {
        $script:IssContent | Should -Match 'CurUninstallStepChanged'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "tian-setup.iss — source file paths exist" {

    # Parse every  Source: "..." line and verify the path (without glob) exists
    It "all Source directories referenced in [Files] exist on disk" {
        $filesSection = $false
        $missing      = @()

        foreach ($line in ($script:IssContent -split "`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[') {
                $filesSection = ($trimmed -match '^\[Files\]')
                continue
            }
            if (-not $filesSection) { continue }
            if ($trimmed -match 'Source:\s*"([^"]+)"') {
                # Resolve relative to installer\ dir, strip trailing wildcard
                $raw     = $Matches[1] -replace '[\\/]\*$', ''
                $abs     = [System.IO.Path]::GetFullPath((Join-Path $script:InstallerDir $raw))
                if (-not (Test-Path $abs)) { $missing += $abs }
            }
        }

        if ($missing.Count -gt 0) {
            $list = $missing -join "`n  "
            throw "Missing source paths referenced in tian-setup.iss:`n  $list"
        }
        $missing.Count | Should -Be 0
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "tian-setup.iss — tasks" {

    It "has addtopath task checked by default" {
        $script:IssContent | Should -Match 'Name:\s*"addtopath"'
        $script:IssContent | Should -Match 'checkedonce'
    }
    It "has desktopicon task" {
        $script:IssContent | Should -Match 'Name:\s*"desktopicon"'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "get-installer.bat — content" {

    BeforeAll {
        $script:BatContent = Get-Content $script:GetInstaller -Raw
    }

    It "file exists at repo root" {
        Test-Path $script:GetInstaller | Should -BeTrue
    }
    It "uses Invoke-WebRequest to download" {
        $script:BatContent | Should -Match 'Invoke-WebRequest'
    }
    It "targets releases/latest" {
        $script:BatContent | Should -Match 'releases/latest'
    }
    It "saves to a TEMP path" {
        $script:BatContent | Should -Match '%TEMP%'
    }
    It "launches the downloaded installer with start /wait" {
        $script:BatContent | Should -Match 'start\s+/wait'
    }
    It "has browser fallback when download fails" {
        $script:BatContent | Should -Match 'start.*releases'
    }
    It "cleans up temp file after install" {
        $script:BatContent | Should -Match 'del\b.*%DEST%'
    }
    It "handles download error with message" {
        $script:BatContent | Should -Match 'ERROR'
        $script:BatContent | Should -Match 'ERRORLEVEL'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
Describe "Invoke-Build — error path (no iscc)" {

    It "exits with code 1 when iscc is absent" {
        if (-not $IsWindows) { Set-ItResult -Skipped -Because "exit codes from child process only reliable on Windows" }

        $pwsh = (Get-Process -Id $PID).MainModule.FileName
        $script = "$(Get-TianRoot)/installer/build-installer.ps1"

        # Intercept iscc lookup by prepending a function override on the command line
        & $pwsh -NoProfile -Command "
            function Get-Command { param([string]`$Name,[string]`$ErrorAction) `$null }
            function Test-Path   { param(`$Path) `$false }
            & '$script' 2>&1
            exit `$LASTEXITCODE
        "
        $exitCode = $LASTEXITCODE
        $exitCode | Should -Be 1
    }
}
