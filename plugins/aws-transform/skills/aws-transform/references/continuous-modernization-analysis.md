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

- Mentions EC2 / "on an instance" → follow [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md)
- Mentions Batch / Fargate / "serverless" → follow [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md)
- Mentions "remotely" / "on AWS" / "in the cloud" (no specific compute) → ask which: EC2 or Batch (Fargate)

**Otherwise**, for analyses with more than 9 repos, ask the customer:

> "Do you want to run this locally, set up an EC2 instance in your AWS account, or submit to AWS Batch (Fargate)?"

- **Local** -- proceed with the commands below
- **EC2** -- follow [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md)
- **Batch** -- follow [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md)

## Commands

```bash
# Run analysis (returns immediately with analysis ID)
atx ct analysis run --type <tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|custom> --source <name> [--repo <source>::<slug>] --telemetry "agent=<AGENT>,executionMode=local"

# Run and wait for completion
atx ct analysis run --type <tech-debt-quick|tech-debt-comprehensive|security|agentic-readiness|modernization-readiness|custom> --source <name> [--repo <source>::<slug>] --wait --telemetry "agent=<AGENT>,executionMode=local"

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

## Artifacts

After an analysis completes, its report artifacts can be listed and retrieved:

```bash
# List all artifacts for an analysis
atx ct analysis list-artifacts --id <analysis-id> --json

# Get content of a specific artifact
atx ct analysis get-artifact --id <analysis-id> --repo <source>::<slug> --name <artifact-name>
```

### Artifact names by analysis type

| Analysis Type           | Artifact Names                                                                                                                                                               |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| tech-debt-comprehensive | `report`, `technical-debt-report/summary`, `technical-debt-report/outdated-components`, `technical-debt-report/maintenance-burden`, `technical-debt-report/remediation-plan` |
| agentic-readiness       | `ara` (per repo); `_portfolio_ara` (portfolio-level)                                                                                                                         |
| modernization-readiness | `mod` (per repo); `_portfolio_mod` (portfolio-level)                                                                                                                         |

## After Analysis Completes

Once an analysis finishes, retrieve its findings by analysis ID and summarize for the user:

```bash
# Get findings produced by a specific analysis
atx ct findings list --analysis-id <analysis-id> --json

# List artifacts to see available reports
atx ct analysis list-artifacts --id <analysis-id> --json

# Read a specific report
atx ct analysis get-artifact --id <analysis-id> --repo <source>::<slug> --name report
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

`atx ct analysis list` exposes three filters. Pick the narrowest combination the question allows.

| Filter       | Where it runs                           | Allowed values                                                                                                     |
| ------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `--status`   | server-side (GSI-backed, fast)          | `pending`, `running`, `complete`, `cancelled`, `failed`                                                            |
| `--type`     | server-side (GSI-backed, fast)          | `tech-debt-quick`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `custom` |
| `--category` | client-side (does not reduce the fetch) | `"Tech Debt"`, `"Security"`, `"Agentic Readiness"`                                                                 |

**Recommended shapes:**

- "What completed analyses do we have?" → `atx ct analysis list --status complete --json`
- "What security analyses ran?" → `atx ct analysis list --type security --json`
- "Find completed security runs" → `atx ct analysis list --status complete --type security --json`
- One specific run → `atx ct analysis get --id <id> --json` (point lookup; cheaper than list).

`--category` is a client-side grouping; e.g. `"Tech Debt"` matches both `tech-debt-quick` and `tech-debt-comprehensive`. Use it when the user wants both subtypes together.

`--status` and `--type` accept only the canonical values above. Off-canonical input (e.g. `--status completed`, `--type tech-debt`) returns an `INVALID_INPUT` error.
