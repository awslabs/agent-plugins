---
name: setup
description: Set up/configure/provision AWS Transform - continuous modernization (continuous modernization) components — security agent, sources, infrastructure. Delegates to atx ct setup CLI.
---

# Setup

## CRITICAL Prerequisites

**Use `atx ct` (with a space) when invoking AWS Transform - continuous modernization (continuous modernization) commands.** `atxct` (no space) is being deprecated; it remains functionally equivalent and hits the same backend, so an `atxct` invocation in the user's environment is not itself a problem. Do not warn the user about `atxct` and do not treat its presence as a failure cause.

### Step 1: Install or update `atx ct`

First verify that the `atx` selected by the shell provides the continuous-modernization commands. Keep stderr visible so dispatch errors are not mistaken for a missing installation:

```bash
atx ct --version
```

Handle the result by failure type:

- **`atx: command not found`** — install the AWS Transform CLI, then restart the shell or source its profile:

  ```bash
  curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
  source ~/.bashrc  # or ~/.zshrc
  ```

- **`unknown command 'ct'`** — an executable named `atx` ran, but it does not provide the required command. Do not reinstall blindly or check AWS credentials/region. Follow [command-resolution troubleshooting](continuous-modernization-troubleshooting.md#atx-ct-reports-unknown-command-ct) first.
- **Success** — compare the installed and latest versions:

  ```bash
  INSTALLED=$(atx ct --version | head -1)
  LATEST=$(curl -fsSL "https://transform-cli.awsstatic.com/index.json" 2>/dev/null | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  echo "Installed: ${INSTALLED:-not found}, Latest: ${LATEST:-unknown}"
  ```

  If `LATEST` is known and newer than `INSTALLED`, run the install command above, then restart the shell or source its profile.

Verify: `atx ct --help` must show CT subcommands.

### Step 2: Choose your region

If the user hasn't already specified one, ask which AWS region to run in and store it as `ATX_REGION=<region>`. Continuous modernization is only available in a subset of AWS regions; if the user picks an unsupported one, the command surfaces a region error.

**Prefix the chosen region inline on EVERY `atx ct` command** — `AWS_REGION=$ATX_REGION atx ct ...`, not just the first one. Each `atx ct` invocation resolves its own region and the shell does not persist env vars between separate command invocations, so the prefix must sit on the same command line as every invocation, including inside compound commands:

```bash
# Correct — prefix sits on the atx ct segment
which atx && AWS_REGION=$ATX_REGION atx ct analysis get --id <id> --json

# Wrong — atx ct runs without the region (the env var only applied to the first command)
AWS_REGION=$ATX_REGION which atx && atx ct analysis get --id <id> --json
```

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

## Tag Defaults (optional)

To have the CLI automatically apply tags to every resource it creates (sources, analyses, remediations, findings), create a settings file:

**File:** `~/.aws/atx/settings.json`

```json
{
  "applyTags": [
    { "team": "alpha", "env": "prod" }
  ]
}
```

`applyTags` is an **array of tag maps**. When this file exists and contains a valid `applyTags` array, the CLI applies those tags on every create operation without requiring `--tags` on each command. Multiple maps merge left-to-right (last map wins on a duplicate key); an explicit `--tags` value merges per key over the result. Tags enable IAM tag-based access control (ABAC) for multi-team isolation. See the [source](continuous-modernization-source.md) skill's Tags section for the full schema, merge semantics, and error behavior.

## Behavior

- If `atx ct` is not installed, install it using the curl command above before proceeding.
- If `atx ct` is installed but a newer version is available, reinstall it using the same curl command.
- If already configured, returns the existing config immediately.
- If not configured, kicks off async provisioning and returns immediately. Use `--status` to check progress.
- `--status` checks current state: `configured`, `setup_in_progress`, `failed`, or `not_configured`.
- `--delete` tears down AWS resources (CloudFormation stack, S3 bucket, config).
- Requires valid AWS credentials (`aws sts get-caller-identity` must succeed).
- If credentials are expired, ask the user to refresh them first.
