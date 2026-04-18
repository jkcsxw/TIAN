# TIAN — Talk Is All you Need
# 天 — 会说话，就会用AI

> Set up AI on your computer in minutes. No coding. No technical background. Just follow the steps.
> 几分钟内在您的电脑上安装好AI助手。无需编程，无需技术背景，按步骤操作即可。

---

## What is TIAN? | 什么是「天」？

TIAN is a simple setup tool that helps **anyone** — even with zero knowledge of AI or software — get powerful AI assistants running on their Windows computer. Whether you want help with daily tasks or want to automate parts of your business, TIAN makes it easy.

You don't need to know what "terminal", "Python", or "API" means. If you can install an app on Windows, you can use TIAN.

---

「天」是一款简单的安装工具，帮助**任何人**——即使完全不了解AI或软件——在Windows电脑上快速配置强大的AI助手。无论您是想提升日常工作效率，还是希望为自己的业务实现自动化，「天」都能轻松搞定。

您不需要了解"终端"、"Python"或"API"是什么。只要您会在Windows上安装软件，就能使用「天」。

---

## What can you do with it? | 能做什么？

- **Chat with AI** to get help with emails, documents, research, spreadsheets, and more
- **Set up MCP servers** — plugins that let your AI connect to files, calendars, email, web search, and business tools
- **Install skills** tailored to your daily workflow or business needs
- **Switch AI backends** based on your preference — Claude, Claude Code, OpenAI Codex, and more

---

- **与AI对话** — 协助处理邮件、文档、调研、表格等各类任务
- **配置MCP工具** — 让AI连接您的文件、日历、邮件、网络搜索和业务软件
- **安装技能包** — 根据您的日常工作或业务需求定制AI能力
- **切换AI引擎** — 按需选择 Claude、Claude Code、OpenAI Codex 等多种AI

---

## Who is this for? | 适合哪些人？

- Business owners who want AI to help with day-to-day operations
- Professionals who want to save time on repetitive tasks
- Anyone curious about AI who has been held back by the complexity of setup

---

- 希望用AI提升日常运营效率的企业主
- 想要节省重复性工作时间的职场人士
- 对AI感兴趣、但被复杂安装步骤劝退的普通用户



---

## Requirements | 系统要求

| | Windows | macOS |
|---|---|---|
| OS version | Windows 10 or later | macOS 10.15 (Catalina) or later |
| Software needed | Nothing — TIAN installs everything | Nothing — TIAN installs everything (including Homebrew if missing) |
| Terminal needed | No (GUI wizard available) | Yes (open Terminal from Applications → Utilities) |
| API key needed | Yes (wizard walks you through it) | Yes (setup script walks you through it) |

| | Windows | macOS |
|---|---|---|
| 系统版本 | Windows 10 或更高 | macOS 10.15（Catalina）或更高 |
| 需要预装软件 | 无，「天」自动安装所有依赖 | 无，「天」自动安装所有依赖（包括Homebrew） |
| 需要终端 | 否（有图形向导） | 是（从"应用程序→实用工具"打开终端） |
| 需要API密钥 | 是（向导引导获取） | 是（安装脚本引导获取） |

---

## Getting Started | 快速开始

### Windows — Quickest way | Windows — 最快方式

> No command line needed. Just double-click and go.
> 无需命令行，双击即可开始。

**Option A — Download installer directly (recommended)**

Download [`tian-setup.exe`](../../releases/latest) from the Releases page and double-click it.

**Option B — Already have the ZIP? Run `get-installer.bat`**

If you downloaded the ZIP from the Code button, double-click **`get-installer.bat`** inside the folder.  
It will download and launch the installer for you automatically — no typing required.

---

**方式A — 直接下载安装程序（推荐）**

从 Releases 页面下载 [`tian-setup.exe`](../../releases/latest)，双击运行即可。

**方式B — 已下载ZIP？运行 `get-installer.bat`**

如果您通过 Code 按钮下载了 ZIP，在解压后的文件夹中双击 **`get-installer.bat`**。  
它会自动下载并启动安装程序，无需任何输入。

---

TIAN supports both **Windows** and **macOS**. Choose your platform below.

「天」同时支持 **Windows** 和 **macOS**，请根据您的系统选择对应说明。

| | Windows Installer | Windows ZIP | macOS |
|---|---|---|---|
| Who it's for | Anyone — easiest | Terminal users / developers | All Mac users |
| How to start | Download & double-click `.exe` | Extract ZIP, double-click `setup.bat` | `bash setup.sh` |
| Adds tian-cli to PATH | Yes (optional) | No (manual) | Yes |
| Includes uninstaller | Yes | No | No |
| Scripting / automation | Yes | Yes | Yes |

| | Windows安装程序 | Windows ZIP | macOS |
|---|---|---|---|
| 适合人群 | 任何人，最简单 | 命令行用户/开发者 | 所有Mac用户 |
| 启动方式 | 下载 `.exe` 双击安装 | 解压ZIP，双击 `setup.bat` | `bash setup.sh` |
| 自动加入PATH | 是（可选） | 否（需手动） | 是 |
| 包含卸载程序 | 是 | 否 | 否 |
| 支持自动化 | 是 | 是 | 是 |

---

### Step 1 (Installer) — Download and Run | 第一步（安装程序）— 下载并运行

> **Recommended for most Windows users | 大多数Windows用户推荐此方式**

Download the latest `tian-setup-*.exe` from the [Releases page](../../releases/latest).  
Double-click the downloaded file and follow the installer wizard. It will:

1. Install TIAN to `C:\Program Files\TIAN` (or your chosen folder)
2. Optionally add `tian-cli` to your system PATH
3. Create a Start Menu shortcut for the Setup Wizard
4. Offer to launch the TIAN Setup Wizard immediately after installation

从 [Releases 页面](../../releases/latest) 下载最新的 `tian-setup-*.exe`。  
双击下载的文件，按照安装向导操作。安装程序将：

1. 将 TIAN 安装到 `C:\Program Files\TIAN`（或您选择的目录）
2. 可选：将 `tian-cli` 加入系统 PATH
3. 在开始菜单创建安装向导快捷方式
4. 安装完成后可立即启动 TIAN 安装向导

---

### Step 1 (ZIP) — Download TIAN | 第一步（ZIP）— 下载「天」

Click the green **Code** button at the top of this page, then click **Download ZIP**. Unzip the folder somewhere easy to find, like your Desktop.

点击本页顶部绿色的 **Code** 按钮，然后选择 **Download ZIP**。将压缩包解压到容易找到的位置，例如桌面。

---

### Step 2 (ZIP / GUI) — Run the Setup Wizard | 第二步（ZIP / 图形界面）— 运行「天」安装向导

Inside the unzipped folder, double-click `setup.bat`. A simple window will open and guide you through:

1. **Choose your AI** — pick Claude, Codex, or another assistant
2. **Connect your account** — the wizard will open a website in your browser where you can sign up and get a free API key. An API key is like a password that lets TIAN talk to the AI on your behalf. The wizard walks you through getting it step by step — you just copy and paste.
3. **Pick your tools and skills** — choose what you want the AI to be able to do
4. **Wait for install** — TIAN handles everything automatically

---

在解压后的文件夹中，双击 `setup.bat`。一个简单的窗口将会弹出，引导您完成以下步骤：

1. **选择AI引擎** — 选择 Claude、Codex 或其他AI助手
2. **连接您的账号** — 向导会自动打开浏览器，引导您注册并获取API密钥。API密钥就像一个密码，让「天」代表您与AI通信。向导会一步步告诉您如何获取，您只需复制粘贴即可。
3. **选择工具和技能包** — 勾选您希望AI能够执行的功能
4. **等待安装完成** — 「天」全自动处理，无需任何操作

---

### Step 2 (CLI) — Install via Terminal | 第二步（命令行）— 通过终端安装

> For users comfortable with PowerShell or Command Prompt.
> 适合熟悉 PowerShell 或命令提示符的用户。

**1. Open a terminal in the TIAN folder**

In File Explorer, navigate to the unzipped TIAN folder. Click the address bar at the top, type `cmd`, and press Enter. A terminal window will open in the right place.

在文件资源管理器中进入解压后的 TIAN 文件夹，点击顶部地址栏，输入 `cmd`，回车即可在当前目录打开终端窗口。

**2. Run the interactive CLI setup**

```bat
tian-cli setup
```

Follow the prompts to choose your backend, paste your API key, and select tools.

按照提示选择AI引擎、粘贴API密钥并选择工具。

**Or install in one line (no prompts)**

```bat
tian-cli install --backend claude-code --key YOUR_API_KEY_HERE --mcp filesystem,web-search --yes
```

Replace `YOUR_API_KEY_HERE` with your actual key. Get one at [console.anthropic.com](https://console.anthropic.com/settings/keys) for Claude, or [platform.openai.com](https://platform.openai.com/api-keys) for Codex.

将 `YOUR_API_KEY_HERE` 替换为您的真实密钥。Claude 密钥在 [console.anthropic.com](https://console.anthropic.com/settings/keys) 获取，Codex 密钥在 [platform.openai.com](https://platform.openai.com/api-keys) 获取。

**3. Verify the install**

```bat
tian-cli status
```

**4. Add more tools any time**

```bat
tian-cli list mcp          :: see all available tools
tian-cli add mcp github    :: add a specific tool
tian-cli add skill data-analyst
```

Run `tian-cli help` for the full command reference.

运行 `tian-cli help` 查看完整命令说明。

---

---

## macOS Setup | macOS 安装

### Mac Step 1 — Download TIAN | Mac第一步 — 下载「天」

Click the green **Code** button at the top of this page, then **Download ZIP**. Unzip the folder to somewhere easy to find, like your Desktop.

点击本页顶部绿色 **Code** 按钮，选择 **Download ZIP**，将压缩包解压到桌面等易找到的位置。

### Mac Step 2 — Open Terminal | Mac第二步 — 打开终端

Open **Terminal** (press `⌘ Space`, type `Terminal`, press Enter). Then type:

打开**终端**（按 `⌘ 空格`，输入 `Terminal`，回车）。然后输入：

```bash
cd ~/Desktop/TIAN-main
bash setup.sh
```

The script will:
1. Install **Homebrew** (the Mac package manager) if you don't have it — you may be asked for your Mac password
2. Install **Node.js** automatically
3. Open your browser to get an API key — just follow the prompts
4. Let you pick your MCP tools and skills
5. Create `launcher.sh` to start chatting

安装脚本将自动完成：
1. 安装 **Homebrew**（Mac包管理器），如未安装会提示输入Mac密码
2. 自动安装 **Node.js**
3. 打开浏览器引导获取API密钥，按提示操作即可
4. 让您选择MCP工具和技能包
5. 创建 `launcher.sh` 启动文件

### Mac Step 3 — Start Talking | Mac第三步 — 开始对话

Open a **new** Terminal window (important — so your API key is loaded), then:

打开一个**新的**终端窗口（重要——确保API密钥已加载），然后输入：

```bash
bash launcher.sh
```

For the CLI on Mac: | Mac命令行：

```bash
bash tian-cli.sh help
bash tian-cli.sh run "Summarise the latest news about AI"
bash tian-cli.sh schedule add --name morning-brief --task "Give me a morning briefing" --time 08:00 --repeat daily
```

> **Note:** The Mac version uses your Terminal instead of a GUI window. Everything else — MCP tools, skills, background tasks, scheduling — works exactly the same as Windows.
>
> **注意：** Mac版本使用终端而非图形界面。其他功能——MCP工具、技能包、后台任务、定时任务——与Windows版本完全一致。

---

### Step 3 — Start Talking | 第三步 — 开始对话

Once setup is complete, double-click `launcher.bat` (Windows) or run `bash launcher.sh` (Mac) and start chatting. TIAN is not just a Q&A tool — it can actively work for you. Here are some things you can say:

**Daily life | 日常生活**
- "Write a professional email to my landlord asking to fix the heating"
- "Summarize this article for me" *(paste any text)*
- "Help me plan a 5-day trip to Japan on a $2,000 budget"
- "Translate this paragraph into Chinese / English"
- "Proofread my CV and suggest improvements"

**Business | 商业用途**
- "Draft a reply to this customer complaint" *(paste the email)*
- "Turn these messy meeting notes into a clean action item list" *(paste notes)*
- "Write 5 LinkedIn post ideas about our new product launch"
- "Analyse this sales data and tell me what's working" *(paste a table)*
- "Create a professional invoice template for my freelance business"
- "Write a job description for a customer service role"

**Automation & files | 自动化与文件**
- "Read the file on my Desktop called report.pdf and summarise it" *(requires File System MCP)*
- "Search the web for the latest news about AI in healthcare" *(requires Web Search MCP)*
- "Save my to-do list to a file and remind me of it tomorrow"

You are always in control — TIAN only does what you ask, one conversation at a time.

---

安装完成后，双击 `launcher.bat` 即可开始对话。「天」不只是问答工具——它可以主动为您完成各种任务。以下是一些示例：

**日常生活**
- "帮我写一封给房东的邮件，要求修复暖气"
- "帮我总结这篇文章"（粘贴任意文字）
- "帮我规划一个2000美元预算的日本5日游"
- "把这段话翻译成中文/英文"
- "帮我修改简历并提出改进建议"

**商业用途**
- "帮我回复这封客户投诉邮件"（粘贴邮件内容）
- "把这些凌乱的会议记录整理成清晰的行动清单"（粘贴记录）
- "为我们的新产品发布写5条LinkedIn帖子"
- "分析这份销售数据，告诉我哪些方面表现良好"（粘贴表格）
- "为我的自由职业创建一个专业发票模板"
- "写一份客服岗位的招聘描述"

**自动化与文件**
- "读取我桌面上的 report.pdf 并帮我总结"（需要文件系统MCP）
- "搜索最新的医疗AI新闻"（需要网络搜索MCP）
- "把我的待办事项保存到文件中"

您始终掌握主动权——「天」只执行您明确要求的操作。

---

## CLI Reference | 命令行参考

For users comfortable with a terminal, `tian-cli.bat` gives full control without the GUI.

适合熟悉命令行的用户，`tian-cli.bat` 提供完整的命令行控制，无需图形界面。

```
tian-cli <command> [subcommand] [options]
```

| Command | Description | 说明 |
|---|---|---|
| `tian-cli setup` | Interactive guided setup in the terminal | 终端交互式安装向导 |
| `tian-cli install --backend <id> --key <key>` | Non-interactive install with flags | 使用参数直接安装，无需交互 |
| `tian-cli status` | Show what is installed and configured | 显示已安装和已配置的内容 |
| `tian-cli list backends` | List all available AI backends | 列出所有可用的AI引擎 |
| `tian-cli list mcp` | List all available MCP servers | 列出所有可用的MCP工具 |
| `tian-cli list skills` | List all available skills | 列出所有可用的技能包 |
| `tian-cli add mcp <id>` | Add an MCP server to your config | 向配置中添加MCP工具 |
| `tian-cli add skill <id>` | Install a skill | 安装技能包 |
| `tian-cli remove mcp <id>` | Remove an MCP server | 移除MCP工具 |
| `tian-cli repair` | Re-run setup for current config | 重新执行当前配置的安装 |
| `tian-cli run "prompt"` | Run a task now and print the result | 立即执行任务并输出结果 |
| `tian-cli run "prompt" --background` | Run a task in the background | 在后台执行任务 |
| `tian-cli jobs` | List all background jobs and their status | 列出所有后台任务及状态 |
| `tian-cli jobs result <id>` | Read the output of a completed job | 查看已完成任务的输出 |
| `tian-cli jobs clear` | Clear completed jobs (`--all` clears everything) | 清除已完成任务记录 |
| `tian-cli schedule add` | Create a recurring scheduled task | 创建定时/定期任务 |
| `tian-cli schedule list` | List all scheduled tasks | 列出所有定时任务 |
| `tian-cli schedule run <name>` | Run a scheduled task immediately | 立即执行某个定时任务 |
| `tian-cli schedule remove <name>` | Delete a scheduled task | 删除定时任务 |

**Install flags | 安装参数**

| Flag | Description |
|---|---|
| `--backend <id>` | AI backend to install (e.g. `claude-code`, `openai-codex`) |
| `--key <apikey>` | API key for the chosen backend |
| `--mcp <ids>` | Comma-separated MCP server IDs (e.g. `filesystem,web-search`) |
| `--skills <ids>` | Comma-separated skill IDs |
| `--yes` | Skip all confirmation prompts (for scripting) |

**Schedule flags | 定时任务参数**

| Flag | Description | 说明 |
|---|---|---|
| `--name <name>` | Schedule name (required) | 任务名称（必填） |
| `--task "prompt"` | The AI prompt to run (required) | 要执行的提示词（必填） |
| `--time HH:MM` | Time of day to run (default: `08:00`) | 每天执行时间（默认08:00） |
| `--repeat <freq>` | `once` / `hourly` / `daily` / `weekly` (default: `daily`) | 重复频率 |
| `--day <days>` | Days for weekly repeat e.g. `MON,WED,FRI` | 每周执行日（weekly模式） |

**Examples | 示例**

```bat
:: Interactive setup
tian-cli setup

:: Fully automated install
tian-cli install --backend claude-code --key sk-ant-xxx --mcp filesystem,web-search --yes

:: Check what's installed
tian-cli status

:: Add a new MCP server after initial setup
tian-cli add mcp github

:: List everything available
tian-cli list mcp

:: Run a task now (output printed to terminal)
tian-cli run "Summarise the latest AI news in 5 bullet points"

:: Run a task in the background and check it later
tian-cli run "Draft my weekly team update email" --background
tian-cli jobs
tian-cli jobs result 20240417-083012-ab12cd

:: Schedule a daily morning briefing at 8am
tian-cli schedule add --name morning-brief --task "Give me a short morning briefing with 3 key things to focus on today" --time 08:00 --repeat daily

:: Schedule a Monday weekly report at 9am
tian-cli schedule add --name weekly-report --task "Summarise this week's priorities and suggest a plan" --time 09:00 --repeat weekly --day MON

:: List and manage schedules
tian-cli schedule list
tian-cli schedule run morning-brief
tian-cli schedule remove morning-brief
```

---

## Supported AI Backends | 支持的AI引擎

| Backend | Best for | 最适合 |
|---|---|---|
| Claude (Anthropic) | Everyday tasks, writing, analysis | 日常任务、写作、分析 |
| Claude Code | Coding, technical work, automation | 编程、技术工作、自动化 |
| OpenAI Codex | Code generation and developer tools | 代码生成和开发者工具 |
| *(more coming)* | | *（持续更新中）* |

You can switch backends at any time by re-running `setup.bat`.
可随时重新运行 `setup.bat` 切换「天」的AI引擎。

---

## MCP Tools — Give Your AI Hands | MCP工具 — 给AI装上"手"

### What is an MCP tool? | 什么是MCP工具？

By default, your AI can only read and write text in the chat window. An **MCP tool** is a plugin that gives your AI the ability to actually *do things* — read files on your computer, search the web, check your calendar, send a message, query a database, and more.

Think of it like this: the AI is the brain, and MCP tools are the hands. Without them, it can think and talk. With them, it can act.

**You do not need to know what MCP stands for.** Just pick the tools that match what you want your AI to do. TIAN installs and connects them automatically.

默认情况下，AI只能在对话窗口中读写文字。**MCP工具**是一种插件，让AI能够真正"做事"——读取您电脑上的文件、搜索网页、查看日历、发送消息、查询数据库等。

可以这样理解：AI是大脑，MCP工具是双手。没有工具，它只能思考和说话；有了工具，它就能付诸行动。

**您不需要了解MCP是什么缩写。** 只需根据您希望AI能做的事情，勾选对应工具，「天」会自动完成安装和配置。

---

### Which MCP tools should I pick? | 我应该选哪些MCP工具？

| If you want your AI to… | Install this tool | 如果您希望AI能… | 安装此工具 |
|---|---|---|---|
| Read and save files on your computer | File System Access | 读写电脑上的文件 | 文件系统访问 |
| Search the internet for up-to-date info | Web Search | 搜索最新网络信息 | 网络搜索 |
| Remember things between conversations | Persistent Memory | 在多次对话间记住信息 | 持久记忆 |
| Read and manage GitHub projects | GitHub Integration | 读写GitHub项目 | GitHub集成 |
| Access Google Drive documents | Google Drive | 访问Google云端文档 | Google云端硬盘 |
| Read and send Slack messages | Slack | 读写Slack消息 | Slack集成 |
| Query your database | PostgreSQL Database | 查询数据库 | PostgreSQL数据库 |
| Automate web browser actions | Web Browser Control | 自动化浏览器操作 | 网页浏览器控制 |

> **Not sure? Start with just "File System Access" and "Web Search".** These two cover most everyday needs and you can always add more later.
>
> **不确定选哪个？从"文件系统访问"和"网络搜索"开始即可。** 这两个工具能满足大多数日常需求，之后可以随时添加更多。

---

## Skills — Teach Your AI Your Way of Working | 技能包 — 教AI按您的方式工作

### What is a skill? | 什么是技能包？

A **skill** is a set of instructions that tells your AI how to behave for a specific type of task. Without a skill, your AI is a generalist — it can do many things but doesn't know your preferred style, format, or workflow. With a skill, it knows exactly how you like things done.

For example, the **Email Assistant** skill tells your AI to always write emails in a clear, professional tone and ask for the recipient and purpose if you haven't specified them. The **Meeting Notes** skill tells it to always output a summary, decisions, and action items table — so you get a consistent format every time.

**You do not need to write or edit any code to use skills.** They are installed automatically. Just tell your AI what you want to do, and it will apply the right approach.

**技能包**是一组指令，告诉AI如何处理特定类型的任务。没有技能包，AI是通才——什么都能做，但不了解您的偏好风格和工作流程。有了技能包，它就能完全按照您习惯的方式工作。

例如，**邮件助手**技能包会让AI始终以清晰、专业的语气撰写邮件，并在您未指定收件人或目的时主动询问。**会议记录**技能包会让AI始终输出摘要、决策事项和行动清单表格，让您每次都获得一致的格式。

**使用技能包无需编写或修改任何代码。** 技能包会自动安装，您只需告诉AI您想做什么，它会自动应用正确的处理方式。

---

### Which skills should I pick? | 我应该选哪些技能包？

| If you regularly need to… | Install this skill | 如果您经常需要… | 安装此技能包 |
|---|---|---|---|
| Write or reply to emails | Email Assistant | 撰写或回复邮件 | 邮件助手 |
| Turn meeting notes into action items | Meeting Notes | 将会议记录转化为行动清单 | 会议记录 |
| Summarise long documents or reports | Document Summarizer | 总结长文档或报告 | 文档摘要 |
| Write customer service replies | Customer Support Templates | 撰写客户服务回复 | 客服模板 |
| Analyse data from spreadsheets | Data Analyst | 分析表格数据 | 数据分析师 |
| Create social media posts | Social Media Content | 创作社交媒体内容 | 社交媒体内容 |

> **Not sure? Pick "Email Assistant" and "Document Summarizer" to start.** These are the two most universally useful skills for both personal and business use.
>
> **不确定选哪个？从"邮件助手"和"文档摘要"开始。** 这两个技能包对个人和商业用途都最为实用。

---

### How do I use a skill after installing it? | 安装技能包后如何使用？

You don't need to do anything special — just chat naturally. Here are some examples of what to say:

安装后无需任何特殊操作，直接自然对话即可。以下是一些示例：

**Email Assistant | 邮件助手**
> "Write an email to my supplier asking why our order is delayed."
> "帮我写一封邮件给供应商，询问订单为何延误。"

**Meeting Notes | 会议记录**
> "Here are my notes from today's meeting: [paste notes]. Please format them."
> "这是今天会议的记录：[粘贴记录]。请帮我整理格式。"

**Document Summarizer | 文档摘要**
> "Summarise this report in 5 bullet points: [paste text]"
> "把这份报告总结成5条要点：[粘贴文字]"

**Data Analyst | 数据分析师**
> "Here is my sales data for Q1: [paste table]. What are the key trends?"
> "这是我Q1的销售数据：[粘贴表格]。有哪些关键趋势？"

---

### Can I add or remove tools and skills later? | 之后可以添加或删除工具和技能包吗？

Yes — at any time.

可以，随时都行。

- **GUI:** Re-run `setup.bat` and your previous choices will be pre-selected. Change whatever you like.
- **CLI:** Use `tian-cli add mcp <id>`, `tian-cli add skill <id>`, or `tian-cli remove mcp <id>`.

- **图形界面：** 重新运行 `setup.bat`，您之前的选择会自动预选，按需修改即可。
- **命令行：** 使用 `tian-cli add mcp <id>`、`tian-cli add skill <id>` 或 `tian-cli remove mcp <id>`。

---

## Extending TIAN | 扩展「天」

TIAN is designed to be extensible. Developers and technically inclined users can:

- Add new AI backends by adding an entry to `config/catalog.json`
- Create and share custom skills as simple Markdown files
- Package new MCP servers for community use

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for details. For running and writing tests, see [`TESTING.md`](TESTING.md).

---

「天」专为可扩展性而设计。开发者和有技术能力的用户可以：

- 在 `config/catalog.json` 中添加条目以接入新的AI引擎
- 创建并分享自定义技能包（Markdown文件格式）
- 为社区打包新的MCP服务器

详情请参阅 [`CONTRIBUTING.md`](CONTRIBUTING.md)。如需了解测试说明，请参阅 [`TESTING.md`](TESTING.md)。

---

## Roadmap | 开发计划

- [x] One-click Windows installer (.exe) | 一键Windows安装程序（.exe）
- [ ] GUI skill browser and installer | 图形化技能浏览与安装界面
- [ ] Business workflow templates | 商业工作流模板
- [x] Mac support | Mac 支持
- [ ] Linux support | Linux 支持
- [ ] Community skill marketplace | 社区技能市场

---

## Bug Reports & Feature Requests | 问题反馈与功能建议

Found a bug or have an idea? Open an issue on GitHub:

- [Report a bug](https://github.com/jkcsxw/TIAN/issues/new?template=bug_report.md) — include your OS, install method, and steps to reproduce
- [Request a feature](https://github.com/jkcsxw/TIAN/issues/new?template=feature_request.md) — describe the problem you want solved and your proposed solution

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for full guidance.

---

发现问题或有新想法？在 GitHub 上提交：

- [报告问题](https://github.com/jkcsxw/TIAN/issues/new?template=bug_report.md) — 请注明您的操作系统、安装方式和复现步骤
- [提交功能建议](https://github.com/jkcsxw/TIAN/issues/new?template=feature_request.md) — 描述您想解决的问题及建议方案

详细指引请参阅 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

---

## License | 开源协议

MIT — free to use, modify, and share.
MIT协议 — 免费使用、修改和分发。

---

*TIAN (天) means "sky" — because the only limit is your imagination.*
*「天」意为"天空"——因为唯一的限制，是你的想象力。*
