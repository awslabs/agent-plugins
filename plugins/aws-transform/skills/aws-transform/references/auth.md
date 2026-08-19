# Authentication

There are two independent auth paths:

- **AWS Transform (MCP tools)** — workspaces, jobs, tasks, artifacts, connectors, agents. The MCP server is authoritative: its tool descriptions, `get_status` response, and error messages describe supported methods, current state, and recovery.
- **Custom transformations (AWS Transform CLI)** — the `atx` CLI, which uses standard AWS credentials. No `atx auth` command, no MCP involvement.

The paths do not block each other. A custom CLI intent proceeds with AWS credentials alone; an MCP intent does not require the CLI. Per the skill instructions, prompt for auth just-in-time for the chosen action — do not probe or demand both.

## Signing in

When sign-in is needed, `get_status` returns a message on the unconfigured connection that enumerates the currently-supported options. Present **every** option from that message — do not drop any, do not add any, do not reorder for emphasis. The MCP server is authoritative for which options are valid at a given moment (some options may be conditionally unavailable).

Details the MCP message does not include, collect from the user only for the option they pick:

- **Cookie mode** — need `origin` and `sessionCookie`. The cookie comes from the browser: log in to the AWS Transform tenant URL → DevTools (F12) → Application → Cookies → `aws-transform-session` → copy **Value**.
- **SSO mode** — need `startUrl` (looks like `https://d-xxxxxxxxxx.awsapps.com/start`, from IAM Identity Center) and `idcRegion`.
- **AWS Credentials** — no interactive detail to gather. `AWS_PROFILE` lives in the MCP client's env block; the MCP picks it up on restart.

When a session expires or a cookie is invalid, follow the recovery guidance in the MCP's error message.

## AWS Transform CLI auth

The CLI uses standard AWS credentials. There is no `atx auth` command — auth is whatever the AWS SDK / CLI provider chain resolves.

```bash
aws sso login --profile my-profile
export AWS_PROFILE=my-profile
export AWS_REGION=us-east-1
```

Verify: `AWS_REGION=us-east-1 atx custom def list --json`.

Common CLI-side conditions:

- `AccessDeniedException` → AWS credentials expired. Re-run `aws sso login` or refresh env vars.
- `command not found: atx` → CLI not installed. Use MCP-based transforms instead, or install the CLI.

### WSL: separate AWS config on the Linux and Windows sides

On Windows, running the CLI inside WSL introduces a common footgun. WSL's Linux home directory and the Windows user profile each hold their **own** `~/.aws/config` (WSL: `~/.aws/config`; Windows: `C:\Users\<user>\.aws\config`). `aws sso login` refreshes the cached SSO token only for the environment it was run in — a login in Windows PowerShell does not produce a token the WSL side can read, and vice versa.

When a user on Windows/WSL reports `AccessDenied`, expired-token, or "no credentials" errors from `atx` or `aws` **despite having signed in**, suspect this split before generic re-auth advice. Confirm which environment they run `atx` in (the WSL shell) versus where they ran `aws sso login`. The fix: run `aws sso login --profile <profile>` **in the same WSL shell** where `atx` runs, so it reads the WSL-side `~/.aws/config` and caches the refreshed token under that side's `~/.aws/sso/cache/`. Verify from that same shell with `aws sts get-caller-identity`. (If a user deliberately shares one config across both sides, they must set `AWS_CONFIG_FILE`/`AWS_SHARED_CREDENTIALS_FILE` to the shared path in every shell — but same-environment login is the simpler default.)

## Environment variables (MCP client config)

Pre-set in `mcp.json` to skip an interactive `configure` call:

| Variable         | Description                                   |
| ---------------- | --------------------------------------------- |
| `ATX_REGION`     | AWS region (default `us-east-1`)              |
| `ATX_AUTH_MODE`  | `cookie` or `sso`                             |
| `ATX_TENANT_URL` | Tenant URL (cookie mode)                      |
| `SESSION_COOKIE` | `aws-transform-session=<value>` (cookie mode) |
