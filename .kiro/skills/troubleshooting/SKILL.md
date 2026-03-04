---
name: troubleshooting
description: Troubleshooting guide for plugin installation, skill auto-triggering, MCP server connections, and CI issues. Use when debugging plugin problems, fixing installation errors, or resolving build failures. Triggers on "plugin not working", "skill not triggering", "MCP connection failed", "troubleshoot", or "CI failed".
---

# Plugin Troubleshooting

## Workflow

### Step 1: Identify the Problem Category

- **Plugin installation** — marketplace not found, plugin not found
- **Skill not triggering** — skill not loaded, phrasing too vague
- **MCP server failure** — connection issues, server not starting
- **CI failure** — flaky jobs, permission issues on forks

### Step 2: Quick Fixes

- Plugin issues: remove and re-add marketplace, then reinstall plugin
- Skill issues: verify with `/skills`, try explicit trigger phrases, check `/plugin list`
- MCP issues: check logs at `~/.cache/claude-code/logs/`, toggle server off/on via `/plugin`
- CI issues: re-run failed jobs via GitHub UI or `gh api`

### Step 3: Full Reset (if quick fixes fail)

1. Remove marketplace via `/plugin` → Marketplaces → Remove
2. Exit Claude Code and close terminal
3. `rm -rf ~/.claude/plugins/cache`
4. Clean entries from `~/.claude/plugins/installed_plugins.json` and `known_marketplaces.json`
5. Restart and re-add: `/plugin marketplace add awslabs/agent-plugins`

For detailed steps, verification commands, CI re-run instructions, and debug mode, see references/full-guide.md.
