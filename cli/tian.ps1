param(
    [string]$TianDir = (Split-Path $PSScriptRoot -Parent),
    [Parameter(Position = 0)][string]$Command = "help",
    [Parameter(Position = 1)][string]$Subcommand = "",
    [string]$Backend   = "",
    [string]$Key       = "",
    [string]$Mcp       = "",
    [string]$Skills    = "",
    # run / schedule flags
    [string]$Task      = "",
    [string]$Name      = "",
    [string]$Time      = "",
    [string]$Repeat    = "daily",
    [string]$Day       = "",
    [switch]$Background,
    [switch]$Yes,
    [switch]$All,
    [switch]$List
)

# ── Colour helpers ────────────────────────────────────────────────────────────
function Write-Color {
    param([string]$Text, [System.ConsoleColor]$Color = "White", [switch]$NoNewline)
    $prev = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    if ($NoNewline) { Write-Host $Text -NoNewline } else { Write-Host $Text }
    $Host.UI.RawUI.ForegroundColor = $prev
}
function Write-Header  { param([string]$t) Write-Color "`n$t" Cyan }
function Write-Ok      { param([string]$t) Write-Color "  [ok] $t" Green }
function Write-Info    { param([string]$t) Write-Color "  [..] $t" Gray }
function Write-Warn    { param([string]$t) Write-Color "  [!!] $t" Yellow }
function Write-Fail    { param([string]$t) Write-Color "  [xx] $t" Red }
function Write-Rule    { Write-Color ("─" * 60) DarkGray }

# ── Load shared libs ──────────────────────────────────────────────────────────
$libDir = Join-Path $TianDir "wizard\lib"
. "$libDir\Catalog.ps1"
. (Join-Path $PSScriptRoot "runner.ps1")
. (Join-Path $PSScriptRoot "scheduler.ps1")

# Minimal stubs so lib functions that expect a RichTextBox / ProgressBar still work
function Append-Log {
    param($LogBox, [string]$Message, [string]$Color = "normal")
    $colorMap = @{ normal="Gray"; info="Cyan"; success="Green"; warn="Yellow"; error="Red" }
    Write-Color "  $Message" $colorMap[$Color]
}

. "$libDir\NodeInstaller.ps1"
. "$libDir\BackendInstaller.ps1"
. "$libDir\EnvManager.ps1"
. "$libDir\McpConfigurator.ps1"
. "$libDir\SkillInstaller.ps1"

$catalog = Get-Catalog -TianDir $TianDir

# ── Helpers ───────────────────────────────────────────────────────────────────
function Get-BackendById($id) { $catalog.backends | Where-Object { $_.id -eq $id } | Select-Object -First 1 }
function Get-McpById($id)     { $catalog.mcpServers | Where-Object { $_.id -eq $id } | Select-Object -First 1 }
function Get-SkillById($id)   { $catalog.skills | Where-Object { $_.id -eq $id } | Select-Object -First 1 }

function Prompt-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 0)
    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "*" } else { " " }
        Write-Color "  $marker [$($i+1)] $($Options[$i])" White
    }
    Write-Host ""
    Write-Color "  $Prompt [$($Default+1)]: " Cyan -NoNewline
    $input = Read-Host
    if ($input -match '^\d+$') {
        $idx = [int]$input - 1
        if ($idx -ge 0 -and $idx -lt $Options.Count) { return $idx }
    }
    return $Default
}

function Prompt-MultiChoice {
    param([string]$Prompt, [string[]]$Options, [int[]]$Defaults = @())
    Write-Host ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $checked = if ($Defaults -contains $i) { "x" } else { " " }
        Write-Color "  [$checked] [$($i+1)] $($Options[$i])" White
    }
    Write-Color "`n  $Prompt (comma-separated numbers, Enter to keep defaults): " Cyan -NoNewline
    $input = (Read-Host).Trim()
    if ($input -eq "") { return $Defaults }
    return $input -split ',' | ForEach-Object { $t = $_.Trim(); if ($t -match '^\d+$') { [int]$t - 1 } } | Where-Object { $_ -ge 0 -and $_ -lt $Options.Count }
}

function Prompt-Secret {
    param([string]$Label)
    Write-Color "  $Label : " Cyan -NoNewline
    $secure = Read-Host -AsSecureString
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

function Confirm-Action {
    param([string]$Prompt)
    if ($Yes) { return $true }
    Write-Color "  $Prompt [y/N]: " Yellow -NoNewline
    return (Read-Host).Trim() -imatch '^y'
}

# Fake progress bar object so lib functions don't crash
$script:_fakeProgress = 0
$fakeProgress = [PSCustomObject]@{}
Add-Member -InputObject $fakeProgress -MemberType ScriptProperty -Name Value -Value { $script:_fakeProgress } -SecondValue { param($v) $script:_fakeProgress = $v }

# ── Commands ──────────────────────────────────────────────────────────────────

function Cmd-Help {
    Write-Color @"

  ████████╗██╗ █████╗ ███╗   ██╗
     ██╔══╝██║██╔══██╗████╗  ██║
     ██║   ██║███████║██╔██╗ ██║
     ██║   ██║██╔══██║██║╚██╗██║
     ██║   ██║██║  ██║██║ ╚████║
     ╚═╝   ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  CLI

  Talking Is All you Need
"@ Cyan

    Write-Rule
    Write-Color @"

  USAGE
    tian-cli <command> [subcommand] [options]

  COMMANDS
    setup               Interactive guided setup (recommended for first run)
    install             Non-interactive install with flags
    status              Show what is currently installed
    list backends       List available AI backends
    list mcp            List available MCP servers
    list skills         List available skills
    add mcp  <id>       Add an MCP server to your config
    add skill <id>      Install a skill
    remove mcp  <id>    Remove an MCP server from your config
    repair              Re-run install for the current config

    run  "prompt"       Run a task now (foreground)
    run  "prompt" --background   Run a task in the background
    jobs                List background jobs
    jobs result <id>    Show output of a completed job
    jobs clear          Clear completed jobs  (--all to clear everything)

    schedule add        Create a recurring scheduled task
    schedule list       List all scheduled tasks
    schedule run <n>    Run a scheduled task immediately
    schedule remove <n> Delete a scheduled task

    help                Show this help

  INSTALL FLAGS
    --backend <id>      AI backend to install  (e.g. claude-code)
    --key     <apikey>  API key for the backend
    --mcp     <ids>     Comma-separated MCP server IDs
    --skills  <ids>     Comma-separated skill IDs
    --yes               Skip all confirmation prompts

  SCHEDULE FLAGS
    --name    <name>    Schedule name (required)
    --task    "prompt"  The prompt to run (required)
    --time    HH:MM     Time of day to run  (default: 08:00)
    --repeat  <freq>    once | hourly | daily | weekly  (default: daily)
    --day     <days>    Days for weekly repeat  e.g. MON,WED,FRI

  EXAMPLES
    tian-cli setup
    tian-cli install --backend claude-code --key sk-ant-xxx --mcp filesystem,web-search --yes
    tian-cli list mcp
    tian-cli add mcp github
    tian-cli status

    tian-cli run "Summarise the latest news about AI"
    tian-cli run "Draft my daily standup update" --background
    tian-cli jobs
    tian-cli jobs result 20240417-083012-ab12cd

    tian-cli schedule add --name morning-brief --task "Give me a short morning briefing" --time 08:00 --repeat daily
    tian-cli schedule add --name weekly-report --task "Summarise this week's key themes" --time 09:00 --repeat weekly --day MON
    tian-cli schedule list
    tian-cli schedule run morning-brief
    tian-cli schedule remove morning-brief

"@ White
    Write-Rule
}

function Cmd-Setup {
    Write-Header "TIAN Interactive Setup"
    Write-Rule

    # 1. Backend
    Write-Header "Step 1 — Choose your AI backend"
    $backendNames = $catalog.backends | ForEach-Object { "$($_.displayName)  —  $($_.description)" }
    $idx = Prompt-Choice "Select backend" $backendNames 0
    $selectedBackend = $catalog.backends[$idx]
    Write-Ok "Selected: $($selectedBackend.displayName)"

    # 2. API key
    Write-Header "Step 2 — Enter your API key"
    Write-Info "$($selectedBackend.apiKeyLabel)  ($($selectedBackend.apiKeyHint))"
    Write-Info "Get one at: $($selectedBackend.apiKeyUrl)"
    $apiKey = Prompt-Secret $selectedBackend.apiKeyLabel

    # 3. MCP servers
    Write-Header "Step 3 — Choose MCP tools"
    $mcpNames = $catalog.mcpServers | ForEach-Object { "$($_.displayName)  —  $($_.description)" }
    $defaultIdxs = @()
    for ($i = 0; $i -lt $catalog.mcpServers.Count; $i++) {
        if ($selectedBackend.defaultMcpServers -contains $catalog.mcpServers[$i].id) { $defaultIdxs += $i }
    }
    $mcpIdxs = Prompt-MultiChoice "Select MCP tools" $mcpNames $defaultIdxs
    $selectedMcp = @($mcpIdxs | ForEach-Object { $catalog.mcpServers[$_] })

    # Extra env vars for chosen MCP servers
    $extraEnvVars = @{}
    $requiredVars = $selectedMcp | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars }
    foreach ($ev in $requiredVars) {
        Write-Info "$($ev.label) — $($ev.hint)"
        if ($ev.url) { Write-Info "Get it at: $($ev.url)" }
        $val = Prompt-Secret $ev.label
        if ($val) { $extraEnvVars[$ev.name] = $val }
    }

    # 4. Skills
    Write-Header "Step 4 — Choose skills"
    $skillNames = $catalog.skills | ForEach-Object { "$($_.displayName)  —  $($_.description)" }
    $skillIdxs = Prompt-MultiChoice "Select skills" $skillNames @()
    $selectedSkills = @($skillIdxs | ForEach-Object { $catalog.skills[$_] })

    # 5. Confirm
    Write-Header "Ready to install"
    Write-Info "Backend : $($selectedBackend.displayName)"
    Write-Info "MCP     : $(if ($selectedMcp.Count) { ($selectedMcp | ForEach-Object { $_.displayName }) -join ', ' } else { 'none' })"
    Write-Info "Skills  : $(if ($selectedSkills.Count) { ($selectedSkills | ForEach-Object { $_.displayName }) -join ', ' } else { 'none' })"
    Write-Host ""

    if (-not (Confirm-Action "Proceed with installation?")) {
        Write-Warn "Setup cancelled."
        return
    }

    Run-Install $selectedBackend $apiKey $extraEnvVars $selectedMcp $selectedSkills
}

function Cmd-Install {
    if (-not $Backend) { Write-Fail "Missing --backend. Run 'tian-cli help' for usage."; exit 1 }

    $selectedBackend = Get-BackendById $Backend
    if (-not $selectedBackend) {
        Write-Fail "Unknown backend '$Backend'. Run 'tian-cli list backends' to see options."
        exit 1
    }

    $apiKey = $Key
    if (-not $apiKey) {
        Write-Info "$($selectedBackend.apiKeyLabel)  ($($selectedBackend.apiKeyHint))"
        $apiKey = Prompt-Secret $selectedBackend.apiKeyLabel
    }

    $selectedMcp = @()
    if ($Mcp) {
        $selectedMcp = @($Mcp -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
            $s = Get-McpById $_
            if (-not $s) { Write-Warn "Unknown MCP id '$_' — skipping." } else { $s }
        } | Where-Object { $_ })
    }

    $selectedSkills = @()
    if ($Skills) {
        $selectedSkills = @($Skills -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
            $s = Get-SkillById $_
            if (-not $s) { Write-Warn "Unknown skill id '$_' — skipping." } else { $s }
        } | Where-Object { $_ })
    }

    $extraEnvVars = @{}
    $requiredVars = $selectedMcp | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars }
    foreach ($ev in $requiredVars) {
        $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
        if (-not $existing) {
            Write-Info "Required for $($ev.label):"
            $val = Prompt-Secret $ev.label
            if ($val) { $extraEnvVars[$ev.name] = $val }
        }
    }

    Run-Install $selectedBackend $apiKey $extraEnvVars $selectedMcp $selectedSkills
}

function Run-Install($selectedBackend, $apiKey, $extraEnvVars, $selectedMcp, $selectedSkills) {
    Write-Header "Installing"
    Write-Rule

    Write-Info "Step 1/5  Checking Node.js..."
    $ok = Install-Node -LogBox $null -ProgressBar $fakeProgress
    if (-not $ok) { Write-Fail "Node.js installation failed. Aborting."; exit 1 }

    Write-Info "Step 2/5  Installing $($selectedBackend.displayName)..."
    $ok = Install-Backend -Backend $selectedBackend -LogBox $null -ProgressBar $fakeProgress
    if (-not $ok) { Write-Fail "Backend installation failed. Aborting."; exit 1 }

    Write-Info "Step 3/5  Saving API key..."
    Set-ApiKey -Backend $selectedBackend -ApiKey $apiKey -LogBox $null
    foreach ($kvp in $extraEnvVars.GetEnumerator()) {
        Set-ExtraEnvVar -Name $kvp.Key -Value $kvp.Value -LogBox $null
    }

    Write-Info "Step 4/5  Configuring MCP servers..."
    Set-McpServers -Backend $selectedBackend -SelectedServers $selectedMcp -LogBox $null -ProgressBar $fakeProgress

    Write-Info "Step 5/5  Installing skills..."
    Install-Skills -SelectedSkills $selectedSkills -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress

    Write-Launcher -Backend $selectedBackend -TianDir $TianDir -LogBox $null

    Write-Rule
    Write-Ok "Installation complete!"
    Write-Host ""
    if ($selectedBackend.cliCommand) {
        Write-Color "  Run 'tian-cli status' to verify, then launch with:" White
        Write-Color "    $($selectedBackend.cliCommand)" Cyan
    }
    Write-Host ""
}

function Cmd-Status {
    Write-Header "TIAN Status"
    Write-Rule

    # Node.js
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { Write-Ok "Node.js    $( & node --version 2>&1 )" }
    else        { Write-Fail "Node.js    not found" }

    # Backends
    Write-Host ""
    Write-Color "  AI Backends:" Gray
    foreach ($b in $catalog.backends) {
        if (-not $b.cliCommand) { continue }
        $cmd = Get-Command $b.cliCommand -ErrorAction SilentlyContinue
        if ($cmd) { Write-Ok "$($b.displayName.PadRight(22)) $($b.cliCommand)" }
        else       { Write-Warn "$($b.displayName.PadRight(22)) not installed" }
    }

    # API keys
    Write-Host ""
    Write-Color "  API Keys:" Gray
    foreach ($b in $catalog.backends) {
        $varName = $b.apiKeyEnvVar
        $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
        if ($val) { Write-Ok "$($varName.PadRight(30)) set" }
        else       { Write-Warn "$($varName.PadRight(30)) not set" }
    }

    # MCP config
    Write-Host ""
    Write-Color "  MCP Config Files:" Gray
    $targets = $catalog.backends | Select-Object -ExpandProperty mcpConfigTarget -Unique
    foreach ($t in $targets) {
        $fakeBackend = [PSCustomObject]@{ mcpConfigTarget = $t; mcpConfigPath = "" }
        $path = Get-McpConfigPath $fakeBackend
        if (Test-Path $path) { Write-Ok "$t`n     $path" }
        else                  { Write-Warn "$t — config not found" }
    }

    # Launcher
    Write-Host ""
    $launcherPath = Join-Path $TianDir "launcher.bat"
    if (Test-Path $launcherPath) { Write-Ok "launcher.bat exists" }
    else                          { Write-Warn "launcher.bat not found — run setup first" }

    Write-Host ""
    Write-Rule
}

function Cmd-List {
    switch ($Subcommand) {
        "backends" {
            Write-Header "Available AI Backends"
            Write-Rule
            foreach ($b in $catalog.backends) {
                Write-Color "  $($b.id.PadRight(18))" Cyan -NoNewline
                Write-Color " $($b.displayName)" White
                Write-Color "  $(" " * 18) $($b.description)" Gray
                Write-Host ""
            }
        }
        "mcp" {
            Write-Header "Available MCP Servers"
            Write-Rule
            $groups = $catalog.mcpServers | Group-Object { $_.category }
            foreach ($g in $groups) {
                Write-Color "  $($g.Name)" Yellow
                foreach ($s in $g.Group) {
                    Write-Color "    $($s.id.PadRight(20))" Cyan -NoNewline
                    Write-Color " $($s.displayName.PadRight(26))" White -NoNewline
                    Write-Color " $($s.description)" Gray
                }
                Write-Host ""
            }
        }
        "skills" {
            Write-Header "Available Skills"
            Write-Rule
            $groups = $catalog.skills | Group-Object { $_.category }
            foreach ($g in $groups) {
                Write-Color "  $($g.Name)" Yellow
                foreach ($s in $g.Group) {
                    Write-Color "    $($s.id.PadRight(24))" Cyan -NoNewline
                    Write-Color " $($s.displayName.PadRight(28))" White -NoNewline
                    Write-Color " $($s.description)" Gray
                }
                Write-Host ""
            }
        }
        default {
            Write-Fail "Unknown list target '$Subcommand'. Try: backends, mcp, skills"
        }
    }
    Write-Rule
}

function Cmd-Add {
    switch ($Subcommand) {
        "mcp" {
            $id = $Command  # positional arg after 'add mcp'
            # When called as: tian-cli add mcp <id>, $Subcommand="mcp", $id comes from args
            # Re-read from raw args
            $id = $args[0]
            if (-not $id) {
                Write-Fail "Usage: tian-cli add mcp <id>   (run 'tian-cli list mcp' for IDs)"
                return
            }
            $server = Get-McpById $id
            if (-not $server) { Write-Fail "Unknown MCP id '$id'"; return }

            # Determine which backend to configure for
            $backendNames = $catalog.backends | ForEach-Object { $_.displayName }
            $idx = Prompt-Choice "Which backend to add this to?" $backendNames 0
            $backend = $catalog.backends[$idx]

            $extraEnvVars = @{}
            if ($server.requiredEnvVars) {
                foreach ($ev in $server.requiredEnvVars) {
                    $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
                    if (-not $existing) {
                        Write-Info "$($ev.label)"
                        if ($ev.url) { Write-Info "Get it at: $($ev.url)" }
                        $val = Prompt-Secret $ev.label
                        if ($val) { Set-ExtraEnvVar -Name $ev.name -Value $val -LogBox $null }
                    }
                }
            }

            Set-McpServers -Backend $backend -SelectedServers @($server) -LogBox $null -ProgressBar $fakeProgress
            Write-Ok "$($server.displayName) added to $($backend.displayName) config."
        }
        "skill" {
            $id = $args[0]
            if (-not $id) {
                Write-Fail "Usage: tian-cli add skill <id>   (run 'tian-cli list skills' for IDs)"
                return
            }
            $skill = Get-SkillById $id
            if (-not $skill) { Write-Fail "Unknown skill id '$id'"; return }
            Install-Skills -SelectedSkills @($skill) -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress
            Write-Ok "$($skill.displayName) installed."
        }
        default {
            Write-Fail "Usage: tian-cli add mcp <id>  |  tian-cli add skill <id>"
        }
    }
}

function Cmd-Remove {
    switch ($Subcommand) {
        "mcp" {
            $id = $args[0]
            if (-not $id) { Write-Fail "Usage: tian-cli remove mcp <id>"; return }
            $server = Get-McpById $id
            if (-not $server) { Write-Fail "Unknown MCP id '$id'"; return }

            $backendNames = $catalog.backends | ForEach-Object { $_.displayName }
            $idx = Prompt-Choice "Which backend to remove this from?" $backendNames 0
            $backend = $catalog.backends[$idx]
            $configPath = Get-McpConfigPath $backend

            if (-not (Test-Path $configPath)) { Write-Warn "Config file not found: $configPath"; return }

            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            $ht = ConvertTo-Hashtable $config
            if ($ht.mcpServers -and $ht.mcpServers.ContainsKey($server.configKey)) {
                $ht.mcpServers.Remove($server.configKey)
                $ht | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
                Write-Ok "$($server.displayName) removed from config."
            } else {
                Write-Warn "$($server.displayName) was not in config."
            }
        }
        default {
            Write-Fail "Usage: tian-cli remove mcp <id>"
        }
    }
}

function Cmd-Repair {
    Write-Header "TIAN Repair"
    Write-Info "This will re-run the install for your current config."
    if (-not (Confirm-Action "Continue?")) { return }
    Cmd-Setup
}

# ── Router ────────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "setup"   { Cmd-Setup }
    "install" { Cmd-Install }
    "status"  { Cmd-Status }
    "list"    { Cmd-List }
    "add"     {
        # tian-cli add mcp <id>  =>  Command=add, Subcommand=mcp, args[0]=id
        $id = $args[0]
        switch ($Subcommand.ToLower()) {
            "mcp"   {
                $server = Get-McpById $id
                if (-not $server) { Write-Fail "Unknown MCP id '$id'. Run 'tian-cli list mcp'."; exit 1 }
                $backendNames = $catalog.backends | ForEach-Object { $_.displayName }
                $bIdx = Prompt-Choice "Which backend to add this to?" $backendNames 0
                $backend = $catalog.backends[$bIdx]
                if ($server.requiredEnvVars) {
                    foreach ($ev in $server.requiredEnvVars) {
                        $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
                        if (-not $existing) {
                            Write-Info "$($ev.label)"; if ($ev.url) { Write-Info "Get it at: $($ev.url)" }
                            $val = Prompt-Secret $ev.label
                            if ($val) { Set-ExtraEnvVar -Name $ev.name -Value $val -LogBox $null }
                        }
                    }
                }
                Set-McpServers -Backend $backend -SelectedServers @($server) -LogBox $null -ProgressBar $fakeProgress
                Write-Ok "$($server.displayName) added."
            }
            "skill" {
                $skill = Get-SkillById $id
                if (-not $skill) { Write-Fail "Unknown skill id '$id'. Run 'tian-cli list skills'."; exit 1 }
                Install-Skills -SelectedSkills @($skill) -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress
                Write-Ok "$($skill.displayName) installed."
            }
            default { Write-Fail "Usage: tian-cli add mcp <id>  |  tian-cli add skill <id>" }
        }
    }
    "remove"  {
        $id = $args[0]
        if ($Subcommand.ToLower() -eq "mcp") {
            $server = Get-McpById $id
            if (-not $server) { Write-Fail "Unknown MCP id '$id'. Run 'tian-cli list mcp'."; exit 1 }
            $backendNames = $catalog.backends | ForEach-Object { $_.displayName }
            $bIdx = Prompt-Choice "Which backend to remove this from?" $backendNames 0
            $backend = $catalog.backends[$bIdx]
            $configPath = Get-McpConfigPath $backend
            if (-not (Test-Path $configPath)) { Write-Warn "Config not found: $configPath"; exit 1 }
            $ht = ConvertTo-Hashtable (Get-Content $configPath -Raw | ConvertFrom-Json)
            if ($ht.mcpServers -and $ht.mcpServers.ContainsKey($server.configKey)) {
                $ht.mcpServers.Remove($server.configKey)
                $ht | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
                Write-Ok "$($server.displayName) removed."
            } else { Write-Warn "$($server.displayName) was not configured." }
        } else { Write-Fail "Usage: tian-cli remove mcp <id>" }
    }
    "repair"  { Cmd-Repair }

    "run" {
        # tian-cli run "prompt"  or  tian-cli run "prompt" --background
        $prompt = if ($Subcommand) { $Subcommand } elseif ($Task) { $Task } else { "" }
        if (-not $prompt) {
            Write-Fail "Usage: tian-cli run `"your task prompt`" [--background]"
            exit 1
        }
        Invoke-Task -Prompt $prompt -TianDir $TianDir -Background:$Background
    }

    "jobs" {
        switch ($Subcommand.ToLower()) {
            "result" {
                if (-not $Name) { Write-Fail "Usage: tian-cli jobs result <job-id>"; exit 1 }
                Show-JobResult -JobId $Name
            }
            "clear"  { Clear-Jobs -All:$All }
            ""       { Show-Jobs }
            default  { Show-Jobs }
        }
    }

    "schedule" {
        switch ($Subcommand.ToLower()) {
            "add" {
                Add-Schedule -Name $Name -Prompt $Task -Time $Time -Repeat $Repeat -DayOfWeek $Day -TianDir $TianDir
            }
            "list"   { Show-Schedules }
            "run"    {
                if (-not $Name) { Write-Fail "Usage: tian-cli schedule run <name>"; exit 1 }
                Invoke-ScheduleNow -Name $Name -TianDir $TianDir
            }
            "remove" {
                if (-not $Name) { Write-Fail "Usage: tian-cli schedule remove --name <name>"; exit 1 }
                Remove-Schedule -Name $Name -TianDir $TianDir
            }
            default  { Write-Fail "Usage: tian-cli schedule add|list|run|remove" }
        }
    }

    { $_ -in "help","--help","-h","" } { Cmd-Help }
    default   { Write-Fail "Unknown command '$Command'. Run 'tian-cli help'."; exit 1 }
}
