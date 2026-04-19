# Centralised UI strings — English (default) and Chinese
# Usage:  T "key"   returns the string for the active language

$global:TIAN_STRINGS = @{
    en = @{
        # ── App shell ─────────────────────────────────────────────────────────
        "app.title"               = "Tian Setup — Talk Is All you Need"
        "app.step_of"             = "Step {0} of {1}"
        "app.lang_btn"            = "中文"          # button label shown when UI is in English

        # ── Buttons (shared) ─────────────────────────────────────────────────
        "btn.back"                = "Back"
        "btn.next"                = "Next"
        "btn.get_started"         = "Get Started"
        "btn.install_now"         = "Install Now"
        "btn.close"               = "Close"
        "btn.launch"              = "Launch Now"
        "btn.open_folder"         = "Open Folder"
        "btn.show_key"            = "Show"
        "btn.open_website"        = "Open website to get my key"
        "btn.get_key_link"        = "Get API key"

        # ── Welcome ───────────────────────────────────────────────────────────
        "welcome.title"           = "Welcome to Tian"
        "welcome.tagline"         = "Talk Is All you Need"
        "welcome.desc"            = "This wizard will set up a powerful AI assistant on your computer.`n`nNo coding knowledge required. Just follow the steps, and you will be chatting with AI in minutes."
        "welcome.what_installed"  = "What will be installed:"
        "welcome.item1"           = "  Your chosen AI assistant (Claude, Codex, or others)"
        "welcome.item2"           = "  Tools that let your AI access files, the web, and more"
        "welcome.item3"           = "  Skill presets for your daily use or business"
        "welcome.est_time"        = "Estimated time: 3-10 minutes depending on your internet speed."

        # ── Backend ───────────────────────────────────────────────────────────
        "backend.title"           = "Choose Your AI Assistant"
        "backend.subtitle"        = "Select the AI you want to use. You can change this later by re-running setup."

        # ── API Key ───────────────────────────────────────────────────────────
        "apikey.title"            = "Connect to Your AI Account"
        "apikey.subtitle"         = "Think of an API key like a password that lets TIAN talk to your AI. You only need to do this once."
        "apikey.guide_title"      = "How to get your key (takes about 2 minutes):"
        "apikey.step1"            = "1.  Click the blue button below — it opens the website in your browser"
        "apikey.step2"            = "2.  Sign up for a free account (or log in if you already have one)"
        "apikey.step3"            = "3.  Click 'Create Key', then copy the key shown on screen"
        "apikey.step4"            = "4.  Come back here and paste it into the box below"
        "apikey.or_paste"         = "— then paste it below —"
        "apikey.privacy"          = "Your key is saved only on this computer. It is never sent anywhere else."
        "apikey.error_empty"      = "Please paste your API key into the box above."
        "apikey.get_here"         = "Get it here"

        # ── MCP Servers ───────────────────────────────────────────────────────
        "mcp.title"               = "Choose AI Tools (MCP Servers)"
        "mcp.subtitle"            = "These tools extend your AI. Select what you need — you can always add more later."

        # ── Skills ────────────────────────────────────────────────────────────
        "skills.title"            = "Choose Skills"
        "skills.subtitle"         = "Skills are pre-built prompts that help your AI with specific tasks. Pick what fits your needs."
        "skills.skip_note"        = "You can skip all skills and install them later."

        # ── Install ───────────────────────────────────────────────────────────
        "install.title"           = "Installing..."
        "install.subtitle"        = "Please wait while Tian sets everything up. This may take a few minutes."
        "install.preparing"       = "Preparing..."
        "install.step1"           = "Step 1/5: Checking Node.js..."
        "install.step2"           = "Step 2/5: Installing {0}..."
        "install.step3"           = "Step 3/5: Saving API key..."
        "install.step4"           = "Step 4/5: Configuring MCP tools..."
        "install.step5"           = "Step 5/5: Installing skills..."
        "install.complete"        = "Installation complete!"
        "install.all_done"        = "=== All done! ==="
        "install.error"           = "Installation encountered an error."

        # ── Done ─────────────────────────────────────────────────────────────
        "done.title_ok"           = "You're all set!"
        "done.msg_ok"             = "Your AI assistant is ready. Here's a summary of what was installed:"
        "done.title_err"          = "Setup completed with errors"
        "done.msg_err"            = "Some items may not have installed correctly. You can re-run setup.bat to try again."
        "done.summary_backend"    = "AI Backend:  {0}"
        "done.summary_mcp"        = "MCP Tools:   {0}"
        "done.summary_skills"     = "Skills:      {0}"
        "done.next_title"         = "What to do next:"
        "done.tip1"               = "1. Click 'Launch Now' below to start chatting"
        "done.tip2"               = "2. You can also double-click launcher.bat any time"
        "done.tip3"               = "3. Re-run setup.bat to add more tools or skills"

        # ── CLI ───────────────────────────────────────────────────────────────
        "cli.tagline"             = "Talk Is All you Need"
        "cli.setup_header"        = "TIAN Interactive Setup"
        "cli.step1_header"        = "Step 1 — Choose your AI backend"
        "cli.step2_header"        = "Step 2 — Enter your API key"
        "cli.step3_header"        = "Step 3 — Choose MCP tools"
        "cli.step4_header"        = "Step 4 — Choose skills"
        "cli.confirm_header"      = "Ready to install"
        "cli.select_backend"      = "Select backend"
        "cli.select_mcp"          = "Select MCP tools"
        "cli.select_skills"       = "Select skills"
        "cli.selected"            = "Selected: {0}"
        "cli.get_at"              = "Get one at: {0}"
        "cli.get_env_at"          = "Get it at: {0}"
        "cli.backend_label"       = "Backend : {0}"
        "cli.mcp_label"           = "MCP     : {0}"
        "cli.skills_label"        = "Skills  : {0}"
        "cli.none"                = "none"
        "cli.confirm_install"     = "Proceed with installation?"
        "cli.cancelled"           = "Setup cancelled."
        "cli.installing_header"   = "Installing"
        "cli.install_step1"       = "Step 1/5  Checking Node.js..."
        "cli.install_step2"       = "Step 2/5  Installing {0}..."
        "cli.install_step3"       = "Step 3/5  Saving API key..."
        "cli.install_step4"       = "Step 4/5  Configuring MCP servers..."
        "cli.install_step5"       = "Step 5/5  Installing skills..."
        "cli.install_ok"          = "Installation complete!"
        "cli.verify_tip"          = "Run 'tian-cli status' to verify, then launch with:"
        "cli.node_fail"           = "Node.js installation failed. Aborting."
        "cli.backend_fail"        = "Backend installation failed. Aborting."
        "cli.missing_backend"     = "Missing --backend. Run 'tian-cli help' for usage."
        "cli.unknown_backend"     = "Unknown backend '{0}'. Run 'tian-cli list backends' to see options."
        "cli.unknown_mcp"         = "Unknown MCP id '{0}' — skipping."
        "cli.unknown_skill"       = "Unknown skill id '{0}' — skipping."
        "cli.required_for"        = "Required for {0}:"
        "cli.repair_header"       = "TIAN Repair"
        "cli.repair_info"         = "This will re-run the install for your current config."
        "cli.repair_confirm"      = "Continue?"
        "cli.status_header"       = "TIAN Status"
        "cli.node_not_found"      = "Node.js    not found"
        "cli.backends_section"    = "  AI Backends:"
        "cli.not_installed"       = "not installed"
        "cli.apikeys_section"     = "  API Keys:"
        "cli.key_set"             = "set"
        "cli.key_not_set"         = "not set"
        "cli.mcp_section"         = "  MCP Config Files:"
        "cli.config_not_found"    = "config not found"
        "cli.launcher_ok"         = "launcher.bat exists"
        "cli.launcher_missing"    = "launcher.bat not found — run setup first"
        "cli.list_backends"       = "Available AI Backends"
        "cli.list_mcp"            = "Available MCP Servers"
        "cli.list_skills"         = "Available Skills"
        "cli.list_unknown"        = "Unknown list target '{0}'. Try: backends, mcp, skills"
        "cli.unknown_cmd"         = "Unknown command '{0}'. Run 'tian-cli help'."
        "cli.lang_set"            = "Language set. Restart tian-cli to apply."
        "cli.lang_usage"          = "Usage: tian-cli lang en|zh"
        "cli.add_usage"           = "Usage: tian-cli add mcp <id>  |  tian-cli add skill <id>"
        "cli.remove_mcp_usage"    = "Usage: tian-cli remove mcp <id>"
        "cli.unknown_mcp_id"      = "Unknown MCP id '{0}'. Run 'tian-cli list mcp'."
        "cli.unknown_skill_id"    = "Unknown skill id '{0}'. Run 'tian-cli list skills'."
        "cli.add_which_backend"   = "Which backend to add this to?"
        "cli.remove_which_backend" = "Which backend to remove this from?"
        "cli.config_not_found_path" = "Config not found: {0}"
        "cli.mcp_added"           = "{0} added."
        "cli.skill_installed"     = "{0} installed."
        "cli.mcp_removed"         = "{0} removed."
        "cli.mcp_not_configured"  = "{0} was not configured."

        # ── Runner ────────────────────────────────────────────────────────────
        "runner.no_backend"       = "No AI backend found on PATH. Run 'tian-cli setup' first."
        "runner.no_flag"          = "{0} does not support non-interactive task execution."
        "runner.started_bg"       = "Task started in background."
        "runner.job_id"           = "Job ID : {0}"
        "runner.check_result"     = "Check result with:  tian-cli jobs result {0}"
        "runner.running"          = "Running task with {0}..."
        "runner.no_jobs"          = "No jobs found. Run a task with: tian-cli run `"your task`""
        "runner.jobs_header"      = "Background Jobs (last {0})"
        "runner.read_output"      = "tian-cli jobs result <job-id>   to read output"
        "runner.job_header"       = "Job: {0}"
        "runner.status"           = "Status  : {0}"
        "runner.backend"          = "Backend : {0}"
        "runner.created"          = "Created : {0}"
        "runner.finished"         = "Finished: {0}"
        "runner.prompt"           = "Prompt  : {0}"
        "runner.still_running"    = "Task is still running. Check again in a moment."
        "runner.no_output"        = "Output file not found."
        "runner.all_cleared"      = "All jobs cleared."
        "runner.cleared_n"        = "Cleared {0} completed job(s). {1} running job(s) kept."

        # ── Scheduler ─────────────────────────────────────────────────────────
        "sched.missing_name"      = "Missing schedule name. Use --name <name>"
        "sched.missing_task"      = "Missing task prompt. Use --task `"your prompt`""
        "sched.already_exists"    = "A schedule named '{0}' already exists. Remove it first with: tian-cli schedule remove {0}"
        "sched.win_fail"          = "Failed to create Windows scheduled task (exit {0})."
        "sched.win_admin"         = "Try running tian-cli as Administrator."
        "sched.launchd_ok"        = "Schedule '{0}' registered with launchd."
        "sched.created"           = "Schedule '{0}' created — {1} at {2}."
        "sched.results_tip"       = "Results : tian-cli jobs  (after first run)"
        "sched.remove_usage"      = "Usage: tian-cli schedule remove <name>"
        "sched.not_found"         = "No schedule named '{0}'."
        "sched.win_remove_fail"   = "Could not remove Windows task (may have already been deleted)."
        "sched.removed"           = "Schedule '{0}' removed."
        "sched.none"              = "No schedules found. Create one with: tian-cli schedule add --name <n> --task `"prompt`" --time 08:00"
        "sched.header"            = "Scheduled Tasks"
        "sched.run_tip"           = "tian-cli schedule run <name>     run immediately"
        "sched.remove_tip"        = "tian-cli schedule remove <name>  delete schedule"
        "sched.run_usage"         = "Usage: tian-cli schedule run <name>"
        "sched.running_now"       = "Running scheduled task '{0}' now..."
    }

    zh = @{
        # ── App shell ─────────────────────────────────────────────────────────
        "app.title"               = "天 安装向导 — 会说话，就会用AI"
        "app.step_of"             = "第 {0} / {1} 步"
        "app.lang_btn"            = "EN"             # button label shown when UI is in Chinese

        # ── Buttons (shared) ─────────────────────────────────────────────────
        "btn.back"                = "返回"
        "btn.next"                = "下一步"
        "btn.get_started"         = "开始安装"
        "btn.install_now"         = "立即安装"
        "btn.close"               = "关闭"
        "btn.launch"              = "立即启动"
        "btn.open_folder"         = "打开文件夹"
        "btn.show_key"            = "显示"
        "btn.open_website"        = "打开网站获取密钥"
        "btn.get_key_link"        = "获取API密钥"

        # ── Welcome ───────────────────────────────────────────────────────────
        "welcome.title"           = "欢迎使用「天」"
        "welcome.tagline"         = "会说话，就会用AI"
        "welcome.desc"            = "本向导将在您的电脑上配置一个强大的AI助手。`n`n无需编程知识，按步骤操作，几分钟内即可开始与AI对话。"
        "welcome.what_installed"  = "将会安装以下内容："
        "welcome.item1"           = "  您选择的AI助手（Claude、Codex 等）"
        "welcome.item2"           = "  让AI访问文件、搜索网络等功能的工具"
        "welcome.item3"           = "  适合日常工作或业务的技能包"
        "welcome.est_time"        = "预计用时：3-10 分钟（取决于网速）"

        # ── Backend ───────────────────────────────────────────────────────────
        "backend.title"           = "选择您的AI助手"
        "backend.subtitle"        = "选择您想使用的AI，之后可重新运行安装程序更改。"

        # ── API Key ───────────────────────────────────────────────────────────
        "apikey.title"            = "连接您的AI账户"
        "apikey.subtitle"         = "API密钥相当于让「天」代您与AI通信的专属密码，只需设置一次。"
        "apikey.guide_title"      = "如何获取密钥（约2分钟）："
        "apikey.step1"            = "1.  点击下方蓝色按钮，浏览器将自动打开对应网站"
        "apikey.step2"            = "2.  注册免费账户（或直接登录已有账户）"
        "apikey.step3"            = "3.  点击「创建密钥」，复制页面上显示的密钥"
        "apikey.step4"            = "4.  回到此处，将密钥粘贴到下方输入框"
        "apikey.or_paste"         = "— 然后粘贴到下方 —"
        "apikey.privacy"          = "密钥仅保存在本机，不会发送到其他任何地方。"
        "apikey.error_empty"      = "请将API密钥粘贴到上方输入框中。"
        "apikey.get_here"         = "点击获取"

        # ── MCP Servers ───────────────────────────────────────────────────────
        "mcp.title"               = "选择AI工具（MCP服务器）"
        "mcp.subtitle"            = "这些工具可扩展AI的能力，按需选择，之后随时可以添加更多。"

        # ── Skills ────────────────────────────────────────────────────────────
        "skills.title"            = "选择技能包"
        "skills.subtitle"         = "技能包是预置的提示词，帮助AI更好地处理特定任务，按需选择即可。"
        "skills.skip_note"        = "可跳过全部技能包，之后随时安装。"

        # ── Install ───────────────────────────────────────────────────────────
        "install.title"           = "安装中..."
        "install.subtitle"        = "请稍候，「天」正在为您配置一切，可能需要几分钟。"
        "install.preparing"       = "准备中..."
        "install.step1"           = "第1步/共5步：检查 Node.js..."
        "install.step2"           = "第2步/共5步：安装 {0}..."
        "install.step3"           = "第3步/共5步：保存API密钥..."
        "install.step4"           = "第4步/共5步：配置MCP工具..."
        "install.step5"           = "第5步/共5步：安装技能包..."
        "install.complete"        = "安装完成！"
        "install.all_done"        = "=== 全部完成！==="
        "install.error"           = "安装过程中出现错误。"

        # ── Done ─────────────────────────────────────────────────────────────
        "done.title_ok"           = "已全部就绪！"
        "done.msg_ok"             = "您的AI助手已配置完毕，以下是本次安装的摘要："
        "done.title_err"          = "安装完成（含错误）"
        "done.msg_err"            = "部分内容可能未能正确安装，您可以重新运行 setup.bat 再试一次。"
        "done.summary_backend"    = "AI助手：  {0}"
        "done.summary_mcp"        = "AI工具：  {0}"
        "done.summary_skills"     = "技能包：  {0}"
        "done.next_title"         = "接下来怎么做："
        "done.tip1"               = "1. 点击下方「立即启动」开始与AI对话"
        "done.tip2"               = "2. 以后也可以双击 launcher.bat 随时启动"
        "done.tip3"               = "3. 重新运行 setup.bat 可添加更多工具或技能包"

        # ── CLI ───────────────────────────────────────────────────────────────
        "cli.tagline"             = "会说话，就会用AI"
        "cli.setup_header"        = "天 交互式安装"
        "cli.step1_header"        = "第1步 — 选择AI后端"
        "cli.step2_header"        = "第2步 — 输入API密钥"
        "cli.step3_header"        = "第3步 — 选择MCP工具"
        "cli.step4_header"        = "第4步 — 选择技能包"
        "cli.confirm_header"      = "准备安装"
        "cli.select_backend"      = "选择后端"
        "cli.select_mcp"          = "选择MCP工具"
        "cli.select_skills"       = "选择技能包"
        "cli.selected"            = "已选择：{0}"
        "cli.get_at"              = "获取地址：{0}"
        "cli.get_env_at"          = "获取地址：{0}"
        "cli.backend_label"       = "AI后端  : {0}"
        "cli.mcp_label"           = "MCP工具 : {0}"
        "cli.skills_label"        = "技能包  : {0}"
        "cli.none"                = "无"
        "cli.confirm_install"     = "确认安装？"
        "cli.cancelled"           = "已取消安装。"
        "cli.installing_header"   = "安装中"
        "cli.install_step1"       = "第1步/共5步  检查 Node.js..."
        "cli.install_step2"       = "第2步/共5步  安装 {0}..."
        "cli.install_step3"       = "第3步/共5步  保存API密钥..."
        "cli.install_step4"       = "第4步/共5步  配置MCP服务器..."
        "cli.install_step5"       = "第5步/共5步  安装技能包..."
        "cli.install_ok"          = "安装完成！"
        "cli.verify_tip"          = "运行 'tian-cli status' 验证安装，然后使用以下命令启动："
        "cli.node_fail"           = "Node.js 安装失败，已中止。"
        "cli.backend_fail"        = "AI后端安装失败，已中止。"
        "cli.missing_backend"     = "缺少 --backend 参数。请运行 'tian-cli help' 查看用法。"
        "cli.unknown_backend"     = "未知后端 '{0}'。请运行 'tian-cli list backends' 查看可用选项。"
        "cli.unknown_mcp"         = "未知MCP ID '{0}'，已跳过。"
        "cli.unknown_skill"       = "未知技能包ID '{0}'，已跳过。"
        "cli.required_for"        = "需要提供 {0}："
        "cli.repair_header"       = "天 修复安装"
        "cli.repair_info"         = "将重新运行安装程序修复当前配置。"
        "cli.repair_confirm"      = "继续？"
        "cli.status_header"       = "天 安装状态"
        "cli.node_not_found"      = "Node.js    未找到"
        "cli.backends_section"    = "  AI后端："
        "cli.not_installed"       = "未安装"
        "cli.apikeys_section"     = "  API密钥："
        "cli.key_set"             = "已设置"
        "cli.key_not_set"         = "未设置"
        "cli.mcp_section"         = "  MCP配置文件："
        "cli.config_not_found"    = "配置未找到"
        "cli.launcher_ok"         = "launcher.bat 存在"
        "cli.launcher_missing"    = "launcher.bat 未找到，请先运行安装程序"
        "cli.list_backends"       = "可用AI后端"
        "cli.list_mcp"            = "可用MCP服务器"
        "cli.list_skills"         = "可用技能包"
        "cli.list_unknown"        = "未知的列出目标 '{0}'。请使用：backends, mcp, skills"
        "cli.unknown_cmd"         = "未知命令 '{0}'。请运行 'tian-cli help' 查看帮助。"
        "cli.lang_set"            = "语言已切换。重启 tian-cli 后生效。"
        "cli.lang_usage"          = "用法：tian-cli lang en|zh"
        "cli.add_usage"           = "用法：tian-cli add mcp <id>  |  tian-cli add skill <id>"
        "cli.remove_mcp_usage"    = "用法：tian-cli remove mcp <id>"
        "cli.unknown_mcp_id"      = "未知MCP ID '{0}'。请运行 'tian-cli list mcp' 查看可用项。"
        "cli.unknown_skill_id"    = "未知技能包ID '{0}'。请运行 'tian-cli list skills' 查看可用项。"
        "cli.add_which_backend"   = "要添加到哪个AI后端？"
        "cli.remove_which_backend" = "要从哪个AI后端移除？"
        "cli.config_not_found_path" = "配置文件未找到：{0}"
        "cli.mcp_added"           = "{0} 已添加。"
        "cli.skill_installed"     = "{0} 已安装。"
        "cli.mcp_removed"         = "{0} 已移除。"
        "cli.mcp_not_configured"  = "{0} 不在配置中。"

        # ── Runner ────────────────────────────────────────────────────────────
        "runner.no_backend"       = "未在系统中找到AI后端，请先运行 'tian-cli setup'。"
        "runner.no_flag"          = "{0} 不支持非交互式任务执行。"
        "runner.started_bg"       = "任务已在后台启动。"
        "runner.job_id"           = "任务ID : {0}"
        "runner.check_result"     = "查看结果：tian-cli jobs result {0}"
        "runner.running"          = "正在使用 {0} 执行任务..."
        "runner.no_jobs"          = "暂无任务记录。运行任务：tian-cli run `"您的任务提示词`""
        "runner.jobs_header"      = "后台任务（最近 {0} 条）"
        "runner.read_output"      = "tian-cli jobs result <任务ID>   查看输出"
        "runner.job_header"       = "任务：{0}"
        "runner.status"           = "状态     : {0}"
        "runner.backend"          = "后端     : {0}"
        "runner.created"          = "创建时间 : {0}"
        "runner.finished"         = "完成时间 : {0}"
        "runner.prompt"           = "提示词   : {0}"
        "runner.still_running"    = "任务仍在执行中，请稍后再查看。"
        "runner.no_output"        = "输出文件未找到。"
        "runner.all_cleared"      = "所有任务已清除。"
        "runner.cleared_n"        = "已清除 {0} 条已完成任务，保留 {1} 条运行中任务。"

        # ── Scheduler ─────────────────────────────────────────────────────────
        "sched.missing_name"      = "缺少定时任务名称，请使用 --name <名称>。"
        "sched.missing_task"      = "缺少任务提示词，请使用 --task `"您的提示词`"。"
        "sched.already_exists"    = "名为 '{0}' 的定时任务已存在，请先删除：tian-cli schedule remove {0}"
        "sched.win_fail"          = "创建Windows定时任务失败（退出码 {0}）。"
        "sched.win_admin"         = "请以管理员身份运行 tian-cli。"
        "sched.launchd_ok"        = "定时任务 '{0}' 已注册到 launchd。"
        "sched.created"           = "定时任务 '{0}' 已创建 — {1} 每天 {2} 执行。"
        "sched.results_tip"       = "查看结果：tian-cli jobs（首次运行后）"
        "sched.remove_usage"      = "用法：tian-cli schedule remove <名称>"
        "sched.not_found"         = "未找到名为 '{0}' 的定时任务。"
        "sched.win_remove_fail"   = "无法删除Windows定时任务（可能已被删除）。"
        "sched.removed"           = "定时任务 '{0}' 已删除。"
        "sched.none"              = "暂无定时任务。创建方式：tian-cli schedule add --name <名称> --task `"提示词`" --time 08:00"
        "sched.header"            = "定时任务列表"
        "sched.run_tip"           = "tian-cli schedule run <名称>     立即运行"
        "sched.remove_tip"        = "tian-cli schedule remove <名称>  删除任务"
        "sched.run_usage"         = "用法：tian-cli schedule run <名称>"
        "sched.running_now"       = "正在立即运行定时任务 '{0}'..."
    }
}

# ── Settings helpers ──────────────────────────────────────────────────────────
$_tianSettingsPath = Join-Path (
    if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
) ".tian" "settings.json"

function Get-TianLang {
    try {
        if (Test-Path $_tianSettingsPath) {
            $s = Get-Content $_tianSettingsPath -Raw | ConvertFrom-Json
            if ($s.lang) { return $s.lang }
        }
    } catch {}
    return "en"
}

function Set-TianLang {
    param([string]$Lang)
    $dir = Split-Path $_tianSettingsPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $settings = @{}
    if (Test-Path $_tianSettingsPath) {
        try { $settings = Get-Content $_tianSettingsPath -Raw | ConvertFrom-Json -AsHashtable } catch {}
    }
    $settings["lang"] = $Lang
    $settings | ConvertTo-Json | Set-Content $_tianSettingsPath -Encoding UTF8
}

# Active language (loaded once at startup)
if (-not $global:TIAN_LANG) { $global:TIAN_LANG = Get-TianLang }

function T {
    param([string]$Key)
    $s = $global:TIAN_STRINGS[$global:TIAN_LANG][$Key]
    if (-not $s) { $s = $global:TIAN_STRINGS["en"][$Key] }
    if (-not $s) { return $Key }
    return $s
}

# Shorthand for formatted strings:  TF "key" arg1 arg2
function TF {
    param([string]$Key, [object[]]$Args)
    return [string]::Format((T $Key), $Args)
}

# Display name helper — use localized name from catalog if available
function Get-DisplayName {
    param($Item)
    $lang = $global:TIAN_LANG
    if ($lang -eq "zh" -and $Item.displayNameZh) { return $Item.displayNameZh }
    return $Item.displayName
}

function Get-Description {
    param($Item)
    $lang = $global:TIAN_LANG
    if ($lang -eq "zh" -and $Item.descriptionZh) { return $Item.descriptionZh }
    return $Item.description
}

function Get-Category {
    param($Item)
    $lang = $global:TIAN_LANG
    if ($lang -eq "zh" -and $Item.categoryZh) { return $Item.categoryZh }
    return $Item.category
}

function Get-ApiKeyLabel {
    param($Backend)
    $lang = $global:TIAN_LANG
    if ($lang -eq "zh" -and $Backend.apiKeyLabelZh) { return $Backend.apiKeyLabelZh }
    return $Backend.apiKeyLabel
}
