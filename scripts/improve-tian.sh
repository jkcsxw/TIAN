#!/usr/bin/env bash
# Periodically checks Claude and Codex quota, then uses whichever has quota
# to improve the TIAN project. Runs as a background loop.
set -euo pipefail

TIAN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$HOME/.tian/tasks/improve-tian.log"
JOBS_FILE="$HOME/.tian/jobs.json"
TASKS_DIR="$HOME/.tian/tasks"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
DIM='\033[2m'; RESET='\033[0m'
# All logging goes to stderr so command-substitution callers get clean stdout
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" >&2; }
ok()   { echo -e "${GREEN}[ok]${RESET} $*" >&2; log "[ok] $*"; }
warn() { echo -e "${YELLOW}[!!]${RESET} $*" >&2; log "[!!] $*"; }
info() { echo -e "${DIM}[..]${RESET} $*" >&2; log "[..] $*"; }

IMPROVE_PROMPT='You are an AI engineer improving the TIAN project — a shell-based installer that helps non-technical users set up AI tools (Claude, Codex, Ollama) on their computers. The project lives at /home/zxk1995/code/TIAN.

Your job: read the codebase, then pick and fully implement ONE improvement. You have full write access to all files. Prioritise by impact:

1. New features that would genuinely help users (e.g. a `tian-cli doctor` command that diagnoses common setup problems, a `tian-cli update` command, an `uninstall` command, multi-backend fallback when one is rate-limited, coloured quota status, a `tian-cli run --watch` mode, wizard improvements, Windows/WSL detection, etc.)
2. Bug fixes for real user-facing problems
3. UX improvements (better error messages, progress indicators, help text)
4. Documentation improvements

Rules:
- Implement the change fully — do not leave TODOs or placeholders
- Do not break existing commands
- Write a short summary at the end: what you changed, which file(s), and why

Start by reading the files you need, then make the change.'

mkdir -p "$TASKS_DIR" "$HOME/.tian"
[[ -f "$JOBS_FILE" ]] || echo '[]' > "$JOBS_FILE"

new_job_id() { date '+%Y%m%d-%H%M%S'-$(openssl rand -hex 3); }

# Returns 0 if command has quota (exit 0 on a trivial probe), 1 if rate-limited
check_claude_quota() {
    local out
    out=$(claude --print "Reply with the single word: ok" 2>&1) || true
    if echo "$out" | grep -qi "rate.limit\|quota\|429\|too many"; then
        return 1
    fi
    return 0
}

check_codex_quota() {
    local out
    out=$(codex --quiet "Reply with the single word: ok" 2>&1) || true
    if echo "$out" | grep -qi "rate.limit\|quota\|429\|too many\|insufficient_quota"; then
        return 1
    fi
    return 0
}

run_improvement() {
    local backend="$1"   # "claude" or "codex"
    local flag="$2"      # --print or --quiet
    local job_id; job_id=$(new_job_id)
    local out_file="$TASKS_DIR/$job_id.txt"

    info "Launching improvement with $backend (job: $job_id)..."

    # Run the AI command, then update job status to done/failed when it finishes
    nohup bash -c '
"$1" "$2" "$3" >"$4" 2>&1
_ec=$?
python3 -c "
import json, sys
jf, jid, code = sys.argv[1], sys.argv[2], int(sys.argv[3])
jobs = json.load(open(jf))
for j in jobs:
    if j[\"id\"] == jid:
        j[\"status\"] = \"done\" if code == 0 else \"failed\"
        break
json.dump(jobs, open(jf, \"w\"), indent=2)
" "$5" "$6" "$_ec"
' -- "$backend" "$flag" "$IMPROVE_PROMPT" "$out_file" "$JOBS_FILE" "$job_id" &>/dev/null &

    python3 - "$JOBS_FILE" "$job_id" "$IMPROVE_PROMPT" "$backend" <<'PYEOF'
import json, sys
from datetime import datetime
jobs_file, jid, prompt, cmd = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
jobs = json.load(open(jobs_file))
jobs.append({"id": jid, "name": "improve-tian", "prompt": prompt, "backend": cmd,
             "status": "running", "createdAt": datetime.now().isoformat()})
json.dump(jobs, open(jobs_file, 'w'), indent=2)
PYEOF
    ok "Improvement job started: $job_id (backend: $backend)"
    echo "$job_id"
}

wait_for_job() {
    local job_id="$1"
    local out_file="$TASKS_DIR/$job_id.txt"
    local max_wait=600   # 10 min max
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        sleep 15
        waited=$((waited + 15))
        # Job is done when the process writing to it has exited (file stops growing)
        local size1; size1=$(wc -c < "$out_file" 2>/dev/null || echo 0)
        sleep 5
        local size2; size2=$(wc -c < "$out_file" 2>/dev/null || echo 0)
        if [[ "$size1" == "$size2" && "$size1" -gt 0 ]]; then
            # Mark completed in jobs.json
            python3 - "$JOBS_FILE" "$job_id" <<'PYEOF'
import json, sys
jobs_file, jid = sys.argv[1], sys.argv[2]
jobs = json.load(open(jobs_file))
for j in jobs:
    if j.get('id') == jid:
        j['status'] = 'completed'
json.dump(jobs, open(jobs_file, 'w'), indent=2)
PYEOF
            return 0
        fi
    done
    warn "Job $job_id timed out after ${max_wait}s"
    return 1
}

# ── Main loop ─────────────────────────────────────────────────────────────────
QUOTA_WAIT_MINUTES="${QUOTA_WAIT_MINUTES:-30}"  # wait when both backends are rate-limited
CYCLE_WAIT_MINUTES="${CYCLE_WAIT_MINUTES:-5}"   # short pause between cycles when quota is available
ITERATIONS="${ITERATIONS:-0}"                   # 0 = run forever

log "=== TIAN improvement loop started (quota_wait=${QUOTA_WAIT_MINUTES}m, cycle_wait=${CYCLE_WAIT_MINUTES}m) ==="

iteration=0
while true; do
    iteration=$((iteration + 1))
    [[ "$ITERATIONS" -gt 0 && "$iteration" -gt "$ITERATIONS" ]] && { log "Reached $ITERATIONS iterations, exiting."; break; }

    log "--- Iteration $iteration ---"

    # Try Claude first, then Codex
    backend=""
    flag=""
    if check_claude_quota; then
        ok "Claude has quota — will use Claude"
        backend="claude"
        flag="--print"
    elif check_codex_quota; then
        ok "Codex has quota — will use Codex"
        backend="codex"
        flag="--quiet"
    else
        warn "Both Claude and Codex are rate-limited. Waiting ${QUOTA_WAIT_MINUTES} minutes..."
        sleep $(( QUOTA_WAIT_MINUTES * 60 ))
        continue
    fi

    job_id=$(run_improvement "$backend" "$flag")
    if wait_for_job "$job_id"; then
        ok "Improvement complete. See: tian-cli jobs result $job_id"
        # Re-check quota immediately — if still available, only pause briefly
        if check_claude_quota || check_codex_quota; then
            info "Quota still available. Waiting ${CYCLE_WAIT_MINUTES} minutes before next cycle..."
            sleep $(( CYCLE_WAIT_MINUTES * 60 ))
        else
            warn "Quota exhausted after job. Waiting ${QUOTA_WAIT_MINUTES} minutes..."
            sleep $(( QUOTA_WAIT_MINUTES * 60 ))
        fi
    else
        warn "Improvement job timed out or failed. Waiting ${CYCLE_WAIT_MINUTES} minutes..."
        sleep $(( CYCLE_WAIT_MINUTES * 60 ))
    fi
done
