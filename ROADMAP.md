# TIAN Roadmap

This roadmap is based on the current codebase and focuses on the highest-leverage gaps for a tool aimed at non-technical users.

## Now

- Close CLI parity gaps between PowerShell and bash so macOS/Linux users without `pwsh` are not blocked.
- Make MCP configuration safer and clearer across Claude Desktop, Claude Code, and OpenAI config targets.
- Keep background jobs and scheduling reliable, especially around quota exhaustion and cross-platform behavior.
- Expand regression coverage for router, job, and scheduler flows on both PowerShell and bash.

## Next

- Add a true non-interactive `install` flow for the bash fallback, matching the PowerShell CLI flags.
- Add backend-aware status output that shows which backend is active and where each config file lives.
- Improve schedule UX with weekly day selection on bash and better one-time job behavior on Linux.
- Add export/import for TIAN configuration so users can migrate setups across machines.

## Later

- Add a richer doctor command that validates MCP credentials and backend reachability without leaking secrets.
- Build a packaged onboarding flow for macOS/Linux that reduces direct shell/profile editing.
- Add first-run templates for common business workflows such as briefs, inbox triage, and report generation.
- Support plugin-style extensions so MCP bundles and skills can be added without editing the main catalog.

## Shipped In This Pass

- `mac/tian-cli-bash.sh` now supports `repair`, `list backends`, `add mcp`, `add skill`, and `remove mcp`.
- Bash MCP config handling now resolves platform-specific config paths more consistently.
- Linux `schedule add ... once` no longer maps to `@reboot`; it falls back explicitly with a warning.
- Bash tests now cover the new router paths for backend listing, skill install, and MCP add/remove.
