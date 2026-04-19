#!/usr/bin/env bash
# Tests for Python3 catalog JSON parsing (used by mac/tian-cli-bash.sh)
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
CATALOG="$TIAN_ROOT/config/catalog.json"

py3() { python3 -c "$1" 2>/dev/null; }

# ─────────────────────────────────────────────────────────────────────────────

suite "Prerequisites"

_test_python3_available() { command -v python3 &>/dev/null; }
it "python3 is available" _test_python3_available

_test_catalog_exists() { assert_file_exists "$CATALOG"; }
it "catalog.json exists" _test_catalog_exists

suite "Catalog structure"

_test_has_backends() {
    local count
    count=$(py3 "import json; c=json.load(open('$CATALOG')); print(len(c['backends']))")
    [[ "$count" -gt 0 ]]
}
it "catalog has at least one backend" _test_has_backends

_test_has_mcp_servers() {
    local count
    count=$(py3 "import json; c=json.load(open('$CATALOG')); print(len(c['mcpServers']))")
    [[ "$count" -gt 0 ]]
}
it "catalog has at least one MCP server" _test_has_mcp_servers

_test_has_skills() {
    local count
    count=$(py3 "import json; c=json.load(open('$CATALOG')); print(len(c['skills']))")
    [[ "$count" -gt 0 ]]
}
it "catalog has at least one skill" _test_has_skills

suite "Backend fields"

_test_backend_has_id() {
    local ids
    ids=$(py3 "import json; c=json.load(open('$CATALOG')); print('\n'.join(b['id'] for b in c['backends']))")
    assert_not_empty "$ids"
}
it "every backend has an id" _test_backend_has_id

_test_backend_has_displayName() {
    local missing
    missing=$(py3 "
import json
c=json.load(open('$CATALOG'))
bad=[b['id'] for b in c['backends'] if 'displayName' not in b]
print('\n'.join(bad))
")
    assert_empty "$missing"
}
it "every backend has a displayName" _test_backend_has_displayName

_test_cli_backend_has_cliCommand() {
    local missing
    missing=$(py3 "
import json
c=json.load(open('$CATALOG'))
bad=[b['id'] for b in c['backends'] if b.get('installType') in ('cli','local-cli') and not b.get('cliCommand')]
print('\n'.join(bad))
")
    assert_empty "$missing"
}
it "cli-type backends have a cliCommand" _test_cli_backend_has_cliCommand

_test_cli_backend_has_noninteractive_flag() {
    local missing
    missing=$(py3 "
import json
c=json.load(open('$CATALOG'))
bad=[b['id'] for b in c['backends'] if b.get('cliCommand') and not b.get('nonInteractiveFlag')]
print('\n'.join(bad))
")
    assert_empty "$missing"
}
it "CLI backends have a nonInteractiveFlag" _test_cli_backend_has_noninteractive_flag

suite "MCP server fields"

_test_mcp_has_id() {
    local bad
    bad=$(py3 "
import json
c=json.load(open('$CATALOG'))
missing=[s for s in c['mcpServers'] if 'id' not in s]
print(len(missing))
")
    assert_eq "$bad" "0"
}
it "every MCP server has an id" _test_mcp_has_id

_test_mcp_has_configSchema() {
    local bad
    bad=$(py3 "
import json
c=json.load(open('$CATALOG'))
missing=[s for s in c['mcpServers'] if 'configSchema' not in s or 'command' not in s.get('configSchema',{})]
print(len(missing))
")
    assert_eq "$bad" "0"
}
it "every MCP server has a configSchema with command" _test_mcp_has_configSchema

suite "Skills fields"

_test_skills_have_promptFile() {
    local bad
    bad=$(py3 "
import json
c=json.load(open('$CATALOG'))
missing=[s for s in c['skills'] if not s.get('promptFile')]
print(len(missing))
")
    assert_eq "$bad" "0"
}
it "every skill has a promptFile" _test_skills_have_promptFile

_test_skill_files_exist() {
    local missing
    missing=$(py3 "
import json, os
c=json.load(open('$CATALOG'))
root='$TIAN_ROOT'
bad=[s['promptFile'] for s in c['skills'] if not os.path.exists(os.path.join(root,s['promptFile']))]
print('\n'.join(bad))
")
    assert_empty "$missing"
}
it "all skill prompt files exist on disk" _test_skill_files_exist

suite "IDs are unique"

_test_backend_ids_unique() {
    local dupes
    dupes=$(py3 "
import json
c=json.load(open('$CATALOG'))
ids=[b['id'] for b in c['backends']]
dupes=[i for i in ids if ids.count(i)>1]
print('\n'.join(set(dupes)))
")
    assert_empty "$dupes"
}
it "backend IDs are unique" _test_backend_ids_unique

_test_mcp_ids_unique() {
    local dupes
    dupes=$(py3 "
import json
c=json.load(open('$CATALOG'))
ids=[s['id'] for s in c['mcpServers']]
dupes=[i for i in ids if ids.count(i)>1]
print('\n'.join(set(dupes)))
")
    assert_empty "$dupes"
}
it "MCP server IDs are unique" _test_mcp_ids_unique

_test_skill_ids_unique() {
    local dupes
    dupes=$(py3 "
import json
c=json.load(open('$CATALOG'))
ids=[s['id'] for s in c['skills']]
dupes=[i for i in ids if ids.count(i)>1]
print('\n'.join(set(dupes)))
")
    assert_empty "$dupes"
}
it "skill IDs are unique" _test_skill_ids_unique

finish
