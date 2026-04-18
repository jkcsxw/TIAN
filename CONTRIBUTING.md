# Contributing to Tian

Tian is designed to be extended by the community. You don't need to write PowerShell to add new AI backends, MCP servers, or skills.

---

## Adding a New AI Backend

Edit `config/catalog.json` and add an entry to the `backends` array:

```json
{
  "id": "my-backend",
  "displayName": "My AI Assistant",
  "description": "One sentence description shown in the wizard.",
  "npmPackage": "my-ai-package",
  "cliCommand": "myai",
  "apiKeyEnvVar": "MY_API_KEY",
  "apiKeyLabel": "My API Key",
  "apiKeyHint": "Starts with ...",
  "apiKeyUrl": "https://example.com/get-key",
  "mcpConfigTarget": "claude_code",
  "defaultMcpServers": [],
  "defaultSkills": []
}
```

If your backend stores MCP config in a non-standard location, add:
```json
"mcpConfigTarget": "custom",
"mcpConfigPath": "%APPDATA%\\MyApp\\config.json"
```

---

## Adding a New MCP Server

Add an entry to the `mcpServers` array in `config/catalog.json`:

```json
{
  "id": "my-server",
  "displayName": "My Tool",
  "description": "What this tool does for the user.",
  "category": "Productivity",
  "npmPackage": "my-mcp-server",
  "configKey": "my-server",
  "configSchema": {
    "command": "npx",
    "args": ["-y", "my-mcp-server"]
  }
}
```

If your server needs extra credentials, add:
```json
"requiredEnvVars": [
  {
    "name": "MY_TOKEN",
    "label": "My Token",
    "hint": "Get it from example.com",
    "url": "https://example.com/token"
  }
]
```

---

## Adding a New Skill

### Option 1: Built-in prompt file

1. Create a Markdown file in `skills/my-skill.md` describing what the AI should do.
2. Add an entry to the `skills` array in `config/catalog.json`:

```json
{
  "id": "my-skill",
  "displayName": "My Skill",
  "description": "One sentence shown in the wizard.",
  "category": "Daily Use",
  "source": "builtin",
  "promptFile": "skills/my-skill.md"
}
```

### Option 2: npm package

```json
{
  "id": "my-npm-skill",
  "displayName": "My NPM Skill",
  "description": "...",
  "category": "Developer",
  "source": "npm",
  "npmPackage": "my-skill-package"
}
```

---

## Wizard UI Changes

The wizard is split into pages under `wizard/pages/`. Each page is a self-contained PowerShell file with a single `Show-Page-*` function. Add a new page by:

1. Creating `wizard/pages/Page-MyPage.ps1` with a `Show-Page-MyPage` function
2. Dot-sourcing it in `wizard/Main.ps1`
3. Adding `"MyPage"` to the `$pages` array in the right position
4. Adding a `"MyPage"` case to the `switch` in `Show-CurrentPage`

---

## Test Status

[![CI](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg)](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml)

All tests run automatically on every push and pull request via GitHub Actions.

| Suite | Platform | Status |
|-------|----------|--------|
| Pester (PowerShell) | Windows | ![Windows](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |
| Bash | Linux (Ubuntu) | ![Linux](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |
| Bash + Pester | macOS | ![macOS](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml/badge.svg) |

Full run history: [Actions → CI](https://github.com/jkcsxw/TIAN/actions/workflows/ci.yml) · See [`TESTING.md`](TESTING.md) for full test layout and how to write new tests.

---

## Testing

### Running Tests

**Windows** — run from the repo root:

```bat
tests\run-tests.bat
```

This auto-installs Pester v5 if missing, then runs all `tests/ps/*.Tests.ps1` files and writes results to `tests/results-windows.xml`.

**Mac / Linux** — run from the repo root:

```bash
bash tests/run-tests.sh
```

This runs all `tests/bash/test-*.sh` suites. If `pwsh` is on your PATH it also runs the Pester suite and writes results to `tests/results-unix.xml`.

### Running a Single Suite

```powershell
# Pester (any platform with pwsh)
Invoke-Pester tests/ps/Runner.Tests.ps1 -Output Detailed
Invoke-Pester tests/ps/Scheduler.Tests.ps1 -Output Detailed
```

```bash
# Bash (Mac / Linux)
bash tests/bash/test-jobs.sh
bash tests/bash/test-schedule.sh
bash tests/bash/test-catalog-parse.sh
```

### Test Structure

```
tests/
  ps/                        # Pester v5 tests (PowerShell modules)
    helpers/
      TestHelpers.ps1        # Shared stubs: Append-Log, New-FakeProgressBar, Get-TianRoot, New-TestTempDir
    Runner.Tests.ps1         # cli/runner.ps1 — job CRUD, New-JobId, Invoke-Task
    Scheduler.Tests.ps1      # cli/scheduler.ps1 — schedule CRUD, schtasks args
    SkillInstaller.Tests.ps1 # wizard/lib/SkillInstaller.ps1
    McpConfigurator.Tests.ps1
    CliRouter.Tests.ps1      # end-to-end tian.ps1 subcommand routing
  bash/
    bash-helpers.sh          # suite/it/assert_* framework
    test-jobs.sh             # bash job management helpers
    test-schedule.sh         # bash scheduler helpers + plist generation
    test-catalog-parse.sh    # config/catalog.json schema validation
  run-tests.bat              # Windows entry-point
  run-tests.sh               # Mac/Linux entry-point
```

### Writing New Tests

**When to add a Pester test** — for any PowerShell function in `cli/` or `wizard/lib/`. Create `tests/ps/<Module>.Tests.ps1`.

**When to add a bash test** — for any function in `mac/tian-cli-bash.sh` or pure shell logic.

**Pester test skeleton:**

```powershell
BeforeAll {
    . "$PSScriptRoot/helpers/TestHelpers.ps1"
    $script:TempDir = New-TestTempDir
    # stub Write-* so tests never need full CLI context
    function global:Write-Ok   { param($t) }
    function global:Write-Info { param($t) }
    function global:Write-Warn { param($t) }
    function global:Write-Fail { param($t) throw $t }
    # dot-source the module, then override any global paths it set
    . "$(Get-TianRoot)/cli/my-module.ps1"
    $global:MY_DATA_FILE = Join-Path $script:TempDir "data.json"
}
AfterAll { Remove-Item $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue }

Describe "My-Function" {
    BeforeEach { Remove-Item $global:MY_DATA_FILE -ErrorAction SilentlyContinue }

    It "does the thing" {
        My-Function -Arg "value"
        $result = Get-Content $global:MY_DATA_FILE | ConvertFrom-Json
        $result.name | Should -Be "value"
    }
}
```

**Key helpers in TestHelpers.ps1:**

| Helper | Purpose |
|---|---|
| `Get-TianRoot` | Returns repo root path |
| `New-TestTempDir` | Creates an isolated temp directory for a test run |
| `New-FakeProgressBar` | Returns a PSCustomObject with a writable `Value` property |
| `$script:LogMessages` | Captures `Append-Log` calls when set before dot-sourcing |

**Platform-specific tests** — skip cleanly rather than failing:

```powershell
It "does Windows-only thing" {
    if (-not $IsWindows) { Set-ItResult -Skipped -Because "Windows only" }
    # ...
}
It "does Mac-only thing" {
    if (-not $IsMacOS) { Set-ItResult -Skipped -Because "macOS only" }
    # ...
}
```

**Mocking external commands** — wrap them in a PowerShell function first, then mock the wrapper:

```powershell
# In the source file (e.g. scheduler.ps1):
function Invoke-Launchctl { param($Action, $PlistFile); & launchctl $Action $PlistFile 2>&1 }

# In the test:
Mock Invoke-Launchctl { }
```

---

## Building the Windows Installer

The installer is built with [Inno Setup 6](https://jrsoftware.org/isdl.php) (free). The script lives at `installer/tian-setup.iss`.

### Prerequisites

Install Inno Setup 6 (once):

```bat
winget install JRSoftware.InnoSetup
```

Or download from https://jrsoftware.org/isdl.php and run the installer.

### Build

```bat
:: From the repo root (Windows)
installer\build-installer.bat

:: Or with PowerShell, with a custom version number
powershell -ExecutionPolicy Bypass -File installer\build-installer.ps1 -Version "1.2.0"
```

Output is written to `installer/dist/tian-setup-<version>.exe`. That directory is git-ignored.

### Customising the installer

| What to change | Where |
|---|---|
| App version | `#define AppVersion` in `installer/tian-setup.iss` |
| App icon | Place `tian.ico` in `installer/assets/` and uncomment `SetupIconFile` |
| License file | Place `LICENSE` in the repo root and uncomment `LicenseFile` |
| Files bundled | `[Files]` section in `tian-setup.iss` |
| Default install dir | `DefaultDirName` in `[Setup]` |

### Code-signing (optional)

If you have a Windows code-signing certificate:

```powershell
installer\build-installer.ps1 -Sign
```

This runs `signtool sign` with a SHA-256 timestamp after compilation. Add your certificate thumbprint or PFX path to the `signtool` call in `build-installer.ps1` if you use a specific cert.

---

## Pull Request Guidelines

- Test on Windows 10 and Windows 11 if possible
- Keep each PR focused: one backend, one MCP server, or one skill per PR
- Update `README.md` if you add a new backend or category of MCP servers
- Add or update tests for any logic you change in `cli/` or `wizard/lib/`
