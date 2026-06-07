#!/usr/bin/env bash
# Tests for bash job management (mac/tian-cli-bash.sh helper functions)
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
TMPDIR_TEST=$(make_temp_dir)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Source only the helper functions we need by extracting them into a test harness
TASKS_DIR="$TMPDIR_TEST/tasks"
JOBS_FILE="$TMPDIR_TEST/jobs.json"
mkdir -p "$TASKS_DIR"
echo '[]' > "$JOBS_FILE"

# Re-implement the subset of functions we're unit-testing
new_job_id() { date '+%Y%m%d-%H%M%S'-$(openssl rand -hex 3); }

ensure_dirs() {
    mkdir -p "$TASKS_DIR" "$(dirname "$JOBS_FILE")"
    [[ -f "$JOBS_FILE" ]] || echo '[]' > "$JOBS_FILE"
}

read_jobs() { python3 -c "
import json, sys
try:
    data = json.load(open('$JOBS_FILE'))
    if not isinstance(data, list): data = [data]
    print(json.dumps(data))
except: print('[]')
"; }

save_jobs() {
    local json="$1"
    echo "$json" > "$JOBS_FILE"
}

resolve_schedule_name_by_prompt() {
    local prompt="$1"
    python3 - "$TMPDIR_TEST/schedules.json" "$prompt" <<'PYEOF'
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

sync_job_statuses() {
    python3 - "$JOBS_FILE" "$TASKS_DIR" <<'PYEOF'
import json, os, re, sys
from datetime import datetime

jobs_file, tasks_dir = sys.argv[1], sys.argv[2]
jobs = json.load(open(jobs_file))
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
    if alive:
        continue
    out_file = os.path.join(tasks_dir, f"{job['id']}.txt")
    text = open(out_file, encoding="utf-8", errors="ignore").read() if os.path.exists(out_file) else ""
    quota = re.search(r"insufficient_quota|quota(?:\s+is)?\s+exhausted|quota_exhausted|rate\.limit|rate limit|429|too many requests|overloaded", text, re.I) is not None
    job["status"] = "stopped" if quota else "done"
    job["finishedAt"] = datetime.now().isoformat()
    if quota:
        job["stopReason"] = "quota_exhausted"
json.dump(jobs, open(jobs_file, "w"), indent=2)
PYEOF
}

# ─────────────────────────────────────────────────────────────────────────────

suite "new_job_id"

_test_id_format() {
    local id
    id=$(new_job_id)
    assert_match "$id" '^[0-9]{8}-[0-9]{6}-[a-z0-9]{6}$'
}
it "matches yyyyMMdd-HHmmss-xxxxxx format" _test_id_format

_test_id_unique() {
    local id1 id2
    id1=$(new_job_id)
    sleep 0.05
    id2=$(new_job_id)
    [[ "$id1" != "$id2" ]]
}
it "two rapid calls produce different IDs" _test_id_unique

suite "read_jobs / save_jobs round-trip"

_test_read_empty() {
    echo '[]' > "$JOBS_FILE"
    local result
    result=$(read_jobs)
    assert_eq "$result" "[]"
}
it "returns empty array when file is empty list" _test_read_empty

_test_roundtrip() {
    local data='[{"id":"j1","status":"done"},{"id":"j2","status":"running"}]'
    save_jobs "$data"
    local result
    result=$(read_jobs)
    assert_contains "$result" '"j1"'
    assert_contains "$result" '"j2"'
}
it "round-trips multi-item array" _test_roundtrip

_test_single_item_array() {
    echo '{"id":"single","status":"done"}' > "$JOBS_FILE"
    local result
    result=$(read_jobs)
    assert_contains "$result" '"single"'
}
it "normalises single-object file to array" _test_single_item_array

suite "ensure_dirs"

_test_ensure_dirs() {
    local d="$TMPDIR_TEST/newdirs"
    TASKS_DIR="$d/tasks"
    JOBS_FILE="$d/jobs.json"
    ensure_dirs
    assert_dir_exists "$TASKS_DIR"
    assert_file_exists "$JOBS_FILE"
    TASKS_DIR="$TMPDIR_TEST/tasks"
    JOBS_FILE="$TMPDIR_TEST/jobs.json"
}
it "creates tasks dir and empty jobs file" _test_ensure_dirs

suite "resolve_schedule_name_by_prompt"

_test_resolve_unique_schedule() {
    echo '[{"name":"brief","prompt":"hello"},{"name":"other","prompt":"world"}]' > "$TMPDIR_TEST/schedules.json"
    local result
    result=$(resolve_schedule_name_by_prompt "hello")
    assert_eq "$result" "brief"
}
it "returns a matching schedule name for a unique prompt" _test_resolve_unique_schedule

_test_resolve_duplicate_schedule() {
    echo '[{"name":"a","prompt":"dup"},{"name":"b","prompt":"dup"}]' > "$TMPDIR_TEST/schedules.json"
    local result
    result=$(resolve_schedule_name_by_prompt "dup")
    assert_empty "$result"
}
it "returns empty when multiple schedules share the same prompt" _test_resolve_duplicate_schedule

suite "sync_job_statuses"

_test_sync_marks_done() {
    local id="job-done"
    echo '[{"id":"job-done","status":"running","pid":999999}]' > "$JOBS_FILE"
    echo 'normal output' > "$TASKS_DIR/$id.txt"
    sync_job_statuses
    local result
    result=$(read_jobs)
    assert_contains "$result" '"status": "done"'
}
it "marks dead running jobs as done when output is normal" _test_sync_marks_done

_test_sync_marks_quota_stopped() {
    local id="job-quota"
    echo '[{"id":"job-quota","status":"running","pid":999999,"scheduleName":"brief"}]' > "$JOBS_FILE"
    echo 'Error 429 insufficient_quota' > "$TASKS_DIR/$id.txt"
    sync_job_statuses
    local result
    result=$(read_jobs)
    assert_contains "$result" '"status": "stopped"'
    assert_contains "$result" '"stopReason": "quota_exhausted"'
}
it "marks dead running jobs as stopped when quota is exhausted" _test_sync_marks_quota_stopped

suite "background multi-backend fallback"

_test_bg_fallback_tries_second_backend() {
    local out_file="$TMPDIR_TEST/bg-fallback.txt"
    local _ec=1

    # Build a fake backends list: first cmd returns quota error, second succeeds
    local bin_dir="$TMPDIR_TEST/fakebins"
    mkdir -p "$bin_dir"
    printf '#!/bin/sh\necho "429 insufficient_quota"\nexit 1\n' > "$bin_dir/fake-quota-backend"
    printf '#!/bin/sh\necho "Task completed successfully"\nexit 0\n'  > "$bin_dir/fake-ok-backend"
    chmod +x "$bin_dir/fake-quota-backend" "$bin_dir/fake-ok-backend"

    local saved_PATH="$PATH"
    export PATH="$bin_dir:$PATH"

    # Simulate the inner nohup fallback loop from cmd_run
    local backends
    backends=$(printf 'fake-quota-backend|\nfake-ok-backend|\n')
    while IFS="|" read -r r_cmd r_flag; do
        [[ -z "$r_cmd" ]] && continue
        $r_cmd $r_flag "test prompt" >"$out_file" 2>&1
        _ec=$?
        grep -qiE "insufficient_quota|quota(_is_)?exhausted|quota is exhausted|rate[._]limit|rate limit|429|too many requests|overloaded" "$out_file" 2>/dev/null && continue
        break
    done <<< "$backends"

    export PATH="$saved_PATH"

    assert_contains "$(cat "$out_file" 2>/dev/null)" "Task completed successfully"
    [[ "$_ec" -eq 0 ]]
}
it "falls back to second backend when first hits a quota error" _test_bg_fallback_tries_second_backend

_test_bg_fallback_quota_when_all_fail() {
    local out_file="$TMPDIR_TEST/bg-allfail.txt"
    local _ec=0

    local bin_dir="$TMPDIR_TEST/fakebins2"
    mkdir -p "$bin_dir"
    printf '#!/bin/sh\necho "rate limit exceeded"\nexit 1\n' > "$bin_dir/fake-rl-backend"
    chmod +x "$bin_dir/fake-rl-backend"

    local saved_PATH="$PATH"
    export PATH="$bin_dir:$PATH"

    local backends
    backends="fake-rl-backend|"
    while IFS="|" read -r r_cmd r_flag; do
        [[ -z "$r_cmd" ]] && continue
        $r_cmd $r_flag "test prompt" >"$out_file" 2>&1
        _ec=$?
        grep -qiE "insufficient_quota|quota(_is_)?exhausted|quota is exhausted|rate[._]limit|rate limit|429|too many requests|overloaded" "$out_file" 2>/dev/null && continue
        break
    done <<< "$backends"

    export PATH="$saved_PATH"

    # Output file should contain the quota error from the only backend
    assert_contains "$(cat "$out_file" 2>/dev/null)" "rate limit exceeded"
}
it "output contains the quota error when all backends fail" _test_bg_fallback_quota_when_all_fail

finish
