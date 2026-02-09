# Plugin Troubleshooting Guide

This guide provides troubleshooting steps for common issues when using plugins with various AI assistants.

## Claude Code

### Official Documentation

For general plugin troubleshooting, see the official documentation:

- [Claude Code plugin marketplace troubleshooting guide](https://code.claude.com/docs/en/plugin-marketplaces#troubleshooting)
- [Claude Code plugins discovery troubleshooting guide](https://code.claude.com/docs/en/discover-plugins#troubleshooting)

### TUI (Terminal User Interface) Issues

If you're experiencing issues with the Claude Code TUI such as plugins not loading, skills not appearing, or marketplace data not refreshing:

#### Complete Reset Procedure

1. **Remove the markerplace**
   - Within claude, run `/plugin`
   - Use your right arrow to navigate to the 'Marketplaces' tab
   - Select your marketplace
   - Press enter, then select 'Remove marketplace'

1. **Exit the current Claude Code session**
   - Press `Ctrl+C` or type `/exit` to close the active session

1. **Close the terminal window**
   - Completely close your terminal application (not just the tab)

1. **Clear the Claude Code cache**

   ```bash
   # On macOS/Linux
   rm -rf ~/.claude/plugins/cache
   ```

1. **Reset plugin state files**
   Remove the information related to this marketplace/installed plugins from this marketplace in the state files:

   - **`~/.claude/plugins/installed_plugins.json`** — which plugins are installed (version, install path, scope)
   - **`~/.claude/plugins/known_marketplaces.json`** — which marketplaces are known (sources, URLs)

1. **Restart**
   - Open a new terminal window
   - Run `claude` to start a fresh session

1. **Install**
   - Within claude, run `/plugin marketplace add awslabs/agent-plugins`

#### Verification Steps

After resetting, verify your setup:

```bash
claude
#(run inside Claude Code the next commands)
# Check installed marketplaces
/plugin marketplace list

# Check installed plugins
/plugin list
# Then navigate to the "Installed" tab using your right arrow

# Check available skills 
/skills

# Check available mcp servers
/mcp
```

### Plugin Installation Issues

#### Marketplace Not Found

```bash
# Remove and re-add the marketplace
/plugin marketplace remove awslabs-agent-plugins
/plugin marketplace add awslabs/agent-plugins
```

#### Plugin Not Found in Marketplace

1. Verify the marketplace was added correctly:

   ```bash
   /plugin marketplace list
   ```

2. Check the marketplace repository is accessible:
   - Visit https://github.com/awslabs/agent-plugins
   - Verify `.claude-plugin/marketplace.json` exists

3. Reinstall the marketplace and plugin:

   ```bash
   /plugin marketplace remove awslabs-agent-plugins
   /plugin marketplace add awslabs/agent-plugins
   /plugin install deploy-on-aws@awslabs-agent-plugins
   ```

4. Try the reset procedure

#### MCP Server Connection Issues

If MCP servers (like `awspricing`, `awsknowledge`, `awsiac`) fail to connect:

1. Check MCP server logs:

   ```bash
   # Logs are typically in
   ~/.cache/claude-code/logs/
   ```

2. Restart the servers

   ```
   # Run this within claude code
   /plugin
   # navigate to the installed tab, use your keyboard arrows to navigate to the plugin you are interested, then the mcp server
   # Press space to toggle the mcp server, then toggle again to restart
   ```

### Skill Not Auto-Triggering

If a skill isn't being invoked when expected:

1. **Verify the skill is loaded:**

   ```bash
   /skills
   ```

   Look for `deploy-on-aws:deploy` in the list

2. **Check your phrasing:**
   - Skills auto-trigger based on intent matching
   - Try explicit phrases like "deploy this to AWS" or "host on AWS"
   - Avoid ambiguous requests like "help me with AWS"

3. **Manually invoke the skill:**

   ```bash
   /deploy
   ```

4. **Check plugin installation:**

   ```bash
   /plugin list
   ```

   Ensure `deploy-on-aws` shows as installed

### Getting Help

If issues persist:

1. **Check GitHub Issues:**
   - Search existing issues: https://github.com/awslabs/agent-plugins/issues
   - Look for similar problems and solutions

2. **Enable Debug Mode:**

   ```bash
   claude --verbose
   ```

3. **Collect Information:**
   - Claude Code version: `claude --version`
   - Plugin version: `/plugin list`
   - Error messages from logs: `~/.cache/claude-code/logs/`
   - Verify the scope of installation

4. **Create a New Issue:**
   - Visit https://github.com/awslabs/agent-plugins/issues/new
   - Include your collected information
   - Describe steps to reproduce the issue

## Other AI Assistants

Support for additional AI assistants will be added here as the plugin system expands.

---

**Last Updated:** 2026-02-09
