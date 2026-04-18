#!/usr/bin/env bash
# Shared test helpers for TIAN bash tests

PASS=0
FAIL=0
SKIP=0
_CURRENT_SUITE=""

suite() { _CURRENT_SUITE="$1"; echo ""; echo "=== $1 ==="; }

it() {
    local desc="$1"
    shift
    if "$@" 2>/dev/null; then
        echo "  [PASS] $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc"
        ((FAIL++))
    fi
}

skip_it() {
    local desc="$1"
    echo "  [SKIP] $desc"
    ((SKIP++))
}

assert_eq() {
    local actual="$1" expected="$2"
    [[ "$actual" == "$expected" ]]
}

assert_match() {
    local actual="$1" pattern="$2"
    [[ "$actual" =~ $pattern ]]
}

assert_file_exists() { [[ -f "$1" ]]; }
assert_dir_exists()  { [[ -d "$1" ]]; }
assert_not_empty()   { [[ -n "$1" ]]; }
assert_empty()       { [[ -z "$1" ]]; }
assert_contains()    { [[ "$1" == *"$2"* ]]; }

finish() {
    echo ""
    echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
    [[ $FAIL -eq 0 ]]
}

# Create a temp directory cleaned up on EXIT
make_temp_dir() {
    local d
    d=$(mktemp -d)
    echo "$d"
}

# Get the repo root (two levels up from tests/bash/)
get_tian_root() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}
