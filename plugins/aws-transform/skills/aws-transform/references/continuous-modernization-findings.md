---
name: findings
description: List/filter/get/update/delete findings (vulnerabilities, tech-debt issues, upgrade opportunities) by repo, source, severity (exact via --severity or threshold via --min-severity), status, analysis type, or auto-fix transform.
---

name: findings

# Findings

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` — the AI assistant driving this session (lowercase, no spaces). Use the real assistant name — e.g. kiro, claude, amazonq, copilot.
- `executionMode` — `local`

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

```bash
# List with JSON output (machine-readable). Always pass --json from agents.
atx ct findings list --json

# Filter by repo, source, severity, type, status, analysis, or fix transform
atx ct findings list \
  --repo <source>::<slug> \
  --source <name> \
  --severity <high|medium|low> \
  --min-severity <high|medium|low> \
  --type <analysis-type> \
  --status <open|dismissed|obsolete|change_ready> \
  --analysis-id <id> \
  --fix-transform <transform-name> \
  --max-items <n>

# --max-items <n> sets about how many findings one call returns (default 1000, up to 10,000; a positive whole number).
# --limit is not a page size (it sets the Agent Minutes budget, and the CLI warns); don't use it to cap results.

# Severity flags (mutually exclusive -- pass at most one):
#   --severity <level>      Exact match. e.g. --severity high returns only high findings.
#   --min-severity <level>  Threshold. e.g. --min-severity medium returns medium AND high.
# For "show me findings at least <level>" prompts, use --min-severity.

# Count findings by a dimension (server-side; far cheaper than listing them to count)
atx ct findings count --by <severity|repo|analysis-type|status> [--source <name>] [--repo <source>::<slug>] [--type <analysis-type>] [--status <open|dismissed|obsolete|change_ready>] --json
# --status defaults to open and isn't allowed with --by status, e.g. the backlog per status:
atx ct findings count --by status --json
# --type is repeatable (--type security --type custom). If the output says the counts are truncated, they are lower bounds.

# Get a single finding by ID (always prints JSON; there is no --json flag)
atx ct findings get --id <finding-id>

# Update a finding (status, notes, dismiss). --reason is required when --status is dismissed.
atx ct findings update --id <finding-id> --status <open|dismissed> --reason "dismiss reason" --notes "notes"

# Batch update multiple findings (--ids is repeatable and/or comma-separated)
atx ct findings batch-update --ids <id1,id2,...> --status <open|dismissed> --reason "reason"

# Delete a finding (must be dismissed or obsolete)
atx ct findings delete --id <finding-id>
```

## Pagination (nextToken)

`atx ct findings list` reads about `--max-items` findings per call (1000 by default, up to 10,000). When the filters match more:

- it exits with **status 2** (a partial result, not a failure) and prints a warning with the `--next-token` that continues the list;
- with `--json` it prints an object instead of an array: `{"findings": [...], "truncated": true, "total_count": N, "nextToken": "..."}` (`total_count` is how many the whole list matches; it can be absent when that can't be counted).

When the result is complete it prints a plain JSON array with no `nextToken`. So after each call, check for a non-empty `nextToken`: if present, call the same command again with the same filters plus `--next-token <token>`, and repeat until no `nextToken` remains. Concatenate the pages (the `findings` arrays) before answering. To answer a "how many" question, prefer `atx ct findings count` or `total_count` over paging everything.

```bash
# First page
atx ct findings list --status open --json
# ...response is {"findings": [...], "truncated": true, "nextToken": "<token>"} → fetch the next page
atx ct findings list --status open --json --next-token <token>
# ...repeat until the response has no nextToken
```

Never present the first page as the complete set when a `nextToken` is present — that silently drops findings and undercounts severity totals.

## Status set

`open`, `dismissed`, `obsolete`, `change_ready`. Transitions a user can drive: `open ↔ dismissed`. `obsolete` and `change_ready` are system-set states users do not transition into or out of: `obsolete` when a re-analysis no longer produces the finding, `change_ready` when a remediation has produced a change (PR/diff) awaiting review. All four are valid `--status` filter values on `findings list` and `findings count`, but `findings update`/`batch-update` still accept only `open`/`dismissed`.

## Filter shapes — pick the narrowest one

Filtering at the CLI is materially faster than pulling everything and filtering after the fact. Each shape below is backed by a server-side index. For any other combination, the service reads the most selective index among the filters you pass and applies the remaining filters to each page it reads, so a filter the index can't use makes the call read more pages and get slow on accounts with thousands of findings. With no filters it reads the whole account.

| User intent                       | Filter shape                                                                                                    |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Findings from one analysis run    | `--analysis-id <id>` (alone or combined with anything)                                                          |
| Live findings on one repo         | `--repo <slug> --status <s>`                                                                                    |
| Account-wide triage               | `--status <s>` (optionally `+ --severity <level>` for one level, or `+ --min-severity <level>` for a threshold) |
| One repo, one analysis type       | `--repo <slug> --type <t>` (single type only)                                                                   |
| Everything under one source       | `--source <name>` (alone)                                                                                       |
| Auto-fixable by a known transform | `--fix-transform <name>` (alone or combined)                                                                    |

### Anti-patterns

- Calling `atx ct findings list --json` with no filters and post-filtering in the model. Always filter at the CLI.
- Per-repo loops when a single `--source` filter would cover the whole batch.
- Omitting `--status open` when the user only cares about live findings — `dismissed` and `obsolete` pile up over time.
- Passing `--type` and `--analysis-id` together when `--analysis-id` alone already pins the result set to one run.
- "Auto-fixable" without a transform name → narrow with `--type rapid-techdebt-analysis` first. `rapid-techdebt-analysis` findings carry an `atx-transform` fix (a transformation definition); `security` findings carry a `security-agent` fix (see the [remediation](continuous-modernization-remediation.md) skill). Findings without a `fix` field may still be remediable — see the [remediation](continuous-modernization-remediation.md) skill's decision tree.
- `--type` alone or `--type --severity`/`--type --min-severity` (no status, no repo) → add `--status open` to anchor on the live-triage shape.
- Passing both `--severity` and `--min-severity` in the same call → the CLI rejects this. Pick one.
- Treating the first page of `atx ct findings list` as the complete set when the response carries a non-empty `nextToken`. Page through with `--next-token <token>` until no `nextToken` remains — otherwise you silently drop findings.

### Multi-repo, multi-type questions

`--repo` accepts one slug. For multi-repo questions, prefer `--source` (one call covers every repo under that source). For multi-type questions, call once per type and merge — combining `--repo` with multiple types is not supported by a single index path.

## Remediating findings

Auto-remediable findings can be fixed by passing their IDs to `remediation create`:

```bash
atx ct findings list --type security --json   # find auto-remediable security findings
atx ct remediation create --ids <finding-id1,finding-id2> --name "Fix name" --telemetry "agent=<AGENT>,executionMode=local"
```

- **Security findings** (`--type security`) route to the AWS Security Agent and produce a code diff; for GitHub, GitLab and Bitbucket sources a pull or merge request is opened from it automatically (local sources stay diff-only).
- **Tech-debt / upgrade findings** route to an AWS Transform transformation definition, which opens a pull request, merge request or code review.

See the [remediation](continuous-modernization-remediation.md) skill for outcomes by source provider and for handling findings without a `fix` field.

## Prerequisites & errors

Before listing findings, AWS credentials must be valid and the CLI must be able
to reach the AWS Transform backend (on a connection error, refresh credentials and confirm `AWS_REGION`). See the [troubleshooting](continuous-modernization-troubleshooting.md)
skill for the full actionable-error reference.

**An empty findings list is not automatically "clean."** Before reporting "no
findings":

- If the read errored (auth/connection), surface the error — do not report `0`.
- Confirm `AWS_REGION` matches where the analysis ran (findings are region-scoped).
- Confirm an analysis has actually completed (`atx ct analysis list`); no completed
  analysis means there is nothing to list yet, not a clean bill of health.
- Check each repository's status in `atx ct analysis get --id <id> --json`. A repository whose
  results couldn't be saved (report missing, unreadable or not uploaded, or the repository not
  found in the source), or whose transformation the agent reported as failed, shows as **Failed**
  with the reason and next step — relay that, don't
  count it as a repository with no findings.
- On `AccessDenied` / 403: credentials likely expired — refresh them and retry.
