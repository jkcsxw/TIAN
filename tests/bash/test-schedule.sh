#!/usr/bin/env bash
# Tests for bash scheduler functions (launchd plist generation, schedule CRUD)
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
TMPDIR_TEST=$(make_temp_dir)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

SCHEDULES_FILE="$TMPDIR_TEST/schedules.json"
LAUNCH_AGENTS_DIR="$TMPDIR_TEST/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS_DIR"
echo '[]' > "$SCHEDULES_FILE"

# ── Minimal inline implementations of functions under test ───────────────────

read_schedules() {
    python3 -c "
import json
try:
    data = json.load(open('$SCHEDULES_FILE'))
    if not isinstance(data, list): data = [data]
    print(json.dumps(data))
except:
    print('[]')
"
}

save_schedules() {
    echo "$1" > "$SCHEDULES_FILE"
}

make_task_name() {
    # mirrors mac/tian-cli-bash.sh naming: TIAN_ prefix, non-alphanumeric → _
    echo "TIAN_$(echo "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9_-]/_/g')"
}

plist_content() {
    local label="$1" hour="$2" min="$3" cmd="$4"
    cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>     <string>${label}</string>
    <key>ProgramArguments</key>
    <array><string>${cmd}</string></array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>   <integer>${hour}</integer>
        <key>Minute</key> <integer>${min}</integer>
    </dict>
    <key>RunAtLoad</key> <false/>
</dict>
</plist>
EOF
}

add_schedule_test() {
    local name="$1" time="$2"
    local label
    label=$(make_task_name "$name")
    local hour min
    hour=$(echo "$time" | cut -d: -f1)
    min=$(echo  "$time" | cut -d: -f2)
    local plist="$LAUNCH_AGENTS_DIR/${label}.plist"
    plist_content "$label" "$hour" "$min" "/usr/bin/true" > "$plist"
    local existing
    existing=$(read_schedules)
    local new_entry="{\"name\":\"$name\",\"label\":\"$label\",\"time\":\"$time\"}"
    local updated
    updated=$(python3 -c "
import json,sys
data=json.loads('$existing')
data.append(json.loads('$new_entry'))
print(json.dumps(data))
")
    save_schedules "$updated"
}

remove_schedule_test() {
    local name="$1"
    local label
    label=$(make_task_name "$name")
    rm -f "$LAUNCH_AGENTS_DIR/${label}.plist"
    local existing
    existing=$(read_schedules)
    local updated
    updated=$(python3 -c "
import json
data=json.loads('$existing')
data=[e for e in data if e.get('name')!='$name']
print(json.dumps(data))
")
    save_schedules "$updated"
}

# ─────────────────────────────────────────────────────────────────────────────

suite "make_task_name"

_test_prefix() { assert_eq "$(make_task_name "foo")" "TIAN_foo"; }
it "adds TIAN_ prefix" _test_prefix

_test_spaces() { assert_match "$(make_task_name "my task")" "TIAN_my_task"; }
it "replaces spaces with underscores" _test_spaces

_test_special() { assert_match "$(make_task_name "a!b")" "TIAN_a_b"; }
it "replaces special chars with underscores" _test_special

_test_preserve() { assert_eq "$(make_task_name "daily-report_v2")" "TIAN_daily-report_v2"; }
it "preserves alphanumeric, hyphen, underscore" _test_preserve

suite "plist_content"

_test_plist_label() {
    local out
    out=$(plist_content "TIAN_test" "8" "30" "/usr/bin/true")
    assert_contains "$out" "TIAN_test"
}
it "plist contains the label" _test_plist_label

_test_plist_hour() {
    local out
    out=$(plist_content "TIAN_test" "8" "30" "/usr/bin/true")
    assert_contains "$out" "<integer>8</integer>"
}
it "plist contains the hour integer" _test_plist_hour

_test_plist_minute() {
    local out
    out=$(plist_content "TIAN_test" "8" "30" "/usr/bin/true")
    assert_contains "$out" "<integer>30</integer>"
}
it "plist contains the minute integer" _test_plist_minute

suite "add_schedule / remove_schedule"

_test_add_persists() {
    echo '[]' > "$SCHEDULES_FILE"
    add_schedule_test "morning" "08:00"
    local result
    result=$(read_schedules)
    assert_contains "$result" '"morning"'
}
it "add_schedule persists entry to schedules file" _test_add_persists

_test_add_creates_plist() {
    echo '[]' > "$SCHEDULES_FILE"
    add_schedule_test "briefing" "09:00"
    assert_file_exists "$LAUNCH_AGENTS_DIR/TIAN_briefing.plist"
}
it "add_schedule creates plist file" _test_add_creates_plist

_test_add_multiple() {
    echo '[]' > "$SCHEDULES_FILE"
    add_schedule_test "s1" "07:00"
    add_schedule_test "s2" "08:00"
    local result
    result=$(read_schedules)
    assert_contains "$result" '"s1"'
    assert_contains "$result" '"s2"'
}
it "adding multiple schedules keeps all entries" _test_add_multiple

_test_remove() {
    echo '[]' > "$SCHEDULES_FILE"
    add_schedule_test "keep"   "08:00"
    add_schedule_test "remove" "09:00"
    remove_schedule_test "remove"
    local result
    result=$(read_schedules)
    assert_contains "$result" '"keep"'
    [[ "$result" != *'"remove"'* ]]
}
it "remove_schedule removes only matching entry" _test_remove

_test_remove_plist() {
    echo '[]' > "$SCHEDULES_FILE"
    add_schedule_test "gone" "10:00"
    remove_schedule_test "gone"
    [[ ! -f "$LAUNCH_AGENTS_DIR/TIAN_gone.plist" ]]
}
it "remove_schedule deletes the plist file" _test_remove_plist

suite "read_schedules / save_schedules round-trip"

_test_rt_empty() {
    echo '[]' > "$SCHEDULES_FILE"
    local r
    r=$(read_schedules)
    assert_eq "$r" "[]"
}
it "returns empty array for empty file" _test_rt_empty

_test_rt_multi() {
    local data='[{"name":"a","time":"08:00"},{"name":"b","time":"09:00"}]'
    save_schedules "$data"
    local r
    r=$(read_schedules)
    assert_contains "$r" '"a"'
    assert_contains "$r" '"b"'
}
it "round-trips multi-entry array" _test_rt_multi

finish
