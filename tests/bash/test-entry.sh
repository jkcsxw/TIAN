#!/usr/bin/env bash
# Tests for the Unix entry wrapper (tian-cli.sh)
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
ENTRY="$TIAN_ROOT/tian-cli.sh"
TEST_DIR=$(make_temp_dir)
trap 'rm -rf "$TEST_DIR"' EXIT

suite "pwsh dispatch"

_test_prefers_pwsh() {
    local bin_dir="$TEST_DIR/pwsh-bin"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/pwsh" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" > "$TEST_DIR/pwsh-args.txt"
exit 0
EOF
    chmod +x "$bin_dir/pwsh"

    PATH="$bin_dir:$PATH" bash "$ENTRY" help
    local args
    args=$(cat "$TEST_DIR/pwsh-args.txt")
    assert_contains "$args" "cli/tian.ps1"
    assert_contains "$args" "help"
}
it "prefers pwsh when available" _test_prefers_pwsh

suite "bash fallback"

_test_falls_back_without_pwsh() {
    local bin_dir="$TEST_DIR/bash-bin"
    mkdir -p "$bin_dir"
    cat > "$bin_dir/bash" <<EOF
#!/usr/bin/bash
printf '%s\n' "\$*" > "$TEST_DIR/bash-args.txt"
exit 0
EOF
    chmod +x "$bin_dir/bash"

    PATH="$bin_dir:/usr/bin:/bin" /usr/bin/bash "$ENTRY" list skills
    local args
    args=$(cat "$TEST_DIR/bash-args.txt")
    assert_contains "$args" "mac/tian-cli-bash.sh"
    assert_contains "$args" "list"
    assert_contains "$args" "skills"
}
it "falls back to the native bash cli when pwsh is unavailable" _test_falls_back_without_pwsh

finish
