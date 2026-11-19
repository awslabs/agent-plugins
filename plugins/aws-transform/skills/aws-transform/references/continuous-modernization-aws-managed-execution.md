---
name: remote-aws-managed
description: Run analysis remotely on the AWS-managed fleet using `atx ct remote analysis --mode aws-managed` — no customer infrastructure to provision or tear down. The AWS Transform service accepts the submission and runs it on its managed fleet. Covers submission, input flags (including `--region`), output formats, status, and the flags that are rejected in this mode.
---

# Remote AWS-Managed Execution

Run analysis remotely **without deploying or managing any customer infrastructure**. With `--mode aws-managed`, the submission goes straight to the AWS Transform service, which runs the analysis on its own managed fleet. There is no EC2 instance, no Batch stack, no VPC/subnets, no provisioning, and no teardown — the create call _is_ the run.

This is the third remote compute option alongside [EC2](continuous-modernization-ec2-execution.md) and [Batch](continuous-modernization-batch-execution.md). Unlike those two — which run on infrastructure the customer deploys into their own account — aws-managed runs on AWS-managed compute, so it is the fastest path to a remote run when the customer does not want to own any infrastructure.

## When to Use

- Customer wants a remote run but does **not** want to provision or manage any infrastructure (no EC2 instance, no Batch stack, no VPC work)
- Fastest path to a remote analysis — no `remote provision` step, no Admin role, no CloudFormation
- The customer says "run it on AWS but I don't want to manage anything", "just run it for me", "no infrastructure", or "managed"

**Not for:**

- Remediation — `--mode aws-managed` is **rejected** for `remote remediation`. Use [EC2](continuous-modernization-ec2-execution.md) or [Batch](continuous-modernization-batch-execution.md).
- A custom analysis that needs `-g`/`--configuration` — custom analysis (`--type custom --transformation-name <name>`) runs on the managed fleet, but `--configuration` is rejected in this mode. Use EC2/Batch for that.
- Local-provider sources — the managed fleet cannot fetch local bundles. Use EC2/Batch (which upload and run from S3), or a registered SCM source.

For persistent warm compute the customer can SSM into, use [EC2](continuous-modernization-ec2-execution.md). For large one-shot fan-out on customer-owned Fargate, use [Batch](continuous-modernization-batch-execution.md).

## Telemetry

Include `--telemetry` on every `atx ct remote analysis --mode aws-managed`:

```
--telemetry "agent=<agent>,executionMode=aws-managed"
```

- `agent` — the AI assistant name (lowercase, no spaces): kiro, claude, amazonq, copilot
- `executionMode` — `aws-managed`

If the user explicitly opts out of telemetry, omit `--telemetry` for the rest of the session.

## Prerequisites

There is **no provisioning step and no Admin role** for aws-managed — that is the whole point. You need:

1. **A registered SCM source.** Register with its clone token so the managed fleet can fetch the repos. The user runs these in their own terminal (`read -s` keeps the token out of this chat; see the `/source` skill):

   ```bash
   # GitHub / GitLab
   read -s TOKEN && atx ct source add --name <src> --provider github|gitlab --org <org> --token "$TOKEN"; unset TOKEN

   # Bitbucket Cloud
   read -s TOKEN && atx ct source add --name <src> --provider bitbucket --org <workspace> --token "$TOKEN" \
     [--username <bitbucket-username>] [--email <account-email>]; unset TOKEN

   # Self-hosted GitLab or Bitbucket Data Center (add --url)
   read -s TOKEN && atx ct source add --name <src> --provider gitlab|bitbucket --org <org> --token "$TOKEN" \
     --url https://gitlab.mycompany.com; unset TOKEN

   # Discover repos
   atx ct discovery scan --source <src>
   ```

   `local`-provider sources are **not** supported in this mode (see Error Handling).

2. **Executor credentials** for submitting the analysis. No `remote provision`, `network create`, or Admin CloudFormation permissions are needed.

**Region:** the AWS-managed fleet is available in every AWS Transform supported region, so you can choose where the workload runs. Pass `--region <region>` to run in a specific region; if you omit it, the run uses your ambient region (`AWS_REGION`, else the AWS SDK default).

## Workflow

### Submit Analysis

```bash
atx ct remote analysis \
  --type rapid-techdebt-analysis \
  --sources <src> \
  --mode aws-managed \
  --telemetry "agent=<agent>,executionMode=aws-managed"
```

The create call is the submission — the AWS Transform service runs it on its managed fleet and returns an analysis ID immediately (there is no separate dispatch or preflight).

A custom analysis runs the same way, with the transformation definition to run:

```bash
atx ct remote analysis \
  --type custom \
  --transformation-name <transformation-name> \
  --sources <src> \
  --mode aws-managed \
  --telemetry "agent=<agent>,executionMode=aws-managed"
```

**Supported flags:**

- `--type <type>` — exactly ONE analysis type per run: `rapid-techdebt-analysis`, `tech-debt-comprehensive`, `security`, `agentic-readiness`, `modernization-readiness`, `graviton-readiness`, `aws-health-readiness`, or `custom`.
- `--transformation-name <name>` — required with `--type custom` (and only valid with it): the transformation definition to run, in analysis mode (see [analysis](continuous-modernization-analysis.md#custom-analysis))
- `--sources <src1,src2>` — source name(s)
- `--repos <src>::<repo>,...` — specific fully-qualified repo slugs (omit to cover all repos in `--sources`)
- `--labels <java,spring>` — filter repos by labels (AND semantics)
- `--region <region>` — run the workload in a specific AWS Transform supported region (defaults to the ambient `AWS_REGION`)
- `--display-name <name>` — human-readable name shown in `atx ct analysis get` and `analysis list`
- `--telemetry "agent=<agent>,executionMode=aws-managed"`
- `--json` — machine-readable output (see Output Formats)

Provide at least one of `--sources` or `--repos`.

**Rejected flags (each produces a tailored error):**

| Flag                     | Why it is rejected                                                                  |
| ------------------------ | ----------------------------------------------------------------------------------- |
| `--stack-name`           | No customer stack — the managed fleet runs the analysis                             |
| `--tags`                 | No customer infrastructure to tag (see note on settings-based tags below)           |
| `--existing-instance`    | No customer instance in this mode                                                   |
| `--batch-name`           | No Batch submission in this mode                                                    |
| `--workers`              | No customer instance in this mode                                                   |
| `--resume-incomplete`    | No batch manifest to resume — submit a fresh run for the repos that didn't complete |
| `-g` / `--configuration` | Not supported in this mode — run a custom analysis that needs it on EC2/Batch       |
| local-provider source    | Managed fleet cannot fetch local bundles — use EC2/Batch or an SCM source           |

> **Settings-based tags still apply.** The `--tags` _flag_ is rejected, but if `~/.aws/atx/settings.json` defines `applyTags`, those default tags are still attached to the analysis (and propagate to its findings). Only the explicit CLI flag is unavailable in this mode.

### Output

`remote analysis --mode aws-managed` returns an analysis id and a poll command. In `--json` the key is `analysisId` (not the EC2 `groupId` or Batch `batchId`). Poll with `atx ct analysis get --id <id> --json`.

### Check Status and Get Results

There is no `remote status --group`/`--batch` for aws-managed (those are stack-scoped). Poll the analysis record directly:

```bash
atx ct analysis get --id <analysis-id> --json
```

`status` is lowercase: `running` → `complete` → then read findings. Once complete:

```bash
atx ct findings list --analysis-id <analysis-id> --json
```

See [continuous-modernization-analysis.md](continuous-modernization-analysis.md) for status semantics and the "0 findings" follow-up guidance.

## Scheduling on the Managed Fleet

aws-managed also has a recurring form: `atx ct schedule create --mode aws-managed` creates a server-side schedule (no EventBridge, no customer stack) that fires analyses on the managed fleet. It requires an `--execution-role`. See [continuous-modernization-schedule.md](continuous-modernization-schedule.md).

## Error Handling

| Error                                                                     | Cause                                   | Fix                                                                        |
| ------------------------------------------------------------------------- | --------------------------------------- | -------------------------------------------------------------------------- |
| `--batch-name is not used with --mode aws-managed`                        | Passed a Batch-only flag                | Drop `--batch-name`                                                        |
| `--stack-name and --tags are not used with --mode aws-managed`            | Passed customer-infra flags             | Drop `--stack-name` / `--tags`                                             |
| `--existing-instance is not used with --mode aws-managed`                 | Passed the BYO-EC2 flag                 | Drop `--existing-instance` or switch to `--mode ec2`                       |
| `--workers is not used with --mode aws-managed`                           | Passed the BYO-EC2 worker count         | Drop `--workers`                                                           |
| `--resume-incomplete is only supported for --mode batch`                  | Tried to resume an aws-managed run      | Submit a fresh `--mode aws-managed` run for the repos that didn't complete |
| `Repo "<repo>" must be fully qualified as source::repoName.`              | Bare repo name in `--repos`             | Use `<source>::<repo>`                                                     |
| `Source "<src>" not found`                                                | Unregistered source                     | `atx ct source add --name <src> ...`                                       |
| `--configuration is not supported for --mode aws-managed ...`             | `-g`/`--configuration` passed           | Drop it, or run the custom analysis on `--mode ec2` or `--mode batch`      |
| `--transformation-name is required when --type is custom.`                | `--type custom` without a TD            | Add `--transformation-name <name>`                                         |
| `--transformation-name can only be used with --type custom.`              | TD passed with a built-in type          | Drop `--transformation-name`, or use `--type custom`                       |
| `--mode aws-managed does not support local-provider sources`              | Source registered as `local`            | Use an SCM source, or run on `--mode ec2`/`--mode batch`                   |
| `Provide --sources or --repos ...`                                        | No repos identified                     | Add `--sources <src>` or `--repos <src>::<repo>`                           |
| `Repo count <n> exceeds the 5000-repo limit for a single analysis record` | Too many repos in one submission        | Split into batches of ≤5,000 repos via `--repos`                           |
| `--mode aws-managed is not supported for remote remediation`              | Tried to remediate on the managed fleet | Remediate with `--mode ec2` or `--mode batch`                              |

## Limits

- Analyses only — no remediation on the managed fleet (use EC2/Batch)
- One analysis type per run (`--type`, singular)
- Max 5,000 repos per analysis record (split larger scopes via `--repos`)
- Custom analysis is supported, but without `-g`/`--configuration`
- No local-provider sources
- No `--stack-name`/`--tags`/`--existing-instance`/`--batch-name`/`--workers`/`--resume-incomplete` (no customer infrastructure); `--region` IS supported — the managed fleet runs in any AWS Transform supported region
- No customer infrastructure — nothing to provision, update, or tear down
