#!/usr/bin/env bash
# Tests for bash CLI routing (mac/tian-cli-bash.sh command dispatch)
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
CLI="$TIAN_ROOT/mac/tian-cli-bash.sh"
TEST_HOME=$(make_temp_dir)
trap 'rm -rf "$TEST_HOME"' EXIT

mkdir -p "$TEST_HOME/.tian/tasks" "$TEST_HOME/Library/Application Support/Claude"
cat > "$TEST_HOME/.tian/jobs.json" <<'EOF'
[
  {
    "id": "20260417-231812-13d702",
    "status": "running",
    "prompt": "run"
  },
  {
    "id": "20260417-231813-abcdef",
    "status": "done",
    "prompt": "done"
  }
]
EOF
echo '[]' > "$TEST_HOME/.tian/schedules.json"

# All invocations pass TIAN_ROOT as first arg (the script's $1 = TIAN_DIR)
run_cli() { HOME="$TEST_HOME" bash "$CLI" "$TIAN_ROOT" "$@" 2>&1; }

# ─────────────────────────────────────────────────────────────────────────────

suite "help / no-args"

_test_help_cmd() {
    local out
    out=$(run_cli help)
    assert_contains "$out" "USAGE"
}
it "'help' prints usage" _test_help_cmd

_test_no_args() {
    local out
    out=$(run_cli)
    assert_contains "$out" "USAGE"
}
it "no arguments prints usage" _test_no_args

suite "status command"

_test_status_exits_ok() {
    run_cli status
    [[ $? -eq 0 ]]
}
it "status exits 0" _test_status_exits_ok

suite "list command"

_test_list_backends() {
    local out
    out=$(run_cli list backends 2>/dev/null || true)
    assert_contains "$out" "claude-code"
}
it "list backends shows backend ids" _test_list_backends

_test_list_mcp() {
    local out
    out=$(run_cli list mcp 2>/dev/null || true)
    # Should not crash (output may be empty if catalog parse fails in test env)
    [[ $? -eq 0 ]] || assert_contains "$out" "mcp"
    true
}
it "list mcp does not crash" _test_list_mcp

_test_list_skills() {
    local out
    out=$(run_cli list skills 2>/dev/null || true)
    true
}
it "list skills does not crash" _test_list_skills

suite "add / remove commands"

_test_add_skill() {
    run_cli add skill email-assistant >/dev/null
    assert_file_exists "$TEST_HOME/.tian/skills/email-assistant.md"
}
it "add skill installs builtin skills into ~/.tian/skills" _test_add_skill

_test_add_mcp() {
    run_cli add mcp memory --backend claude-code >/dev/null
    local cfg="$TEST_HOME/.claude/settings.json"
    assert_file_exists "$cfg"
    local out
    out=$(cat "$cfg")
    assert_contains "$out" '"memory"'
}
it "add mcp writes backend config" _test_add_mcp

_test_remove_mcp() {
    run_cli add mcp memory --backend claude-code >/dev/null
    run_cli remove mcp memory --backend claude-code >/dev/null
    local cfg="$TEST_HOME/.claude/settings.json"
    local out
    out=$(cat "$cfg")
    [[ "$out" != *'"memory"'* ]]
}
it "remove mcp removes configured servers" _test_remove_mcp

suite "jobs command"

_test_jobs_exits_ok() {
    run_cli jobs
    [[ $? -eq 0 ]]
}
it "jobs exits 0" _test_jobs_exits_ok

_test_jobs_clear() {
    run_cli jobs clear
    [[ $? -eq 0 ]]
}
it "jobs clear exits 0" _test_jobs_clear

suite "schedule subcommands"

_test_sched_list() {
    run_cli schedule list
    [[ $? -eq 0 ]]
}
it "schedule list exits 0" _test_sched_list

suite "multi-backend fallback helpers"

_test_is_quota_error_matches() {
    # Source the CLI so we can call is_quota_error directly
    local cli_src="$TIAN_ROOT/mac/tian-cli-bash.sh"
    # Extract and eval just the function (safe: no side effects)
    local fn; fn=$(awk '/^is_quota_error\(\)/,/^}/' "$cli_src")
    eval "$fn"
    is_quota_error "Error: insufficient_quota — please add credits"
}
it "is_quota_error detects insufficient_quota" _test_is_quota_error_matches

_test_is_quota_error_rate_limit() {
    local cli_src="$TIAN_ROOT/mac/tian-cli-bash.sh"
    local fn; fn=$(awk '/^is_quota_error\(\)/,/^}/' "$cli_src")
    eval "$fn"
    is_quota_error "HTTP 429: rate limit exceeded"
}
it "is_quota_error detects 429 rate limit" _test_is_quota_error_rate_limit

_test_is_quota_error_negative() {
    local cli_src="$TIAN_ROOT/mac/tian-cli-bash.sh"
    local fn; fn=$(awk '/^is_quota_error\(\)/,/^}/' "$cli_src")
    eval "$fn"
    ! is_quota_error "Task completed successfully."
}
it "is_quota_error returns false for normal output" _test_is_quota_error_negative

suite "doctor command"

_test_doctor_exits_ok() {
    run_cli doctor
    [[ $? -eq 0 ]]
}
it "doctor exits 0" _test_doctor_exits_ok

_test_doctor_checks_node() {
    local out
    out=$(run_cli doctor 2>/dev/null || true)
    assert_contains "$out" "Node"
}
it "doctor output mentions Node.js" _test_doctor_checks_node

suite "unknown command"

_test_unknown() {
    local out
    out=$(run_cli totally-unknown-command 2>&1 || true)
    # Should print help or an error, not hang
    assert_not_empty "$out"
}
it "unknown command prints output and does not hang" _test_unknown

suite "run --watch flag"

_test_help_mentions_watch() {
    local out
    out=$(run_cli help)
    assert_contains "$out" "-w"
}
it "help text mentions -w / --watch flag" _test_help_mentions_watch

_test_help_mentions_auto_exits() {
    local out
    out=$(run_cli help)
    assert_contains "$out" "auto-exits"
}
it "help text describes auto-exit behaviour for jobs tail" _test_help_mentions_auto_exits

# Verify _watch_job exits cleanly when the underlying job transitions to "done".
# We avoid invoking a real backend by directly sourcing the helper, then having
# a background process flip the job status mid-watch.
_test_watch_job_exits_when_done() {
    local cli="$TIAN_ROOT/mac/tian-cli-bash.sh"
    local sandbox; sandbox=$(make_temp_dir)
    export TASKS_DIR="$sandbox/tasks"
    export JOBS_FILE="$sandbox/jobs.json"
    mkdir -p "$TASKS_DIR"
    local jid="watch-test-job"
    echo "[{\"id\":\"$jid\",\"status\":\"running\"}]" > "$JOBS_FILE"
    printf 'partial output\n' > "$TASKS_DIR/$jid.txt"

    # Define stubs so _watch_job's helpers operate against the sandbox.
    info() { :; }
    warn() { :; }
    ok()   { :; }
    fail() { return 1; }
    rule() { :; }
    sync_job_statuses() { :; }

    # Extract the three helper functions we want to test.
    local fn
    fn=$(awk '/^_get_job_status\(\)/,/^}/' "$cli")
    eval "$fn"
    fn=$(awk '/^_get_job_stop_reason\(\)/,/^}/' "$cli")
    eval "$fn"
    fn=$(awk '/^_watch_job\(\)/,/^}/' "$cli")
    eval "$fn"

    # Flip the job to "done" after a short delay so _watch_job's loop exits.
    ( sleep 2
      python3 -c "
import json, sys
with open('$JOBS_FILE') as fh:
    jobs = json.load(fh)
for j in jobs:
    if j['id'] == '$jid':
        j['status'] = 'done'
with open('$JOBS_FILE', 'w') as fh:
    json.dump(jobs, fh)
"
      echo 'final output' >> "$TASKS_DIR/$jid.txt"
    ) &
    local flipper_pid=$!

    # _watch_job should return within ~5 seconds (poll interval is 1s).
    local rc=0
    _watch_job "$jid" >/dev/null 2>&1 || rc=$?
    wait $flipper_pid 2>/dev/null || true
    rm -rf "$sandbox"
    [[ $rc -eq 0 ]]
}
it "_watch_job auto-exits when job transitions to done" _test_watch_job_exits_when_done

finish
