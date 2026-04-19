#!/usr/bin/env bash
# TIAN Test Runner — Mac / Linux
# Runs bash tests and optionally PowerShell (Pester) tests if pwsh is available
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS_SUITES=0
FAIL_SUITES=0

echo ""
echo "============================================================"
echo " TIAN Test Runner  (Mac/Linux)"
echo "============================================================"

run_bash_suite() {
    local file="$1"
    local name
    name=$(basename "$file")
    echo ""
    echo "── $name ──────────────────────────────────────────────"
    if bash "$file"; then
        ((PASS_SUITES++))
    else
        ((FAIL_SUITES++))
    fi
}

# ── Bash test suites ──────────────────────────────────────────────────────────
for f in "$SCRIPT_DIR/bash/test-"*.sh; do
    [[ -f "$f" ]] && run_bash_suite "$f"
done

# ── PowerShell / Pester tests (optional) ─────────────────────────────────────
if command -v pwsh &>/dev/null; then
    echo ""
    echo "── Pester (PowerShell) tests ───────────────────────────"
    pwsh -NoProfile -Command "
        if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge '5.0')) {
            Write-Host 'Installing Pester v5...'
            Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
        }
        Set-Location '$SCRIPT_DIR/..'
        \$config = New-PesterConfiguration
        \$config.Run.Path = '$SCRIPT_DIR/ps'
        \$config.Run.Exit = \$true
        \$config.Output.Verbosity = 'Detailed'
        \$config.TestResult.Enabled = \$true
        \$config.TestResult.OutputPath = '$SCRIPT_DIR/results-mac.xml'
        Invoke-Pester -Configuration \$config
    " && ((PASS_SUITES++)) || ((FAIL_SUITES++))
else
    echo ""
    echo "[SKIP] pwsh not found — skipping Pester tests (install PowerShell Core to enable)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Results: $PASS_SUITES suite(s) passed, $FAIL_SUITES suite(s) failed"
echo "============================================================"
echo ""

[[ $FAIL_SUITES -eq 0 ]]
