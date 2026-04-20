#!/usr/bin/env bash
# Pipeable bootstrap installer for macOS and Linux.
set -euo pipefail

OWNER="jkcsxw"
REPO="TIAN"
REF="${TIAN_REF:-main}"
ARCHIVE_URL="https://github.com/$OWNER/$REPO/archive/refs/heads/$REF.tar.gz"
INSTALL_DIR="${TIAN_INSTALL_DIR:-$HOME/.tian/repo}"
BIN_DIR="${TIAN_BIN_DIR:-$HOME/.local/bin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  [ok]${RESET} $*"; }
info() { echo -e "${DIM}  [..]${RESET} $*"; }
warn() { echo -e "${YELLOW}  [!!]${RESET} $*"; }
fail() { echo -e "${RED}  [xx]${RESET} $*"; exit 1; }

detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) echo "linux" ;;
        *) fail "This installer currently supports macOS and Linux only." ;;
    esac
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

profile_file() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        zsh) echo "$HOME/.zshrc" ;;
        bash) [[ "$(detect_platform)" == "macos" ]] && echo "$HOME/.bash_profile" || echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *) echo "$HOME/.profile" ;;
    esac
}

ensure_path_line() {
    local profile
    profile="$(profile_file)"
    mkdir -p "$(dirname "$profile")" "$BIN_DIR"
    touch "$profile"

    if [[ "$profile" == *"/config.fish" ]]; then
        grep -Fq 'set -gx PATH "$HOME/.local/bin" $PATH' "$profile" || \
            printf '\nset -gx PATH "$HOME/.local/bin" $PATH\n' >> "$profile"
    else
        grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$profile" || \
            printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profile"
    fi
}

install_wrapper() {
    mkdir -p "$BIN_DIR"
    cat > "$BIN_DIR/tian-cli" <<EOF
#!/usr/bin/env bash
exec bash "$INSTALL_DIR/tian-cli.sh" "\$@"
EOF
    chmod +x "$BIN_DIR/tian-cli"
}

download_repo() {
    local tmp_dir archive extracted_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    archive="$tmp_dir/tian.tar.gz"

    info "Downloading TIAN..."
    curl -fsSL "$ARCHIVE_URL" -o "$archive"

    mkdir -p "$tmp_dir/extracted"
    tar -xzf "$archive" -C "$tmp_dir/extracted"
    extracted_dir="$(find "$tmp_dir/extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$extracted_dir" ]] || fail "Failed to unpack TIAN archive."

    mkdir -p "$(dirname "$INSTALL_DIR")"
    rm -rf "$INSTALL_DIR"
    mv "$extracted_dir" "$INSTALL_DIR"

    chmod +x "$INSTALL_DIR/setup.sh" "$INSTALL_DIR/tian-cli.sh" "$INSTALL_DIR/mac/setup.sh" "$INSTALL_DIR/mac/tian-cli-bash.sh"
    ok "Installed files to $INSTALL_DIR"
}

run_platform_flow() {
    local platform
    platform="$(detect_platform)"

    case "$platform" in
        macos)
            info "Starting macOS setup..."
            bash "$INSTALL_DIR/setup.sh"
            ;;
        linux)
            ok "Linux CLI installed."
            echo ""
            echo -e "${BOLD}Next steps${RESET}"
            echo "  1. Open a new terminal, or run: export PATH=\"$HOME/.local/bin:\$PATH\""
            echo "  2. Run: tian-cli help"
            echo "  3. Optional: if you have PowerShell Core, run: tian-cli setup"
            echo ""
            bash "$INSTALL_DIR/tian-cli.sh" help
            ;;
    esac
}

main() {
    require_cmd curl
    require_cmd tar
    require_cmd find
    require_cmd bash

    echo ""
    echo -e "${CYAN}${BOLD}TIAN one-line install${RESET}"
    echo ""

    download_repo
    install_wrapper
    ensure_path_line
    ok "Installed CLI wrapper to $BIN_DIR/tian-cli"

    run_platform_flow
}

main "$@"
