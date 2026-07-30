---
name: remote-schedule
description: Create and manage scheduled analyses using `atx ct schedule` CLI commands. Uses EventBridge Scheduler to fire recurring analyses on EC2 or Batch (Fargate). Covers create, list, get, enable, disable, delete, and teardown.
---

# Remote Scheduling (EC2 and Batch)

Create recurring analyses using EventBridge Scheduler. A schedule fires on a cadence and dispatches the work to either EC2 (via SSM) or Batch (via Lambda). All management is through `atx ct schedule ...` commands — no raw `aws scheduler` calls.

**Schedules run analyses only.** Scheduled remediations are not supported: `--job-type remediation` is rejected with guidance. For a one-off remediation use [remote Batch execution](continuous-modernization-batch-execution.md) or [remote EC2 execution](continuous-modernization-ec2-execution.md).

## Telemetry

Include `--telemetry` when creating a schedule:

```
--telemetry "agent=<agent>,executionMode=<ec2|batch>"
```

- `agent` — the AI assistant name (lowercase, no spaces): kiro, claude, amazonq, copilot
- `executionMode` — `ec2` for EC2 schedules, `batch` for Batch schedules

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

**Scheduled analyses run on remote infrastructure only.** They are dispatched by EventBridge Scheduler to a provisioned EC2 or Batch stack. Do NOT set up, suggest, or write a local cron entry (`crontab`, `cron.d`, `launchd`, Task Scheduler, a systemd timer, or a shell loop on the customer's machine) to drive `atx ct` on a cadence. A local cron job depends on the customer's laptop being awake and authenticated, produces no schedule record the CLI can list/enable/disable, and creates no anchor analysis — so the run is invisible to `atx ct schedule list` and to the linkage model below.

If the customer asks for local scheduling, or has no remote stack yet, say that recurring analyses require remote infrastructure and route them to `atx ct remote provision --mode ec2|batch --execute --ack` first. Never offer local cron as a fallback or workaround.

## Prerequisites

### Environment

```bash
export AWS_REGION=<supported-region>     # required — the region your stacks are deployed in (e.g. us-east-1)
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

### 1. Create a Schedule

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

**Power-user escape hatch (hidden from `--help`):** `--expression "cron(...)"` takes a raw 6-field EventBridge cron, and `--timezone <IANA>` overrides the zone. Pass exactly one of `--recurrence` / `--expression`. One-shot `at(...)` expressions are **not** supported — schedules are recurring by definition. `--recurrence` defaults the timezone to the operator's local zone; `--expression` defaults to UTC. Prefer `--recurrence` unless the customer explicitly needs a cron they already have.

### 2. List Schedules

```bash
atx ct schedule list
```

Shows every schedule in the `atx-ct` group. `--json` for machine-readable output.

### 3. Get Schedule Details

```bash
atx ct schedule get <name>
```

Prints name, group, ARN, mode, job type, cron expression, timezone, state, target ARN, and created/updated timestamps. Human output shows the resolved **expression**; `--json` also carries the typed recurrence.

### 4. Disable / Enable

```bash
atx ct schedule disable <name>   # pause (idempotent)
atx ct schedule enable  <name>   # resume (idempotent)
```

### 5. Delete

```bash
atx ct schedule delete <name>
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

## Routing Customer Intent

| Customer says                                     | Route to                                                                    |
| ------------------------------------------------- | --------------------------------------------------------------------------- |
| "weekly tech-debt scan", "monthly security audit" | `schedule create --recurrence weekly:MONDAY` / `monthly:1`                  |
| "run it nightly"                                  | `schedule create --recurrence daily`                                        |
| "remediate these findings on Friday"              | NOT schedulable — run `atx ct remote remediation` when they're ready        |
| "scan AND auto-fix on a cadence"                  | Schedule the analysis; remediation stays a manual `remote remediation` step |
| Customer supplies their own cron                  | `--expression "cron(...)"` (hidden flag; cron only, no `at()`)              |

## Error Handling

| Error                                                  | Cause                                | Fix                                                                     |
| ------------------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------------- |
| Guidance to `atx ct remote provision`                  | Compute or scheduler infra missing   | `atx ct remote provision --mode ec2\|batch --execute --ack`             |
| `--recurrence is required`                             | Neither cadence flag given           | Add `--recurrence daily\|weekly:<DAY>\|monthly:<N>`                     |
| `provide exactly one of --recurrence and --expression` | Both given                           | Keep one                                                                |
| `--types has been removed`                             | Plural flag used                     | Use `--type <type>` — a schedule runs a single type                     |
| `--job-type remediation is not supported`              | Tried to schedule a remediation      | Schedule the analysis; run remediation with `atx ct remote remediation` |
| `--labels is not schedulable yet`                      | Label filter given (flag is hidden)  | List repos explicitly with `--repos`                                    |
| Schedule name already exists                           | Duplicate name in the `atx-ct` group | Pick a unique `--name`, or delete the existing one                      |
| Schedule not found                                     | Wrong name or already deleted        | `atx ct schedule list`                                                  |
| Local sources require an S3 source bucket              | Stack exposes no `atx-source-code-*` | Re-provision the stack, or use an SCM provider                          |
| Token not available                                    | Clone credential not staged          | `atx ct remote credentials --source <src> --token <token> --ack`        |

## Limits

- Analyses only — no scheduled remediations
- One analysis type per schedule (`--type`, singular)
- One schedule group (`atx-ct`) per account/region; one singleton `atx-scheduler` stack serving both modes
- Cadence is `--recurrence`, or a raw `cron(...)` via the hidden `--expression`; `at()` one-shots are not supported
- Fire time is always ~2 minutes from creation time (not selectable)
- `--labels` is not supported on schedules
- Max 250 jobs per fire (same fan-out ceiling as a manual submission)
- EC2 mode needs a running EC2 stack; Batch mode needs a deployed Batch stack
- Remote infrastructure only — local cron / systemd timers / Task Scheduler are never a substitute
