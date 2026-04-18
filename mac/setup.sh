#!/usr/bin/env bash
# Mac interactive setup wizard — called by setup.sh
set -euo pipefail
TIAN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CATALOG="$TIAN_DIR/config/catalog.json"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [ok]${RESET} $*"; }
info() { echo -e "${DIM}  [..]${RESET} $*"; }
warn() { echo -e "${YELLOW}  [!!]${RESET} $*"; }
fail() { echo -e "${RED}  [xx]${RESET} $*"; exit 1; }
rule() { echo -e "${DIM}──────────────────────────────────────────────────────────${RESET}"; }
hdr()  { echo ""; echo -e "${CYAN}${BOLD}$*${RESET}"; rule; }

# ── Read catalog via Python 3 (ships with macOS 10.15+) ──────────────────────
py3() { python3 -c "$1" 2>/dev/null; }

catalog_backends() {
    py3 "
import json, sys
c = json.load(open('$CATALOG'))
for b in c['backends']:
    print(b['id']+'|'+b['displayName']+'|'+b.get('cliCommand','')+'|'+b.get('apiKeyEnvVar','')+'|'+b.get('apiKeyHint','')+'|'+b.get('apiKeyUrl','')+'|'+b.get('npmPackage','')+'|'+b.get('nonInteractiveFlag',''))
"
}

catalog_mcpservers() {
    py3 "
import json
c = json.load(open('$CATALOG'))
for s in c['mcpServers']:
    req = ','.join(e['name'] for e in s.get('requiredEnvVars',[]))
    print(s['id']+'|'+s['displayName']+'|'+s['category']+'|'+s.get('configKey',s['id'])+'|'+req)
"
}

catalog_skills() {
    py3 "
import json
c = json.load(open('$CATALOG'))
for s in c['skills']:
    print(s['id']+'|'+s['displayName']+'|'+s['category']+'|'+s.get('promptFile',''))
"
}

# ── Prerequisites ─────────────────────────────────────────────────────────────
hdr "Step 1/5 — Checking prerequisites"

# Xcode Command Line Tools (needed for Homebrew)
if ! xcode-select -p &>/dev/null; then
    info "Installing Xcode Command Line Tools (required for Homebrew)..."
    xcode-select --install 2>/dev/null || true
    echo "  A dialog may have appeared. Please click Install, then re-run setup.sh."
    exit 0
fi
ok "Xcode Command Line Tools"

# Homebrew
if ! command -v brew &>/dev/null; then
    info "Installing Homebrew (the Mac package manager)..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    fi
fi
ok "Homebrew $(brew --version | head -1)"

# Node.js
if ! command -v node &>/dev/null || [[ $(node -e "process.exit(process.version.split('.')[0].slice(1) < 18 ? 1 : 0)" 2>/dev/null; echo $?) -ne 0 ]]; then
    info "Installing Node.js LTS..."
    brew install node@20
    brew link node@20 --force --overwrite 2>/dev/null || true
    export PATH="/opt/homebrew/opt/node@20/bin:/usr/local/opt/node@20/bin:$PATH"
fi
ok "Node.js $(node --version)"

# ── Choose backend ────────────────────────────────────────────────────────────
hdr "Step 2/5 — Choose your AI assistant"

mapfile -t BACKENDS < <(catalog_backends)
i=1
for b in "${BACKENDS[@]}"; do
    name=$(echo "$b" | cut -d'|' -f2)
    printf "  [%d] %s\n" $i "$name"
    ((i++))
done
echo ""
read -rp "  Choose [1]: " BACKEND_CHOICE
BACKEND_CHOICE="${BACKEND_CHOICE:-1}"
BACKEND_IDX=$((BACKEND_CHOICE - 1))
BACKEND_ROW="${BACKENDS[$BACKEND_IDX]}"

B_ID=$(echo "$BACKEND_ROW"     | cut -d'|' -f1)
B_NAME=$(echo "$BACKEND_ROW"   | cut -d'|' -f2)
B_CMD=$(echo "$BACKEND_ROW"    | cut -d'|' -f3)
B_KEYENV=$(echo "$BACKEND_ROW" | cut -d'|' -f4)
B_KEYHINT=$(echo "$BACKEND_ROW"| cut -d'|' -f5)
B_KEYURL=$(echo "$BACKEND_ROW" | cut -d'|' -f6)
B_NPM=$(echo "$BACKEND_ROW"    | cut -d'|' -f7)
B_NIFLAG=$(echo "$BACKEND_ROW" | cut -d'|' -f8)
ok "Selected: $B_NAME"

# ── API key ───────────────────────────────────────────────────────────────────
hdr "Step 3/5 — Connect your account"
echo ""
echo -e "  An API key lets 「天」talk to your AI on your behalf."
echo -e "  Think of it as a password for the AI service."
echo ""
echo -e "  How to get your key (takes ~2 minutes):"
echo -e "  ${DIM}1. Press Enter — your browser will open${RESET}"
echo -e "  ${DIM}2. Sign up or log in at the website${RESET}"
echo -e "  ${DIM}3. Click 'Create Key' and copy the key shown${RESET}"
echo -e "  ${DIM}4. Come back here and paste it${RESET}"
echo ""
read -rp "  Press Enter to open $B_KEYURL in your browser..."
open "$B_KEYURL" 2>/dev/null || true
echo ""
read -rsp "  Paste your $B_KEYENV here (hidden): " API_KEY
echo ""
ok "API key received."

# ── Install backend ───────────────────────────────────────────────────────────
hdr "Step 4/5 — Installing $B_NAME"
if [[ -n "$B_NPM" ]]; then
    info "Running: npm install -g $B_NPM"
    npm install -g "$B_NPM"
    ok "$B_NAME installed."
fi

# Save API key to shell profile
SHELL_PROFILE="$HOME/.zshrc"
[[ "$SHELL" == */bash ]] && SHELL_PROFILE="$HOME/.bash_profile"

# Remove old entry if present, then append
grep -v "export $B_KEYENV=" "$SHELL_PROFILE" > /tmp/tian_profile_tmp 2>/dev/null || true
mv /tmp/tian_profile_tmp "$SHELL_PROFILE" 2>/dev/null || true
echo "export $B_KEYENV=\"$API_KEY\"" >> "$SHELL_PROFILE"
export "$B_KEYENV"="$API_KEY"
ok "$B_KEYENV saved to $SHELL_PROFILE"

# ── MCP tools ─────────────────────────────────────────────────────────────────
hdr "Step 4b/5 — Choose MCP tools"
echo -e "  ${DIM}MCP tools give your AI the ability to read files, search the web, and more.${RESET}"
echo ""

mapfile -t MCP_SERVERS < <(catalog_mcpservers)
i=1
declare -A MCP_NAMES
for s in "${MCP_SERVERS[@]}"; do
    sid=$(echo "$s"  | cut -d'|' -f1)
    sname=$(echo "$s"| cut -d'|' -f2)
    scat=$(echo "$s" | cut -d'|' -f3)
    MCP_NAMES[$i]="$sid"
    printf "  [%2d] %-28s %s\n" $i "$sname" "($scat)"
    ((i++))
done
echo ""
read -rp "  Enter numbers to install (e.g. 1,2) or press Enter to skip: " MCP_CHOICE

SELECTED_MCP=()
if [[ -n "$MCP_CHOICE" ]]; then
    IFS=',' read -ra NUMS <<< "$MCP_CHOICE"
    for n in "${NUMS[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        [[ -n "${MCP_NAMES[$n]:-}" ]] && SELECTED_MCP+=("${MCP_NAMES[$n]}")
    done
fi

# Write MCP config
MCP_CONFIG_DIR="$HOME/Library/Application Support/Claude"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/claude_desktop_config.json"
mkdir -p "$MCP_CONFIG_DIR"

if [[ ! -f "$MCP_CONFIG_FILE" ]]; then
    echo '{"mcpServers":{}}' > "$MCP_CONFIG_FILE"
fi

for sid in "${SELECTED_MCP[@]}"; do
    info "Configuring MCP: $sid"
    python3 - "$MCP_CONFIG_FILE" "$CATALOG" "$sid" <<'PYEOF'
import json, sys
config_path, catalog_path, server_id = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_path) as f:
    config = json.load(f)
with open(catalog_path) as f:
    catalog = json.load(f)
server = next((s for s in catalog['mcpServers'] if s['id'] == server_id), None)
if server:
    config.setdefault('mcpServers', {})[server['configKey']] = server['configSchema']
with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)
PYEOF
    ok "$sid added to MCP config."
done

# ── Skills ────────────────────────────────────────────────────────────────────
hdr "Step 5/5 — Choose skills"
echo -e "  ${DIM}Skills teach your AI how to handle specific tasks your way.${RESET}"
echo ""

mapfile -t SKILLS < <(catalog_skills)
i=1
declare -A SKILL_IDS
declare -A SKILL_FILES
for s in "${SKILLS[@]}"; do
    sid=$(echo "$s"   | cut -d'|' -f1)
    sname=$(echo "$s" | cut -d'|' -f2)
    scat=$(echo "$s"  | cut -d'|' -f3)
    sfile=$(echo "$s" | cut -d'|' -f4)
    SKILL_IDS[$i]="$sid"
    SKILL_FILES[$i]="$sfile"
    printf "  [%2d] %-28s %s\n" $i "$sname" "($scat)"
    ((i++))
done
echo ""
read -rp "  Enter numbers to install (e.g. 1,3) or press Enter to skip: " SKILL_CHOICE

SKILLS_DIR="$HOME/.tian/skills"
mkdir -p "$SKILLS_DIR"

if [[ -n "$SKILL_CHOICE" ]]; then
    IFS=',' read -ra SNUMS <<< "$SKILL_CHOICE"
    for n in "${SNUMS[@]}"; do
        n=$(echo "$n" | tr -d ' ')
        if [[ -n "${SKILL_IDS[$n]:-}" ]]; then
            src="$TIAN_DIR/${SKILL_FILES[$n]}"
            if [[ -f "$src" ]]; then
                cp "$src" "$SKILLS_DIR/${SKILL_IDS[$n]}.md"
                ok "Skill '${SKILL_IDS[$n]}' installed."
            else
                warn "Skill file not found: $src"
            fi
        fi
    done
fi

# ── Write launcher ────────────────────────────────────────────────────────────
LAUNCHER="$TIAN_DIR/launcher.sh"
cat > "$LAUNCHER" <<LAUNCHEOF
#!/usr/bin/env bash
source "\$HOME/.zshrc" 2>/dev/null || source "\$HOME/.bash_profile" 2>/dev/null || true
echo "Starting $B_NAME..."
$B_CMD
LAUNCHEOF
chmod +x "$LAUNCHER"
ok "Launcher created: launcher.sh"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
rule
echo -e "${GREEN}${BOLD}  All done! 天 is ready.${RESET}"
rule
echo ""
echo -e "  Start chatting:  ${CYAN}bash launcher.sh${RESET}"
echo -e "  CLI commands:    ${CYAN}bash tian-cli.sh help${RESET}"
echo ""
echo -e "  ${DIM}Note: open a new Terminal window first so the API key is loaded.${RESET}"
echo ""
