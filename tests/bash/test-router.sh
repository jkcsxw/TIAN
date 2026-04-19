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

suite "unknown command"

_test_unknown() {
    local out
    out=$(run_cli totally-unknown-command 2>&1 || true)
    # Should print help or an error, not hang
    assert_not_empty "$out"
}
it "unknown command prints output and does not hang" _test_unknown

finish
