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
new_job_id() { date '+%Y%m%d-%H%M%S'-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 6); }

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

finish
