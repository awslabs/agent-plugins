---
name: analysis
description: Run/start/restart/cancel/delete analyses (rapid-techdebt-analysis, tech-debt-comprehensive, security, agentic-readiness, modernization-readiness, graviton-readiness, custom). Detects vulnerabilities, outdated dependencies, migration opportunities, modernization candidates. Custom type runs one of your own analysis transformation definitions.
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

## Repositories per run

`atx ct analysis run` has no fixed repository cap of its own. The AWS Transform service refuses a run whose repository list is longer than the limit for the account (the service allows up to 5,000), and a request body over about 950 KB is refused before it is sent. In both cases nothing is created. The messages are `AWS Transform refused this analysis: <N> repositories is more than this account may put in ONE analysis (...). Split the submission (for example with --repo), ...` and `This analysis would send a <N>-byte ... request, over the 950000-byte budget ... Split the submission (for example with --repo), or use shorter source/repository names.`

Before starting an analysis that targets many repos (for example a whole source), check how many repositories are in scope: `atx ct source list` or `atx ct repository list --source <name>` report the per-source count. (Bare `atx ct status` shows workspace-wide totals across all sources, so prefer a scoped form when the analysis targets a single source.) If a run is refused for its size, split the repositories into batches and start one run per batch with `--repo <source>::<slug>[,<source>::<slug>...]`, sized under the limit the message names, and tell the user you are splitting the work. Don't guess a batch size and retry in a loop.

## Commands

```bash
# Run analysis. Pass --wait so the command blocks until the run finishes (preferred — see "Running long analyses" below).
atx ct analysis run --type <rapid-techdebt-analysis|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|graviton-readiness|aws-health-readiness|custom> --source <name> [--repo <source>::<slug>] --wait --telemetry "agent=<AGENT>,executionMode=local"

# --wait needs CLI 3.2.0 or later (check `atx ct --version`). On an older CLI, run the same command without --wait.
atx ct analysis run --type <rapid-techdebt-analysis|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|graviton-readiness|aws-health-readiness|custom> --source <name> [--repo <source>::<slug>] --telemetry "agent=<AGENT>,executionMode=local"

# Run custom analysis with a specific transformation definition
atx ct analysis run --type custom --transformation-name <transformation-name> --source <name> --repo <source>::<slug> --wait --telemetry "agent=<AGENT>,executionMode=local"

# Run custom analysis with configuration (file://, JSON, or key=value)
atx ct analysis run --type custom --transformation-name <transformation-name> -g "additionalPlanContext=Focus on auth module" --source <name> --repo <source>::<slug> --wait --telemetry "agent=<AGENT>,executionMode=local"

# Several repos in one run: --repo (or its alias --repos) is repeatable and/or comma-separated; bare names need --source
atx ct analysis run --type security --repo svc-a,svc-b --source <name> --wait --telemetry "agent=<AGENT>,executionMode=local"

# Steer the readiness assessments (see "Readiness steering flags")
atx ct analysis run --type agentic-readiness --source <name> --agent-scope <read-only|write-enabled> --context "<goals>" --wait --telemetry "agent=<AGENT>,executionMode=local"
atx ct analysis run --type modernization-readiness --source <name> --prefer eks,aurora --avoid self-managed-kafka --context "<goals>" --wait --telemetry "agent=<AGENT>,executionMode=local"

# Optional on any run: --display-name labels the run in `analysis get`/`analysis list`;
# --json prints only { analysisId, status, total, findingCount } on stdout (for scripting)
atx ct analysis run --type rapid-techdebt-analysis --repo <source>::<slug> --display-name "<label>" --json --wait --telemetry "agent=<AGENT>,executionMode=local"

# Get details (JSON for parsing)
atx ct analysis get --id <id> --json

# List all
atx ct analysis list --json

# Filter on the server-side index (fast). Combine as needed.
atx ct analysis list --status <pending|running|complete|cancelled|failed> --json
atx ct analysis list --type <rapid-techdebt-analysis|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|graviton-readiness|aws-health-readiness|custom> --json
atx ct analysis list --status complete --type security --json

# Category is filtered client-side (does not reduce the fetch); only narrows what's printed.
atx ct analysis list --category "Tech Debt" --json

# Cancel or delete
atx ct analysis cancel --id <id>
atx ct analysis delete --id <id> [--cascade-findings]   # findings are kept unless --cascade-findings

# Stored reports of a remote run (one per-repo bundle, e.g. <repo>/artifacts.zip; partial while the run is going)
atx ct analysis list-artifacts --id <id> [--repo <source>::<slug>] [--max-results <1-100>] [--next-token <token>] --json
atx ct analysis get-artifact --id <id> --artifact-id <artifact-id> [--output <file>] [--force]   # --force overwrites an existing file
```

`atx ct analysis get` and `atx ct analysis delete --cascade-findings` exit with status 2 on a partial result: `get` when it could not count the findings (`Findings: unavailable`), `delete` when some findings could not be deleted (it names the `findings list --analysis-id` command to find them). Relay the warning; don't report a clean result.

## Local vs remote execution (command differences)

The commands above (`atx ct analysis run`) execute **locally** on this machine. To run on AWS instead, use the **`atx ct remote analysis`** verb with a `--mode`. There are three remote modes; the command surface differs from local in a few important ways:

|                         | Local                                   | AWS-managed (`--mode aws-managed`)          | EC2 / Batch (`--mode ec2\|batch`)                    |
| ----------------------- | --------------------------------------- | ------------------------------------------- | ---------------------------------------------------- |
| Verb                    | `atx ct analysis run`                   | `atx ct remote analysis`                    | `atx ct remote analysis`                             |
| Infrastructure          | none (this machine)                     | **none** — the AWS-managed fleet runs it    | customer-owned stack (must `remote provision` first) |
| Source/repo flags       | `--source` / `--repo` (alias `--repos`) | `--sources` / `--repos` (plural)            | `--sources` / `--repos` (plural)                     |
| Region                  | n/a                                     | `--region` (optional; any supported region) | `--region` + `--stack-name`                          |
| Create semantics        | runs in-process                         | create **is** the submission (no dispatch)  | submits jobs to the stack                            |
| Poll with               | `atx ct analysis get --id <id>`         | `atx ct analysis get --id <id>`             | `atx ct remote status --group\|--batch ...`          |
| executionMode telemetry | `local`                                 | `aws-managed`                               | `ec2` / `fargate`                                    |

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

**`--wait` is version-gated.** `atx ct analysis run` accepts it from CLI 3.2.0 on. `--help` doesn't list it (the option is hidden), so check the version instead: run `atx ct --version`, and pass `--wait` only on 3.2.0 or later. On an older CLI, run the command without it, and leave `--wait` out of every command you show the user too, including ones for after an upgrade; do not invent the flag. If a run fails with an unknown-option error for `--wait`, re-run without it.

**Run long jobs in the background and monitor a log.** A blocking run ties up the session, so start long-running analyses in the background with `&`, redirect output to a log file, and monitor the log:

```bash
atx ct analysis run --type tech-debt-comprehensive --source <name> --wait --telemetry "agent=<AGENT>,executionMode=local" > /tmp/atx-analysis.log 2>&1 &
tail -f /tmp/atx-analysis.log
```

The redirect captures the command's diagnostics — the in-process CLI writes logs to STDERR, which `2>&1` folds into the log file. Only warnings and errors are logged by default; when troubleshooting, prefix the command with `ATXCT_LOG_LEVEL=debug` for verbose output (e.g. `ATXCT_LOG_LEVEL=debug atx ct analysis run ... > /tmp/atx-analysis.log 2>&1 &`).

This applies to comprehensive scans, large multi-repo runs, and any analysis the user expects to take a while. Tell the user where the log is and how to check progress.

## Custom Analysis

The `custom` type runs a transformation definition against a repository **in analysis mode**, which is set to only report findings (what the transformation definition would change) and to write only the report or documentation files the transformation definition asks for. The CLI prints a note saying so (`Note: custom analysis runs your transformation definition in analysis mode, which is set to only report findings.`) — that note is expected, not an error. To actually apply a transformation definition's changes, use [remediation](continuous-modernization-remediation.md) instead.

**Where the reports are:** a local custom analysis keeps the report files the transformation definition writes under `~/.atxct/shared/analyses/<analysis-id>/artifacts/<repository>/`, and `atx ct analysis get --id <id> --json` lists them under `report_paths`. Remote EC2 and Batch runs upload them as the repository's `artifacts.zip`; list and download them with `atx ct analysis list-artifacts` and `atx ct analysis get-artifact` (see Get Results in [Batch](continuous-modernization-batch-execution.md) or [EC2](continuous-modernization-ec2-execution.md)).

**Required flags for `--type custom`:**

- `--transformation-name <name>` -- Name of the transformation definition in the registry. It must be one of the account's **own** transformation definitions in the `analysis` category (`atx custom def list` shows the category). The CLI checks this before starting and rejects an AWS-managed transformation definition (`"<name>" is an AWS-managed transformation definition. A custom analysis runs one of your own transformation definitions tagged analysis.`), one with another or no category (`... so it can't be used for a custom analysis. Publish it with --category analysis to use it here.`), and an unknown name (`... was not found in this account.`).

**Optional flags:**

- `-g, --configuration <config>` -- Configuration passed directly to the transformation definition. Accepts:
  - Key-value: `"additionalPlanContext=Upgrade to Java 17,buildCommand=mvn clean test"`
  - JSON: `'{"additionalPlanContext":"Upgrade to Java 17"}'`
  - File path: `"file:///path/to/config.json"`

  The analysis adds its own instructions to `additionalPlanContext`, so a context that leaves no room for them is rejected before anything starts: `--configuration is too large: its additionalPlanContext is N characters. Shorten it by M characters.` Shorten it by that much and re-run.

**Constraints:**

- `--transformation-name` is only valid with `--type custom` (and required with it)
- `-g` is only valid with `--type custom`
- Custom analysis reports findings; it never applies the changes itself

## Graviton readiness

`--type graviton-readiness` checks **Java** repositories for AWS Graviton (ARM64) compatibility — native libraries, dependencies, architecture-specific code, Dockerfiles, build configuration, and JVM flags — using the AWS-managed `AWS/graviton-readiness-assessment` transformation. Reports are saved under `graviton-analysis/`. Each ARM64 finding recommends `AWS/java-x86-to-graviton` as its fix, so `atx ct remediation create --ids <finding-ids>` can resolve it.

```bash
# Add --wait only if the installed CLI supports it (see "Running long analyses")
atx ct analysis run --type graviton-readiness --source <name> [--repo <source>::<slug>] --telemetry "agent=<AGENT>,executionMode=local"
```

Use it when the user asks about moving Java workloads to Graviton or ARM64. It also runs remotely (`atx ct remote analysis --type graviton-readiness` on EC2, Batch or AWS-managed) and on a schedule (`atx ct schedule create --type graviton-readiness`).

## AWS Health lifecycle

`--type aws-health-readiness` finds the AWS Lambda runtime and Amazon EKS Kubernetes versions a repository sets that are deprecated or reach a lifecycle date within 180 days, using the AWS-managed `AWS/aws-health-lifecycle-analysis` transformation. Its report is saved under `aws-health-lifecycle-analysis/REPORT.md`. Each finding names the AWS-managed transformation that upgrades it (for example `AWS/python-version-upgrade`, `AWS/lambda-nodejs-runtime-upgrade`, `AWS/eks-kubernetes-version-upgrade`), so `atx ct remediation create --ids <finding-ids>` can resolve it.

```bash
# Add --wait only if the installed CLI supports it (see "Running long analyses")
atx ct analysis run --type aws-health-readiness --source <name> [--repo <source>::<slug>] --telemetry "agent=<AGENT>,executionMode=local"
```

Use it when the user asks about AWS Health planned lifecycle events, Lambda runtime deprecation, or EKS end of support. It also runs remotely (`atx ct remote analysis --type aws-health-readiness` on EC2, Batch or AWS-managed) and on a schedule (`atx ct schedule create --type aws-health-readiness`).

When the account can read AWS Health, each finding also names the affected resources. That needs a Business or Enterprise Support plan and `health:DescribeEvents`, `health:DescribeEventDetails` and `health:DescribeAffectedEntities` for whoever runs it (the user's credentials locally, the stack's role remotely). Without them the analysis still completes from the code, and the report says "AWS Health was not used". A local run also needs AWS CLI v2 on PATH. When a prerequisite is missing, the repo fails with `AWS Health could not be read. Missing: <items>.`; report that failure and the missing items, never "no AWS Health issues".

## Readiness steering flags

`agentic-readiness` and `modernization-readiness` take optional steering on `atx ct analysis run`; pass them when the user states goals or technology preferences:

- `--context <text>` -- free-form goals for the assessment (both types).
- `--agent-scope <read-only|write-enabled>` -- `agentic-readiness` only. If omitted, the assessment infers the scope from each repository; don't default it to `read-only`.
- `--prefer <list>` / `--avoid <list>` -- comma-separated technologies to recommend or steer away from (e.g. `--prefer eks,aurora,bedrock --avoid self-managed-kafka`); `modernization-readiness` only.

Using one with another type is rejected (e.g. `--agent-scope is only valid with --type agentic-readiness.`, `--prefer and --avoid are only valid with --type modernization-readiness.`).

## Transformation definition discovery and recommendation

When the user asks to run a custom analysis or mentions a capability not covered by built-in types (e.g., "generate sequence diagrams", "check code quality", "run compliance scan"), use transformation definition discovery to find the right transformation:

### Workflow

1. **List available transformation definitions:** Run `atx custom def list` to fetch the available transformation definitions and their categories.
2. **Match intent:** Based on the user's description, match their intent against the account's own transformation definitions in the `analysis` category (names and descriptions). AWS-managed transformation definitions can't run as a custom analysis; if only an AWS-managed one fits, use the matching built-in type or offer [remediation](continuous-modernization-remediation.md) instead.
3. **Recommend and confirm:** Present the matched transformation definition(s) to the user with a brief description. Wait for confirmation before executing.
4. **Execute:** Run `atx ct analysis run --type custom --transformation-name <matched-name> --source <s> --repo <r> --wait`

### When to use discovery vs built-in types

- If the user's request clearly maps to a built-in type (`rapid-techdebt-analysis`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `graviton-readiness`, `aws-health-readiness`), use that type directly -- do NOT use custom.
- If the request mentions a specific capability not covered by built-in types, or asks about the account's own transformation definitions, use discovery.
- If the user explicitly names a transformation definition, skip discovery and run it directly with `--type custom --transformation-name <name>`. If the CLI rejects its category, relay the message: the owner can publish it again with `atx custom def publish --category analysis`.

## Repo slug rules

When passing `--repo` (or its alias `--repos`; both are repeatable and comma-separated, and their values are unioned) to `analysis run`:

- **Qualified slug** (`<source>::<repo>`): always works, doesn't need `--source`.
- **Bare repo name** (`<repo>`): only works if `--source <name>` is also supplied.
- **Bare `--repo` without `--source`**: hard error (`--repo "<repo>" is unqualified — supply --source <name> or pass a fully-qualified slug like <source>::<repo>.`). Don't generate this combination.
- **Neither `--repo` nor `--source`**: rejected (`At least one of --repo or --source is required.`). `--source` alone analyzes every repo under that source.
- **Multiple repos**: must all share the same source. A run that mixes repos from different sources is rejected with `repos span multiple sources`.

Prefer qualified slugs so the source is unambiguous.

## Status Values

When polling with `atx ct analysis get --id <id> --json`, the `status` field is **lowercase**:

- `pending` -- submitted, not started yet
- `running` -- in progress
- `complete` -- finished (check findings)
- `cancelled` -- user cancelled
- `failed` -- error occurred

**Note:** It's `complete`, NOT `COMPLETED` or `completed`.

An analysis whose repositories were all cancelled one by one ends `cancelled`, not `failed`.

`status` alone doesn't say whether every repository succeeded. `atx ct analysis get` adds an `Outcome:` line when there is more to tell, for example `Complete with failures (N of M failed)`, `Partially complete (N of M did not start)`, `Complete (30 of 100 cancelled)` or `Cancelled (70 of 100 completed)`. `atx ct analysis run --wait` prints the same line after the final status. With `--json`, read `display_status` (`complete`, `complete_with_failures`, `partially_complete`, `failed`, `cancelled`, `running`, `pending`) and, when present, `repos_not_run`, `repos_complete` and `repos_cancelled`. Report a `complete_with_failures` or `partially_complete` run as such, not as fully complete. A cancelled analysis read from `analysis list` shows as plain `cancelled`, without counts.

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
| `rapid-techdebt-analysis` | Metadata files didn't expose any stale versions. **Inconclusive** -- quick scan only inspects manifests.            | Tell the user the result is inconclusive (metadata-only). Offer to run `tech-debt-comprehensive` for a code-level analysis.                                       |
| `tech-debt-comprehensive` | Bedrock did not surface tech-debt issues. Repo is likely well-maintained, but other dimensions weren't checked.     | Offer `security` for CVEs, `agentic-readiness` for AI-readiness, and `modernization-readiness` for modernization opportunities. Mention these are separate scans. |
| `security`                | Security Agent didn't surface CVEs or vulnerable patterns.                                                          | Verify the Security Agent is healthy (`atx ct setup security-agent --status`). If healthy, offer `tech-debt-comprehensive` for non-security issues.               |
| `agentic-readiness`       | Repo did not show AI-readiness gaps at the framework level.                                                         | Offer `modernization-readiness` for cloud/infrastructure modernization or `tech-debt-comprehensive` for general code health.                                      |
| `modernization-readiness` | Repo did not show modernization opportunities (infrastructure, application, data, security, operations dimensions). | Offer `agentic-readiness` for AI-integration scope or `tech-debt-comprehensive` for general code health.                                                          |

### Sanity check before reporting "clean"

If an analysis returns 0 findings on a repo that's obviously stale (Java 8, Node 14, Python 2, .NET Framework, an old `pom.xml` from 4+ years ago), do NOT report the repo as clean. Treat it as a signal that the analysis type was wrong for the question and offer a follow-up.

## Listing analyses

`atx ct analysis list` exposes these filters. Pick the narrowest combination the question allows.

| Filter          | Where it runs                           | Allowed values                                                                                                                                   |
| --------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `--status`      | server-side (GSI-backed, fast)          | `pending`, `running`, `complete`, `cancelled`, `failed`                                                                                          |
| `--type`        | server-side (GSI-backed, fast)          | `rapid-techdebt-analysis`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `custom`, `graviton-readiness` |
| `--category`    | client-side (does not reduce the fetch) | `"Tech Debt"`, `"Security"`, `"Agentic Readiness"`, `"Modernization Readiness"`, `"Graviton Readiness"`, `"Custom"`                              |
| `--schedule-id` | server-side                             | a schedule's `sched-` analysisId (from `atx ct schedule list`) — lists that schedule's fired child runs, newest first                            |

**Recommended shapes:**

- "What completed analyses do we have?" → `atx ct analysis list --status complete --json`
- "What security analyses ran?" → `atx ct analysis list --type security --json`
- "Find completed security runs" → `atx ct analysis list --status complete --type security --json`
- "What has my nightly schedule run so far?" → `atx ct analysis list --schedule-id <sched-id> --json` (the fired child runs of that schedule; get `<sched-id>` from `atx ct schedule list`)
- One specific run → `atx ct analysis get --id <id> --json` (point lookup; cheaper than list).

`--category` is a client-side grouping; e.g. `"Tech Debt"` matches both `rapid-techdebt-analysis` and `tech-debt-comprehensive`. Use it when the user wants both subtypes together.

In `--json` output a `rapid-techdebt-analysis` run's `analysis_type` is `tech-debt-quick` (the stored name); report it to the user as rapid tech-debt analysis.

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
- **Security scan finished but its findings could not be retrieved** — the run prints
  `... its findings could not be retrieved: <reason>. This is NOT a clean result` (or
  `Code review job for <repo> did not complete`) and marks that repository failed. It is
  _not_ a clean result: retry; if it persists, verify credentials/region and Security Agent
  access (`atx ct setup security-agent`).
- **Analysis stuck / no progress** — do not report success; check `atx ct analysis get --id <id>`
  (per-repo status and wait reasons) and surface the actual status.
