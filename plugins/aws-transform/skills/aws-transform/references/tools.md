# Table of Contents

- [Jobs](#jobs)
- [Connectors](#connectors)
- [HITL Tasks (Collaborator Requests)](#hitl-tasks-collaborator-requests)
  - [Building the content payload](#building-the-content-payload)
  - [Severity](#severity)
  - [TOOL_APPROVAL tasks (separate flow)](#tool_approval-tasks-separate-flow)
- [AWS Transform CLI Commands](#aws-transform-cli-commands)
  - [Core Commands](#core-commands)
  - [Execution Flags](#execution-flags)
- [Troubleshooting (Non-Auth)](#troubleshooting-non-auth)
  - [Job Issues](#job-issues)
  - [Connector Issues](#connector-issues)
  - [HITL Task Issues](#hitl-task-issues)
  - [MCP Server Issues](#mcp-server-issues)
  - [Rollback](#rollback)

---

## Tools

Canonical tool names, parameters, and per-resource requirements come from the MCP server's `tools/list` response — read the tool descriptions directly. This file covers cross-tool workflows, behavioral rules, and the AWS Transform CLI, which the schemas don't provide. For auth behavior, see [auth](auth.md).

## Jobs

`create_job` creates AND starts the job in one call — no separate `control_job` start is needed. Only orchestrator agents can create jobs; discover them via `list_resources resource="agents" agentType="ORCHESTRATOR_AGENT"`. Use `jobType` OR `orchestratorAgent`, not both — if one fails, retry with the other.

## Connectors

Connector lifecycle:

```
PENDING → ACTIVE → COMPLETED
   ↓         ↓
REJECTED   FAILED
```

Connectors start `PENDING`. An AWS admin must approve via the verification link returned by `create_connector`. Do NOT proceed with dependent tasks until the user confirms admin approval. Check status with `get_resource resource="connector"`.

## HITL Tasks (Collaborator Requests)

**CRITICAL: Never auto-submit. Always present to the user first.**

Workflow for a regular HITL task:

1. `list_resources resource="tasks"` — find tasks needing human action. Three human-actionable states:
   - `AWAITING_HUMAN_INPUT` — first input required from the user
   - `IN_PROGRESS` — user has engaged but not submitted
   - `AWAITING_APPROVAL` — submitted for admin/approver decision
     Surface all three to the user — the person in front of you may be the approver. Whether a task blocks the job depends on its `blockingType` (`BLOCKING` vs `NON_BLOCKING`); surface the state regardless, but let the user know when a blocking task is holding progress.
2. `get_resource resource="task"` — returns two top-level objects you must read together:
   - `task` — enriched with `_outputSchema`, `_responseTemplate`, `_responseHint`, `uxComponentId`, `severity`. Tells you the **submission shape**.
   - `agentArtifactContent` — downloaded from S3. Tells you the **user-visible context**: current field values, items to select from, component-specific extras (toggles, feature flags, resource identifiers) that may not appear in `_outputSchema`.
3. Present the task to the user. Two things must be surfaced:
   - The content of `agentArtifactContent` — this is what the user sees in the web UI. Do not paraphrase it down to a single field.
   - Any fields in `_outputSchema` the user needs to provide.
4. Follow `_responseHint` — it is authoritative per `uxComponentId`. If the hint says "Only provide fields you want to change" or similar merge language, the server merges your payload onto the existing artifact. Send **only fields the user explicitly changed** — omit any field the user confirmed as-is or did not modify. Including unchanged fields violates the merge contract and can produce unintended overwrites.
5. Never silently substitute a value the user didn't see. This applies especially to boolean toggles and opt-ins — surface the current value and ask, even if the server has a safe default.
6. Wait for the user's decision.
7. Before calling `complete_task`, show the full payload you are about to submit and confirm.
8. `complete_task` — submit with the user's response.

### Building the `content` payload

Shape the payload based on the task's `_outputSchema` (returned by `get_resource resource="task"`):

- **TextInput** — `{"data": "your text"}`
- **AutoForm** — `{"fieldName": "value", ...}` — flat JSON matching the schema
- **File upload** — call `upload_artifact` first, then pass the returned `artifactId` in `content`
- **Display-only** — omit `content` (the server submits `{}`)

### Severity

- `STANDARD` — APPROVE/REJECT submits immediately.
- `CRITICAL` — non-admins must use `SEND_FOR_APPROVAL`; admins can APPROVE directly.

### TOOL_APPROVAL tasks (separate flow)

When `list_resources resource="tasks" category="TOOL_APPROVAL"` returns items, use `list_tool_approvals` / `approve_tool_approval` / `deny_tool_approval` — NOT `complete_task`. The backend rejects `complete_task` for TOOL_APPROVAL tasks.

---

## AWS Transform CLI Commands

The CLI uses standard AWS credentials (see [auth](auth.md)). Always set `AWS_REGION`.

### Core Commands

| Action                                | Command                                                                 |
| ------------------------------------- | ----------------------------------------------------------------------- |
| List transformation definitions       | `atx custom def list --json`                                            |
| Execute transformation definition     | `atx custom def exec -n <name> -p <path> -x -t`                         |
| Get transformation definition details | `atx custom def get -n <name>`                                          |
| Save draft                            | `atx custom def save-draft -n <name> --description "<desc>" --sd <dir>` |
| Publish                               | `atx custom def publish -n <name> --description "<desc>" --sd <dir>`    |
| Delete transformation definition      | `atx custom def delete -n <name>`                                       |
| Interactive mode                      | `atx`                                                                   |
| Resume conversation                   | `atx --resume`                                                          |
| Update CLI                            | `atx update`                                                            |

### Execution Flags

| Flag                                | Description                                                        |
| ----------------------------------- | ------------------------------------------------------------------ |
| `-n` / `--transformation-name`      | Transformation definition name (from `atx custom def list --json`) |
| `-p` / `--code-repository-path`     | Path to code repo (`.` for current dir)                            |
| `-x` / `--non-interactive`          | No user prompts                                                    |
| `-t` / `--trust-all-tools`          | Auto-approve tool executions (required with `-x`)                  |
| `-c` / `--build-command`            | Build/validation command (optional, auto-detected)                 |
| `-d` / `--do-not-learn`             | Prevent knowledge item extraction                                  |
| `-g` / `--configuration`            | Config file (`file://config.yaml`) or inline (`'key=val'`)         |
| `--tv` / `--transformation-version` | Specific transformation definition version                         |

**NEVER hardcode transformation definition names.** Always fetch from `atx custom def list --json`.

---

## Troubleshooting (Non-Auth)

### Job Issues

| Problem               | Resolution                                                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Job stuck in RUNNING  | Check `list_resources resource="tasks"` for pending HITL tasks                                                    |
| Job fails immediately | Check `get_resource resource="job"` for `errorDetails`. Common: connectors not set up or not ACTIVE               |
| Job type not found    | Use `list_resources resource="agents"` to discover available agents. Try `orchestratorAgent` instead of `jobType` |
| Missing artifacts     | Job may not be complete — check status first                                                                      |

### Connector Issues

| Problem                  | Resolution                                                                                                             |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Stuck in PENDING         | Admin hasn't approved — share verification link                                                                        |
| FAILED                   | Check IAM role permissions. Trust policy must allow `transform.amazonaws.com`                                          |
| `accept_connector` fails | Needs AWS Credentials available in the environment; see the tool's description and `get_status` for current auth state |

### HITL Task Issues

| Problem                      | Resolution                                                                                                                                |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `VALIDATION_ERROR` on submit | Check `_outputSchema` from `get_resource resource="task"`. Don't wrap in `{"data":...}` or `{"properties":...}` unless schema requires it |
| Empty `agentArtifactContent` | Agent still generating. Check worklogs, wait 30-60s, retry                                                                                |
| File upload fails            | Verify path exists. Specify `fileType` explicitly                                                                                         |

### MCP Server Issues

| Problem                 | Resolution                                                                 |
| ----------------------- | -------------------------------------------------------------------------- |
| Tools not available     | Restart your IDE. Check `mcp.json` for syntax errors                       |
| MCP server not starting | Path in `mcp.json` may be relative — must be absolute. Check binary exists |
| Region mismatch         | Ensure `region` in `configure` matches where resources are                 |

### Rollback

Transform works on copies — original code is untouched until you apply changes.

- **Haven't applied changes:** Safe. Delete job/artifacts if unwanted.
- **Applied via git:** `git log` to find pre-transform commit, `git checkout <hash>` or `git revert`.
- **Code connector branch:** Transform creates a separate branch. Delete it with `git branch -D atx/transform-<jobId>`.
- **Manually copied files:** Use `git checkout HEAD~1 -- path/to/file` or IDE local history.
