---
name: remote-ec2
description: Run analysis or remediation on a persistent EC2 instance using `atx ct remote` CLI commands. 1-5 long-running worker containers on one instance; jobs run via SSM. Covers provisioning, job submission, status, cancel, BYO instance, and teardown.
---

# Remote EC2 Execution

Run analysis or remediation on a persistent EC2 instance with one or more long-running containers. The instance stays up between submissions — useful for repeated analyses on the same sources without cold-start. Jobs are queued through the account's dispatcher, which starts each one on a free worker via SSM SendCommand (a BYO instance gets its jobs straight from the CLI, round-robin across workers).

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
- Customer prefers a persistent instance they can SSM into for debugging (the bundled executor policy grants `ssm:StartSession` on instances tagged `atx-remote-infra=true`)
- Workloads that run sequentially or with limited parallelism (1-5 workers)
- Customer wants to use their own existing EC2 instance (BYO path)

For one-shot fan-out at scale (>5 parallel jobs), use [remote Batch execution](continuous-modernization-batch-execution.md) instead.

## ⚠ MANDATORY: Permission Consent (MUST be first interaction)

**CRITICAL: When the customer chooses EC2, present this consent message before ANY setup question, and wait for a response.**

"To run on EC2, the executor role needs the `AWSTransformInfrastructureExecutorAccessEC2` policy (included with this skill) plus the `AWSTransformCustomFullAccess` managed policy, and an admin must provision the EC2 stack and store the source token for remote containers. Do you have these permissions configured?"

- If the customer says **yes** → proceed with the workflow.
- If the customer says **no** → respond with: "If you don't have sufficient permissions you may encounter errors during the flow. Your administrator can run the Admin commands in this skill." Then proceed with the workflow.

**Record the customer's response** -- if they later file a bug about permission errors, we refer to their choice here.

**Admin commands are for the user to run.** The agent MUST NOT execute `remote provision`, `remote update` or `remote teardown` with `--execute`, `remote network create`, or `remote credentials`. The agent may run only genuinely read-only previews: `remote provision` without `--execute` writes templates locally, and `remote teardown` without `--execute` only describes resources. `remote update` is different: even without `--execute` it creates, describes, and deletes a CloudFormation changeset, so give both update forms to the user or their admin to run. Never add `--ack` to skip a prompt on the user's behalf.

## Prerequisites

### Environment

```bash
export AWS_REGION=us-east-1     # required
```

### Permission Model

Two roles are needed:

- **Admin** — for `provision`, `update`, `teardown`, `credentials`, `network create`
- **Executor** — for `analysis`, `remediation`, `status`, `cancel`, `detect`, `network discover`

Executor policy: [AWSTransformInfrastructureExecutorAccessEC2](https://github.com/awslabs/agent-plugins/blob/main/plugins/aws-transform/skills/aws-transform/references/AWSTransformInfrastructureExecutorAccessEC2.json) (`AWSTransformInfrastructureExecutorAccessEC2.json`, included with this skill) + `AWSTransformCustomFullAccess` managed policy. It also covers scheduling (the `atx-ct` schedule group and `iam:PassRole` on `AtxSchedulerInvocationRole-<region>`); if the admin passed a differently named role with `--existing-scheduler-role-arn`, the executor also needs `iam:PassRole` on that role.

### Source Registration

Before submitting remote jobs, the customer must have a registered source with credentials stored. The user runs the token commands below in their own terminal (`read -s` keeps the token out of this chat and shell history; see the `/source` skill), never pasting a token into chat. Storing the token for remote runs writes an `atx/...` secret to AWS Secrets Manager, which the executor policy doesn't grant: run `source add --token` with credentials that can create and update that secret (for example the admin's), or have the admin store it later with `atx ct remote credentials`. If the admin provisioned with a customer-managed KMS key or bucket names outside `atx-*`, the bundled executor policy must be widened to those resources.

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

## Multi-Worker Support

EC2 supports 1-5 parallel workers (containers) on a single instance. The dispatcher starts each job on a free worker (a BYO instance gets its jobs round-robin from the CLI).

| Customer intent                                                    | Workers           | Instance type |
| ------------------------------------------------------------------ | ----------------- | ------------- |
| Single analysis at a time                                          | 1                 | m5.2xlarge    |
| 2 parallel analyses (e.g. 2 repos, or 2 runs)                      | 2                 | m5.4xlarge    |
| 3-4 parallel jobs                                                  | 3-4               | m5.4xlarge    |
| 5 parallel jobs (max, and the default when `--workers` is omitted) | 5                 | m5.8xlarge    |
| 6+ parallel jobs                                                   | Use Batch instead | —             |

WorkerCount is fixed at stack-create time. Changing it requires a destructive redeploy (`teardown` + `provision`).

Each worker is memory-capped at `(instance RAM - 4 GB) / WorkerCount`, and the instance must have at least 2 GB per worker plus 4 GB. The CLI auto-sizes the instance type and the EBS volume (50 GB per worker) if not specified.

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
`tag:GetResources` permission, and listing without either needs
`cloudformation:ListStacks`; the Executor policy covers both. Omit both to
list every EC2 stack with the `atx-runner` prefix.

If deployed → skip to step 3 (Submit Analysis).
If not deployed → proceed to step 2 (Provision).

### 2. Provision

Requires Admin credentials. The user or their admin runs `network create` and `provision --execute` in their own terminal; the agent can run the `provision` dry run (no `--execute`) and show the command.

**Discover network resources:**

```bash
atx ct remote network discover --region us-east-1
```

Lists VPCs, private subnets, and security groups (`--vpc <id>` narrows to one VPC). Public subnets are excluded.

**If no suitable VPC exists:**

```bash
atx ct remote network create --region us-east-1 --no-security-group --ack
```

Creates a VPC (default CIDR `10.1.0.0/16`, override with `--cidr`) with private subnets and a NAT gateway. `--no-security-group` skips the security group, since the EC2 stack creates its own; `--tags` tags the network resources. The provision command it prints is for `--mode batch`; for EC2 use the VPC and private subnet IDs it lists.

**Provision the EC2 stack:**

```bash
atx ct remote provision --mode ec2 \
  --vpc <vpc-id> \
  --subnets <subnet-1>,<subnet-2> \
  --workers <1-5> \
  --execute --ack
```

Choose the worker count explicitly before presenting the command. Always state that the valid range is 1-5 workers, even when the user already requested one worker. Use `--workers 1` when the user wants one analysis at a time. If omitted, the CLI defaults to five workers, auto-sizes a persistent `m5.8xlarge` instance, and creates a 250 GB EBS volume; WorkerCount cannot be changed without teardown and reprovisioning.

Required flags:

- `--mode ec2` — required
- `--vpc <id>` — required
- `--subnets <ids>` — required (comma-separated, private subnets only; public subnets are rejected; the instance goes in the first one)

Optional flags:

- `--workers <1-5>` — parallel container count (default: 5)
- `--instance-type <type>` — override auto-sizing (m5.large to m5.12xlarge)
- `--volume-size <gb>` — EBS volume size (default: auto-sized from workers)
- `--image-uri <uri>` — container image override (default: public AWS Transform — continuous modernization image). A later `remote update` resets it to the default; re-run provision with `--image-uri` to keep a custom image
- `--stack-name <name>` — custom name (must start with `atx-runner`)
- `--suffix <name>` — appended to default stack name
- `--securityGroup <sg-id>` — optional for EC2 (auto-created if omitted)
- `--tags <key=value,...>` — resource tags applied to the stack. These same tags can later target the stack via `--tags` on `detect`/`analysis`/`remediation` (instead of `--stack-name`)
- `--existing-instance-profile-name <name>` — attach an instance profile an admin pre-created instead of creating the transform role + profile (the role must be fully permissioned)
- `--existing-scheduler-role-arn <arn>` — reference a pre-created scheduler role instead of creating it
- `--skip-scheduler` — skip the scheduler stack that provision ensures alongside the compute stack
- `--json` — print the result as JSON

Without `--execute`, it's a dry run: it prints the IAM roles an admin can pre-create (and the PassRole grants the executor then needs), and writes the CloudFormation templates (EC2 stack, dispatcher stack, scheduler stack) to local files for review (`--out-dir <dir>`, default the OS temp directory).

The stack creates: EC2 instance, IAM role + instance profile, security group (no inbound, SSM access), S3 buckets for sources and outputs, a KMS key, CloudWatch log group, and dashboard. UserData pulls the container image, starts workers, and signals CFN on health check pass. Provision also deploys or updates the account's shared dispatcher stack (`AtxDispatcherStack`) and scheduler stack (`atx-scheduler`) in the region.

### 3. Submit Analysis

Requires Executor credentials. The dispatcher starts each job on a free worker (BYO: round-robin from the CLI).

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode ec2 \
  --stack-name <stack-name> \
  --telemetry "agent=<agent>,executionMode=ec2"
```

Fan-out options:

- `--type <type>` — exactly ONE analysis type per run (rapid-techdebt-analysis, tech-debt-comprehensive, security, agentic-readiness, modernization-readiness, graviton-readiness, aws-health-readiness, custom); to run multiple types, submit once per type
- `--sources src1,src2` — multiple sources
- `--repos src::repo1,src::repo2` — specific repos (fully qualified)
- `--labels java,spring` — filter repos by labels (AND semantics)
- `--transformation-name <name>` — for `--type custom`
- `-g key=value` — configuration for custom transformations
- `--display-name <name>` — human-readable name shown in `atx ct analysis get` and `analysis list`
- `--json` — print the submission (`groupId` and poll command) as JSON

Stack targeting (choose one):

- `--stack-name <stack>` — target the stack by name
- `--tags env=prod,team=platform` — discover the stack by its resource tags instead of naming it (alternative to `--stack-name`; same tags set at provision time)
- `--existing-instance <id>` — BYO path; replaces `--stack-name`/`--tags` (see below)

The CLI runs pre-flight checks (token validation, instance health), queues the jobs for the dispatcher, and returns a group ID (`ec2-...`) and a `remote status` poll command for polling. EC2 runs can't be resumed (`--resume-incomplete` is Batch-only); resubmit the repos that didn't complete.

### 4. Check Status

```bash
# Poll once
atx ct remote status --group <ec2-group-id>

# Poll until all jobs complete (gives up after 60 minutes unless --wait-timeout <minutes>)
atx ct remote status --group <ec2-group-id> --wait
```

The group manifest is kept on the machine that submitted it. From another machine add the `--output-bucket <atx-ct-output-bucket>` that the submission's poll command shows (`remote cancel` takes it too). Shows per-job status with completion counts. A job that is waiting shows why (for example `pending (waiting for capacity)` or a retry); add `--verbose` to also print the raw wait data for each queued job.

### 5. Cancel

```bash
# Cancel all jobs in a group
atx ct remote cancel --group <ec2-group-id>

# Cancel a single job (a job key `repo#type` / `repo#findingId`; a result id works only when no other job shares it)
atx ct remote cancel --group <ec2-group-id> --job <repo#type>
```

`--job` kills only that job's in-container process and marks only that repo's slot cancelled — sibling repos sharing the analysis id keep running, and the aggregate settles once every slot is terminal.

### 6. Submit Remediation

Remediates findings from a completed analysis. With `--transformation-name` and no `--ids`, it runs that transformation directly against each repo instead, with no findings needed.

```bash
atx ct remote remediation \
  --ids <finding-id1>,<finding-id2> \
  --mode ec2 \
  --stack-name <stack-name> \
  --telemetry "agent=<agent>,executionMode=ec2"
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

Analyses that write reports (`tech-debt-comprehensive`, `agentic-readiness`, `modernization-readiness`, `graviton-readiness`, `aws-health-readiness`, `custom`) upload each repository's report files as `<repo>/artifacts.zip` to your bucket. List and download them:

```bash
atx ct analysis list-artifacts --id <resultId> [--repo <repositoryId>] --json
atx ct analysis get-artifact --id <resultId> --artifact-id <artifactId> [--output <file>]
```

Artifacts appear per repository as each one completes, so a listing during the run can be partial. A repository whose report files collide by name, weren't archived, or can't be read fails with an output error.

### 8. Update Stack

The user or their admin first runs the preview:

```bash
atx ct remote update --mode ec2 --stack-name <stack>
```

After reviewing the changeset, they apply it:

```bash
atx ct remote update --mode ec2 --stack-name <stack> --execute --ack
```

Both preview and execution require Admin credentials: without `--execute`, the command still creates, describes, and deletes a CloudFormation changeset. The agent must not run either form with Executor credentials. With `--execute` it also updates the shared dispatcher and scheduler stacks (`--skip-dispatcher` / `--skip-scheduler` skip them). Update resets a custom `--image-uri` to the default image.

### 9. Teardown

```bash
atx ct remote teardown --mode ec2 --stack-name <stack> --execute --ack
```

Without `--execute`, teardown is a read-only preview: it describes the stack and prints what would be deleted, creates no CloudFormation changeset, and may be run by the agent with Executor credentials. The user or their admin runs the `--execute` command. Execution deletes the instance and its EBS volume (in-flight work on it is lost), the IAM role and instance profile, the dashboard and log group, and the security group if the stack created it. S3 buckets, the KMS key, Secrets Manager tokens, the VPC/subnets, and the shared dispatcher and scheduler stacks persist.

## BYO Instance (Existing EC2)

Use an existing customer-owned EC2 instance instead of provisioning a new stack. The instance must be SSM-managed, run the worker container(s), and carry the `atx-remote-infra=true` tag. Before submitting, the CLI checks SSM registration and the container names, and warns if the instance role fails a permission probe.

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode ec2 \
  --existing-instance <instance-id> \
  --workers 2 \
  --telemetry "agent=<agent>,executionMode=ec2"
```

BYO-specific flags:

- `--existing-instance <id>` — instance ID (mutually exclusive with `--stack-name`/`--tags`)
- `--workers <n>` — container count on the instance (default 1); must match the running containers
- `--ct-output-bucket <name>` — `atx-ct-output-*` bucket (default `atx-ct-output-<accountId>`)
- `--source-bucket <name>` — `atx-source-code-*` bucket (default `atx-source-code-<accountId>`); needed when a source uses the `local` provider
- `--output-bucket <name>` — `atx-custom-output-*` bucket (default `atx-custom-output-<accountId>`); needed for analysis types that write reports

Note: `--image-uri` is NOT available for BYO — it's a `provision` flag only. The instance must already have the AWS Transform — continuous modernization container image running.

Prerequisites for BYO:

- Instance is running and SSM-managed (SSM agent Online)
- Docker installed with the AWS Transform — continuous modernization container(s) running the image's default command, named `atx-ct` for one worker or `atx-ct-1`..`atx-ct-N` for N workers
- Instance tagged with `atx-remote-infra=true` (required by executor policy)
- Instance role equivalent to the provisioned one: `transform-custom:*`, S3 on the `atx-source-code-*` / `atx-ct-output-*` / `atx-custom-output-*` buckets, `secretsmanager:GetSecretValue` on `atx/*`, KMS, and the Security Agent actions
- The account's `atx-ct-output-*`, `atx-custom-output-*`, and `atx-source-code-*` buckets exist

## Error Handling

| Error                                                                                                            | Cause                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Fix                                                                                                                                                                                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Stack "<stack>" is not deployed (status: <status>)`                                                             | No EC2 infra                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | Run `atx ct remote provision --mode ec2 ...`                                                                                                                                                                                                                                                |
| `EC2 stack exposed no InstanceId`                                                                                | Stack exists but instance missing                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Check CFN stack events; may need teardown + reprovision                                                                                                                                                                                                                                     |
| `workerCount must be an integer in [1, 5]`                                                                       | Workers out of range                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use 1-5, or switch to Batch for more parallelism                                                                                                                                                                                                                                            |
| `Stack name "<name>" is not allowed`                                                                             | Name doesn't start with `atx-runner`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use `--stack-name atx-runner-<suffix>` or `--suffix <name>`                                                                                                                                                                                                                                 |
| `--existing-instance is mutually exclusive with --stack-name / --tags`                                           | Both specified                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | Use one or the other                                                                                                                                                                                                                                                                        |
| `Existing-instance prerequisite check failed`                                                                    | Instance not registered or Online with SSM, or the expected `atx-ct` container(s) aren't running                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Verify the SSM agent and its egress, and run containers named to match `--workers`                                                                                                                                                                                                          |
| `Token invalid for source`                                                                                       | Expired/revoked SCM token                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Have the user run `read -s TOKEN && atx ct remote credentials --source <src> --token "$TOKEN" --ack; unset TOKEN` in their own terminal                                                                                                                                                     |
| `No deployed stack found for tags`                                                                               | `--tags` matched no deployed stack                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Verify tags with `atx ct remote detect --mode ec2 --tags <k=v>`, or target by `--stack-name`                                                                                                                                                                                                |
| `Group <id> not found.`                                                                                          | Wrong group ID, or the manifest is on another machine                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              | Check the ID; from another machine pass the `--output-bucket` shown in the submission's poll command                                                                                                                                                                                        |
| `No cancellable job matching "<job>" in group <id>`                                                              | Job already finished, wrong key, or a result id shared by several jobs                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Use the job key (`repo#type`) from `remote status --group <id>`                                                                                                                                                                                                                             |
| `Tag matched multiple deployed stacks`                                                                           | `--tags` matched more than one stack                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | Use `--stack-name`                                                                                                                                                                                                                                                                          |
| `--existing-instance is only supported for --mode ec2.`                                                          | BYO flag with Batch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Use `--mode ec2`                                                                                                                                                                                                                                                                            |
| `Job count <n> exceeds the <cap>-job limit for --mode ec2`                                                       | Too many jobs in one submission                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Split into submissions of at most `<cap>` jobs, or use `--mode batch`                                                                                                                                                                                                                       |
| `createDefaultUserAgentProvider is not a function`                                                               | Stack's Lambda functions predate a fix                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Have the user or their admin update the stack (`atx ct remote update --mode ec2 --stack-name <stack> --execute --ack`), then resubmit                                                                                                                                                       |
| `Dispatcher stack <what> failed: <status> (<resource>: <reason>)`                                                | A dispatcher resource failed to deploy. On `remote provision` the command fails with it. On `remote update` the stack update itself succeeds and the message follows `Warning: the stack update succeeded, but reconciling the dispatcher infrastructure failed:`                                                                                                                                                                                                                                                                                                                  | Fix the cause it names (for example grant the deploy role the missing `dynamodb:CreateTable` permission), then rerun the same command (`remote update --execute` retries the dispatcher)                                                                                                    |
| `The dispatcher's waiting-room table <table> already exists` (`<table>` is `atx-waiting-room-<id>`)              | The table was left from an earlier deploy of this stack (an older CLI's update, or an upgrade that rolled back). `remote provision` and `remote update` clear such a table themselves (they back it up, move its jobs into the table the stack uses, and delete it), so this message means clearing it failed; the reason follows `clearing it failed:`. On `remote provision` the command fails with it. On `remote update` the stack update itself succeeds and the message follows `Warning: the stack update succeeded, but reconciling the dispatcher infrastructure failed:` | Fix the reason it gives if you can and rerun the command. Otherwise follow the steps the message prints: check the table for jobs and back it up if it has any, delete it, and rerun the command; if you backed it up, restore the backup as `AtxDispatcherStack-WaitingRoomTable-restored` |
| `The dispatcher's waiting-room table <table>, kept from an earlier deploy of this stack, is still being deleted` | The kept table's deletion hadn't finished when the command stopped waiting                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Wait until the table is gone, then rerun the command; nothing is lost                                                                                                                                                                                                                       |
| `Did not finish clearing the kept waiting-room table <table>`                                                    | The dispatcher stack changed, or couldn't be checked, while the command was clearing the kept table                                                                                                                                                                                                                                                                                                                                                                                                                                                                                | Don't delete the table (it may now be the stack's own); rerun the command once the stack is no longer updating                                                                                                                                                                              |

A stack deployed by an older CLI keeps its old infrastructure. When a fix needs the stack itself (the CLI or its release notes say to run `remote update`), update it as in step 8.

The dispatcher's waiting-room table is now named `atx-waiting-room-<id>` (it was `AtxDispatcherStack-WaitingRoomTable-<id>`), so a deploy role that limits DynamoDB to `table/atx-*` can provision and update the stack. The next `remote update` or `provision` creates the new table and keeps the old one, and the dispatcher moves any jobs still waiting in the old table into the new one by itself. Tell the user to delete the old table only once the dispatcher's log shows `legacy-waiting-room-drained`.

## Limits

- Account-wide: every analysis and remediation type except security shares one pool of 50 concurrent jobs across all your Batch stacks and EC2 runners (30 while the stacks were last provisioned or updated by an older CLI; `atx ct remote update` raises it). On-demand jobs start before scheduled ones, and scheduled jobs that have waited 4 hours get about half of the free slots.
- Max 5,000 analysis jobs (1,000 remediation jobs) per submission. Split a larger remediation scope into disjoint `--repos` lists within the cap; do not repeat `--sources`, which selects the whole source each time.
- Max 5 workers per instance (default 5)
- Not resumable — `--resume-incomplete` is Batch-only
- EC2 stack names must start with `atx-runner`
- WorkerCount fixed at provision time (change requires redeploy)
- `--execute` flag gates all destructive operations
- Instance types: m5.large to m5.12xlarge
