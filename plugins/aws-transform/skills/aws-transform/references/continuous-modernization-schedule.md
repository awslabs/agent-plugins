# continuous modernization Recurring Analysis Scheduling

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` -- the AI assistant driving this session (lowercase, no spaces). Use the real assistant name -- e.g. kiro, claude, amazonq, copilot.
- `executionMode` -- `ec2` for the EC2 path, `fargate` for the Batch path

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

Create and manage scheduled AWS Transform - continuous modernization (continuous modernization) work using AWS EventBridge Scheduler. Schedules fire on a cron expression (or one-shot via `at()`) and dispatch the work to either:

- **EC2 path**: SSM SendCommand to the customer's running atx-ct container, or
- **Batch path**: Lambda invocation of `atx-trigger-batch-jobs` to submit a Fargate job

The skill supports two job types:

- **Analysis** (`JOB_TYPE=analysis`, default): runs `atx ct analysis run`, persists findings to the backend, uploads artifacts (for analysis types that produce code changes). Customer reviews and acts on findings later.
- **Remediation** (`JOB_TYPE=remediation`): runs `atx ct remediation create` against a pre-determined target (specific finding IDs OR a transformation+repo combo). Customer captures the target NOW (before scheduling); the schedule fires it later.

Either way, results land in the same place as a manual run -- findings in the backend, PRs/MRs pushed by the backend (github/gitlab/bitbucket), or `code.zip` uploaded to S3 (local provider).

## When to Use This Skill

The customer's intent involves recurring or delayed work on a schedule:

- "schedule this analysis to run weekly"
- "automate the scan, run it every Monday"
- "set up a cron job for tech-debt analysis"
- "I want this to run nightly / daily / monthly"
- "apply these fixes Friday at 9am"
- "delay the remediation until off-hours"
- "schedule the Java upgrade for next week"
- "I have findings to fix -- schedule it for tonight"

**This is NOT for:**

- One-shot analyses → use [continuous-modernization-analysis](continuous-modernization-analysis.md), [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md), or [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md)
- Local cron on the customer's laptop -- use the OS's native cron; no AWS resources needed

## Choose the Path

Ask the customer (or infer from context):

1. **EC2 path** -- fires on a long-running EC2 instance (one container, persistent). Best when the customer already has an EC2 stack from `continuous-modernization-ec2-execution` and wants to reuse it.
2. **Batch path** -- fires a Fargate job per scheduled invocation. Best when the customer uses `continuous-modernization-batch-execution` and prefers serverless / fan-out execution.

```bash
PATH_TYPE="${PATH_TYPE:-ec2}"   # or "batch"
```

If the customer has both available and didn't specify, default to whichever they used most recently for one-shot analyses.

## Choosing the Right Mode

The skill supports two job types. Match customer intent before committing.

### Mode 1: Scheduled Analysis (`JOB_TYPE=analysis`)

Use when the customer wants **recurring visibility** into their codebase health. Findings populate the backend; the customer reviews and acts on them later (manually or via a separate scheduled remediation).

Customer-intent signals:

- "schedule a weekly tech-debt scan"
- "run analysis every Monday"
- "track our code quality over time"
- "audit my repos monthly for security issues"
- "find new vulnerabilities each week"

Setup: customer chooses an analysis type and cadence. Schedule fires `atx ct analysis run` and uploads artifacts (for analysis types that produce code changes).

### Mode 2: Scheduled Remediation (`JOB_TYPE=remediation`)

Use when the customer wants **delayed action** on a known set of issues. They've reviewed findings (or know the transformation to apply) and want to fire the remediation later -- e.g., during a maintenance window or after a code freeze.

Customer-intent signals:

- "apply these fixes Friday at 9am"
- "schedule the Java upgrade for next week"
- "delay the remediation until off-hours"
- "run AWS/java-version-upgrade on these repos every Sunday night"
- "fix these 50 findings tonight"

Two sub-modes:

- **`REMEDIATION_MODE=findings`**: customer provides explicit finding IDs (captured from a prior `atx ct findings list`). Schedule fires with those IDs hardcoded. Best for one-shot delayed remediation.
  - Default: findings must have `.fix` populated (typical of `tech-debt-quick`). The backend uses each finding's `.fix.transform_name` automatically.
  - **Hybrid mode** (optional): set `TRANSFORMATION_NAME` to override. Lets you remediate findings WITHOUT `.fix` populated (typical of `tech-debt-comprehensive`, `security` findings without auto-fix). The skill appends `--transformation-name <name>` to apply the same transformation to all selected findings -- so filter findings to one coherent category (e.g., all "Java" findings + `AWS/java-version-upgrade`) before scheduling.
- **`REMEDIATION_MODE=transformation`**: customer provides a transformation name + repo (e.g., `AWS/java-version-upgrade` on `my-org::my-repo`). Schedule fires that transformation directly without referencing findings. Best for recurring upgrades.

### Routing a customer's request

| Customer says                                                                                                                       | Mode                                                                                                                    |
| ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| "weekly tech-debt scan", "monthly security audit", "track findings over time"                                                       | Mode 1 (analysis)                                                                                                       |
| "remediate these findings on Friday", "apply this fix tonight", "I have IDs to fix" (findings have `.fix`)                          | Mode 2, findings sub-mode (no `TRANSFORMATION_NAME`)                                                                    |
| "remediate these comprehensive findings with `AWS/java-version-upgrade`", "apply this transformation to these specific finding IDs" | Mode 2, findings sub-mode + hybrid (set `TRANSFORMATION_NAME`)                                                          |
| "run `AWS/java-version-upgrade` every Sunday on my repos", "weekly Python upgrade"                                                  | Mode 2, transformation sub-mode                                                                                         |
| "scan AND auto-fix"                                                                                                                 | Decompose: run analysis NOW (one-shot), then route to Mode 2 findings sub-mode                                          |
| Mixed/unclear                                                                                                                       | Ask: "Are you trying to (a) regularly scan your repos for visibility, or (b) schedule a fix you've already decided on?" |

```bash
JOB_TYPE="${JOB_TYPE:-analysis}"        # analysis | remediation
REMEDIATION_MODE=""                      # findings | transformation (only when JOB_TYPE=remediation)
TRANSFORMATION_NAME=""                   # optional override for findings sub-mode (when .fix == null)
```

## Prerequisites

### For the EC2 path

Customer **MUST** already have an EC2 instance running with the `atx-ct` container set up via [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md). The schedule reuses that instance.

Specifically:

1. EC2 instance running with one or more atx-ct containers active (CFN-managed via `atx-runner` stack, or any other source; both supported)
2. Container has the CT server up (`docker exec ${CONTAINER_NAME} atx ct status --health` succeeds)
3. Instance has `AmazonSSMManagedInstanceCore` attached (so SSM can target it)
4. Customer has previously registered the source via `atx ct source add` (so a manual `atx ct analysis run` would work)

The schedule skill auto-discovers the instance via CFN stack outputs first (preferred), then falls back to tag-based search. If neither finds the instance, the customer is asked to set `INSTANCE_ID` manually.

**Multi-worker stacks**: if the customer's stack was deployed with `WorkerCount > 1`, the schedule routes to a specific worker via the optional `WORKER_NUM` env var (1..WorkerCount, default 1). Container naming: single-worker stacks use `atx-ct`; multi-worker stacks use `atx-ct-1`, `atx-ct-2`, etc. The skill auto-detects WorkerCount from the CFN stack parameter, so the customer only sets `WORKER_NUM` when they want a specific worker (otherwise worker 1 is used). To fan out N parallel scheduled jobs across N workers, create N schedules each with a distinct `WORKER_NUM` (1..N).

If any prerequisite is missing, hand off to [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md) first.

### For the Batch path

Customer **MUST** already have the Custom CDK stack (`AtxInfrastructureStack`) deployed via [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md). The schedule reuses the existing Lambda functions and Batch infrastructure.

Specifically:

1. `AtxInfrastructureStack` in `CREATE_COMPLETE` or `UPDATE_COMPLETE` state
2. `atx-trigger-batch-jobs` Lambda function is callable
3. Customer has previously registered the source via `atx ct source add` (same as EC2 path)
4. For local sources: source bundle uploaded to `s3://atx-source-code-${ACCOUNT_ID}/repos/`

If any prerequisite is missing, hand off to [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md) first.

## Two-Persona Permission Model

This skill respects the same admin/executor split as `continuous-modernization-ec2-execution.md`. Schedule lifecycle and IAM mutations require admin; everything else is executor.

| Persona      | Managed policy                                              | Owns                                                                                                                                                                                             | When used in this skill                                                                                                                      |
| ------------ | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Admin**    | `AdministratorAccess` (or equivalent)                       | `iam:Create/Put/Delete*` on `AtxSchedulerInvocationRole`, `scheduler:CreateScheduleGroup`                                                                                                        | Step 3 (one-time IAM + group setup) only                                                                                                     |
| **Executor** | (a least-privilege role scoped to the actions listed below) | `scheduler:CreateSchedule`/`DeleteSchedule`/`GetSchedule`/`UpdateSchedule`/`ListSchedules` (scoped to `atx-control-tower` group), `iam:PassRole` on `AtxSchedulerInvocationRole`, all read calls | Steps 1, 2, 4 (verify, identity-detect, parameter collection), Step 5 (create-schedule), Step 6 (verify), entire Schedule Management section |

The agent NEVER runs admin actions itself, even if an admin profile is reachable locally -- every admin step prints a handoff command and waits for the user to run it.

## Step 1: Verify Path Prerequisites

Verify the customer's chosen path is ready before creating any schedules. Branches on `PATH_TYPE`:

```bash
PROFILE="${AWS_PROFILE:-default}"
REGION=$(aws --profile $PROFILE configure get region 2>/dev/null || echo "us-east-1")
ACCOUNT_ID=$(aws --profile $PROFILE sts get-caller-identity --query Account --output text)
PATH_TYPE="${PATH_TYPE:-ec2}"   # "ec2" or "batch"

if [ "$PATH_TYPE" = "ec2" ]; then
  # ─────────────────────────────────────────────────────────────────
  # EC2 path: discover the instance, verify SSM, verify container
  # ─────────────────────────────────────────────────────────────────
  # Discovery order: (1) CFN stack outputs (preferred), (2) instance tags, (3) ask customer.
  # If the EC2 was provisioned via the CFN-based continuous-modernization-ec2-execution skill, the stack
  # (default name: atx-runner) has the InstanceId in its outputs.

  STACK_NAME="${STACK_NAME:-atx-runner}"
  INSTANCE_ID=""
  ROLE_ARN=""

  # (1) Try the CFN stack first
  STACK_STATUS=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

  case "$STACK_STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE)
      INSTANCE_ID=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
      ROLE_ARN=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' --output text)
      echo "Found CFN stack '$STACK_NAME'. Instance: $INSTANCE_ID, Role: $ROLE_ARN"
      ;;
  esac

  # (2) If no stack found, try tag-based discovery (handles legacy / non-CFN setups)
  if [ -z "$INSTANCE_ID" ]; then
    echo "No CFN stack '$STACK_NAME' found. Falling back to tag-based discovery."

    MATCHES=$(aws --profile $PROFILE --region $REGION ec2 describe-instances \
      --filters "Name=tag:Name,Values=atx-ct-runner,atx-ct-runner-*" \
                "Name=instance-state-name,Values=running" \
      --query 'Reservations[].Instances[].[InstanceId, LaunchTime]' \
      --output text 2>/dev/null | sort -k2 -r)

    INSTANCE_COUNT=$(echo "$MATCHES" | grep -c '^i-' || true)

    if [ "$INSTANCE_COUNT" = "0" ]; then
      echo "No running instance tagged Name=atx-ct-runner* and no CFN stack '$STACK_NAME'."
      echo "List candidates:"
      aws --profile $PROFILE --region $REGION ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value]' \
        --output table
      echo "Ask the customer for the instance ID and set INSTANCE_ID before continuing."
      return 1
    fi

    if [ "$INSTANCE_COUNT" -gt 1 ]; then
      echo "WARNING: $INSTANCE_COUNT running instances tagged atx-ct-runner*:"
      echo "$MATCHES" | column -t
      echo ""
      echo "Picking the most recently launched. If wrong, set INSTANCE_ID manually."
    fi

    INSTANCE_ID=$(echo "$MATCHES" | head -1 | awk '{print $1}')

    # Try to derive role ARN from the instance's profile (for non-CFN setups)
    PROFILE_ARN=$(aws --profile $PROFILE --region $REGION ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text 2>/dev/null)
    PROFILE_NAME=$(echo "$PROFILE_ARN" | awk -F/ '{print $NF}')
    ROLE_ARN=$(aws --profile $PROFILE iam get-instance-profile \
      --instance-profile-name "$PROFILE_NAME" \
      --query 'InstanceProfile.Roles[0].Arn' --output text 2>/dev/null)
  fi

  echo "Using instance: $INSTANCE_ID"
  echo "Instance role:  $ROLE_ARN"

  # Verify the SSM agent on the instance is online
  SSM_STATUS=$(aws --profile $PROFILE --region $REGION ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)

  if [ "$SSM_STATUS" != "Online" ]; then
    echo "ERROR: SSM agent is not online for instance $INSTANCE_ID (status: $SSM_STATUS)."
    echo "Verify the instance role has AmazonSSMManagedInstanceCore."
    echo "  CFN-managed instances: it's attached automatically -- check stack status."
    echo "  Ad-hoc instances: aws iam list-attached-role-policies --role-name <role>"
    echo "Wait 30-90s after attaching the policy for the agent to phone home."
    return 1
  fi

  # Helper for sending commands to the instance (drop-in for the prior $SSH "..." pattern).
  ssm_run() {
    local cmd="$1"
    local CMD_ID=$(aws --profile $PROFILE --region $REGION ssm send-command \
      --instance-ids "$INSTANCE_ID" \
      --document-name AWS-RunShellScript \
      --parameters "commands=[\"$cmd\"]" \
      --query 'Command.CommandId' --output text)
    aws --profile $PROFILE --region $REGION ssm wait command-executed \
      --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" 2>/dev/null || true
    aws --profile $PROFILE --region $REGION ssm get-command-invocation \
      --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' --output text
  }

  CONTAINER_STATUS=$(ssm_run "sudo docker inspect -f '{{.State.Status}}' atx-ct 2>/dev/null || echo missing")
  if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "Container atx-ct is not running (status: $CONTAINER_STATUS)."
    echo "Customer must restart it before scheduling. See continuous-modernization-ec2-execution Step 6 (verify) or Step 7 (start container)."
    return 1
  fi

  echo "Container atx-ct: running"

elif [ "$PATH_TYPE" = "batch" ]; then
  # ─────────────────────────────────────────────────────────────────
  # Batch path: verify CDK stack and Lambda function exist
  # ─────────────────────────────────────────────────────────────────
  CDK_STACK_NAME="AtxInfrastructureStack"

  # Verify the CDK stack is deployed
  CDK_STACK_STATUS=$(aws --profile $PROFILE --region $REGION cloudformation describe-stacks \
    --stack-name "$CDK_STACK_NAME" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

  case "$CDK_STACK_STATUS" in
    CREATE_COMPLETE|UPDATE_COMPLETE)
      echo "Found CDK stack '$CDK_STACK_NAME' in $CDK_STACK_STATUS state."
      ;;
    "")
      echo "ERROR: CDK stack '$CDK_STACK_NAME' not found in account $ACCOUNT_ID, region $REGION."
      echo "The Batch path requires the CDK stack to be deployed first."
      echo "Hand off to continuous-modernization-batch-execution and run setup.sh, then return here."
      return 1
      ;;
    *)
      echo "ERROR: CDK stack '$CDK_STACK_NAME' is in $CDK_STACK_STATUS state. Wait for completion or investigate."
      return 1
      ;;
  esac

  # Verify the trigger Lambda exists and is callable
  LAMBDA_FN="atx-trigger-batch-jobs"
  LAMBDA_STATUS=$(aws --profile $PROFILE --region $REGION lambda get-function \
    --function-name "$LAMBDA_FN" \
    --query 'Configuration.State' --output text 2>/dev/null)

  if [ "$LAMBDA_STATUS" != "Active" ]; then
    echo "ERROR: Lambda function '$LAMBDA_FN' is not Active (status: ${LAMBDA_STATUS:-not found})."
    echo "Verify the CDK stack deployment completed without errors."
    return 1
  fi

  echo "Lambda '$LAMBDA_FN': Active"
  echo "Batch path is ready for scheduling."

  # No INSTANCE_ID, no ROLE_ARN -- Batch path uses Lambda + Batch infrastructure managed by CDK.
  INSTANCE_ID=""
  ROLE_ARN=""

else
  echo "ERROR: PATH_TYPE must be 'ec2' or 'batch' (got: '$PATH_TYPE')"
  return 1
fi
```

## Step 2: Detect Identity Type

Different identity types need different IAM setup. Detect once before doing any IAM work:

```bash
CALLER_ARN=$(aws --profile $PROFILE sts get-caller-identity --query Arn --output text)

case "$CALLER_ARN" in
  *":user/"*)
    IDENTITY_TYPE="iam_user"
    USER_NAME=$(echo "$CALLER_ARN" | awk -F'/' '{print $NF}')
    echo "Identity: IAM user $USER_NAME"
    ;;
  *":assumed-role/"*)
    IDENTITY_TYPE="federated"
    ROLE_NAME=$(echo "$CALLER_ARN" | awk -F'/' '{print $(NF-1)}')
    echo "Identity: federated role $ROLE_NAME"
    echo "Will skip put-user-policy. Federated roles inherit perms from their attached policies."
    ;;
  *)
    IDENTITY_TYPE="unknown"
    echo "Identity type not recognized: $CALLER_ARN"
    echo "Will attempt schedule creation. If AccessDenied, customer's admin must grant"
    echo "  scheduler:CreateSchedule/DeleteSchedule/GetSchedule/UpdateSchedule/ListSchedules"
    echo "  on arn:aws:scheduler:*:\$ACCOUNT_ID:schedule/atx-control-tower/*"
    echo "  plus iam:PassRole on arn:aws:iam::\$ACCOUNT_ID:role/AtxSchedulerInvocationRole"
    ;;
esac
```

For Amazon engineers using Isengard / SSO-federated access, the result is `federated`. For most enterprise customers using IAM Identity Center, also `federated`. IAM users are uncommon outside legacy setups.

## Step 3: One-Time IAM Setup (Admin Handoff)

This step provisions the `AtxSchedulerInvocationRole` (the role EventBridge Scheduler assumes when firing each schedule) and the schedule group. Every action in this step is **admin-only**:

| Action                                                             | Why admin          |
| ------------------------------------------------------------------ | ------------------ |
| `iam:AttachRolePolicy` (3a -- SSM safety net for ad-hoc instances) | IAM mutation       |
| `iam:CreateRole` (3c -- `AtxSchedulerInvocationRole`)              | IAM mutation       |
| `iam:PutRolePolicy` (3d -- inline policy on that role)             | IAM mutation       |
| `scheduler:CreateScheduleGroup` (3f -- `atx-control-tower`)        | Resource lifecycle |
| `iam:PutUserPolicy` (3g -- for IAM-user identities only)           | IAM mutation       |

**The agent does NOT run these commands itself**, even if an admin profile is reachable locally. It prepares the inputs, prints the bundle as a single admin handoff, and waits for the user to come back. This is the same pattern Step 5d uses in `continuous-modernization-ec2-execution.md`.

**Profile-name guidance for the agent.** When emitting this admin handoff (or any admin handoff in this skill), the agent MUST use the placeholder `<your-admin-profile>` rather than guessing a profile name from the customer's local AWS config, environment variables, or shell history. Customers commonly have multiple AWS profiles configured locally and the agent has no reliable way to identify which one carries admin permissions. Substituting a wrong name leads to confusing AccessDenied errors during execution.

This step is also idempotent -- re-running it on an already-set-up account is safe (`grep -v EntityAlreadyExists` and `grep -v ConflictException` swallow the no-op cases). So the admin runs it once per account; subsequent schedules reuse the same role and group.

The agent assembles the input values (`ACCOUNT_ID`, `REGION`, `PATH_TYPE`, `INSTANCE_ROLE_NAME` if EC2, `IDENTITY_TYPE` + `USER_NAME` from Step 2), then prints:

> **Admin handoff -- one-time scheduler setup**
>
> The schedule cannot be created until your account has the `AtxSchedulerInvocationRole` and the `atx-control-tower` schedule group provisioned. This requires admin / role-creation permissions (`iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole`, `scheduler:CreateScheduleGroup`). Run it with an admin identity. Read-only or runtime credentials are enough for everything afterward.
>
> Ask someone with admin permissions to run this from the same shell, in the same region:
>
> ```bash
> # 3a. (EC2 path only) Ensure the instance role has AmazonSSMManagedInstanceCore.
> # CFN-managed instances (atx-runner stack) already have it via the stack's role definition.
> if [ "$PATH_TYPE" = "ec2" ] && [ -n "$INSTANCE_ROLE_NAME" ]; then
>   aws iam attach-role-policy \
>     --role-name "$INSTANCE_ROLE_NAME" \
>     --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>&1 | grep -v "EntityAlreadyExists" || true
> fi
>
> # 3c. Create the Scheduler invocation role (both paths share the role; policies differ).
> aws iam create-role \
>   --role-name AtxSchedulerInvocationRole \
>   --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"scheduler.amazonaws.com"},"Action":"sts:AssumeRole"}]}' 2>&1 | grep -v "EntityAlreadyExists" || true
>
> # 3d. Attach the path-specific inline policy. put-role-policy is idempotent (overwrites
> # the named policy). Each path uses a different policy name so both can coexist on the
> # same role -- useful when a customer schedules on both EC2 and Batch from the same account.
> if [ "$PATH_TYPE" = "ec2" ]; then
>   POLICY_NAME="ssm-send-command"
>   POLICY_DOC='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"ssm:SendCommand","Resource":"arn:aws:ec2:'$REGION':'$ACCOUNT_ID':instance/*","Condition":{"StringEquals":{"ssm:resourceTag/atx-remote-infra":"true"}}},{"Effect":"Allow","Action":"ssm:SendCommand","Resource":"arn:aws:ssm:'$REGION'::document/AWS-RunShellScript"}]}'
> else
>   POLICY_NAME="lambda-invoke-batch-trigger"
>   POLICY_DOC='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"lambda:InvokeFunction","Resource":"arn:aws:lambda:'$REGION':'$ACCOUNT_ID':function:atx-trigger-batch-jobs"}]}'
> fi
> aws iam put-role-policy \
>   --role-name AtxSchedulerInvocationRole \
>   --policy-name "$POLICY_NAME" \
>   --policy-document "$POLICY_DOC"
>
> # 3e. Brief wait for IAM propagation (eventual consistency).
> sleep 5
>
> # 3f. Create the scheduler group to isolate our schedules.
> aws --region $REGION scheduler create-schedule-group \
>   --name atx-control-tower 2>&1 | grep -v "ConflictException" || true
>
> # 3g. (IAM-user identities only) Grant the user permission to manage schedules.
> #     For federated/SSO identities, grant scheduler:CreateSchedule + iam:PassRole on
> #     AtxSchedulerInvocationRole through the same mechanism your org uses for that role.
> if [ "$IDENTITY_TYPE" = "iam_user" ]; then
>   aws iam put-user-policy \
>     --user-name "$USER_NAME" \
>     --policy-name atx-scheduler-access \
>     --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["scheduler:CreateSchedule","scheduler:DeleteSchedule","scheduler:GetSchedule","scheduler:UpdateSchedule","scheduler:ListSchedules","scheduler:GetScheduleGroup","scheduler:ListScheduleGroups"],"Resource":["arn:aws:scheduler:*:'$ACCOUNT_ID':schedule/atx-control-tower/*","arn:aws:scheduler:*:'$ACCOUNT_ID':schedule-group/atx-control-tower"]},{"Effect":"Allow","Action":"iam:PassRole","Resource":"arn:aws:iam::'$ACCOUNT_ID':role/AtxSchedulerInvocationRole"}]}'
> fi
> ```
>
> When this finishes, come back to the conversation. I'll re-detect the role and group via read-only `iam:GetRole` + `scheduler:GetSchedule` and continue from Step 4.

The agent then STOPS this turn. The admin runs the commands in their own terminal, outside the chat. On the next user turn, re-run Step 2 (Detect Identity Type) -- it should succeed now -- and continue.

**Why one role, two inline policies:** A customer who schedules analyses on BOTH paths from the same account ends up with `AtxSchedulerInvocationRole` having both `ssm-send-command` AND `lambda-invoke-batch-trigger` inline policies. Each schedule's target uses whichever it needs -- the role grants both, the action filter on the policy ensures only the right action is allowed.

## Step 4: Collect Schedule Parameters

Parameter collection branches on `JOB_TYPE`. Common parameters first, then mode-specific.

### Common parameters (both modes)

```bash
# Customer's choice, lowercase + hyphens
SCHEDULE_NAME="atxct-weekly-techdebt"

# The atx ct source name (must match `atx ct source list`)
LOGICAL_SOURCE_NAME="my-org-github"

AGENT="<AGENT>"  # AI assistant name (kiro, claude, amazonq, etc.)

# Provider -- needed for Batch path to pick the right build_command_*() template.
# For EC2 path, ignored (uses the running container's existing source config).
PROVIDER="github"   # github | gitlab | local

# Cron expression (or at() for one-shot)
CRON_EXPR="cron(0 9 ? * MON *)"   # Monday 9am
TIMEZONE="UTC"                     # or "America/Los_Angeles", "Europe/London", etc.

# Batch + local provider only -- name of the source bundle in S3
ZIP_NAME=""   # e.g., "my-org-bundle"

# Optional repo scope (analysis mode) -- leave empty for source-wide
REPO_FILTER=""   # e.g., "--repo my-org::my-repo"
```

Common cron expressions:

| Customer says              | Cron expression           |
| -------------------------- | ------------------------- |
| every Monday at 9am        | `cron(0 9 ? * MON *)`     |
| daily at 2am               | `cron(0 2 * * ? *)`       |
| weekdays at 5am            | `cron(0 5 ? * MON-FRI *)` |
| first of every month       | `cron(0 9 1 * ? *)`       |
| every 15 minutes (testing) | `cron(0/15 * * * ? *)`    |
| every hour                 | `cron(0 * * * ? *)`       |
| one-shot at specific time  | `at(2026-06-15T09:00:00)` |

For other patterns: AWS Scheduler uses 6-field cron (`min hr day-of-month month day-of-week year`). Day-of-month and day-of-week can't both be `*` -- use `?` for the unused one.

### Verify the source is registered

The schedule skill creates the schedule but does NOT register sources -- that's the [continuous-modernization-source](continuous-modernization-source.md) skill's job. Verify the source exists before creating the schedule, otherwise the customer gets a "successful" schedule that fails at fire time when the container can't find the source.

```bash
echo "Verifying source '$LOGICAL_SOURCE_NAME' is registered..."
SOURCE_EXISTS=$(atx ct source list --json 2>/dev/null \
  | jq -r --arg n "$LOGICAL_SOURCE_NAME" '.[] | select(.name == $n) | .name' 2>/dev/null)

if [ -z "$SOURCE_EXISTS" ]; then
  echo ""
  echo "❌ Source '$LOGICAL_SOURCE_NAME' is NOT registered in atx ct."
  echo ""
  echo "Register it first via the continuous-modernization-source skill, then re-run this step:"
  echo "  github/gitlab : atx ct source add --name $LOGICAL_SOURCE_NAME --provider <github|gitlab> --org <org-name> --token <PAT>"
  echo "  local         : atx ct source add --name $LOGICAL_SOURCE_NAME --provider local --path <local-path>"
  echo ""
  echo "After registration, also ensure credentials are in Secrets Manager"
  echo "(see continuous-modernization-ec2-execution Step 3 or continuous-modernization-batch-execution Step 2 for the put-secret-value pattern)."
  return 1
fi
echo "✅ Source '$LOGICAL_SOURCE_NAME' is registered (provider=$(atx ct source list --json | jq -r --arg n "$LOGICAL_SOURCE_NAME" '.[] | select(.name == $n) | .provider'))"
```

### Verify credentials are accessible (Batch path only)

You MUST verify that the caller has access to the required credential secret BEFORE
creating the schedule. A schedule without accessible credentials will fail silently
at fire time. You MUST NOT create a schedule if this check fails.

For non-local providers, verify the provider secret exists and is accessible:

```bash
PROVIDER=$(atx ct source list --json | jq -r --arg n "$LOGICAL_SOURCE_NAME" '.[] | select(.name == $n) | .provider')

if [ "$PROVIDER" != "local" ]; then
  SECRET_ID="atx/${PROVIDER}-token"

  echo "Verifying access to credential secret '${SECRET_ID}'..."
  if ! aws secretsmanager describe-secret --secret-id "$SECRET_ID" 2>/dev/null; then
    echo ""
    echo "❌ Cannot access secret '${SECRET_ID}'."
    echo ""
    echo "Either the secret does not exist, or you do not have permission to access it."
    echo "Create it first (see continuous-modernization-batch-execution Step 2)."
    echo ""
    echo "Schedule creation blocked — the schedule would fail at fire time without valid credentials."
    return 1
  fi
  echo "✅ Credential secret '${SECRET_ID}' is accessible"
fi
```

### Mode-specific parameters

#### Mode 1: Analysis (`JOB_TYPE=analysis`)

Ask the customer:

1. **Analysis type** -- `tech-debt-quick`, `tech-debt-comprehensive`, `agentic-readiness`, `modernization-readiness`, `security`, or `custom`
2. **(For `custom` only)** Transformation name and optional configuration

```bash
if [ "$JOB_TYPE" = "analysis" ]; then
  ANALYSIS_TYPE="tech-debt-quick"   # tech-debt-quick | tech-debt-comprehensive | security | agentic-readiness | modernization-readiness | custom

  # Required only when ANALYSIS_TYPE=custom
  TRANSFORMATION_NAME=""
  CONFIGURATION=""

  if [ "$ANALYSIS_TYPE" = "custom" ]; then
    [ -z "$TRANSFORMATION_NAME" ] && { echo "ERROR: ANALYSIS_TYPE=custom requires TRANSFORMATION_NAME"; return 1; }
  fi
fi
```

#### Mode 2: Remediation (`JOB_TYPE=remediation`)

Ask the customer which sub-mode:

- **`findings`** -- they have specific finding IDs to fix (from a prior `atx ct findings list`). The skill captures those IDs NOW and bakes them into the schedule.
- **`transformation`** -- they want to run a specific transformation on a specific repo on schedule (no findings dependency).

##### Sub-mode: findings

Pre-flight: capture finding IDs before creating the schedule. The skill uses these as a frozen list -- at fire time, the schedule remediates exactly these IDs (no fresh discovery).

`TRANSFORMATION_NAME` is **optional**:

- **Leave empty** when findings have `.fix` populated (typical for `tech-debt-quick`). The backend uses each finding's `.fix.transform_name` automatically.
- **Set explicitly** when findings DON'T have `.fix` populated (typical for `tech-debt-comprehensive`, `security` issues without auto-fix). The skill appends `--transformation-name $TRANSFORMATION_NAME` to override, applying the same transformation to all selected finding IDs.

Capture pattern depends on which case you're in:

```bash
if [ "$JOB_TYPE" = "remediation" ] && [ "$REMEDIATION_MODE" = "findings" ]; then
  # Optional explicit transformation override (for findings without .fix populated)
  TRANSFORMATION_NAME=""   # e.g., "AWS/java-version-upgrade"

  if [ -z "$TRANSFORMATION_NAME" ]; then
    # ── Default capture: only findings with .fix populated ──
    # Backend will pick the transformation per finding from .fix.transform_name
    if [ -n "$AID" ]; then
      FINDING_IDS=$(atx ct findings list --analysis-id "$AID" --json \
        | jq -r '.[] | select(.fix != null and .status == "open") | .id' \
        | paste -sd, -)
    else
      FINDING_IDS=$(atx ct findings list --source "$LOGICAL_SOURCE_NAME" --json \
        | jq -r '.[] | select(.fix != null and .status == "open") | .id' \
        | paste -sd, -)
    fi

    if [ -z "$FINDING_IDS" ]; then
      echo ""
      echo "❌ No auto-remediable findings (fix != null, status == open) on source '$LOGICAL_SOURCE_NAME'."
      echo ""
      echo "Two options:"
      echo "  1. Run a fresh tech-debt-quick analysis to surface auto-fixable findings:"
      echo "     atx ct analysis run --type tech-debt-quick --source $LOGICAL_SOURCE_NAME --wait"
      echo "  2. Set TRANSFORMATION_NAME explicitly to remediate findings WITHOUT .fix populated"
      echo "     (e.g., from a tech-debt-comprehensive analysis). Then capture by category instead:"
      echo "     FINDING_IDS=\$(atx ct findings list --analysis-id <AID> --json \\"
      echo "       | jq -r '.[] | select(.category == \"Java\") | .id' | paste -sd, -)"
      echo "     TRANSFORMATION_NAME=\"AWS/java-version-upgrade\""
      return 1
    fi

  else
    # ── Hybrid capture: any findings, override transformation explicitly ──
    # Customer specifies TRANSFORMATION_NAME, so .fix is not required.
    # Filter by category/severity/repo as needed (must produce a coherent group
    # the chosen transformation applies to).
    if [ -z "$AID" ]; then
      echo "ERROR: TRANSFORMATION_NAME requires AID (analysis ID) so we can scope finding capture"
      return 1
    fi
    # Default: capture ALL open findings under the analysis. Customer should
    # narrow this by category/repo for a coherent transformation target.
    FINDING_IDS=$(atx ct findings list --analysis-id "$AID" --json \
      | jq -r '.[] | select(.status == "open") | .id' \
      | paste -sd, -)

    if [ -z "$FINDING_IDS" ]; then
      echo "❌ No open findings under analysis '$AID'"
      return 1
    fi
  fi

  COUNT=$(echo "$FINDING_IDS" | tr ',' '\n' | wc -l | tr -d ' ')
  if [ -n "$TRANSFORMATION_NAME" ]; then
    echo "✅ Captured $COUNT finding IDs to remediate with transformation: $TRANSFORMATION_NAME"
  else
    echo "✅ Captured $COUNT auto-remediable finding IDs (each will use its own .fix.transform_name)"
  fi
  echo "First 3: $(echo $FINDING_IDS | cut -d, -f1-3)..."
fi
```

**How to choose TRANSFORMATION_NAME for hybrid mode:**

When `TRANSFORMATION_NAME` is needed (findings without `.fix`), the agent should:

1. List the finding categories present in the captured set:

   ```bash
   atx ct findings list --analysis-id "$AID" --json \
     | jq -r '[.[] | .category] | unique | .[]'
   ```

2. Match category to a known transformation. Common mappings:

   | Finding category/title               | Likely TRANSFORMATION_NAME           |
   | ------------------------------------ | ------------------------------------ |
   | "Java" / "Java 8" / "Java 11"        | `AWS/java-version-upgrade`           |
   | "Python" / "Python 2" / "Python 3.6" | `AWS/python-version-upgrade`         |
   | "Node.js" / "Node 14" / "Node 16"    | `AWS/nodejs-version-upgrade`         |
   | "AWS SDK" / "boto2" / "JS SDK v2"    | `AWS/aws-sdk-upgrade`                |
   | ".NET Framework" / ".NET Core"       | `AWS/dotnet-upgrade`                 |
   | "Code Quality" / "Complexity"        | (no transformation -- manual review) |
   | "Deprecated APIs" (mixed)            | varies -- match to specific upgrade  |

3. **Filter `FINDING_IDS` to only the matching category** -- applying one transformation to mixed findings is incorrect. Re-run the capture with `select(.category == "Java")` or whatever matches.
4. Confirm with the customer before scheduling.

##### Sub-mode: transformation

Customer provides a transformation + repo. No findings discovery needed.

```bash
if [ "$JOB_TYPE" = "remediation" ] && [ "$REMEDIATION_MODE" = "transformation" ]; then
  # Required: transformation name and at least one repo
  TRANSFORMATION_NAME="AWS/java-version-upgrade"
  REPO_FILTER="--repo my-org-github::my-java-repo"   # required (single repo) or comma-separated for multiple
  REMEDIATION_CONFIG=""                              # optional, becomes the `-g` flag value

  [ -z "$TRANSFORMATION_NAME" ] && { echo "ERROR: REMEDIATION_MODE=transformation requires TRANSFORMATION_NAME"; return 1; }
  [ -z "$REPO_FILTER" ] && { echo "ERROR: REMEDIATION_MODE=transformation requires --repo (REPO_FILTER)"; return 1; }
fi
```

If the customer hasn't registered the source yet or needs to update the token on an existing source, hand off to [continuous-modernization-source](continuous-modernization-source.md) BEFORE creating the schedule. Saves confusion when the schedule fires and fails silently.

## Step 5: Construct and Create the Schedule

The schedule's payload depends on `PATH_TYPE` and `JOB_TYPE`:

- **EC2 path**: a wrapper script base64-encoded inside an SSM SendCommand. Same pattern as the EC2 skill's `build_command_*()` (avoids quoting issues when the SSM payload contains nested quotes).
- **Batch path**: a JSON payload that the EventBridge scheduler passes directly to the `atx-trigger-batch-jobs` Lambda. The Lambda submits a Fargate job with the command baked in.

The wrapper/command body branches on `JOB_TYPE`:

- `analysis` -- runs `atx ct analysis run`
- `remediation` -- runs `atx ct remediation create` (findings or transformation sub-mode), polls until terminal, optionally uploads (only for `local` provider)

### Build common pieces (used by both paths)

```bash
# For analysis mode: extra flags for --type custom
EXTRA_FLAGS=""
if [ "$JOB_TYPE" = "analysis" ] && [ "$ANALYSIS_TYPE" = "custom" ]; then
  [ -z "$TRANSFORMATION_NAME" ] && { echo "ERROR: --type custom requires TRANSFORMATION_NAME"; return 1; }
  EXTRA_FLAGS="--transformation-name $TRANSFORMATION_NAME"
  [ -n "$CONFIGURATION" ] && EXTRA_FLAGS="$EXTRA_FLAGS -g \"$CONFIGURATION\""
fi

# For remediation+transformation mode: extra flags
REMED_FLAGS=""
if [ "$JOB_TYPE" = "remediation" ] && [ "$REMEDIATION_MODE" = "transformation" ]; then
  REMED_FLAGS="--transformation-name $TRANSFORMATION_NAME $REPO_FILTER"
  [ -n "$REMEDIATION_CONFIG" ] && REMED_FLAGS="$REMED_FLAGS -g \"$REMEDIATION_CONFIG\""
fi
```

### EC2 path: build SSM SendCommand target

The EC2 wrapper is base64'd through SSM, so we can use full bash idioms (`$()`, `select(...)`, etc.) -- the Lambda allowlist does NOT apply here.

```bash
if [ "$PATH_TYPE" = "ec2" ]; then
  # ─────────────────────────────────────────────────────────────────
  # Resolve target worker container (multi-worker stacks)
  # ─────────────────────────────────────────────────────────────────
  # WorkerCount comes from the CFN stack parameter (defaults to 1 for legacy stacks
  # that don't have the parameter). WORKER_NUM is the 1-indexed worker to schedule
  # against (defaults to 1). For WorkerCount=1, container is "atx-ct" (existing
  # behavior). For WorkerCount>1, container is "atx-ct-${WORKER_NUM}".
  WORKER_COUNT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
    --query 'Stacks[0].Parameters[?ParameterKey==`WorkerCount`].ParameterValue' --output text 2>/dev/null)
  WORKER_COUNT=$(echo "$WORKER_COUNT" | xargs)   # strip whitespace defensively
  [ -z "$WORKER_COUNT" ] || [ "$WORKER_COUNT" = "None" ] && WORKER_COUNT=1
  WORKER_NUM="${WORKER_NUM:-1}"
  if [ "$WORKER_COUNT" -eq 1 ]; then
    CONTAINER_NAME="atx-ct"
  else
    if [ "$WORKER_NUM" -lt 1 ] || [ "$WORKER_NUM" -gt "$WORKER_COUNT" ]; then
      echo "ERROR: WORKER_NUM ($WORKER_NUM) must be 1-${WORKER_COUNT} for this multi-worker stack." >&2
      return 1
    fi
    CONTAINER_NAME="atx-ct-${WORKER_NUM}"
  fi
  echo "Targeting container: $CONTAINER_NAME (worker $WORKER_NUM of $WORKER_COUNT)"

  # ─────────────────────────────────────────────────────────────────
  # Build the wrapper script body based on JOB_TYPE
  # ─────────────────────────────────────────────────────────────────

  if [ "$JOB_TYPE" = "analysis" ]; then
    # Analysis mode: skip upload for tech-debt-quick (read-only)
    UPLOAD_LINE="sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh \$AID atx-ct-output-${ACCOUNT_ID}"
    [ "$ANALYSIS_TYPE" = "tech-debt-quick" ] && UPLOAD_LINE='echo "[skip upload -- tech-debt-quick is read-only]"'

    SCRIPT_BODY=$(cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-sched-\$(date +%s).log
echo "=== \$(date) [START] scheduled $ANALYSIS_TYPE analysis on $LOGICAL_SOURCE_NAME ===" >> \$LOG

sudo docker exec ${CONTAINER_NAME} bash -c "source /home/atxuser/.nvm/nvm.sh && nvm use 22 >/dev/null 2>&1 && export PATH=/home/atxuser/.local/bin:\\\$PATH && atx ct analysis run --type $ANALYSIS_TYPE $EXTRA_FLAGS --source $LOGICAL_SOURCE_NAME $REPO_FILTER --wait --telemetry \"agent=${AGENT},executionMode=ec2\"" >> \$LOG 2>&1
ANALYSIS_RC=\$?

AID=\$(grep -oE '01[A-Z0-9]+' \$LOG | head -1)
[ -n "\$AID" ] && echo "ANALYSIS_STARTED: \$AID"   # to stdout for 'aws ssm get-command-invocation' visibility (regardless of pass/fail)

if [ \$ANALYSIS_RC -ne 0 ]; then
  echo "=== \$(date) [ERROR] analysis failed (rc=\$ANALYSIS_RC, AID=\$AID) ===" >> \$LOG
  exit \$ANALYSIS_RC
fi

[ -z "\$AID" ] && { echo "=== \$(date) [ERROR] success but no AID extracted ===" >> \$LOG; exit 1; }
echo "=== \$(date) [DONE] analysis \$AID ===" >> \$LOG

$UPLOAD_LINE >> \$LOG 2>&1
echo "=== \$(date) [DONE] upload ===" >> \$LOG
EOF
)

  elif [ "$JOB_TYPE" = "remediation" ]; then
    # Remediation mode: build the create command, poll until terminal,
    # upload artifacts only for local provider (github/gitlab/bitbucket
    # push results to source repo automatically).

    # Build the remediation create line based on sub-mode
    if [ "$REMEDIATION_MODE" = "findings" ]; then
      [ -z "$FINDING_IDS" ] && { echo "ERROR: REMEDIATION_MODE=findings requires FINDING_IDS"; return 1; }
      # Optional --transformation-name override (when findings don't have .fix populated, e.g. comprehensive)
      REMED_TRANSFORM_FLAG=""
      [ -n "$TRANSFORMATION_NAME" ] && REMED_TRANSFORM_FLAG=" --transformation-name $TRANSFORMATION_NAME"
      REMED_CREATE_LINE="atx ct remediation create --ids $FINDING_IDS$REMED_TRANSFORM_FLAG --name $SCHEDULE_NAME-rem"
    elif [ "$REMEDIATION_MODE" = "transformation" ]; then
      REMED_CREATE_LINE="atx ct remediation create $REMED_FLAGS --name $SCHEDULE_NAME-rem"
    else
      echo "ERROR: REMEDIATION_MODE must be 'findings' or 'transformation'"
      return 1
    fi

    # --local flag for local provider (github/gitlab/bitbucket: backend pushes to source repo)
    [ "$PROVIDER" = "local" ] && REMED_CREATE_LINE="$REMED_CREATE_LINE --local"

    # Upload only for local provider
    UPLOAD_REMED_LINE='echo "[skip upload -- github/gitlab/bitbucket pushes results to source repo]"'
    [ "$PROVIDER" = "local" ] && UPLOAD_REMED_LINE="sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh \$RID atx-ct-output-${ACCOUNT_ID}"

    SCRIPT_BODY=$(cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-sched-\$(date +%s).log
echo "=== \$(date) [START] scheduled remediation ($REMEDIATION_MODE) on $LOGICAL_SOURCE_NAME ===" >> \$LOG

sudo docker exec ${CONTAINER_NAME} bash -c "source /home/atxuser/.nvm/nvm.sh && nvm use 22 >/dev/null 2>&1 && export PATH=/home/atxuser/.local/bin:\\\$PATH && $REMED_CREATE_LINE --telemetry \"agent=${AGENT},executionMode=ec2\"" >> \$LOG 2>&1
CREATE_RC=\$?

RID=\$(grep -oE '01[A-Z0-9]+' \$LOG | tail -1)
[ -n "\$RID" ] && echo "REMEDIATION_STARTED: \$RID"   # to stdout for SSM visibility (regardless of pass/fail)

if [ \$CREATE_RC -ne 0 ]; then
  echo "=== \$(date) [ERROR] remediation create failed (rc=\$CREATE_RC, RID=\$RID) ===" >> \$LOG
  exit \$CREATE_RC
fi

[ -z "\$RID" ] && { echo "=== \$(date) [ERROR] success but no RID extracted ===" >> \$LOG; exit 1; }
echo "=== \$(date) [REMED] remediation \$RID started -- polling status ===" >> \$LOG

# Poll every 30s until terminal status (atx ct remediation create does not support --wait)
STATUS=""
while true; do
  STATUS=\$(sudo docker exec ${CONTAINER_NAME} bash -c "source /home/atxuser/.nvm/nvm.sh && nvm use 22 >/dev/null 2>&1 && export PATH=/home/atxuser/.local/bin:\\\$PATH && atx ct remediation status --id \$RID --json" 2>>\$LOG | jq -r .status 2>/dev/null)
  case "\$STATUS" in
    complete|completed|failed|cancelled)
      echo "=== \$(date) [REMED] remediation \$RID terminal: \$STATUS ===" >> \$LOG
      break
      ;;
  esac
  sleep 30
done

$UPLOAD_REMED_LINE >> \$LOG 2>&1
echo "=== \$(date) [DONE] remediation flow complete (status=\$STATUS) ===" >> \$LOG

# Exit non-zero if remediation didn't complete successfully (so the SSM invocation reports failure)
[ "\$STATUS" != "complete" ] && exit 1
exit 0
EOF
)
  else
    echo "ERROR: JOB_TYPE must be 'analysis' or 'remediation' (got: '$JOB_TYPE')"
    return 1
  fi

  # ─────────────────────────────────────────────────────────────────
  # Encode and submit via SSM SendCommand
  # ─────────────────────────────────────────────────────────────────

  # Encode the script body -- base64 chars (A-Za-z0-9+/=) survive any quoting layer
  B64=$(echo "$SCRIPT_BODY" | base64 | tr -d '\n')

  # The command the schedule fires on the instance: decode the script and run it.
  COMMAND="echo $B64 | base64 -d > /tmp/atxct-sched.sh && bash /tmp/atxct-sched.sh"

  # SSM SendCommand timeout: 4h for analysis-only, 8h if remediation involved.
  # Bump for source-level comprehensive analyses on many repos.
  TIMEOUT=14400
  [ "$JOB_TYPE" = "remediation" ] && TIMEOUT=28800

  INPUT_JSON=$(jq -n \
    --arg id "$INSTANCE_ID" \
    --arg cmd "$COMMAND" \
    --argjson timeout $TIMEOUT \
    '{InstanceIds: [$id], DocumentName: "AWS-RunShellScript", TimeoutSeconds: $timeout, Parameters: {commands: [$cmd]}}')

  TARGET=$(jq -n \
    --arg arn "arn:aws:scheduler:::aws-sdk:ssm:sendCommand" \
    --arg role "arn:aws:iam::$ACCOUNT_ID:role/AtxSchedulerInvocationRole" \
    --arg input "$INPUT_JSON" \
    '{Arn: $arn, RoleArn: $role, Input: $input}')
fi
```

### Batch path: build Lambda Invoke target

The Batch JOB_COMMAND must comply with the atx-trigger-batch-jobs Lambda allowlist (see [continuous-modernization-batch-execution.md Step 5](continuous-modernization-batch-execution.md) for the canonical rules). Lambda rejects strings containing `$`, `^`, `()`, `{}`, `*`, backticks, or non-ASCII characters (em-dashes, en-dashes, smart quotes, and any other non-ASCII punctuation).

We build the JOB_COMMAND in three pieces:

1. **Provider preamble** (per-provider source/token setup) -- same across job types
2. **Job body** (analysis run OR remediation create) -- branches on `JOB_TYPE`
3. **Trailing chain** (poll, upload) -- per-mode, with provider-specific upload suffix

```bash
if [ "$PATH_TYPE" = "batch" ]; then
  # ─────────────────────────────────────────────────────────────────
  # Build the JOB_BODY based on JOB_TYPE × REMEDIATION_MODE × PROVIDER
  # ─────────────────────────────────────────────────────────────────

  # Skip analysis-artifact upload for tech-debt-quick (read-only)
  ANALYSIS_UPLOAD_SUFFIX=""
  if [ "$JOB_TYPE" = "analysis" ] && [ "$ANALYSIS_TYPE" != "tech-debt-quick" ]; then
    ANALYSIS_UPLOAD_SUFFIX=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi

  # Remediation suffix (poll status until terminal, upload only if local provider)
  # Lambda-safe: no $(), no select(...), no em-dash. See allowlist constraints above.
  REMED_POLL_SUFFIX=" && grep -oE '01[A-Z0-9]+' /tmp/rem.log | tail -1 > /tmp/rid.txt && while true ; do cat /tmp/rid.txt | xargs -I RID atx ct remediation status --id RID > /tmp/status.txt ; grep -qE 'complete|completed|failed|cancelled' /tmp/status.txt && break ; sleep 30 ; done"

  REMED_UPLOAD_SUFFIX=""
  if [ "$PROVIDER" = "local" ]; then
    REMED_UPLOAD_SUFFIX=" && cat /tmp/rid.txt | xargs -I RID /app/upload-ct-artifacts.sh RID atx-ct-output-${ACCOUNT_ID}"
  fi

  # Build the JOB_BODY (the "do the work" part of the command)
  if [ "$JOB_TYPE" = "analysis" ]; then
    JOB_BODY="atx ct analysis run --type ${ANALYSIS_TYPE} ${EXTRA_FLAGS} --source ${LOGICAL_SOURCE_NAME} ${REPO_FILTER} --wait --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log${ANALYSIS_UPLOAD_SUFFIX}"
  elif [ "$JOB_TYPE" = "remediation" ]; then
    # --local flag only for local provider
    LOCAL_FLAG=""
    [ "$PROVIDER" = "local" ] && LOCAL_FLAG=" --local"

    if [ "$REMEDIATION_MODE" = "findings" ]; then
      [ -z "$FINDING_IDS" ] && { echo "ERROR: REMEDIATION_MODE=findings requires FINDING_IDS"; return 1; }
      # Optional --transformation-name override (when findings don't have .fix populated, e.g. comprehensive)
      REMED_TRANSFORM_FLAG=""
      [ -n "$TRANSFORMATION_NAME" ] && REMED_TRANSFORM_FLAG=" --transformation-name $TRANSFORMATION_NAME"
      # NOTE: remediation name uses <aws.scheduler.scheduled-time> for uniqueness on recurring schedules
      JOB_BODY="atx ct remediation create --ids ${FINDING_IDS}${REMED_TRANSFORM_FLAG} --name \"${SCHEDULE_NAME}-rem-<aws.scheduler.scheduled-time>\"${LOCAL_FLAG} --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/rem.log${REMED_POLL_SUFFIX}${REMED_UPLOAD_SUFFIX}"
    elif [ "$REMEDIATION_MODE" = "transformation" ]; then
      JOB_BODY="atx ct remediation create ${REMED_FLAGS} --name \"${SCHEDULE_NAME}-rem-<aws.scheduler.scheduled-time>\"${LOCAL_FLAG} --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/rem.log${REMED_POLL_SUFFIX}${REMED_UPLOAD_SUFFIX}"
    else
      echo "ERROR: REMEDIATION_MODE must be 'findings' or 'transformation'"
      return 1
    fi
  else
    echo "ERROR: JOB_TYPE must be 'analysis' or 'remediation' (got: '$JOB_TYPE')"
    return 1
  fi

  # ─────────────────────────────────────────────────────────────────
  # Provider-specific preamble (sets up source registration, tokens)
  # ─────────────────────────────────────────────────────────────────
  PREAMBLE_COMMON="atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15"

  case "$PROVIDER" in
    github)
      PREAMBLE="${PREAMBLE_COMMON} ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/github-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/github_token"
      ;;
    gitlab)
      PREAMBLE="${PREAMBLE_COMMON} ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/gitlab-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/gitlab_token"
      ;;
    local)
      [ -z "$ZIP_NAME" ] && { echo "ERROR: Batch + local provider requires ZIP_NAME"; return 1; }
      PREAMBLE="${PREAMBLE_COMMON} ; mkdir -p /home/atxuser/repos && aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/repos/${ZIP_NAME}.zip /tmp/${ZIP_NAME}.zip && unzip -q /tmp/${ZIP_NAME}.zip -d /home/atxuser/repos/ && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} --path /home/atxuser/repos"
      ;;
    *)
      echo "ERROR: PROVIDER must be github, gitlab, or local (got: '$PROVIDER')"
      return 1
      ;;
  esac

  # Combine preamble + job body
  JOB_COMMAND="${PREAMBLE} && ${JOB_BODY}"

  # Build Lambda payload -- the schema atx-trigger-batch-jobs expects.
  # batchName uses <aws.scheduler.scheduled-time> for uniqueness on recurring fires.
  LAMBDA_PAYLOAD=$(jq -nc \
    --arg cmd "$JOB_COMMAND" \
    --arg base "${SCHEDULE_NAME}" \
    '{batchName: ($base + "-<aws.scheduler.scheduled-time>"), jobs: [{command: $cmd, jobName: ($base + "-job")}]}')

  # Schedule's target -- direct Lambda Invoke
  TARGET=$(jq -n \
    --arg arn "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:atx-trigger-batch-jobs" \
    --arg role "arn:aws:iam::$ACCOUNT_ID:role/AtxSchedulerInvocationRole" \
    --arg input "$LAMBDA_PAYLOAD" \
    '{Arn: $arn, RoleArn: $role, Input: $input}')
fi
```

### Create the schedule (executor)

`scheduler:CreateSchedule` is in the executor policy, scoped to the `atx-control-tower` group. `iam:PassRole` on `AtxSchedulerInvocationRole` is also in the executor policy (scoped to `iam:PassedToService=scheduler.amazonaws.com`). The agent runs this directly:

```bash
aws --profile $PROFILE --region $REGION scheduler create-schedule \
  --name "$SCHEDULE_NAME" \
  --group-name atx-control-tower \
  --schedule-expression "$CRON_EXPR" \
  --schedule-expression-timezone "$TIMEZONE" \
  --flexible-time-window '{"Mode":"OFF"}' \
  --target "$TARGET" \
  --action-after-completion NONE
```

No admin handoff needed for routine scheduling -- the one-time IAM setup in Step 3 (admin handoff) provisioned `AtxSchedulerInvocationRole` and the `atx-control-tower` group, and the executor's `iam:PassRole` is bounded to that role only. The schedule's target can therefore only invoke what `AtxSchedulerInvocationRole` is allowed to invoke (which admin scoped to `ssm:SendCommand` on tagged instances or `lambda:Invoke` on `atx-trigger-batch-jobs`). Privilege surface is unchanged from what admin pre-vetted.

**Why the upload step matters:** Without the trailing `/app/upload-ct-artifacts.sh` call, scheduled analyses leave findings in the backend (queryable via `atx ct findings list`) but don't upload `code.zip` artifacts to S3. For analysis types that produce working-tree changes (tech-debt-comprehensive, security, agentic-readiness, modernization-readiness), the customer typically wants the artifacts for `git diff` review -- so the upload step is essential. tech-debt-quick is read-only (no working-tree changes), so its upload is intentionally skipped.

**EventBridge contextual variables:** `<aws.scheduler.scheduled-time>` in the Batch payload is replaced by EventBridge at fire time with the scheduled fire timestamp. This makes each batch's name unique, so `atx-get-batch-status` and `atx-terminate-batch-jobs` can target a specific firing if needed. See [AWS Scheduler context attributes](https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-schedule-context-attributes.html).

## Step 6: Verify and Report

```bash
# Confirm the schedule exists and show next firing time
aws --profile $PROFILE --region $REGION scheduler get-schedule \
  --name "$SCHEDULE_NAME" \
  --group-name atx-control-tower \
  --query '{Name:Name, State:State, Cron:ScheduleExpression, TZ:ScheduleExpressionTimezone}' \
  --output table

echo ""
echo "Schedule '$SCHEDULE_NAME' created."
echo ""
echo "What it does:"
echo "  Cron: $CRON_EXPR ($TIMEZONE)"
echo "  Targets instance: $INSTANCE_ID"
echo "  Runs: $COMMAND"
echo ""
echo "Manage your schedules:"
echo "  List:    aws --region $REGION scheduler list-schedules --group-name atx-control-tower"
echo "  Get:     aws --region $REGION scheduler get-schedule --name $SCHEDULE_NAME --group-name atx-control-tower"
echo "  Disable: aws --region $REGION scheduler update-schedule --name $SCHEDULE_NAME --group-name atx-control-tower --state DISABLED [...]"
echo "  Delete:  aws --region $REGION scheduler delete-schedule --name $SCHEDULE_NAME --group-name atx-control-tower"
echo ""
echo "AWS Console: Amazon EventBridge → Schedules → atx-control-tower"
```

## Quick Test (Optional, Recommended)

For first-time setup, fire a one-off SendCommand manually to confirm the SSM path works before relying on the schedule:

```bash
TEST_COMMAND_ID=$(aws --profile $PROFILE --region $REGION ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"sudo docker exec ${CONTAINER_NAME} date\"]" \
  --timeout-seconds 60 \
  --query 'Command.CommandId' --output text)

sleep 10

aws --profile $PROFILE --region $REGION ssm get-command-invocation \
  --command-id "$TEST_COMMAND_ID" \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status, Output:StandardOutputContent, Error:StandardErrorContent}' \
  --output table
```

If `Status: Success` with the current date in `Output`, the SSM path works and the schedule will fire correctly. We use plain `date` here (not `atx ct status`) so the test isolates the SSM mechanism from any backend auth or CT server issues -- those are validated separately when the actual scheduled `atx ct analysis run` fires.

If `Status: Failed` or `TimedOut`, debug:

- SSM agent reachable? `aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID"`
- Container running? `aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript --parameters 'commands=["sudo docker ps | grep atx-ct"]'`
- Instance role has `AmazonSSMManagedInstanceCore`? `aws iam list-attached-role-policies --role-name "${ROLE_ARN##*/}"` (using the role ARN discovered in Step 1)

## Schedule Management

### List schedules

```bash
aws --profile $PROFILE --region $REGION scheduler list-schedules \
  --group-name atx-control-tower \
  --query 'Schedules[].{Name:Name, State:State, NextRun:Target.RoleArn}' \
  --output table
```

### Disable temporarily (executor)

`scheduler:UpdateSchedule` is in the executor policy -- the agent runs this directly.

```bash
# Get current target then disable
TARGET=$(aws --profile $PROFILE --region $REGION scheduler get-schedule \
  --name "$SCHEDULE_NAME" --group-name atx-control-tower \
  --query 'Target' --output json)

aws --profile $PROFILE --region $REGION scheduler update-schedule \
  --name "$SCHEDULE_NAME" \
  --group-name atx-control-tower \
  --state DISABLED \
  --schedule-expression "$CRON_EXPR" \
  --schedule-expression-timezone "$TIMEZONE" \
  --flexible-time-window '{"Mode":"OFF"}' \
  --target "$TARGET"
```

### Re-enable (executor)

Same as Disable but with `--state ENABLED`.

### Delete permanently (executor)

`scheduler:DeleteSchedule` is in the executor policy, scoped to the `atx-control-tower` group. The agent runs this directly:

```bash
aws --profile $PROFILE --region $REGION scheduler delete-schedule \
  --name "$SCHEDULE_NAME" \
  --group-name atx-control-tower
```

### View invocation history (CloudWatch)

EventBridge Scheduler logs invocations to CloudWatch. To inspect:

```bash
aws --profile $PROFILE --region $REGION logs tail /aws/events/scheduler --since 7d
```

To inspect what the EC2 instance actually ran on a given schedule fire:

```bash
# List recent SSM command invocations against the instance
aws --profile $PROFILE --region $REGION ssm list-command-invocations \
  --instance-id "$INSTANCE_ID" \
  --query 'CommandInvocations[].{Time:RequestedDateTime, Status:Status, CommandId:CommandId}' \
  --output table

# Inspect the output of one
aws --profile $PROFILE --region $REGION ssm get-command-invocation \
  --command-id <CommandId> \
  --instance-id "$INSTANCE_ID" \
  --query '{Status:Status, Output:StandardOutputContent, Error:StandardErrorContent}' \
  --output table
```

## Edge Cases

| Scenario                                                     | What Happens                                                                                                      | Mitigation                                                                                                                                           |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| EC2 instance stopped at fire time                            | SSM SendCommand fails, schedule retries 2x with exponential backoff, then waits for next fire                     | Customer keeps instance running; or document instance-start step                                                                                     |
| Container `atx-ct` not running                               | `docker exec` fails inside the SSM command, returns non-zero                                                      | Step 10 of continuous-modernization-ec2-execution adds `--restart unless-stopped` so container survives reboot. Customer can verify with `docker ps` |
| Instance rebooted                                            | If `--restart unless-stopped` set on docker run: container auto-starts. If not: container is gone, schedule fails | Always use `--restart unless-stopped` (now baked into Step 10)                                                                                       |
| Two schedules fire simultaneously                            | Both `docker exec` calls arrive; CT server may serialize internally                                               | Avoid overlapping schedules during testing                                                                                                           |
| Customer terminates instance, schedule remains               | SSM SendCommand fails silently against the orphaned instance ID                                                   | Skill should warn during cleanup; or explicitly delete schedules before terminating instance                                                         |
| Schedule fires but command runs longer than `TimeoutSeconds` | Command is killed at the timeout; partial findings persist if CT pushed any                                       | Bump `TimeoutSeconds` (default 14400 = 4h here, max 172800 = 48h)                                                                                    |
| SSM agent loses connection mid-run                           | Command may be marked Failed in SSM but actually ran to completion on the instance                                | Verify findings via `atx ct findings list` before assuming the schedule failed                                                                       |

## Why SSM Instead of SSH

- SSH requires a key pair, public IP, and port 22 inbound -- Scheduler can't authenticate over SSH
- SSM uses outbound HTTPS only; agent is pre-installed on Amazon Linux 2023
- SSM Send-command is an AWS API call, which Scheduler natively supports
- IAM-controlled (no key management)

## Pricing

EventBridge Scheduler: free tier covers 14 million invocations/month (so cron-style schedules are effectively free). Beyond that, see [AWS pricing](https://aws.amazon.com/eventbridge/pricing/).

SSM SendCommand: no charge for the API call itself; you pay for whatever the EC2 instance does at runtime.

The EC2 instance and other costs are unchanged from the manual analysis flow -- see [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md) for those.

## Related Skills

- [continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md) -- sets up the EC2 instance + container that this schedule reuses
- [continuous-modernization-analysis](continuous-modernization-analysis.md) -- the underlying `atx ct analysis run` command details
- [continuous-modernization-status](continuous-modernization-status.md) -- check what analyses exist after a schedule fires
- [continuous-modernization-findings](continuous-modernization-findings.md) -- query findings produced by the scheduled analysis
