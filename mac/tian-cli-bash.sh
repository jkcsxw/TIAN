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

ensure_dirs() {
    mkdir -p "$TASKS_DIR" "$HOME/.tian"
    [[ -f "$JOBS_FILE" ]] || echo '[]' > "$JOBS_FILE"
    [[ -f "$SCHEDULES_FILE" ]] || echo '[]' > "$SCHEDULES_FILE"
}

resolve_schedule_name_by_prompt() {
    local prompt="${1:-}"
    python3 - "$SCHEDULES_FILE" "$prompt" <<'PYEOF'
import json, sys
try:
    schedules = json.load(open(sys.argv[1]))
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
    jobs = json.load(open(jobs_file))
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
    json.dump(jobs, open(jobs_file, "w"), indent=2)
PYEOF
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
jobs = json.load(open(jobs_file))
for job in jobs:
    if job.get("id") == job_id:
        job["status"] = "stopped"
        job["finishedAt"] = datetime.now().isoformat()
        job["stopReason"] = reason
        break
json.dump(jobs, open(jobs_file, "w"), indent=2)
PYEOF
        ok "Stopped job $jid"
    done < <(python3 - "$JOBS_FILE" "$target" <<'PYEOF'
import json, sys

jobs_file, target = sys.argv[1], sys.argv[2]
jobs = json.load(open(jobs_file))
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
cat <<EOF

  TIAN CLI
  Talk Is All you Need

$(rule)

  USAGE
    tian-cli.sh <command> [options]

  COMMANDS
    setup               Re-run the interactive setup wizard
    update              Upgrade installed AI backends to their latest versions
    doctor              Check your setup and diagnose common problems
    uninstall           Remove TIAN's installed components (backends, keys, data)
    status              Show what is installed
    list mcp            List available MCP servers
    list skills         List available skills
    run "prompt"        Run a task (foreground)
    run "prompt" -b     Run a task in the background
    jobs                List background jobs
    jobs result <id>    Show output of a completed job
    jobs tail <id>      Stream live output of a running job (or show result if done)
    jobs stop <id>      Stop a running job (--all stops every running job)
    jobs clear          Clear completed jobs
    schedule add        Create a recurring task (crontab on Linux, launchd on macOS)
    schedule list       List scheduled tasks
    schedule run <n>    Run a scheduled task now
    schedule remove <n> Delete a scheduled task
    help                Show this help

  EXAMPLES
    bash tian-cli.sh run "Summarise today's AI news"
    bash tian-cli.sh run "Draft my weekly report" -b
    bash tian-cli.sh jobs
    bash tian-cli.sh schedule add morning-brief "Morning briefing" 08:00 daily
    bash tian-cli.sh schedule list

EOF
}

cmd_status() {
    hdr "TIAN Status"
    command -v node &>/dev/null && ok "Node.js    $(node --version)" || warn "Node.js    not found"
    python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, os, sys
c = json.load(open(sys.argv[1]))
print()
for b in c['backends']:
    cmd = b.get('cliCommand','')
    if not cmd: continue
    found = subprocess.run(['which', cmd], capture_output=True).returncode == 0
    status = '[ok]' if found else '[!!]'
    print(f'  {status}  {b["displayName"]}')
print()
for b in c['backends']:
    env = b.get('apiKeyEnvVar','')
    if not env: continue
    val = os.environ.get(env,'')
    status = '[ok]' if val else '[!!]'
    print(f'  {status}  {env}')
PYEOF
    # Bug fix: check platform-appropriate MCP config path
    local platform; platform=$(detect_platform)
    local mcp_config
    if [[ "$platform" == "macos" ]]; then
        mcp_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    else
        mcp_config="$HOME/.config/claude/claude_desktop_config.json"
    fi
    echo ""
    [[ -f "$mcp_config" ]] && ok "MCP config: $mcp_config" || warn "MCP config not found"
    [[ -f "$TIAN_DIR/launcher.sh" ]] && ok "launcher.sh exists" || warn "launcher.sh not found — run setup.sh first"
    echo ""; rule
}

cmd_run() {
    local prompt="$1"; shift || true
    local background=false
    local job_name=""
    local schedule_name=""
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            -b|--background)
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
            *)
                shift
                ;;
        esac
    done

    local backend_row; backend_row=$(active_backend)
    local cmd; cmd=$(echo "$backend_row" | cut -d'|' -f1)
    local flag; flag=$(echo "$backend_row" | cut -d'|' -f2)

    [[ -z "$cmd" ]] && fail "No AI backend found. Run: bash setup.sh"

    ensure_dirs
    local job_id; job_id=$(new_job_id)
    local out_file="$TASKS_DIR/$job_id.txt"
    [[ -n "$schedule_name" ]] || schedule_name=$(resolve_schedule_name_by_prompt "$prompt")
    [[ -n "$job_name" ]] || [[ -z "$schedule_name" ]] || job_name="$schedule_name"

    if $background; then
        info "Running in background (job: $job_id)..."
        # Run AI command, then classify quota exhaustion so scheduled jobs can be disabled.
        nohup bash -c '
"$1" "$2" "$3" >"$4" 2>&1
_ec=$?
python3 -c "
import json, os, re, subprocess, sys
jf, jid, code, out_file, schedule_name, tian_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
jobs = json.load(open(jf))
text = open(out_file, encoding=\"utf-8\", errors=\"ignore\").read() if os.path.exists(out_file) else \"\"
quota = re.search(r\"insufficient_quota|quota(?:\\s+is)?\\s+exhausted|quota_exhausted|rate\\.limit|rate limit|429|too many requests|overloaded\", text, re.I) is not None
for j in jobs:
    if j[\"id\"] == jid:
        j[\"status\"] = \"stopped\" if quota else (\"done\" if code == 0 else \"failed\")
        if quota:
            j[\"stopReason\"] = \"quota_exhausted\"
        break
json.dump(jobs, open(jf, \"w\"), indent=2)
if quota and schedule_name:
    subprocess.run([\"bash\", os.path.join(tian_dir, \"tian-cli.sh\"), \"schedule\", \"remove\", schedule_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
" "$5" "$6" "$_ec" "$4" "$7" "$8"
' -- "$cmd" "$flag" "$prompt" "$out_file" "$JOBS_FILE" "$job_id" "$schedule_name" "$TIAN_DIR" &>/dev/null &
        local pid=$!
        python3 - "$JOBS_FILE" "$job_id" "$prompt" "$cmd" "$pid" "$job_name" "$schedule_name" <<'PYEOF'
import json, sys
from datetime import datetime
jobs_file, jid, prompt, cmd, pid, job_name, schedule_name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), sys.argv[6], sys.argv[7]
jobs = json.load(open(jobs_file))
jobs.append({"id": jid, "name": job_name or jid, "prompt": prompt, "backend": cmd,
             "scheduleName": schedule_name or "", "status": "running",
             "createdAt": datetime.now().isoformat(), "pid": pid})
json.dump(jobs, open(jobs_file, 'w'), indent=2)
PYEOF
        ok "Job started: $job_id"
        info "Check result with: bash tian-cli.sh jobs result $job_id"
    else
        rule
        # Bug fix: pass prompt as argument, not via eval string interpolation
        "$cmd" "$flag" "$prompt" | tee "$out_file"
        rule
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
            [[ -f "$f" ]] && cat "$f" || fail "Job '$id' not found."
            ;;
        tail)
            local id="${1:-}"; [[ -z "$id" ]] && fail "Usage: jobs tail <job-id>"
            local f="$TASKS_DIR/$id.txt"
            [[ -f "$f" ]] || fail "Job '$id' not found."
            local status
            status=$(python3 - "$JOBS_FILE" "$id" <<'PYEOF'
import json, sys
jobs = json.load(open(sys.argv[1]))
j = next((x for x in jobs if x.get('id') == sys.argv[2]), None)
print(j.get('status', 'unknown') if j else 'unknown')
PYEOF
)
            if [[ "$status" == "running" ]]; then
                info "Job $id is still running — streaming output (Ctrl+C to stop)..."
                tail -f "$f"
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
        clear)
            python3 - "$JOBS_FILE" "$TASKS_DIR" <<'PYEOF'
import json, sys, os, glob
jobs_file, tasks_dir = sys.argv[1], sys.argv[2]
jobs = json.load(open(jobs_file))
keep = [j for j in jobs if j.get('status') == 'running']
for j in [x for x in jobs if x.get('status') != 'running']:
    for f in glob.glob(f"{tasks_dir}/{j['id']}*"):
        os.remove(f)
json.dump(keep, open(jobs_file, 'w'), indent=2)
print(f"  Cleared {len(jobs)-len(keep)} completed jobs.")
PYEOF
            ;;
        *)
            ensure_dirs
            python3 - "$JOBS_FILE" <<'PYEOF'
import json, sys
jobs = json.load(open(sys.argv[1]))
if not jobs:
    print("  No jobs yet. Run: bash tian-cli.sh run \"your task\"")
else:
    print(f"\n  {'ID':<30} {'STATUS':<10} PROMPT")
    print("  " + "─"*70)
    for j in reversed(jobs[-20:]):
        jid    = j.get('id','?')[:28]
        status = j.get('status','?').upper()
        prompt = j.get('prompt','')[:50]
        print(f"  {jid:<30} {status:<10} {prompt}...")
    print()
PYEOF
            ;;
    esac
}

# ── Schedule helpers ───────────────────────────────────────────────────────────

_schedule_add_linux() {
    local name="$1" prompt="$2" time="$3" repeat="$4"
    local hour minute cron_expr
    hour=$(echo "$time" | cut -d: -f1)
    minute=$(echo "$time" | cut -d: -f2)

    case "$repeat" in
        hourly) cron_expr="0 * * * *" ;;
        daily)  cron_expr="$minute $hour * * *" ;;
        weekly) cron_expr="$minute $hour * * 1" ;;
        once)   cron_expr="@reboot" ;;
        *)      cron_expr="$minute $hour * * *" ;;
    esac

    local job_line="$cron_expr  bash '$TIAN_DIR/tian-cli.sh' schedule run '$name'  # tian-$name"

    # Remove existing entry for this name then append new one
    ( crontab -l 2>/dev/null | grep -v "# tian-$name" ; echo "$job_line" ) | crontab -

    python3 - "$SCHEDULES_FILE" "$name" "$prompt" "$time" "$repeat" "" <<'PYEOF'
import json, sys
from datetime import datetime
sf, name, prompt, time, repeat, _ = sys.argv[1:]
schedules = json.load(open(sf))
schedules = [s for s in schedules if s.get('name') != name]
schedules.append({"name": name, "prompt": prompt, "time": time, "repeat": repeat,
                  "createdAt": datetime.now().isoformat()})
json.dump(schedules, open(sf, 'w'), indent=2)
PYEOF
    ok "Schedule '$name' created ($repeat at $time) via crontab."
    info "Results will appear in: bash tian-cli.sh jobs"
}

_schedule_add_macos() {
    local name="$1" prompt="$2" time="$3" repeat="$4"
    local plist_dir="$HOME/Library/LaunchAgents"
    local plist_label="com.tian.$name"
    local plist_file="$plist_dir/$plist_label.plist"
    mkdir -p "$plist_dir"

    local hour; hour=$(echo "$time" | cut -d: -f1 | sed 's/^0//')
    local minute; minute=$(echo "$time" | cut -d: -f2 | sed 's/^0//')

    local interval_block=""
    case "$repeat" in
        hourly) interval_block="<key>StartInterval</key><integer>3600</integer>" ;;
        daily)  interval_block="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
        weekly) interval_block="<key>StartCalendarInterval</key><dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
        once)   interval_block="" ;;
        *)      interval_block="<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
    esac

    cat > "$plist_file" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$plist_label</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$TIAN_DIR/tian-cli.sh</string>
        <string>schedule</string>
        <string>run</string>
        <string>$name</string>
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

    python3 - "$SCHEDULES_FILE" "$name" "$prompt" "$time" "$repeat" "$plist_file" <<'PYEOF'
import json, sys
from datetime import datetime
sf, name, prompt, time, repeat, plist = sys.argv[1:]
schedules = json.load(open(sf))
schedules = [s for s in schedules if s.get('name') != name]
schedules.append({"name": name, "prompt": prompt, "time": time, "repeat": repeat,
                  "plistFile": plist, "createdAt": datetime.now().isoformat()})
json.dump(schedules, open(sf, 'w'), indent=2)
PYEOF
    ok "Schedule '$name' created ($repeat at $time) via launchd."
    info "Results will appear in: bash tian-cli.sh jobs"
}

_schedule_remove_linux() {
    local name="$1"
    ( crontab -l 2>/dev/null | grep -v "# tian-$name" ) | crontab - 2>/dev/null || true
}

_schedule_remove_macos() {
    local plist_file="$1"
    if [[ -n "$plist_file" && -f "$plist_file" ]]; then
        launchctl unload "$plist_file" 2>/dev/null || launchctl bootout "gui/$(id -u)" "$plist_file" 2>/dev/null || true
        rm -f "$plist_file"
    fi
}

cmd_schedule() {
    local sub="${1:-list}"; shift || true
    local platform; platform=$(detect_platform)

    case "$sub" in
        add)
            local name="${1:-}"; local prompt="${2:-}"; local time="${3:-08:00}"; local repeat="${4:-daily}"
            [[ -z "$name" || -z "$prompt" ]] && fail "Usage: schedule add <name> \"prompt\" [HH:MM] [daily|weekly|hourly|once]"
            [[ ! "$time" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] && fail "Invalid time '$time'. Use HH:MM format (e.g. 08:30)."
            [[ ! "$repeat" =~ ^(daily|weekly|hourly|once)$ ]] && fail "Invalid repeat '$repeat'. Choose: daily, weekly, hourly, once."
            ensure_dirs
            if [[ "$platform" == "linux" ]]; then
                _schedule_add_linux "$name" "$prompt" "$time" "$repeat"
            else
                _schedule_add_macos "$name" "$prompt" "$time" "$repeat"
            fi
            ;;

        list)
            ensure_dirs
            python3 - "$SCHEDULES_FILE" <<'PYEOF'
import json, sys
schedules = json.load(open(sys.argv[1]))
if not schedules:
    print("  No schedules. Create one with: bash tian-cli.sh schedule add <name> \"prompt\" HH:MM daily")
else:
    print(f"\n  {'NAME':<22} {'REPEAT':<10} {'TIME':<8} PROMPT")
    print("  " + "─"*70)
    for s in schedules:
        print(f"  {s['name']:<22} {s['repeat']:<10} {s['time']:<8} {s['prompt'][:40]}...")
    print()
PYEOF
            ;;

        run)
            local name="${1:-}"; [[ -z "$name" ]] && fail "Usage: schedule run <name>"
            ensure_dirs
            local prompt
            prompt=$(python3 - "$SCHEDULES_FILE" "$name" <<'PYEOF'
import json, sys
s = json.load(open(sys.argv[1]))
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
s = json.load(open(sys.argv[1]))
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
schedules = [s for s in json.load(open(sf)) if s.get('name') != name]
json.dump(schedules, open(sf, 'w'), indent=2)
PYEOF
            ok "Schedule '$name' removed."
            ;;

        *) fail "Usage: schedule add|list|run|remove" ;;
    esac
}

cmd_update() {
    hdr "TIAN Update — Upgrade AI Backends"

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

cmd_doctor() {
    hdr "TIAN Doctor — Setup Diagnostics"
    local platform; platform=$(detect_platform)
    case "$platform" in
        macos) info "Platform: macOS" ;;
        wsl)   info "Platform: Linux (WSL)" ;;
        linux) info "Platform: Linux" ;;
        *)     warn "Platform: unknown ($(uname -s))" ;;
    esac
    echo ""
    local issues=0

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
    python3 - "$CATALOG" <<'PYEOF'
import json, subprocess, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    cmd = b.get('cliCommand', '')
    if not cmd: continue
    ok = subprocess.run(['which', cmd], capture_output=True).returncode == 0
    sym = '[ok]' if ok else '[!!]'
    npm = b.get('npmPackage', b.get('downloadUrl', 'see docs'))
    hint = f" (install: npm install -g {npm})" if not ok else ''
    print(f"  {sym}  {b['displayName']}{hint}")
PYEOF
    echo ""

    echo -e "${BOLD}  API keys${RESET}"
    python3 - "$CATALOG" <<'PYEOF'
import json, os, subprocess, sys
c, seen = json.load(open(sys.argv[1])), set()
for b in c['backends']:
    env = b.get('apiKeyEnvVar', ''); cmd = b.get('cliCommand', '')
    if not env or env in seen: continue
    seen.add(env)
    installed = cmd and subprocess.run(['which', cmd], capture_output=True).returncode == 0
    val = os.environ.get(env, '')
    if val:
        print(f"  [ok]  {env} is set ({val[:8]}...)")
    elif installed:
        print(f"  [!!]  {env} not set — get key: {b.get('apiKeyUrl', 'see docs')}")
    else:
        print(f"  [..]  {env} (backend not installed)")
PYEOF
    echo ""

    echo -e "${BOLD}  Config files${RESET}"
    local mcp_config
    [[ "$platform" == "macos" ]] \
        && mcp_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
        || mcp_config="$HOME/.config/claude/claude_desktop_config.json"
    if [[ -f "$mcp_config" ]]; then
        python3 -c "import json; json.load(open('$mcp_config'))" 2>/dev/null \
            && ok "MCP config valid: $mcp_config" \
            || { warn "MCP config has invalid JSON: $mcp_config"; ((issues++)) || true; }
    else
        info "MCP config not found (optional): $mcp_config"
    fi
    [[ -f "$CATALOG" ]] && ok "catalog.json found" || { warn "catalog.json missing — reinstall TIAN"; ((issues++)) || true; }
    [[ -f "$TIAN_DIR/launcher.sh" ]] && ok "launcher.sh found" || { warn "launcher.sh missing — run setup"; ((issues++)) || true; }
    echo ""

    rule
    if [[ $issues -eq 0 ]]; then
        ok "All checks passed — TIAN looks healthy!"
    else
        warn "$issues problem(s) found. Follow the hints above, then re-run: tian-cli doctor"
    fi
    echo ""
}

cmd_list() {
    local sub="${1:-}"; shift || true
    case "$sub" in
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
        *) fail "Usage: list mcp  |  list skills" ;;
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

    local platform; platform=$(detect_platform)
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
c = json.load(open(catalog_path))
env_vars = set(b.get('apiKeyEnvVar','') for b in c['backends'] if b.get('apiKeyEnvVar'))
lines = open(profile).readlines()
kept = [l for l in lines if not any(re.search(rf'export\s+{v}\s*=', l) for v in env_vars)]
removed = len(lines) - len(kept)
if removed:
    open(profile, 'w').writelines(kept)
    print(f"  [ok]  Removed {removed} API key export(s) from {profile}")
else:
    print(f"  [..]  No TIAN API key exports found in {profile}")
PYEOF
    ((removed++)) || true

    # ── 3. Remove MCP config entries written by TIAN ─────────────────────────
    echo ""
    echo -e "${BOLD}  Cleaning MCP config${RESET}"
    local mcp_config
    [[ "$platform" == "macos" ]] \
        && mcp_config="$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
        || mcp_config="$HOME/.config/claude/claude_desktop_config.json"

    if [[ -f "$mcp_config" ]]; then
        python3 - "$CATALOG" "$mcp_config" <<'PYEOF'
import json, sys, os
catalog_path, cfg_path = sys.argv[1], sys.argv[2]
c     = json.load(open(catalog_path))
tian_keys = set(s.get('configKey','') for s in c.get('mcpServers',[]) if s.get('configKey'))
cfg   = json.load(open(cfg_path))
mcp   = cfg.get('mcpServers', {})
before = set(mcp.keys())
for k in list(mcp.keys()):
    if k in tian_keys:
        del mcp[k]
after = set(mcp.keys())
removed = before - after
if removed:
    json.dump(cfg, open(cfg_path, 'w'), indent=2)
    print(f"  [ok]  Removed {len(removed)} MCP server(s) from config: {', '.join(removed)}")
else:
    print(f"  [..]  No TIAN MCP entries found in config")
PYEOF
    else
        info "MCP config not found — skipping"
    fi

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

# ── Router ────────────────────────────────────────────────────────────────────
CMD="${1:-help}"; shift || true
case "$CMD" in
    setup)     bash "$TIAN_DIR/mac/setup.sh" "$TIAN_DIR" ;;
    update)    cmd_update ;;
    doctor)    cmd_doctor ;;
    status)    cmd_status ;;
    uninstall) cmd_uninstall "$@" ;;
    run)       cmd_run "$@" ;;
    jobs)      cmd_jobs "$@" ;;
    schedule)  cmd_schedule "$@" ;;
    list)      cmd_list "$@" ;;
    help|--help|-h) cmd_help ;;
    *) fail "Unknown command '$CMD'. Run: bash tian-cli.sh help" ;;
esac
