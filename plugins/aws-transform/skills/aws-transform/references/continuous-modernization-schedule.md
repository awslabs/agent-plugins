---
name: remote-schedule
description: Create and manage scheduled analyses using `atx ct schedule` CLI commands. Two flavors: customer-managed (EventBridge Scheduler firing on EC2 or Batch) and AWS-managed (`--mode aws-managed`, a server-side schedule in the AWS Transform service with no EventBridge and no customer infrastructure). Covers create, list, get, enable, disable, delete, and teardown.
---

# Remote Scheduling (EC2, Batch, and AWS-managed)

Create recurring analyses that fire on a cadence. All management is through `atx ct schedule ...` commands — no raw `aws scheduler` calls. There are two scheduling flavors, chosen by `--mode`:

- **Customer-managed** (`--mode ec2` / `--mode batch`) — an **EventBridge Scheduler** schedule in the customer's account fires on a cadence and dispatches the work to their EC2 (via SSM) or Batch (via Lambda) stack. Requires that compute stack plus the singleton scheduler stack (see Prerequisites).
- **AWS-managed** (`--mode aws-managed`) — a **server-side schedule** stored in the AWS Transform service. There is **no EventBridge schedule and no customer infrastructure**; the AWS-managed fleet runs each fire. Requires an `--execution-role` the Scheduled Analysis Runner assumes at fire time. See also [continuous-modernization-aws-managed-execution.md](continuous-modernization-aws-managed-execution.md) for the one-shot form.

`schedule list/get/enable/disable/delete` work on both flavors — the CLI detects which flavor a schedule is and does the right thing (EventBridge plus AWS Transform service sync for customer-managed; AWS Transform service only for AWS-managed).

**Schedules run analyses only.** Scheduled remediations are not supported: `--job-type remediation` is rejected with guidance. For a one-off remediation use [remote Batch execution](continuous-modernization-batch-execution.md) or [remote EC2 execution](continuous-modernization-ec2-execution.md).

## Telemetry

Include `--telemetry` when creating a schedule:

```
--telemetry "agent=<agent>,executionMode=<ec2|batch|aws-managed>"
```

- `agent` — the AI assistant name (lowercase, no spaces): kiro, claude, amazonq, copilot
- `executionMode` — `ec2` for EC2 schedules, `batch` for Batch schedules, `aws-managed` for AWS-managed schedules

The CLI appends `invocationMethod=scheduled` itself, so do not pass it.

If the user explicitly opts out of telemetry, omit `--telemetry` for the rest of the session.

## When to Use

- "schedule a weekly tech-debt scan"
- "run analysis every Monday"
- "automate the scan nightly"
- "audit my repos monthly for security issues"
- "track code quality over time with recurring scans"

**Not for:**

- One-shot immediate analysis → use `atx ct remote analysis`
- Any scheduled remediation → not supported (see above)

**Scheduled analyses always run remotely — never via local cron.** A customer-managed schedule is dispatched by EventBridge Scheduler to a provisioned EC2 or Batch stack; an AWS-managed schedule runs server-side on the AWS-managed fleet. Either way, do NOT set up, suggest, or write a local cron entry (`crontab`, `cron.d`, `launchd`, Task Scheduler, a systemd timer, or a shell loop on the customer's machine) to drive `atx ct` on a cadence. A local cron job depends on the customer's laptop being awake and authenticated, produces no schedule record the CLI can list/enable/disable, and creates no anchor analysis — so the run is invisible to `atx ct schedule list` and to the linkage model below.

If the customer asks for local scheduling, route them to a real schedule instead — pick the flavor by whether they want to own infrastructure. **No infrastructure:** `atx ct schedule create --mode aws-managed --execution-role <arn> ...` (server-side; nothing to provision). **Customer-owned compute:** ensure an EC2/Batch stack first (`atx ct remote provision --mode ec2|batch --execute --ack`), then `atx ct schedule create --mode ec2|batch ...`. Never offer local cron as a fallback or workaround.

## Prerequisites

> **AWS-managed (`--mode aws-managed`) skips almost all of this.** There is no compute stack, no scheduler stack, and no provisioning — you only need a registered SCM source and an `--execution-role` ARN. `AWS_REGION` is not required — pass `--region` to choose which AWS Transform supported region the managed workload runs in (defaults to your ambient region). The rest of this section applies to the **customer-managed** (EC2/Batch) flavor.

### Environment

```bash
export AWS_REGION=<supported-region>     # required for EC2/Batch schedules — the region your stacks are deployed in (e.g. us-east-1)
```

### Infrastructure Required

1. **EC2 or Batch stack deployed** — `atx ct remote detect --mode ec2|batch` shows a deployed stack
2. **Scheduler infrastructure** — provisioned automatically by `atx ct remote provision` (see below)
3. **Source registered** — `atx ct source add`, plus `atx ct remote credentials` for SCM providers

There is **no separate `schedule setup` command**. `atx ct remote provision --mode <mode> --execute --ack` deploys the compute stack and ensures the singleton `atx-scheduler` stack (the `AtxSchedulerInvocationRole` and the `atx-ct` schedule group) in the same run. Relevant provision flags:

- `--skip-scheduler` — skip the scheduler-infrastructure ensure
- `--existing-scheduler-role-arn <arn>` — reference a pre-created `AtxSchedulerInvocationRole` instead of creating one (admin owns its mode policies)

The scheduler stack is mode-agnostic: provisioning a second mode updates the same stack, so EC2 and Batch schedules coexist.

### Permission Model

- **Admin** — `remote provision` (which ensures the scheduler stack), `schedule teardown`
- **Executor** — `schedule create`, `list`, `get`, `enable`, `disable`, `delete`

## Workflow

### 0. Pick the flavor FIRST

Before anything else, decide which schedule flavor the request calls for — this determines the whole flow:

- **No infrastructure / "don't want to manage or provision anything" / no existing EC2 or Batch stack → AWS-managed.** Skip the EC2/Batch create below and go straight to [§1b (AWS-managed)](#1b-create-an-aws-managed-schedule---mode-aws-managed). It is server-side (no EventBridge, no stack, nothing to provision) and just needs `--execution-role`. Do NOT present EC2/Batch or a provisioning step for these requests, and do NOT call EC2/Batch "the easy path that provisions nothing" — they deploy a customer-owned stack.
- **Customer wants their own compute (EC2/Batch), or a stack is already deployed → customer-managed.** Use §1 below.

### 1. Create a Schedule (customer-managed: EC2 / Batch)

```bash
atx ct schedule create \
  --name weekly-techdebt \
  --mode batch \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --recurrence weekly:MONDAY \
  --telemetry "agent=kiro,executionMode=batch"
```

EC2 is identical apart from the mode and telemetry:

```bash
atx ct schedule create \
  --name nightly-techdebt \
  --mode ec2 \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --recurrence daily \
  --telemetry "agent=kiro,executionMode=ec2"
```

The CLI auto-detects the deployed stack for the given mode — there is no `--stack-name` on `create`.

**Required flags:**

- `--name <name>` — unique within the `atx-ct` group
- `--mode ec2|batch` — which compute to target
- `--recurrence <recurrence>` — the cadence (see below)

**Cadence — `--recurrence`:**

| Value                     | Meaning                                      |
| ------------------------- | -------------------------------------------- |
| `daily`                   | every day                                    |
| `weekly:<MONDAY..SUNDAY>` | every week on that day, e.g. `weekly:FRIDAY` |
| `monthly:<1..28>`         | every month on that day-of-month             |

The fire **time** is not a flag: it resolves to about 2 minutes from now, in the operator's local wall clock, and is DST-stable. So "daily" means "every day at roughly this time of day". Capped at day 28 for `monthly` so every month has the date.

**Job flags** (mirror `remote analysis`, so the two surfaces cannot drift):

- `--type <type>` — a single analysis type: `rapid-techdebt-analysis`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `custom`. A schedule runs ONE type; `--types` (plural) is removed and is an error.
- `--sources <src1,src2>` — source name(s)
- `--repos <src>::<repo>,...` — explicit repo slugs (omit to cover all repos in `--sources`)
- `--transformation-name <name>` — required with `--type custom`
- `-g, --configuration <config>` — only valid with `--transformation-name`

**Other flags:**

- `--provider github|gitlab|bitbucket|local` — default `github`. SCM providers stage clone-token secrets. `local` zips and uploads the source directory **at create time**, so every fire analyzes that uploaded snapshot (re-create the schedule to refresh it).
- `--description <text>` — human-readable note stored on the schedule
- `--region <region>` — defaults to `AWS_REGION`
- `--json` — machine-readable output

**Not supported on schedules:**

- `--labels` — hidden from `--help` and registered only so the CLI can reject it with tailored guidance: label filtering is resolved against the backend at submit time and cannot be re-resolved at fire time. List repos explicitly via `--repos` instead.
- `--job-type remediation` — rejected; schedules run analyses only.

### 1b. Create an AWS-managed Schedule (`--mode aws-managed`)

An AWS-managed schedule is a **server-side schedule** stored in the AWS Transform service — there is no EventBridge schedule, no scheduler stack, and no customer compute. The AWS-managed fleet runs each fire. This is the no-infrastructure scheduling option.

```bash
atx ct schedule create \
  --name nightly-managed \
  --mode aws-managed \
  --execution-role arn:aws:iam::<acct>:role/<ScheduledAnalysisRunnerRole> \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --recurrence daily \
  --telemetry "agent=kiro,executionMode=aws-managed"
```

**Required (in addition to `--name` and `--recurrence`):**

- `--mode aws-managed`
- `--execution-role <arn>` — the IAM role the **Scheduled Analysis Runner** assumes at fire time. Required for this mode; there is no default.

**Execution role requirements.** The `--execution-role` ARN must be set up correctly or schedule creation fails with a validation error:

- **Caller needs `iam:PassRole`.** The identity creating the schedule must have `iam:PassRole` permission for the execution-role ARN — it is _passing_ that role to the scheduled analysis. Without `iam:PassRole`, creation is rejected.
- **Role trust policy must allow the AWS Transform Custom service.** The execution role's trust policy must let the service principal **`transform-custom.amazonaws.com`** assume it (an `sts:AssumeRole` statement with that principal). If the trust policy omits `transform-custom.amazonaws.com`, the service cannot assume the role at fire time and creation is rejected.
- **Role permissions (recommended minimum).** The execution role should grant at least:
  - the AWS-managed policy **`arn:aws:iam::aws:policy/AWSTransformCustomFullAccess`**, and
  - **Secrets Manager read** for the SCM personal-access-token secrets the source stored in the customer account (under the `atx/*` prefix), so the fired analysis can fetch clone credentials:

    ```json
    {
      "Sid": "SecretsManagerScmTokenAccess",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": ["arn:aws:secretsmanager:<region>:<account-id>:secret:atx/*"]
    }
    ```

  Scope `<region>`/`<account-id>` to the account and region where the source's secrets live. Without the `atx/*` Secrets Manager read, fires that clone from an SCM provider fail to retrieve the token.

**Recurrence:** same `--recurrence` grammar as the other modes — `daily`, `weekly:<MONDAY..SUNDAY>`, `monthly:<1..28>`. AWS-managed schedules fire on **UTC presets only**.

**Region:** pass `--region <region>` to run the fired workloads in a specific AWS Transform supported region (defaults to the ambient `AWS_REGION`).

**Rejected in this mode (each with tailored guidance):**

| Flag                           | Why                                                           |
| ------------------------------ | ------------------------------------------------------------- |
| `--stack-name`                 | No customer stack — the managed fleet runs the analysis       |
| `--provider`                   | The provider is resolved from the source registration         |
| `--job-type`                   | Schedules run analyses only                                   |
| `--type custom`                | Managed fleet does not install custom transformation packages |
| `--transformation-name` / `-g` | Only valid with `--type custom`, unsupported here             |
| local-provider source          | Managed fleet cannot fetch local bundles                      |

### 2. List Schedules

```bash
atx ct schedule list
```

Lists **both** flavors together as scheduled-analysis records — a `ListAnalyses` query scoped to scheduled runs, **not** an EventBridge schedule list. Each entry shows the same fields as `schedule get` (Id, Name, Infrastructure, Analysis type, Repositories, Recurrence, State, Next run, Created/Updated). `--json` emits an array of the raw analysis-wire records. `Next run` is server-populated for AWS-managed schedules only; customer-managed entries omit it.

### 3. Get Schedule Details

```bash
atx ct schedule get <sched-id>
```

Prints the scheduled-analysis record: Id, Name, Infrastructure (`awsManaged` | `customerManaged`), Analysis type, Repositories, Recurrence, State, Next run (AWS-managed only), and Created/Updated timestamps. `--json` emits the raw analysis-wire record (same shape as `atx ct analysis get --json`). Pass the `sched-` id shown by `schedule list`.

### 4. Disable / Enable

```bash
atx ct schedule disable <sched-id>   # pause (idempotent)
atx ct schedule enable  <sched-id>   # resume (idempotent)
```

### 5. Delete

```bash
atx ct schedule delete <sched-id>
```

Removes the schedule from the `atx-ct` group **and deletes the schedule's anchor analysis** (the parent record described below), reporting `Schedule anchor analysis <id> deleted.` If the anchor cannot be deleted, the CLI says so rather than claiming success. Already-running fires are unaffected.

### 6. Teardown Scheduler Infrastructure (Admin)

```bash
atx ct schedule teardown --execute

# Non-interactive (CI)
atx ct schedule teardown --execute --yes
```

Omit `--execute` for a preview. `--stack-name <name>` overrides the stack. This deletes the scheduler role and the `atx-ct` group stack, removing every schedule in the group. Note this uses `--yes` (not `--ack`) to skip the consent prompt.

## How Scheduled Runs Are Recorded

Understanding this makes the status commands make sense:

- **Creating a schedule** pre-creates one **anchor** (parent) analysis record that represents the schedule itself. It is a template — it never runs directly and never has findings.
- **Each fire** creates ONE **shared child** analysis for that fire, covering every repo in the schedule, and the child carries the schedule linkage (parent id, fire id, schedule name, cadence). This holds for both EC2 and Batch.
- `schedule delete` deletes the anchor; the children (which do carry findings) are left alone.

## Verifying a Schedule Fires

After a fire, check results the same way as a manual submission:

```bash
# Batch: list recent batches, then drill in
atx ct remote status --stack-name <stack>
atx ct remote status --batch <batch-id> --stack-name <stack>

# EC2: check the fire's group
atx ct remote status --group <ec2-group-id>
```

The batch/group id is generated per fire — look for the submission created at the scheduled time. Findings are then queryable with `atx ct analysis get --id <resultId> --json`.

**AWS-managed schedules** have no batch/group and no `remote status` (that command is stack-scoped). Verify them through the analysis records instead: `atx ct schedule list` shows the server-computed `nextRunAt`, and each fire's child analysis is queryable with `atx ct analysis get --id <analysis-id> --json` (then `atx ct findings list --analysis-id <id> --json`).

## Routing Customer Intent

| Customer says                                     | Route to                                                                      |
| ------------------------------------------------- | ----------------------------------------------------------------------------- |
| "weekly tech-debt scan", "monthly security audit" | `schedule create --recurrence weekly:MONDAY` / `monthly:1`                    |
| "run it nightly"                                  | `schedule create --recurrence daily`                                          |
| "remediate these findings on Friday"              | NOT schedulable — run `atx ct remote remediation` when they're ready          |
| "scan AND auto-fix on a cadence"                  | Schedule the analysis; remediation stays a manual `remote remediation` step   |
| Customer supplies their own cron                  | Map it to the nearest `--recurrence` (daily / weekly:`<DAY>` / monthly:`<N>`) |

## Error Handling

| Error                                                                           | Cause                                                 | Fix                                                                                                  |
| ------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Guidance to `atx ct remote provision`                                           | Compute or scheduler infra missing                    | `atx ct remote provision --mode ec2\|batch --execute --ack`                                          |
| `--recurrence is required`                                                      | Neither cadence flag given                            | Add `--recurrence daily\|weekly:<DAY>\|monthly:<N>`                                                  |
| `--types has been removed`                                                      | Plural flag used                                      | Use `--type <type>` — a schedule runs a single type                                                  |
| `--job-type remediation is not supported`                                       | Tried to schedule a remediation                       | Schedule the analysis; run remediation with `atx ct remote remediation`                              |
| `--labels is not schedulable yet`                                               | Label filter given (flag is hidden)                   | List repos explicitly with `--repos`                                                                 |
| Schedule name already exists                                                    | Duplicate name in the `atx-ct` group                  | Pick a unique `--name`, or delete the existing one                                                   |
| Schedule not found                                                              | Wrong name or already deleted                         | `atx ct schedule list`                                                                               |
| Local sources require an S3 source bucket                                       | Stack exposes no `atx-source-code-*`                  | Re-provision the stack, or use an SCM provider                                                       |
| Token not available                                                             | Clone credential not staged                           | `atx ct remote credentials --source <src> --token <token> --ack`                                     |
| `--execution-role is required for --mode aws-managed`                           | Missing role on an AWS-managed schedule               | Add `--execution-role <arn>` (the Scheduled Analysis Runner role)                                    |
| Not authorized to perform `iam:PassRole`                                        | Caller lacks PassRole for the execution role          | Grant the caller `iam:PassRole` for the `--execution-role` ARN                                       |
| Execution role cannot be assumed / invalid trust policy                         | Role trust policy omits the service principal         | Add `transform-custom.amazonaws.com` as a trusted principal (`sts:AssumeRole`) on the execution role |
| `--stack-name`/`--provider`/`--job-type` not supported for `--mode aws-managed` | Customer-managed flag used on an AWS-managed schedule | Drop the flag; use `--recurrence` for cadence                                                        |

## Limits

- Analyses only — no scheduled remediations
- One analysis type per schedule (`--type`, singular)
- Cadence is `--recurrence` (`daily`/`weekly:<DAY>`/`monthly:<1..28>`); `at()` one-shots are never supported
- `--labels` is not supported on schedules
- **Customer-managed (EC2/Batch):** one schedule group (`atx-ct`) per account/region; one singleton `atx-scheduler` stack serving both modes; fire time is ~2 minutes from creation in the operator's local zone; EC2 mode needs a running EC2 stack and Batch mode a deployed Batch stack; max 250 jobs per fire (same fan-out ceiling as a manual submission)
- **AWS-managed:** no customer infrastructure (no scheduler/compute stack); requires `--execution-role`; fires on UTC presets only; `--region` selects the workload region (any AWS Transform supported region); no `--stack-name`/`--provider`/`--job-type`/`--type custom`; no local-provider sources
- Remote only — local cron / systemd timers / Task Scheduler are never a substitute (for either flavor)
