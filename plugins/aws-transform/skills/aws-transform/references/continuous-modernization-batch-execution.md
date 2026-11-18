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
- Customer wants serverless Fargate compute in **their own account** (no EC2 instance to keep running) — note this still deploys a customer-owned Batch stack. For a run with **no customer infrastructure at all**, use [AWS-managed execution](continuous-modernization-aws-managed-execution.md) (`--mode aws-managed`) instead.

For persistent compute with warm containers, use [remote EC2 execution](continuous-modernization-ec2-execution.md) instead.

## ⚠ MANDATORY: Permission Consent (MUST be first interaction)

**CRITICAL: When the customer chooses AWS Batch (Fargate), present this consent message before ANY setup question, and wait for a response.**

"To run on AWS Batch (Fargate), the executor role needs the `AWSTransformInfrastructureExecutorAccessBatch` policy (included with this skill) plus the `AWSTransformCustomFullAccess` managed policy, and an admin must provision the Batch stack and store the source token for remote containers. Do you have these permissions configured?"

- If the customer says **yes** → proceed with the workflow.
- If the customer says **no** → respond with: "If you don't have sufficient permissions you may encounter errors during the flow. Your administrator can run the Admin commands in this skill." Then proceed with the workflow.

**Record the customer's response** -- if they later file a bug about permission errors, we refer to their choice here.

**Admin commands are for the user to run.** The agent MUST NOT execute `remote provision`, `remote update` or `remote teardown` with `--execute`, `remote network create`, or `remote credentials`. Run the dry run (the same command without `--execute`) to show what will change, then give the user the full command to run (or pass to their admin) in their own terminal once they agree. Never add `--ack` to skip a prompt on the user's behalf.

## Prerequisites

### Environment

```bash
export AWS_REGION=us-east-1     # required
```

### Permission Model

Two roles are needed:

- **Admin** — for `provision`, `update`, `teardown`, `credentials`, `network create`
- **Executor** — for `analysis`, `remediation`, `status`, `cancel`, `detect`, `network discover`

Executor policy: [AWSTransformInfrastructureExecutorAccessBatch](https://github.com/awslabs/agent-plugins/blob/main/plugins/aws-transform/skills/aws-transform/references/AWSTransformInfrastructureExecutorAccessBatch.json) (`AWSTransformInfrastructureExecutorAccessBatch.json`, included with this skill) + `AWSTransformCustomFullAccess` managed policy. It also covers scheduling (the `atx-ct` schedule group and `iam:PassRole` on `AtxSchedulerInvocationRole-<region>`); if the admin passed a differently named role with `--existing-scheduler-role-arn`, the executor also needs `iam:PassRole` on that role.

### Source Registration

Before submitting remote jobs, the customer must have a registered source with credentials stored for remote execution. The user runs the token commands below in their own terminal (`read -s` keeps the token out of this chat and shell history; see the `/source` skill), never pasting a token into chat. Storing the token for remote runs writes an `atx/...` secret to AWS Secrets Manager, which the executor policy doesn't grant: run `source add --token` with credentials that can create and update that secret (for example the admin's), or have the admin store it later with `atx ct remote credentials`. If the admin provisioned with a customer-managed KMS key or bucket names outside `atx-*`, the bundled executor policy must be widened to those resources.

```bash
# GitHub / GitLab
read -s TOKEN && atx ct source add --name <src> --provider github|gitlab --org <org> --token "$TOKEN"; unset TOKEN

# Bitbucket Cloud (--username and --email are OPTIONAL: the API authenticates as Bearer
# without an email, and git clone/push uses x-token-auth either way)
read -s TOKEN && atx ct source add --name <src> --provider bitbucket --org <workspace> --token "$TOKEN" \
  [--username <bitbucket-username>] [--email <account-email>]; unset TOKEN

# Self-hosted GitLab or Bitbucket Data Center (add --url)
read -s TOKEN && atx ct source add --name <src> --provider gitlab|bitbucket --org <org> --token "$TOKEN" \
  --url https://gitlab.mycompany.com; unset TOKEN

# Local filesystem
atx ct source add --name <src> --provider local --path /path/to/repos

# Store or rotate the credential for remote containers (github/gitlab/bitbucket)
read -s TOKEN && atx ct remote credentials --source <src> --token "$TOKEN" --ack; unset TOKEN

# Discover repos
atx ct discovery scan --source <src>
```

**Remote credential.** Remote containers read the source token from AWS Secrets Manager
(`atx/<source>/<provider>-token`). `source add --token` stores it there (it prints
`✓ Token created in AWS Secrets Manager`, or warns `Token saved locally only` when it could not), and
`atx ct remote credentials` stores or rotates it; neither command has an option that reports whether
a token is stored. Before the first remote job on a GitHub, GitLab or Bitbucket source,
ask the user whether they have stored it, even when the source is already registered. If they
haven't or aren't sure, give them this one-liner with their region filled in (the token is stored in that region) to run in
their own terminal, never ask for the token in this chat, and continue once they say it's done:

```bash
read -s TOKEN && AWS_REGION=<region> atx ct remote credentials --source <src> --token "$TOKEN" --ack; unset TOKEN
```

The same command rotates the token, or removes it with `--remove`. It is not used for `local` sources.

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
`tag:GetResources` permission, and listing without either needs
`cloudformation:ListStacks`; the Executor policy covers both. Omit both to
list every Batch stack with the `AtxInfrastructureStack` prefix.

If deployed → skip to step 3 (Submit Analysis).
If not deployed → proceed to step 2 (Provision).

### 2. Provision

Requires Admin credentials. The user or their admin runs `network create` and `provision --execute` in their own terminal; the agent can run the `provision` dry run (no `--execute`) and show the command. The CLI generates the CFN template, creates S3 buckets, bundles Lambda functions, and deploys the stack.

**Discover network resources first:**

```bash
atx ct remote network discover --region us-east-1
```

Lists VPCs, private subnets, and security groups. Public subnets are excluded.

**If no suitable VPC exists:**

```bash
atx ct remote network create --region us-east-1 --ack
```

Creates a VPC (default CIDR `10.1.0.0/16`, override with `--cidr`) with private subnets, a NAT gateway, and a security group, then prints the `remote provision --mode batch` command to run with them. `--tags` tags the network resources.

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
- `--subnets <ids>` — required (comma-separated, private subnets only; public subnets are rejected)
- `--securityGroup <sg-id>` — required for Batch

Optional flags:

- `--suffix <name>` — custom stack name suffix (default: no suffix)
- `--image-uri <uri>` — container image override (default: public AWS Transform — continuous modernization image). A later `remote update` resets it to the default; re-run provision with `--image-uri` to keep a custom image
- `--job-timeout <seconds>` — per-attempt timeout, 60..604800 (default: 43200 = 12h)
- `--tags <key=value,...>` — resource tags applied to the stack. These same tags can later target the stack via `--tags` on `detect`/`analysis`/`remediation` (instead of `--stack-name`)
- `--existing-batch-job-role-arn`, `--existing-batch-execution-role-arn`, `--existing-lambda-submit-role-arn`, `--existing-lambda-terminate-role-arn`, `--existing-lambda-metrics-role-arn <arn>` — reference roles an admin pre-created instead of creating them
- `--existing-scheduler-role-arn <arn>` — reference a pre-created scheduler role instead of creating it
- `--skip-scheduler` — skip the scheduler stack that provision ensures alongside the compute stack
- `--json` — print the result as JSON

Without `--execute`, it's a dry run: it prints the IAM roles an admin can pre-create (and the PassRole grants the executor then needs), and writes the CloudFormation templates (Batch stack, dispatcher stack, scheduler stack) to local files for review (`--out-dir <dir>`, default the OS temp directory).

Provision also deploys or updates the account's shared dispatcher stack (`AtxDispatcherStack`) and scheduler stack (`atx-scheduler`) in the region.

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

- `--type <type>` — exactly ONE analysis type per run (rapid-techdebt-analysis, tech-debt-comprehensive, security, agentic-readiness, modernization-readiness, graviton-readiness, aws-health-readiness, custom); to run multiple types, submit once per type
- `--sources src1,src2` — multiple sources
- `--repos src::repo1,src::repo2` — specific repos (fully qualified)
- `--labels java,spring` — filter repos by labels (AND semantics)
- `--transformation-name <name>` — required when `--type custom`
- `-g key=value` — configuration for custom transformations
- `--display-name <name>` — human-readable name shown in `atx ct analysis get` and `analysis list`
- `--batch-name <name>` — custom batch ID (default: generated); must be unused
- `--json` — print the submission (`batchId` and poll command) as JSON

Stack targeting (choose one):

- `--stack-name <stack>` — target the stack by name
- `--tags env=prod,team=platform` — discover the stack by its resource tags instead of naming it (alternative to `--stack-name`; same tags set at provision time)

The CLI runs pre-flight checks (token validation, source existence), then queues the jobs for the account's dispatcher (a stack without one gets them through its trigger Lambda). Returns immediately with a batch ID and a `remote status` poll command.

Max 5,000 analysis jobs per submission (1,000 for remediation).

### 4. Check Status

```bash
atx ct remote status --batch <batch-name> --stack-name <stack>
```

Shows per-job status (running/complete/failed) with counts. Omit `--batch` to list the batches submitted in the last 7 days. A job that is waiting shows why (for example `pending (waiting for capacity)` or a retry); add `--verbose` to also print the raw wait data for each queued job.

Add `--json` for machine-readable output.

### 5. Resume a Partial Run

If some jobs in a batch failed:

```bash
atx ct remote analysis --resume-incomplete --batch-name <batch> --mode batch --stack-name <stack>
```

Re-submits only the non-completed jobs (failed, never started, or interrupted) under the same batch ID; each restarts from the beginning. Don't pass `--type`, `--sources`, `--repos`, `--labels`, or `--display-name` — they come from the original run.

### 6. Cancel

```bash
# Cancel all jobs in a batch
atx ct remote cancel --batch <batch-name> --stack-name <stack>

# Cancel a single job (jobName or Batch job id from `remote status`; a result id works only when no other job shares it)
atx ct remote cancel --batch <batch-name> --job <job-id> --stack-name <stack>
```

`--job` requires `--batch`. It kills only that job's container and marks only that repo's slot cancelled — sibling repos sharing the analysis id keep running, and the aggregate settles once every slot is terminal.

### 7. Submit Remediation

Remediates findings from a completed analysis. With `--transformation-name` and no `--ids`, it runs that transformation directly against each repo instead, with no findings needed.

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

Analyses that write reports (`tech-debt-comprehensive`, `agentic-readiness`, `modernization-readiness`, `graviton-readiness`, `aws-health-readiness`, `custom`) upload each repository's report files as `<repo>/artifacts.zip` to your bucket. List and download them:

```bash
atx ct analysis list-artifacts --id <resultId> [--repo <repositoryId>] --json
atx ct analysis get-artifact --id <resultId> --artifact-id <artifactId> [--output <file>]
```

Artifacts appear per repository as each one completes, so a listing during the run can be partial. A repository whose report files collide by name, weren't archived, or can't be read fails with an output error.

### 9. Update Stack

Update to the latest CFN template:

```bash
atx ct remote update --mode batch --stack-name <stack> --execute --ack
```

Without `--execute`, shows changeset preview (the agent can run this); the user or their admin runs the `--execute` command. With `--execute` it also updates the shared dispatcher and scheduler stacks (`--skip-dispatcher` / `--skip-scheduler` skip them). Update resets a custom `--image-uri` to the default image.

### 10. Teardown

```bash
atx ct remote teardown --mode batch --stack-name <stack> --execute --ack
```

The user or their admin runs the `--execute` command; the agent can run the preview without it. Deletes the stack (compute environments, queues, job definition, Lambda functions, IAM roles, dashboard), its CloudWatch log groups, and the infrastructure assets S3 bucket. S3 data buckets (source code, outputs), the KMS key, and Secrets Manager tokens are preserved. VPC/subnets/security groups are customer-managed and not deleted. Without `--execute` it previews what will be deleted.

## Error Handling

| Error                                                                                                            | Cause                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Fix                                                                                                                                                                                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Stack "<stack>" is not deployed (status: <status>)`                                                             | No Batch infra                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Run `atx ct remote provision --mode batch ...`                                                                                                                                                                                                                                              |
| `--stack-name is required for Batch status` / `for Batch cancel`                                                 | Batch `remote status`/`cancel` without the stack                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Add `--stack-name <stack>`                                                                                                                                                                                                                                                                  |
| `No job matching "<job>" in batch <id>`                                                                          | Wrong `--job`, or a result id shared by several jobs                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use the jobName or Batch job id from `remote status --batch <id>`                                                                                                                                                                                                                           |
| `--resume-incomplete is only supported for --mode batch`                                                         | Resume used with EC2 or aws-managed                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Resubmit the remaining repos with a new run                                                                                                                                                                                                                                                 |
| `Tag matched multiple deployed stacks`                                                                           | `--tags` matched more than one stack                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use `--stack-name`                                                                                                                                                                                                                                                                          |
| `Token invalid for source`                                                                                       | Expired/revoked SCM token                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Have the user run `read -s TOKEN && atx ct remote credentials --source <src> --token "$TOKEN" --ack; unset TOKEN` in their own terminal                                                                                                                                                     |
| `Job count <n> exceeds Lambda batch limit of <cap>`                                                              | Too many repos in one run                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Split into multiple submissions of at most `<cap>` jobs (5,000 for analysis, 1,000 for remediation), e.g. with `--repos`                                                                                                                                                                    |
| `Batch name "<name>" already exists`                                                                             | Duplicate batch name                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use a unique `--batch-name` or omit for auto-generated                                                                                                                                                                                                                                      |
| `No repos resolved`                                                                                              | Source has no repos or labels don't match                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Check `atx ct repository list --source <src>`                                                                                                                                                                                                                                               |
| `No deployed stack found for tags`                                                                               | `--tags` matched no deployed stack                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Verify tags with `atx ct remote detect --mode batch --tags <k=v>`, or target by `--stack-name`                                                                                                                                                                                              |
| `--securityGroup is required for --mode batch`                                                                   | Missing required flag                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Add `--securityGroup <sg-id>`                                                                                                                                                                                                                                                               |
| `Public subnet(s) are not allowed`                                                                               | Provided public subnets                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Use private subnets only (with NAT for internet)                                                                                                                                                                                                                                            |
| `createDefaultUserAgentProvider is not a function`                                                               | Stack's Lambda functions predate a fix                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Have the user or their admin update the stack (`atx ct remote update --mode batch --stack-name <stack> --execute --ack`), then resubmit                                                                                                                                                     |
| `Dispatcher stack <what> failed: <status> (<resource>: <reason>)`                                                | A dispatcher resource failed to deploy. On `remote provision` the command fails with it. On `remote update` the stack update itself succeeds and the message follows `Warning: the stack update succeeded, but reconciling the dispatcher infrastructure failed:`                                                                                                                                                                                                                                                                                                                  | Fix the cause it names (for example grant the deploy role the missing `dynamodb:CreateTable` permission), then rerun the same command (`remote update --execute` retries the dispatcher)                                                                                                    |
| `The dispatcher's waiting-room table <table> already exists` (`<table>` is `atx-waiting-room-<id>`)              | The table was left from an earlier deploy of this stack (an older CLI's update, or an upgrade that rolled back). `remote provision` and `remote update` clear such a table themselves (they back it up, move its jobs into the table the stack uses, and delete it), so this message means clearing it failed; the reason follows `clearing it failed:`. On `remote provision` the command fails with it. On `remote update` the stack update itself succeeds and the message follows `Warning: the stack update succeeded, but reconciling the dispatcher infrastructure failed:` | Fix the reason it gives if you can and rerun the command. Otherwise follow the steps the message prints: check the table for jobs and back it up if it has any, delete it, and rerun the command; if you backed it up, restore the backup as `AtxDispatcherStack-WaitingRoomTable-restored` |
| `The dispatcher's waiting-room table <table>, kept from an earlier deploy of this stack, is still being deleted` | The kept table's deletion hadn't finished when the command stopped waiting                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Wait until the table is gone, then rerun the command; nothing is lost                                                                                                                                                                                                                       |
| `Did not finish clearing the kept waiting-room table <table>`                                                    | The dispatcher stack changed, or couldn't be checked, while the command was clearing the kept table                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Don't delete the table (it may now be the stack's own); rerun the command once the stack is no longer updating                                                                                                                                                                              |

A stack deployed by an older CLI keeps its old infrastructure. When a fix needs the stack itself (the CLI or its release notes say to run `remote update`), update it as in step 9.

The dispatcher's waiting-room table is now named `atx-waiting-room-<id>` (it was `AtxDispatcherStack-WaitingRoomTable-<id>`), so a deploy role that limits DynamoDB to `table/atx-*` can provision and update the stack. The next `remote update` or `provision` creates the new table and keeps the old one, and the dispatcher moves any jobs still waiting in the old table into the new one by itself. Tell the user to delete the old table only once the dispatcher's log shows `legacy-waiting-room-drained`.

## Limits

- Account-wide: every analysis and remediation type except security shares one pool of 50 concurrent jobs across all your Batch stacks and EC2 runners (30 while the stacks were last provisioned or updated by an older CLI; `atx ct remote update` raises it). On-demand jobs start before scheduled ones, and scheduled jobs that have waited 4 hours get about half of the free slots.
- Max 5,000 analysis jobs (1,000 remediation jobs) per submission (fan-out ceiling)
- Job timeout: 60s to 604800s (default 12h)
- Batch stack names must start with `AtxInfrastructureStack`
- `--execute` flag gates all destructive operations (provision/update/teardown)
