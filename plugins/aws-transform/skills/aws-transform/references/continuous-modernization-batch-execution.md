---
name: remote-batch
description: Run analysis or remediation at scale on AWS Batch (Fargate) using `atx ct remote` CLI commands. Exactly one --type per run; one container per repo. Covers provisioning, job submission, status, cancel, and teardown.
---

# Remote Batch Execution

Run analysis or remediation at scale on AWS Batch (Fargate). Each job runs in its own container — one container per repo (exactly one --type per run). All orchestration is handled by the CLI (`atx ct remote ...`); no raw AWS commands needed.

## Telemetry

Include `--telemetry` on every `atx ct remote analysis` and `atx ct remote remediation`:

```
--telemetry "agent=<agent>,executionMode=fargate"
```

- `agent` — the AI assistant name (lowercase, no spaces): kiro, claude, amazonq, copilot
- `executionMode` — `fargate`

If the user explicitly opts out of telemetry, omit `--telemetry` for the rest of the session.

## When to Use

- Analyzing or remediating many repos in parallel (one container per repo)
- Analyzing one type across many sources or repos in a single run (to run multiple types, submit once per type)
- One-shot batch jobs with no persistent infrastructure between runs
- Customer wants AWS-managed compute (no EC2 instance to manage)

For persistent compute with warm containers, use [remote EC2 execution](continuous-modernization-ec2-execution.md) instead.

## Prerequisites

### Environment

```bash
export AWS_REGION=us-east-1     # required
```

### Permission Model

Two roles are needed:

- **Admin** — for `provision`, `update`, `teardown`, `credentials`, `network create`
- **Executor** — for `analysis`, `remediation`, `status`, `cancel`, `detect`, `network discover`

Executor policy: [AWSTransformInfrastructureExecutorAccessBatch](https://code.amazon.com/packages/ATXControlTowerPolicies/blobs/mainline/--/managed-policies/draft/AWSTransformInfrastructureExecutorAccessBatch.json) + `AWSTransformCustomFullAccess` managed policy.

### Source Registration

Before submitting remote jobs, the customer must have a registered source with credentials stored for remote execution:

```bash
# GitHub / GitLab
atx ct source add --name <src> --provider github|gitlab --org <org> --token <token>

# Bitbucket Cloud (--username and --email optional but needed for clone/push and API auth)
atx ct source add --name <src> --provider bitbucket --org <workspace> --token <token> \
  --username <bitbucket-username> --email <account-email>

# Self-hosted GitLab or Bitbucket Data Center (add --url)
atx ct source add --name <src> --provider gitlab|bitbucket --org <org> --token <token> \
  --url https://gitlab.mycompany.com

# Local filesystem
atx ct source add --name <src> --provider local --path /path/to/repos

# Store credential for remote containers (required for github/gitlab/bitbucket)
atx ct remote credentials --source <src> --token <token> --ack

# Discover repos
atx ct discovery scan --source <src>
```

## Workflow

### 1. Detect Infrastructure

Check if a Batch stack is already deployed:

```bash
# List all Batch stacks in the account (mode prefix)
atx ct remote detect --mode batch

# Look up one stack directly
atx ct remote detect --mode batch --stack-name <stack>

# Discover the stack by its resource tags
atx ct remote detect --mode batch --tags env=prod,team=platform
```

`--stack-name` and `--tags` are mutually exclusive. Tag discovery requires the
`tag:GetResources` permission (covered by the Executor policy). Omit both to
list every Batch stack with the `AtxInfrastructureStack` prefix.

If deployed → skip to step 3 (Submit Analysis).
If not deployed → proceed to step 2 (Provision).

### 2. Provision

Requires Admin credentials. The CLI generates the CFN template, creates S3 buckets, bundles Lambda functions, and deploys the stack.

**Discover network resources first:**

```bash
atx ct remote network discover --region us-east-1
```

Lists VPCs, private subnets, and security groups. Public subnets are excluded.

**If no suitable VPC exists:**

```bash
atx ct remote network create --region us-east-1 --ack
```

**Provision the Batch stack:**

```bash
atx ct remote provision --mode batch \
  --vpc <vpc-id> \
  --subnets <subnet-1>,<subnet-2> \
  --securityGroup <sg-id> \
  --execute --ack
```

Required flags:

- `--mode batch` — required
- `--vpc <id>` — required
- `--subnets <ids>` — required (comma-separated, private subnets only)
- `--securityGroup <sg-id>` — required for Batch

Optional flags:

- `--suffix <name>` — custom stack name suffix (default: no suffix)
- `--image-uri <uri>` — container image override (default: public AWS Transform — continuous modernization image)
- `--job-timeout <seconds>` — per-attempt timeout, 60..604800 (default: 43200 = 12h)
- `--tags <key=value,...>` — resource tags applied to the stack. These same tags can later target the stack via `--tags` on `detect`/`analysis`/`remediation` (instead of `--stack-name`)

Without `--execute`, the command prints the CFN template (dry-run preview).

### 3. Submit Analysis

Requires Executor credentials. Exactly one --type per run; one container per repo.

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode batch \
  --stack-name <stack> \
  --batch-name <custom-name> \
  --telemetry "agent=kiro,executionMode=fargate"
```

Fan-out options:

- `--type <type>` — exactly ONE analysis type per run (rapid-techdebt-analysis, tech-debt-comprehensive, security, agentic-readiness, modernization-readiness, custom); to run multiple types, submit once per type
- `--sources src1,src2` — multiple sources
- `--repos src::repo1,src::repo2` — specific repos (fully qualified)
- `--labels java,spring` — filter repos by labels (AND semantics)
- `--transformation-name <name>` — required when `--type custom`
- `-g key=value` — configuration for custom transformations

Stack targeting (choose one):

- `--stack-name <stack>` — target the stack by name
- `--tags env=prod,team=platform` — discover the stack by its resource tags instead of naming it (alternative to `--stack-name`; same tags set at provision time)

The CLI runs pre-flight checks (token validation, source existence), then invokes the trigger Lambda. Returns immediately with a batch ID for polling.

Max 250 jobs per submission.

### 4. Check Status

```bash
atx ct remote status --batch <batch-name> --stack-name <stack>
```

Shows per-job status (running/complete/failed) with counts. Omit `--batch` to list recent batches.

Add `--json` for machine-readable output.

### 5. Resume a Partial Run

If some jobs in a batch failed:

```bash
atx ct remote analysis --resume --batch-name <batch> --mode batch --stack-name <stack>
```

Re-submits only the non-completed jobs from the original batch.

### 6. Cancel

```bash
# Cancel all jobs in a batch
atx ct remote cancel --batch <batch-name> --stack-name <stack>

# Cancel a single job (jobName, Batch job id, or remediation id from `remote status`)
atx ct remote cancel --batch <batch-name> --job <job-id> --stack-name <stack>
```

`--job` requires `--batch`. It kills only that job's container and marks only that repo's slot cancelled — sibling repos sharing the analysis id keep running, and the aggregate settles once every slot is terminal.

### 7. Submit Remediation

Requires completed analysis with findings.

```bash
atx ct remote remediation \
  --sources <src> \
  --min-severity medium \
  --mode batch \
  --stack-name <stack> \
  --batch-name rem-1 \
  --telemetry "agent=kiro,executionMode=fargate"
```

Filter options:

- `--ids <id1,id2>` — specific finding IDs
- `--sources <src>` / `--repos <src>::<repo>` — by source/repo
- `--severity high` — exact severity match
- `--min-severity medium` — minimum threshold
- `--labels <labels>` — filter by repo labels
- `--transformation-name <name>` — override fix strategy
- `-g, --configuration <config>` — config path or key=value pairs (only valid with `--transformation-name`)

Stack targeting is the same as analysis: pass `--stack-name <stack>` or discover the stack by its resource tags with `--tags env=prod,...` (alternative to `--stack-name`).

### 8. Get Results

Status output already shows key result info for completed jobs:

- **Analysis**: `resultId` and finding count (e.g., `(3 findings)`)
- **Remediation**: `resultId` and PR/MR URL (for SCM sources) or S3 output path (for local sources)

For deeper detail on findings:

```bash
atx ct analysis get --id <resultId> --json
```

### 9. Update Stack

Update to the latest CFN template:

```bash
atx ct remote update --mode batch --stack-name <stack> --execute --ack
```

Without `--execute`, shows changeset preview.

### 10. Teardown

```bash
atx ct remote teardown --mode batch --stack-name <stack> --execute --ack
```

S3 buckets (source code, outputs) and Secrets Manager tokens are preserved. VPC/subnets are customer-managed and not deleted.

## Error Handling

| Error                                          | Cause                                     | Fix                                                                                            |
| ---------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `Stack not deployed`                           | No Batch infra                            | Run `atx ct remote provision --mode batch ...`                                                 |
| `Token invalid for source`                     | Expired/revoked SCM token                 | Run `atx ct remote credentials --source <src> --token <new> --ack`                             |
| `Job count exceeds Lambda batch limit of 250`  | Too many repos in one run                 | Split into multiple submissions                                                                |
| `Batch name already exists`                    | Duplicate batch name                      | Use a unique `--batch-name` or omit for auto-generated                                         |
| `No repos resolved`                            | Source has no repos or labels don't match | Check `atx ct repository list --source <src>`                                                  |
| `No deployed stack found for tags`             | `--tags` matched no deployed stack        | Verify tags with `atx ct remote detect --mode batch --tags <k=v>`, or target by `--stack-name` |
| `--securityGroup is required for --mode batch` | Missing required flag                     | Add `--securityGroup <sg-id>`                                                                  |
| `Public subnet(s) are not allowed`             | Provided public subnets                   | Use private subnets only (with NAT for internet)                                               |

## Limits

- Max 250 jobs per submission (fan-out ceiling)
- Job timeout: 60s to 604800s (default 12h)
- Batch stack names must start with `AtxInfrastructureStack`
- `--execute` flag gates all destructive operations (provision/update/teardown)
