# Contributing to Tian

Tian is designed to be extended by the community. You don't need to write PowerShell to add new AI backends, MCP servers, or skills.

---

## Adding a New AI Backend

Edit `config/catalog.json` and add an entry to the `backends` array:

```json
{
  "id": "my-backend",
  "displayName": "My AI Assistant",
  "description": "One sentence description shown in the wizard.",
  "npmPackage": "my-ai-package",
  "cliCommand": "myai",
  "apiKeyEnvVar": "MY_API_KEY",
  "apiKeyLabel": "My API Key",
  "apiKeyHint": "Starts with ...",
  "apiKeyUrl": "https://example.com/get-key",
  "mcpConfigTarget": "claude_code",
  "defaultMcpServers": [],
  "defaultSkills": []
}
```

If your backend stores MCP config in a non-standard location, add:
```json
"mcpConfigTarget": "custom",
"mcpConfigPath": "%APPDATA%\\MyApp\\config.json"
```

---

## Adding a New MCP Server

Add an entry to the `mcpServers` array in `config/catalog.json`:

```json
{
  "id": "my-server",
  "displayName": "My Tool",
  "description": "What this tool does for the user.",
  "category": "Productivity",
  "npmPackage": "my-mcp-server",
  "configKey": "my-server",
  "configSchema": {
    "command": "npx",
    "args": ["-y", "my-mcp-server"]
  }
}
```

If your server needs extra credentials, add:
```json
"requiredEnvVars": [
  {
    "name": "MY_TOKEN",
    "label": "My Token",
    "hint": "Get it from example.com",
    "url": "https://example.com/token"
  }
]
```

---

## Adding a New Skill

### Option 1: Built-in prompt file

1. Create a Markdown file in `skills/my-skill.md` describing what the AI should do.
2. Add an entry to the `skills` array in `config/catalog.json`:

```json
{
  "id": "my-skill",
  "displayName": "My Skill",
  "description": "One sentence shown in the wizard.",
  "category": "Daily Use",
  "source": "builtin",
  "promptFile": "skills/my-skill.md"
}
```

### Option 2: npm package

```json
{
  "id": "my-npm-skill",
  "displayName": "My NPM Skill",
  "description": "...",
  "category": "Developer",
  "source": "npm",
  "npmPackage": "my-skill-package"
}
```

---

## Wizard UI Changes

The wizard is split into pages under `wizard/pages/`. Each page is a self-contained PowerShell file with a single `Show-Page-*` function. Add a new page by:

1. Creating `wizard/pages/Page-MyPage.ps1` with a `Show-Page-MyPage` function
2. Dot-sourcing it in `wizard/Main.ps1`
3. Adding `"MyPage"` to the `$pages` array in the right position
4. Adding a `"MyPage"` case to the `switch` in `Show-CurrentPage`

---

## Pull Request Guidelines

- Test on Windows 10 and Windows 11 if possible
- Keep each PR focused: one backend, one MCP server, or one skill per PR
- Update `README.md` if you add a new backend or category of MCP servers
