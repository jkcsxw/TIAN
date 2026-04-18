#!/usr/bin/env bash
# TIAN native bash CLI — used on Mac when PowerShell Core (pwsh) is not installed
set -euo pipefail
TIAN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
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

py3() { python3 -c "$1" 2>/dev/null; }

active_backend() {
    py3 "
import json
c = json.load(open('$CATALOG'))
for b in c['backends']:
    cmd = b.get('cliCommand','')
    flag = b.get('nonInteractiveFlag','')
    if cmd:
        print(cmd+'|'+flag+'|'+b['id'])
        break
"
}

ensure_dirs() {
    mkdir -p "$TASKS_DIR" "$HOME/.tian"
    [[ -f "$JOBS_FILE" ]] || echo '[]' > "$JOBS_FILE"
    [[ -f "$SCHEDULES_FILE" ]] || echo '[]' > "$SCHEDULES_FILE"
}

new_job_id() { date '+%Y%m%d-%H%M%S'-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6); }

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_help() {
cat <<EOF

  TIAN CLI  (macOS bash mode)
  Talk Is All you Need

$(rule)

  USAGE
    tian-cli.sh <command> [options]

  COMMANDS
    setup               Re-run the interactive setup wizard
    status              Show what is installed
    list mcp            List available MCP servers
    list skills         List available skills
    run "prompt"        Run a task (foreground)
    run "prompt" -b     Run a task in the background
    jobs                List background jobs
    jobs result <id>    Show output of a completed job
    jobs clear          Clear completed jobs
    schedule add        Create a recurring task (uses launchd)
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
    py3 "
import json, subprocess, os
c = json.load(open('$CATALOG'))
print()
for b in c['backends']:
    cmd = b.get('cliCommand','')
    if not cmd: continue
    found = subprocess.run(['which', cmd], capture_output=True).returncode == 0
    status = '[ok]' if found else '[!!]'
    print(f'  {status}  {b[\"displayName\"]}'  )
print()
for b in c['backends']:
    env = b.get('apiKeyEnvVar','')
    if not env: continue
    val = os.environ.get(env,'')
    status = '[ok]' if val else '[!!]'
    print(f'  {status}  {env}')
"
    MCP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    echo ""
    [[ -f "$MCP_CONFIG" ]] && ok "MCP config: $MCP_CONFIG" || warn "MCP config not found"
    [[ -f "$TIAN_DIR/launcher.sh" ]] && ok "launcher.sh exists" || warn "launcher.sh not found — run setup.sh first"
    echo ""; rule
}

cmd_run() {
    local prompt="$1"; shift || true
    local background=false
    [[ "${1:-}" == "-b" || "${1:-}" == "--background" ]] && background=true

    local backend_row; backend_row=$(active_backend)
    local cmd; cmd=$(echo "$backend_row" | cut -d'|' -f1)
    local flag; flag=$(echo "$backend_row" | cut -d'|' -f2)

    [[ -z "$cmd" ]] && fail "No AI backend found. Run: bash setup.sh"

    ensure_dirs
    local job_id; job_id=$(new_job_id)
    local out_file="$TASKS_DIR/$job_id.txt"

    if $background; then
        info "Running in background (job: $job_id)..."
        nohup bash -c "$cmd $flag \"$prompt\" > \"$out_file\" 2>&1" &>/dev/null &
        python3 - "$JOBS_FILE" "$job_id" "$prompt" "$cmd" <<'PYEOF'
import json, sys
jobs_file, jid, prompt, cmd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
from datetime import datetime
jobs = json.load(open(jobs_file))
jobs.append({"id": jid, "name": jid, "prompt": prompt, "backend": cmd,
             "status": "running", "createdAt": datetime.now().isoformat()})
json.dump(jobs, open(jobs_file, 'w'), indent=2)
PYEOF
        ok "Job started: $job_id"
        info "Check result with: bash tian-cli.sh jobs result $job_id"
    else
        rule
        eval "$cmd $flag \"$prompt\"" | tee "$out_file"
        rule
    fi
}

cmd_jobs() {
    local sub="${1:-}"; shift || true
    ensure_dirs
    case "$sub" in
        result)
            local id="${1:-}"; [[ -z "$id" ]] && fail "Usage: jobs result <job-id>"
            local f="$TASKS_DIR/$id.txt"
            [[ -f "$f" ]] && cat "$f" || fail "Job '$id' not found."
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
from datetime import datetime
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

cmd_schedule() {
    local sub="${1:-list}"; shift || true
    case "$sub" in
        add)
            local name="${1:-}"; local prompt="${2:-}"; local time="${3:-08:00}"; local repeat="${4:-daily}"
            [[ -z "$name" || -z "$prompt" ]] && fail "Usage: schedule add <name> \"prompt\" [HH:MM] [daily|weekly|hourly|once]"
            ensure_dirs

            local plist_dir="$HOME/Library/LaunchAgents"
            local plist_label="com.tian.$name"
            local plist_file="$plist_dir/$plist_label.plist"
            mkdir -p "$plist_dir"

            local hour; hour=$(echo "$time" | cut -d: -f1 | sed 's/^0//')
            local minute; minute=$(echo "$time" | cut -d: -f2 | sed 's/^0//')

            local interval_key interval_val
            case "$repeat" in
                hourly) interval_key="<key>StartInterval</key>"; interval_val="<integer>3600</integer>" ;;
                daily)  interval_key="<key>StartCalendarInterval</key>"; interval_val="<dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
                weekly) interval_key="<key>StartCalendarInterval</key>"; interval_val="<dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
                once)   interval_key=""; interval_val="" ;;
                *)      interval_key="<key>StartCalendarInterval</key>"; interval_val="<dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>" ;;
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
        <string>run</string>
        <string>$prompt</string>
        <string>-b</string>
    </array>
    <key>StandardOutPath</key>
    <string>$HOME/.tian/tasks/schedule-$name.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.tian/tasks/schedule-$name.err</string>
    $interval_key
    $interval_val
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
            ok "Schedule '$name' created ($repeat at $time)."
            info "Results will appear in: bash tian-cli.sh jobs"
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
            local prompt
            prompt=$(python3 -c "
import json, sys
s = json.load(open('$SCHEDULES_FILE'))
e = next((x for x in s if x['name'] == '$name'), None)
print(e['prompt'] if e else '')
")
            [[ -z "$prompt" ]] && fail "Schedule '$name' not found."
            info "Running '$name' now..."
            cmd_run "$prompt" -b
            ;;

        remove)
            local name="${1:-}"; [[ -z "$name" ]] && fail "Usage: schedule remove <name>"
            ensure_dirs
            local plist_file
            plist_file=$(python3 -c "
import json
s = json.load(open('$SCHEDULES_FILE'))
e = next((x for x in s if x['name'] == '$name'), None)
print(e.get('plistFile','') if e else '')
")
            if [[ -n "$plist_file" && -f "$plist_file" ]]; then
                launchctl unload "$plist_file" 2>/dev/null || launchctl bootout "gui/$(id -u)" "$plist_file" 2>/dev/null || true
                rm -f "$plist_file"
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

cmd_list() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        mcp)
            hdr "Available MCP Servers"
            py3 "
import json
c = json.load(open('$CATALOG'))
for s in c['mcpServers']:
    print(f\"  {s['id']:<22} {s['displayName']:<28} {s['category']}\")
"
            rule ;;
        skills)
            hdr "Available Skills"
            py3 "
import json
c = json.load(open('$CATALOG'))
for s in c['skills']:
    print(f\"  {s['id']:<26} {s['displayName']:<30} {s['category']}\")
"
            rule ;;
        *) fail "Usage: list mcp  |  list skills" ;;
    esac
}

# ── Router ────────────────────────────────────────────────────────────────────
CMD="${1:-help}"; shift || true
case "$CMD" in
    setup)    bash "$TIAN_DIR/mac/setup.sh" "$TIAN_DIR" ;;
    status)   cmd_status ;;
    run)      cmd_run "$@" ;;
    jobs)     cmd_jobs "$@" ;;
    schedule) cmd_schedule "$@" ;;
    list)     cmd_list "$@" ;;
    help|--help|-h) cmd_help ;;
    *) fail "Unknown command '$CMD'. Run: bash tian-cli.sh help" ;;
esac
