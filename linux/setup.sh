#!/usr/bin/env bash
# TIAN interactive setup wizard — Linux / WSL
set -euo pipefail
TIAN_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
CATALOG="$TIAN_DIR/config/catalog.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [ok]${RESET} $*"; }
info() { echo -e "${DIM}  [..]${RESET} $*"; }
warn() { echo -e "${YELLOW}  [!!]${RESET} $*"; }
fail() { echo -e "${RED}  [xx]${RESET} $*"; exit 1; }
rule() { echo -e "${DIM}──────────────────────────────────────────────────────────${RESET}"; }
hdr()  { echo ""; echo -e "${CYAN}${BOLD}$*${RESET}"; rule; }

detect_platform() {
    grep -qi microsoft /proc/version 2>/dev/null && echo "wsl" || echo "linux"
}

profile_file() {
    if [[ -f "$HOME/.zshrc" ]]; then
        echo "$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
        echo "$HOME/.bashrc"
    else
        echo "$HOME/.bashrc"
    fi
}

save_env_var() {
    local name="${1:-}" value="${2:-}"
    local profile; profile=$(profile_file)
    touch "$profile"
    python3 - "$profile" "$name" "$value" <<'PYEOF'
import os, re, sys
profile, name, value = sys.argv[1], sys.argv[2], sys.argv[3]
pattern = re.compile(rf'^\s*export\s+{re.escape(name)}=')
lines = []
if os.path.exists(profile):
    with open(profile, encoding='utf-8', errors='ignore') as fh:
        lines = fh.readlines()
kept = [line for line in lines if not pattern.search(line)]
kept.append(f'export {name}="{value}"\n')
with open(profile, 'w', encoding='utf-8') as fh:
    fh.writelines(kept)
PYEOF
    export "$name"="$value"
}

open_url() {
    local url="${1:-}"
    local platform; platform=$(detect_platform)
    if [[ "$platform" == "wsl" ]]; then
        explorer.exe "$url" 2>/dev/null || \
        cmd.exe /c start "$url" 2>/dev/null || \
        wslview "$url" 2>/dev/null || true
    else
        xdg-open "$url" 2>/dev/null || \
        sensible-browser "$url" 2>/dev/null || true
    fi
}

# Returns the Claude Desktop MCP config path.
# On WSL this is inside the Windows AppData directory.
claude_desktop_cfg() {
    local platform; platform=$(detect_platform)
    if [[ "$platform" == "wsl" ]] && command -v cmd.exe &>/dev/null; then
        local raw wsl_appdata
        raw=$(cmd.exe /c "echo %APPDATA%" 2>/dev/null | tr -d '\r\n' || true)
        if [[ -n "$raw" && "$raw" != "%APPDATA%" ]]; then
            wsl_appdata=$(wslpath "$raw" 2>/dev/null || true)
            if [[ -n "$wsl_appdata" ]]; then
                echo "$wsl_appdata/Claude/claude_desktop_config.json"
                return
            fi
        fi
    fi
    echo "$HOME/.config/Claude/claude_desktop_config.json"
}

catalog_backends() {
    python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for b in c['backends']:
    print('|'.join([
        b['id'],
        b['displayName'],
        b.get('cliCommand', ''),
        b.get('apiKeyEnvVar', ''),
        b.get('apiKeyHint', ''),
        b.get('apiKeyUrl', ''),
        b.get('npmPackage', ''),
        b.get('nonInteractiveFlag', ''),
    ]))
PYEOF
}

catalog_mcpservers() {
    python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for s in c['mcpServers']:
    req = ','.join(e['name'] for e in s.get('requiredEnvVars', []))
    print('|'.join([s['id'], s['displayName'], s['category'], s.get('configKey', s['id']), req]))
PYEOF
}

catalog_skills() {
    python3 - "$CATALOG" <<'PYEOF'
import json, sys
c = json.load(open(sys.argv[1]))
for s in c['skills']:
    print('|'.join([s['id'], s['displayName'], s['category'], s.get('promptFile', '')]))
PYEOF
}

# ── Banner ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}  ████████╗██╗ █████╗ ███╗   ██╗${RESET}"
echo -e "${CYAN}${BOLD}     ██╔══╝██║██╔══██╗████╗  ██║${RESET}"
echo -e "${CYAN}${BOLD}     ██║   ██║███████║██╔██╗ ██║${RESET}"
echo -e "${CYAN}${BOLD}     ██║   ██║██╔══██║██║╚██╗██║${RESET}"
echo -e "${CYAN}${BOLD}     ██║   ██║██║  ██║██║ ╚████║${RESET}"
echo -e "${CYAN}${BOLD}     ╚═╝   ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝${RESET}"
echo ""
PLATFORM=$(detect_platform)
if [[ "$PLATFORM" == "wsl" ]]; then
    echo -e "  Talk Is All you Need — Linux/WSL Setup"
else
    echo -e "  Talk Is All you Need — Linux Setup"
fi
echo ""

# ── Step 1: Prerequisites ──────────────────────────────────────────────────────
hdr "Step 1/5 — Checking prerequisites"

# Python 3
if command -v python3 &>/dev/null; then
    ok "Python3 $(python3 --version 2>&1 | awk '{print $2}')"
else
    fail "Python3 not found. Install it: sudo apt-get install python3"
fi

# Node.js
if command -v node &>/dev/null; then
    NODE_VER=$(node --version)
    NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v\([0-9]*\).*/\1/')
    if [[ "$NODE_MAJOR" -ge 18 ]]; then
        ok "Node.js $NODE_VER"
    else
        warn "Node.js $NODE_VER is too old — v18+ required. Attempting upgrade via nvm..."
        NODE_NEEDS_INSTALL=true
    fi
else
    warn "Node.js not found — installing via nvm (Node Version Manager)..."
    NODE_NEEDS_INSTALL=true
fi

if [[ "${NODE_NEEDS_INSTALL:-false}" == "true" ]]; then
    if command -v nvm &>/dev/null || [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        # nvm is already installed, just use it
        # shellcheck source=/dev/null
        [[ -s "$HOME/.nvm/nvm.sh" ]] && source "$HOME/.nvm/nvm.sh"
        info "Running: nvm install --lts"
        nvm install --lts
        nvm use --lts
        ok "Node.js $(node --version) installed via nvm"
    else
        info "Installing nvm (Node Version Manager)..."
        NVM_INSTALL_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh"
        curl -fsSL "$NVM_INSTALL_URL" | bash
        # Load nvm into this session
        export NVM_DIR="$HOME/.nvm"
        # shellcheck source=/dev/null
        [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
        info "Running: nvm install --lts"
        nvm install --lts
        nvm use --lts
        ok "Node.js $(node --version) installed via nvm"
        info "  nvm is sourced automatically in new shells via your profile."
    fi
fi

if ! command -v node &>/dev/null; then
    fail "Node.js installation failed. Install manually: https://nodejs.org/en/download"
fi
if ! command -v npm &>/dev/null; then
    fail "npm not found after Node install. Check your PATH."
fi
ok "npm $(npm --version)"

# ── Step 2: Choose backend ─────────────────────────────────────────────────────
hdr "Step 2/5 — Choose your AI assistant"

mapfile -t BACKENDS < <(catalog_backends)
i=1
for b in "${BACKENDS[@]}"; do
    name=$(echo "$b" | cut -d'|' -f2)
    printf "  [%d] %s\n" $i "$name"
    ((i++))
done
echo ""
read -rp "  Choose [1]: " BACKEND_CHOICE </dev/tty
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
ok "Selected: $B_NAME"

# ── Step 3: API key ────────────────────────────────────────────────────────────
hdr "Step 3/5 — Connect your account"

if [[ -n "$B_KEYENV" ]]; then
    echo ""
    echo -e "  An API key lets 天 talk to your AI on your behalf."
    echo -e "  Think of it as a password for the AI service."
    echo ""
    if [[ -n "$B_KEYURL" ]]; then
        echo -e "  How to get your key (takes ~2 minutes):"
        echo -e "  ${DIM}1. Press Enter — your browser will open (or visit the URL shown)${RESET}"
        echo -e "  ${DIM}2. Sign up or log in at the website${RESET}"
        echo -e "  ${DIM}3. Click 'Create Key' and copy the key shown${RESET}"
        echo -e "  ${DIM}4. Come back here and paste it${RESET}"
        echo ""
        echo -e "  URL: ${CYAN}$B_KEYURL${RESET}"
        read -rp "  Press Enter to try opening in browser (or visit the URL above)..." </dev/tty
        open_url "$B_KEYURL"
        echo ""
    fi
    read -rsp "  Paste your $B_KEYENV here (hidden): " API_KEY </dev/tty
    echo ""
    if [[ -n "$API_KEY" ]]; then
        save_env_var "$B_KEYENV" "$API_KEY"
        ok "$B_KEYENV saved to $(profile_file)"
    else
        warn "No key entered — you can set it later with: export $B_KEYENV=<your-key>"
    fi
else
    info "No API key required for $B_NAME."
fi

# ── Step 4: Install backend ────────────────────────────────────────────────────
hdr "Step 4/5 — Installing $B_NAME"

if [[ -n "$B_NPM" ]]; then
    if [[ -n "$B_CMD" ]] && command -v "$B_CMD" &>/dev/null; then
        ok "$B_NAME already installed ($(command -v "$B_CMD"))"
    else
        info "Running: npm install -g $B_NPM"
        npm install -g "$B_NPM"
        ok "$B_NAME installed."
    fi
elif [[ "$B_ID" == *"ollama"* ]]; then
    if command -v ollama &>/dev/null; then
        ok "Ollama already installed ($(ollama --version 2>/dev/null | head -1 || echo 'version unknown'))"
    else
        info "Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        ok "Ollama installed."
        info "Downloading qwen2.5-coder model (this may take a few minutes)..."
        ollama pull qwen2.5-coder 2>/dev/null || warn "Model pull failed — run: ollama pull qwen2.5-coder"
    fi
else
    info "$B_NAME is a desktop application — please install it manually from $B_KEYURL"
fi

# ── Step 4b: MCP tools ─────────────────────────────────────────────────────────
if [[ -n "$B_CMD" ]] || [[ "$B_ID" == *"desktop"* ]]; then
    hdr "Step 4b/5 — Choose MCP tools"
    echo -e "  ${DIM}MCP tools give your AI the ability to read files, search the web, and more.${RESET}"
    if [[ "$PLATFORM" == "wsl" && "$B_ID" == *"desktop"* ]]; then
        echo -e "  ${DIM}On WSL, Claude Desktop is a Windows app — MCP config will be written to the Windows AppData path.${RESET}"
    fi
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
    read -rp "  Enter numbers to install (e.g. 1,2) or press Enter to skip: " MCP_CHOICE </dev/tty

    SELECTED_MCP=()
    if [[ -n "$MCP_CHOICE" ]]; then
        IFS=',' read -ra NUMS <<< "$MCP_CHOICE"
        for n in "${NUMS[@]}"; do
            n=$(echo "$n" | tr -d ' ')
            [[ -n "${MCP_NAMES[$n]:-}" ]] && SELECTED_MCP+=("${MCP_NAMES[$n]}")
        done
    fi

    if [[ ${#SELECTED_MCP[@]} -gt 0 ]]; then
        MCP_CONFIG_FILE=$(claude_desktop_cfg)
        MCP_CONFIG_DIR=$(dirname "$MCP_CONFIG_FILE")
        mkdir -p "$MCP_CONFIG_DIR"
        [[ -f "$MCP_CONFIG_FILE" ]] || echo '{"mcpServers":{}}' > "$MCP_CONFIG_FILE"

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

            # Prompt for any required env vars
            while IFS='|' read -r env_name env_label env_hint env_url; do
                [[ -n "$env_name" ]] || continue
                if [[ -z "${!env_name:-}" ]]; then
                    echo ""
                    info "$env_label is required for $sid"
                    [[ -n "$env_hint" ]] && info "  $env_hint"
                    [[ -n "$env_url" ]]  && info "  Get it at: $env_url"
                    read -rsp "  Paste $env_name (hidden): " env_val </dev/tty
                    echo ""
                    if [[ -n "$env_val" ]]; then
                        save_env_var "$env_name" "$env_val"
                        ok "$env_name saved."
                    else
                        warn "$env_name not set — add it later: export $env_name=..."
                    fi
                fi
            done < <(python3 - "$CATALOG" "$sid" <<'PYEOF'
import json, sys
catalog = json.load(open(sys.argv[1]))
server_id = sys.argv[2]
server = next((s for s in catalog['mcpServers'] if s['id'] == server_id), None)
if server:
    for ev in server.get('requiredEnvVars', []):
        print('|'.join([
            ev.get('name', ''),
            ev.get('label', ev.get('name', '')),
            ev.get('hint', ''),
            ev.get('url', ''),
        ]))
PYEOF
)
        done
    fi
fi

# ── Step 5: Skills ─────────────────────────────────────────────────────────────
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
read -rp "  Enter numbers to install (e.g. 1,3) or press Enter to skip: " SKILL_CHOICE </dev/tty

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

# ── Write launcher ─────────────────────────────────────────────────────────────
if [[ -n "$B_CMD" ]]; then
    LAUNCHER="$TIAN_DIR/launcher.sh"
    PROFILE_FILE=$(profile_file)
    cat > "$LAUNCHER" <<LAUNCHEOF
#!/usr/bin/env bash
source "$PROFILE_FILE" 2>/dev/null || true
echo "Starting $B_NAME..."
$B_CMD
LAUNCHEOF
    chmod +x "$LAUNCHER"
    ok "Launcher created: launcher.sh"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
rule
echo -e "${GREEN}${BOLD}  All done! 天 is ready.${RESET}"
rule
echo ""
if [[ -n "$B_CMD" ]]; then
    echo -e "  Start chatting:  ${CYAN}bash launcher.sh${RESET}"
fi
echo -e "  CLI commands:    ${CYAN}tian-cli help${RESET}"
echo ""
echo -e "  ${DIM}Note: open a new terminal (or run 'source $(profile_file)') so API keys are loaded.${RESET}"
echo ""
