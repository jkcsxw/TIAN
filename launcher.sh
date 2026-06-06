#!/usr/bin/env bash
source "$HOME/.zshrc" 2>/dev/null || source "$HOME/.bashrc" 2>/dev/null || source "$HOME/.bash_profile" 2>/dev/null || true
echo "Starting Claude Code (Anthropic)..."
claude
