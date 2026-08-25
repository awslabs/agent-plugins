---
name: analysis
description: Run/start/restart/cancel/delete analyses (tech-debt-quick, tech-debt-comprehensive, security, agentic-readiness, modernization-readiness, custom). Detects vulnerabilities, outdated dependencies, migration opportunities, modernization candidates. Custom type runs any TD.
---

name: analysis

# Analysis

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` -- the AI assistant driving this session (lowercase, no spaces). Use the real assistant name -- e.g. kiro, claude, amazonq, copilot.
- `executionMode` -- `local`

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

## Choose Compute (Before Running)

**Explicit intent overrides repo count.** If the user's prompt contains words like "remotely", "on AWS", "on EC2", "on Fargate", "in the cloud", or "remote execution", route to the corresponding execution skill regardless of how many repos are in scope:

- Mentions "no infrastructure" / "don't want to set up / manage / provision anything" / "no EC2" / "no Batch stack" / "managed" / "just run it for me on AWS" → follow [continuous-modernization-aws-managed-execution](continuous-modernization-aws-managed-execution.md). This is the **no-infrastructure** option (AWS-managed fleet); do NOT offer EC2/Batch or a provisioning step for these requests. **Batch/Fargate is NOT the no-infrastructure option** — it still deploys a customer-owned stack.
- Mentions EC2 / "on an instance" → follow [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md)
- Mentions Batch / Fargate / "serverless" → follow [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md)
- Mentions "remotely" / "on AWS" / "in the cloud" (no specific compute) → ask which: AWS-managed (no infrastructure), EC2, or Batch (Fargate)

**Otherwise**, for analyses with more than 9 repos, ask the customer:

> "Do you want to run this locally, on the AWS-managed fleet (no infrastructure to set up), set up an EC2 instance in your AWS account, or submit to AWS Batch (Fargate)?"

- **Local** -- proceed with the commands below
- **AWS-managed** -- follow [continuous-modernization-aws-managed-execution](continuous-modernization-aws-managed-execution.md) (no customer infrastructure)
- **EC2** -- follow [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md)
- **Batch** -- follow [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md)

## Repository limit per request (max 100)

A single `atx ct analysis run` can be associated with at most **100 repositories**. Before starting an analysis that targets many repos (for example a whole source), check how many repositories are in scope — `atx ct source list` or `atx ct repository list --source <name>` report the per-source count. (Bare `atx ct status` shows workspace-wide totals across all sources, so prefer a scoped form when the analysis targets a single source.)

If the scope exceeds 100 repositories, split it into multiple runs, each targeting at most 100 repos (pass the repos in batches via `--repo <source>::<slug>`), and tell the user you are breaking the work up because of the 100-repo-per-request limit. Never issue a single run associated with more than 100 repositories — it will be rejected. Example: 300 repos → three runs (100 + 100 + 100); 600 repos → six runs (100 each).

## Commands

```bash
# Run analysis. Pass --wait so the command blocks until the run finishes (preferred — see "Running long analyses" below).
atx ct analysis run --type <tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|custom> --source <name> [--repo <source>::<slug>] --wait --telemetry "agent=<AGENT>,executionMode=local"

# --wait is only in newer CLI versions. If it isn't supported, run the same command without --wait.
atx ct analysis run --type <tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|custom> --source <name> [--repo <source>::<slug>] --telemetry "agent=<AGENT>,executionMode=local"

# Run custom analysis with a specific transformation definition
atx ct analysis run --type custom --transformation-name <TD-name> --source <name> --repo <source>::<slug> --wait --telemetry "agent=<AGENT>,executionMode=local"

# Run custom analysis with configuration (file://, JSON, or key=value)
atx ct analysis run --type custom --transformation-name <TD-name> -g "additionalPlanContext=Focus on auth module" --source <name> --repo <source>::<slug> --wait --telemetry "agent=<AGENT>,executionMode=local"

# Get details (JSON for parsing)
atx ct analysis get --id <id> --json

# List all
atx ct analysis list --json

# Filter on the server-side index (fast). Combine as needed.
atx ct analysis list --status <pending|running|complete|cancelled|failed> --json
atx ct analysis list --type <tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|custom> --json
atx ct analysis list --status complete --type security --json

# Category is filtered client-side (does not reduce the fetch); only narrows what's printed.
atx ct analysis list --category "Tech Debt" --json

# Cancel or delete
atx ct analysis cancel --id <id>
atx ct analysis delete --id <id> [--cascade-findings]
```

## Local vs remote execution (command differences)

The commands above (`atx ct analysis run`) execute **locally** on this machine. To run on AWS instead, use the **`atx ct remote analysis`** verb with a `--mode`. There are three remote modes; the command surface differs from local in a few important ways:

|                         | Local                            | AWS-managed (`--mode aws-managed`)          | EC2 / Batch (`--mode ec2\|batch`)                    |
| ----------------------- | -------------------------------- | ------------------------------------------- | ---------------------------------------------------- |
| Verb                    | `atx ct analysis run`            | `atx ct remote analysis`                    | `atx ct remote analysis`                             |
| Infrastructure          | none (this machine)              | **none** — the AWS-managed fleet runs it    | customer-owned stack (must `remote provision` first) |
| Source/repo flags       | `--source` / `--repo` (singular) | `--sources` / `--repos` (plural)            | `--sources` / `--repos` (plural)                     |
| Region                  | n/a                              | `--region` (optional; any supported region) | `--region` + `--stack-name`                          |
| Create semantics        | runs in-process                  | create **is** the submission (no dispatch)  | submits jobs to the stack                            |
| Poll with               | `atx ct analysis get --id <id>`  | `atx ct analysis get --id <id>`             | `atx ct remote status --group\|--batch ...`          |
| executionMode telemetry | `local`                          | `aws-managed`                               | `ec2` / `fargate`                                    |

AWS-managed is the closest remote analog to a local run — same `analysis get` polling, no infrastructure — just running on AWS compute in the region you choose:

```bash
# AWS-managed remote analysis (no infrastructure to provision)
atx ct remote analysis \
  --type tech-debt-comprehensive \
  --sources <name> \
  --mode aws-managed \
  --region <region> \
  --telemetry "agent=<AGENT>,executionMode=aws-managed"
# → prints an analysis id; poll with: atx ct analysis get --id <id> --json
```

EC2/Batch, by contrast, run on a stack the customer deploys and are polled with `remote status`:

```bash
# EC2/Batch remote analysis (customer-owned stack; provision first)
atx ct remote analysis --type tech-debt-comprehensive --sources <name> \
  --mode batch --stack-name <stack> --telemetry "agent=<AGENT>,executionMode=fargate"
```

Full details, flag-rejection rules, and output shapes per mode:
[aws-managed](continuous-modernization-aws-managed-execution.md) · [EC2](continuous-modernization-ec2-execution.md) · [Batch](continuous-modernization-batch-execution.md). For choosing a mode, see "Choose Compute" above.

## Running long analyses (--wait, background, logs)

`atx ct analysis run` returns immediately by default with an analysis ID. With `--wait` it blocks until the run completes — and a comprehensive or multi-repo run can take a long time. Prefer `--wait` so the run blocks to completion and you can act on the result in the same step.

**`--wait` is version-gated.** It exists only in newer CLI versions. Before relying on it, confirm the installed CLI supports it — check `atx ct analysis run --help` (or `atx ct --version`). If `--wait` isn't listed, run the command without it; do not invent the flag. If a run fails with an unknown-option error for `--wait`, re-run without it.

**Run long jobs in the background and monitor a log.** A blocking run ties up the session, so start long-running analyses in the background with `&`, redirect output to a log file, and monitor the log:

```bash
atx ct analysis run --type tech-debt-comprehensive --source <name> --wait --telemetry "agent=<AGENT>,executionMode=local" > /tmp/atx-analysis.log 2>&1 &
tail -f /tmp/atx-analysis.log
```

The redirect captures the command's diagnostics — the in-process CLI writes logs to STDERR, which `2>&1` folds into the log file. Only warnings and errors are logged by default; when troubleshooting, prefix the command with `ATXCT_LOG_LEVEL=debug` for verbose output (e.g. `ATXCT_LOG_LEVEL=debug atx ct analysis run ... > /tmp/atx-analysis.log 2>&1 &`).

This applies to comprehensive scans, large multi-repo runs, and any analysis the user expects to take a while. Tell the user where the log is and how to check progress.

## Custom Analysis

The `custom` type runs any transformation definition (TD) against a repository. Unlike other analysis types, custom analysis does not generate findings -- it executes the TD directly.

**Required flags for `--type custom`:**

- `--transformation-name <name>` -- Name of the TD in the registry

**Optional flags:**

- `-g, --configuration <config>` -- Configuration passed directly to the TD. Accepts:
  - Key-value: `"additionalPlanContext=Upgrade to Java 17,buildCommand=mvn clean test"`
  - JSON: `'{"additionalPlanContext":"Upgrade to Java 17"}'`
  - File path: `"file:///path/to/config.json"`

**Constraints:**

- `--transformation-name` is only valid with `--type custom`
- `-g` is only valid with `--type custom`
- Custom analysis will not generate findings

## TD Discovery and Recommendation

When the user asks to run a custom analysis or mentions a capability not covered by built-in types (e.g., "generate sequence diagrams", "check code quality", "run compliance scan"), use TD discovery to find the right transformation:

### Workflow

1. **List available TDs:** Run `atx custom def list` to fetch all available transformation definitions (both AWS-managed and customer-owned custom TDs).
2. **Match intent to TD:** Based on the user's description, match their intent against TD names and descriptions.
3. **Recommend and confirm:** Present the matched TD(s) to the user with a brief description. Wait for confirmation before executing.
4. **Execute:** Run `atx ct analysis run --type custom --transformation-name <matched-TD> --source <s> --repo <r> --wait`

### When to use TD discovery vs built-in types

- If the user's request clearly maps to a built-in type (`tech-debt-quick`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`), use that type directly -- do NOT use custom.
- If the request mentions a specific capability not covered by built-in types, or asks about custom/customer-owned TDs, use TD discovery.
- If the user explicitly names a TD, skip discovery and run it directly with `--type custom --transformation-name <TD>`.

## Repo slug rules

When passing `--repo` to `analysis run`:

- **Qualified slug** (`<source>::<repo>`): always works, doesn't need `--source`.
- **Bare repo name** (`<repo>`): only works if `--source <name>` is also supplied.
- **Bare `--repo` without `--source`**: hard error (`Unqualified repo slug(s)`). Don't generate this combination.
- **Multiple repos**: must all share the same source. A run that mixes repos from different sources is rejected with `repos span multiple sources`.

Prefer qualified slugs so the source is unambiguous.

## Status Values

When polling with `atx ct analysis get --id <id> --json`, the `status` field is **lowercase**:

- `running` -- in progress
- `complete` -- finished (check findings)
- `cancelled` -- user cancelled
- `failed` -- error occurred

**Note:** It's `complete`, NOT `COMPLETED` or `completed`.

## After Analysis Completes

Once an analysis finishes, retrieve its findings by analysis ID and summarize for the user:

```bash
# Get findings produced by a specific analysis
atx ct findings list --analysis-id <analysis-id> --json
```

## When an analysis returns 0 findings

A `0 findings` result does NOT automatically mean the repo is clean. Each analysis type has its own scope. Do NOT report "clean" without running the right follow-up.

| Type                      | What 0 findings means                                                                                               | What to do next                                                                                                                                                   |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tech-debt-quick`         | Metadata files didn't expose any stale versions. **Inconclusive** -- quick scan only inspects manifests.            | Tell the user the result is inconclusive (metadata-only). Offer to run `tech-debt-comprehensive` for a code-level analysis.                                       |
| `tech-debt-comprehensive` | Bedrock did not surface tech-debt issues. Repo is likely well-maintained, but other dimensions weren't checked.     | Offer `security` for CVEs, `agentic-readiness` for AI-readiness, and `modernization-readiness` for modernization opportunities. Mention these are separate scans. |
| `security`                | Security Agent didn't surface CVEs or vulnerable patterns.                                                          | Verify the Security Agent is healthy (`atx ct setup security-agent --status`). If healthy, offer `tech-debt-comprehensive` for non-security issues.               |
| `agentic-readiness`       | Repo did not show AI-readiness gaps at the framework level.                                                         | Offer `modernization-readiness` for cloud/infrastructure modernization or `tech-debt-comprehensive` for general code health.                                      |
| `modernization-readiness` | Repo did not show modernization opportunities (infrastructure, application, data, security, operations dimensions). | Offer `agentic-readiness` for AI-integration scope or `tech-debt-comprehensive` for general code health.                                                          |

### Sanity check before reporting "clean"

If an analysis returns 0 findings on a repo that's obviously stale (Java 8, Node 14, Python 2, .NET Framework, an old `pom.xml` from 4+ years ago), do NOT report the repo as clean. Treat it as a signal that the analysis type was wrong for the question and offer a follow-up.

## Listing analyses

`atx ct analysis list` exposes these filters. Pick the narrowest combination the question allows.

| Filter          | Where it runs                           | Allowed values                                                                                                        |
| --------------- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `--status`      | server-side (GSI-backed, fast)          | `pending`, `running`, `complete`, `cancelled`, `failed`                                                               |
| `--type`        | server-side (GSI-backed, fast)          | `tech-debt-quick`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `custom`    |
| `--category`    | client-side (does not reduce the fetch) | `"Tech Debt"`, `"Security"`, `"Agentic Readiness"`                                                                    |
| `--schedule-id` | server-side                             | a schedule's `sched-` analysisId (from `atx ct schedule list`) — lists that schedule's fired child runs, newest first |

**Recommended shapes:**

- "What completed analyses do we have?" → `atx ct analysis list --status complete --json`
- "What security analyses ran?" → `atx ct analysis list --type security --json`
- "Find completed security runs" → `atx ct analysis list --status complete --type security --json`
- "What has my nightly schedule run so far?" → `atx ct analysis list --schedule-id <sched-id> --json` (the fired child runs of that schedule; get `<sched-id>` from `atx ct schedule list`)
- One specific run → `atx ct analysis get --id <id> --json` (point lookup; cheaper than list).

`--category` is a client-side grouping; e.g. `"Tech Debt"` matches both `tech-debt-quick` and `tech-debt-comprehensive`. Use it when the user wants both subtypes together.

`--schedule-id` is how you inspect a schedule's history: each fire creates one child analysis, and this lists them newest-first. It **cannot** be combined with `--status` or `--type` (the CLI returns `INVALID_INPUT`). To read one fire's findings, take a child's id and run `atx ct findings list --analysis-id <id> --json`.

`--status` and `--type` accept only the canonical values above. Off-canonical input (e.g. `--status completed`, `--type tech-debt`) returns an `INVALID_INPUT` error.

### Pagination (nextToken)

Depending on the CLI version, `atx ct analysis list` may return only a bounded page rather than every result — don't assume a fixed response shape. After each call, check whether the response carries a `nextToken`; if it's present and non-empty, call the command again with `--next-token <token>` and repeat until no `nextToken` remains. Never treat the first page as the complete set when a `nextToken` is present, or you'll silently miss analyses.

## Tags (resource tagging)

The `--tags` flag attaches IAM resource tags to an analysis at creation time, and propagates those tags through to any findings the analysis produces.

```bash
# Run analysis with tags (comma-separated key=value pairs)
atx ct analysis run --type tech-debt-comprehensive --source <name> --tags team=alpha,env=prod --wait --telemetry "agent=<AGENT>,executionMode=local"
```

**Behavior:**

- `--tags key=value,key2=value2` accepts comma-separated pairs in a single flag (e.g. `--tags team=alpha,env=prod`).
- Tags are optional. If omitted, the analysis and its findings are untagged.
- Tags are injected into the `--atxct-configuration` payload passed to the transformation agent. When the agent calls `report_finding`, the tags are forwarded to `BatchCreateFindings` — so findings inherit the analysis's tags automatically.
- If `~/.aws/atx/settings.json` defines `applyTags` (an array of tag maps), those defaults are applied automatically even without explicit `--tags`. An explicit `--tags` override merges **per key** over the settings defaults.

See the [source](continuous-modernization-source.md) skill's Tags section for the full schema, merge semantics, and error behavior.

## Prerequisites & errors

AWS credentials must be valid and the CLI must be able to reach the AWS Transform
backend before starting or reading an analysis. See the [troubleshooting](continuous-modernization-troubleshooting.md)
skill for the full actionable-error reference. Common cases:

- **`command not found: atx`** — the CLI isn't installed/on PATH. Install it (see
  the `setup` skill) and verify with `atx --version`.
- **Connection error** — the CLI can't reach the AWS Transform backend: refresh AWS credentials and confirm `AWS_REGION` is a supported region, then retry.
- **`AccessDenied` / 403** — refresh AWS credentials,
  confirm the role's permissions and `AWS_REGION`, then retry.
- **`required option '--type <type>' not specified`** — `--type` takes a value; run
  `atx ct analysis run --help` for valid values (e.g. `--type tech-debt-comprehensive`).
- **Security analysis reports COMPLETED with 0 findings after an error line** — this
  is _not_ a clean result; the findings fetch failed. Retry; if it persists, verify
  credentials/region and Security Agent access (`atx ct setup security-agent`).
- **Analysis stuck / no progress** — do not report success; check `atx ct analysis list`
  and surface the actual status.
