# Testing

[![CI](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg)](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml)

All tests run automatically on every push and pull request via GitHub Actions.

---

## Test Status

| Suite | Runner | Status |
|-------|--------|--------|
| Pester (PowerShell) | Windows | ![Windows](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |
| Bash | Linux (Ubuntu) | ![Linux](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |
| Bash + Pester | macOS | ![macOS](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |

Full run history: [Actions → CI](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml)

---

## Test Layout

```
tests/
├── ps/                        # PowerShell / Pester v5 tests (Windows)
│   ├── helpers/TestHelpers.ps1
│   ├── Catalog.Tests.ps1
│   ├── CliRouter.Tests.ps1
│   ├── BackendInstaller.Tests.ps1
│   ├── McpConfigurator.Tests.ps1
│   ├── SkillInstaller.Tests.ps1
│   ├── EnvManager.Tests.ps1
│   ├── Runner.Tests.ps1
│   ├── Scheduler.Tests.ps1
│   ├── Installer.Tests.ps1
│   └── ConvertToHashtable.Tests.ps1
├── bash/                      # Bash tests (macOS / Linux)
│   ├── bash-helpers.sh
│   ├── test-catalog-parse.sh
│   ├── test-jobs.sh
│   ├── test-router.sh
│   └── test-schedule.sh
├── run-tests.bat              # Windows local runner
└── run-tests.sh               # macOS / Linux local runner
```

---

## Running Tests Locally

### Windows

```bat
tests\run-tests.bat
```

Requires PowerShell 5.1+. Pester v5 is auto-installed if missing.  
Results saved to `tests/results-windows.xml`.

### macOS / Linux

```bash
bash tests/run-tests.sh
```

Runs all bash suites. If `pwsh` (PowerShell Core) is available it also runs the Pester suite.  
Results saved to `tests/results-mac.xml`.

Install PowerShell Core on macOS to enable the Pester suite:

```bash
brew install --cask powershell
```

---

## CI Workflow

The workflow file is at `.github/workflows/ci.yml`. It runs three parallel jobs:

| Job | Runner | What it does |
|-----|--------|-------------|
| `test-windows` | `windows-latest` | Installs Pester v5, runs all `tests/ps/*.Tests.ps1` |
| `test-bash` | `ubuntu-latest` | Runs all `tests/bash/test-*.sh` |
| `test-macos` | `macos-latest` | Installs `pwsh`, runs `tests/run-tests.sh` (bash + Pester) |

Test result XML artifacts are uploaded after each run and available on the Actions summary page.

---

## Writing New Tests

### PowerShell (Pester v5)

Create `tests/ps/MyFeature.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    . "$(Get-TianRoot)/wizard/lib/MyFeature.ps1"
}

Describe "MyFeature" {
    It "does the thing" {
        MyFunction -Param "value" | Should -Be "expected"
    }
}
```

The helpers file provides `Get-TianRoot`, `New-TestTempDir`, `Write-TestJson`, and a no-op `Append-Log` stub so library modules load without Windows Forms.

### Bash

Create `tests/bash/test-myfeature.sh`:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/bash-helpers.sh"
TIAN_ROOT="$(get_tian_root)"

suite "My Feature"

it "does the thing" assert_eq "$(some_command)" "expected"

finish
```

The file is auto-discovered by both the local runner (`run-tests.sh`) and the CI workflow.
