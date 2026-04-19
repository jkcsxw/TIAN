#!/usr/bin/env bash
# TIAN CLI — macOS/Linux entry point
# Usage: bash tian-cli.sh <command> [options]

TIAN_DIR="$(cd "$(dirname "$0")" && pwd)"
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

if [[ "$OS_NAME" != "Darwin" && "$OS_NAME" != "Linux" ]]; then
    echo "This script is for macOS/Linux. On Windows please use tian-cli.bat instead."
    exit 1
fi

# Prefer PowerShell Core if available (shares the same cli/tian.ps1 logic)
if command -v pwsh &>/dev/null; then
    pwsh -NoProfile -ExecutionPolicy Bypass \
         -File "$TIAN_DIR/cli/tian.ps1" \
         -TianDir "$TIAN_DIR" "$@"
else
    # Fall back to the native bash CLI
    bash "$TIAN_DIR/mac/tian-cli-bash.sh" "$TIAN_DIR" "$@"
fi
