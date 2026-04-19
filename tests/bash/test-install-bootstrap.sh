#!/usr/bin/env bash
# Tests for the one-line bootstrap installer.
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
INSTALL_SH="$TIAN_ROOT/install.sh"
README_MD="$TIAN_ROOT/README.md"
DOCS_HTML="$TIAN_ROOT/docs/index.html"
ONE_LINE_CMD='curl -fsSL https://raw.githubusercontent.com/jkcsxw/TIAN/main/install.sh | bash'

suite "Bootstrap installer"

_test_install_script_exists() { assert_file_exists "$INSTALL_SH"; }
it "install.sh exists" _test_install_script_exists

_test_install_script_parses() { bash -n "$INSTALL_SH"; }
it "install.sh passes bash -n" _test_install_script_parses

_test_install_script_uses_raw_entrypoint() {
    local content
    content=$(cat "$INSTALL_SH")
    assert_contains "$content" 'exec bash "$INSTALL_DIR/tian-cli.sh"'
}
it "install.sh installs a tian-cli wrapper" _test_install_script_uses_raw_entrypoint

suite "Docs"

_test_readme_mentions_one_line_install() {
    local content
    content=$(cat "$README_MD")
    assert_contains "$content" "$ONE_LINE_CMD"
}
it "README uses the one-line install command" _test_readme_mentions_one_line_install

_test_docs_page_mentions_one_line_install() {
    local content
    content=$(cat "$DOCS_HTML")
    assert_contains "$content" "$ONE_LINE_CMD"
}
it "docs page uses the one-line install command" _test_docs_page_mentions_one_line_install

finish
