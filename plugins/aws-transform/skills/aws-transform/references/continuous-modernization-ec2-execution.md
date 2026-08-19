---
name: remote-ec2
description: Run analysis or remediation on a persistent EC2 instance using `atx ct remote` CLI commands. One long-running container with 1-5 workers; jobs dispatched via SSM. Covers provisioning, job submission, status, cancel, BYO instance, and teardown.
---

# Remote EC2 Execution

Run analysis or remediation on a persistent EC2 instance with one or more long-running containers. The instance stays up between submissions — useful for repeated analyses on the same sources without cold-start. Jobs are dispatched via SSM SendCommand and distributed round-robin across workers.

## Telemetry

Include `--telemetry` on every `atx ct remote analysis` and `atx ct remote remediation`:

```
--telemetry "agent=<agent>,executionMode=ec2"
```

- `agent` — the AI assistant name (lowercase, no spaces): kiro, claude, amazonq, copilot
- `executionMode` — `ec2`

If the user explicitly opts out of telemetry, omit `--telemetry` for the rest of the session.

## When to Use

- Re-running multiple analyses on the same compute (warm container, no cold-start)
- Customer prefers a persistent instance they can SSM into for debugging
- Workloads that run sequentially or with limited parallelism (1-5 workers)
- Customer wants to use their own existing EC2 instance (BYO path)

For one-shot fan-out at scale (>5 parallel jobs), use [remote Batch execution](continuous-modernization-batch-execution.md) instead.

## Prerequisites

### Environment

```bash
export AWS_REGION=us-east-1     # required
```

### Permission Model

Two roles are needed:

- **Admin** — for `provision`, `update`, `teardown`, `credentials`, `network create`
- **Executor** — for `analysis`, `remediation`, `status`, `cancel`, `detect`, `network discover`

Executor policy: [AWSTransformInfrastructureExecutorAccessEC2](https://code.amazon.com/packages/ATXControlTowerPolicies/blobs/mainline/--/managed-policies/draft/AWSTransformInfrastructureExecutorAccessEC2.json) + `AWSTransformCustomFullAccess` managed policy.

### Source Registration

Before submitting remote jobs, the customer must have a registered source with credentials stored:

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

## Multi-Worker Support

EC2 supports 1-5 parallel workers (containers) on a single instance. Jobs are distributed round-robin across workers.

| Customer intent                               | Workers           | Instance type |
| --------------------------------------------- | ----------------- | ------------- |
| Single analysis / default                     | 1                 | m5.2xlarge    |
| 2 parallel analyses (e.g. 2 repos, or 2 runs) | 2                 | m5.4xlarge    |
| 3-4 parallel jobs                             | 3-4               | m5.4xlarge    |
| 5 parallel jobs (max)                         | 5                 | m5.8xlarge    |
| 6+ parallel jobs                              | Use Batch instead | —             |

WorkerCount is fixed at stack-create time. Changing it requires a destructive redeploy (`teardown` + `provision`).

Each worker is memory-capped at `(instance RAM - 4 GB) / WorkerCount`. The CLI auto-sizes instance type if not specified.

## Workflow

### 1. Detect Infrastructure

```bash
# List all EC2 stacks in the account (mode prefix)
atx ct remote detect --mode ec2

# Look up one stack directly
atx ct remote detect --mode ec2 --stack-name <stack>

# Discover the stack by its resource tags
atx ct remote detect --mode ec2 --tags env=prod,team=platform
```

`--stack-name` and `--tags` are mutually exclusive. Tag discovery requires the
`tag:GetResources` permission (covered by the Executor policy). Omit both to
list every EC2 stack with the `atx-runner` prefix.

If deployed → skip to step 3 (Submit Analysis).
If not deployed → proceed to step 2 (Provision).

### 2. Provision

Requires Admin credentials.

**Discover network resources:**

```bash
atx ct remote network discover --region us-east-1
```

**If no suitable VPC exists:**

```bash
atx ct remote network create --region us-east-1 --ack
```

**Provision the EC2 stack:**

```bash
atx ct remote provision --mode ec2 \
  --vpc <vpc-id> \
  --subnets <subnet-1>,<subnet-2> \
  --execute --ack
```

Required flags:

- `--mode ec2` — required
- `--vpc <id>` — required
- `--subnets <ids>` — required (comma-separated, private subnets only)

Optional flags:

- `--workers <1-5>` — parallel container count (default: 1)
- `--instance-type <type>` — override auto-sizing (m5.large to m5.12xlarge)
- `--volume-size <gb>` — EBS volume size (default: auto-sized from workers)
- `--image-uri <uri>` — container image override (default: public AWS Transform — continuous modernization image)
- `--stack-name <name>` — custom name (must start with `atx-runner`)
- `--suffix <name>` — appended to default stack name
- `--securityGroup <sg-id>` — optional for EC2 (auto-created if omitted)
- `--tags <key=value,...>` — resource tags applied to the stack. These same tags can later target the stack via `--tags` on `detect`/`analysis`/`remediation` (instead of `--stack-name`)

Without `--execute`, prints the CFN template (dry-run preview).

The stack creates: EC2 instance, IAM role + instance profile, security group (no inbound, SSM access), CloudWatch log group, and dashboard. UserData pulls the container image, starts workers, and signals CFN on health check pass.

### 3. Submit Analysis

Requires Executor credentials. Jobs are distributed round-robin across workers.

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode ec2 \
  --stack-name <stack-name> \
  --telemetry "agent=kiro,executionMode=ec2"
```

Fan-out options:

- `--type <type>` — exactly ONE analysis type per run (to run multiple types, submit once per type)
- `--sources src1,src2` — multiple sources
- `--repos src::repo1,src::repo2` — specific repos (fully qualified)
- `--labels java,spring` — filter repos by labels (AND semantics)
- `--transformation-name <name>` — for `--type custom`
- `-g key=value` — configuration for custom transformations

Stack targeting (choose one):

- `--stack-name <stack>` — target the stack by name
- `--tags env=prod,team=platform` — discover the stack by its resource tags instead of naming it (alternative to `--stack-name`; same tags set at provision time)
- `--existing-instance <id>` — BYO path; replaces `--stack-name`/`--tags` (see below)

The CLI runs pre-flight checks (token validation, instance health), dispatches via SSM, and returns a group ID for polling.

### 4. Check Status

```bash
# Poll once
atx ct remote status --group <ec2-group-id>

# Poll until all jobs complete
atx ct remote status --group <ec2-group-id> --wait
```

Shows per-job status with completion counts.

### 5. Cancel

```bash
# Cancel all jobs in a group
atx ct remote cancel --group <ec2-group-id>

# Cancel a single job (a job key `repo#type` / `repo#findingId`, or its result ULID)
atx ct remote cancel --group <ec2-group-id> --job <repo#type>
```

`--job` kills only that job's in-container process and marks only that repo's slot cancelled — sibling repos sharing the analysis id keep running, and the aggregate settles once every slot is terminal.

### 6. Submit Remediation

Requires completed analysis with findings.

```bash
atx ct remote remediation \
  --ids <finding-id1>,<finding-id2> \
  --mode ec2 \
  --stack-name <stack-name> \
  --telemetry "agent=kiro,executionMode=ec2"
```

Filter options:

- `--ids <id1,id2>` — specific finding IDs
- `--sources <src>` / `--repos <src>::<repo>` — by source/repo
- `--severity high` — exact match
- `--min-severity medium` — minimum threshold
- `--labels <labels>` — filter by repo labels
- `--transformation-name <name>` — override fix strategy
- `-g, --configuration <config>` — config path or key=value pairs (only valid with `--transformation-name`)

Stack targeting is the same as analysis: `--stack-name <stack>`, discover by resource tags with `--tags env=prod,...` (alternative to `--stack-name`), or `--existing-instance <id>` for BYO.

### 7. Get Results

Status output already shows key result info for completed jobs:

- **Analysis**: `resultId` and finding count
- **Remediation**: `resultId` and PR/MR URL (for SCM sources) or S3 output path (for local sources)

For deeper detail on findings:

```bash
atx ct analysis get --id <resultId> --json
```

### 8. Update Stack

```bash
atx ct remote update --mode ec2 --stack-name <stack> --execute --ack
```

Without `--execute`, shows changeset preview.

### 9. Teardown

```bash
atx ct remote teardown --mode ec2 --stack-name <stack> --execute --ack
```

Instance, IAM role, security group removed atomically. S3 buckets and Secrets Manager tokens persist.

## BYO Instance (Existing EC2)

Use an existing customer-owned EC2 instance instead of provisioning a new stack. The instance must have SSM agent running and the `atx-remote-infra=true` tag.

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode ec2 \
  --existing-instance <instance-id> \
  --workers 2 \
  --telemetry "agent=kiro,executionMode=ec2"
```

BYO-specific flags:

- `--existing-instance <id>` — instance ID (mutually exclusive with `--stack-name`/`--tags`)
- `--workers <n>` — container count on the instance (default 1)
- `--ct-output-bucket <name>` — custom output bucket
- `--source-bucket <name>` — custom source bucket
- `--output-bucket <name>` — custom artifact bucket

Note: `--image-uri` is NOT available for BYO — it's a `provision` flag only. The instance must already have the AWS Transform — continuous modernization container image running.

Prerequisites for BYO:

- Instance is running and SSM-managed
- Docker installed with the AWS Transform — continuous modernization container running
- Instance tagged with `atx-remote-infra=true` (required by executor policy)
- Instance role has S3, Secrets Manager, and transform-custom access

## Error Handling

| Error                                                                  | Cause                                   | Fix                                                                                          |
| ---------------------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------------------------------- |
| `Stack not deployed`                                                   | No EC2 infra                            | Run `atx ct remote provision --mode ec2 ...`                                                 |
| `EC2 stack exposed no InstanceId`                                      | Stack exists but instance missing       | Check CFN stack events; may need teardown + reprovision                                      |
| `workerCount must be in [1, 5]`                                        | Workers out of range                    | Use 1-5, or switch to Batch for more parallelism                                             |
| `Stack name must start with "atx-runner"`                              | Invalid prefix                          | Use `--stack-name atx-runner-<suffix>` or `--suffix <name>`                                  |
| `--existing-instance is mutually exclusive with --stack-name / --tags` | Both specified                          | Use one or the other                                                                         |
| `Existing-instance prerequisite check failed`                          | Instance not SSM-managed or missing tag | Verify SSM agent, add `atx-remote-infra=true` tag                                            |
| `Token invalid for source`                                             | Expired/revoked SCM token               | Run `atx ct remote credentials --source <src> --token <new> --ack`                           |
| `No deployed stack found for tags`                                     | `--tags` matched no deployed stack      | Verify tags with `atx ct remote detect --mode ec2 --tags <k=v>`, or target by `--stack-name` |
| `Group not found`                                                      | Invalid or expired group ID             | Check `atx ct remote status --group <id>`                                                    |

## Limits

- Max 5 workers per instance
- EC2 stack names must start with `atx-runner`
- WorkerCount fixed at provision time (change requires redeploy)
- `--execute` flag gates all destructive operations
- Instance types: m5.large to m5.12xlarge
