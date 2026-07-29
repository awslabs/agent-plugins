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
  --status <open|dismissed|obsolete> \
  --analysis-id <id> \
  --fix-transform <transform-name>

# Severity flags (mutually exclusive -- pass at most one):
#   --severity <level>      Exact match. e.g. --severity high returns only high findings.
#   --min-severity <level>  Threshold. e.g. --min-severity medium returns medium AND high.
# For "show me findings at least <level>" prompts, use --min-severity.

# Get a single finding by ID
atx ct findings get --id <finding-id>

# Update a finding (status, notes, dismiss)
atx ct findings update --id <finding-id> --status <open|dismissed> --reason "dismiss reason" --notes "notes"

# Batch update multiple findings
atx ct findings batch-update --ids <id1,id2,...> --status <open|dismissed> --reason "reason"

# Delete a finding (must be dismissed or obsolete)
atx ct findings delete --id <finding-id>
```

## Pagination (nextToken)

Depending on the CLI version, `atx ct findings list` may return only a bounded page rather than every finding — so don't assume a fixed response shape. After each call, check whether the response carries a `nextToken`. If it's present and non-empty, the results are truncated: call the same command again with the same filters plus `--next-token <token>`, and repeat until the response has no `nextToken`. Concatenate the pages before answering. If there's no `nextToken`, you already have the full set.

```bash
# First page
atx ct findings list --status open --json
# ...response includes "nextToken": "<token>" → fetch the next page
atx ct findings list --status open --json --next-token <token>
# ...repeat until the response has no nextToken
```

Never present the first page as the complete set when a `nextToken` is present — that silently drops findings and undercounts severity totals.

## Status set

`open`, `dismissed`, `obsolete`. Transitions a user can drive: `open ↔ dismissed`. `obsolete` is a terminal state set by the system when a re-analysis no longer produces the finding — users do not transition into or out of it.

## Filter shapes — pick the narrowest one

Filtering at the CLI is materially faster than pulling everything and filtering after the fact. Each shape below is backed by a server-side index. Combinations that don't match one of these degrade to a full account scan with in-memory filtering and get slow on accounts with thousands of findings.

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
- "Auto-fixable" without a transform name → narrow with `--type tech-debt-quick` first. `tech-debt-quick` findings carry an ATX-transform fix; `security` findings carry a security-agent fix (see the [remediation](continuous-modernization-remediation.md) skill). Findings without a `fix` field may still be remediable — see the [remediation](continuous-modernization-remediation.md) skill's decision tree.
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

- **Security findings** (`--type security`) route to the AWS Security Agent and produce a code diff or, for GitHub sources, an auto-opened pull request.
- **Tech-debt / upgrade findings** route to an ATX transform (PR/CR).

See the [remediation](continuous-modernization-remediation.md) skill for outcomes by source provider and for handling findings without a `fix` field.
