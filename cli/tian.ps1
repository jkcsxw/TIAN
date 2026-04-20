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
. "$libDir\Strings.ps1"
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

try {
    $catalog = Get-Catalog -TianDir $TianDir
} catch {
    Write-Fail "TIAN catalog not found or corrupted. Reinstall TIAN or restore config/catalog.json."
    Write-Fail $_.Exception.Message
    exit 1
}

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

  $(T "cli.tagline")
"@ Cyan

    Write-Rule
    if ($global:TIAN_LANG -eq "zh") {
        Write-Color @"

  用法
    tian-cli <命令> [子命令] [选项]

  命令
    setup               交互式引导安装（首次使用推荐）
    install             使用参数快速安装
    doctor              诊断常见安装问题
    update              将已安装的AI后端更新到最新版本
    uninstall           移除TIAN安装的组件（后端、密钥、数据）
    status              查看当前安装状态
    list backends       列出可用AI后端
    list mcp            列出可用MCP服务器
    list skills         列出可用技能包
    add mcp  <id>       添加MCP服务器到配置
    add skill <id>      安装技能包
    remove mcp  <id>    从配置中移除MCP服务器
    repair              重新安装修复当前配置
    lang en|zh          切换界面语言

    run  "提示词"              立即执行任务（前台）
    run  "提示词" --background 在后台执行任务
    jobs                      列出后台任务
    jobs result <id>          查看已完成任务的输出
    jobs clear                清除已完成任务（--all 清除全部）

    schedule add              创建定时任务
    schedule list             列出所有定时任务
    schedule run <名称>        立即运行某个定时任务
    schedule remove <名称>     删除定时任务

    help                      显示此帮助

  安装参数
    --backend <id>      指定AI后端（例如 claude-code）
    --key     <apikey>  指定API密钥
    --mcp     <ids>     MCP服务器ID（逗号分隔）
    --skills  <ids>     技能包ID（逗号分隔）
    --yes               跳过所有确认提示

  定时参数
    --name    <名称>    定时任务名称（必填）
    --task    "提示词"  要执行的任务（必填）
    --time    HH:MM    执行时间（默认 08:00）
    --repeat  <频率>    once | hourly | daily | weekly（默认 daily）
    --day     <星期>    weekly 时指定星期，例如 MON,WED,FRI

  示例
    tian-cli setup
    tian-cli install --backend claude-code --key sk-ant-xxx --mcp filesystem,web-search --yes
    tian-cli list mcp
    tian-cli add mcp github
    tian-cli status
    tian-cli update
    tian-cli lang en

    tian-cli run "总结今日AI领域最新动态"
    tian-cli run "帮我写今天的工作日报" --background
    tian-cli jobs
    tian-cli jobs result 20240417-083012-ab12cd

    tian-cli schedule add --name morning-brief --task "给我一份简短的早间简报" --time 08:00 --repeat daily
    tian-cli schedule list
    tian-cli schedule run morning-brief
    tian-cli schedule remove morning-brief

"@ White
    } else {
        Write-Color @"

  USAGE
    tian-cli <command> [subcommand] [options]

  COMMANDS
    setup               Interactive guided setup (recommended for first-time users)
    install             Non-interactive install with flags
    doctor              Check your setup and diagnose common problems
    update              Upgrade installed AI backends to their latest versions
    uninstall           Remove TIAN's installed components (backends, keys, data)
    status              Show what is currently installed
    list backends       List available AI backends
    list mcp            List available MCP servers
    list skills         List available skills
    add mcp  <id>       Add an MCP server to your config
    add skill <id>      Install a skill
    remove mcp  <id>    Remove an MCP server from your config
    repair              Re-run install to fix the current config
    lang en|zh          Switch interface language

    run  "prompt"              Run a task now (foreground)
    run  "prompt" --background Run a task in the background
    jobs                       List background jobs
    jobs result <id>           Show output of a completed job
    jobs clear                 Clear completed jobs (--all clears all)

    schedule add               Create a recurring scheduled task
    schedule list              List all scheduled tasks
    schedule run <name>        Run a scheduled task immediately
    schedule remove <name>     Delete a scheduled task

    help                       Show this help

  INSTALL FLAGS
    --backend <id>      AI backend to use (e.g. claude-code)
    --key     <apikey>  API key
    --mcp     <ids>     MCP server IDs (comma-separated)
    --skills  <ids>     Skill IDs (comma-separated)
    --yes               Skip all confirmation prompts

  SCHEDULE FLAGS
    --name    <name>    Schedule name (required)
    --task    "prompt"  Task prompt (required)
    --time    HH:MM    Time to run (default 08:00)
    --repeat  <freq>    once | hourly | daily | weekly (default daily)
    --day     <day>     Day for weekly, e.g. MON,WED,FRI

  EXAMPLES
    tian-cli setup
    tian-cli install --backend claude-code --key sk-ant-xxx --mcp filesystem,web-search --yes
    tian-cli list mcp
    tian-cli add mcp github
    tian-cli status
    tian-cli update
    tian-cli lang zh

    tian-cli run "Summarise today's AI news"
    tian-cli run "Write my daily work report" --background
    tian-cli jobs
    tian-cli jobs result 20240417-083012-ab12cd

    tian-cli schedule add --name morning-brief --task "Give me a short morning briefing" --time 08:00 --repeat daily
    tian-cli schedule list
    tian-cli schedule run morning-brief
    tian-cli schedule remove morning-brief

"@ White
    }
    Write-Rule
}

function Cmd-Setup {
    Write-Header (T "cli.setup_header")
    Write-Rule

    Write-Header (T "cli.step1_header")
    $backendNames = $catalog.backends | ForEach-Object { "$(Get-DisplayName $_)  —  $(Get-Description $_)" }
    $idx = Prompt-Choice (T "cli.select_backend") $backendNames 0
    $selectedBackend = $catalog.backends[$idx]
    Write-Ok (TF "cli.selected" $selectedBackend.displayName)

    Write-Header (T "cli.step2_header")
    $apiKey = ""
    if (Test-BackendRequiresApiKey $selectedBackend) {
        $keyLabel = Get-ApiKeyLabel $selectedBackend
        Write-Info "$keyLabel  ($($selectedBackend.apiKeyHint))"
        Write-Info (TF "cli.get_at" $selectedBackend.apiKeyUrl)
        $apiKey = Prompt-Secret $keyLabel
    } elseif ($selectedBackend.setupNote) {
        Write-Info $selectedBackend.setupNote
    }

    Write-Header (T "cli.step3_header")
    $selectedMcp = @()
    $extraEnvVars = @{}
    if (Test-BackendSupportsMcp $selectedBackend) {
        $mcpNames = $catalog.mcpServers | ForEach-Object { "$(Get-DisplayName $_)  —  $(Get-Description $_)" }
        $defaultIdxs = @()
        for ($i = 0; $i -lt $catalog.mcpServers.Count; $i++) {
            if ($selectedBackend.defaultMcpServers -contains $catalog.mcpServers[$i].id) { $defaultIdxs += $i }
        }
        $mcpIdxs = Prompt-MultiChoice (T "cli.select_mcp") $mcpNames $defaultIdxs
        $selectedMcp = @($mcpIdxs | ForEach-Object { $catalog.mcpServers[$_] })

        $requiredVars = $selectedMcp | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars }
        foreach ($ev in $requiredVars) {
            $evLabel = if ($global:TIAN_LANG -eq "zh" -and $ev.labelZh) { $ev.labelZh } else { $ev.label }
            Write-Info "$evLabel — $($ev.hint)"
            if ($ev.url) { Write-Info (TF "cli.get_env_at" $ev.url) }
            $val = Prompt-Secret $evLabel
            if ($val) { $extraEnvVars[$ev.name] = $val }
        }
    } else {
        Write-Info "$($selectedBackend.displayName) does not support MCP server configuration."
    }

    Write-Header (T "cli.step4_header")
    $skillNames = $catalog.skills | ForEach-Object { "$(Get-DisplayName $_)  —  $(Get-Description $_)" }
    $skillIdxs = Prompt-MultiChoice (T "cli.select_skills") $skillNames @()
    $selectedSkills = @($skillIdxs | ForEach-Object { $catalog.skills[$_] })

    Write-Header (T "cli.confirm_header")
    Write-Info (TF "cli.backend_label" $selectedBackend.displayName)
    Write-Info (TF "cli.mcp_label"     (if ($selectedMcp.Count) { ($selectedMcp | ForEach-Object { Get-DisplayName $_ }) -join ', ' } else { T "cli.none" }))
    Write-Info (TF "cli.skills_label"  (if ($selectedSkills.Count) { ($selectedSkills | ForEach-Object { Get-DisplayName $_ }) -join ', ' } else { T "cli.none" }))
    Write-Host ""

    if (-not (Confirm-Action (T "cli.confirm_install"))) {
        Write-Warn (T "cli.cancelled")
        return
    }

    Run-Install $selectedBackend $apiKey $extraEnvVars $selectedMcp $selectedSkills
}

function Cmd-Install {
    if (-not $Backend) { Write-Fail (T "cli.missing_backend"); exit 1 }

    $selectedBackend = Get-BackendById $Backend
    if (-not $selectedBackend) {
        Write-Fail (TF "cli.unknown_backend" $Backend)
        exit 1
    }

    $apiKey = $Key
    if ((-not $apiKey) -and (Test-BackendRequiresApiKey $selectedBackend)) {
        $keyLabel = Get-ApiKeyLabel $selectedBackend
        Write-Info "$keyLabel  ($($selectedBackend.apiKeyHint))"
        $apiKey = Prompt-Secret $keyLabel
    } elseif (-not (Test-BackendRequiresApiKey $selectedBackend)) {
        $apiKey = ""
    }

    $selectedMcp = @()
    if ($Mcp -and (Test-BackendSupportsMcp $selectedBackend)) {
        $selectedMcp = @($Mcp -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
            $s = Get-McpById $_
            if (-not $s) { Write-Warn (TF "cli.unknown_mcp" $_) } else { $s }
        } | Where-Object { $_ })
    } elseif ($Mcp) {
        Write-Warn "$($selectedBackend.displayName) does not support MCP server configuration. Ignoring --mcp."
    }

    $selectedSkills = @()
    if ($Skills) {
        $selectedSkills = @($Skills -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
            $s = Get-SkillById $_
            if (-not $s) { Write-Warn (TF "cli.unknown_skill" $_) } else { $s }
        } | Where-Object { $_ })
    }

    $extraEnvVars = @{}
    if (Test-BackendSupportsMcp $selectedBackend) {
        $requiredVars = $selectedMcp | Where-Object { $_.requiredEnvVars } | ForEach-Object { $_.requiredEnvVars }
        foreach ($ev in $requiredVars) {
            $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
            if (-not $existing) {
                $evLabel = if ($global:TIAN_LANG -eq "zh" -and $ev.labelZh) { $ev.labelZh } else { $ev.label }
                Write-Info (TF "cli.required_for" $evLabel)
                $val = Prompt-Secret $evLabel
                if ($val) { $extraEnvVars[$ev.name] = $val }
            }
        }
    }

    Run-Install $selectedBackend $apiKey $extraEnvVars $selectedMcp $selectedSkills
}

function Run-Install($selectedBackend, $apiKey, $extraEnvVars, $selectedMcp, $selectedSkills) {
    Write-Header (T "cli.installing_header")
    Write-Rule

    Write-Info (T "cli.install_step1")
    $ok = Install-Node -LogBox $null -ProgressBar $fakeProgress
    if (-not $ok) { Write-Fail (T "cli.node_fail"); exit 1 }

    Write-Info (TF "cli.install_step2" $selectedBackend.displayName)
    $ok = Install-Backend -Backend $selectedBackend -LogBox $null -ProgressBar $fakeProgress
    if (-not $ok) { Write-Fail (T "cli.backend_fail"); exit 1 }

    Write-Info (T "cli.install_step3")
    Set-ApiKey -Backend $selectedBackend -ApiKey $apiKey -LogBox $null
    foreach ($kvp in $extraEnvVars.GetEnumerator()) {
        Set-ExtraEnvVar -Name $kvp.Key -Value $kvp.Value -LogBox $null
    }

    Write-Info (T "cli.install_step4")
    if (Test-BackendSupportsMcp $selectedBackend) {
        Set-McpServers -Backend $selectedBackend -SelectedServers $selectedMcp -LogBox $null -ProgressBar $fakeProgress
    } else {
        Write-Info "$($selectedBackend.displayName) does not support MCP server configuration. Skipping."
    }

    Write-Info (T "cli.install_step5")
    Install-Skills -SelectedSkills $selectedSkills -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress

    Write-Launcher -Backend $selectedBackend -TianDir $TianDir -LogBox $null

    Write-Rule
    Write-Ok (T "cli.install_ok")
    Write-Host ""
    if ($selectedBackend.cliCommand) {
        Write-Color "  $(T 'cli.verify_tip')" White
        Write-Color "    $(if ($selectedBackend.launchCommand) { $selectedBackend.launchCommand } else { $selectedBackend.cliCommand })" Cyan
    }
    Write-Host ""
}

function Cmd-Status {
    Write-Header (T "cli.status_header")
    Write-Rule

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { Write-Ok "Node.js    $( & node --version 2>&1 )" }
    else        { Write-Fail (T "cli.node_not_found") }

    Write-Host ""
    Write-Color (T "cli.backends_section") Gray
    foreach ($b in $catalog.backends) {
        if (-not $b.cliCommand) { continue }
        $cmd = Get-Command $b.cliCommand -ErrorAction SilentlyContinue
        $name = (Get-DisplayName $b).PadRight(22)
        if ($cmd) { Write-Ok "$name $($b.cliCommand)" }
        else       { Write-Warn "$name $(T 'cli.not_installed')" }
    }

    Write-Host ""
    Write-Color (T "cli.apikeys_section") Gray
    foreach ($b in $catalog.backends) {
        if (-not (Test-BackendRequiresApiKey $b)) { continue }
        $varName = $b.apiKeyEnvVar
        $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
        if ($val) { Write-Ok "$($varName.PadRight(30)) $(T 'cli.key_set')" }
        else       { Write-Warn "$($varName.PadRight(30)) $(T 'cli.key_not_set')" }
    }

    Write-Host ""
    Write-Color (T "cli.mcp_section") Gray
    $targets = $catalog.backends | Where-Object { (Test-BackendSupportsMcp $_) -and $_.mcpConfigTarget } | Select-Object -ExpandProperty mcpConfigTarget -Unique
    foreach ($t in $targets) {
        $fakeBackend = [PSCustomObject]@{ mcpConfigTarget = $t; mcpConfigPath = "" }
        $path = Get-McpConfigPath $fakeBackend
        if (Test-Path $path) { Write-Ok "$t`n     $path" }
        else                  { Write-Warn "$t — $(T 'cli.config_not_found')" }
    }

    Write-Host ""
    $launcherPath = Join-Path $TianDir "launcher.bat"
    if (Test-Path $launcherPath) { Write-Ok (T "cli.launcher_ok") }
    else                          { Write-Warn (T "cli.launcher_missing") }

    Write-Host ""
    Write-Rule
}

function Cmd-List {
    switch ($Subcommand) {
        "backends" {
            Write-Header (T "cli.list_backends")
            Write-Rule
            foreach ($b in $catalog.backends) {
                Write-Color "  $($b.id.PadRight(18))" Cyan -NoNewline
                Write-Color " $(Get-DisplayName $b)" White
                Write-Color "  $(" " * 18) $(Get-Description $b)" Gray
                Write-Host ""
            }
        }
        "mcp" {
            Write-Header (T "cli.list_mcp")
            Write-Rule
            $groups = $catalog.mcpServers | Group-Object { $_.category }
            foreach ($g in $groups) {
                Write-Color "  $(Get-Category $g.Group[0])" Yellow
                foreach ($s in $g.Group) {
                    Write-Color "    $($s.id.PadRight(20))" Cyan -NoNewline
                    Write-Color " $((Get-DisplayName $s).PadRight(20))" White -NoNewline
                    Write-Color " $(Get-Description $s)" Gray
                }
                Write-Host ""
            }
        }
        "skills" {
            Write-Header (T "cli.list_skills")
            Write-Rule
            $groups = $catalog.skills | Group-Object { $_.category }
            foreach ($g in $groups) {
                Write-Color "  $(Get-Category $g.Group[0])" Yellow
                foreach ($s in $g.Group) {
                    Write-Color "    $($s.id.PadRight(24))" Cyan -NoNewline
                    Write-Color " $((Get-DisplayName $s).PadRight(20))" White -NoNewline
                    Write-Color " $(Get-Description $s)" Gray
                }
                Write-Host ""
            }
        }
        default {
            Write-Fail (TF "cli.list_unknown" $Subcommand)
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

function Cmd-Doctor {
    Write-Header "TIAN Doctor — Setup Diagnostics"
    Write-Rule

    $okCount   = 0
    $warnCount = 0
    $failCount = 0

    # ── Runtime ───────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  Runtime" DarkGray

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nodeVer = (& node --version 2>&1).TrimStart('v')
        $major   = [int]($nodeVer -split '\.')[0]
        if ($major -ge 18) {
            Write-Ok "Node.js v$nodeVer"; $okCount++
        } else {
            Write-Warn "Node.js v$nodeVer installed but v18+ required — upgrade at https://nodejs.org"
            $warnCount++
        }
    } else {
        Write-Fail "Node.js not found — install from https://nodejs.org"
        $failCount++
    }

    $npxCmd = Get-Command npx -ErrorAction SilentlyContinue
    if ($npxCmd) { Write-Ok "npx $((& npx --version 2>&1) -join '')"; $okCount++ }
    else          { Write-Warn "npx not found — install Node.js to get it"; $warnCount++ }

    # ── AI Backends ───────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  AI Backends" DarkGray
    foreach ($b in $catalog.backends) {
        if (-not $b.cliCommand) { continue }
        $cmd  = Get-Command $b.cliCommand -ErrorAction SilentlyContinue
        $name = (Get-DisplayName $b).PadRight(24)
        if ($cmd) {
            Write-Ok "$name  $($b.cliCommand)"; $okCount++
        } else {
            $hint = if ($b.npmPackage) { "  (install: npm install -g $($b.npmPackage))" } else { "" }
            Write-Warn "$name not installed$hint"
            $warnCount++
        }
    }

    # ── API Keys ──────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  API Keys" DarkGray
    $seenVars = @{}
    foreach ($b in $catalog.backends) {
        $varName = $b.apiKeyEnvVar
        if (-not $varName -or $seenVars.ContainsKey($varName)) { continue }
        $seenVars[$varName] = $true

        $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
        if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($varName, "Process") }
        $padName = $varName.PadRight(30)

        if (-not $val) {
            Write-Fail "$padName not set — run: tian-cli setup"
            $failCount++
        } else {
            $hint          = if ($b.apiKeyHint) { $b.apiKeyHint } else { "" }
            $prefixMatch   = [regex]::Match($hint, 'sk-\w+')
            $expectedPrefix = if ($prefixMatch.Success) { $prefixMatch.Value } else { "" }

            if ($expectedPrefix -and -not $val.StartsWith($expectedPrefix)) {
                Write-Warn "$padName set but format looks wrong (expected prefix: $expectedPrefix)"
                $warnCount++
            } elseif ($val.Length -lt 20) {
                Write-Warn "$padName set but value seems too short — verify your key"
                $warnCount++
            } else {
                Write-Ok "$padName set ($($val.Length) chars)"
                $okCount++
            }
        }
    }

    # ── MCP Config ────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  MCP Config" DarkGray
    $targets = $catalog.backends |
        Where-Object { (Test-BackendSupportsMcp $_) -and $_.mcpConfigTarget } |
        Select-Object -ExpandProperty mcpConfigTarget -Unique
    foreach ($t in $targets) {
        $fakeBackend = [PSCustomObject]@{ mcpConfigTarget = $t; mcpConfigPath = "" }
        $path = Get-McpConfigPath $fakeBackend
        if (Test-Path $path) {
            try {
                $cfg      = Get-Content $path -Raw | ConvertFrom-Json
                $mcpCount = if ($cfg.mcpServers) {
                    ($cfg.mcpServers | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue).Count
                } else { 0 }
                Write-Ok "$t config valid — $mcpCount server(s) configured"; $okCount++
            } catch {
                Write-Fail "$t config has invalid JSON: $path"; $failCount++
            }
        } else {
            Write-Info "$t config not found (OK if not using $t)"
        }
    }

    # ── Catalog & Launcher ────────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  TIAN Installation" DarkGray
    $catalogPath = Join-Path $TianDir "config\catalog.json"
    if (Test-Path $catalogPath) { Write-Ok "catalog.json found"; $okCount++ }
    else                         { Write-Fail "catalog.json missing — reinstall TIAN"; $failCount++ }

    $launcherPath = Join-Path $TianDir "launcher.bat"
    if (Test-Path $launcherPath) { Write-Ok "launcher.bat present"; $okCount++ }
    else                          { Write-Warn "launcher.bat missing — run: tian-cli repair"; $warnCount++ }

    $tianHome = Join-Path $env:USERPROFILE ".tian"
    if (Test-Path $tianHome) { Write-Ok "~\.tian directory present"; $okCount++ }
    else                      { Write-Info "~\.tian not yet created (created on first job run)" }

    # ── Network Connectivity ──────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  Connectivity" DarkGray
    try {
        $req          = [System.Net.WebRequest]::Create("https://api.anthropic.com")
        $req.Timeout  = 5000
        $req.Method   = "HEAD"
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Ok "Anthropic API reachable"; $okCount++
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            Write-Ok "Anthropic API reachable (HTTP $([int]$_.Exception.Response.StatusCode))"; $okCount++
        } else {
            Write-Warn "Cannot reach api.anthropic.com — check internet / firewall"; $warnCount++
        }
    } catch {
        Write-Warn "Connectivity check failed: $($_.Exception.Message)"; $warnCount++
    }

    # ── Summary ───────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Rule
    Write-Color "  " White -NoNewline
    Write-Color "[ok] $okCount   " Green -NoNewline
    Write-Color "[!!] $warnCount   " Yellow -NoNewline
    Write-Color "[xx] $failCount" Red

    Write-Host ""
    if ($failCount -gt 0) {
        Write-Color "  Fix the errors above, then re-run: tian-cli doctor" Red
    } elseif ($warnCount -gt 0) {
        Write-Color "  Setup mostly OK — review warnings above." Yellow
    } else {
        Write-Color "  All checks passed — you're ready to use TIAN!" Green
    }
    Write-Host ""
}

function Cmd-Update {
    Write-Header "TIAN Update — Upgrade AI Backends"
    Write-Rule

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        Write-Fail "npm not found. Install Node.js first: https://nodejs.org"
        return
    }

    $updated  = 0
    $skipped  = 0
    $failed   = 0

    foreach ($b in $catalog.backends) {
        if (-not $b.npmPackage) {
            if ($b.installType -eq "desktop-app") {
                Write-Info "$($b.displayName.PadRight(26)) desktop app — check for updates in the app itself"
                $skipped++
            } elseif ($b.installType -eq "local-cli") {
                Write-Info "$($b.displayName.PadRight(26)) local install — update manually"
                $skipped++
            }
            continue
        }

        $cmd = Get-Command $b.cliCommand -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Info "$($b.displayName.PadRight(26)) not installed — skipping (run 'tian-cli setup' to install)"
            $skipped++
            continue
        }

        # Capture version before update
        $verBefore = ""
        try { $verBefore = (& $b.cliCommand --version 2>&1) -join "" } catch {}

        Write-Info "Updating $($b.displayName) ($($b.npmPackage))..."

        $result = & npm install -g "$($b.npmPackage)@latest" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $verAfter = ""
            try { $verAfter = (& $b.cliCommand --version 2>&1) -join "" } catch {}

            if ($verBefore -and $verAfter -and ($verBefore.Trim() -ne $verAfter.Trim())) {
                Write-Ok "$($b.displayName.PadRight(26)) $verBefore  →  $verAfter"
            } else {
                Write-Ok "$($b.displayName.PadRight(26)) already up to date ($verAfter)"
            }
            $updated++
        } else {
            Write-Fail "$($b.displayName.PadRight(26)) update failed:"
            $result | Select-Object -Last 5 | ForEach-Object { Write-Color "    $_" DarkGray }
            $failed++
        }
    }

    Write-Host ""
    Write-Rule
    Write-Color "  Updated: $updated   Skipped: $skipped   Failed: $failed" $(if ($failed -gt 0) { "Yellow" } else { "Green" })
    Write-Host ""
}

function Cmd-Repair {
    Write-Header (T "cli.repair_header")
    Write-Info (T "cli.repair_info")
    if (-not (Confirm-Action (T "cli.repair_confirm"))) { return }
    Cmd-Setup
}

function Cmd-Uninstall {
    Write-Header "TIAN Uninstall — Remove Installed Components"
    Write-Rule
    Write-Color "`n  This will remove:" Yellow
    Write-Color "    • npm-installed AI backends (claude, codex, etc.)" White
    Write-Color "    • API keys saved in User environment variables" White
    Write-Color "    • TIAN job data and schedules (~\.tian)" White
    Write-Color "    • TIAN launcher script (launcher.bat)" White
    Write-Color "`n  Note: Node.js itself will NOT be removed.`n" DarkGray

    if (-not (Confirm-Action "Proceed with uninstall?")) {
        Write-Warn "Cancelled."
        return
    }

    $removed = 0
    $skipped = 0

    # ── 1. Uninstall npm-installed backends ───────────────────────────────────
    Write-Host ""
    Write-Color "  AI Backends" DarkGray
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    foreach ($b in $catalog.backends) {
        $name = (Get-DisplayName $b).PadRight(26)
        if (-not $b.npmPackage) {
            Write-Info "$name skipping (not npm-installed)"
            $skipped++
            continue
        }
        $cmd = Get-Command $b.cliCommand -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Info "$name not installed — skipping"
            $skipped++
            continue
        }
        if (-not $npm) {
            Write-Warn "$name npm not found — cannot remove $($b.npmPackage)"
            $skipped++
            continue
        }
        $result = & npm uninstall -g $b.npmPackage 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$name removed ($($b.npmPackage))"
            $removed++
        } else {
            Write-Warn "$name npm uninstall failed — try: npm uninstall -g $($b.npmPackage)"
            $skipped++
        }
    }

    # ── 2. Remove API key environment variables ───────────────────────────────
    Write-Host ""
    Write-Color "  API Keys" DarkGray
    $seenVars = @{}
    foreach ($b in $catalog.backends) {
        $varName = $b.apiKeyEnvVar
        if (-not $varName -or $seenVars.ContainsKey($varName)) { continue }
        $seenVars[$varName] = $true
        $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
        if ($val) {
            [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
            Write-Ok "$($varName.PadRight(30)) removed"
            $removed++
        } else {
            Write-Info "$($varName.PadRight(30)) not set — skipping"
        }
    }

    # ── 3. Remove TIAN MCP entries from config files ──────────────────────────
    Write-Host ""
    Write-Color "  MCP Config" DarkGray
    $targets = $catalog.backends |
        Where-Object { (Test-BackendSupportsMcp $_) -and $_.mcpConfigTarget } |
        Select-Object -ExpandProperty mcpConfigTarget -Unique
    foreach ($t in $targets) {
        $fakeBackend = [PSCustomObject]@{ mcpConfigTarget = $t; mcpConfigPath = "" }
        $path = Get-McpConfigPath $fakeBackend
        if (-not (Test-Path $path)) { Write-Info "$t config not found — skipping"; continue }
        try {
            $cfg = Get-Content $path -Raw | ConvertFrom-Json
            $ht  = ConvertTo-Hashtable $cfg
            $tianKeys = $catalog.mcpServers | Where-Object { $_.configKey } | Select-Object -ExpandProperty configKey
            $countBefore = if ($ht.mcpServers) { $ht.mcpServers.Count } else { 0 }
            foreach ($k in $tianKeys) {
                if ($ht.mcpServers -and $ht.mcpServers.ContainsKey($k)) { $ht.mcpServers.Remove($k) }
            }
            $countAfter = if ($ht.mcpServers) { $ht.mcpServers.Count } else { 0 }
            $ht | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding UTF8
            $delta = $countBefore - $countAfter
            if ($delta -gt 0) {
                Write-Ok "$t — removed $delta MCP server(s) from config"
                $removed++
            } else {
                Write-Info "$t — no TIAN MCP entries found"
            }
        } catch {
            Write-Warn "$t — could not clean config: $($_.Exception.Message)"
        }
    }

    # ── 4. Remove launcher ────────────────────────────────────────────────────
    Write-Host ""
    Write-Color "  Launcher" DarkGray
    $launcherPath = Join-Path $TianDir "launcher.bat"
    if (Test-Path $launcherPath) {
        Remove-Item $launcherPath -Force
        Write-Ok "launcher.bat removed"
        $removed++
    } else {
        Write-Info "launcher.bat not found — skipping"
    }

    # ── 5. Remove ~/.tian data directory ─────────────────────────────────────
    Write-Host ""
    Write-Color "  Job Data" DarkGray
    $tianHome = Join-Path $env:USERPROFILE ".tian"
    if (Test-Path $tianHome) {
        Remove-Item $tianHome -Recurse -Force
        Write-Ok "~\.tian removed"
        $removed++
    } else {
        Write-Info "~\.tian not found — skipping"
    }

    # ── Summary ───────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Rule
    Write-Ok "TIAN components removed.  Removed: $removed   Skipped: $skipped"
    Write-Host ""
    Write-Color "  The TIAN installation folder ($TianDir) was NOT deleted." DarkGray
    Write-Color "  To fully remove it, delete that folder manually." DarkGray
    Write-Host ""
}

# ── Router ────────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "setup"   { Cmd-Setup }
    "install" { Cmd-Install }
    "status"  { Cmd-Status }
    "list"    { Cmd-List }
    "add"     {
        $id = $args[0]
        switch ($Subcommand.ToLower()) {
            "mcp"   {
                $server = Get-McpById $id
                if (-not $server) { Write-Fail (TF "cli.unknown_mcp_id" $id); exit 1 }
                $backendNames = $catalog.backends | ForEach-Object { Get-DisplayName $_ }
                $bIdx = Prompt-Choice (T "cli.add_which_backend") $backendNames 0
                $backend = $catalog.backends[$bIdx]
                if ($server.requiredEnvVars) {
                    foreach ($ev in $server.requiredEnvVars) {
                        $existing = [System.Environment]::GetEnvironmentVariable($ev.name, "User")
                        if (-not $existing) {
                            $evLabel = if ($global:TIAN_LANG -eq "zh" -and $ev.labelZh) { $ev.labelZh } else { $ev.label }
                            Write-Info $evLabel
                            if ($ev.url) { Write-Info (TF "cli.get_env_at" $ev.url) }
                            $val = Prompt-Secret $evLabel
                            if ($val) { Set-ExtraEnvVar -Name $ev.name -Value $val -LogBox $null }
                        }
                    }
                }
                Set-McpServers -Backend $backend -SelectedServers @($server) -LogBox $null -ProgressBar $fakeProgress
                Write-Ok (TF "cli.mcp_added" (Get-DisplayName $server))
            }
            "skill" {
                $skill = Get-SkillById $id
                if (-not $skill) { Write-Fail (TF "cli.unknown_skill_id" $id); exit 1 }
                Install-Skills -SelectedSkills @($skill) -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress
                Write-Ok (TF "cli.skill_installed" (Get-DisplayName $skill))
            }
            default { Write-Fail (T "cli.add_usage") }
        }
    }
    "remove"  {
        $id = $args[0]
        if ($Subcommand.ToLower() -eq "mcp") {
            $server = Get-McpById $id
            if (-not $server) { Write-Fail (TF "cli.unknown_mcp_id" $id); exit 1 }
            $backendNames = $catalog.backends | ForEach-Object { Get-DisplayName $_ }
            $bIdx = Prompt-Choice (T "cli.remove_which_backend") $backendNames 0
            $backend = $catalog.backends[$bIdx]
            $configPath = Get-McpConfigPath $backend
            if (-not (Test-Path $configPath)) { Write-Warn (TF "cli.config_not_found_path" $configPath); exit 1 }
            $ht = ConvertTo-Hashtable (Get-Content $configPath -Raw | ConvertFrom-Json)
            if ($ht.mcpServers -and $ht.mcpServers.ContainsKey($server.configKey)) {
                $ht.mcpServers.Remove($server.configKey)
                $ht | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
                Write-Ok (TF "cli.mcp_removed" (Get-DisplayName $server))
            } else { Write-Warn (TF "cli.mcp_not_configured" (Get-DisplayName $server)) }
        } else { Write-Fail (T "cli.remove_mcp_usage") }
    }
    "doctor"    { Cmd-Doctor }
    "update"    { Cmd-Update }
    "repair"    { Cmd-Repair }
    "uninstall" { Cmd-Uninstall }

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

    "lang" {
        if ($Subcommand -in "en","zh") {
            $global:TIAN_LANG = $Subcommand
            Set-TianLang $Subcommand
            Write-Ok (T "cli.lang_set")
        } else {
            Write-Fail (T "cli.lang_usage")
        }
    }

    { $_ -in "help","--help","-h","" } { Cmd-Help }
    default   { Write-Fail (TF "cli.unknown_cmd" $Command); exit 1 }
}
