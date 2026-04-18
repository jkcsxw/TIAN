#!/usr/bin/env bash
# TIAN — Talk Is All you Need
# Mac setup entry point — double-click in Finder or run: bash setup.sh

set -euo pipefail
TIAN_DIR="$(cd "$(dirname "$0")" && pwd)"

# Must be macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is for macOS. On Windows please run setup.bat instead."
    exit 1
fi

echo ""
echo "  ████████╗██╗ █████╗ ███╗   ██╗"
echo "     ██╔══╝██║██╔══██╗████╗  ██║"
echo "     ██║   ██║███████║██╔██╗ ██║"
echo "     ██║   ██║██╔══██║██║╚██╗██║"
echo "     ██║   ██║██║  ██║██║ ╚████║"
echo "     ╚═╝   ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝"
echo ""
echo "  Talk Is All you Need — macOS Setup"
echo ""

bash "$TIAN_DIR/mac/setup.sh" "$TIAN_DIR"
