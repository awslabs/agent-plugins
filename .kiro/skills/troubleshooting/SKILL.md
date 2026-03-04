---
name: troubleshooting
description: Troubleshooting guide for plugin installation, skill auto-triggering, MCP server connections, and CI issues. Use when debugging plugin problems, fixing installation errors, or resolving build failures. Triggers on "plugin not working", "skill not triggering", "MCP connection failed", "troubleshoot", or "CI failed".
---

# Plugin Troubleshooting

For the full troubleshooting guide, read `docs/TROUBLESHOOTING.md` in the repository root.

## Common Issues

### Skill Not Auto-Triggering

1. Verify skill is loaded: `/skills`
2. Use explicit trigger phrases from the skill description
3. Check plugin installation: `/plugin list`

### MCP Server Connection Issues

1. Check logs: `~/.cache/claude-code/logs/`
2. Toggle the MCP server off/on via `/plugin` UI

### Plugin Installation Issues

```bash
/plugin marketplace remove agent-plugins-for-aws
/plugin marketplace add awslabs/agent-plugins
/plugin install deploy-on-aws@agent-plugins-for-aws
```

### CI Failed Jobs

- Repository collaborators: use "Re-run failed jobs" in GitHub UI
- Fork contributors: push empty commit (`git commit --allow-empty -m "retry CI"`) or ask a maintainer
