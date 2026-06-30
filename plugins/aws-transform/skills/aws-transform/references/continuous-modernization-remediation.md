---
name: remediation
description: Create/retry/list/delete remediation campaigns — auto-fix findings by applying ATX transforms or run custom TDs directly on repos, create PRs/CRs with fixes.
---

name: remediation

# Remediation

## Before offering remediation

When the user wants to remediate specific findings, fetch each one with `atx ct findings get --id <id>` and inspect its `fix` field before presenting options.

When using `--transformation-name`, ask the user if they have additional instructions (e.g. a target version or specific guidance) before running. If they do, pass them via `-g "additionalPlanContext=<instructions>"`.

- **`fix` is set** — the finding is auto-remediable via `--ids` alone. The server runs the finding's own `fix.transform_name`, which always matches the finding.
- **`fix` is null and `recommendation` names a transformation definition** — offer `--ids --transformation-name <name-from-recommendation>` ONLY when the finding is exactly the upgrade or migration that transformation definition performs (e.g. a Node.js version finding with a Node.js version-upgrade definition). A `recommendation` can name a transformation definition that does not actually fix the finding — a version-upgrade definition must never be used for ad-hoc work such as deleting files, resolving CDK Nag suppressions, Docker cleanup, or config edits. If the named definition does not directly perform the finding's fix, treat it as if there were no recommendation and use discovery below.
- **`fix` is null and no `recommendation`** (or a `recommendation` whose named definition does not fit) — use [Transformation Definition Discovery for Remediation](#transformation-definition-discovery-for-remediation) to find a matching transformation definition. If none performs the finding's fix, tell the user it must be fixed manually rather than forcing an unrelated definition.

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` — the AI assistant driving this session (lowercase, no spaces). Use the real assistant name — e.g. kiro, claude, amazonq, copilot.
- `executionMode` — `local`

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

```bash
# Create from finding IDs (uses each finding's fix.transform_name)
atx ct remediation create --ids <id1,id2> --name "Fix name" --telemetry "agent=<AGENT>,executionMode=local"

# Create from finding IDs with a custom TD override (ignores finding's fix field)
atx ct remediation create --ids <id1,id2> --transformation-name <TD-name> --telemetry "agent=<AGENT>,executionMode=local"

# Create directly on a repo with a custom TD (no findings required)
atx ct remediation create --transformation-name <TD-name> --repo <source>::<slug> --telemetry "agent=<AGENT>,executionMode=local"

# Create with configuration passed to the TD
atx ct remediation create --transformation-name <TD-name> --repo <source>::<slug> -g "additionalPlanContext=Upgrade to Node.js 22" --telemetry "agent=<AGENT>,executionMode=local"

# Create with local execution (runs ATX transform on the server instead of GitHub Actions)
atx ct remediation create --ids <id1,id2> --name "Fix name" --local --telemetry "agent=<AGENT>,executionMode=local"

# List all
atx ct remediation list

# Check status
atx ct remediation status --id <id>

# Retry failed
atx ct remediation retry --id <id>

# Delete
atx ct remediation delete --id <id>
```

## Security Remediation

Security findings (from `atx ct analysis run --type security`) are auto-remediable with the **same** `remediation create` command as any other finding — no `--transformation-name` is needed. Security findings carry a `security-agent` fix, which routes to the AWS Security Agent code-remediation API instead of an ATX transform; the fix is generated server-side.

```bash
# 1. Find the security findings to remediate
atx ct findings list --type security --json

# 2. Create a remediation from one or more security finding IDs
#    (same command as any other remediation)
atx ct remediation create --ids <security-finding-id> --name "Fix SQL injection"

# 3. Check status -- the result is a code diff or, for GitHub sources, a pull request
atx ct remediation status --id <remediation-id>
```

### Outcomes by source provider

The result link surfaces in `remediation status` and in the remediation record's `execution_artifacts`. What you get depends on the repo's source provider:

| Source provider                        | Per-repo status | Artifact            | Meaning                                                                                                                                                |
| -------------------------------------- | --------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **github**                             | `pr_open`       | `pull_request_link` | AWS Transform - continuous modernization (continuous modernization) applies the diff on the scanned commit and **opens a pull request** automatically. |
| **gitlab** / **bitbucket** / **local** | `diff_ready`    | `code_diff_link`    | A presigned URL to a unified diff. No PR is opened — apply the diff yourself.                                                                          |

- For **GitHub** sources, the diff is applied on a fresh clone pinned to the scanned commit and pushed as a pull request (idempotent per finding — re-running updates the same PR).
- For **gitlab**, **bitbucket**, and **local** sources, security remediation stays **diff-only**. GitHub is the only provider that gets an auto-opened PR from a security diff. (This differs from tech-debt/transform remediation, where GitLab opens a Merge Request and Bitbucket opens a Pull Request — security diffs are not pushed to those providers.)
- The PR step is **fail-soft**: if opening the PR fails, the usable diff is preserved (status stays `diff_ready`, `code_diff_link` set) and the reason is recorded in `execution_artifacts.pr_bridge_error`. A bridge failure never discards a good diff.

### Requirements

- The `AWSSecurityAgentWebAppPolicy` IAM policy already required to run `analysis --type security` also grants the remediation permission — **no additional setup is needed** beyond `atx ct setup security-agent`.
- The finding must come from a security analysis whose code review is still resolvable. If it has aged out, the finding carries no fix (`fix: null`) and is manual-only — re-run the security analysis to make it remediable again.

## Custom Transformation Definition Remediation

Remediation supports running any transformation definition directly, with or without existing findings.

### Three modes:

1. **Findings-based (existing):** `--ids <finding-ids>` — uses each finding's `fix.transform_name` to determine which transformation definition to run on each repo.

2. **Findings + transformation definition override:** `--ids <finding-ids> --transformation-name <name>` — uses the repos from the findings but runs the specified transformation definition instead of the finding's `fix.transform_name`. Findings without a `fix` field are accepted (they would normally be rejected).

3. **Direct transformation definition on repo (no findings):** `--transformation-name <name> --repo <source>::<slug>` — runs the transformation definition directly on the specified repo without requiring any findings. Repos must be discovered first (`atx ct discovery scan`).

### Configuration (`-g`)

The `-g`/`--configuration` flag passes configuration directly to the transformation definition. Accepts three formats:

- Key-value: `"additionalPlanContext=Upgrade to Node.js 22,buildCommand=npm test"`
- JSON: `'{"additionalPlanContext":"Upgrade to Node.js 22"}'`
- File path: `"file:///path/to/config.json"`

Only valid with `--transformation-name`.

### Constraints

- At least one of `--ids` or `--transformation-name` is required
- `--repo` cannot be used together with `--ids` (repos are derived from findings)
- `--repo` is required when `--transformation-name` is used without `--ids`
- `-g` is only valid with `--transformation-name`
- Repos must be discovered (`atx ct discovery scan`) before remediation can target them

## Transformation Definition Discovery for Remediation

When the user asks to remediate with a custom transformation definition, or a finding has no `fix` field and no `recommendation` that names a transformation definition which actually performs the finding's fix, use transformation definition discovery to find the right transformation definition. If a finding's `recommendation` names a transformation definition AND that definition is exactly the upgrade/migration that performs the finding's fix, skip discovery and use that name directly; otherwise treat the recommendation as if it were absent and discover.

### Workflow

1. **List available transformation definitions:** Run `atx custom def list` to fetch all available transformation definitions.
2. **Match intent:** Based on the user's description of what they want to fix, match against transformation definition names and descriptions.
3. **Recommend and confirm:** Present the matched transformation definition(s) to the user. Wait for confirmation.
4. **Ask for additional instructions:** Ask the user if they have additional instructions (e.g. a target version or specific guidance) before running. If they do, pass them via `-g "additionalPlanContext=<instructions>"`.
5. **Execute:** Run `atx ct remediation create --transformation-name <matched-name> --repo <source>::<slug>` (with `-g` if the user provided additional instructions).

## Options

### `--local` flag (remediation create)

When `--local` is passed, the ATX transform runs directly on the server against a cloned copy of the repository instead of dispatching a GitHub Actions workflow. This is useful for:

- GitHub-sourced repos where you want faster feedback without waiting for CI
- Environments where GitHub Actions workflows are not configured or available
- Testing transforms locally before committing to a full workflow run

The execution mode is persisted on the remediation record (`compute_mode = 'local'`), so subsequent `retry` and `resume` operations automatically honour the original intent without needing to re-specify the flag.
