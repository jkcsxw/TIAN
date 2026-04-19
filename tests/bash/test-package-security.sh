#!/usr/bin/env bash
# Security checks for the Windows installer package contents
set -uo pipefail
source "$(dirname "$0")/bash-helpers.sh"

TIAN_ROOT=$(get_tian_root)
export TIAN_ROOT

run_package_scan() {
    local mode="$1"
    PACKAGE_SCAN_MODE="$mode" python3 <<'PY'
import glob
import os
import re
import sys
from pathlib import Path


def packaged_files(repo_root: Path):
    iss_file = repo_root / "installer" / "tian-setup.iss"
    installer_dir = iss_file.parent
    files = []
    in_files_section = False

    for raw_line in iss_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("["):
            in_files_section = line.lower() == "[files]"
            continue
        if not in_files_section:
            continue

        match = re.search(r'Source:\s*"([^"]+)"', line, re.IGNORECASE)
        if not match:
            continue

        source_pattern = match.group(1).replace("\\", os.sep)
        full_pattern = str(installer_dir / source_pattern)
        for candidate in glob.glob(full_pattern, recursive=True):
            path = Path(candidate)
            if path.is_file():
                files.append(path.resolve())

    unique_files = []
    seen = set()
    for path in sorted(files):
        rel = path.relative_to(repo_root).as_posix()
        if rel not in seen:
            seen.add(rel)
            unique_files.append(path)
    return unique_files


def scan_forbidden_names(files):
    forbidden_patterns = [
        r"(^|/)\.env($|[.])",
        r"(^|/)\.npmrc$",
        r"(^|/)\.netrc$",
        r"(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$",
        r"(^|/)credentials(\.json)?$",
        r"(^|/)secrets?(\.json)?$",
        r"\.(pem|key|p12|pfx|crt|cer)$",
    ]

    flagged = []
    for path in files:
        rel = path.relative_to(repo_root).as_posix()
        for pattern in forbidden_patterns:
            if re.search(pattern, rel, re.IGNORECASE):
                flagged.append(rel)
                break
    return flagged


def scan_secret_patterns(files):
    secret_patterns = [
        ("private_key", re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC |DSA |)?PRIVATE KEY-----")),
        ("aws_access_key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
        ("github_token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b")),
        ("github_pat", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
        ("slack_token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
        ("google_api_key", re.compile(r"\bAIza[0-9A-Za-z\-_]{20,}\b")),
        ("stripe_live_key", re.compile(r"\bsk_live_[0-9A-Za-z]{16,}\b")),
        ("openai_api_key", re.compile(r"\bsk-(?!ant-)(?:proj-)?[A-Za-z0-9_-]{20,}\b")),
        ("anthropic_api_key", re.compile(r"\bsk-ant-(?!xxx\b)(?!\.\.\.)([A-Za-z0-9_-]{20,})\b")),
    ]

    findings = []
    for path in files:
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = path.read_text(encoding="utf-8", errors="ignore")

        for name, pattern in secret_patterns:
            match = pattern.search(content)
            if match:
                findings.append(f"{path.relative_to(repo_root).as_posix()}: {name}: {match.group(0)}")
    return findings


repo_root = Path(os.environ["TIAN_ROOT"]).resolve()
mode = os.environ["PACKAGE_SCAN_MODE"]
files = packaged_files(repo_root)

if not files:
    print("No packaged files were resolved from installer/tian-setup.iss")
    sys.exit(1)

if mode == "resolve":
    print(len(files))
    sys.exit(0)

if mode == "filenames":
    bad = scan_forbidden_names(files)
    if bad:
        print("\n".join(bad))
        sys.exit(1)
    sys.exit(0)

if mode == "contents":
    leaks = scan_secret_patterns(files)
    if leaks:
        print("\n".join(leaks))
        sys.exit(1)
    sys.exit(0)

print(f"Unknown PACKAGE_SCAN_MODE: {mode}")
sys.exit(1)
PY
}

suite "Package security"

_test_packaged_file_list_resolves() {
    local count
    count=$(run_package_scan resolve)
    [[ "$count" -gt 0 ]]
}
it "installer package contents resolve from tian-setup.iss" _test_packaged_file_list_resolves

_test_no_sensitive_files_packaged() {
    run_package_scan filenames
}
it "package excludes common credential and key files" _test_no_sensitive_files_packaged

_test_no_secret_like_content_packaged() {
    run_package_scan contents
}
it "package text files do not contain secret-like values" _test_no_secret_like_content_packaged

finish
