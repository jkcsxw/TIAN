#!/usr/bin/env bash
# TIAN native bash CLI — used on macOS/Linux when PowerShell Core (pwsh) is not installed
set -euo pipefail
TIAN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
export TIAN_DIR
shift || true
CATALOG="$TIAN_DIR/config/catalog.json"
TASKS_DIR="$HOME/.tian/tasks"
SCHEDULES_FILE="$HOME/.tian/schedules.json"
JOBS_FILE="$HOME/.tian/jobs.json"
TIAN_LANG_FILE="$HOME/.tian/lang"
TIAN_LANG="${TIAN_LANG:-}"
[[ -z "$TIAN_LANG" && -f "$TIAN_LANG_FILE" ]] && TIAN_LANG=$(cat "$TIAN_LANG_FILE" 2>/dev/null | tr -d '[:space:]') || true
[[ "$TIAN_LANG" == "zh" ]] || TIAN_LANG="en"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [ok]${RESET} $*"; }
info() { echo -e "${DIM}  [..]${RESET} $*"; }
warn() { echo -e "${YELLOW}  [!!]${RESET} $*"; }
fail() { echo -e "${RED}  [xx]${RESET} $*"; exit 1; }
rule() { echo -e "${DIM}──────────────────────────────────────────────────────────${RESET}"; }
hdr()  { echo ""; echo -e "${CYAN}${BOLD}$*${RESET}"; rule; }

# Bug fix: removed 2>/dev/null so Python errors are visible
py3() { python3 -c "$1"; }

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            grep -qi microsoft /proc/version 2>/dev/null && echo "wsl" || echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

# Returns the Claude Desktop config file path for the current platform.
# On WSL, Claude Desktop is a Windows app: its config lives in the Windows
# AppData directory, which we resolve via cmd.exe + wslpath.
# Falls back to ~/.config/Claude/... if the Windows path cannot be determined.
_claude_desktop_cfg_path() {
    local platform; platform=$(detect_platform)
    case "$platform" in
        macos)
            echo "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
            return ;;
        wsl)
            if command -v cmd.exe &>/dev/null; then
                local raw wsl_appdata
                raw=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r\n' || true)
                if [[ -n "$raw" && "$raw" != "%APPDATA%" ]]; then
                    wsl_appdata=$(wslpath "$raw" 2>/dev/null || true)
                    if [[ -n "$wsl_appdata" ]]; then
                        echo "$wsl_appdata/Claude/claude_desktop_config.json"
                        return
                    fi
                fi
            fi ;;
    esac
    echo "$HOME/.config/Claude/claude_desktop_config.json"
}

# Bug fix: check if command is actually installed, not just present in catalog
active_backend() {
    python3 - "$CATALOG" <<'PYEOF'
import json, sys, subprocess
catalog = json.load(open(sys.argv[1]))
for b in catalog['backends']:
    cmd = b.get('cliCommand', '')
    flag = b.get('nonInteractiveFlag', '')
    if cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0:
        print(cmd + '|' + flag + '|' + b['id'])
        break
PYEOF
}

all_backends() {
    python3 - "$CATALOG" <<'PYEOF'
import json, sys, subprocess
catalog = json.load(open(sys.argv[1]))
for b in catalog['backends']:
    cmd = b.get('cliCommand', '')
    flag = b.get('nonInteractiveFlag', '') or ''
    if cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0:
        print(f"{cmd}|{flag}|{b['id']}|{b.get('displayName', b['id'])}")
PYEOF
}

is_quota_error() {
    echo "${1:-}" | grep -qiE \
        "insufficient_quota|quota(_is_)?exhausted|quota is exhausted|rate[._]limit|rate limit|429|too many requests|overloaded"
}

# Detect whether a cron daemon is currently running. macOS uses launchd
# (always available), so this only matters on Linux/WSL where cron may
# need to be started manually — particularly on WSL, where it's off by
# default and `schedule add` would otherwise silently never fire.
cron_running() {
    if command -v pgrep &>/dev/null; then
        pgrep -x cron &>/dev/null && return 0
        pgrep -x crond &>/dev/null && return 0
    fi
    # Fallback: scan /proc for a cron/crond process
    if [[ -d /proc ]]; then
        for pid_dir in /proc/[0-9]*; do
            local comm
            comm=$(cat "$pid_dir/comm" 2>/dev/null || true)
            [[ "$comm" == "cron" || "$comm" == "crond" ]] && return 0
        done
    fi
    return 1
}

cron_fix_hint() {
    local platform="${1:-}"
    if [[ "$platform" == "wsl" ]]; then
        echo "Cron is off by default on WSL. Start it with: sudo service cron start"
        echo "  To start cron automatically on every WSL launch, add this to ~/.bashrc:"
        echo "    (pgrep -x cron >/dev/null) || sudo service cron start >/dev/null 2>&1"
    else
        echo "Start cron with:  sudo systemctl start cron   (or: sudo service cron start)"
        echo "  Enable on boot:   sudo systemctl enable cron"
    fi
}

ensure_dirs() {
    mkdir -p "$TASKS_DIR" "$HOME/.tian"
    [[ -f "$JOBS_FILE" ]] || echo '[]' > "$JOBS_FILE"
    [[ -f "$SCHEDULES_FILE" ]] || echo '[]' > "$SCHEDULES_FILE"
}

profile_file() {
    if [[ -f "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        echo "$HOME/.bash_profile"
    else
        echo "$HOME/.bashrc"
    fi
}

save_shell_env_var() {
    local name="${1:-}" value="${2:-}"
    [[ -n "$name" ]] || return 1
    local profile; profile=$(profile_file)
    mkdir -p "$(dirname "$profile")"
    touch "$profile"
    python3 - "$profile" "$name" "$value" <<'PYEOF'
import os, re, sys

profile, name, value = sys.argv[1], sys.argv[2], sys.argv[3]
pattern = re.compile(rf'^\s*export\s+{re.escape(name)}=')
lines = []
if os.path.exists(profile):
    with open(profile, encoding='utf-8', errors='ignore') as fh:
        lines = fh.readlines()
kept = [line for line in lines if not pattern.search(line)]
kept.append(f'export {name}="{value}"\n')
with open(profile, 'w', encoding='utf-8') as fh:
    fh.writelines(kept)
PYEOF
    export "$name=$value"
}

prompt_secret() {
    local label="${1:-Value}"
    local value=""
    read -rsp "  $label: " value
    echo ""
    printf '%s' "$value"
}

backend_supports_mcp() {
    local backend_id="${1:-}"
    [[ -n "$backend_id" ]] || return 1
    python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
backend = next((b for b in catalog["backends"] if b.get("id") == sys.argv[2]), None)
supports = backend is not None and backend.get("supportsMcp", True) and bool(backend.get("mcpConfigTarget") or backend.get("mcpConfigPath"))
raise SystemExit(0 if supports else 1)
PYEOF
}

find_backend_by_id() {
    local backend_id="${1:-}"
    python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
backend = next((b for b in catalog["backends"] if b.get("id") == sys.argv[2]), None)
if not backend:
    raise SystemExit(1)
print("|".join([
    backend.get("id", ""),
    backend.get("displayName", ""),
    backend.get("cliCommand", "") or "",
    backend.get("mcpConfigTarget", "") or "",
    backend.get("mcpConfigPath", "") or "",
]))
PYEOF
}

find_backend_install_by_id() {
    local backend_id="${1:-}"
    python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
backend = next((b for b in catalog["backends"] if b.get("id") == sys.argv[2]), None)
if not backend:
    raise SystemExit(1)
default_mcp = ",".join(backend.get("defaultMcpServers", []) or [])
print("|".join([
    backend.get("id", ""),
    backend.get("displayName", ""),
    backend.get("cliCommand", "") or "",
    backend.get("npmPackage", "") or "",
    backend.get("apiKeyEnvVar", "") or "",
    backend.get("apiKeyHint", "") or "",
    backend.get("apiKeyUrl", "") or "",
    backend.get("installType", "") or "",
    backend.get("launchCommand", "") or "",
    backend.get("setupNote", "") or "",
    "1" if backend.get("supportsMcp", True) else "0",
    default_mcp,
]))
PYEOF
}

find_mcp_by_id() {
    local server_id="${1:-}"
    python3 - "$CATALOG" "$server_id" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
server = next((s for s in catalog["mcpServers"] if s.get("id") == sys.argv[2]), None)
if not server:
    raise SystemExit(1)
reqs = ",".join((item.get("name") or "") for item in server.get("requiredEnvVars", []))
print("|".join([
    server.get("id", ""),
    server.get("displayName", ""),
    server.get("configKey", "") or "",
    reqs,
]))
PYEOF
}

find_skill_by_id() {
    local skill_id="${1:-}"
    python3 - "$CATALOG" "$skill_id" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
skill = next((s for s in catalog["skills"] if s.get("id") == sys.argv[2]), None)
if not skill:
    raise SystemExit(1)
print("|".join([
    skill.get("id", ""),
    skill.get("displayName", ""),
    skill.get("source", ""),
    skill.get("promptFile", "") or "",
    skill.get("npmPackage", "") or "",
    skill.get("gitUrl", "") or "",
]))
PYEOF
}

get_mcp_config_path_for_backend() {
    local backend_id="${1:-}"
    python3 - "$CATALOG" "$backend_id" "$(detect_platform)" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys

catalog_path, backend_id, platform, home, claude_desktop_cfg = sys.argv[1:6]
catalog = json.load(open(catalog_path))
backend = next((b for b in catalog["backends"] if b.get("id") == backend_id), None)
if not backend:
    raise SystemExit(1)
target = backend.get("mcpConfigTarget") or ""
custom = backend.get("mcpConfigPath") or ""

def expand(path: str) -> str:
    if platform == "macos":
        path = path.replace("%APPDATA%", os.path.join(home, "Library", "Application Support"))
    elif platform in ("linux", "wsl"):
        path = path.replace("%APPDATA%", os.path.join(home, ".config"))
    path = path.replace("%USERPROFILE%", home)
    return path.replace("\\", "/")

if target == "claude_desktop":
    print(claude_desktop_cfg)
elif target == "claude_code":
    print(os.path.join(home, ".claude", "settings.json"))
elif custom:
    print(expand(custom))
else:
    print(os.path.join(home, ".tian", "mcp_config.json"))
PYEOF
}

select_backend_for_mcp() {
    local explicit_backend="${1:-}"
    if [[ -n "$explicit_backend" ]]; then
        backend_supports_mcp "$explicit_backend" || fail "Backend '$explicit_backend' does not support MCP configuration."
        printf '%s' "$explicit_backend"
        return 0
    fi

    local active_row active_id
    active_row=$(active_backend || true)
    active_id=$(echo "$active_row" | cut -d'|' -f3)
    if [[ -n "$active_id" ]] && backend_supports_mcp "$active_id"; then
        printf '%s' "$active_id"
        return 0
    fi

    python3 - "$CATALOG" <<'PYEOF'
import json, sys

catalog = json.load(open(sys.argv[1]))
for backend in catalog["backends"]:
    if backend.get("supportsMcp", True) and (backend.get("mcpConfigTarget") or backend.get("mcpConfigPath")):
        print(backend["id"])
        break
PYEOF
}

ensure_required_env_vars() {
    local server_id="${1:-}"
    python3 - "$CATALOG" "$server_id" <<'PYEOF' | while IFS='|' read -r name label hint url; do
import json, sys

catalog = json.load(open(sys.argv[1]))
server = next((s for s in catalog["mcpServers"] if s.get("id") == sys.argv[2]), None)
for env_var in (server or {}).get("requiredEnvVars", []):
    print("|".join([
        env_var.get("name", ""),
        env_var.get("label", "") or env_var.get("name", ""),
        env_var.get("hint", "") or "",
        env_var.get("url", "") or "",
    ]))
PYEOF
        [[ -n "$name" ]] || continue
        if [[ -n "${!name:-}" ]]; then
            continue
        fi
        info "$label${hint:+ — $hint}"
        [[ -n "$url" ]] && info "Get it at: $url"
        local value; value=$(prompt_secret "$label")
        [[ -n "$value" ]] || fail "Missing required value for $name."
        save_shell_env_var "$name" "$value"
        ok "$name saved to $(profile_file)"
    done
}

install_skill() {
    local skill_id="${1:-}"
    local row
    row=$(find_skill_by_id "$skill_id") || fail "Unknown skill id '$skill_id'."
    local _id display_name source prompt_file npm_package git_url
    IFS='|' read -r _id display_name source prompt_file npm_package git_url <<< "$row"
    local skills_dir="$HOME/.tian/skills"
    mkdir -p "$skills_dir"

    case "$source" in
        builtin)
            [[ -n "$prompt_file" ]] || fail "Skill '$skill_id' does not define a prompt file."
            local src="$TIAN_DIR/$prompt_file"
            [[ -f "$src" ]] || fail "Skill file not found: $prompt_file"
            cp "$src" "$skills_dir/${skill_id}.md"
            ;;
        npm)
            [[ -n "$npm_package" ]] || fail "Skill '$skill_id' does not define an npm package."
            npm install -g "$npm_package"
            ;;
        git)
            [[ -n "$git_url" ]] || fail "Skill '$skill_id' does not define a git URL."
            git clone "$git_url" "$skills_dir/$skill_id"
            ;;
        *)
            fail "Unsupported skill source '$source' for '$skill_id'."
            ;;
    esac

    ok "$display_name installed."
}

add_mcp_server() {
    local server_id="${1:-}" backend_id="${2:-}"
    local server_row
    server_row=$(find_mcp_by_id "$server_id") || fail "Unknown MCP id '$server_id'."
    local _sid display_name config_key _
    IFS='|' read -r _sid display_name config_key _ <<< "$server_row"

    backend_id=$(select_backend_for_mcp "$backend_id")
    [[ -n "$backend_id" ]] || fail "No MCP-capable backend found."
    local backend_row backend_name config_path
    backend_row=$(find_backend_by_id "$backend_id") || fail "Unknown backend id '$backend_id'."
    IFS='|' read -r _ backend_name _ _ _ <<< "$backend_row"
    config_path=$(get_mcp_config_path_for_backend "$backend_id")
    mkdir -p "$(dirname "$config_path")"
    ensure_required_env_vars "$server_id"

    python3 - "$CATALOG" "$config_path" "$server_id" <<'PYEOF'
import json, os, sys

catalog_path, config_path, server_id = sys.argv[1:4]
catalog = json.load(open(catalog_path))
server = next((s for s in catalog["mcpServers"] if s.get("id") == server_id), None)
if not server:
    raise SystemExit(1)
config = {}
if os.path.exists(config_path):
    try:
        with open(config_path) as fh:
            config = json.load(fh)
    except Exception:
        config = {}
if not isinstance(config, dict):
    config = {}
config.setdefault("mcpServers", {})
config["mcpServers"][server["configKey"]] = server["configSchema"]
with open(config_path, "w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
PYEOF
    ok "$display_name added to $backend_name config."
    info "Config written to: $config_path"
}

remove_mcp_server() {
    local server_id="${1:-}" backend_id="${2:-}"
    local server_row
    server_row=$(find_mcp_by_id "$server_id") || fail "Unknown MCP id '$server_id'."
    local _sid display_name config_key _
    IFS='|' read -r _sid display_name config_key _ <<< "$server_row"

    backend_id=$(select_backend_for_mcp "$backend_id")
    [[ -n "$backend_id" ]] || fail "No MCP-capable backend found."
    local backend_row backend_name config_path
    backend_row=$(find_backend_by_id "$backend_id") || fail "Unknown backend id '$backend_id'."
    IFS='|' read -r _ backend_name _ _ _ <<< "$backend_row"
    config_path=$(get_mcp_config_path_for_backend "$backend_id")
    [[ -f "$config_path" ]] || fail "Config file not found: $config_path"

    local result
    result=$(python3 - "$config_path" "$config_key" <<'PYEOF'
import json, sys

config_path, config_key = sys.argv[1], sys.argv[2]
with open(config_path) as fh:
    config = json.load(fh)
servers = config.get("mcpServers", {})
if config_key in servers:
    del servers[config_key]
    config["mcpServers"] = servers
    with open(config_path, "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2)
    print("removed")
else:
    print("missing")
PYEOF
)
    [[ "$result" == "missing" ]] && fail "$display_name is not configured in $backend_name."
    ok "$display_name removed from $backend_name config."
}

resolve_schedule_name_by_prompt() {
    local prompt="${1:-}"
    python3 - "$SCHEDULES_FILE" "$prompt" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        schedules = json.load(fh)
except Exception:
    schedules = []
if not isinstance(schedules, list):
    schedules = [schedules]
matches = [s.get("name", "") for s in schedules if s.get("prompt") == sys.argv[2]]
print(matches[0] if len(matches) == 1 else "")
PYEOF
}

new_job_id() { date '+%Y%m%d-%H%M%S'-$(openssl rand -hex 3); }

sync_job_statuses() {
    python3 - "$JOBS_FILE" <<'PYEOF'
import json, os, re, subprocess, sys
from datetime import datetime

jobs_file = sys.argv[1]
try:
    with open(jobs_file) as fh:
        jobs = json.load(fh)
except Exception:
    jobs = []

changed = False
for job in jobs:
    if job.get("status") != "running":
        continue
    pid = job.get("pid")
    alive = False
    if pid:
        try:
            os.kill(int(pid), 0)
            alive = True
        except Exception:
            alive = False
    if not alive:
        job_id = job.get("id", "")
        out_file = os.path.expanduser(f"~/.tian/tasks/{job_id}.txt")
        text = open(out_file, encoding="utf-8", errors="ignore").read() if os.path.exists(out_file) else ""
        quota = re.search(r"insufficient_quota|quota(?:\s+is)?\s+exhausted|quota_exhausted|rate\.limit|rate limit|429|too many requests|overloaded", text, re.I) is not None
        job["status"] = "stopped" if quota else "done"
        job["finishedAt"] = datetime.now().isoformat()
        if quota:
            job["stopReason"] = "quota_exhausted"
            schedule_name = job.get("scheduleName", "")
            if schedule_name:
                tian_dir = os.environ.get("TIAN_DIR", "")
                if tian_dir:
                    subprocess.run(["bash", os.path.join(tian_dir, "tian-cli.sh"), "schedule", "remove", schedule_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        changed = True

if changed:
    with open(jobs_file, "w") as fh:
        json.dump(jobs, fh, indent=2)
PYEOF
}

_get_job_status() {
    python3 - "$JOBS_FILE" "$1" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        jobs = json.load(fh)
except Exception:
    jobs = []
j = next((x for x in jobs if x.get('id') == sys.argv[2]), None)
print(j.get('status', 'unknown') if j else 'unknown')
PYEOF
}

_get_job_stop_reason() {
    python3 - "$JOBS_FILE" "$1" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        jobs = json.load(fh)
except Exception:
    jobs = []
j = next((x for x in jobs if x.get('id') == sys.argv[2]), None)
print((j or {}).get('stopReason', ''))
PYEOF
}

# Stream a job's output to the terminal and return when the job is no longer
# running. Ctrl+C during streaming stops watching but leaves the job alive.
# Exit code: 0 if job ended as "done", non-zero otherwise.
_watch_job() {
    local job_id="$1"
    local out_file="$TASKS_DIR/$job_id.txt"

    # Output file is created when the background redirect starts; wait briefly.
    local waited=0
    while [[ ! -f "$out_file" && $waited -lt 20 ]]; do
        sleep 0.25
        waited=$((waited + 1))
    done
    if [[ ! -f "$out_file" ]]; then
        warn "Output file did not appear: $out_file"
        return 1
    fi

    tail -n +1 -f "$out_file" &
    local tail_pid=$!

    local interrupted=0
    # Stop tail on Ctrl+C or shell exit; flag the loop so it breaks cleanly.
    trap 'interrupted=1; kill '"$tail_pid"' 2>/dev/null || true' INT
    trap 'kill '"$tail_pid"' 2>/dev/null || true' EXIT

    local status="running"
    while :; do
        sleep 1
        [[ $interrupted -eq 1 ]] && break
        sync_job_statuses
        status=$(_get_job_status "$job_id")
        [[ "$status" != "running" ]] && break
    done

    if [[ $interrupted -eq 0 ]]; then
        # Allow tail a moment to flush any trailing output.
        sleep 1
    fi
    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    trap - INT EXIT

    echo ""
    rule
    if [[ $interrupted -eq 1 ]]; then
        info "Stopped watching — job $job_id is still running in the background."
        info "Resume with: bash tian-cli.sh jobs tail $job_id"
        return 130
    fi

    case "$status" in
        done)
            ok "Job $job_id finished."
            ;;
        failed)
            warn "Job $job_id failed. See output above or: bash tian-cli.sh jobs result $job_id"
            ;;
        stopped)
            local reason
            reason=$(_get_job_stop_reason "$job_id")
            if [[ "$reason" == "quota_exhausted" ]]; then
                warn "Job $job_id stopped — quota or rate limit exhausted."
            else
                warn "Job $job_id was stopped."
            fi
            ;;
        *)
            info "Job $job_id status: $status"
            ;;
    esac
    [[ "$status" == "done" ]]
}

terminate_pid_tree() {
    local pid="${1:-}"
    [[ -z "$pid" ]] && return 0
    if command -v pgrep &>/dev/null; then
        local child
        while IFS= read -r child; do
            [[ -n "$child" ]] && terminate_pid_tree "$child"
        done < <(pgrep -P "$pid" 2>/dev/null || true)
    fi
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
}

stop_jobs() {
    local target="${1:-}"
    local reason="${2:-stopped_by_user}"
    local matched=0
    while IFS='|' read -r jid pid; do
        [[ -z "$jid" ]] && continue
        matched=1
        [[ -n "$pid" ]] && terminate_pid_tree "$pid"
        python3 - "$JOBS_FILE" "$jid" "$reason" <<'PYEOF'
import json, sys
from datetime import datetime

jobs_file, job_id, reason = sys.argv[1], sys.argv[2], sys.argv[3]
with open(jobs_file) as fh:
    jobs = json.load(fh)
for job in jobs:
    if job.get("id") == job_id:
        job["status"] = "stopped"
        job["finishedAt"] = datetime.now().isoformat()
        job["stopReason"] = reason
        break
with open(jobs_file, "w") as fh:
    json.dump(jobs, fh, indent=2)
PYEOF
        ok "Stopped job $jid"
    done < <(python3 - "$JOBS_FILE" "$target" <<'PYEOF'
import json, sys

jobs_file, target = sys.argv[1], sys.argv[2]
with open(jobs_file) as fh:
    jobs = json.load(fh)
for job in jobs:
    if job.get("status") != "running":
        continue
    if target and target != "--all" and job.get("id") != target:
        continue
    print(f"{job.get('id','')}|{job.get('pid','')}")
PYEOF
)

    [[ "$matched" -eq 1 ]] || info "No matching running jobs found."
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_help() {
    [[ "${TIAN_LANG:-en}" == "zh" ]] && { _cmd_help_zh; return; }
cat <<EOF

  TIAN CLI
  Talk Is All you Need

$(rule)

  USAGE
    tian-cli.sh <command> [options]

  COMMANDS
    setup               Re-run the interactive setup wizard
    install             Non-interactive install (flag-driven, scriptable)
    repair              Re-run setup to repair the current install
    update              Upgrade TIAN scripts and installed AI backends to their latest versions
    doctor [--fix]      Check your setup and diagnose common problems; --fix auto-resolves fixable issues
    uninstall           Remove TIAN's installed components (backends, keys, data)
    status              Show what is installed
    list backends       List available AI backends
    list mcp            List available MCP servers
    list skills         List available skills
    add mcp <id>        Add an MCP server to backend config
    add skill <id>      Install a skill
    remove mcp <id>     Remove an MCP server from backend config
    skill list          List skills and show which are installed
    skill run <id>      Run an installed skill (use its prompt template)
    skill run <id> <t>  Run a skill with extra input/context
    skill info <id>     Print a skill's prompt template
    run "prompt"        Run a task (foreground)
    run "prompt" -b     Run a task in the background
    run "prompt" -w     Run in background and stream live output (auto-exits when done)
    run "prompt" --backend <id>   Force a specific backend (e.g. ollama-qwen-local for privacy)
    run "prompt" --file <path>    Append file content to the prompt (e.g. summarize a document)
    run "prompt" --stdin          Append piped stdin to the prompt (also triggered automatically when stdin is not a tty)
    run "prompt" --output <path>  Save the AI response to a file (works with foreground and background)
    jobs                List background jobs
    jobs result <id>    Show output of a completed job
    jobs tail <id>      Stream live output (auto-exits when job ends; shows result if already done)
    jobs stop <id>      Stop a running job (--all stops every running job)
    jobs retry <id>     Re-run a failed or quota-stopped job with its original prompt
    jobs clear          Clear completed jobs (--old <days> keeps recent ones; --dry-run previews)
    schedule add        Create a recurring task (crontab on Linux, launchd on macOS)
    schedule add --day  Day(s) for weekly schedules: single (FRI), comma-separated (MON,WED,FRI),
                        or named preset (weekdays, weekends)
    schedule list       List scheduled tasks
    schedule run <n>    Run a scheduled task now
    schedule remove <n> Delete a scheduled task
    schedule templates  List pre-built schedule templates (morning briefing, weekly review, …)
    schedule templates apply <name>  Create a schedule from a template
    key set [id]        Set or update an API key for a backend (interactive)
    key show            Show which API keys are currently set
    key remove <id>     Remove an API key from your shell profile
    ping [--backend id] Send a quick test prompt to the active AI backend and verify it responds
    quota               Check live quota/rate-limit status for all API keys (colored output)
    config export       Export setup (API keys, MCP configs, skills, schedules) to a file
    config import       Restore a previously exported config on this machine
    completion bash     Print a bash tab-completion script (eval "\$(tian-cli completion bash)")
    completion zsh      Print a zsh tab-completion script  (eval "\$(tian-cli completion zsh)")
    completion install  Auto-install tab completion into your shell profile
    lang en|zh          Switch interface language (切换界面语言)
    help                Show this help

  INSTALL FLAGS (non-interactive)
    --backend <id>      AI backend (required, e.g. claude-code)
    --key     <key>     API key (saved to your shell profile)
    --mcp     <ids>     Comma-separated MCP server ids, or 'default'
    --skills  <ids>     Comma-separated skill ids
    --yes               Skip prompts; missing required env vars cause that
                        MCP server to be skipped (not a hard failure)

  EXAMPLES
    bash tian-cli.sh install --backend claude-code --key sk-ant-xxx --mcp default --yes
    bash tian-cli.sh install --backend claude-code --key sk-ant-xxx --mcp filesystem,memory --skills email-assistant
    bash tian-cli.sh run "Summarise today's AI news"
    bash tian-cli.sh run "Draft my weekly report" -b
    bash tian-cli.sh run "Research the latest LLM papers" -w
    bash tian-cli.sh run "Summarise this privately" --backend ollama-qwen-local
    bash tian-cli.sh run "Urgent task" --backend claude-code -b
    bash tian-cli.sh run "Summarise this document" --file report.pdf
    bash tian-cli.sh run "Review this code for bugs" --file src/main.py -b
    bash tian-cli.sh run "Write a blog post about AI" --output blog-post.md
    bash tian-cli.sh run "Summarise this document" --file report.pdf --output summary.md
    cat notes.txt | bash tian-cli.sh run "Organise these notes into bullet points"
    bash tian-cli.sh list backends
    bash tian-cli.sh jobs
    bash tian-cli.sh schedule add morning-brief "Morning briefing" 08:00 daily
    bash tian-cli.sh schedule add weekly-report "Weekly summary" 09:00 weekly --day FRI
    bash tian-cli.sh schedule add mwf-standup  "Standup notes"  09:00 weekly --day MON,WED,FRI
    bash tian-cli.sh schedule add weekday-task "Daily digest"   08:00 weekly --day weekdays
    bash tian-cli.sh schedule list
    bash tian-cli.sh config export --output my-tian-backup.json
    bash tian-cli.sh config export --no-keys
    bash tian-cli.sh config import my-tian-backup.json
    bash tian-cli.sh quota
    bash tian-cli.sh lang zh

EOF
}

_cmd_help_zh() {
cat <<'ZHEOF'

  TIAN CLI
  Talk Is All you Need

──────────────────────────────────────────────────────────

  用法
    tian-cli.sh <命令> [选项]

  命令
    setup               重新运行交互式安装向导
    install             非交互式安装（参数驱动，适合脚本）
    repair              重新运行安装以修复当前配置
    update              将TIAN脚本和已安装的AI后端升级到最新版本
    doctor [--fix]      检查安装并诊断常见问题；--fix 自动修复可修复的问题
    uninstall           移除TIAN安装的组件（后端、密钥、数据）
    status              显示已安装的内容
    list backends       列出可用的AI后端
    list mcp            列出可用的MCP服务器
    list skills         列出可用的技能包
    add mcp <id>        将MCP服务器添加到后端配置
    add skill <id>      安装技能包
    remove mcp <id>     从后端配置中移除MCP服务器
    skill list          列出技能包并显示已安装的
    skill run <id>      运行已安装的技能（使用提示词模板）
    skill run <id> <t>  带额外输入/上下文运行技能
    skill info <id>     打印技能的提示词模板
    run "提示词"        运行任务（前台）
    run "提示词" -b     在后台运行任务
    run "提示词" -w     在后台运行并实时显示输出（完成后自动退出）
    run "提示词" --backend <id>   指定后端（如：ollama-qwen-local 用于隐私任务）
    run "提示词" --file <路径>    将文件内容附加到提示词（如：总结文档）
    run "提示词" --stdin          将管道输入内容附加到提示词
    jobs                列出后台任务
    jobs result <id>    查看已完成任务的输出
    jobs tail <id>      实时追踪输出（任务结束后自动退出；Ctrl+C 停止追踪）
    jobs stop <id>      停止运行中的任务（--all 停止全部）
    jobs retry <id>     用原始提示词重新执行失败或配额耗尽的任务
    jobs clear          清除已完成任务（--old <天数> 保留近期；--dry-run 预览）
    schedule add        创建定时任务（Linux 用 crontab，macOS 用 launchd）
    schedule add --day  指定每周任务的运行日期：单天（FRI）、多天（MON,WED,FRI）或预设（weekdays、weekends）
    schedule list       列出所有定时任务
    schedule run <名称> 立即运行某个定时任务
    schedule remove <名称> 删除定时任务
    schedule templates  列出内置定时任务模板（早间简报、每周复盘等）
    schedule templates apply <名称>  从模板创建定时任务
    key set [id]        设置或更新API密钥（交互式）
    key show            显示当前已设置的API密钥
    key remove <id>     从Shell配置文件中移除API密钥
    ping [--backend id] 向AI后端发送测试提示词，验证其是否正常响应
    quota               检查所有API密钥的配额/速率限制状态（彩色输出）
    config export       将配置（API密钥、MCP、技能、定时任务）导出到文件
    config import       在此机器上恢复之前导出的配置
    completion bash     打印bash自动补全脚本
    completion zsh      打印zsh自动补全脚本
    completion install  自动将自动补全安装到Shell配置文件
    lang en|zh          切换界面语言
    help                显示此帮助

  安装参数（非交互式）
    --backend <id>      AI后端（必填，如：claude-code）
    --key     <key>     API密钥（保存到Shell配置文件）
    --mcp     <ids>     MCP服务器ID（逗号分隔，或填 'default'）
    --skills  <ids>     技能包ID（逗号分隔）
    --yes               跳过确认；缺少必要环境变量时跳过该MCP（非致命错误）

  示例
    bash tian-cli.sh install --backend claude-code --key sk-ant-xxx --mcp default --yes
    bash tian-cli.sh run "总结今日AI领域最新动态"
    bash tian-cli.sh run "帮我写今天的工作日报" -b
    bash tian-cli.sh run "研究最新的大语言模型论文" -w
    bash tian-cli.sh run "私密任务" --backend ollama-qwen-local
    bash tian-cli.sh run "总结这份文档" --file report.pdf
    cat notes.txt | bash tian-cli.sh run "将这些笔记整理成要点"
    bash tian-cli.sh list backends
    bash tian-cli.sh jobs
    bash tian-cli.sh schedule add morning-brief "早间简报" 08:00 daily
    bash tian-cli.sh schedule add weekly-report "每周总结"   09:00 weekly --day FRI
    bash tian-cli.sh schedule add mwf-standup  "站会记录"   09:00 weekly --day MON,WED,FRI
    bash tian-cli.sh schedule add weekday-task "每日摘要"   08:00 weekly --day weekdays
    bash tian-cli.sh config export --output 我的备份.json
    bash tian-cli.sh config import 我的备份.json
    bash tian-cli.sh quota
    bash tian-cli.sh lang en

ZHEOF
}

cmd_lang() {
    local lang="${1:-}"
    case "$lang" in
        en|zh)
            mkdir -p "$(dirname "$TIAN_LANG_FILE")"
            echo "$lang" > "$TIAN_LANG_FILE"
            TIAN_LANG="$lang"
            if [[ "$lang" == "zh" ]]; then
                ok "界面语言已切换为中文。运行 'tian-cli lang en' 可切回英文。"
            else
                ok "Interface language set to English. Run 'tian-cli lang zh' to switch to Chinese."
            fi
            ;;
        *)
            echo ""
            echo -e "  Usage: tian-cli lang en|zh"
            echo ""
            echo "    en   English interface"
            echo "    zh   中文界面"
            echo ""
            if [[ "${TIAN_LANG:-en}" == "zh" ]]; then
                info "当前语言：中文  (Current: zh)"
            else
                info "Current language: English  (当前：en)"
            fi
            echo ""
            ;;
    esac
}

cmd_status() {
    hdr "TIAN Status"

    # ── Active backend ────────────────────────────────────────────────────────
    echo -e "${BOLD}  Active backend${RESET}"
    local active_row; active_row=$(active_backend || true)
    if [[ -n "$active_row" ]]; then
        local active_cmd; active_cmd=$(echo "$active_row" | cut -d'|' -f1)
        local active_id;  active_id=$(echo "$active_row"  | cut -d'|' -f3)
        local active_ver=""
        case "$active_cmd" in
            claude) active_ver=$(claude --version 2>/dev/null | head -1 | awk '{print $1}') ;;
            codex)  active_ver=$(codex  --version 2>/dev/null | head -1 | awk '{print $1}') ;;
            ollama) active_ver=$(ollama --version 2>/dev/null | head -1 | awk '{print $NF}') ;;
        esac
        [[ -n "$active_ver" ]] && ok "$active_cmd  v$active_ver  (${active_id})" \
                                || ok "$active_cmd  (${active_id})"
    else
        warn "No backend installed — run: bash setup.sh"
    fi
    echo ""

    # ── All backends ──────────────────────────────────────────────────────────
    echo -e "${BOLD}  All backends${RESET}"
    while IFS='|' read -r b_cmd _flag b_id b_name b_installed; do
        [[ -z "$b_cmd" ]] && continue
        if [[ "$b_installed" == "1" ]]; then
            [[ "$b_cmd" == "$active_cmd" ]] \
                && ok   "$b_name  ← active" \
                || info "$b_name  (installed)"
        else
            info "$b_name  (not installed)"
        fi
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    cmd = b.get('cliCommand', '')
    flag = b.get('nonInteractiveFlag', '') or ''
    found = '1' if (cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0) else '0'
    print(f"{cmd}|{flag}|{b.get('id','')}|{b['displayName']}|{found}")
PYEOF
)
    echo ""

    # ── API keys ──────────────────────────────────────────────────────────────
    echo -e "${BOLD}  API keys${RESET}"
    local any_key=false
    while IFS='|' read -r env_var b_installed; do
        [[ -z "$env_var" ]] && continue
        local val="${!env_var:-}"
        if [[ -n "$val" ]]; then
            ok "$env_var  ${val:0:8}..."
            any_key=true
        elif [[ "$b_installed" == "1" ]]; then
            warn "$env_var  not set — run: tian-cli setup"
        else
            info "$env_var  (backend not installed)"
        fi
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, sys
c, seen = json.load(open(sys.argv[1])), set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', '')
    cmd = b.get('cliCommand', '')
    if not env or env in seen: continue
    seen.add(env)
    installed = '1' if (cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0) else '0'
    print(f"{env}|{installed}")
PYEOF
)
    echo ""

    # ── MCP config files ──────────────────────────────────────────────────────
    echo -e "${BOLD}  MCP config files${RESET}"
    local platform; platform=$(detect_platform)
    local mcp_count=0
    while IFS='|' read -r label path; do
        [[ -z "$path" ]] && continue
        if [[ -f "$path" ]]; then
            local n_servers
            n_servers=$(python3 -c "import json,os; d=json.load(open('$path')); print(len(d.get('mcpServers',{})))" 2>/dev/null || echo "?")
            ok "$label  ($n_servers server(s))  $path"
            ((mcp_count++)) || true
        else
            info "$label  not configured yet"
        fi
    done < <(python3 - "$CATALOG" "$platform" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys
catalog_path, platform, home, claude_desktop_cfg = sys.argv[1:5]
catalog = json.load(open(catalog_path))
seen = set()
for backend in catalog["backends"]:
    if not backend.get("supportsMcp", True): continue
    key = backend.get("mcpConfigTarget") or backend.get("mcpConfigPath") or ""
    if not key or key in seen: continue
    seen.add(key)
    target = backend.get("mcpConfigTarget") or ""
    custom = backend.get("mcpConfigPath") or ""
    if target == "claude_desktop":
        path = claude_desktop_cfg
    elif target == "claude_code":
        path = os.path.join(home, ".claude", "settings.json")
    else:
        base = os.path.join(home, "Library", "Application Support") if platform == "macos" else os.path.join(home, ".config")
        path = custom.replace("%APPDATA%", base).replace("%USERPROFILE%", home).replace("\\", "/") if custom else os.path.join(home, ".tian", "mcp_config.json")
    print(f"{target or backend.get('id','mcp')}|{path}")
PYEOF
)
    echo ""

    # ── Jobs summary ──────────────────────────────────────────────────────────
    echo -e "${BOLD}  Background jobs${RESET}"
    if [[ -f "$JOBS_FILE" ]]; then
        python3 - "$JOBS_FILE" "$TASKS_DIR" <<'PYEOF'
import json, os, sys

jobs_file, tasks_dir = sys.argv[1:3]
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; RESET='\033[0m'; BOLD='\033[1m'
PURPLE='\033[0;35m'

try:
    jobs = json.load(open(jobs_file))
except Exception:
    jobs = []

counts = {}
for j in jobs:
    s = j.get('status', 'unknown')
    counts[s] = counts.get(s, 0) + 1

if not jobs:
    print(f"  {DIM}  [..]{RESET} No jobs yet — run: tian-cli run \"your task\"")
else:
    parts = []
    if counts.get('running'):  parts.append(f"{GREEN}{counts['running']} running{RESET}")
    if counts.get('done'):     parts.append(f"{DIM}{counts['done']} done{RESET}")
    if counts.get('failed'):   parts.append(f"{RED}{counts['failed']} failed{RESET}")
    if counts.get('stopped'):  parts.append(f"{PURPLE}{counts['stopped']} quota-stopped{RESET}")
    print(f"  {GREEN}  [ok]{RESET} {',  '.join(parts)}  (total: {len(jobs)})")

    # show any currently running jobs
    running = [j for j in jobs if j.get('status') == 'running']
    for j in running[:3]:
        name = j.get('name') or j.get('id', '')
        task = (j.get('prompt') or '')[:60]
        print(f"  {DIM}  [..]{RESET}   ↳ [{j['id']}] {task}{'…' if len(j.get('prompt',''))>60 else ''}")

    # compute disk usage
    total_bytes = 0
    if os.path.isdir(tasks_dir):
        for fn in os.listdir(tasks_dir):
            try:
                total_bytes += os.path.getsize(os.path.join(tasks_dir, fn))
            except OSError:
                pass
    if total_bytes > 0:
        kb = total_bytes / 1024
        size_str = f"{kb/1024:.1f} MB" if kb > 1024 else f"{kb:.0f} KB"
        print(f"  {DIM}  [..]{RESET} Task output storage: {size_str}  ({tasks_dir})")
PYEOF
    else
        info "No jobs file yet"
    fi
    echo ""

    # ── Schedules summary ─────────────────────────────────────────────────────
    echo -e "${BOLD}  Scheduled tasks${RESET}"
    if [[ -f "$SCHEDULES_FILE" ]]; then
        python3 - "$SCHEDULES_FILE" <<'PYEOF'
import json, sys
GREEN='\033[0;32m'; DIM='\033[2m'; RESET='\033[0m'
try:
    schedules = json.load(open(sys.argv[1]))
except Exception:
    schedules = []
if not schedules:
    print(f"  {DIM}  [..]{RESET} No schedules — run: tian-cli schedule add ...")
else:
    print(f"  {GREEN}  [ok]{RESET} {len(schedules)} schedule(s) configured")
    for s in schedules[:5]:
        name   = s.get('name', '?')
        repeat = s.get('repeat', '?')
        time_  = s.get('time', '')
        task   = (s.get('prompt') or '')[:50]
        label  = f"{time_} {repeat}" if time_ else repeat
        print(f"  {DIM}  [..]{RESET}   ↳ {name}  [{label}]  {task}{'…' if len(s.get('prompt',''))>50 else ''}")
    if len(schedules) > 5:
        print(f"  {DIM}  [..]{RESET}   ↳ … and {len(schedules)-5} more")
PYEOF
    else
        info "No schedules yet"
    fi

    # Show whether the scheduler daemon is actually running — critical on WSL/Linux
    # where cron is off by default and schedules would silently never fire.
    local _sched_platform; _sched_platform=$(detect_platform)
    case "$_sched_platform" in
        macos)
            ok "Daemon: launchd (always active on macOS)" ;;
        linux|wsl)
            if cron_running; then
                ok "Daemon: cron is running — scheduled tasks will fire"
            else
                warn "Daemon: cron is NOT running — scheduled tasks will never fire"
                while IFS= read -r _hint; do
                    info "  $_hint"
                done < <(cron_fix_hint "$_sched_platform")
            fi
            ;;
    esac
    echo ""

    # ── Quick tips ────────────────────────────────────────────────────────────
    [[ -f "$TIAN_DIR/launcher.sh" ]] || warn "launcher.sh not found — run: bash setup.sh"
    rule
    info "Run 'tian-cli doctor' for a full health check."
    echo ""
}

cmd_run() {
    local prompt="$1"; shift || true
    local background=false
    local watch=false
    local job_name=""
    local schedule_name=""
    local forced_backend_id=""
    local input_file=""
    local read_stdin=false
    local output_path=""
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            -b|--background)
                background=true
                shift
                ;;
            -w|--watch)
                watch=true
                background=true
                shift
                ;;
            --job-name)
                job_name="${2:-}"
                shift 2
                ;;
            --schedule-name)
                schedule_name="${2:-}"
                shift 2
                ;;
            --backend)
                forced_backend_id="${2:-}"
                shift 2
                ;;
            --file|-f)
                input_file="${2:-}"
                shift 2
                ;;
            --stdin)
                read_stdin=true
                shift
                ;;
            --output|-o)
                output_path="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Append file content to the prompt when --file is given
    if [[ -n "$input_file" ]]; then
        [[ -f "$input_file" ]] || fail "File not found: $input_file"
        local file_size
        file_size=$(wc -c < "$input_file" 2>/dev/null || echo 0)
        if [[ "$file_size" -gt 524288 ]]; then
            warn "File is larger than 512 KB ($file_size bytes). Large files may exceed the AI's context window."
        fi
        local filename; filename=$(basename "$input_file")
        local file_content; file_content=$(cat "$input_file")
        prompt="${prompt}

---
File: ${filename}

${file_content}"
        info "Appended file content: $input_file"
    fi

    # Append stdin content when --stdin is given (or when stdin is not a tty)
    if $read_stdin || { [[ ! -t 0 ]] && [[ -z "$input_file" ]]; }; then
        local stdin_content; stdin_content=$(cat)
        if [[ -n "$stdin_content" ]]; then
            prompt="${prompt}

---
Piped input:

${stdin_content}"
            $read_stdin && info "Appended piped stdin content."
        fi
    fi

    [[ -z "$prompt" ]] && fail "Usage: tian-cli run \"your prompt\" [--file path] [--stdin] [--output path] [-b] [-w]"

    local backend_row cmd flag
    if [[ -n "$forced_backend_id" ]]; then
        local _bcheck
        _bcheck=$(python3 - "$CATALOG" "$forced_backend_id" <<'PYEOF'
import json, subprocess, sys
catalog = json.load(open(sys.argv[1]))
bid = sys.argv[2]
b = next((bb for bb in catalog['backends'] if bb.get('id') == bid), None)
if not b:
    print("error:notfound")
    raise SystemExit(1)
c = b.get('cliCommand', '')
fl = (b.get('nonInteractiveFlag', '') or '').strip()
if not c or subprocess.run(['which', c], capture_output=True).returncode != 0:
    print("error:notinstalled")
    raise SystemExit(2)
print(f"{c}|{fl}|{bid}")
PYEOF
) || true
        case "$_bcheck" in
            error:notfound)
                fail "Unknown backend '$forced_backend_id'. Run: tian-cli list backends" ;;
            error:notinstalled)
                fail "Backend '$forced_backend_id' is not installed. Run: tian-cli install --backend $forced_backend_id" ;;
        esac
        cmd=$(echo "$_bcheck" | cut -d'|' -f1)
        flag=$(echo "$_bcheck" | cut -d'|' -f2)
        [[ -z "$cmd" ]] && fail "Could not resolve backend '$forced_backend_id'."
        info "Using backend: $forced_backend_id"
    else
        backend_row=$(active_backend)
        cmd=$(echo "$backend_row" | cut -d'|' -f1)
        flag=$(echo "$backend_row" | cut -d'|' -f2)
        [[ -z "$cmd" ]] && fail "No AI backend found. Run: bash setup.sh"
    fi

    ensure_dirs
    local job_id; job_id=$(new_job_id)
    local out_file="$TASKS_DIR/$job_id.txt"
    [[ -n "$schedule_name" ]] || schedule_name=$(resolve_schedule_name_by_prompt "$prompt")
    [[ -n "$job_name" ]] || [[ -z "$schedule_name" ]] || job_name="$schedule_name"

    if $background; then
        info "Running in background (job: $job_id)..."
        # Run AI command with multi-backend fallback on quota exhaustion.
        # Mirrors the foreground fallback loop so background jobs also survive a rate-limited primary.
        nohup bash -c '
CATALOG="$8/config/catalog.json"
_primary="$1"
_prompt="$3"
_out="$4"
_ec=1
_forced="${9:-}"
if [[ -n "$_forced" ]]; then
    backends="$1|$2"
else
    backends=$(python3 -c "
import json, subprocess, sys
c = json.load(open(sys.argv[1]))
for b in c[\"backends\"]:
    cmd = b.get(\"cliCommand\", \"\")
    flag = (b.get(\"nonInteractiveFlag\", \"\") or \"\").strip()
    if cmd and subprocess.run([\"which\", cmd], capture_output=True).returncode == 0:
        print(cmd + \"|\" + flag)
" "$CATALOG" 2>/dev/null)
fi
while IFS="|" read -r r_cmd r_flag; do
    [[ -z "$r_cmd" ]] && continue
    $r_cmd $r_flag "$_prompt" >"$_out" 2>&1
    _ec=$?
    grep -qiE "insufficient_quota|quota(_is_)?exhausted|quota is exhausted|rate[._]limit|rate limit|429|too many requests|overloaded" "$_out" 2>/dev/null && continue
    break
done <<< "$backends"
python3 -c "
import json, os, re, subprocess, sys
jf, jid, code, out_file, schedule_name, tian_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
with open(jf) as _fh:
    jobs = json.load(_fh)
text = open(out_file, encoding=\"utf-8\", errors=\"ignore\").read() if os.path.exists(out_file) else \"\"
quota = re.search(r\"insufficient_quota|quota(?:\\s+is)?\\s+exhausted|quota_exhausted|rate\\.limit|rate limit|429|too many requests|overloaded\", text, re.I) is not None
for j in jobs:
    if j[\"id\"] == jid:
        j[\"status\"] = \"stopped\" if quota else (\"done\" if code == 0 else \"failed\")
        if quota:
            j[\"stopReason\"] = \"quota_exhausted\"
        break
with open(jf, \"w\") as _fh:
    json.dump(jobs, _fh, indent=2)
if quota and schedule_name:
    subprocess.run([\"bash\", os.path.join(tian_dir, \"tian-cli.sh\"), \"schedule\", \"remove\", schedule_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
" "$5" "$6" "$_ec" "$4" "$7" "$8"
# Desktop notification on job completion
if grep -qiE "insufficient_quota|quota|rate[._]limit|429|too many requests|overloaded" "$_out" 2>/dev/null; then
    _notif_msg="Job $6 stopped — quota exhausted"
elif [[ "$_ec" -ne 0 ]]; then
    _notif_msg="Job $6 failed"
else
    _notif_msg="Job $6 finished"
fi
case "$(uname -s)" in
    Darwin) osascript -e "display notification \"$_notif_msg\" with title \"TIAN\"" 2>/dev/null || true ;;
    Linux)  command -v notify-send &>/dev/null && DISPLAY="${DISPLAY:-:0}" notify-send -t 8000 "TIAN" "$_notif_msg" 2>/dev/null || true ;;
esac
# Copy output to user-specified file if requested
_output_path="${10:-}"
[[ -n "$_output_path" ]] && cp "$_out" "$_output_path" 2>/dev/null || true
' -- "$cmd" "$flag" "$prompt" "$out_file" "$JOBS_FILE" "$job_id" "$schedule_name" "$TIAN_DIR" "$forced_backend_id" "$output_path" &>/dev/null &
        local pid=$!
        python3 - "$JOBS_FILE" "$job_id" "$prompt" "$cmd" "$pid" "$job_name" "$schedule_name" "$forced_backend_id" <<'PYEOF'
import json, sys
from datetime import datetime
jobs_file, jid, prompt, cmd, pid, job_name, schedule_name, forced_backend = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), sys.argv[6], sys.argv[7], sys.argv[8]
with open(jobs_file) as fh:
    jobs = json.load(fh)
entry = {"id": jid, "name": job_name or jid, "prompt": prompt, "backend": cmd,
         "scheduleName": schedule_name or "", "status": "running",
         "createdAt": datetime.now().isoformat(), "pid": pid}
if forced_backend:
    entry["forcedBackend"] = forced_backend
jobs.append(entry)
with open(jobs_file, 'w') as fh:
    json.dump(jobs, fh, indent=2)
PYEOF
        ok "Job started: $job_id"
        info "Check result with: bash tian-cli.sh jobs result $job_id"
        [[ -n "$output_path" ]] && info "Output will also be saved to: $output_path (when job completes)"
        if $watch; then
            echo ""
            info "Watching live output (Ctrl+C to stop watching; job continues)..."
            rule
            _watch_job "$job_id"
            return $?
        fi
    else
        if [[ -n "$forced_backend_id" ]]; then
            rule
            "$cmd" $flag "$prompt" 2>&1 | tee "$out_file" || true
            rule
        else
            local primary_cmd="$cmd"
            while IFS='|' read -r r_cmd r_flag _bid r_name; do
                [[ -z "$r_cmd" ]] && continue
                [[ "$r_cmd" == "$primary_cmd" ]] || warn "Falling back to $r_name (quota/rate-limit on previous backend)..."
                rule
                # r_flag may be empty or multi-word; unquoted expansion handles both correctly
                "$r_cmd" $r_flag "$prompt" 2>&1 | tee "$out_file" || true
                rule
                local out_text; out_text=$(cat "$out_file" 2>/dev/null || true)
                is_quota_error "$out_text" || break
                warn "$r_name: quota or rate limit — trying next backend..."
            done < <(all_backends)
        fi
        if [[ -n "$output_path" ]]; then
            cp "$out_file" "$output_path" && ok "Result saved to: $output_path" \
                || warn "Could not save result to '$output_path'"
        fi
    fi
}

cmd_jobs() {
    local sub="${1:-}"; shift || true
    ensure_dirs
    sync_job_statuses
    case "$sub" in
        result)
            local id="${1:-}"; [[ -z "$id" ]] && fail "Usage: jobs result <job-id>"
            local f="$TASKS_DIR/$id.txt"
            [[ -f "$f" ]] || fail "Job '$id' not found."
            local stop_reason; stop_reason=$(_get_job_stop_reason "$id")
            if [[ "$stop_reason" == "quota_exhausted" ]]; then
                echo ""
                echo -e "${YELLOW}  [!!] This job stopped because the API quota or rate limit was exhausted.${RESET}"
                echo -e "${DIM}       The AI backend ran out of credits or hit its usage cap mid-task.${RESET}"
                echo -e "${DIM}       Options: wait for your quota to reset, upgrade your API plan,${RESET}"
                echo -e "${DIM}       or install a second backend (e.g. Ollama) for free local fallback.${RESET}"
                echo -e "${DIM}       Run tian-cli doctor to check your current key and quota status.${RESET}"
                echo -e "${DIM}       Once ready, retry this job with: tian-cli jobs retry $id${RESET}"
                echo ""
                rule
            fi
            cat "$f"
            ;;
        tail)
            local id="${1:-}"; [[ -z "$id" ]] && fail "Usage: jobs tail <job-id>"
            local f="$TASKS_DIR/$id.txt"
            [[ -f "$f" ]] || fail "Job '$id' not found."
            local status; status=$(_get_job_status "$id")
            if [[ "$status" == "running" ]]; then
                info "Job $id is still running — streaming output (auto-stops when finished; Ctrl+C to stop watching)..."
                rule
                _watch_job "$id"
            else
                info "Job $id status: $status"
                cat "$f"
            fi
            ;;
        stop)
            local target="${1:-}"
            [[ -n "$target" ]] || target="--all"
            stop_jobs "$target"
            ;;
        retry)
            local id="${1:-}"; [[ -z "$id" ]] && fail "Usage: jobs retry <job-id>"
            local orig_prompt orig_name orig_schedule orig_backend
            orig_prompt=$(python3 - "$JOBS_FILE" "$id" <<'PYEOF'
import json, sys
jobs = json.load(open(sys.argv[1]))
j = next((x for x in jobs if x.get('id') == sys.argv[2]), None)
if not j: sys.exit(1)
print(j.get('prompt', ''))
PYEOF
) || fail "Job '$id' not found."
            [[ -z "$orig_prompt" ]] && fail "Job '$id' has no recorded prompt."
            orig_name=$(python3 -c "
import json,sys
j=next((x for x in json.load(open(sys.argv[1])) if x.get('id')==sys.argv[2]),{})
print(j.get('name','') or '')
" "$JOBS_FILE" "$id")
            orig_schedule=$(python3 -c "
import json,sys
j=next((x for x in json.load(open(sys.argv[1])) if x.get('id')==sys.argv[2]),{})
print(j.get('scheduleName','') or '')
" "$JOBS_FILE" "$id")
            orig_backend=$(python3 -c "
import json,sys
j=next((x for x in json.load(open(sys.argv[1])) if x.get('id')==sys.argv[2]),{})
print(j.get('forcedBackend','') or '')
" "$JOBS_FILE" "$id")
            info "Retrying prompt from job $id..."
            local retry_args=(-b)
            [[ -n "$orig_name"     ]] && retry_args+=(--job-name      "$orig_name")
            [[ -n "$orig_schedule" ]] && retry_args+=(--schedule-name "$orig_schedule")
            [[ -n "$orig_backend"  ]] && retry_args+=(--backend       "$orig_backend")
            cmd_run "$orig_prompt" "${retry_args[@]}"
            ;;
        clear)
            local _clear_old_days="" _clear_dry_run=false
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    --old)
                        _clear_old_days="${2:-}"
                        [[ "$_clear_old_days" =~ ^[0-9]+$ ]] || fail "Usage: jobs clear --old <days>"
                        shift 2
                        ;;
                    --dry-run) _clear_dry_run=true; shift ;;
                    *) shift ;;
                esac
            done
            local _dry_flag; $_clear_dry_run && _dry_flag=1 || _dry_flag=0
            python3 - "$JOBS_FILE" "$TASKS_DIR" "${_clear_old_days:-}" "$_dry_flag" <<'PYEOF'
import json, sys, os, glob
from datetime import datetime, timezone

jobs_file, tasks_dir, old_days_str, dry_run_flag = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
dry_run = (dry_run_flag == "1")
old_days = int(old_days_str) if old_days_str else None

now = datetime.now(timezone.utc)

with open(jobs_file) as fh:
    jobs = json.load(fh)

to_remove = []
for j in jobs:
    if j.get('status') == 'running':
        continue
    if old_days is not None:
        created_str = j.get('createdAt', '')
        if created_str:
            try:
                created = datetime.fromisoformat(created_str.replace('Z', '+00:00'))
                if created.tzinfo is None:
                    created = created.replace(tzinfo=timezone.utc)
                age_days = (now - created).days
                if age_days < old_days:
                    continue
            except ValueError:
                pass
    to_remove.append(j)

if dry_run:
    if not to_remove:
        print("  Nothing to clear.")
    else:
        print(f"  Would clear {len(to_remove)} job(s) (--dry-run, nothing deleted):")
        for j in to_remove:
            created = j.get('createdAt', 'unknown date')[:10]
            prompt = (j.get('prompt') or '')[:50]
            print(f"    [{j['id']}] {created}  {j.get('status','?')}  {prompt}{'…' if len(j.get('prompt',''))>50 else ''}")
else:
    remove_ids = {j['id'] for j in to_remove}
    keep = [j for j in jobs if j['id'] not in remove_ids]
    for j in to_remove:
        for f in glob.glob(f"{tasks_dir}/{j['id']}*"):
            os.remove(f)
    with open(jobs_file, 'w') as fh:
        json.dump(keep, fh, indent=2)
    if old_days is not None:
        print(f"  Cleared {len(to_remove)} job(s) older than {old_days} day(s).")
    else:
        print(f"  Cleared {len(to_remove)} completed job(s).")
PYEOF
            ;;
        *)
            ensure_dirs
            python3 - "$JOBS_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    jobs = json.load(fh)
if not jobs:
    print("  No jobs yet. Run: bash tian-cli.sh run \"your task\"")
else:
    print(f"\n  {'ID':<30} {'STATUS':<10} PROMPT")
    print("  " + "─"*70)
    STATUS_COLORS = {
        'running': '\033[0;36m',
        'done':    '\033[0;32m',
        'failed':  '\033[0;31m',
        'stopped': '\033[1;33m',
        'quota':   '\033[0;35m',
    }
    RESET = '\033[0m'
    has_quota = False
    for j in reversed(jobs[-20:]):
        jid        = j.get('id', '?')[:28]
        status_raw = j.get('status', '?')
        is_quota   = j.get('stopReason') == 'quota_exhausted'
        if is_quota:
            has_quota   = True
            label       = 'QUOTA'
            color       = STATUS_COLORS['quota']
        else:
            label       = status_raw.upper()
            color       = STATUS_COLORS.get(status_raw, '')
        status_str = f"{color}{label:<10}{RESET}" if color else f"{label:<10}"
        prompt     = j.get('prompt', '')[:50]
        print(f"  {jid:<30} {status_str} {prompt}...")
    print()
    if has_quota:
        print(f"  \033[0;35m[!!]\033[0m QUOTA = API quota or rate limit exhausted.")
        print(f"  \033[2m     Wait for your quota to reset, upgrade your plan, or switch backends.\033[0m")
        print(f"  \033[2m     Diagnose with: tian-cli doctor\033[0m")
        print(f"  \033[2m     Retry a stopped job with: tian-cli jobs retry <job-id>\033[0m")
        print()
PYEOF
            ;;
    esac
}

# ── Schedule helpers ───────────────────────────────────────────────────────────

# Convert a day name (SUN MON TUE WED THU FRI SAT, case-insensitive) to the
# cron/launchd weekday integer (0=Sun … 6=Sat). Accepts full names too.
_day_name_to_num() {
    local d; d=$(echo "${1:-MON}" | tr '[:lower:]' '[:upper:]' | cut -c1-3)
    case "$d" in
        SUN) echo 0 ;;
        MON) echo 1 ;;
        TUE) echo 2 ;;
        WED) echo 3 ;;
        THU) echo 4 ;;
        FRI) echo 5 ;;
        SAT) echo 6 ;;
        *) echo "1" ;;  # fallback to Monday
    esac
}

# Expand named presets and return a normalised comma-separated list of 3-letter
# day abbreviations in upper case.  Examples:
#   weekdays  → MON,TUE,WED,THU,FRI
#   weekends  → SAT,SUN
#   MON,wed,FRI → MON,WED,FRI
_expand_days() {
    local raw; raw=$(echo "${1:-MON}" | tr '[:lower:]' '[:upper:]')
    case "$raw" in
        WEEKDAYS|WORKDAYS) echo "MON,TUE,WED,THU,FRI" ;;
        WEEKENDS)          echo "SAT,SUN" ;;
        EVERYDAY|DAILY)    echo "SUN,MON,TUE,WED,THU,FRI,SAT" ;;
        *)
            # Normalise to comma-separated 3-char abbreviations
            local result="" IFS_SAVE="$IFS"
            IFS=','
            for d in $raw; do
                IFS="$IFS_SAVE"
                d=$(echo "$d" | tr -d ' ' | cut -c1-3)
                result="${result:+$result,}$d"
                IFS=','
            done
            IFS="$IFS_SAVE"
            echo "$result"
            ;;
    esac
}

# Convert a (possibly multi-day) day spec to a cron weekday field.
# "MON"          → "1"
# "MON,WED,FRI"  → "1,3,5"
# "weekdays"     → "1,2,3,4,5"
_days_to_cron_field() {
    local expanded nums="" IFS_SAVE="$IFS"
    expanded=$(_expand_days "${1:-MON}")
    IFS=','
    for d in $expanded; do
        IFS="$IFS_SAVE"
        local n; n=$(_day_name_to_num "$d")
        nums="${nums:+$nums,}$n"
        IFS=','
    done
    IFS="$IFS_SAVE"
    echo "$nums"
}

# Build a launchd StartCalendarInterval XML block for one or more days.
# For a single day produces a <dict>; for multiple days produces an <array> of
# <dict> entries — both are valid launchd plist formats.
_days_to_launchd_block() {
    local expanded hour="$2" minute="$3" IFS_SAVE="$IFS"
    expanded=$(_expand_days "${1:-MON}")

    local day_count=0 IFS_SAVE2="$IFS"
    IFS=','
    for _d in $expanded; do ((day_count++)) || true; done
    IFS="$IFS_SAVE2"

    if [[ "$day_count" -eq 1 ]]; then
        local n; n=$(_day_name_to_num "$expanded")
        echo "<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>${n}</integer><key>Hour</key><integer>${hour}</integer><key>Minute</key><integer>${minute}</integer></dict>"
    else
        local entries=""
        IFS=','
        for d in $expanded; do
            IFS="$IFS_SAVE"
            local n; n=$(_day_name_to_num "$d")
            entries="${entries}
        <dict><key>Weekday</key><integer>${n}</integer><key>Hour</key><integer>${hour}</integer><key>Minute</key><integer>${minute}</integer></dict>"
            IFS=','
        done
        IFS="$IFS_SAVE"
        echo "<key>StartCalendarInterval</key><array>${entries}
    </array>"
    fi
}

_schedule_add_linux() {
    local name="$1" prompt="$2" time="$3" repeat="$4" day="${5:-MON}"
    local hour minute cron_expr
    hour=$(echo "$time" | cut -d: -f1)
    minute=$(echo "$time" | cut -d: -f2)

    local job_cmd="bash '$TIAN_DIR/tian-cli.sh' schedule run '$name'"

    case "$repeat" in
        hourly) cron_expr="0 * * * *" ;;
        daily)  cron_expr="$minute $hour * * *" ;;
        weekly) cron_expr="$minute $hour * * $(_days_to_cron_field "$day")" ;;
        once)
            # Write a self-removing wrapper: runs the task then deletes its own
            # cron entry so it fires exactly once rather than becoming recurring.
            cron_expr="$minute $hour * * *"
            local once_script="$HOME/.tian/once-${name}.sh"
            cat > "$once_script" <<ONCESCRIPT
#!/usr/bin/env bash
bash '$TIAN_DIR/tian-cli.sh' schedule run '$name'
( crontab -l 2>/dev/null | grep -vF "# tian-$name" ) | crontab - 2>/dev/null || true
rm -f '$once_script'
ONCESCRIPT
            chmod +x "$once_script"
            job_cmd="bash '$once_script'"
            ;;
        *)      cron_expr="$minute $hour * * *" ;;
    esac

    local job_line="$cron_expr  $job_cmd  # tian-$name"

    # Remove existing entry for this name then append new one
    ( crontab -l 2>/dev/null | grep -vF "# tian-$name" ; echo "$job_line" ) | crontab -

    python3 - "$SCHEDULES_FILE" "$name" "$prompt" "$time" "$repeat" "$day" <<'PYEOF'
import json, sys
from datetime import datetime
sf, name, prompt, time, repeat, day = sys.argv[1:]
with open(sf) as fh:
    schedules = json.load(fh)
schedules = [s for s in schedules if s.get('name') != name]
entry = {"name": name, "prompt": prompt, "time": time, "repeat": repeat,
         "createdAt": datetime.now().isoformat()}
if repeat == "weekly" and day:
    entry["dayOfWeek"] = day.upper()
with open(sf, 'w') as fh:
    json.dump(schedules + [entry], fh, indent=2)
PYEOF
    ok "Schedule '$name' created ($repeat at $time) via crontab."
    info "Results will appear in: bash tian-cli.sh jobs"

    if ! cron_running; then
        local platform; platform=$(detect_platform)
        echo ""
        warn "Cron daemon is NOT running — this schedule will not fire until you start it."
        while IFS= read -r line; do
            [[ -n "$line" ]] && info "$line"
        done < <(cron_fix_hint "$platform")
    fi
}

_schedule_add_macos() {
    local name="$1" prompt="$2" time="$3" repeat="$4" day="${5:-MON}"
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_label="com.tian.$name"
    local plist_file="$plist_dir/$plist_label.plist"
    mkdir -p "$plist_dir"

    local hour; hour=$(echo "$time" | cut -d: -f1 | sed 's/^0//')
    local minute; minute=$(echo "$time" | cut -d: -f2 | sed 's/^0//')
    # sed can turn "00" into "" — ensure at least "0"
    hour="${hour:-0}"; minute="${minute:-0}"

    local interval_block program_args
    case "$repeat" in
        hourly) interval_block="<key>StartInterval</key><integer>3600</integer>" ;;
        daily)  interval_block="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
        weekly) interval_block="$(_days_to_launchd_block "$day" "$hour" "$minute")" ;;
        once)
            # Fire at the specified time exactly once: use a self-removing wrapper
            # script so launchd doesn't repeat the job on subsequent days.
            interval_block="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>"
            local once_script="$HOME/.tian/once-${name}.sh"
            cat > "$once_script" <<ONCESCRIPT
#!/usr/bin/env bash
bash '$TIAN_DIR/tian-cli.sh' schedule run '$name'
launchctl unload '$plist_file' 2>/dev/null || launchctl bootout "gui/\$(id -u)" '$plist_file' 2>/dev/null || true
rm -f '$plist_file' '$once_script'
ONCESCRIPT
            chmod +x "$once_script"
            program_args="    <string>/bin/bash</string>
        <string>$once_script</string>"
            ;;
        *)      interval_block="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
    esac

    # For non-once repeats, ProgramArguments calls tian-cli directly
    if [[ "$repeat" != "once" ]]; then
        program_args="    <string>/bin/bash</string>
        <string>$TIAN_DIR/tian-cli.sh</string>
        <string>schedule</string>
        <string>run</string>
        <string>$name</string>"
    fi

    cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plist_label</string>
    <key>ProgramArguments</key>
    <array>
        $program_args
    </array>
    <key>StandardOutPath</key>
    <string>$HOME/.tian/tasks/schedule-$name.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.tian/tasks/schedule-$name.err</string>
    $interval_block
</dict>
</plist>
PLIST

    launchctl load "$plist_file" 2>/dev/null || launchctl bootstrap "gui/$(id -u)" "$plist_file" 2>/dev/null || true

    python3 - "$SCHEDULES_FILE" "$name" "$prompt" "$time" "$repeat" "$plist_file" "$day" <<'PYEOF'
import json, sys
from datetime import datetime
sf, name, prompt, time, repeat, plist, day = sys.argv[1:]
with open(sf) as fh:
    schedules = json.load(fh)
schedules = [s for s in schedules if s.get('name') != name]
entry = {"name": name, "prompt": prompt, "time": time, "repeat": repeat,
         "plistFile": plist, "createdAt": datetime.now().isoformat()}
if repeat == "weekly" and day:
    entry["dayOfWeek"] = day.upper()
with open(sf, 'w') as fh:
    json.dump(schedules + [entry], fh, indent=2)
PYEOF
    ok "Schedule '$name' created ($repeat at $time) via launchd."
    info "Results will appear in: bash tian-cli.sh jobs"
}

_schedule_remove_linux() {
    local name="$1"
    ( crontab -l 2>/dev/null | grep -vF "# tian-$name" ) | crontab - 2>/dev/null || true
    rm -f "$HOME/.tian/once-${name}.sh"
}

_schedule_remove_macos() {
    local plist_file="$1"
    if [[ -n "$plist_file" && -f "$plist_file" ]]; then
        launchctl unload "$plist_file" 2>/dev/null || launchctl bootout "gui/$(id -u)" "$plist_file" 2>/dev/null || true
        rm -f "$plist_file"
    fi
}

# Built-in schedule templates.  Format: name|time|repeat|day|description|prompt
_tian_sched_templates() {
    cat <<'TEMPLATES'
morning-briefing|08:00|daily|MON|Morning priority check|Start my day well: suggest exactly 3 clear priorities for me to focus on today, note any recurring commitments I should not forget, and add a one-line motivational nudge to help me get started with energy.
evening-digest|18:00|daily|MON|End-of-day wrap-up|Give me a concise end-of-day reflection template: what I likely accomplished today, what should carry over to tomorrow, and one concrete thing I can improve tomorrow. Keep it brief and action-oriented.
weekly-review|17:00|weekly|FRI|Weekly retrospective|Create a structured weekly review for me: celebrate this week's wins, list any unfinished tasks to roll into next week, share one lesson worth remembering, and suggest my top 3 priorities for next week.
inbox-triage|09:00|daily|MON|Email inbox triage guide|Walk me through email triage. Sort messages into four buckets — Act Now (urgent reply needed today), Schedule (respond within 48 hours), Delegate (forward to someone else), Archive (no action needed) — and give me a one-line template reply for each bucket.
meeting-prep|08:30|daily|MON|Daily meeting preparation|Help me prepare for any meetings today. Suggest 5 sharp questions I could ask in a typical team meeting, a 3-step pre-meeting checklist (agenda, materials, goal), and one tip for keeping meetings on time.
focus-reset|14:00|daily|MON|Afternoon focus reset|It is early afternoon — help me reset. Remind me to review this morning's priorities, assess which are done versus still open, then recommend: should I push through current tasks or reprioritise for the remaining hours of the day?
TEMPLATES
}

cmd_schedule() {
    local sub="${1:-list}"; shift || true
    local platform; platform=$(detect_platform)

    case "$sub" in
        add)
            local name="${1:-}"; local prompt="${2:-}"; local time="${3:-08:00}"; local repeat="${4:-daily}"
            # Consume positional args before scanning for flags
            shift 4 2>/dev/null || true
            local day="MON"
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    --day|-d) day="${2:-MON}"; shift 2 ;;
                    *) shift ;;
                esac
            done
            [[ -z "$name" || -z "$prompt" ]] && fail "Usage: schedule add <name> \"prompt\" [HH:MM] [daily|weekly|hourly|once] [--day MON,WED,FRI]"
            [[ ! "$time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && fail "Invalid time '$time'. Use HH:MM format (e.g. 08:30)."
            [[ ! "$repeat" =~ ^(daily|weekly|hourly|once)$ ]] && fail "Invalid repeat '$repeat'. Choose: daily, weekly, hourly, once."
            # Expand named presets then validate each individual day token
            day=$(_expand_days "$day")
            local _bad_day=""
            local _IFS_SAVE="$IFS"; IFS=','
            for _d in $day; do
                IFS="$_IFS_SAVE"
                [[ ! "$_d" =~ ^(SUN|MON|TUE|WED|THU|FRI|SAT)$ ]] && { _bad_day="$_d"; break; }
                IFS=','
            done
            IFS="$_IFS_SAVE"
            [[ -n "$_bad_day" ]] && fail "Invalid day '$_bad_day'. Use: SUN MON TUE WED THU FRI SAT (comma-separated for multiple days, or: weekdays, weekends)"
            ensure_dirs
            if [[ "$platform" == "linux" || "$platform" == "wsl" ]]; then
                _schedule_add_linux "$name" "$prompt" "$time" "$repeat" "$day"
            elif [[ "$platform" == "macos" ]]; then
                _schedule_add_macos "$name" "$prompt" "$time" "$repeat" "$day"
            else
                fail "schedule add is not supported on this platform ($platform)."
            fi
            ;;

        list)
            ensure_dirs
            local sched_count=0
            sched_count=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$SCHEDULES_FILE" 2>/dev/null || echo 0)
            if [[ "$sched_count" -gt 0 && ( "$platform" == "linux" || "$platform" == "wsl" ) ]] && ! cron_running; then
                warn "cron daemon is not running — none of these schedules will fire until you start it."
                while IFS= read -r line; do
                    [[ -n "$line" ]] && info "$line"
                done < <(cron_fix_hint "$platform")
                echo ""
            fi
            python3 - "$SCHEDULES_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    schedules = json.load(fh)
if not schedules:
    print("  No schedules. Create one with: bash tian-cli.sh schedule add <name> \"prompt\" HH:MM daily")
else:
    print(f"\n  {'NAME':<22} {'REPEAT':<14} {'TIME':<8} PROMPT")
    print("  " + "─"*74)
    for s in schedules:
        repeat = s['repeat']
        if repeat == 'weekly' and s.get('dayOfWeek'):
            repeat = f"weekly({s['dayOfWeek']})"
        print(f"  {s['name']:<22} {repeat:<14} {s['time']:<8} {s['prompt'][:40]}{'...' if len(s.get('prompt',''))>40 else ''}")
    print()
PYEOF
            ;;

        run)
            local name="${1:-}"; [[ -z "$name" ]] && fail "Usage: schedule run <name>"
            ensure_dirs
            local prompt
            prompt=$(python3 - "$SCHEDULES_FILE" "$name" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    s = json.load(fh)
e = next((x for x in s if x['name'] == sys.argv[2]), None)
print(e['prompt'] if e else '')
PYEOF
)
            [[ -z "$prompt" ]] && fail "Schedule '$name' not found."
            info "Running '$name' now..."
            cmd_run "$prompt" -b --job-name "$name" --schedule-name "$name"
            ;;

        remove)
            local name="${1:-}"; [[ -z "$name" ]] && fail "Usage: schedule remove <name>"
            ensure_dirs
            local plist_file=""
            if [[ "$platform" == "macos" ]]; then
                plist_file=$(python3 - "$SCHEDULES_FILE" "$name" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    s = json.load(fh)
e = next((x for x in s if x['name'] == sys.argv[2]), None)
print(e.get('plistFile', '') if e else '')
PYEOF
)
                _schedule_remove_macos "$plist_file"
            else
                _schedule_remove_linux "$name"
            fi
            python3 - "$SCHEDULES_FILE" "$name" <<'PYEOF'
import json, sys
sf, name = sys.argv[1], sys.argv[2]
with open(sf) as fh:
    schedules = [s for s in json.load(fh) if s.get('name') != name]
with open(sf, 'w') as fh:
    json.dump(schedules, fh, indent=2)
PYEOF
            ok "Schedule '$name' removed."
            ;;

        templates)
            local tsub="${1:-list}"; shift || true
            case "$tsub" in
                list|"")
                    echo ""
                    echo -e "${BOLD}  Available schedule templates${RESET}"
                    echo ""
                    printf "  %-22s %-10s %-14s %s\n" "NAME" "TIME" "REPEAT" "DESCRIPTION"
                    printf "  %s\n" "$(printf '%74s' | tr ' ' '─')"
                    while IFS='|' read -r tname ttime trepeat tday tdesc _tprompt; do
                        local extra=""
                        [[ "$trepeat" == "weekly" ]] && extra=" ($tday)"
                        printf "  %-22s %-10s %-14s %s\n" "$tname" "$ttime" "${trepeat}${extra}" "$tdesc"
                    done < <(_tian_sched_templates)
                    echo ""
                    echo -e "  ${DIM}Apply a template:       tian-cli schedule templates apply <name>${RESET}"
                    echo -e "  ${DIM}Custom time:            tian-cli schedule templates apply <name> --time HH:MM${RESET}"
                    echo -e "  ${DIM}Edit after applying:    tian-cli schedule remove <name>, then schedule add${RESET}"
                    echo ""
                    ;;
                apply)
                    local tname="${1:-}"; shift || true
                    [[ -z "$tname" ]] && fail "Usage: schedule templates apply <name> [--time HH:MM]"
                    local custom_time=""
                    while [[ $# -gt 0 ]]; do
                        case "${1:-}" in
                            --time|-t) custom_time="${2:-}"; shift 2 ;;
                            *) shift ;;
                        esac
                    done

                    local row
                    row=$(_tian_sched_templates | grep "^${tname}|") \
                        || fail "Template '$tname' not found. Run: tian-cli schedule templates"

                    local ttime trepeat tday tdesc tprompt
                    IFS='|' read -r _ ttime trepeat tday tdesc tprompt <<< "$row"
                    [[ -n "$custom_time" ]] && ttime="$custom_time"

                    ensure_dirs
                    local existing
                    existing=$(python3 - "$SCHEDULES_FILE" "$tname" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    s = json.load(fh)
print('1' if any(x['name'] == sys.argv[2] for x in s) else '0')
PYEOF
)
                    [[ "$existing" == "1" ]] && \
                        fail "A schedule named '$tname' already exists. Remove it first: tian-cli schedule remove $tname"

                    info "Applying template: $tdesc"
                    info "  Prompt: ${tprompt:0:72}..."
                    echo ""
                    cmd_schedule add "$tname" "$tprompt" "$ttime" "$trepeat" --day "$tday"
                    ;;
                *) fail "Usage: schedule templates [list|apply <name>]" ;;
            esac
            ;;

        *) fail "Usage: schedule add|list|run|remove|templates" ;;
    esac
}

_update_tian_self() {
    # Only self-update when running from the standard install location created by install.sh.
    # Development checkouts (e.g. /home/.../code/TIAN) are left untouched.
    local default_install="$HOME/.tian/repo"
    [[ "$TIAN_DIR" != "$default_install" ]] && return 0

    info "Checking for TIAN script updates..."

    if ! command -v curl &>/dev/null; then
        info "curl not available — skipping TIAN self-update"
        return 0
    fi

    local tmp_dir; tmp_dir="$(mktemp -d)"
    local archive="$tmp_dir/tian.tar.gz"

    if ! curl -fsSL "https://github.com/jkcsxw/TIAN/archive/refs/heads/main.tar.gz" \
               -o "$archive" 2>/dev/null; then
        info "TIAN self-update: could not reach GitHub — skipping"
        rm -rf "$tmp_dir"
        return 0
    fi

    mkdir -p "$tmp_dir/extracted"
    if ! tar -xzf "$archive" -C "$tmp_dir/extracted" 2>/dev/null; then
        warn "TIAN self-update: failed to extract archive — skipping"
        rm -rf "$tmp_dir"
        return 0
    fi

    local extracted_dir
    extracted_dir="$(find "$tmp_dir/extracted" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    if [[ -z "$extracted_dir" ]]; then
        warn "TIAN self-update: unexpected archive layout — skipping"
        rm -rf "$tmp_dir"
        return 0
    fi

    # Overwrite scripts in place.  User data (jobs, tasks, schedules) lives in
    # ~/.tian/ — not inside ~/.tian/repo/ — so a plain cp -r is safe.
    cp -r "$extracted_dir/." "$TIAN_DIR/"
    chmod +x "$TIAN_DIR/tian-cli.sh" "$TIAN_DIR/mac/setup.sh" \
              "$TIAN_DIR/mac/tian-cli-bash.sh" "$TIAN_DIR/setup.sh" 2>/dev/null || true
    rm -rf "$tmp_dir"
    ok "TIAN scripts updated to latest version from GitHub"
}

cmd_update() {
    hdr "TIAN Update — Upgrade TIAN & AI Backends"

    # --- Step 1: self-update TIAN scripts --------------------------------
    echo -e "${BOLD}  TIAN scripts${RESET}"
    _update_tian_self
    echo ""

    # --- Step 2: upgrade AI backend CLIs via npm -------------------------
    echo -e "${BOLD}  AI backend CLIs${RESET}"
    if ! command -v npm &>/dev/null; then
        warn "npm not found. Install Node.js first: https://nodejs.org"
        return 1
    fi

    local updated=0 skipped=0 failed=0

    # Read backends from catalog and update npm-installed ones
    while IFS='|' read -r bid bname bcmd bnpm binstall; do
        if [[ -z "$bnpm" ]]; then
            if [[ "$binstall" == "desktop-app" ]]; then
                info "$(printf '%-28s' "$bname") desktop app — check for updates in the app itself"
                ((skipped++)) || true
            elif [[ "$binstall" == "local-cli" ]]; then
                info "$(printf '%-28s' "$bname") local install — update manually"
                ((skipped++)) || true
            fi
            continue
        fi

        if [[ -z "$bcmd" ]] || ! command -v "$bcmd" &>/dev/null; then
            info "$(printf '%-28s' "$bname") not installed — skipping"
            ((skipped++)) || true
            continue
        fi

        local ver_before=""
        ver_before=$("$bcmd" --version 2>/dev/null || true)

        info "Updating $bname ($bnpm)..."

        if npm install -g "${bnpm}@latest" >/dev/null 2>&1; then
            local ver_after=""
            ver_after=$("$bcmd" --version 2>/dev/null || true)
            if [[ -n "$ver_before" && -n "$ver_after" && "$ver_before" != "$ver_after" ]]; then
                ok "$(printf '%-28s' "$bname") $ver_before  →  $ver_after"
            else
                ok "$(printf '%-28s' "$bname") already up to date ($ver_after)"
            fi
            ((updated++)) || true
        else
            warn "$(printf '%-28s' "$bname") update failed — try: npm install -g ${bnpm}@latest"
            ((failed++)) || true
        fi
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    print('|'.join([
        b.get('id',''),
        b.get('displayName',''),
        b.get('cliCommand',''),
        b.get('npmPackage',''),
        b.get('installType','cli'),
    ]))
PYEOF
)

    echo ""
    rule
    if [[ $failed -gt 0 ]]; then
        warn "Updated: $updated   Skipped: $skipped   Failed: $failed"
    else
        ok "Updated: $updated   Skipped: $skipped   Failed: $failed"
    fi
    echo ""
}

# Configure an MCP server for a known backend, without prompting when --yes is set.
# Returns 0 on success, 1 if a required env var is missing in --yes mode (so we can warn).
install_mcp_for_backend() {
    local server_id="${1:-}" backend_id="${2:-}" assume_yes="${3:-false}"
    local server_row
    server_row=$(find_mcp_by_id "$server_id") || { warn "Unknown MCP id '$server_id' — skipping."; return 1; }
    local _sid display_name _ reqs
    IFS='|' read -r _sid display_name _ reqs <<< "$server_row"

    if [[ -n "$reqs" ]]; then
        local missing=()
        IFS=',' read -ra req_names <<< "$reqs"
        for rn in "${req_names[@]}"; do
            [[ -n "$rn" && -z "${!rn:-}" ]] && missing+=("$rn")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            if [[ "$assume_yes" == "true" ]]; then
                warn "$display_name needs env var(s): ${missing[*]} — skipping. Add later with: tian-cli add mcp $server_id"
                return 1
            fi
        fi
    fi
    add_mcp_server "$server_id" "$backend_id"
}

write_bash_launcher() {
    local backend_name="${1:-}" launch_cmd="${2:-}"
    local launcher="$TIAN_DIR/launcher.sh"
    cat > "$launcher" <<LAUNCHEOF
#!/usr/bin/env bash
source "\$HOME/.zshrc" 2>/dev/null || source "\$HOME/.bashrc" 2>/dev/null || source "\$HOME/.bash_profile" 2>/dev/null || true
echo "Starting $backend_name..."
$launch_cmd
LAUNCHEOF
    chmod +x "$launcher"
    ok "Launcher created: $launcher"
}

cmd_install() {
    local backend_id="" api_key="" mcp_csv="" skills_csv=""
    local assume_yes="false"
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            --backend) backend_id="${2:-}"; shift 2 ;;
            --key)     api_key="${2:-}";    shift 2 ;;
            --mcp)     mcp_csv="${2:-}";    shift 2 ;;
            --skills)  skills_csv="${2:-}"; shift 2 ;;
            -y|--yes)  assume_yes="true";   shift ;;
            -h|--help)
                cat <<EOF
Usage: tian-cli install --backend <id> [--key <api-key>] [--mcp <ids>] [--skills <ids>] [--yes]

Flags:
  --backend <id>     Required. AI backend id (run 'list backends' to see options).
  --key     <key>    API key. Saved to your shell profile. Omit to use --mcp 'default' or rely on an existing env var.
  --mcp     <ids>    Comma-separated MCP server ids. Use 'default' to use the backend's recommended set.
  --skills  <ids>    Comma-separated skill ids.
  --yes              Skip prompts. Missing required MCP env vars cause the MCP to be skipped (with a warning).
EOF
                return 0
                ;;
            *) shift ;;
        esac
    done

    [[ -n "$backend_id" ]] || fail "Missing --backend. Run: tian-cli list backends"

    local row
    row=$(find_backend_install_by_id "$backend_id") || fail "Unknown backend id '$backend_id'. Run: tian-cli list backends"
    local b_id b_name b_cmd b_npm b_envkey b_keyhint b_keyurl b_install b_launch b_setupnote b_supports_mcp b_default_mcp
    IFS='|' read -r b_id b_name b_cmd b_npm b_envkey b_keyhint b_keyurl b_install b_launch b_setupnote b_supports_mcp b_default_mcp <<< "$row"

    hdr "TIAN Install — $b_name"

    # ── Node.js / npm prerequisite (only required for npm-installed backends) ────
    if [[ -n "$b_npm" ]]; then
        if ! command -v node &>/dev/null; then
            fail "Node.js not found. Install it from https://nodejs.org or run: tian-cli setup"
        fi
        if ! command -v npm &>/dev/null; then
            fail "npm not found. Install Node.js first: https://nodejs.org"
        fi
        ok "Node.js $(node --version)"
    fi

    # ── API key ─────────────────────────────────────────────────────────────────
    if [[ -n "$b_envkey" ]]; then
        if [[ -z "$api_key" ]]; then
            local existing="${!b_envkey:-}"
            if [[ -n "$existing" ]]; then
                info "$b_envkey already set in environment — keeping existing value."
            elif [[ "$assume_yes" == "true" ]]; then
                if [[ "$b_install" == "desktop-app" ]]; then
                    info "No --key provided. $b_name can sign in via the desktop app instead."
                else
                    warn "No --key provided and $b_envkey not set. You can set it later with: export $b_envkey=..."
                fi
            else
                [[ -n "$b_keyhint" ]] && info "$b_envkey ($b_keyhint)"
                [[ -n "$b_keyurl" ]]  && info "Get it at: $b_keyurl"
                local _provider=""
                case "$b_envkey" in
                    ANTHROPIC_API_KEY) _provider="anthropic" ;;
                    OPENAI_API_KEY)    _provider="openai" ;;
                esac
                local _key_attempts=0
                while true; do
                    api_key=$(prompt_secret "$b_envkey")
                    ((_key_attempts++)) || true
                    if [[ -z "$api_key" ]]; then
                        warn "No key entered — you can set it later with: export $b_envkey=..."
                        break
                    fi
                    if [[ -n "$_provider" ]]; then
                        info "  Verifying key with API..."
                        if _verify_api_key "$_provider" "$api_key" "$b_keyurl"; then
                            break
                        else
                            if [[ "$_key_attempts" -ge 3 ]]; then
                                warn "3 failed attempts — saving key anyway. Fix it later with: export $b_envkey=<your-key>"
                                break
                            fi
                            printf "  Try again? [Y/n]: "
                            local _retry; read -r _retry </dev/tty
                            [[ "$_retry" =~ ^[Nn] ]] && break
                        fi
                    else
                        break
                    fi
                done
            fi
        fi
        if [[ -n "$api_key" ]]; then
            save_shell_env_var "$b_envkey" "$api_key"
            ok "$b_envkey saved to $(profile_file)"
        fi
    elif [[ -n "$b_setupnote" ]]; then
        info "$b_setupnote"
    fi

    # ── Install backend ─────────────────────────────────────────────────────────
    if [[ -n "$b_npm" ]]; then
        if [[ -n "$b_cmd" ]] && command -v "$b_cmd" &>/dev/null; then
            ok "$b_name already installed ($(command -v "$b_cmd"))"
        else
            info "Installing $b_name ($b_npm)..."
            if npm install -g "$b_npm"; then
                ok "$b_name installed."
            else
                fail "npm install -g $b_npm failed. Re-run with sudo, or fix npm permissions."
            fi
        fi
    elif [[ "$b_install" == "desktop-app" ]]; then
        info "$b_name is a desktop app — please install it manually if you haven't already."
    elif [[ "$b_install" == "local-cli" ]]; then
        info "$b_name uses a local CLI ($b_cmd). Install separately if not yet on PATH."
    fi

    # ── MCP servers ─────────────────────────────────────────────────────────────
    if [[ "$b_supports_mcp" == "1" ]]; then
        # 'default' expands to backend's defaultMcpServers
        if [[ "$mcp_csv" == "default" ]]; then
            mcp_csv="$b_default_mcp"
            [[ -n "$mcp_csv" ]] && info "Using default MCP set for $b_name: $mcp_csv"
        fi
        if [[ -n "$mcp_csv" ]]; then
            local mcp_ok=0 mcp_skipped=0
            IFS=',' read -ra MCP_IDS <<< "$mcp_csv"
            for mid in "${MCP_IDS[@]}"; do
                mid="$(echo "$mid" | tr -d '[:space:]')"
                [[ -z "$mid" ]] && continue
                if install_mcp_for_backend "$mid" "$b_id" "$assume_yes"; then
                    ((mcp_ok++)) || true
                else
                    ((mcp_skipped++)) || true
                fi
            done
            info "MCP servers configured: $mcp_ok, skipped: $mcp_skipped"
        fi
    elif [[ -n "$mcp_csv" ]]; then
        warn "$b_name does not support MCP — ignoring --mcp."
    fi

    # ── Skills ──────────────────────────────────────────────────────────────────
    if [[ -n "$skills_csv" ]]; then
        IFS=',' read -ra SKILL_IDS <<< "$skills_csv"
        for sid in "${SKILL_IDS[@]}"; do
            sid="$(echo "$sid" | tr -d '[:space:]')"
            [[ -z "$sid" ]] && continue
            install_skill "$sid" || warn "Skill '$sid' could not be installed."
        done
    fi

    # ── Launcher ────────────────────────────────────────────────────────────────
    if [[ -n "$b_cmd" ]]; then
        local launch="${b_launch:-$b_cmd}"
        write_bash_launcher "$b_name" "$launch"
    fi

    echo ""
    rule
    ok "Install complete for $b_name."
    if [[ -n "$b_cmd" ]]; then
        echo ""
        echo "  Verify with: $b_cmd  (or: bash launcher.sh)"
    fi
    echo "  Open a new terminal so the saved env vars are loaded."
    echo ""
}

# Make a lightweight API call to verify a key is accepted.
# provider: "anthropic" | "openai" | "" (unknown — skip silently)
# Returns 0 on success/skipped, 1 if key is rejected.
_verify_api_key() {
    local provider="${1:-}" key="${2:-}" url_hint="${3:-}"
    [[ -n "$provider" && -n "$key" ]] || return 0
    if ! command -v curl &>/dev/null; then
        info "  curl not found — skipping live key verification"
        return 0
    fi

    local endpoint http_status
    case "$provider" in
        anthropic)
            endpoint="https://api.anthropic.com/v1/models"
            http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
                -H "x-api-key: $key" \
                -H "anthropic-version: 2023-06-01" \
                "$endpoint" 2>/dev/null) || http_status="000"
            ;;
        openai)
            endpoint="https://api.openai.com/v1/models"
            http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
                -H "Authorization: Bearer $key" \
                "$endpoint" 2>/dev/null) || http_status="000"
            ;;
        *)
            return 0
            ;;
    esac

    case "$http_status" in
        200) ok "  Key accepted by API" ;;
        401) warn "  Key rejected (HTTP 401) — check for typos or regenerate at: $url_hint" ; return 1 ;;
        403) warn "  Key forbidden (HTTP 403) — key may lack required permissions" ; return 1 ;;
        429) info "  Rate limited (HTTP 429) — key looks valid but quota may be exhausted" ;;
        000) info "  Could not reach API (no network or DNS failure) — skipping live check" ;;
        *)   info "  Unexpected HTTP $http_status — could not verify key" ;;
    esac
}

# Validate a known MCP server credential by making a lightweight test API call.
# Returns 0 if valid or check skipped; returns 1 if credential is definitely invalid.
_validate_mcp_credential() {
    local var_name="${1:-}" key="${2:-}"
    [[ -n "$var_name" && -n "$key" ]] || return 0
    command -v curl &>/dev/null || return 0

    local http_status body ok_flag err_msg

    case "$var_name" in
        BRAVE_API_KEY)
            http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
                -H "X-Subscription-Token: $key" \
                "https://api.search.brave.com/res/v1/web/search?q=test&count=1" 2>/dev/null) \
                || http_status="000"
            case "$http_status" in
                200)     ok     "  Brave API key is valid" ;;
                401|403) warn   "  Brave API key is invalid (HTTP $http_status) — regenerate at https://api.search.brave.com/register"; return 1 ;;
                429)     info   "  Brave API rate limited (HTTP 429) — key is likely valid" ;;
                000)     info   "  Cannot reach Brave API — skipping credential check" ;;
                *)       info   "  Brave API returned HTTP $http_status" ;;
            esac
            ;;
        GITHUB_PERSONAL_ACCESS_TOKEN)
            http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
                -H "Authorization: Bearer $key" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/user" 2>/dev/null) \
                || http_status="000"
            case "$http_status" in
                200)     ok     "  GitHub token is valid" ;;
                401)     warn   "  GitHub token is invalid or expired (HTTP 401) — create a new one at https://github.com/settings/tokens"; return 1 ;;
                403)     warn   "  GitHub token lacks required permissions (HTTP 403) — check scopes at https://github.com/settings/tokens"; return 1 ;;
                000)     info   "  Cannot reach GitHub API — skipping credential check" ;;
                *)       info   "  GitHub API returned HTTP $http_status" ;;
            esac
            ;;
        SLACK_BOT_TOKEN)
            body=$(curl -s --max-time 5 \
                -H "Authorization: Bearer $key" \
                "https://slack.com/api/auth.test" 2>/dev/null) || body=""
            if [[ -z "$body" ]]; then
                info "  Cannot reach Slack API — skipping credential check"
            else
                ok_flag=$(echo "$body" | python3 -c \
                    "import json,sys; print('ok' if json.load(sys.stdin).get('ok') else 'fail')" \
                    2>/dev/null) || ok_flag="fail"
                if [[ "$ok_flag" == "ok" ]]; then
                    ok "  Slack bot token is valid"
                else
                    err_msg=$(echo "$body" | python3 -c \
                        "import json,sys; print(json.load(sys.stdin).get('error','unknown'))" \
                        2>/dev/null) || err_msg="unknown"
                    warn "  Slack bot token is invalid: $err_msg — check your Slack app at https://api.slack.com/apps"; return 1
                fi
            fi
            ;;
        POSTGRES_CONNECTION_STRING)
            if command -v psql &>/dev/null; then
                if PGCONNECT_TIMEOUT=3 psql "$key" -c "SELECT 1" &>/dev/null 2>&1; then
                    ok "  PostgreSQL connection string is valid"
                else
                    warn "  Cannot connect to PostgreSQL — check the connection string"; return 1
                fi
            else
                info "  psql not found — skipping PostgreSQL connection test"
            fi
            ;;
    esac
    return 0
}

cmd_doctor() {
    local fix=false
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            --fix|-f) fix=true; shift ;;
            *) shift ;;
        esac
    done

    hdr "TIAN Doctor — Setup Diagnostics${fix:+ (--fix mode)}"
    local platform; platform=$(detect_platform)
    case "$platform" in
        macos) info "Platform: macOS" ;;
        wsl)   info "Platform: Linux (WSL)" ;;
        linux) info "Platform: Linux" ;;
        *)     warn "Platform: unknown ($(uname -s))" ;;
    esac
    if $fix; then info "Auto-fix enabled — will attempt to resolve fixable issues automatically."; fi
    echo ""
    local issues=0
    local fixed=0

    echo -e "${BOLD}  Core dependencies${RESET}"
    if command -v node &>/dev/null; then
        local node_ver; node_ver=$(node --version)
        local node_major; node_major=$(echo "$node_ver" | sed 's/v\([0-9]*\).*/\1/')
        if [[ "$node_major" -ge 18 ]]; then
            ok "Node.js $node_ver"
        else
            warn "Node.js $node_ver — v18+ recommended"; info "  Fix: https://nodejs.org/en/download"
            ((issues++)) || true
        fi
    else
        warn "Node.js not found — required for MCP servers"; info "  Fix: https://nodejs.org/en/download"
        ((issues++)) || true
    fi
    command -v python3 &>/dev/null && ok "Python3 $(python3 --version 2>&1 | awk '{print $2}')" || { warn "Python3 not found"; ((issues++)) || true; }
    command -v npx    &>/dev/null && ok "npx $(npx --version 2>/dev/null || echo '?')" || { warn "npx not found — install Node.js"; ((issues++)) || true; }
    echo ""

    echo -e "${BOLD}  AI backends${RESET}"
    while IFS='|' read -r _status _name _npm; do
        [[ -z "$_name" ]] && continue
        if [[ "$_status" == "ok" ]]; then
            ok "$_name"
        elif $fix && [[ -n "$_npm" ]] && command -v npm &>/dev/null; then
            info "  Auto-fixing: installing $_name via npm..."
            if npm install -g "$_npm" 2>/dev/null; then
                ok "$_name — installed successfully"
                ((fixed++)) || true
            else
                warn "$_name — install failed; run manually: npm install -g $_npm"
                ((issues++)) || true
            fi
        else
            local _hint=""
            [[ -n "$_npm" ]] && _hint=" (fix: npm install -g $_npm)"
            warn "$_name not installed${_hint}"
            ((issues++)) || true
        fi
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    cmd = b.get('cliCommand', '')
    if not cmd: continue
    is_ok = subprocess.run(['which', cmd], capture_output=True).returncode == 0
    npm = b.get('npmPackage', '')
    print(f"{'ok' if is_ok else 'missing'}|{b['displayName']}|{npm}")
PYEOF
)
    echo ""

    echo -e "${BOLD}  API keys${RESET}"
    local _profile_file; _profile_file=$(profile_file)
    while IFS='|' read -r env provider url_hint installed; do
        [[ -n "$env" ]] || continue
        local actual_val="${!env:-}"
        if [[ -n "$actual_val" ]]; then
            ok "$env is set (${actual_val:0:8}...)"
            _verify_api_key "$provider" "$actual_val" "$url_hint" || ((issues++)) || true
        else
            # Check if the key exists in the shell profile but wasn't loaded into this session
            local in_profile=false
            if [[ -f "$_profile_file" ]] && grep -qE "export[[:space:]]+${env}[[:space:]]*=" "$_profile_file" 2>/dev/null; then
                in_profile=true
            fi
            if $in_profile; then
                warn "$env saved in $(basename "$_profile_file") but not active in this session"
                info "  Fix: open a new terminal, or run: source $_profile_file"
                ((issues++)) || true
            elif [[ "$installed" == "1" ]]; then
                warn "$env not set — get key: $url_hint"
                ((issues++)) || true
            else
                info "$env (backend not installed)"
            fi
        fi
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, os, subprocess, sys
c, seen = json.load(open(sys.argv[1])), set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', '')
    cmd = b.get('cliCommand', '')
    if not env or env in seen:
        continue
    seen.add(env)
    installed = '1' if (cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0) else '0'
    provider = 'anthropic' if 'ANTHROPIC' in env else ('openai' if 'OPENAI' in env else '')
    print(f"{env}|{provider}|{b.get('apiKeyUrl', 'see docs')}|{installed}")
PYEOF
)
    echo ""

    echo -e "${BOLD}  Config files${RESET}"
    while IFS='|' read -r label path; do
        [[ -n "$path" ]] || continue
        if [[ -f "$path" ]]; then
            TIAN_CHECK_PATH="$path" python3 -c "import json,os; json.load(open(os.environ['TIAN_CHECK_PATH']))" 2>/dev/null \
                && ok "$label config valid: $path" \
                || { warn "$label config has invalid JSON: $path"; ((issues++)) || true; }
        else
            info "$label config not found (optional): $path"
        fi
    done < <(python3 - "$CATALOG" "$platform" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys

catalog_path, platform, home, claude_desktop_cfg = sys.argv[1:5]
catalog = json.load(open(catalog_path))
seen = set()
for backend in catalog["backends"]:
    if not backend.get("supportsMcp", True):
        continue
    key = backend.get("mcpConfigTarget") or backend.get("mcpConfigPath") or ""
    if not key or key in seen:
        continue
    seen.add(key)
    target = backend.get("mcpConfigTarget") or ""
    custom = backend.get("mcpConfigPath") or ""
    if target == "claude_desktop":
        path = claude_desktop_cfg
    elif target == "claude_code":
        path = os.path.join(home, ".claude", "settings.json")
    else:
        base = os.path.join(home, "Library", "Application Support") if platform == "macos" else os.path.join(home, ".config")
        path = custom.replace("%APPDATA%", base).replace("%USERPROFILE%", home).replace("\\", "/") if custom else os.path.join(home, ".tian", "mcp_config.json")
    print(f"{target or backend.get('id', 'mcp')}|{path}")
PYEOF
)
    [[ -f "$CATALOG" ]] && ok "catalog.json found" || { warn "catalog.json missing — reinstall TIAN"; ((issues++)) || true; }
    [[ -f "$TIAN_DIR/launcher.sh" ]] && ok "launcher.sh found" || { warn "launcher.sh missing — run setup"; ((issues++)) || true; }
    echo ""

    echo -e "${BOLD}  Configured MCP servers${RESET}"
    local mcp_check_output
    mcp_check_output=$(python3 - "$CATALOG" "$(detect_platform)" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys

catalog_path, platform, home, claude_desktop_cfg = sys.argv[1:5]
catalog = json.load(open(catalog_path))

# Build a map from configKey -> server (for env-var lookups)
server_by_key = {s.get("configKey", ""): s for s in catalog.get("mcpServers", []) if s.get("configKey")}

def expand_path(target, custom):
    if target == "claude_desktop":
        return claude_desktop_cfg
    if target == "claude_code":
        return os.path.join(home, ".claude", "settings.json")
    if custom:
        base = os.path.join(home, "Library", "Application Support") if platform == "macos" else os.path.join(home, ".config")
        return custom.replace("%APPDATA%", base).replace("%USERPROFILE%", home).replace("\\", "/")
    return os.path.join(home, ".tian", "mcp_config.json")

seen_paths = set()
found_any = False
for backend in catalog["backends"]:
    if not backend.get("supportsMcp", True):
        continue
    target = backend.get("mcpConfigTarget") or ""
    custom = backend.get("mcpConfigPath") or ""
    path = expand_path(target, custom)
    if path in seen_paths or not os.path.isfile(path):
        continue
    seen_paths.add(path)
    try:
        config = json.load(open(path))
    except Exception:
        continue
    mcp_servers = config.get("mcpServers", {})
    if not mcp_servers:
        continue
    for config_key in mcp_servers:
        server = server_by_key.get(config_key)
        if not server:
            continue
        found_any = True
        for ev in server.get("requiredEnvVars", []):
            var_name = ev.get("name", "")
            label = ev.get("label") or var_name
            hint = ev.get("hint") or ""
            is_set = "1" if os.environ.get(var_name) else "0"
            print(f"{server['displayName']}|{var_name}|{label}|{hint}|{is_set}")

if not found_any:
    print("__none__")
PYEOF
)
    if [[ "$mcp_check_output" == "__none__" ]]; then
        info "No MCP servers configured yet"
    else
        local mcp_issues=0
        while IFS='|' read -r svc_name var_name label hint is_set; do
            [[ -z "$var_name" ]] && continue
            if [[ "$is_set" == "1" ]]; then
                ok "$svc_name: $var_name is set"
                local _actual_val="${!var_name:-}"
                _validate_mcp_credential "$var_name" "$_actual_val" || ((issues++)) || true
            else
                warn "$svc_name: $var_name not set — ${hint:-required for this MCP server}"
                info "  Fix: export $var_name=<your-key>, then source your shell profile"
                ((issues++)) || true
                ((mcp_issues++)) || true
            fi
        done <<< "$mcp_check_output"
    fi
    echo ""

    echo -e "${BOLD}  Network & service reachability${RESET}"
    if command -v curl &>/dev/null; then
        local anthropic_status openai_status
        anthropic_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "x-api-key: test" -H "anthropic-version: 2023-06-01" \
            "https://api.anthropic.com/v1/models" 2>/dev/null) || anthropic_status="000"
        case "$anthropic_status" in
            200|401|403|429) ok "api.anthropic.com reachable (HTTP $anthropic_status)" ;;
            000) warn "Cannot reach api.anthropic.com — check internet / firewall"; ((issues++)) || true ;;
            *)   info "api.anthropic.com returned HTTP $anthropic_status" ;;
        esac

        openai_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            -H "Authorization: Bearer test" \
            "https://api.openai.com/v1/models" 2>/dev/null) || openai_status="000"
        case "$openai_status" in
            200|401|403|429) ok "api.openai.com reachable (HTTP $openai_status)" ;;
            000) warn "Cannot reach api.openai.com — check internet / firewall"; ((issues++)) || true ;;
            *)   info "api.openai.com returned HTTP $openai_status" ;;
        esac
    else
        info "curl not found — skipping network reachability checks"
    fi

    # Check if Ollama service is running (it needs a daemon, not just a CLI binary)
    if command -v ollama &>/dev/null; then
        local ollama_status
        if command -v curl &>/dev/null; then
            ollama_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
                "http://localhost:11434/api/tags" 2>/dev/null) || ollama_status="000"
        else
            # fallback: `ollama list` exits 0 only when the daemon is running
            ollama list &>/dev/null && ollama_status="200" || ollama_status="000"
        fi
        if [[ "$ollama_status" == "200" ]]; then
            ok "Ollama service is running (localhost:11434)"
            # Check that at least one model has been pulled; service running with no models is a
            # common non-obvious failure — users get confusing "no models" errors at runtime.
            local ollama_models=""
            if command -v curl &>/dev/null; then
                ollama_models=$(curl -s --max-time 5 "http://localhost:11434/api/tags" 2>/dev/null \
                    | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('models',[])))" 2>/dev/null) \
                    || ollama_models="0"
            else
                ollama_models=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ') || ollama_models="0"
            fi
            if [[ "${ollama_models:-0}" -gt 0 ]]; then
                ok "Ollama: ${ollama_models} model(s) available"
            else
                warn "Ollama is running but no models are pulled — tasks will fail"
                info "  Fix: run 'ollama pull llama3' (or another model name)"
                if $fix; then
                    info "  Auto-fixing: pulling llama3 (this may take several minutes)..."
                    if ollama pull llama3 2>/dev/null; then
                        ok "  llama3 pulled successfully"
                        ((fixed++)) || true
                    else
                        warn "  'ollama pull llama3' failed — try manually or choose a different model"
                        ((issues++)) || true
                    fi
                else
                    ((issues++)) || true
                fi
            fi
        else
            warn "Ollama is installed but the service is NOT running"
            if $fix; then
                info "  Auto-fixing: starting 'ollama serve' in background..."
                nohup ollama serve &>/dev/null &
                sleep 2
                local _new_ollama_status
                if command -v curl &>/dev/null; then
                    _new_ollama_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
                        "http://localhost:11434/api/tags" 2>/dev/null) || _new_ollama_status="000"
                else
                    ollama list &>/dev/null && _new_ollama_status="200" || _new_ollama_status="000"
                fi
                if [[ "$_new_ollama_status" == "200" ]]; then
                    ok "  Ollama service started successfully"
                    ((fixed++)) || true
                else
                    warn "  Could not start Ollama automatically; run: ollama serve"
                    ((issues++)) || true
                fi
            else
                info "  Fix: run 'ollama serve' in a separate terminal (or start the Ollama app)"
                ((issues++)) || true
            fi
        fi
    fi
    echo ""

    echo -e "${BOLD}  Shell environment${RESET}"

    # ── PATH: is tian-cli findable? ───────────────────────────────────────────
    local tian_bin
    tian_bin=$(command -v tian-cli 2>/dev/null || true)
    if [[ -n "$tian_bin" ]]; then
        ok "tian-cli found on PATH: $tian_bin"
    else
        warn "tian-cli not found on PATH — you may need to open a new terminal or re-run setup"
        info "  Fix: open a new terminal window, or run: source $(profile_file)"
        ((issues++)) || true
    fi

    # ── Shell profile: is the profile actually sourced in this session? ───────
    # We detect this by checking whether TIAN_DIR resolves to our actual install dir.
    # If the env var is empty the profile hasn't been sourced yet this session.
    if [[ -n "${TIAN_DIR:-}" ]]; then
        ok "Shell profile sourced (TIAN_DIR=$TIAN_DIR)"
    else
        warn "TIAN_DIR not set — shell profile may not have been sourced"
        info "  Fix: open a new terminal, or run: source $(profile_file)"
        ((issues++)) || true
    fi

    # ── Disk space: warn if free space is low (Ollama models need several GB) ─
    local avail_kb avail_gb
    avail_kb=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4}') || avail_kb=""
    if [[ -n "$avail_kb" ]]; then
        avail_gb=$(awk "BEGIN{printf \"%.1f\", $avail_kb/1048576}")
        if awk "BEGIN{exit ($avail_kb >= 5242880) ? 0 : 1}"; then
            ok "Disk space: ${avail_gb} GB free"
        elif awk "BEGIN{exit ($avail_kb >= 2097152) ? 0 : 1}"; then
            warn "Disk space: only ${avail_gb} GB free — Ollama models may not fit (need ~4 GB+)"
            info "  Free up space or choose a smaller model (e.g. ollama pull phi)"
            ((issues++)) || true
        else
            warn "Disk space: critically low — only ${avail_gb} GB free"
            info "  TIAN and AI models need several GB of free space"
            ((issues++)) || true
        fi
    fi

    # ── TIAN data directory size ───────────────────────────────────────────────
    if [[ -d "$TIAN_DIR" ]]; then
        local tian_size
        tian_size=$(du -sh "$TIAN_DIR" 2>/dev/null | awk '{print $1}') || tian_size="?"
        info "TIAN data directory: $tian_size  ($TIAN_DIR)"
    fi
    echo ""

    echo -e "${BOLD}  Background scheduler${RESET}"
    local sched_count=0
    [[ -f "$SCHEDULES_FILE" ]] && sched_count=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" "$SCHEDULES_FILE" 2>/dev/null || echo 0)
    case "$platform" in
        macos)
            if command -v launchctl &>/dev/null; then
                ok "launchd available (macOS scheduler)"
            else
                warn "launchctl not found — scheduled tasks cannot run"; ((issues++)) || true
            fi
            ;;
        linux|wsl)
            if cron_running; then
                ok "cron daemon is running"
            elif [[ "$sched_count" -gt 0 ]]; then
                warn "cron daemon is NOT running — your $sched_count schedule(s) will not fire"
                if $fix; then
                    info "  Auto-fixing: attempting to start cron (requires sudo)..."
                    if sudo -n service cron start &>/dev/null 2>&1; then
                        ok "  cron daemon started"
                        ((fixed++)) || true
                    else
                        warn "  Cannot start cron automatically (sudo password required)"
                        info "  Run manually: sudo service cron start"
                        ((issues++)) || true
                    fi
                else
                    while IFS= read -r line; do
                        [[ -n "$line" ]] && info "$line"
                    done < <(cron_fix_hint "$platform")
                    ((issues++)) || true
                fi
            else
                info "cron daemon is not running (no schedules defined — fine for now)"
                [[ "$platform" == "wsl" ]] && info "  Note: cron is off by default on WSL; start it before using 'schedule add'."
            fi
            ;;
        *)
            warn "Unknown platform — scheduler status cannot be verified"
            ;;
    esac
    echo ""

    rule
    if [[ $issues -eq 0 && $fixed -eq 0 ]]; then
        ok "All checks passed — TIAN looks healthy!"
    elif [[ $issues -eq 0 && $fixed -gt 0 ]]; then
        ok "Fixed $fixed issue(s) automatically — TIAN looks healthy!"
    elif $fix && [[ $fixed -gt 0 ]]; then
        ok "Fixed $fixed issue(s) automatically."
        warn "$issues problem(s) remain. Follow the hints above, then re-run: tian-cli doctor"
    else
        warn "$issues problem(s) found. Follow the hints above, then re-run: tian-cli doctor"
        info "  Tip: run 'tian-cli doctor --fix' to auto-resolve fixable issues (npm backends, Ollama)"
    fi
    echo ""
}

cmd_skill() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        run)
            local skill_id="${1:-}"; shift || true
            [[ -n "$skill_id" ]] || fail "Usage: skill run <id> [input text]"
            local extra_input="$*"

            # Prefer the installed copy; fall back to the bundled builtin file
            local skill_file=""
            if [[ -f "$HOME/.tian/skills/${skill_id}.md" ]]; then
                skill_file="$HOME/.tian/skills/${skill_id}.md"
            else
                local row; row=$(find_skill_by_id "$skill_id" 2>/dev/null) \
                    || fail "Unknown skill '$skill_id'. Run: tian-cli list skills"
                local _id _name _source prompt_file
                IFS='|' read -r _id _name _source prompt_file _ <<< "$row"
                if [[ -n "$prompt_file" && -f "$TIAN_DIR/$prompt_file" ]]; then
                    skill_file="$TIAN_DIR/$prompt_file"
                else
                    fail "Skill '$skill_id' is not installed. Run: tian-cli add skill $skill_id"
                fi
            fi

            local skill_prompt; skill_prompt=$(cat "$skill_file")
            local full_prompt="$skill_prompt"
            if [[ -n "$extra_input" ]]; then
                full_prompt="${skill_prompt}

---

${extra_input}"
            fi

            info "Running skill: $skill_id"
            cmd_run "$full_prompt"
            ;;

        list)
            hdr "Skills"
            python3 - "$CATALOG" "$HOME" <<'PYEOF'
import json, os, sys
catalog, home = json.load(open(sys.argv[1])), sys.argv[2]
skills_dir = os.path.join(home, ".tian", "skills")
GREEN  = '\033[0;32m'
DIM    = '\033[2m'
YELLOW = '\033[1;33m'
RESET  = '\033[0m'
BOLD   = '\033[1m'
for s in catalog["skills"]:
    sid   = s.get("id", "")
    name  = s.get("displayName", sid)
    cat_  = s.get("category", "")
    installed = os.path.isfile(os.path.join(skills_dir, f"{sid}.md"))
    tag = f"{GREEN}installed{RESET}" if installed else f"{DIM}not installed{RESET}"
    print(f"  {sid:<26} {name:<28} {cat_:<14}  {tag}")
PYEOF
            echo ""
            info "Run a skill: tian-cli skill run <id> [input text]"
            info "Install:     tian-cli add skill <id>"
            rule
            ;;

        info)
            local skill_id="${1:-}"
            [[ -n "$skill_id" ]] || fail "Usage: skill info <id>"
            local row; row=$(find_skill_by_id "$skill_id") \
                || fail "Unknown skill '$skill_id'. Run: tian-cli skill list"
            local _id display_name _source prompt_file
            IFS='|' read -r _id display_name _source prompt_file _ <<< "$row"

            local skill_file=""
            if [[ -f "$HOME/.tian/skills/${skill_id}.md" ]]; then
                skill_file="$HOME/.tian/skills/${skill_id}.md"
            elif [[ -n "$prompt_file" && -f "$TIAN_DIR/$prompt_file" ]]; then
                skill_file="$TIAN_DIR/$prompt_file"
            fi

            hdr "Skill: $display_name"
            if [[ -n "$skill_file" ]]; then
                cat "$skill_file"
                echo ""
                info "Run it with: tian-cli skill run $skill_id [your input]"
            else
                warn "Skill not installed. Run: tian-cli add skill $skill_id"
            fi
            ;;

        ""|help|--help|-h)
            echo ""
            echo -e "${CYAN}${BOLD}  tian-cli skill${RESET}"
            rule
            echo "  skill list                  List available skills and show which are installed"
            echo "  skill run <id>              Run a skill (reads its prompt template)"
            echo "  skill run <id> <input>      Run a skill with extra context or instructions"
            echo "  skill info <id>             Print the skill's prompt template"
            echo ""
            echo "  Examples:"
            echo "    tian-cli skill run email-assistant"
            echo "    tian-cli skill run email-assistant \"Draft a reply declining the meeting\""
            echo "    tian-cli skill run meeting-notes \"$(printf '<paste your notes here>')\" "
            echo ""
            ;;

        *)
            fail "Unknown subcommand '$sub'. Run: tian-cli skill"
            ;;
    esac
}

cmd_list() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        backends)
            hdr "Available AI Backends"
            python3 - "$CATALOG" <<'PYEOF'
import json, sys, subprocess, os

GREEN  = '\033[0;32m'; YELLOW = '\033[1;33m'; DIM  = '\033[2m'
CYAN   = '\033[0;36m'; BOLD   = '\033[1m';    RESET = '\033[0m'

c = json.load(open(sys.argv[1]))
active_found = False
rows = []
for b in c['backends']:
    cmd = b.get('cliCommand', '')
    installed = bool(cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0)
    is_active = installed and not active_found
    if is_active:
        active_found = True
    env_var = b.get('apiKeyEnvVar', '')
    key_set  = bool(env_var and os.environ.get(env_var))
    npm      = b.get('npmPackage', '')

    marker    = f"{CYAN}★{RESET}" if is_active else ' '
    inst_str  = f"{GREEN}✓ installed{RESET}    " if installed else f"{DIM}✗ not installed{RESET}"
    if not env_var:
        key_str = f"{DIM}no key needed{RESET}"
    elif key_set:
        key_str = f"{GREEN}✓ key set{RESET}"
    else:
        key_str = f"{YELLOW}✗ key not set{RESET}"
    hint = f"  {DIM}→ npm install -g {npm}{RESET}" if npm and not installed else ''
    rows.append((marker, b['id'], b['displayName'], inst_str, key_str, hint))

# Print header row
print(f"  {'':1}  {'ID':<22} {'NAME':<26} {'INSTALLED':<23} {'API KEY'}")
print("  " + "─"*80)
for marker, bid, name, inst_str, key_str, hint in rows:
    print(f"  {marker}  {bid:<22} {name:<26} {inst_str} {key_str}{hint}")
print()
print(f"  {CYAN}★{RESET} = active backend (first installed one used by default)")
print(f"  {DIM}install:  tian-cli install --backend <id>{RESET}")
print(f"  {DIM}use once: tian-cli run \"task\" --backend <id>{RESET}")
PYEOF
            rule ;;
        mcp)
            hdr "Available MCP Servers"
            python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for s in c['mcpServers']:
    print(f"  {s['id']:<22} {s['displayName']:<28} {s['category']}")
PYEOF
            rule ;;
        skills)
            hdr "Available Skills"
            python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for s in c['skills']:
    print(f"  {s['id']:<26} {s['displayName']:<30} {s['category']}")
PYEOF
            rule ;;
        *) fail "Usage: list backends  |  list mcp  |  list skills" ;;
    esac
}

cmd_add() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        mcp)
            local server_id="${1:-}" backend_id=""
            shift || true
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    --backend)
                        backend_id="${2:-}"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            [[ -n "$server_id" ]] || fail "Usage: add mcp <id> [--backend <backend-id>]"
            add_mcp_server "$server_id" "$backend_id"
            ;;
        skill)
            local skill_id="${1:-}"
            [[ -n "$skill_id" ]] || fail "Usage: add skill <id>"
            install_skill "$skill_id"
            ;;
        *)
            fail "Usage: add mcp <id> [--backend <backend-id>]  |  add skill <id>"
            ;;
    esac
}

cmd_remove() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        mcp)
            local server_id="${1:-}" backend_id=""
            shift || true
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    --backend)
                        backend_id="${2:-}"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            [[ -n "$server_id" ]] || fail "Usage: remove mcp <id> [--backend <backend-id>]"
            remove_mcp_server "$server_id" "$backend_id"
            ;;
        *)
            fail "Usage: remove mcp <id> [--backend <backend-id>]"
            ;;
    esac
}

cmd_uninstall() {
    local yes_flag=false
    [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]] && yes_flag=true

    hdr "TIAN Uninstall"
    echo -e "${YELLOW}  This will remove TIAN's installed components:${RESET}"
    echo "    • npm-installed AI backends (claude, codex, etc.)"
    echo "    • API keys written to shell profile (~/.bashrc / ~/.zshrc)"
    echo "    • TIAN job data and schedules (~/.tian)"
    echo "    • TIAN launcher script"
    echo ""
    echo -e "${DIM}  Note: Node.js itself will NOT be removed.${RESET}"
    echo ""

    if ! $yes_flag; then
        printf "${YELLOW}  Proceed with uninstall? [y/N]: ${RESET}"
        read -r answer
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "  Cancelled."; return 0; }
    fi

    local removed=0 skipped=0

    # ── 1. Uninstall npm packages ─────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}  Removing AI backends${RESET}"
    if command -v npm &>/dev/null; then
        while IFS='|' read -r bname bcmd bnpm; do
            if [[ -z "$bnpm" || -z "$bcmd" ]]; then
                [[ -n "$bname" ]] && info "$(printf '%-26s' "$bname") skipping (not npm-installed)"
                ((skipped++)) || true
                continue
            fi
            if command -v "$bcmd" &>/dev/null; then
                if npm uninstall -g "$bnpm" >/dev/null 2>&1; then
                    ok "$(printf '%-26s' "$bname") removed ($bnpm)"
                    ((removed++)) || true
                else
                    warn "$(printf '%-26s' "$bname") npm uninstall failed — try: npm uninstall -g $bnpm"
                    ((skipped++)) || true
                fi
            else
                info "$(printf '%-26s' "$bname") not installed — skipping"
                ((skipped++)) || true
            fi
        done < <(python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    print('|'.join([b.get('displayName',''), b.get('cliCommand',''), b.get('npmPackage','')]))
PYEOF
)
    else
        warn "npm not found — skipping backend removal"
    fi

    # ── 2. Remove API key entries from shell profile ──────────────────────────
    echo ""
    echo -e "${BOLD}  Removing API key exports from shell profile${RESET}"
    local profile_file=""
    [[ -f "$HOME/.zshrc" ]]  && profile_file="$HOME/.zshrc"
    [[ -f "$HOME/.bashrc" ]] && profile_file="${profile_file:-$HOME/.bashrc}"

    python3 - "$CATALOG" "$profile_file" <<'PYEOF'
import json, sys, re, os
catalog_path, profile = sys.argv[1], sys.argv[2]
if not profile or not os.path.isfile(profile):
    print("  [!!]  No shell profile found — skipping")
    sys.exit(0)
with open(catalog_path) as fh:
    c = json.load(fh)
env_vars = set(b.get('apiKeyEnvVar','') for b in c['backends'] if b.get('apiKeyEnvVar'))
with open(profile) as fh:
    lines = fh.readlines()
kept = [l for l in lines if not any(re.search(rf'export\s+{v}\s*=', l) for v in env_vars)]
removed = len(lines) - len(kept)
if removed:
    with open(profile, 'w') as fh:
        fh.writelines(kept)
    print(f"  [ok]  Removed {removed} API key export(s) from {profile}")
else:
    print(f"  [..]  No TIAN API key exports found in {profile}")
PYEOF
    ((removed++)) || true

    # ── 3. Remove MCP config entries written by TIAN ─────────────────────────
    echo ""
    echo -e "${BOLD}  Cleaning MCP config${RESET}"
    while IFS='|' read -r label cfg_path; do
        [[ -n "$cfg_path" ]] || continue
        if [[ -f "$cfg_path" ]]; then
            python3 - "$CATALOG" "$cfg_path" "$label" <<'PYEOF'
import json, sys

catalog_path, cfg_path, label = sys.argv[1:4]
catalog = json.load(open(catalog_path))
tian_keys = {s.get("configKey", "") for s in catalog.get("mcpServers", []) if s.get("configKey")}
cfg = json.load(open(cfg_path))
mcp = cfg.get("mcpServers", {})
before = set(mcp.keys())
for key in list(mcp.keys()):
    if key in tian_keys:
        del mcp[key]
removed = before - set(mcp.keys())
if removed:
    cfg["mcpServers"] = mcp
    with open(cfg_path, "w") as fh:
        json.dump(cfg, fh, indent=2)
    print(f"  [ok]  {label}: removed {len(removed)} MCP server(s)")
else:
    print(f"  [..]  {label}: no TIAN MCP entries found")
PYEOF
        else
            info "$label config not found — skipping"
        fi
    done < <(python3 - "$CATALOG" "$(detect_platform)" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys

catalog_path, platform, home, claude_desktop_cfg = sys.argv[1:5]
catalog = json.load(open(catalog_path))
seen = set()
for backend in catalog["backends"]:
    if not backend.get("supportsMcp", True):
        continue
    key = backend.get("mcpConfigTarget") or backend.get("mcpConfigPath") or ""
    if not key or key in seen:
        continue
    seen.add(key)
    target = backend.get("mcpConfigTarget") or ""
    custom = backend.get("mcpConfigPath") or ""
    if target == "claude_desktop":
        path = claude_desktop_cfg
    elif target == "claude_code":
        path = os.path.join(home, ".claude", "settings.json")
    else:
        base = os.path.join(home, "Library", "Application Support") if platform == "macos" else os.path.join(home, ".config")
        path = custom.replace("%APPDATA%", base).replace("%USERPROFILE%", home).replace("\\", "/") if custom else os.path.join(home, ".tian", "mcp_config.json")
    print(f"{target or backend.get('id', 'mcp')}|{path}")
PYEOF
)

    # ── 4. Remove launcher script ─────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}  Removing launcher${RESET}"
    local launcher="$TIAN_DIR/launcher.sh"
    if [[ -f "$launcher" ]]; then
        rm -f "$launcher"
        ok "launcher.sh removed"
        ((removed++)) || true
    else
        info "launcher.sh not found — skipping"
    fi

    # ── 5. Remove ~/.tian data directory ─────────────────────────────────────
    echo ""
    echo -e "${BOLD}  Removing job data (~/.tian)${RESET}"
    if [[ -d "$HOME/.tian" ]]; then
        rm -rf "$HOME/.tian"
        ok "~/.tian removed"
        ((removed++)) || true
    else
        info "~/.tian not found — skipping"
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo ""
    rule
    ok "TIAN components removed. Removed: $removed  Skipped: $skipped"
    echo ""
    echo -e "${DIM}  TIAN installation directory ($TIAN_DIR) was NOT deleted.${RESET}"
    echo -e "${DIM}  To fully remove it: rm -rf \"$TIAN_DIR\"${RESET}"
    echo ""
}

cmd_repair() {
    info "Re-running setup to repair the current install."
    bash "$TIAN_DIR/mac/setup.sh" "$TIAN_DIR"
}

# ── Config export / import ────────────────────────────────────────────────────

_cmd_config_export() {
    local out_file="$1" include_keys="$2"
    local platform; platform=$(detect_platform)

    if [[ "$include_keys" == "true" ]]; then
        warn "This export file will contain your API keys in plaintext."
        info "Keep it secure. Use --no-keys to omit keys."
        echo ""
    fi

    python3 - "$CATALOG" "$out_file" "$platform" "$HOME" \
        "$include_keys" "$SCHEDULES_FILE" "$HOME/.tian/skills" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys, datetime

catalog_path, out_file, platform, home = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
include_keys      = sys.argv[5] == "true"
schedules_file    = sys.argv[6]
skills_dir        = sys.argv[7]
claude_desktop_cfg = sys.argv[8]

catalog = json.load(open(catalog_path))

export_data = {
    "version":    1,
    "exportedAt": datetime.datetime.now().isoformat(),
    "platform":   platform,
}

# ── API keys from current environment ──────────────────────────────────────
if include_keys:
    api_keys, seen = {}, set()
    for b in catalog["backends"]:
        env = b.get("apiKeyEnvVar", "")
        if not env or env in seen:
            continue
        seen.add(env)
        val = os.environ.get(env, "")
        if val:
            api_keys[env] = val
    export_data["apiKeys"] = api_keys

# ── MCP server configs ─────────────────────────────────────────────────────
def expand_path(target, custom):
    if target == "claude_desktop":
        return claude_desktop_cfg
    if target == "claude_code":
        return os.path.join(home, ".claude", "settings.json")
    if custom:
        base = os.path.join(home, "Library", "Application Support") if platform == "macos" else os.path.join(home, ".config")
        return custom.replace("%APPDATA%", base).replace("%USERPROFILE%", home).replace("\\", "/")
    return os.path.join(home, ".tian", "mcp_config.json")

mcp_configs, seen_paths = {}, set()
for backend in catalog["backends"]:
    if not backend.get("supportsMcp", True):
        continue
    target = backend.get("mcpConfigTarget") or ""
    custom = backend.get("mcpConfigPath") or ""
    path   = expand_path(target, custom)
    key    = target or backend.get("id", "")
    if path in seen_paths or not os.path.isfile(path):
        continue
    seen_paths.add(path)
    try:
        cfg     = json.load(open(path))
        servers = cfg.get("mcpServers", {})
        if servers:
            mcp_configs[key] = servers
    except Exception:
        pass
export_data["mcpServers"] = mcp_configs

# ── Schedules ──────────────────────────────────────────────────────────────
try:
    schedules = json.load(open(schedules_file))
except Exception:
    schedules = []
export_data["schedules"] = schedules

# ── Installed skills (files in ~/.tian/skills/) ───────────────────────────
installed_skills = []
if os.path.isdir(skills_dir):
    for f in sorted(os.listdir(skills_dir)):
        if f.endswith(".md"):
            installed_skills.append(f[:-3])
export_data["installedSkills"] = installed_skills

with open(out_file, "w", encoding="utf-8") as fh:
    json.dump(export_data, fh, indent=2)
PYEOF
    ok "Config exported to: $out_file"
    info "Copy this file to the new machine, then run:"
    info "  bash tian-cli.sh config import $out_file"
    echo ""
}

_cmd_config_import() {
    local in_file="$1" assume_yes="$2"
    local platform; platform=$(detect_platform)

    [[ -f "$in_file" ]] || fail "File not found: $in_file"
    python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$in_file" 2>/dev/null \
        || fail "Invalid JSON in $in_file"

    info "Importing TIAN config from: $in_file"
    echo ""

    if [[ "$assume_yes" != "true" ]]; then
        printf "  Proceed? [y/N]: "
        read -r _answer
        [[ "$_answer" =~ ^[Yy]$ ]] || { echo "  Cancelled."; return 0; }
        echo ""
    fi

    # ── API keys ───────────────────────────────────────────────────────────────
    echo -e "${BOLD}  API Keys${RESET}"
    local key_count=0
    while IFS='|' read -r _kname _kval; do
        [[ -n "$_kname" && -n "$_kval" ]] || continue
        save_shell_env_var "$_kname" "$_kval"
        ok "$_kname saved to $(profile_file)"
        ((key_count++)) || true
    done < <(python3 - "$in_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for name, val in (data.get("apiKeys") or {}).items():
    if name and val:
        print(f"{name}|{val}")
PYEOF
)
    [[ $key_count -eq 0 ]] && info "No API keys in export file"
    echo ""

    # ── MCP server configs ─────────────────────────────────────────────────────
    echo -e "${BOLD}  MCP Servers${RESET}"
    local mcp_count
    mcp_count=$(python3 - "$CATALOG" "$in_file" "$platform" "$HOME" "$(_claude_desktop_cfg_path)" <<'PYEOF'
import json, os, sys

catalog_path, in_file, platform, home, claude_desktop_cfg = sys.argv[1:6]
catalog  = json.load(open(catalog_path))
imported = json.load(open(in_file))

def expand_path(target):
    if target == "claude_desktop":
        return claude_desktop_cfg
    if target == "claude_code":
        return os.path.join(home, ".claude", "settings.json")
    return os.path.join(home, ".tian", "mcp_config.json")

count = 0
for target, new_servers in (imported.get("mcpServers") or {}).items():
    if not new_servers:
        continue
    # Verify target exists in catalog (skip unknown targets)
    known = any(
        (b.get("mcpConfigTarget") or "") == target
        for b in catalog["backends"]
    )
    if not known:
        print(f"WARN|{target}|Unknown backend target — skipping")
        continue
    cfg_path = expand_path(target)
    os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
    cfg = {}
    if os.path.exists(cfg_path):
        try:
            cfg = json.load(open(cfg_path))
        except Exception:
            cfg = {}
    cfg.setdefault("mcpServers", {}).update(new_servers)
    with open(cfg_path, "w", encoding="utf-8") as fh:
        json.dump(cfg, fh, indent=2)
    n = len(new_servers)
    print(f"OK|{target}|{n} MCP server(s) merged into {cfg_path}")
    count += 1

if count == 0:
    print("NONE||No MCP servers in export file")
PYEOF
)
    while IFS='|' read -r _status _target _msg; do
        case "$_status" in
            OK)   ok "$_target: $_msg" ;;
            WARN) warn "$_target: $_msg" ;;
            NONE) info "$_msg" ;;
        esac
    done <<< "$mcp_count"
    echo ""

    # ── Skills ─────────────────────────────────────────────────────────────────
    echo -e "${BOLD}  Skills${RESET}"
    local skill_count=0
    while IFS= read -r _sid; do
        [[ -n "$_sid" ]] || continue
        if (install_skill "$_sid") 2>/dev/null; then
            ok "Skill '$_sid' installed"
            ((skill_count++)) || true
        else
            warn "Skill '$_sid' not found in catalog — skipping"
        fi
    done < <(python3 - "$in_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for s in (data.get("installedSkills") or []):
    if s:
        print(s)
PYEOF
)
    [[ $skill_count -eq 0 ]] && info "No skills in export file"
    echo ""

    # ── Schedules ──────────────────────────────────────────────────────────────
    echo -e "${BOLD}  Schedules${RESET}"
    ensure_dirs
    local sched_count=0
    while IFS='|' read -r _sname _sprompt _stime _srepeat; do
        [[ -n "$_sname" && -n "$_sprompt" ]] || continue
        if [[ "$platform" == "linux" || "$platform" == "wsl" ]]; then
            _schedule_add_linux "$_sname" "$_sprompt" "$_stime" "$_srepeat" 2>/dev/null \
                && ok "Schedule '$_sname' created" \
                || warn "Could not create schedule '$_sname'"
        elif [[ "$platform" == "macos" ]]; then
            _schedule_add_macos "$_sname" "$_sprompt" "$_stime" "$_srepeat" 2>/dev/null \
                && ok "Schedule '$_sname' created" \
                || warn "Could not create schedule '$_sname'"
        else
            warn "Unsupported platform for schedules — skipping '$_sname'"
        fi
        ((sched_count++)) || true
    done < <(python3 - "$in_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for s in (data.get("schedules") or []):
    name   = s.get("name", "")
    prompt = s.get("prompt", "")
    time   = s.get("time", "08:00")
    repeat = s.get("repeat", "daily")
    if name and prompt:
        print(f"{name}|{prompt}|{time}|{repeat}")
PYEOF
)
    [[ $sched_count -eq 0 ]] && info "No schedules in export file"
    echo ""

    rule
    ok "Import complete!"
    info "Open a new terminal so the saved env vars take effect."
    echo ""
}

cmd_config() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        export)
            local out_file="tian-config.json" include_keys="true"
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    --output|-o) out_file="${2:-}"; shift 2 ;;
                    --no-keys)   include_keys="false"; shift ;;
                    *) shift ;;
                esac
            done
            hdr "TIAN Config Export"
            _cmd_config_export "$out_file" "$include_keys"
            ;;
        import)
            local in_file="${1:-}" assume_yes="false"
            shift || true
            while [[ $# -gt 0 ]]; do
                case "${1:-}" in
                    -y|--yes) assume_yes="true"; shift ;;
                    *) shift ;;
                esac
            done
            [[ -n "$in_file" ]] || fail "Usage: config import <file> [--yes]"
            hdr "TIAN Config Import"
            _cmd_config_import "$in_file" "$assume_yes"
            ;;
        *)
            cat <<EOF

  config export [--output <file>] [--no-keys]
      Export your TIAN setup (API keys, MCP configs, skills, schedules) to a
      portable JSON file. Default output: tian-config.json
      Use --no-keys to omit API keys from the export.

  config import <file> [--yes]
      Restore a previously exported TIAN config on this machine.
      Re-applies API keys, MCP server configs, skills, and schedules.

EOF
            ;;
    esac
}

cmd_key() {
    local sub="${1:-}"; shift || true

    case "$sub" in
        set)
            # tian-cli key set [backend-id]
            local backend_id="${1:-}"
            local b_row=""

            if [[ -n "$backend_id" ]]; then
                b_row=$(python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
target = sys.argv[2]
for b in c['backends']:
    if b.get('id') == target and b.get('apiKeyEnvVar'):
        print('|'.join([b.get('id',''), b.get('displayName',''), b.get('apiKeyEnvVar',''), b.get('apiKeyUrl',''), b.get('apiKeyHint','')]))
        break
PYEOF
) || true
                [[ -z "$b_row" ]] && fail "Unknown backend '$backend_id' or it has no API key. Run: tian-cli list backends"
            else
                # No backend given: list backends that require a key and let user pick
                local b_names=() b_ids=() b_envs=() b_urls=() b_hints=()
                while IFS='|' read -r bid bname benv burl bhint; do
                    [[ -z "$bid" ]] && continue
                    b_ids+=("$bid")
                    b_names+=("$bname")
                    b_envs+=("$benv")
                    b_urls+=("$burl")
                    b_hints+=("$bhint")
                done < <(python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
seen = set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', '')
    if not env or env in seen: continue
    seen.add(env)
    print('|'.join([b.get('id',''), b.get('displayName',''), env, b.get('apiKeyUrl',''), b.get('apiKeyHint','')]))
PYEOF
)
                if [[ ${#b_ids[@]} -eq 0 ]]; then
                    fail "No backends with API keys found in catalog."
                fi

                echo -e "${BOLD}  Which backend do you want to set a key for?${RESET}"
                local i
                for i in "${!b_names[@]}"; do
                    echo "    [$((i+1))] ${b_names[$i]}"
                done
                echo ""
                local choice
                read -rp "  Enter number [1]: " choice
                choice="${choice:-1}"
                local idx=$(( choice - 1 ))
                if [[ "$idx" -lt 0 || "$idx" -ge ${#b_ids[@]} ]]; then
                    fail "Invalid choice."
                fi
                b_row="${b_ids[$idx]}|${b_names[$idx]}|${b_envs[$idx]}|${b_urls[$idx]}|${b_hints[$idx]}"
            fi

            local bid bname benv burl bhint
            IFS='|' read -r bid bname benv burl bhint <<< "$b_row"

            hdr "Set API Key — $bname"
            [[ -n "$burl" ]]  && info "Get your key at: $burl"
            [[ -n "$bhint" ]] && info "$bhint"
            echo ""

            local existing="${!benv:-}"
            if [[ -n "$existing" ]]; then
                info "Current value: ${existing:0:8}..."
                echo ""
            fi

            local api_key
            api_key=$(prompt_secret "$benv (paste your key, then Enter)")
            echo ""
            [[ -z "$api_key" ]] && fail "No key entered — aborting."

            local provider=""
            [[ "$benv" == *ANTHROPIC* ]] && provider="anthropic"
            [[ "$benv" == *OPENAI* ]]    && provider="openai"

            save_shell_env_var "$benv" "$api_key"
            ok "$benv saved to $(profile_file)"
            echo ""

            if [[ -n "$provider" ]]; then
                info "Verifying key with the API..."
                _verify_api_key "$provider" "$api_key" "$burl"
            fi

            echo ""
            info "To activate immediately in this session: source $(profile_file)"
            ;;

        show)
            hdr "API Keys"
            local any=false
            while IFS='|' read -r bname benv burl; do
                [[ -z "$benv" ]] && continue
                local val="${!benv:-}"
                if [[ -n "$val" ]]; then
                    ok "$(printf '%-40s' "$bname ($benv)") ${val:0:8}..."
                    any=true
                else
                    local profile; profile=$(profile_file)
                    if [[ -f "$profile" ]] && grep -qE "export[[:space:]]+${benv}[[:space:]]*=" "$profile" 2>/dev/null; then
                        warn "$(printf '%-40s' "$bname ($benv)") saved in profile but not active — open a new terminal"
                    else
                        info "$(printf '%-40s' "$bname ($benv)") not set"
                    fi
                fi
            done < <(python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
seen = set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', '')
    if not env or env in seen: continue
    seen.add(env)
    print('|'.join([b.get('displayName',''), env, b.get('apiKeyUrl','')]))
PYEOF
)
            if ! $any; then
                echo ""
                info "No API keys are currently active. Run: tian-cli key set"
            fi
            ;;

        remove)
            local backend_id="${1:-}"
            [[ -n "$backend_id" ]] || fail "Usage: tian-cli key remove <backend-id>"
            local b_row
            b_row=$(python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    if b.get('id') == sys.argv[2] and b.get('apiKeyEnvVar'):
        print('|'.join([b.get('displayName',''), b.get('apiKeyEnvVar','')]))
        break
PYEOF
) || true
            [[ -z "$b_row" ]] && fail "Unknown backend '$backend_id' or it has no API key."
            local bname benv
            IFS='|' read -r bname benv <<< "$b_row"
            local profile; profile=$(profile_file)
            if [[ -f "$profile" ]] && grep -qE "export[[:space:]]+${benv}[[:space:]]*=" "$profile" 2>/dev/null; then
                python3 - "$profile" "$benv" <<'PYEOF'
import os, re, sys
profile, name = sys.argv[1], sys.argv[2]
pattern = re.compile(rf'^\s*export\s+{re.escape(name)}=')
with open(profile, encoding='utf-8', errors='ignore') as fh:
    lines = fh.readlines()
kept = [l for l in lines if not pattern.search(l)]
with open(profile, 'w', encoding='utf-8') as fh:
    fh.writelines(kept)
PYEOF
                unset "$benv" 2>/dev/null || true
                ok "$benv removed from $(basename "$profile") and unset from current session"
            else
                info "$benv was not found in $(profile_file) — nothing to remove"
            fi
            ;;

        *)
            echo -e "${BOLD}Usage:${RESET}"
            echo "  tian-cli key set [backend-id]   Set or update an API key"
            echo "  tian-cli key show               Show which API keys are set"
            echo "  tian-cli key remove <backend-id> Remove an API key from your shell profile"
            echo ""
            echo "  Example: tian-cli key set claude-code"
            ;;
    esac
}

_quota_render_result() {
    # Print the result for one backend from a pre-populated temp dir.
    # Args: bid bname benv burl provider tmpdir
    local bid="$1" bname="$2" benv="$3" burl="$4" provider="$5" tmpdir="$6"
    local body_file="$tmpdir/${benv}.body"
    local hdr_file="$tmpdir/${benv}.hdr"

    local body="" http_status="" retry_after=""
    [[ -f "$body_file" ]] && body=$(cat "$body_file")
    http_status=$(echo "$body" | tail -1)
    body=$(echo "$body" | head -n -1)   # strip the appended status line
    [[ -f "$hdr_file" ]] && retry_after=$(grep -i "^retry-after:" "$hdr_file" \
        | awk '{print $2}' | tr -d '\r' | head -1) || retry_after=""

    printf "  %-32s" "$bname"
    case "$http_status" in
        200)
            echo -e "${GREEN}OK${RESET}  — key valid, not rate-limited"
            ;;
        401)
            echo -e "${RED}INVALID${RESET}  — key rejected (HTTP 401)"
            echo -e "             Fix: tian-cli key set ${bid}  (get a new key at: $burl)"
            ;;
        403)
            if echo "$body" | grep -qi "credit\|billing\|quota\|insufficient"; then
                echo -e "${RED}QUOTA EXHAUSTED${RESET}  — billing/credit issue (HTTP 403)"
                echo -e "             Fix: add credits at $burl"
            else
                echo -e "${YELLOW}FORBIDDEN${RESET}  — key lacks permissions (HTTP 403)"
                echo -e "             Fix: check key permissions at $burl"
            fi
            ;;
        429)
            if [[ -n "$retry_after" ]]; then
                echo -e "${YELLOW}RATE LIMITED${RESET}  — retry after ${retry_after}s (HTTP 429)"
                echo -e "             Retry after: ${retry_after}s"
            else
                echo -e "${YELLOW}RATE LIMITED${RESET}  — quota exhausted or too many requests (HTTP 429)"
                local err_type
                err_type=$(echo "$body" | python3 -c \
                    "import json,sys
try:
    d=json.load(sys.stdin)
    err=d.get('error',{})
    t=err.get('type','') or ''
    m=(err.get('message','') or '')[:80]
    print(t + (': ' + m if m else ''))
except Exception:
    pass" 2>/dev/null) || err_type=""
                [[ -n "$err_type" ]] && echo -e "             Detail: $err_type"
                echo -e "             This may resolve automatically — try again in a few minutes"
            fi
            ;;
        000|"")
            echo -e "${YELLOW}UNREACHABLE${RESET}  — network error or DNS failure"
            echo -e "             Check internet connection or firewall rules"
            ;;
        *)
            echo -e "${DIM}UNKNOWN${RESET}  — unexpected HTTP $http_status"
            ;;
    esac
}

cmd_ping() {
    local forced_backend_id=""
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            --backend) forced_backend_id="${2:-}"; shift 2 ;;
            -h|--help)
                echo ""
                echo "Usage: tian-cli ping [--backend <id>]"
                echo ""
                echo "  Send a quick test prompt to the active AI backend and verify it responds."
                echo "  Use --backend <id> to test a specific backend instead of the active one."
                echo ""
                echo "  Examples:"
                echo "    tian-cli ping"
                echo "    tian-cli ping --backend ollama"
                echo ""
                return 0 ;;
            *) shift ;;
        esac
    done

    hdr "TIAN Ping — End-to-End AI Test"

    local cmd="" flag="" backend_id="" b_name=""
    if [[ -n "$forced_backend_id" ]]; then
        local _bcheck
        _bcheck=$(python3 - "$CATALOG" "$forced_backend_id" <<'PYEOF'
import json, subprocess, sys
catalog = json.load(open(sys.argv[1]))
bid = sys.argv[2]
b = next((bb for bb in catalog['backends'] if bb.get('id') == bid), None)
if not b:
    print("error:notfound"); raise SystemExit(1)
c = b.get('cliCommand', '')
fl = (b.get('nonInteractiveFlag', '') or '').strip()
if not c or subprocess.run(['which', c], capture_output=True).returncode != 0:
    print("error:notinstalled"); raise SystemExit(2)
print(f"{c}|{fl}|{bid}|{b['displayName']}")
PYEOF
) || true
        case "$_bcheck" in
            error:notfound)     fail "Unknown backend '$forced_backend_id'. Run: tian-cli list backends" ;;
            error:notinstalled) fail "Backend '$forced_backend_id' is not installed. Run: tian-cli install --backend $forced_backend_id" ;;
        esac
        cmd=$(echo "$_bcheck"    | cut -d'|' -f1)
        flag=$(echo "$_bcheck"   | cut -d'|' -f2)
        backend_id=$(echo "$_bcheck" | cut -d'|' -f3)
        b_name=$(echo "$_bcheck" | cut -d'|' -f4)
    else
        local backend_row; backend_row=$(active_backend) || true
        if [[ -z "$backend_row" ]]; then
            fail "No AI backend found. Run: bash setup.sh"
        fi
        cmd=$(echo "$backend_row"    | cut -d'|' -f1)
        flag=$(echo "$backend_row"   | cut -d'|' -f2)
        backend_id=$(echo "$backend_row" | cut -d'|' -f3)
        b_name=$(python3 - "$CATALOG" "$backend_id" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
bid = sys.argv[2]
b = next((bb for bb in c['backends'] if bb.get('id') == bid), None)
print(b['displayName'] if b else bid)
PYEOF
)
    fi

    info "Backend: $b_name  ($cmd)"
    info "Sending test prompt..."
    echo ""

    local test_prompt="Reply with exactly and only the word: PONG"
    local tmpfile; tmpfile=$(mktemp)
    trap 'rm -f "$tmpfile"' RETURN

    # Capture start time in milliseconds
    local start_ms end_ms
    start_ms=$(date +%s%3N 2>/dev/null || date +%s)

    local exit_code=0
    # flag may be empty; unquoted expansion is intentional so multi-word flags split correctly
    timeout 30 "$cmd" $flag "$test_prompt" > "$tmpfile" 2>&1 || exit_code=$?

    end_ms=$(date +%s%3N 2>/dev/null || date +%s)
    local elapsed_ms=$(( end_ms - start_ms ))
    local elapsed_s
    elapsed_s=$(awk "BEGIN{printf \"%.1f\", $elapsed_ms/1000}")

    local response; response=$(cat "$tmpfile")

    # ── No output at all ────────────────────────────────────────────────────────
    if [[ -z "$response" ]]; then
        warn "No output received from backend (exit code: $exit_code, ${elapsed_s}s)"
        info "  Check: tian-cli doctor  — to diagnose configuration issues"
        info "  Check: tian-cli quota   — to check API quota"
        echo ""
        return 1
    fi

    # ── Quota / rate-limit error in response ────────────────────────────────────
    if is_quota_error "$response"; then
        warn "Quota or rate-limit error detected in backend response (${elapsed_s}s)"
        info "  Check: tian-cli quota   — to see your API quota status"
        echo ""
        rule
        echo -e "${DIM}Response snippet:${RESET}"
        echo "$response" | head -5
        echo ""
        return 1
    fi

    # ── Success ─────────────────────────────────────────────────────────────────
    rule
    echo -e "${DIM}Response received in ${elapsed_s}s:${RESET}"
    echo ""
    echo "$response" | head -20
    echo ""
    rule
    ok "AI backend is responding correctly.  (${elapsed_s}s)"
    echo ""
}

cmd_quota() {
    hdr "API Quota / Rate-Limit Status"

    if ! command -v curl &>/dev/null; then
        fail "curl is required for quota checks. Install it and retry."
    fi

    local tmpdir; tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    # ── Phase 1: fire all curl requests in parallel (one per provider) ─────────
    # Each request uses -D to capture response headers alongside the body in a
    # single round-trip, halving the previous two-request-per-provider approach.
    declare -A pids=()
    local skipped_names=()
    local n_checked=0

    while IFS='|' read -r bid bname benv burl provider; do
        [[ -z "$benv" ]] && continue
        local key="${!benv:-}"
        if [[ -z "$key" ]]; then
            skipped_names+=("$bname ($benv)")
            continue
        fi

        local body_file="$tmpdir/${benv}.body"
        local hdr_file="$tmpdir/${benv}.hdr"
        local meta_file="$tmpdir/${benv}.meta"
        printf '%s|%s|%s|%s|%s\n' "$bid" "$bname" "$benv" "$burl" "$provider" > "$meta_file"

        case "$provider" in
            anthropic)
                ( curl -s -w "\n%{http_code}" --max-time 8 \
                    -D "$hdr_file" \
                    -H "x-api-key: $key" \
                    -H "anthropic-version: 2023-06-01" \
                    "https://api.anthropic.com/v1/models" > "$body_file" 2>/dev/null
                ) &
                pids["$benv"]=$!
                ((n_checked++)) || true
                ;;
            openai)
                ( curl -s -w "\n%{http_code}" --max-time 8 \
                    -D "$hdr_file" \
                    -H "Authorization: Bearer $key" \
                    "https://api.openai.com/v1/models" > "$body_file" 2>/dev/null
                ) &
                pids["$benv"]=$!
                ((n_checked++)) || true
                ;;
            *)
                printf '%s|%s|%s|%s|__unsupported__\n' "$bid" "$bname" "$benv" "$burl" > "$meta_file"
                pids["$benv"]=0
                ;;
        esac
    done < <(python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, sys
c, seen = json.load(open(sys.argv[1])), set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', '')
    if not env or env in seen: continue
    seen.add(env)
    provider = 'anthropic' if 'ANTHROPIC' in env else ('openai' if 'OPENAI' in env else '')
    print(f"{b.get('id','')}|{b['displayName']}|{env}|{b.get('apiKeyUrl','')}|{provider}")
PYEOF
)

    # ── Phase 2: wait for all jobs, then render results in catalog order ───────
    for meta_file in "$tmpdir"/*.meta; do
        [[ -f "$meta_file" ]] || continue
        IFS='|' read -r bid bname benv burl provider < "$meta_file"
        local pid="${pids[$benv]:-}"
        [[ -n "$pid" && "$pid" != "0" ]] && wait "$pid" 2>/dev/null || true
        if [[ "$provider" == "__unsupported__" ]]; then
            printf "  %-32s%s\n" "$bname" "(no quota check available for this provider)"
            continue
        fi
        _quota_render_result "$bid" "$bname" "$benv" "$burl" "$provider" "$tmpdir"
    done

    # ── Phase 3: summary ───────────────────────────────────────────────────────
    echo ""
    for sname in "${skipped_names[@]}"; do
        info "$sname: not set — skipping"
    done

    if [[ $n_checked -le 0 ]]; then
        warn "No API keys are set. Run: tian-cli key set"
    else
        local issues=0
        for body_file in "$tmpdir"/*.body; do
            [[ -f "$body_file" ]] || continue
            local st; st=$(tail -1 "$body_file")
            [[ "$st" =~ ^(401|403|429|000)$ ]] && ((issues++)) || true
        done
        if [[ $issues -eq 0 ]]; then
            ok "All $n_checked API key(s) are active and within quota limits."
        else
            warn "$issues issue(s) found across $n_checked key(s)."
            info "Run 'tian-cli doctor' for a full health check."
        fi
    fi
    echo ""
}

cmd_completion() {
    local shell="${1:-}"
    case "$shell" in
        --help|-h)
            echo "Usage: tian-cli completion <bash|zsh|install>"
            echo "  bash     Print a bash completion script"
            echo "           Usage: eval \"\$(tian-cli completion bash)\""
            echo "  zsh      Print a zsh completion script"
            echo "           Usage: eval \"\$(tian-cli completion zsh)\""
            echo "  install  Auto-detect your shell and install completion into your profile"
            return 0 ;;
        bash|zsh|install) ;;
        "") fail "Usage: tian-cli completion <bash|zsh|install>. Run: tian-cli completion --help" ;;
        *)  fail "Unknown shell '${shell}'. Use: bash, zsh, or install" ;;
    esac

    # Embed static catalog IDs at generation time for instant completions.
    # Jobs and schedule names are read dynamically at tab-press time since they change often.
    local _backend_ids _mcp_ids _skill_ids
    _backend_ids=$(python3 -c "
import json, sys
try:
    c = json.load(open(sys.argv[1]))
    print(' '.join(b['id'] for b in c['backends']))
except Exception:
    pass
" "$CATALOG" 2>/dev/null || true)
    _mcp_ids=$(python3 -c "
import json, sys
try:
    c = json.load(open(sys.argv[1]))
    print(' '.join(m['id'] for m in c.get('mcpServers', [])))
except Exception:
    pass
" "$CATALOG" 2>/dev/null || true)
    _skill_ids=$(python3 -c "
import json, sys
try:
    c = json.load(open(sys.argv[1]))
    print(' '.join(s['id'] for s in c.get('skills', [])))
except Exception:
    pass
" "$CATALOG" 2>/dev/null || true)

    # Build the bash completion script.
    # Variables prefixed with \ are intentionally NOT expanded here — they belong in the output script.
    local bash_script
    bash_script=$(cat <<ENDOFSCRIPT
# TIAN CLI bash completion — generated by: tian-cli completion bash
# To activate in this session:  eval "\$(tian-cli completion bash)"
# To activate permanently:      tian-cli completion install
_tian_complete() {
    local cur="\${COMP_WORDS[COMP_CWORD]}"
    local prev="\${COMP_WORDS[COMP_CWORD-1]}"
    local cmd="\${COMP_WORDS[1]}"
    local cword=\$COMP_CWORD

    # Dynamic helpers — read live data files so job/schedule completions stay current.
    local _jf="\$HOME/.tian/jobs.json"
    local _sf="\$HOME/.tian/schedules.json"
    _tj_ids()   { python3 -c "import json,os; j=json.load(open('\$_jf')) if os.path.isfile('\$_jf') else []; print(' '.join(x.get('id','') for x in j if x.get('id')))" 2>/dev/null; }
    _ts_names() { python3 -c "import json,os; s=json.load(open('\$_sf')) if os.path.isfile('\$_sf') else []; print(' '.join(x.get('name','') for x in s if x.get('name')))" 2>/dev/null; }

    # Top-level subcommands
    if [[ \$cword -eq 1 ]]; then
        COMPREPLY=( \$(compgen -W "setup install repair update doctor status uninstall add remove run jobs schedule list skill config key ping quota completion lang help" -- "\$cur") )
        return
    fi

    case "\$cmd" in
        run)
            case "\$prev" in
                --backend) COMPREPLY=( \$(compgen -W "${_backend_ids}" -- "\$cur") ) ;;
                --file|-f) COMPREPLY=( \$(compgen -f -- "\$cur") ) ;;
                --output|-o) COMPREPLY=( \$(compgen -f -- "\$cur") ) ;;
                *)         COMPREPLY=( \$(compgen -W "--backend --file -f --stdin --output -o -b --background -w --watch --job-name" -- "\$cur") ) ;;
            esac ;;
        install)
            case "\$prev" in
                --backend) COMPREPLY=( \$(compgen -W "${_backend_ids}" -- "\$cur") ) ;;
                --mcp)     COMPREPLY=( \$(compgen -W "${_mcp_ids} default" -- "\$cur") ) ;;
                --skills)  COMPREPLY=( \$(compgen -W "${_skill_ids}" -- "\$cur") ) ;;
                *)         COMPREPLY=( \$(compgen -W "--backend --key --mcp --skills --yes -y" -- "\$cur") ) ;;
            esac ;;
        jobs)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "result tail stop retry clear" -- "\$cur") )
            else
                case "\${COMP_WORDS[2]}" in
                    result|tail|retry) COMPREPLY=( \$(compgen -W "\$(_tj_ids)" -- "\$cur") ) ;;
                    stop)              COMPREPLY=( \$(compgen -W "\$(_tj_ids) --all" -- "\$cur") ) ;;
                    clear)             COMPREPLY=( \$(compgen -W "--old --dry-run" -- "\$cur") ) ;;
                esac
            fi ;;
        schedule)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "add list run remove templates" -- "\$cur") )
            else
                case "\${COMP_WORDS[2]}" in
                    run|remove) COMPREPLY=( \$(compgen -W "\$(_ts_names)" -- "\$cur") ) ;;
                    add)
                        if [[ "\$prev" == "--day" ]]; then
                            COMPREPLY=( \$(compgen -W "SUN MON TUE WED THU FRI SAT" -- "\$cur") )
                        else
                            COMPREPLY=( \$(compgen -W "--day" -- "\$cur") )
                        fi ;;
                    templates)
                        if [[ \$cword -eq 3 ]]; then
                            COMPREPLY=( \$(compgen -W "list apply" -- "\$cur") )
                        elif [[ "\${COMP_WORDS[3]}" == "apply" ]]; then
                            COMPREPLY=( \$(compgen -W "morning-briefing evening-digest weekly-review inbox-triage meeting-prep focus-reset" -- "\$cur") )
                        fi ;;
                esac
            fi ;;
        add)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "mcp skill" -- "\$cur") )
            else
                case "\${COMP_WORDS[2]}" in
                    mcp)   COMPREPLY=( \$(compgen -W "${_mcp_ids}" -- "\$cur") ) ;;
                    skill) COMPREPLY=( \$(compgen -W "${_skill_ids}" -- "\$cur") ) ;;
                esac
            fi ;;
        remove)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "mcp" -- "\$cur") )
            else
                COMPREPLY=( \$(compgen -W "${_mcp_ids}" -- "\$cur") )
            fi ;;
        list)
            COMPREPLY=( \$(compgen -W "backends mcp skills" -- "\$cur") ) ;;
        skill)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "list run info" -- "\$cur") )
            else
                case "\${COMP_WORDS[2]}" in
                    run|info) COMPREPLY=( \$(compgen -W "${_skill_ids}" -- "\$cur") ) ;;
                esac
            fi ;;
        key)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "set show remove" -- "\$cur") )
            elif [[ "\${COMP_WORDS[2]}" == "set" || "\${COMP_WORDS[2]}" == "remove" ]]; then
                COMPREPLY=( \$(compgen -W "${_backend_ids}" -- "\$cur") )
            fi ;;
        config)
            if [[ \$cword -eq 2 ]]; then
                COMPREPLY=( \$(compgen -W "export import" -- "\$cur") )
            else
                case "\${COMP_WORDS[2]}" in
                    export) COMPREPLY=( \$(compgen -W "--output --no-keys" -- "\$cur") ) ;;
                    import) COMPREPLY=( \$(compgen -f -- "\$cur") ) ;;
                esac
            fi ;;
        ping)
            case "\$prev" in
                --backend) COMPREPLY=( \$(compgen -W "${_backend_ids}" -- "\$cur") ) ;;
                *)         COMPREPLY=( \$(compgen -W "--backend" -- "\$cur") ) ;;
            esac ;;
        doctor)     COMPREPLY=( \$(compgen -W "--fix -f" -- "\$cur") ) ;;
        lang)       COMPREPLY=( \$(compgen -W "en zh" -- "\$cur") ) ;;
        completion) COMPREPLY=( \$(compgen -W "bash zsh install" -- "\$cur") ) ;;
        uninstall)  COMPREPLY=( \$(compgen -W "--yes -y" -- "\$cur") ) ;;
    esac
}
complete -F _tian_complete tian-cli
ENDOFSCRIPT
)

    # Build the zsh completion script (wraps the bash function with zsh's bashcompinit).
    local zsh_script
    zsh_script=$(cat <<ENDZSH
# TIAN CLI zsh completion — generated by: tian-cli completion zsh
# To activate in this session:  eval "\$(tian-cli completion zsh)"
# To activate permanently:      tian-cli completion install
autoload -U +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null || true
autoload -U +X compinit     2>/dev/null && compinit     2>/dev/null || true
${bash_script}
ENDZSH
)

    case "$shell" in
        bash)
            echo "$bash_script"
            ;;
        zsh)
            echo "$zsh_script"
            ;;
        install)
            hdr "TIAN Shell Completion — Install"
            local _profile; _profile=$(profile_file)
            local _shell_name; _shell_name=$(basename "${SHELL:-bash}")

            local _marker='# tian-cli tab completion'
            if grep -qF "$_marker" "$_profile" 2>/dev/null; then
                ok "Completion already installed in $_profile"
                info "Re-running 'tian-cli completion install' will update it — remove the"
                info "  existing block between '$_marker' lines first if you want a clean reinstall."
                return 0
            fi

            local _source_line
            case "$_shell_name" in
                zsh)  _source_line="eval \"\$(tian-cli completion zsh)\"" ;;
                *)    _source_line="eval \"\$(tian-cli completion bash)\"" ;;
            esac

            {
                printf '\n%s\n' "$_marker"
                printf '%s\n' "$_source_line"
                printf '%s\n' "$_marker"
            } >> "$_profile"

            ok "Completion installed into $_profile"
            info "Activate now with:"
            echo ""
            echo "    $_source_line"
            echo ""
            info "Or open a new terminal. Tab completion will be active for all future sessions."
            ;;
    esac
}

# ── Router ────────────────────────────────────────────────────────────────────
CMD="${1:-help}"; shift || true
case "$CMD" in
    setup)      bash "$TIAN_DIR/mac/setup.sh" "$TIAN_DIR" ;;
    install)    cmd_install "$@" ;;
    repair)     cmd_repair ;;
    update)     cmd_update ;;
    doctor)     cmd_doctor "$@" ;;
    status)     cmd_status ;;
    uninstall)  cmd_uninstall "$@" ;;
    add)        cmd_add "$@" ;;
    remove)     cmd_remove "$@" ;;
    run)        cmd_run "$@" ;;
    jobs)       cmd_jobs "$@" ;;
    schedule)   cmd_schedule "$@" ;;
    list)       cmd_list "$@" ;;
    skill)      cmd_skill "$@" ;;
    config)     cmd_config "$@" ;;
    key)        cmd_key "$@" ;;
    ping)       cmd_ping "$@" ;;
    quota)      cmd_quota ;;
    completion) cmd_completion "$@" ;;
    lang)       cmd_lang "$@" ;;
    help|--help|-h) cmd_help ;;
    *) fail "Unknown command '$CMD'. Run: bash tian-cli.sh help" ;;
esac
