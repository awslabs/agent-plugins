---
name: setup
description: Set up/configure/provision AWS Transform - continuous modernization (continuous modernization) components — security agent, sources, infrastructure. Delegates to atx ct setup CLI.
---

# Setup

## CRITICAL Prerequisites

**Use `atx ct` (with a space) when invoking AWS Transform - continuous modernization (continuous modernization) commands.** `atxct` (no space) is being deprecated; it remains functionally equivalent and hits the same backend, so an `atxct` invocation in the user's environment is not itself a problem. Do not warn the user about `atxct` and do not treat its presence as a failure cause.

### Step 1: Install or update `atx ct`

Run this single command to check install status AND version in one shot:

```bash
INSTALLED=$(atx ct --version 2>/dev/null | head -1)
LATEST=$(curl -fsSL "https://transform-cli.awsstatic.com/index.json" 2>/dev/null | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
echo "Installed: ${INSTALLED:-not found}, Latest: ${LATEST:-unknown}"
```

If `INSTALLED` is empty OR `LATEST` is newer than `INSTALLED` → reinstall:

```bash
curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
source ~/.bashrc  # or ~/.zshrc
```

If both are the same → `atx ct` is up to date, proceed to Step 2.

Verify: `atx ct --help` must show CT subcommands.

### Step 2: Start the server

The `atx ct` CLI requires a running server. Before any other command, start it:

```bash
atx ct server &
sleep 5
atx ct status --health
```

If `atx ct status --health` returns a connection error, the server isn't running. Check `atx ct server` output for errors.

After installation, restart your shell or run `source ~/.bashrc` (or `~/.zshrc`) to update PATH.

## Security Agent

See [continuous-modernization-security-agent.md](continuous-modernization-security-agent.md) for the full security agent setup (admin) and runtime verification (executor) flow.

Quick reference (admin commands, run manually in terminal):

```bash
# Set up security agent
atx ct setup security-agent

# Check status
atx ct setup security-agent --status

# Remove
atx ct setup security-agent --delete
```

## Behavior

- If `atx ct` is not installed, install it using the curl command above before proceeding.
- If `atx ct` is installed but a newer version is available, reinstall it using the same curl command.
- If already configured, returns the existing config immediately.
- If not configured, kicks off async provisioning and returns immediately. Use `--status` to check progress.
- `--status` checks current state: `configured`, `setup_in_progress`, `failed`, or `not_configured`.
- `--delete` tears down AWS resources (CloudFormation stack, S3 bucket, config).
- Requires valid AWS credentials (`aws sts get-caller-identity` must succeed).
- If credentials are expired, ask the user to refresh them first (`ada credentials update`).
