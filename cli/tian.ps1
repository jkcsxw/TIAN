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
    [switch]$Watch,
    [string]$File       = "",
    [switch]$Stdin,
    [switch]$Yes,
    [switch]$All,
    [switch]$List,
    [switch]$Fix,
    [switch]$NoKeys,
    [string]$Output     = "",
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
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

function Test-ApiKey {
    param([object]$Backend, [string]$ApiKey)
    if (-not $ApiKey) { return $true }
    $envVar = $Backend.apiKeyEnvVar
    if (-not $envVar) { return $true }

    $headers = @{}
    $url     = ""
    switch -Wildcard ($envVar) {
        "ANTHROPIC_API_KEY" {
            $url     = "https://api.anthropic.com/v1/models"
            $headers = @{ "x-api-key" = $ApiKey; "anthropic-version" = "2023-06-01" }
        }
        "OPENAI_API_KEY" {
            $url     = "https://api.openai.com/v1/models"
            $headers = @{ "Authorization" = "Bearer $ApiKey" }
        }
        default { return $true }
    }

    Write-Info "  Verifying key with API..."
    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Timeout = 6000
        $req.Method  = "GET"
        foreach ($h in $headers.GetEnumerator()) { $req.Headers[$h.Key] = $h.Value }
        $resp = $req.GetResponse(); $resp.Close()
        Write-Ok "  Key accepted by API"
        return $true
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
            switch ($code) {
                401 { Write-Warn "  Key rejected (HTTP 401) — check for typos or regenerate at: $($Backend.apiKeyUrl)"; return $false }
                403 { Write-Warn "  Key forbidden (HTTP 403) — key may lack required permissions"; return $false }
                429 { Write-Info "  Rate limited (HTTP 429) — key looks valid but quota may be exhausted"; return $true }
                default { Write-Info "  API returned HTTP $code — could not verify key"; return $true }
            }
        } else {
            Write-Info "  Could not reach API (no network or timeout) — skipping live check"
            return $true
        }
    } catch {
        Write-Info "  Could not verify key — skipping live check"
        return $true
    }
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
    doctor [--fix]      诊断常见安装问题；--fix 自动修复可修复的问题
    quota               检查所有API密钥的配额和速率限制状态（彩色输出）
    update              将已安装的AI后端更新到最新版本
    uninstall           移除TIAN安装的组件（后端、密钥、数据）
    status              查看当前安装状态
    list backends       列出可用AI后端
    list mcp            列出可用MCP服务器
    list skills         列出可用技能包
    add mcp  <id>       添加MCP服务器到配置
    add skill <id>      安装技能包
    remove mcp  <id>    从配置中移除MCP服务器
    key set [id]        设置或更新API密钥（带实时验证）
    key show            显示所有已设置的API密钥（已掩码）
    key remove <id>     从环境变量中删除API密钥
    repair              重新安装修复当前配置
    lang en|zh          切换界面语言

    run  "提示词"                    立即执行任务（前台）
    run  "提示词" --background       在后台执行任务
    run  "提示词" -w/--watch         后台执行并实时显示输出（auto-exits when done）
    run  "提示词" --file <路径>       将文件内容附加到提示词（如：总结文档）
    run  "提示词" --stdin            将管道输入内容附加到提示词
    jobs                            列出后台任务
    jobs result <id>                查看已完成任务的输出
    jobs tail <id>                  实时追踪任务输出（auto-exits when done; Ctrl+C 停止追踪）
    jobs stop <id>                  停止运行中的任务（--all 停止全部）
    jobs retry <id>                 重新执行已停止或失败的任务（使用原始提示词）
    jobs clear                      清除已完成任务（--all 清除全部）

    schedule add              创建定时任务
    schedule list             列出所有定时任务
    schedule run <名称>        立即运行某个定时任务
    schedule remove <名称>     删除定时任务
    schedule templates        列出内置定时任务模板（早间简报、每周复盘等）
    schedule templates apply <名称>  从模板创建定时任务（--time HH:MM 自定义时间）

    config export             将配置（API密钥、MCP、技能、定时任务）导出到文件
    config import <文件>       在此机器上恢复之前导出的配置

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

    tian-cli config export --output 我的备份.json
    tian-cli config export --no-keys
    tian-cli config import 我的备份.json

"@ White
    } else {
        Write-Color @"

  USAGE
    tian-cli <command> [subcommand] [options]

  COMMANDS
    setup               Interactive guided setup (recommended for first-time users)
    install             Non-interactive install with flags
    doctor [--fix]      Check your setup and diagnose common problems; --fix auto-resolves fixable issues
    quota               Check live quota/rate-limit status for all API keys (colored output)
    update              Upgrade installed AI backends to their latest versions
    uninstall           Remove TIAN's installed components (backends, keys, data)
    status              Show what is currently installed
    list backends       List available AI backends
    list mcp            List available MCP servers
    list skills         List available skills
    add mcp  <id>       Add an MCP server to your config
    add skill <id>      Install a skill
    remove mcp  <id>    Remove an MCP server from your config
    key set [id]        Set or update an API key (with live verification)
    key show            Show all API keys that are currently set (masked)
    key remove <id>     Remove an API key from environment variables
    repair              Re-run install to fix the current config
    lang en|zh          Switch interface language

    run  "prompt"                    Run a task now (foreground)
    run  "prompt" --background       Run a task in the background
    run  "prompt" -w/--watch         Background task with live output streaming (auto-exits when done)
    run  "prompt" --file <path>      Append file content to the prompt (e.g. summarize a document)
    run  "prompt" --stdin            Append piped stdin content to the prompt
    jobs                             List background jobs
    jobs result <id>                 Show output of a completed job
    jobs tail <id>                   Stream a running job's output live (auto-exits when done; Ctrl+C stops watching)
    jobs stop <id>                   Stop a running job (--all stops all)
    jobs retry <id>                  Re-run a quota-stopped or failed job with its original prompt
    jobs clear                       Clear completed jobs (--all clears all)

    schedule add               Create a recurring scheduled task
    schedule list              List all scheduled tasks
    schedule run <name>        Run a scheduled task immediately
    schedule remove <name>     Delete a scheduled task
    schedule templates         List pre-built schedule templates (morning briefing, weekly review, …)
    schedule templates apply <name>  Create a schedule from a template (--time HH:MM to customise)

    config export              Export setup (API keys, MCP configs, skills, schedules) to a file
    config import <file>       Restore a previously exported config on this machine

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
    tian-cli run "Summarise this document" --file report.pdf
    tian-cli run "Review this code for bugs" --file src/main.py --background
    tian-cli jobs
    tian-cli jobs result 20240417-083012-ab12cd

    tian-cli schedule add --name morning-brief --task "Give me a short morning briefing" --time 08:00 --repeat daily
    tian-cli schedule list
    tian-cli schedule run morning-brief
    tian-cli schedule remove morning-brief

    tian-cli config export --output my-tian-backup.json
    tian-cli config export --no-keys
    tian-cli config import my-tian-backup.json

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
        $keyAttempts = 0
        do {
            $apiKey = Prompt-Secret $keyLabel
            $keyAttempts++
            if (-not $apiKey) { break }
            $keyOk = Test-ApiKey $selectedBackend $apiKey
            if (-not $keyOk) {
                if ($keyAttempts -ge 3) {
                    Write-Warn "  3 failed attempts — saving key anyway. Fix later with: tian-cli install --backend $($selectedBackend.id) --key <new-key>"
                    break
                }
                Write-Color "  Try a different key? [Y/n]: " Yellow -NoNewline
                $retry = (Read-Host).Trim()
                if ($retry -imatch '^n') { break }
            }
        } while (-not $keyOk)
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
    if ($apiKey) { Test-ApiKey $selectedBackend $apiKey | Out-Null }

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
            $id = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
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
            $id = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
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
            $id = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
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
    param([switch]$Fix)

    $headerSuffix = if ($Fix) { " (--fix mode)" } else { "" }
    Write-Header "TIAN Doctor — Setup Diagnostics$headerSuffix"
    Write-Rule
    if ($Fix) { Write-Info "Auto-fix enabled — will attempt to resolve fixable issues automatically." }

    $okCount    = 0
    $warnCount  = 0
    $failCount  = 0
    $fixedCount = 0

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
        } elseif ($Fix -and $b.npmPackage -and (Get-Command npm -ErrorAction SilentlyContinue)) {
            Write-Info "  Auto-fixing: installing $($b.displayName) via npm..."
            $npmOut = & npm install -g $b.npmPackage 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "$name — installed successfully"
                $fixedCount++
            } else {
                Write-Warn "$name — npm install failed; run: npm install -g $($b.npmPackage)"
                $warnCount++
            }
        } else {
            $hint = if ($b.npmPackage) { "  (fix: npm install -g $($b.npmPackage))" } else { "" }
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
                $keyOk = Test-ApiKey $b $val
                if ($keyOk) { $okCount++ } else { $warnCount++ }
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

    # ── Network & Service Reachability ───────────────────────────────────────────
    Write-Host ""
    Write-Color "  Network & service reachability" DarkGray

    function Test-HttpReachable([string]$url, [hashtable]$headers = @{}) {
        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Timeout = 5000
            $req.Method  = "GET"
            foreach ($h in $headers.GetEnumerator()) { $req.Headers[$h.Key] = $h.Value }
            $resp = $req.GetResponse(); $resp.Close()
            return 200
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
            return 0
        } catch { return 0 }
    }

    $anthropicCode = Test-HttpReachable "https://api.anthropic.com/v1/models" @{
        "x-api-key"           = "test"
        "anthropic-version"   = "2023-06-01"
    }
    if ($anthropicCode -in 200,401,403,429) { Write-Ok "api.anthropic.com reachable (HTTP $anthropicCode)"; $okCount++ }
    elseif ($anthropicCode -eq 0)           { Write-Warn "Cannot reach api.anthropic.com — check internet / firewall"; $warnCount++ }
    else                                    { Write-Info "api.anthropic.com returned HTTP $anthropicCode" }

    $openaiCode = Test-HttpReachable "https://api.openai.com/v1/models" @{ "Authorization" = "Bearer test" }
    if ($openaiCode -in 200,401,403,429) { Write-Ok "api.openai.com reachable (HTTP $openaiCode)"; $okCount++ }
    elseif ($openaiCode -eq 0)           { Write-Warn "Cannot reach api.openai.com — check internet / firewall"; $warnCount++ }
    else                                 { Write-Info "api.openai.com returned HTTP $openaiCode" }

    # Check whether the Ollama daemon is running (the backend needs it, not just the CLI)
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($ollamaCmd) {
        $ollamaCode = Test-HttpReachable "http://localhost:11434/api/tags"
        if ($ollamaCode -eq 200) {
            Write-Ok "Ollama service is running (localhost:11434)"; $okCount++
            # Check that at least one model has been pulled
            try {
                $tagsJson  = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction Stop
                $modelCount = if ($tagsJson.models) { @($tagsJson.models).Count } else { 0 }
                if ($modelCount -gt 0) {
                    Write-Ok "Ollama: $modelCount model(s) available"; $okCount++
                } else {
                    Write-Warn "Ollama is running but no models are pulled — tasks will fail"
                    Write-Info "  Fix: run 'ollama pull llama3' (or another model name)"
                    if ($Fix) {
                        Write-Info "  Auto-fixing: pulling llama3 (this may take several minutes)..."
                        $pullResult = & ollama pull llama3 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Ok "  llama3 pulled successfully"; $fixedCount++
                        } else {
                            Write-Warn "  'ollama pull llama3' failed — try manually or choose a different model"
                            $warnCount++
                        }
                    } else {
                        $warnCount++
                    }
                }
            } catch {
                Write-Info "  Could not query Ollama model list — skipping model check"
            }
        } elseif ($Fix) {
            Write-Info "  Auto-fixing: starting 'ollama serve' in background..."
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $newOllamaCode = Test-HttpReachable "http://localhost:11434/api/tags"
            if ($newOllamaCode -eq 200) {
                Write-Ok "  Ollama service started successfully"
                $fixedCount++
            } else {
                Write-Warn "  Could not start Ollama automatically; run: ollama serve"
                $warnCount++
            }
        } else {
            Write-Warn "Ollama is installed but the service is NOT running"
            Write-Info "  Fix: run 'ollama serve' in a separate terminal (or start the Ollama app)"
            $warnCount++
        }
    }

    # ── Shell environment & disk space ────────────────────────────────────────────
    Write-Host ""
    Write-Color "  Shell environment & disk space" DarkGray

    # Is tian-cli on PATH?
    $tianBin = Get-Command tian-cli -ErrorAction SilentlyContinue
    if ($tianBin) {
        Write-Ok "tian-cli found on PATH: $($tianBin.Source)"; $okCount++
    } else {
        Write-Warn "tian-cli not found on PATH — open a new terminal or re-run setup"
        $warnCount++
    }

    # Disk space check (warn if < 5 GB free on system drive)
    try {
        $drive     = Split-Path -Qualifier $env:USERPROFILE
        $diskInfo  = Get-PSDrive ($drive.TrimEnd(':')) -ErrorAction Stop
        $freeGB    = [math]::Round($diskInfo.Free / 1GB, 1)
        if ($freeGB -ge 5) {
            Write-Ok "Disk space: $freeGB GB free on $drive"; $okCount++
        } elseif ($freeGB -ge 2) {
            Write-Warn "Disk space: only $freeGB GB free on $drive — Ollama models need ~4 GB+"
            Write-Info "  Free up space or choose a smaller model (e.g. ollama pull phi)"
            $warnCount++
        } else {
            Write-Fail "Disk space: critically low — only $freeGB GB free on $drive"
            Write-Info "  TIAN and AI models need several GB of free space"
            $failCount++
        }
    } catch {
        Write-Info "Could not read disk usage — skipping disk space check"
    }

    # TIAN data directory size (informational)
    $tianHome = Join-Path $env:USERPROFILE ".tian"
    if (Test-Path $tianHome) {
        $tianSizeKB = (Get-ChildItem $tianHome -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1KB
        $tianSizeStr = if ($tianSizeKB -gt 1024) { "$([math]::Round($tianSizeKB/1024,1)) MB" } else { "$([math]::Round($tianSizeKB,0)) KB" }
        Write-Info "TIAN data directory: $tianSizeStr  ($tianHome)"
    }

    # ── Summary ───────────────────────────────────────────────────────────────────
    Write-Host ""
    Write-Rule
    Write-Color "  " White -NoNewline
    Write-Color "[ok] $okCount   " Green -NoNewline
    Write-Color "[!!] $warnCount   " Yellow -NoNewline
    Write-Color "[xx] $failCount" Red

    Write-Host ""
    if ($failCount -eq 0 -and $warnCount -eq 0 -and $fixedCount -eq 0) {
        Write-Color "  All checks passed — you're ready to use TIAN!" Green
    } elseif ($failCount -eq 0 -and $warnCount -eq 0 -and $fixedCount -gt 0) {
        Write-Color "  Fixed $fixedCount issue(s) automatically — you're ready to use TIAN!" Green
    } elseif ($Fix -and $fixedCount -gt 0) {
        Write-Color "  Fixed $fixedCount issue(s) automatically." Green
        if ($failCount -gt 0) {
            Write-Color "  $failCount error(s) remain — fix them above, then re-run: tian-cli doctor" Red
        } elseif ($warnCount -gt 0) {
            Write-Color "  $warnCount warning(s) remain — review above." Yellow
        }
    } else {
        if ($failCount -gt 0) {
            Write-Color "  Fix the errors above, then re-run: tian-cli doctor" Red
        } elseif ($warnCount -gt 0) {
            Write-Color "  Setup mostly OK — review warnings above." Yellow
        }
        if (-not $Fix) {
            Write-Color "  Tip: run 'tian-cli doctor --fix' to auto-resolve fixable issues (npm backends, Ollama)" DarkGray
        }
    }
    Write-Host ""
}

function Cmd-Quota {
    Write-Header "API Quota / Rate-Limit Status"
    Write-Rule

    $seenVars  = @{}
    $toCheck   = [System.Collections.Generic.List[hashtable]]::new()
    $skipped   = [System.Collections.Generic.List[string]]::new()

    foreach ($b in $catalog.backends) {
        $varName = $b.apiKeyEnvVar
        if (-not $varName -or $seenVars.ContainsKey($varName)) { continue }
        $seenVars[$varName] = $true

        $provider = if ($varName -like "*ANTHROPIC*") { "anthropic" }
                    elseif ($varName -like "*OPENAI*")   { "openai" }
                    else                                  { "" }
        if (-not $provider) { continue }

        $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
        if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($varName, "Process") }
        if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($varName) }

        if (-not $val) {
            $skipped.Add("$($b.displayName) ($varName)")
            continue
        }

        $toCheck.Add(@{
            Name     = $b.displayName
            VarName  = $varName
            Key      = $val
            Provider = $provider
            Url      = $b.apiKeyUrl
            Id       = $b.id
        })
    }

    if ($toCheck.Count -eq 0 -and $skipped.Count -gt 0) {
        Write-Warn "No API keys are set. Run: tian-cli key set"
        foreach ($s in $skipped) { Write-Info "$s — not set" }
        Write-Host ""
        return
    }

    $issueCount = 0

    foreach ($entry in $toCheck) {
        $name     = $entry.Name
        $varName  = $entry.VarName
        $key      = $entry.Key
        $provider = $entry.Provider
        $keyUrl   = $entry.Url
        $id       = $entry.Id

        $headers = @{}
        $url     = ""
        switch ($provider) {
            "anthropic" {
                $url     = "https://api.anthropic.com/v1/models"
                $headers = @{ "x-api-key" = $key; "anthropic-version" = "2023-06-01" }
            }
            "openai" {
                $url     = "https://api.openai.com/v1/models"
                $headers = @{ "Authorization" = "Bearer $key" }
            }
        }

        $label = $name.PadRight(32)
        $httpCode  = 0
        $retryAfter = ""
        $bodyText   = ""

        try {
            $req = [System.Net.WebRequest]::Create($url)
            $req.Timeout = 8000
            $req.Method  = "GET"
            foreach ($h in $headers.GetEnumerator()) { $req.Headers[$h.Key] = $h.Value }
            $resp    = $req.GetResponse()
            $httpCode = [int]$resp.StatusCode
            $reader  = [System.IO.StreamReader]::new($resp.GetResponseStream())
            $bodyText = $reader.ReadToEnd()
            $reader.Close(); $resp.Close()
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $httpCode   = [int]$_.Exception.Response.StatusCode
                $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                try {
                    $errStream = $_.Exception.Response.GetResponseStream()
                    $reader    = [System.IO.StreamReader]::new($errStream)
                    $bodyText  = $reader.ReadToEnd()
                    $reader.Close()
                } catch {}
            } else {
                $httpCode = 0
            }
        } catch {
            $httpCode = 0
        }

        switch ($httpCode) {
            200 {
                Write-Ok   "$label OK  — key valid, not rate-limited"
            }
            401 {
                Write-Fail "$label INVALID  — key rejected (HTTP 401)"
                Write-Info "             Fix: tian-cli key set $id  (get a new key at: $keyUrl)"
                $issueCount++
            }
            403 {
                $isBilling = $bodyText -imatch "credit|billing|quota|insufficient"
                if ($isBilling) {
                    Write-Fail "$label QUOTA EXHAUSTED  — billing/credit issue (HTTP 403)"
                    Write-Info "             Fix: add credits at $keyUrl"
                } else {
                    Write-Warn "$label FORBIDDEN  — key lacks permissions (HTTP 403)"
                    Write-Info "             Fix: check key permissions at $keyUrl"
                }
                $issueCount++
            }
            429 {
                if ($retryAfter) {
                    Write-Warn "$label RATE LIMITED  — retry after ${retryAfter}s (HTTP 429)"
                } else {
                    Write-Warn "$label RATE LIMITED  — quota exhausted or too many requests (HTTP 429)"
                    Write-Info "             This may resolve automatically — try again in a few minutes"
                }
                $issueCount++
            }
            0 {
                Write-Warn "$label UNREACHABLE  — network error or DNS failure"
                Write-Info "             Check internet connection or firewall rules"
                $issueCount++
            }
            default {
                Write-Info "$label UNKNOWN  — unexpected HTTP $httpCode"
            }
        }
    }

    Write-Host ""
    foreach ($s in $skipped) { Write-Info "$s — not set, skipping" }

    if ($toCheck.Count -gt 0) {
        Write-Host ""
        if ($issueCount -eq 0) {
            Write-Ok "All $($toCheck.Count) API key(s) are active and within quota limits."
        } else {
            Write-Warn "$issueCount issue(s) found across $($toCheck.Count) key(s). Run: tian-cli doctor"
        }
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

function Cmd-Config-Export {
    $outFile = if ($Output) { $Output } else { "tian-config.json" }

    Write-Header "TIAN Config Export"
    Write-Rule

    if (-not $NoKeys) {
        Write-Warn "This export file will contain your API keys in plaintext."
        Write-Info "Keep it secure. Use --no-keys to omit keys."
        Write-Host ""
    }

    $export = [ordered]@{
        version    = 1
        exportedAt = (Get-Date).ToString("o")
        platform   = "windows"
    }

    # ── API Keys ──────────────────────────────────────────────────────────────
    if (-not $NoKeys) {
        $apiKeys  = @{}
        $seenVars = @{}
        foreach ($b in $catalog.backends) {
            $varName = $b.apiKeyEnvVar
            if (-not $varName -or $seenVars.ContainsKey($varName)) { continue }
            $seenVars[$varName] = $true
            $val = [System.Environment]::GetEnvironmentVariable($varName, "User")
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($varName, "Process") }
            if ($val) { $apiKeys[$varName] = $val }
        }
        $export["apiKeys"] = $apiKeys
        Write-Info "API keys collected: $($apiKeys.Count)"
    }

    # ── MCP Servers ───────────────────────────────────────────────────────────
    $mcpConfigs = @{}
    $seenPaths  = @{}
    foreach ($backend in $catalog.backends) {
        if (-not (Test-BackendSupportsMcp $backend)) { continue }
        $target = $backend.mcpConfigTarget
        if (-not $target) { continue }
        $path = Get-McpConfigPath $backend
        if ($seenPaths.ContainsKey($path) -or -not (Test-Path $path)) { continue }
        $seenPaths[$path] = $true
        try {
            $cfg     = Get-Content $path -Raw | ConvertFrom-Json
            $servers = $cfg.mcpServers
            if ($servers) {
                $ht = ConvertTo-Hashtable $servers
                if ($ht.Count -gt 0) {
                    $mcpConfigs[$target] = $ht
                    Write-Info "MCP: $target — $($ht.Count) server(s) collected"
                }
            }
        } catch {
            Write-Warn "Could not read MCP config at $path — skipping"
        }
    }
    $export["mcpServers"] = $mcpConfigs

    # ── Schedules ─────────────────────────────────────────────────────────────
    $schedules = @()
    try { $schedules = Read-Schedules; if (-not $schedules) { $schedules = @() } } catch {}
    $export["schedules"] = $schedules
    Write-Info "Schedules collected: $(@($schedules).Count)"

    # ── Installed Skills ──────────────────────────────────────────────────────
    $skillsDir      = Join-Path $env:USERPROFILE ".tian\skills"
    $installedSkills = @()
    if (Test-Path $skillsDir) {
        $installedSkills = @(Get-ChildItem $skillsDir -Filter "*.md" | ForEach-Object { $_.BaseName })
    }
    $export["installedSkills"] = $installedSkills
    Write-Info "Skills collected: $($installedSkills.Count)"

    # ── Write output file ─────────────────────────────────────────────────────
    $json = $export | ConvertTo-Json -Depth 10
    Set-Content -Path $outFile -Value $json -Encoding UTF8

    Write-Host ""
    Write-Ok "Config exported to: $outFile"
    Write-Info "Copy this file to the new machine, then run:"
    Write-Info "  tian-cli config import $outFile"
    Write-Host ""
}

function Cmd-Config-Import {
    $inFile = if ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
    if (-not $inFile) {
        Write-Fail "Usage: tian-cli config import <file> [--yes]"
        return
    }
    if (-not (Test-Path $inFile)) {
        Write-Fail "File not found: $inFile"
        return
    }

    Write-Header "TIAN Config Import"
    Write-Rule

    $imported = $null
    try {
        $imported = Get-Content $inFile -Raw | ConvertFrom-Json
    } catch {
        Write-Fail "Invalid JSON in $inFile"
        return
    }

    Write-Info "Importing TIAN config from: $inFile"
    Write-Host ""

    if (-not (Confirm-Action "Proceed?")) {
        Write-Info "Cancelled."
        return
    }
    Write-Host ""

    # ── API Keys ──────────────────────────────────────────────────────────────
    Write-Color "  API Keys" DarkGray
    $keyCount = 0
    if ($imported.apiKeys) {
        $keyProps = $imported.apiKeys | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue
        foreach ($prop in $keyProps) {
            $name = $prop.Name
            $val  = $imported.apiKeys.$name
            if ($name -and $val) {
                [System.Environment]::SetEnvironmentVariable($name, $val, "User")
                [System.Environment]::SetEnvironmentVariable($name, $val, "Process")
                Write-Ok "$name saved to user environment"
                $keyCount++
            }
        }
    }
    if ($keyCount -eq 0) { Write-Info "No API keys in export file" }
    Write-Host ""

    # ── MCP Servers ───────────────────────────────────────────────────────────
    Write-Color "  MCP Servers" DarkGray
    $mcpCount = 0
    if ($imported.mcpServers) {
        $targetProps = $imported.mcpServers | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue
        foreach ($prop in $targetProps) {
            $target     = $prop.Name
            $newServers = $imported.mcpServers.$target
            if (-not $newServers) { continue }

            $known = $catalog.backends | Where-Object { $_.mcpConfigTarget -eq $target } | Select-Object -First 1
            if (-not $known) { Write-Warn "Unknown backend target '$target' — skipping"; continue }

            $fakeBackend = [PSCustomObject]@{ mcpConfigTarget = $target; mcpConfigPath = "" }
            $cfgPath = Get-McpConfigPath $fakeBackend
            $cfgDir  = Split-Path $cfgPath -Parent
            if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }

            $cfg = @{}
            if (Test-Path $cfgPath) {
                try { $cfg = ConvertTo-Hashtable (Get-Content $cfgPath -Raw | ConvertFrom-Json) } catch {}
            }
            if (-not $cfg.ContainsKey("mcpServers")) { $cfg["mcpServers"] = @{} }

            $newHt = ConvertTo-Hashtable $newServers
            foreach ($k in $newHt.Keys) { $cfg["mcpServers"][$k] = $newHt[$k] }
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
            Write-Ok "$target`: $($newHt.Count) MCP server(s) merged into $cfgPath"
            $mcpCount++
        }
    }
    if ($mcpCount -eq 0) { Write-Info "No MCP servers in export file" }
    Write-Host ""

    # ── Skills ────────────────────────────────────────────────────────────────
    Write-Color "  Skills" DarkGray
    $skillCount = 0
    if ($imported.installedSkills) {
        foreach ($skillId in $imported.installedSkills) {
            if (-not $skillId) { continue }
            $skill = Get-SkillById $skillId
            if ($skill) {
                Install-Skills -SelectedSkills @($skill) -TianDir $TianDir -LogBox $null -ProgressBar $fakeProgress
                Write-Ok "Skill '$skillId' installed"
                $skillCount++
            } else {
                Write-Warn "Skill '$skillId' not in catalog — skipping"
            }
        }
    }
    if ($skillCount -eq 0) { Write-Info "No skills in export file" }
    Write-Host ""

    # ── Schedules ─────────────────────────────────────────────────────────────
    Write-Color "  Schedules" DarkGray
    $schedCount = 0
    if ($imported.schedules) {
        foreach ($sched in $imported.schedules) {
            $sName   = $sched.name
            $sPrompt = $sched.prompt
            $sTime   = if ($sched.time)   { $sched.time }   else { "08:00" }
            $sRepeat = if ($sched.repeat) { $sched.repeat } else { "daily" }
            if ($sName -and $sPrompt) {
                Add-Schedule -Name $sName -Prompt $sPrompt -Time $sTime -Repeat $sRepeat -TianDir $TianDir
                $schedCount++
            }
        }
    }
    if ($schedCount -eq 0) { Write-Info "No schedules in export file" }
    Write-Host ""

    Write-Rule
    Write-Ok "Import complete!"
    Write-Info "Open a new terminal so the saved environment variables take effect."
    Write-Host ""
}

function Cmd-Config {
    switch ($Subcommand.ToLower()) {
        "export" { Cmd-Config-Export }
        "import" { Cmd-Config-Import }
        default  {
            Write-Fail "Usage: tian-cli config export [--output <file>] [--no-keys]"
            Write-Fail "       tian-cli config import <file> [--yes]"
        }
    }
}

function Cmd-Key {
    # tian-cli key set [backend-id]
    # tian-cli key show
    # tian-cli key remove <backend-id>
    $sub = $Subcommand.ToLower()

    # Helper: collect all backends that have an API key, de-duplicated by env var
    function Get-KeyBackends {
        $seen = @{}
        $catalog.backends | ForEach-Object {
            $env = $_.apiKeyEnvVar
            if ($env -and -not $seen.ContainsKey($env)) {
                $seen[$env] = $true
                [PSCustomObject]@{
                    Id          = $_.id
                    DisplayName = Get-DisplayName $_
                    EnvVar      = $env
                    KeyUrl      = $_.apiKeyUrl
                    KeyHint     = $_.apiKeyHint
                }
            }
        }
    }

    switch ($sub) {
        "set" {
            $backendId = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
            $backends  = Get-KeyBackends

            if ($backendId) {
                $entry = $backends | Where-Object { $_.Id -eq $backendId } | Select-Object -First 1
                if (-not $entry) {
                    Write-Fail "Unknown backend '$backendId' or it has no API key. Run: tian-cli list backends"
                    exit 1
                }
            } else {
                if (-not $backends) {
                    Write-Fail "No backends with API keys found in catalog."
                    exit 1
                }
                Write-Header "Set API Key"
                Write-Rule
                $names = @($backends | ForEach-Object { "$($_.DisplayName)  ($($_.EnvVar))" })
                $idx   = Prompt-Choice "Which backend do you want to set a key for?" $names 0
                $entry = @($backends)[$idx]
            }

            Write-Header "Set API Key — $($entry.DisplayName)"
            Write-Rule
            if ($entry.KeyUrl)  { Write-Info "Get your key at: $($entry.KeyUrl)" }
            if ($entry.KeyHint) { Write-Info $entry.KeyHint }
            Write-Host ""

            $existing = [System.Environment]::GetEnvironmentVariable($entry.EnvVar, "User")
            if (-not $existing) { $existing = [System.Environment]::GetEnvironmentVariable($entry.EnvVar, "Process") }
            if ($existing) {
                Write-Info "Current value: $($existing.Substring(0, [Math]::Min(8, $existing.Length)))..."
                Write-Host ""
            }

            $apiKey = Prompt-Secret "$($entry.EnvVar) (paste your key)"
            Write-Host ""
            if (-not $apiKey) { Write-Fail "No key entered — aborting."; exit 1 }

            # Determine provider for live verification
            $provider = ""
            if ($entry.EnvVar -match "ANTHROPIC") { $provider = "anthropic" }
            elseif ($entry.EnvVar -match "OPENAI") { $provider = "openai" }

            # Persist: User scope on Windows, shell profile on macOS/Linux
            if ($IsMacOS -or $IsLinux) {
                $profilePath = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bash_profile" }
                $varName     = $entry.EnvVar
                $filtered    = (Get-Content $profilePath -ErrorAction SilentlyContinue) | Where-Object { $_ -notmatch "^export $varName=" }
                ($filtered + "export $varName=`"$($apiKey.Trim())`"") | Set-Content $profilePath -Encoding UTF8
                [System.Environment]::SetEnvironmentVariable($varName, $apiKey.Trim(), "Process")
                Write-Ok "$($entry.EnvVar) saved to $profilePath"
                Write-Info "To activate in this session: . $profilePath"
            } else {
                [System.Environment]::SetEnvironmentVariable($entry.EnvVar, $apiKey.Trim(), "User")
                [System.Environment]::SetEnvironmentVariable($entry.EnvVar, $apiKey.Trim(), "Process")
                Write-Ok "$($entry.EnvVar) saved to User environment variables"
                Write-Info "Open a new terminal for the change to take effect."
            }
            Write-Host ""

            # Live verification (best-effort)
            if ($provider) {
                $b = $catalog.backends | Where-Object { $_.id -eq $entry.Id } | Select-Object -First 1
                if ($b) { Test-ApiKey -Backend $b -ApiKey $apiKey | Out-Null }
            }
            Write-Host ""
        }

        "show" {
            Write-Header "API Keys"
            Write-Rule
            $backends = Get-KeyBackends
            if (-not $backends) { Write-Info "No backends with API keys found in catalog."; return }
            $anySet = $false
            foreach ($entry in $backends) {
                $val = [System.Environment]::GetEnvironmentVariable($entry.EnvVar, "User")
                if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($entry.EnvVar, "Process") }
                $label = "{0,-38}" -f "$($entry.DisplayName) ($($entry.EnvVar))"
                if ($val) {
                    Write-Ok "$label  $($val.Substring(0, [Math]::Min(8, $val.Length)))..."
                    $anySet = $true
                } else {
                    Write-Info "$label  not set"
                }
            }
            if (-not $anySet) {
                Write-Host ""
                Write-Info "No API keys are currently set. Run: tian-cli key set"
            }
            Write-Host ""
        }

        "remove" {
            $backendId = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
            if (-not $backendId) {
                Write-Fail "Usage: tian-cli key remove <backend-id>"
                exit 1
            }
            $backends = Get-KeyBackends
            $entry    = $backends | Where-Object { $_.Id -eq $backendId } | Select-Object -First 1
            if (-not $entry) {
                Write-Fail "Unknown backend '$backendId' or it has no API key. Run: tian-cli list backends"
                exit 1
            }

            if ($IsMacOS -or $IsLinux) {
                $profilePath = if (Test-Path "$env:HOME/.zshrc") { "$env:HOME/.zshrc" } else { "$env:HOME/.bash_profile" }
                $varName     = $entry.EnvVar
                if (Test-Path $profilePath) {
                    $filtered = (Get-Content $profilePath) | Where-Object { $_ -notmatch "^export $varName=" }
                    $filtered | Set-Content $profilePath -Encoding UTF8
                    [System.Environment]::SetEnvironmentVariable($varName, $null, "Process")
                    Write-Ok "$varName removed from $profilePath"
                } else {
                    Write-Info "$varName was not found in profile — nothing to remove"
                }
            } else {
                $current = [System.Environment]::GetEnvironmentVariable($entry.EnvVar, "User")
                if ($current) {
                    [System.Environment]::SetEnvironmentVariable($entry.EnvVar, $null, "User")
                    [System.Environment]::SetEnvironmentVariable($entry.EnvVar, $null, "Process")
                    Write-Ok "$($entry.EnvVar) removed from User environment variables"
                } else {
                    Write-Info "$($entry.EnvVar) was not set — nothing to remove"
                }
            }
            Write-Host ""
        }

        default {
            Write-Host ""
            Write-Color "  Usage:" White
            Write-Info "  tian-cli key set [backend-id]    Set or update an API key (with live verification)"
            Write-Info "  tian-cli key show                Show which API keys are set"
            Write-Info "  tian-cli key remove <backend-id> Remove an API key from environment variables"
            Write-Host ""
            Write-Info "  Example: tian-cli key set claude-code"
            Write-Host ""
        }
    }
}

# ── Router ────────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "setup"   { Cmd-Setup }
    "install" { Cmd-Install }
    "status"  { Cmd-Status }
    "list"    { Cmd-List }
    "add"     {
        $id = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
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
        $id = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }
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
    "config"    { Cmd-Config }
    "key"       { Cmd-Key }
    "doctor"    { Cmd-Doctor -Fix:$Fix }
    "quota"     { Cmd-Quota }
    "update"    { Cmd-Update }
    "repair"    { Cmd-Repair }
    "uninstall" { Cmd-Uninstall }

    "run" {
        # tian-cli run "prompt"  [-b/--background]  [-w/--watch]  [--file path]  [--stdin]
        $prompt = if ($Subcommand) { $Subcommand } elseif ($Task) { $Task } else { "" }
        if (-not $prompt) {
            Write-Fail "Usage: tian-cli run `"your task prompt`" [--background] [--watch] [--file <path>] [--stdin]"
            exit 1
        }

        # Append --file content to prompt
        if ($File) {
            if (-not (Test-Path $File)) {
                Write-Fail "File not found: $File"
                exit 1
            }
            $fileSize = (Get-Item $File).Length
            if ($fileSize -gt 524288) {
                Write-Warn "File is larger than 512 KB ($fileSize bytes). Large files may exceed the AI's context window."
            }
            $fileName  = Split-Path $File -Leaf
            $fileContent = Get-Content $File -Raw -Encoding UTF8
            $prompt = "$prompt`n`n---`nFile: $fileName`n`n$fileContent"
            Write-Info "Appended file content: $File"
        }

        # Append --stdin content to prompt
        if ($Stdin) {
            $stdinContent = $input | Out-String
            if ($stdinContent.Trim()) {
                $prompt = "$prompt`n`n---`nPiped input:`n`n$stdinContent"
                Write-Info "Appended piped stdin content."
            }
        }

        # --watch implies --background (job must be backgrounded to be watched)
        $runBackground = $Background -or $Watch
        Invoke-Task -Prompt $prompt -TianDir $TianDir -Background:$runBackground -Watch:$Watch
    }

    "jobs" {
        switch ($Subcommand.ToLower()) {
            "result" {
                $jobId = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $jobId) { Write-Fail "Usage: tian-cli jobs result <job-id>"; exit 1 }
                Show-JobResult -JobId $jobId
            }
            "tail"   {
                $jobId = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $jobId) { Write-Fail "Usage: tian-cli jobs tail <job-id>"; exit 1 }
                $meta = Get-JobStatus -JobId $jobId
                if (-not $meta) { Write-Fail "Job '$jobId' not found."; exit 1 }
                if ($meta.status -ne "running") {
                    Write-Info "Job $jobId status: $($meta.status) — showing stored output."
                    Show-JobResult -JobId $jobId
                } else {
                    Write-Info "Job $jobId is still running — streaming output (auto-exits when finished; Ctrl+C to stop watching)..."
                    Watch-Job -JobId $jobId
                }
            }
            "stop"   {
                $jobId = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $All -and -not $jobId) { Write-Fail "Usage: tian-cli jobs stop <job-id> [--all]"; exit 1 }
                Stop-Jobs -JobId $jobId -All:$All
            }
            "retry"  {
                $jobId = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $jobId) { Write-Fail "Usage: tian-cli jobs retry <job-id>"; exit 1 }
                Retry-Job -JobId $jobId -TianDir $TianDir
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
                $scheduleName = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $scheduleName) { Write-Fail "Usage: tian-cli schedule run <name>"; exit 1 }
                Invoke-ScheduleNow -Name $scheduleName -TianDir $TianDir
            }
            "remove" {
                $scheduleName = if ($Name) { $Name } elseif ($RemainingArgs.Count -gt 0) { [string]$RemainingArgs[0] } else { "" }
                if (-not $scheduleName) { Write-Fail "Usage: tian-cli schedule remove --name <name>"; exit 1 }
                Remove-Schedule -Name $scheduleName -TianDir $TianDir
            }
            "templates" {
                # Built-in template library: name, defaultTime, repeat, day, description, prompt
                $schedTemplates = @(
                    [ordered]@{
                        Name="morning-briefing"; Time="08:00"; Repeat="daily"; Day="MON"
                        Desc="Morning priority check"
                        Prompt="Start my day well: suggest exactly 3 clear priorities for me to focus on today, note any recurring commitments I should not forget, and add a one-line motivational nudge to help me get started with energy."
                    },
                    [ordered]@{
                        Name="evening-digest"; Time="18:00"; Repeat="daily"; Day="MON"
                        Desc="End-of-day wrap-up"
                        Prompt="Give me a concise end-of-day reflection template: what I likely accomplished today, what should carry over to tomorrow, and one concrete thing I can improve tomorrow. Keep it brief and action-oriented."
                    },
                    [ordered]@{
                        Name="weekly-review"; Time="17:00"; Repeat="weekly"; Day="FRI"
                        Desc="Weekly retrospective"
                        Prompt="Create a structured weekly review for me: celebrate this week's wins, list any unfinished tasks to roll into next week, share one lesson worth remembering, and suggest my top 3 priorities for next week."
                    },
                    [ordered]@{
                        Name="inbox-triage"; Time="09:00"; Repeat="daily"; Day="MON"
                        Desc="Email inbox triage guide"
                        Prompt="Walk me through email triage. Sort messages into four buckets — Act Now (urgent reply needed today), Schedule (respond within 48 hours), Delegate (forward to someone else), Archive (no action needed) — and give me a one-line template reply for each bucket."
                    },
                    [ordered]@{
                        Name="meeting-prep"; Time="08:30"; Repeat="daily"; Day="MON"
                        Desc="Daily meeting preparation"
                        Prompt="Help me prepare for any meetings today. Suggest 5 sharp questions I could ask in a typical team meeting, a 3-step pre-meeting checklist (agenda, materials, goal), and one tip for keeping meetings on time."
                    },
                    [ordered]@{
                        Name="focus-reset"; Time="14:00"; Repeat="daily"; Day="MON"
                        Desc="Afternoon focus reset"
                        Prompt="It is early afternoon — help me reset. Remind me to review this morning's priorities, assess which are done versus still open, then recommend: should I push through current tasks or reprioritise for the remaining hours of the day?"
                    }
                )

                $templateSub = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0].ToLower() } else { "list" }
                switch ($templateSub) {
                    { $_ -in "list","" } {
                        Write-Header "Schedule Templates"
                        Write-Rule
                        Write-Host ""
                        $fmt = "  {0,-22} {1,-10} {2,-14} {3}"
                        Write-Color ($fmt -f "NAME","TIME","REPEAT","DESCRIPTION") DarkGray
                        Write-Color ("  " + ("─" * 74)) DarkGray
                        foreach ($t in $schedTemplates) {
                            $repeatLabel = if ($t.Repeat -eq "weekly") { "weekly($($t.Day))" } else { $t.Repeat }
                            Write-Color ($fmt -f $t.Name, $t.Time, $repeatLabel, $t.Desc) White
                        }
                        Write-Host ""
                        Write-Color "  Apply a template:   tian-cli schedule templates apply <name>" DarkGray
                        Write-Color "  Custom time:        tian-cli schedule templates apply <name> --time HH:MM" DarkGray
                        Write-Host ""
                    }
                    "apply" {
                        $tName = if ($RemainingArgs.Count -gt 1) { $RemainingArgs[1] } else { "" }
                        if (-not $tName) { Write-Fail "Usage: tian-cli schedule templates apply <name> [--time HH:MM]"; exit 1 }
                        $tmpl = $schedTemplates | Where-Object { $_.Name -eq $tName } | Select-Object -First 1
                        if (-not $tmpl) {
                            Write-Fail "Template '$tName' not found. Run: tian-cli schedule templates"
                            exit 1
                        }
                        $applyTime = if ($Time) { $Time } else { $tmpl.Time }

                        # Check for existing schedule with same name
                        $schedulesPath = Join-Path $env:USERPROFILE ".tian\schedules.json"
                        if (Test-Path $schedulesPath) {
                            $existingSchedules = Get-Content $schedulesPath -Raw | ConvertFrom-Json
                            if ($existingSchedules | Where-Object { $_.name -eq $tName }) {
                                Write-Fail "A schedule named '$tName' already exists. Remove it first: tian-cli schedule remove $tName"
                                exit 1
                            }
                        }

                        Write-Info "Applying template: $($tmpl.Desc)"
                        Write-Info "  Prompt: $($tmpl.Prompt.Substring(0, [Math]::Min(72, $tmpl.Prompt.Length)))..."
                        Write-Host ""
                        Add-Schedule -Name $tName -Prompt $tmpl.Prompt -Time $applyTime -Repeat $tmpl.Repeat -DayOfWeek $tmpl.Day -TianDir $TianDir
                    }
                    default { Write-Fail "Usage: tian-cli schedule templates [list|apply <name>]" }
                }
            }
            default  { Write-Fail "Usage: tian-cli schedule add|list|run|remove|templates" }
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
