---
name: remediation
description: Create/retry/list/cancel/delete remediation campaigns — auto-fix findings by applying AWS Transform transformation definitions, or run a transformation definition directly on repos, and open pull/merge requests with the fixes.
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
# Create from finding IDs (uses each finding's fix.transform_name).
# Pass --wait so the command blocks until the remediation finishes (version-gated — see "Running long remediations" below).
atx ct remediation create --ids <id1,id2> --name "Fix name" --wait --telemetry "agent=<AGENT>,executionMode=local"

# Create from finding IDs with a transformation definition override (ignores finding's fix field)
atx ct remediation create --ids <id1,id2> --transformation-name <transformation-name> --telemetry "agent=<AGENT>,executionMode=local"

# Create directly on a repo with a transformation definition (no findings required)
atx ct remediation create --transformation-name <transformation-name> --repo <source>::<slug> --telemetry "agent=<AGENT>,executionMode=local"

# Several repos: --repo (alias --repos) is repeatable and/or comma-separated; a bare <repo> needs --source
atx ct remediation create --transformation-name <transformation-name> --repo svc-a,svc-b --source <name> --telemetry "agent=<AGENT>,executionMode=local"

# Create with configuration passed to the transformation definition
atx ct remediation create --transformation-name <transformation-name> --repo <source>::<slug> -g "additionalPlanContext=Upgrade to Node.js 22" --telemetry "agent=<AGENT>,executionMode=local"

# Record the run as local and cap its concurrency by this host's memory (see "--local flag")
atx ct remediation create --ids <id1,id2> --name "Fix name" --local --telemetry "agent=<AGENT>,executionMode=local"

# Limit how many repos are remediated at once (see "--slots flag")
atx ct remediation create --transformation-name <transformation-name> --repo <source>::<slug> --slots 10 --telemetry "agent=<AGENT>,executionMode=local"

# `remediation run` is an alias of `remediation create`

# List all, or one status (pending|running|completed|partial|failed|cancelled)
atx ct remediation list --json
atx ct remediation list --status failed --json

# Check status (add --json for display_status and per-repo results)
atx ct remediation status --id <id>

# Retry the repos that are still pending or failed (re-runs them with the original settings)
atx ct remediation retry --id <id>

# Cancel a running remediation
atx ct remediation cancel --id <id>

# Delete
atx ct remediation delete --id <id>
```

A remediation created from finding IDs gives the transformation every finding it covers, and fixes each one. When it ends, it lists any finding it did not fully address and why — relay that list to the user rather than reporting every finding as fixed.

If validation finds items blocked outside the change (for example a dependency version the project's build environment doesn't provide yet), the pull or merge request description starts with a **Not complete: blocked outside this change** section that lists them and the actions their owners need to take. Tell the user the change isn't done, and pass on those actions.

## Size limits per request

`atx ct remediation create` has no fixed repository cap of its own. Two limits apply before anything is created:

- **At most 250 findings** per remediation: `Too many findings: <N> exceeds the 250-finding limit for one remediation. Split the submission.`
- **A metadata budget** that scales with the findings and repositories together, because the CLI stores each repository's finding details with the remediation and the stored record has a fixed size. When it is exceeded the CLI prints `Remediation metadata too large: <R> repos / <F> findings serialize to ... At this metadata size about <K> findings (or repos) fit — split the submission.` Details such as long finding titles and descriptions make each repository's share larger, so the number of repositories that fit varies from request to request.

Do not split in advance or guess a group size: submit the full list in one `remediation create` first, and let the CLI tell you how many fit.

If either message appears, split the work into several `remediation create` requests: divide the `--ids` list (or the `--repo` list when you pass `--transformation-name` alone) into groups no larger than the number the message gives, create one remediation per group, and tell the user you are splitting it. A message that says even one repo's or finding's metadata does not fit can't be fixed by splitting; report it to the user.

## Reading a remediation's result

A finished remediation's `Status:` is one of:

- `completed` — every repository ran (or was cancelled) and at least one succeeded. Some may still have failed: check the `Outcome:` line and the per-repo results.
- `partial` — some repositories did not start, and at least one succeeded.
- `failed` — no repository succeeded.
- `cancelled` — the remediation was cancelled, or every repository was cancelled.

Each repository's own status is one of: succeeded — `pr_open`, `diff_ready`, `no_changes` (nothing to change), `already_applied`, `pr_exists`, `skipped`; failed — `failed`, `blocked`; or `cancelled`, `pending`, `running`.

`atx ct remediation status` adds an `Outcome:` line when there is more to tell, for example `Complete with failures (N of M failed)` or `Partially complete (N of M did not start)`, with cancel counts when some repositories were cancelled. `atx ct remediation create --wait` prints the same line after the final status. With `--json`, read `display_status` (`complete`, `complete_with_failures`, `partially_complete`, `failed`, `cancelled`, `running`, `pending`) and `repos_not_run`. Report a `completed` remediation with failures as complete with failures, and list the failed repositories, rather than as fully done.

## Running long remediations (--wait, background, logs)

`atx ct remediation create` returns immediately by default with a remediation ID. With `--wait` it blocks until the remediation completes — and applying transforms across repos can take a long time. Prefer `--wait` so you can act on the result in the same step.

**`--wait` is version-gated** — `atx ct remediation create` accepts it from CLI 3.5.0 on. `--help` doesn't list it (the option is hidden), so check the version instead: run `atx ct --version`, and pass `--wait` only on 3.5.0 or later; on an older CLI, run without `--wait`, leave it out of every command you show the user too, including ones for after an upgrade, and do not invent the flag. Only re-run without `--wait` if the command fails with an error that explicitly names `--wait` as an unrecognized option AND returned no remediation ID — do not treat auth, `INVALID_INPUT`, or repo-cap failures as a missing-flag error, and never blindly re-run a `create` that may have already submitted.

**Run long jobs in the background and monitor a log.** Start long-running remediations with `&`, redirect output to a log file, and monitor it:

```bash
atx ct remediation create --ids <id1,id2> --name "Fix name" --wait --telemetry "agent=<AGENT>,executionMode=local" > /tmp/atx-remediation.log 2>&1 &
tail -f /tmp/atx-remediation.log
```

The redirect captures the command's diagnostics — the in-process CLI writes logs to STDERR, which `2>&1` folds into the log file. Only warnings and errors are logged by default; when troubleshooting, prefix the command with `ATXCT_LOG_LEVEL=debug` for verbose output.

`atx ct remediation retry --id <id>` accepts the same hidden `--wait` from CLI 3.6.0 on, with the same version check (`atx ct --version`) and the same rule against inventing the flag on an older CLI. Without it, `retry` re-dispatches the pending repositories and returns; with it, `retry` blocks until the retried remediation finishes. Use `--wait` the same way as for `create`, and treat the process as still running until it exits.

Tell the user where the log is and how to check progress.

## Listing remediations (pagination)

Depending on the CLI version, `atx ct remediation list` may return only a bounded page — don't assume a fixed response shape. After each call, if the response carries a non-empty `nextToken`, call the command again with `--next-token <token>` and repeat until no `nextToken` remains. Don't treat the first page as complete when a `nextToken` is present.

## Security Remediation

Security findings (from `atx ct analysis run --type security`) are auto-remediable with the **same** `remediation create` command as any other finding — no `--transformation-name` is needed. Security findings carry a `security-agent` fix, which routes to the AWS Security Agent code-remediation API instead of a transformation definition; the fix is generated server-side.

```bash
# 1. Find the security findings to remediate
atx ct findings list --type security --json

# 2. Create a remediation from one or more security finding IDs
#    (same command as any other remediation)
atx ct remediation create --ids <security-finding-id> --name "Fix SQL injection"

# 3. Check status -- the result is a pull/merge request or, for local sources, a code diff
atx ct remediation status --id <remediation-id>
```

### Outcomes by source provider

The result link surfaces in `remediation status` and in the remediation record's `execution_artifacts`. What you get depends on the repo's source provider:

| Source provider                         | Per-repo status | Artifact            | Meaning                                                                                                                                                                            |
| --------------------------------------- | --------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **github** / **gitlab** / **bitbucket** | `pr_open`       | `pull_request_link` | AWS Transform - continuous modernization (continuous modernization) applies the diff on the scanned commit and **opens a pull request** (a merge request on GitLab) automatically. |
| **local**                               | `diff_ready`    | `code_diff_link`    | A presigned URL to a unified diff. No PR is opened — apply the diff yourself.                                                                                                      |

- For **GitHub**, **GitLab** and **Bitbucket** sources, the diff is applied on a fresh clone pinned to the scanned commit (or the default branch if that commit is gone) and pushed with the source's token as a pull or merge request (idempotent per finding — re-running updates the same branch).
- For **local** sources there is no remote to push to, so security remediation stays **diff-only**.
- The PR step is **fail-soft**: if opening the PR fails, the usable diff is preserved (status stays `diff_ready`, `code_diff_link` set) and the reason is recorded in `execution_artifacts.pr_bridge_error`. A diff that no longer applies to the repository ends the repo `failed`, with the diff link kept; a diff with nothing left to change ends it `no_changes`.

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

### Which transformation definitions remediation accepts

Before it starts, the CLI checks the `--transformation-name` against the registry (`atx custom def list` shows each one's category):

- An AWS-managed transformation definition is accepted unless it is in the `analysis` category (`"<name>" is tagged analysis, so it can't be used for remediation.`).
- One of the account's own transformation definitions must be in the `remediation` category; otherwise: `... so it can't be used for remediation. Publish it with --category remediation to use it here.`
- An unknown name is rejected with `Transformation definition "<name>" was not found in this account.`

Relay the message; don't retry with the same name.

### Constraints

- At least one of `--ids` or `--transformation-name` is required
- `--repo` cannot be used together with `--ids` (repos are derived from findings)
- `--repo` is required when `--transformation-name` is used without `--ids`; a bare `<repo>` also needs `--source <name>`
- `-g` is only valid with `--transformation-name`
- Repos must be discovered (`atx ct discovery scan`) before remediation can target them

## Transformation Definition Discovery for Remediation

When the user asks to remediate with a custom transformation definition, or a finding has no `fix` field and no `recommendation` that names a transformation definition which actually performs the finding's fix, use transformation definition discovery to find the right transformation definition. If a finding's `recommendation` names a transformation definition AND that definition is exactly the upgrade/migration that performs the finding's fix, skip discovery and use that name directly; otherwise treat the recommendation as if it were absent and discover.

### Workflow

1. **List available transformation definitions:** Run `atx custom def list` to fetch all available transformation definitions.
2. **Match intent:** Based on the user's description of what they want to fix, match against transformation definition names and descriptions. Only AWS-managed definitions not in the `analysis` category, and the account's own definitions in the `remediation` category, can run (see "Which transformation definitions remediation accepts").
3. **Recommend and confirm:** Present the matched transformation definition(s) to the user. Wait for confirmation.
4. **Ask for additional instructions:** Ask the user if they have additional instructions (e.g. a target version or specific guidance) before running. If they do, pass them via `-g "additionalPlanContext=<instructions>"`.
5. **Execute:** Run `atx ct remediation create --transformation-name <matched-name> --repo <source>::<slug>` (with `-g` if the user provided additional instructions).

## Options

### `--local` flag (remediation create)

`atx ct remediation create` already runs the transformation on this machine (it clones each repository here and opens the pull or merge request from here) for GitHub, GitLab, Bitbucket and local sources, with or without `--local`. `--local` does not change where the transformation runs. It records the remediation as a local run (`compute_mode = 'local'`) and lowers its concurrency to the smaller of `--slots`, 8, and what this host's memory allows. `retry` reuses the recorded mode, so it doesn't need the flag again.

### `--slots` flag (remediation create)

`--slots <n>` sets how many repositories are remediated at once (default 20). Transformation-definition remediation allows at most 30 (`--slots cannot exceed 30 for transform remediation (--transformation-name) — Bedrock concurrency limit.`); security-agent remediation allows up to 128 (`--slots must be an integer between 1 and 128.`). With `--local` the host's memory caps it further.

### `--tags` flag (remediation create)

Attaches IAM resource tags to the remediation at creation time.

```bash
# Create remediation with tags (comma-separated key=value pairs)
atx ct remediation create --ids <id1,id2> --name "Fix name" --tags team=alpha,env=prod --telemetry "agent=<AGENT>,executionMode=local"
```

**Behavior:**

- `--tags key=value,key2=value2` accepts comma-separated pairs in a single flag (e.g. `--tags team=alpha,env=prod`).
- Tags are optional. If omitted, the remediation is untagged.
- If `~/.aws/atx/settings.json` defines `applyTags` (an array of tag maps), those defaults are applied automatically even without explicit `--tags`. An explicit `--tags` override merges **per key** over the settings defaults.

See the [source](continuous-modernization-source.md) skill's Tags section for the full schema, merge semantics, and error behavior.

## Prerequisites & errors

Remediation shells out to `git`, `atx`, and any provider-specific CLIs, and needs
valid AWS + provider credentials. See the
[troubleshooting](continuous-modernization-troubleshooting.md) skill for
the full actionable-error reference. Common cases:

- **`Required CLI "<tool>" was not found on PATH`** — install the named tool and
  ensure it's on PATH (the error prints the searched PATH and an install hint).
- **Connection error** — the CLI can't reach the AWS Transform backend: refresh AWS credentials and confirm `AWS_REGION` is a supported region, then retry.
- **`AccessDenied` / 403 (AWS)** — refresh AWS credentials, confirm `AWS_REGION`, then retry.
- **`401` from the provider** — the PAT is invalid/expired; have the user update the source
  with a valid token in their own terminal (`read -s TOKEN && atx ct source update --name <name> --token "$TOKEN"; unset TOKEN`;
  `repo` scope, SSO-authorized for the org if required — see the [source](continuous-modernization-source.md)
  skill's Token handling). Never ask the user to paste the token into chat.
- **Push rejected by a commit-message or branch-name rule** — record the shape the remote
  requires with `atx ct source update --name <name> --commit-message-template "<template>"`
  or `--branch-name-template "<template>"` (see the [source](continuous-modernization-source.md) skill), then `retry`.
- **A repo shows `blocked` / `failed`** — surface the per-repo error rather than
  reporting the remediation as done; retry that repo after fixing the cause.
