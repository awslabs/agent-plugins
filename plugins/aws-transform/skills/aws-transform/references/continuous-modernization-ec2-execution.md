---
name: ec2-execution
description: Run continuous modernization analysis or remediation on a single EC2 instance with one long-running atx-ct container. Customer launches the instance once (or reuses an existing one); agent submits work via SSM SendCommand. Each submission auto-polls and auto-uploads artifacts.
---

# continuous modernization EC2 Execution

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` -- the AI assistant driving this session (lowercase, no spaces). Use the real assistant name -- e.g. kiro, claude, amazonq, copilot.
- `executionMode` -- `ec2`

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

Run continuous modernization analysis or remediation on a single EC2 instance with **one long-running atx-ct container**. The customer provisions the instance via a **CloudFormation stack** (atomic deploy/rollback, single-command teardown) -- or reuses an existing one. The container hosts `atx ct server` and stays up between submissions. The agent submits work via SSM SendCommand -- each submission runs in the background on the instance and includes auto-upload of artifacts to S3 (for analysis on any provider, and for `--local` remediation; github/gitlab remediations push a result branch instead -- no S3 upload).

## When to Use

- Re-running multiple analyses against the same source(s) on the same compute
- Customer prefers a persistent dev box they can Session-Manager into
- Avoiding Batch cold-start (Fargate provisioning adds latency per job)
- Workloads that benefit from a warm container (multiple analyses without re-installing the CLI)

For one-shot or fan-out workloads (many sources analyzed in parallel), use [continuous-modernization-batch-execution](continuous-modernization-batch-execution.md) instead.

## Architecture

```
Customer's local machine                     EC2 instance (CFN-managed)
  ↓ atx ct source add                        ┌────────────────────────────────┐
  ↓ aws s3api create-bucket (idempotent)     │ atx-ct container (long-running)│
  ↓ aws cloudformation create-stack          │  - atx ct server (running)     │
                                             │                                │
[Setup, once via CFN]                        │  CFN stack contains:           │
  CFN provisions: IAM role, profile,         │  - 1× EC2 instance             │
  security group, EC2 instance.              │  - 1× IAM role + profile       │
  UserData installs Docker, pulls image, ────┼─→ - 1× security group          │
  starts container, signals CREATE_COMPLETE  │   (S3 buckets are outside the  │
                                             │    stack -- persist across      │
                                             │    delete-and-recreate)        │
[Per submission, via SSM]                    │                                │
  build_command_*() returns a nohup'd ───────┼─→ background script:           │
  chain; SSM returns immediately             │   1. fetch token from SecMgr   │
                                             │   2. atx ct analysis run       │
[Status check, on demand]                    │   3. poll status until done    │
  ssm_run "atx ct analysis get --id X" ──────┼─→ 4. /app/upload-ct-artifacts  │
                                             └────────────────────────────────┘
[Teardown]
  aws cloudformation delete-stack
  → instance + IAM + SG removed atomically
  (S3 buckets and Secrets Manager entries persist)
```

The container persists across submissions. Customer can run many analyses (or one analysis followed by remediation) without re-provisioning anything. The build_command_*() functions encapsulate the entire submit → poll → upload flow as one nohup'd script, so the agent stays free during long-running work. CFN's `CreationPolicy` ensures `CREATE_COMPLETE` only fires after UserData verifies the container is up -- there's no "is the container ready yet?" race.

## Provider Compatibility

| Provider      | Container setup at job time                                                                                                                                    | Analysis output           | Remediation flag     | Remediation output                                   |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- | -------------------- | ---------------------------------------------------- |
| **github**    | Fetch token from `atx/github-token` (Secrets Manager) → place in `~/.atxct/sources/<src>/github_token`                                                         | `code.zip` per repo in S3 | NO `--local`         | Result branch pushed to source repo and PR is opened |
| **gitlab**    | Fetch token from `atx/gitlab-token` → place in `~/.atxct/sources/<src>/gitlab_token`                                                                           | `code.zip` per repo in S3 | NO `--local`         | Result branch pushed to source repo and MR is opened |
| **bitbucket** | Fetch token from `atx/bitbucket-token` → place in `~/.atxct/sources/<src>/bitbucket_token` + inject `config.json` with email/username (Cloud) or base_url (DC) | `code.zip` per repo in S3 | NO `--local`         | Result branch pushed to source repo and PR is opened |
| **local**     | Pull bundle from S3 (Step 7), `discovery scan --path /home/atxuser/repos`                                                                                      | `code.zip` per repo in S3 | `--local` (required) | `code.zip` per repo in S3                            |

For github / gitlab / bitbucket, the customer must register the source on their own machine first via `atx ct source add --provider github|gitlab|bitbucket --org <name> --token <pat>`. The token is then stored in Secrets Manager (Step 4) and fetched by the container at job time. atx ct's async provider resolution queries the backend for source metadata (provider type, base URL, identifier) at clone time. Bitbucket additionally requires a `config.json` with email/username (Cloud) or base_url (Data Center) injected into the container -- unlike github/gitlab where the backend has all needed metadata.

## Multi-Worker Support

**Default behavior (`WorkerCount=1`): a single container** named `atx-ct` (legacy behavior), sized for the default `m5.2xlarge` (32 GB) with a 50 GB volume. Each worker runs its own atx ct server. The default is 1 because every worker is memory-capped at `(instance RAM - 4 GB) / WorkerCount`, so a higher WorkerCount must be paired with a larger InstanceType; defaulting to 1 keeps a no-preference customer on a right-sized box rather than over-provisioning. For multi-analysis parallelism the customer chooses N>1 and the laptop-side provisioning script auto-sizes the InstanceType to match (m5.4xlarge for 2-4, m5.8xlarge for 5). The agent targets a specific worker by setting `WORKER_NUM` (1..WorkerCount) before calling SSM helpers or `build_command_*()`.

To run multiple analyses in parallel, set `WORKER_COUNT` to any value in 1-5; the auto-sized instance type and disk grow to match. Note WorkerCount is fixed at stack-create time -- raising it later requires a destructive redeploy (see "Changing WorkerCount Requires Redeploy"), so a customer who knows they will need parallelism can opt into a higher count up front.

### Choosing WorkerCount

| Customer intent                                                           | WorkerCount                                                                             |
| ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| "Scan my source" / "tech-debt-quick on source X" / "find vulnerabilities" | 1 is sufficient                                                                         |
| Default (no specific parallelism request)                                 | 1 (right-sized m5.2xlarge; each worker is memory-capped, so 1 avoids over-provisioning) |
| "Run tech-debt AND security in parallel" on the same source               | 2+ (one per analysis type)                                                              |
| "Analyze sources A, B, C concurrently"                                    | 3+ (one per source)                                                                     |
| "Run a separate analysis on each repo in this source in parallel"         | N where N is the repo count, capped at 5                                                |
| 6+ truly parallel jobs                                                    | Use the Batch path instead (Fargate scales to 64 concurrent)                            |

If the customer's intent is unclear, ASK: "Do you want one analysis covering everything (single AID, simpler reporting), or N separate analyses running in parallel (one AID per item)?" Default to 1 if they have no preference; the laptop-side auto-sizing matches WorkerCount=1 to m5.2xlarge with a 50 GB volume, so they pay only for what they need. If they expect parallelism later, mention they can opt into a higher count now to avoid a destructive redeploy.

When proposing a WorkerCount for a new CFN stack in the consent prompt, ALWAYS include this warning: "Note: WorkerCount is fixed at stack-create time. Changing it later requires the admin to redeploy the stack (which causes downtime)." This warning does NOT apply to the existing-instance path; there's no stack to redeploy, and WorkerCount can be changed by stopping/starting containers.

### Sizing

Each worker uses ~3-4 vCPU average and ~4-8 GB RAM for typical single-repo analyses, peaking at ~16 GB for monorepos. The skill auto-picks based on WorkerCount:

- 1 worker: m5.2xlarge, 50 GB
- 2-4 workers: m5.4xlarge, 100-200 GB
- 5 workers: m5.8xlarge, 250-500 GB

The pre-deploy confirmation prompt shows the resolved config before the customer commits. Customer can override `INSTANCE_TYPE` and `VOLUME_SIZE` env vars to deviate from the auto-pick.

For monorepos (>5 GB working tree per repo) or running many source-wide analyses concurrently, override to `INSTANCE_TYPE=m5.12xlarge` (48 vCPU, 192 GB RAM) and `VOLUME_SIZE=1000`. The default sizing assumes typical single-repo fan-out work. Each worker has its own isolated filesystem inside its container, so repos cloned by worker 1 are not visible to worker 2.

### Bridge Networking

Multi-worker uses bridge networking (no `--net=host`) so each container has its own network namespace. The atx ct CLI to server communication is intra-container (`localhost`) so nothing outside needs to reach the server. SSM `docker exec` works the same as before. Single-worker (`WorkerCount=1`) also uses bridge mode, so there is no behavioral difference visible to the customer.

### Changing WorkerCount Requires Redeploy

**WorkerCount is fixed at stack-create time.** To change it, the customer runs a stack update which is destructive: the EC2 instance and EBS volume are REPLACED.

```bash
# Stack update: REPLACEMENT update because UserData contains ${WorkerCount}
aws cloudformation update-stack --stack-name atx-runner \
  --use-previous-template \
  --parameters \
    ParameterKey=WorkerCount,ParameterValue=$NEW_COUNT \
    ParameterKey=InstanceType,UsePreviousValue=true \
    ParameterKey=VpcId,UsePreviousValue=true \
    ParameterKey=SubnetId,UsePreviousValue=true \
    ParameterKey=VolumeSizeGB,UsePreviousValue=true \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION
```

**What is preserved:**

- Findings, AIDs, RIDs (live on the atx ct backend, independent of EC2)
- S3 artifacts already uploaded (`atx-ct-output-${ACCOUNT_ID}/<AID>/...`)
- IAM role, security group (in-place CFN updates)
- Source registrations in the backend
- Secrets in Secrets Manager (managed outside the stack)

**What is LOST with the EBS volume:**

- Cloned repo caches in `~/.atxct/sources/<src>/repos/`
- Build tool caches (Maven `.m2`, Gradle, npm, etc.)
- atx ct internal artifact cache
- Any in-flight wrapper scripts (analyses CONTINUE on the backend, but the EC2-side polling and S3 upload die)

**Before redeploying, the agent should:**

1. **Check for in-flight work** across all workers:

   ```bash
   for i in $(seq 1 $WORKER_COUNT); do
     if [ "$WORKER_COUNT" -eq 1 ]; then CONT="atx-ct"; else CONT="atx-ct-${i}"; fi
     ssm_run "sudo docker exec $CONT atx ct analysis list --json | jq '.items[] | select(.status == \"running\" or .status == \"pending\") | .id'" 2>/dev/null
     ssm_run "sudo docker exec $CONT atx ct remediation list --json | jq '.items[] | select(.status == \"running\" or .status == \"pending\") | .id'" 2>/dev/null
   done
   ```

2. **Warn the customer**: in-flight analyses on the backend will COMPLETE, but the EC2-side wrapper (polling + S3 upload) will be killed. Customer can re-trigger artifact upload after redeploy via (substitute `atx-ct` for `atx-ct-1` if WorkerCount=1):

   ```bash
   ssm_run "sudo docker exec atx-ct-1 /app/upload-ct-artifacts.sh <AID> atx-ct-output-${ACCOUNT_ID}"
   ```

3. **Recommend Batch path** if the customer's workload is HIGHLY VARIABLE in parallelism. EC2 multi-worker is best when WorkerCount is set once and rarely changed. For elastic demand (e.g., "1 baseline, occasional spike to 8"), Batch's Fargate scaling is cheaper and avoids the redeploy.

## Fan-out: Run Analysis on Each Repo in Parallel

When the customer says "run analysis on each repo in source X in parallel" (one AID per repo, all running concurrently), the agent fans out N analyses across the available workers. The pattern below handles three cases automatically: (1) fresh stack provisioning, (2) running on an existing stack with enough workers, and (3) running on an existing stack where REPO_COUNT exceeds WORKER_COUNT (chunked round-robin distribution).

```bash
# ──────────────────────────────────────────────────────────────────────────
# Step 1: Discover how many repos are in the source
# ──────────────────────────────────────────────────────────────────────────
# `discovery scan` outputs human-readable text (no --json flag in current CLI).
# Format of repo lines: "  <org>/<repo-name>                <language>"
# We extract the basename (after the last "/") because the --repo flag in Step 5
# expects "<source>::<repo-basename>" format (without the org prefix).
REPOS=$(atx ct discovery scan --source "$LOGICAL_SOURCE_NAME" 2>&1 \
  | awk 'NF >= 2 && $1 ~ /\// { sub(/.*\//, "", $1); print $1 }')
REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
[ -z "$REPOS" ] && REPO_COUNT=0   # echo "" | wc -l returns 1, guard against empty
echo "Source $LOGICAL_SOURCE_NAME has $REPO_COUNT repos"

if [ "$REPO_COUNT" -eq 0 ]; then
  echo "ERROR: No repos found in source $LOGICAL_SOURCE_NAME. Verify the source is registered and discovery scan succeeded."
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 2: Determine WORKER_COUNT (read from existing stack, existing instance, or pick for new)
# ──────────────────────────────────────────────────────────────────────────
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION >/dev/null 2>&1; then
  WORKER_COUNT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
    --query 'Stacks[0].Parameters[?ParameterKey==`WorkerCount`].ParameterValue' --output text 2>/dev/null)
  WORKER_COUNT=$(echo "$WORKER_COUNT" | xargs)   # strip whitespace defensively
  [ -z "$WORKER_COUNT" ] || [ "$WORKER_COUNT" = "None" ] && WORKER_COUNT=1
  echo "Using existing stack '$STACK_NAME' (WorkerCount=$WORKER_COUNT)"
elif [ -n "$INSTANCE_ID" ]; then
  # Existing instance (no CFN stack). WORKER_COUNT was set in Step C.1 based on
  # customer's choice and the instance's vCPU/RAM capacity. Default to 1 if not set.
  WORKER_COUNT="${WORKER_COUNT:-1}"
  echo "Using existing instance '$INSTANCE_ID' (WorkerCount=$WORKER_COUNT)"
else
  # No stack yet, no existing instance: pick WORKER_COUNT to match REPO_COUNT, capped at 5
  WORKER_COUNT=$(( REPO_COUNT > 5 ? 5 : REPO_COUNT ))
  echo "Will provision new stack with WorkerCount=$WORKER_COUNT"
  # ... agent runs the "Create New Instance" flow with this WORKER_COUNT ...
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 3: Decide strategy based on REPO_COUNT vs WORKER_COUNT
# ──────────────────────────────────────────────────────────────────────────
REPOS_PER_WORKER=$(( (REPO_COUNT + WORKER_COUNT - 1) / WORKER_COUNT ))   # ceiling

if [ "$REPO_COUNT" -le "$WORKER_COUNT" ]; then
  echo "Strategy: 1:1 fan-out ($REPO_COUNT repos across $WORKER_COUNT workers, $((WORKER_COUNT - REPO_COUNT)) idle)"
elif [ "$REPO_COUNT" -le $((WORKER_COUNT * 2)) ]; then
  echo "Strategy: chunked (slight overflow, no infra change needed)"
  echo "  $REPO_COUNT repos across $WORKER_COUNT workers, ~${REPOS_PER_WORKER} repos per worker"
  echo "  Alternative: ASK customer if they prefer the Batch path."
else
  echo "WARNING: $REPO_COUNT repos significantly exceeds $WORKER_COUNT workers."
  echo "  Strongly recommend the Batch path (handles up to 64 concurrent Fargate tasks)."
  # Agent should pause here and ask the customer to choose chunked vs Batch
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 4: Round-robin distribution of repos across workers
# ──────────────────────────────────────────────────────────────────────────
# Round-robin (NOT chunked-by-REPOS_PER_WORKER) ensures even utilization.
# Example for 7 repos / 5 workers:
#   workers 1-2 get 2 repos each (run sequentially within the worker)
#   workers 3-5 get 1 repo each (then idle)
declare -A WORKER_REPOS
i=0
for REPO in $REPOS; do
  WORKER_NUM=$(( (i % WORKER_COUNT) + 1 ))
  WORKER_REPOS[$WORKER_NUM]+="$REPO "
  i=$((i + 1))
done

# ──────────────────────────────────────────────────────────────────────────
# Step 4.5: For local provider, pre-sync the repos bundle to ALL workers
# ──────────────────────────────────────────────────────────────────────────
# Local provider analyses require the repos bundle to be present in each
# worker's filesystem (containers are filesystem-isolated). github/gitlab/
# bitbucket fetch repos via API at job time, so no pre-sync needed.
#
# IMPORTANT: this sync is IDEMPOTENT but SOURCE-AWARE. We track which source's
# repos are present via /home/atxuser/repos/.atx_source_marker:
#   - If marker matches the current source AND repo dirs are present: skip sync
#     (preserves atx ct's result-staging branches from prior analyses on this source)
#   - If marker is missing, mismatched, or no repo dirs exist: wipe and re-sync
#     (prevents source A's repos from contaminating source B's analysis)
# Counting uses `find -type d` so stray files (e.g., .DS_Store, lock files) don't
# falsely satisfy the "has repos" check.
if [ "$PROVIDER" = "local" ]; then
  echo "Checking local-provider bundle state on all $WORKER_COUNT workers..."
  ssm_run "for c in \$(sudo docker ps --filter name=atx-ct --format '{{.Names}}'); do \
    CURRENT_SOURCE=\$(sudo docker exec \$c cat /home/atxuser/repos/.atx_source_marker 2>/dev/null || echo ''); \
    REPO_COUNT=\$(sudo docker exec \$c bash -c 'find /home/atxuser/repos -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l' || echo 0); \
    if [ \"\$CURRENT_SOURCE\" = \"${LOGICAL_SOURCE_NAME}\" ] && [ \"\$REPO_COUNT\" -gt 0 ]; then \
      echo \"  \$c: has ${LOGICAL_SOURCE_NAME} repos (\$REPO_COUNT dir(s)), skipping sync to preserve atx ct state\"; \
    else \
      echo \"  \$c: syncing ${LOGICAL_SOURCE_NAME} bundle from S3 (was: \${CURRENT_SOURCE:-empty})\"; \
      sudo docker exec \$c bash -c 'rm -rf /home/atxuser/repos && mkdir -p /home/atxuser/repos /tmp/zips && \
        aws s3 sync s3://atx-source-code-${ACCOUNT_ID}/repos/ /tmp/zips/ && \
        for zip in /tmp/zips/*.zip; do unzip -q -o \"\\\$zip\" -d /home/atxuser/repos/; done && \
        echo ${LOGICAL_SOURCE_NAME} > /home/atxuser/repos/.atx_source_marker'; \
    fi; \
  done"
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 5: Submit ALL workers via a SINGLE SSM command (each handles its assigned repos serially)
# ──────────────────────────────────────────────────────────────────────────
# Why a single SSM command + double-fork instead of N per-worker submissions:
# SSM's process tracking holds the command slot until all descendants exit
# (the cgroup is empty). Per-worker SSM commands would each stay InProgress
# until each wrapper completes, saturating the SSM agent's worker pool
# (CommandWorkersLimit default 5) and blocking subsequent status-check calls.
# The `( ( bash X & ) & )` double-fork orphans the wrapper to init (PID 1),
# letting the SSM command return Success immediately while wrappers run.
TS=$(date +%s)
MASTER="#!/bin/bash
"
for WORKER_NUM in $(seq 1 $WORKER_COUNT); do
  REPOS_FOR_THIS_WORKER="${WORKER_REPOS[$WORKER_NUM]}"
  [ -z "$REPOS_FOR_THIS_WORKER" ] && continue   # skip workers with no assignment

  # Resolve container name (legacy "atx-ct" if WorkerCount=1, else "atx-ct-N")
  if [ "$WORKER_COUNT" -eq 1 ]; then
    CONT="atx-ct"
  else
    CONT="atx-ct-${WORKER_NUM}"
  fi

  # Build provider-specific TOKEN_PRELUDE (mirrors build_command_analysis()).
  # github/gitlab: fetch token from Secrets Manager into ~/.atxct/sources/<src>/.
  # bitbucket: fetch token + inject config.json with email/username (Cloud) or base_url (DC).
  # local: no prelude (repos already pre-synced in Step 4.5).
  TOKEN_PRELUDE=""
  if [ "$PROVIDER" = "github" ] || [ "$PROVIDER" = "gitlab" ]; then
    SECRET_ID="atx/${PROVIDER}-token"
    TOKEN_FILE="${PROVIDER}_token"
    TOKEN_PRELUDE="sudo docker exec ${CONT} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE} && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE}'"
  elif [ "$PROVIDER" = "bitbucket" ]; then
    if [ -n "${BITBUCKET_BASE_URL}" ]; then
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
    else
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
    fi
    CONFIG_B64=$(echo "${config_json}" | base64 -w 0)
    TOKEN_PRELUDE="sudo docker exec ${CONT} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token'"
  fi

  JOB_ID="fan-w${WORKER_NUM}-${TS}"

  # Per-worker script: loops through its assigned repos and runs analysis on each.
  # Continues on failure (so other repos still get analyzed). Each repo emits its own AID.
  SCRIPT=$(cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-${JOB_ID}.log
AIDS_FILE=/tmp/atxct-${JOB_ID}.aids
echo "=== \$(date) [START] worker ${WORKER_NUM} repos: ${REPOS_FOR_THIS_WORKER}===" >> \$LOG

${TOKEN_PRELUDE}

for REPO in ${REPOS_FOR_THIS_WORKER}; do
  echo "--- \$(date) starting analysis on \$REPO (worker ${WORKER_NUM}) ---" >> \$LOG
  sudo docker exec ${CONT} atx ct analysis run \\
    --type ${ANALYSIS_TYPE} ${EXTRA_FLAGS} --source ${LOGICAL_SOURCE_NAME} --repo "${LOGICAL_SOURCE_NAME}::\$REPO" --wait --telemetry "agent=${AGENT},executionMode=ec2" >> \$LOG 2>&1
  RC=\$?
  AID=\$(tail -50 \$LOG | grep -oE '01[A-Z0-9]+' | tail -1)
  echo "\$REPO -> \$AID (rc=\$RC)" >> \$AIDS_FILE
  if [ "${UPLOAD_ARTIFACTS:-true}" = "true" ] && [ "${ANALYSIS_TYPE}" != "tech-debt-quick" ] && [ -n "\$AID" ] && [ \$RC -eq 0 ]; then
    sudo docker exec ${CONT} /app/upload-ct-artifacts.sh \$AID atx-ct-output-${ACCOUNT_ID} >> \$LOG 2>&1
  fi
done

echo "=== \$(date) [DONE] worker ${WORKER_NUM} ===" >> \$LOG
EOF
)

  B64=$(echo "$SCRIPT" | base64 | tr -d '\n')
  # Append decode + double-fork stanza for this worker to the master launcher
  MASTER+="echo ${B64} | base64 -d > /tmp/${JOB_ID}.sh && chmod +x /tmp/${JOB_ID}.sh && ( ( bash /tmp/${JOB_ID}.sh > /tmp/${JOB_ID}.stdout 2>&1 < /dev/null & ) & ) && echo Launched_w${WORKER_NUM}
"
done
MASTER+="echo ALL_LAUNCHED"

# Submit the master launcher as a SINGLE SSM command. Wrappers run as orphaned
# background processes; this command itself exits immediately.
MASTER_B64=$(echo "$MASTER" | base64 | tr -d '\n')
SUBMIT_ID=$(ssm_submit "echo ${MASTER_B64} | base64 -d > /tmp/master-${TS}.sh && chmod +x /tmp/master-${TS}.sh && bash /tmp/master-${TS}.sh")
echo "Launched all $WORKER_COUNT workers via single SSM command (id: $SUBMIT_ID)"

# ──────────────────────────────────────────────────────────────────────────
# Step 6: Poll status across all workers (agent helper)
# ──────────────────────────────────────────────────────────────────────────
# Each worker writes AIDs to /tmp/atxct-fan-w${N}-${TS}.aids as repos finish.
# To check overall progress:
#   for w in $(seq 1 $WORKER_COUNT); do
#     ssm_run "cat /tmp/atxct-fan-w${w}-*.aids 2>/dev/null"
#   done
# When all workers' AIDS files match their assigned repo count, fan-out is complete.
```

The agent should **report all N AIDs back** to the customer once each worker emits them (typically as each repo finishes, staggered as workers complete their assigned repos in sequence).

## Fan-out: Run Remediation on Each Repo in Parallel

Same round-robin distribution as the analysis fan-out, but each worker runs `atx ct remediation create` (not `atx ct analysis run`). The provider differences match `build_command_remediation()`: github/gitlab/bitbucket push result branches automatically (no S3 upload); local provider requires explicit `--local` flag and S3 upload of the remediated code.

Use this when the customer says "remediate each repo in source X in parallel" (one RID per repo). Steps 1-4 are identical to the analysis fan-out (discover repos, determine WORKER_COUNT, decide strategy, round-robin distribute). Step 4.5 (local-provider repo sync) also applies and is source-aware: if a prior analysis on the same source already populated `/home/atxuser/repos/` on each worker, Step 4.5 skips the re-sync to preserve atx ct's branch state from that operation. If the customer switched to a different source, Step 4.5 wipes and re-syncs to prevent contamination. The differences are in Step 5 below.

**`--transformation-name` vs `--ids` mode**: the fan-out below runs Mode 3 from [continuous-modernization-remediation](continuous-modernization-remediation.md), which uses `--transformation-name` per repo with `--repo "<source>::<basename>"`. For finding-driven remediation (Modes 1 or 2), distribute finding IDs across workers in chunks instead of repos: each worker calls `atx ct remediation create --ids <chunk>` WITHOUT `--repo` (atx ct rejects `--repo` with `--ids` because repos are derived from findings). Extract auto-remediable IDs from a prior analysis with: `atx ct findings list --analysis-id $AID --json | jq -r '.[] | select(.auto_remediable == true) | .id'`.

```bash
# Steps 1-4.5: same as analysis fan-out (REPOS, REPO_COUNT, WORKER_COUNT,
# WORKER_REPOS round-robin assignment, local-provider repo sync if applicable)

# Build CREATE_ARGS based on remediation mode (mirrors build_command_remediation)
if [ -n "$FINDING_IDS" ]; then
  CREATE_ARGS_BASE="--ids ${FINDING_IDS}"
  [ -n "${TRANSFORMATION_NAME}" ] && CREATE_ARGS_BASE="${CREATE_ARGS_BASE} --transformation-name ${TRANSFORMATION_NAME}"
else
  CREATE_ARGS_BASE="--transformation-name ${TRANSFORMATION_NAME}"
fi
[ -n "${CONFIGURATION}" ] && CREATE_ARGS_BASE="${CREATE_ARGS_BASE} -g \"${CONFIGURATION}\""

# Provider-aware --local flag and upload behavior
LOCAL_FLAG=""
UPLOAD_REMED_LINE='echo "[skip upload: github/gitlab/bitbucket pushes results to source repo]"'
if [ "$PROVIDER" = "local" ]; then
  LOCAL_FLAG="--local"
  # UPLOAD_REMED_LINE set per-worker below (uses ${CONT})
fi

# ──────────────────────────────────────────────────────────────────────────
# Step 5: Submit ALL remediations via a SINGLE SSM command (each worker handles assigned repos serially)
# ──────────────────────────────────────────────────────────────────────────
# Same single-SSM + double-fork rationale as the analysis fan-out: one command
# submission orphans all wrappers to init so SSM returns immediately and status
# checks aren't queued behind the wrappers.
TS=$(date +%s)
MASTER="#!/bin/bash
"
for WORKER_NUM in $(seq 1 $WORKER_COUNT); do
  REPOS_FOR_THIS_WORKER="${WORKER_REPOS[$WORKER_NUM]}"
  [ -z "$REPOS_FOR_THIS_WORKER" ] && continue

  # Resolve container name (same as analysis fan-out)
  if [ "$WORKER_COUNT" -eq 1 ]; then
    CONT="atx-ct"
  else
    CONT="atx-ct-${WORKER_NUM}"
  fi

  # Build TOKEN_PRELUDE (same as analysis fan-out's logic for github/gitlab/bitbucket)
  TOKEN_PRELUDE=""
  if [ "$PROVIDER" = "github" ] || [ "$PROVIDER" = "gitlab" ]; then
    SECRET_ID="atx/${PROVIDER}-token"
    TOKEN_FILE="${PROVIDER}_token"
    TOKEN_PRELUDE="sudo docker exec ${CONT} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE} && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE}'"
  elif [ "$PROVIDER" = "bitbucket" ]; then
    if [ -n "${BITBUCKET_BASE_URL}" ]; then
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
    else
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
    fi
    CONFIG_B64=$(echo "${config_json}" | base64 -w 0)
    TOKEN_PRELUDE="sudo docker exec ${CONT} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token'"
  fi

  # Per-worker upload line (only meaningful for local provider)
  WORKER_UPLOAD_LINE='echo "[skip upload: github/gitlab/bitbucket pushes to source repo]"'
  if [ "$PROVIDER" = "local" ]; then
    WORKER_UPLOAD_LINE="sudo docker exec ${CONT} /app/upload-ct-artifacts.sh \\\$RID atx-ct-output-${ACCOUNT_ID}"
  fi

  JOB_ID="fan-rem-w${WORKER_NUM}-${TS}"

  # Per-worker remediation script: loops through assigned repos.
  # Continues on failure. Polls each remediation until terminal status.
  # Uploads to S3 only for local provider.
  SCRIPT=$(cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-${JOB_ID}.log
RIDS_FILE=/tmp/atxct-${JOB_ID}.rids
echo "=== \$(date) [START] worker ${WORKER_NUM} repos: ${REPOS_FOR_THIS_WORKER}===" >> \$LOG

${TOKEN_PRELUDE}

for REPO in ${REPOS_FOR_THIS_WORKER}; do
  echo "--- \$(date) starting remediation on \$REPO (worker ${WORKER_NUM}) ---" >> \$LOG
  sudo docker exec ${CONT} atx ct remediation create \\
    ${CREATE_ARGS_BASE} ${LOCAL_FLAG} --source ${LOGICAL_SOURCE_NAME} --repo "${LOGICAL_SOURCE_NAME}::\$REPO" --telemetry "agent=${AGENT},executionMode=ec2" >> \$LOG 2>&1
  RC=\$?
  RID=\$(tail -50 \$LOG | grep -oE '01[A-Z0-9]+' | tail -1)
  echo "\$REPO -> \$RID (rc=\$RC)" >> \$RIDS_FILE

  # Poll until terminal status
  if [ -n "\$RID" ] && [ \$RC -eq 0 ]; then
    while true; do
      STATUS=\$(sudo docker exec ${CONT} atx ct remediation status --id \$RID --json 2>/dev/null | jq -r .status 2>/dev/null)
      case "\$STATUS" in
        complete|completed|failed|cancelled) break ;;
      esac
      sleep 30
    done
    echo "\$REPO -> \$RID terminal: \$STATUS" >> \$LOG

    # Upload artifacts (only meaningful for local; github/gitlab/bitbucket skip)
    if [ "\$STATUS" = "complete" ] || [ "\$STATUS" = "completed" ]; then
      ${WORKER_UPLOAD_LINE} >> \$LOG 2>&1
    fi
  fi
done

echo "=== \$(date) [DONE] worker ${WORKER_NUM} ===" >> \$LOG
EOF
)

  B64=$(echo "$SCRIPT" | base64 | tr -d '\n')
  # Append decode + double-fork stanza for this worker to the master launcher
  MASTER+="echo ${B64} | base64 -d > /tmp/${JOB_ID}.sh && chmod +x /tmp/${JOB_ID}.sh && ( ( bash /tmp/${JOB_ID}.sh > /tmp/${JOB_ID}.stdout 2>&1 < /dev/null & ) & ) && echo Launched_w${WORKER_NUM}
"
done
MASTER+="echo ALL_LAUNCHED"

# Submit the master launcher as a SINGLE SSM command. Wrappers run as orphaned
# background processes; this command itself exits immediately.
MASTER_B64=$(echo "$MASTER" | base64 | tr -d '\n')
SUBMIT_ID=$(ssm_submit "echo ${MASTER_B64} | base64 -d > /tmp/master-${TS}.sh && chmod +x /tmp/master-${TS}.sh && bash /tmp/master-${TS}.sh")
echo "Launched all $WORKER_COUNT remediation workers via single SSM command (id: $SUBMIT_ID)"

# Step 6: Poll status across workers (same pattern as analysis fan-out)
# Each worker writes RIDs to /tmp/atxct-fan-rem-w${N}-${TS}.rids as repos finish.
```

The agent should **report all N RIDs back** to the customer. For github/gitlab/bitbucket, customers will see N PRs/MRs created in their source provider. For local, customers can download the remediated code from `s3://atx-ct-output-${ACCOUNT_ID}/<RID>/` after each remediation completes.

## Setup Paths

Step 0 below detects which one of three states applies and routes accordingly:

| Path                              | Trigger                                                | Admin handoff?                                             |
| --------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------- |
| **Operate existing CFN stack**    | `describe-stacks atx-runner` returns `CREATE_COMPLETE` | No -- executor creds suffice                               |
| **Use existing non-CFN instance** | No stack, customer has their own EC2 instance          | Only if the instance lacks the `atx-remote-infra=true` tag |
| **Provision a new CFN stack**     | No stack, no existing instance                         | Yes -- admin runs `aws cloudformation create-stack` once   |

## Two-Persona Permission Model

Provisioning and operating the runner are split across two distinct IAM personas. The skill respects this split: the agent NEVER asks the executor to run a privileged provisioning command, and NEVER asks the admin to run a routine job submission.

| Persona      | Managed policy                                                                                                               | Owns                                                                                                                                                                                                                                                                                                                                                                                                                                                             | When used                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Admin**    | (any identity with the permissions listed below -- typically full admin / `AdministratorAccess` or an org-scoped admin role) | All resource-lifecycle mutations: `iam:Create/Put/Delete*` on `atx-transform-*`, `cloudformation:CreateStack`/`DeleteStack`, `ec2:RunInstances`/`CreateSecurityGroup`/`CreateKeyPair`/`TerminateInstances`/`DeleteSecurityGroup`/`DeleteKeyPair`, `s3:CreateBucket`+lifecycle, `scheduler:CreateScheduleGroup`, `ec2:AssociateIamInstanceProfile`/`ModifyInstanceMetadataOptions`                                                                                | Initial setup (buckets + stack) and teardown (`delete-stack`)                                |
| **Executor** | (a least-privilege role scoped to the actions listed below)                                                                  | Read-only CFN/EC2/SSM, SSM SendCommand on tagged, S3 data plane on `atx-*` buckets, `secretsmanager:GetSecretValue`/`DescribeSecret` on `atx/*` (read only), `ec2:Start/StopInstances` on tagged (power state), KMS-via-alias, `scheduler:CreateSchedule`/`DeleteSchedule`/`GetSchedule`/`UpdateSchedule`/`ListSchedules` (scoped to `atx-control-tower` group), `iam:PassRole` to `atx-transform-role*` (EC2) and `AtxSchedulerInvocationRole` (scheduler) only | Every analysis / remediation submission, status check, artifact fetch, schedule pause/resume |

The executor policy has **zero IAM mutations and zero resource-lifecycle creations**. Privilege-escalation surface is bounded to the admin handoff at stack create/delete, not the day-to-day developer flow.

### Skill flow at every entry

```
Entry (executor creds -- agent always assumes least privilege)
  │
  └─ Step 5: DETECT (read-only -- describe-stacks)
       ├─ NOT_DEPLOYED ─────► PROVISION
       │                        Agent prints template + create-stack command
       │                        with admin caveat. STOPS. User runs it
       │                        with admin creds outside the agent. User
       │                        re-enters the flow when done.
       │
       └─ EXISTS & healthy ──► OPERATE
                                Steps 6–10 run with executor creds only.
```

Detection is read-only and always safe. Only `create-stack` and `delete-stack` need admin, and the agent hands those to the user.

## Step 0: Detect Existing Infrastructure

ALWAYS run this first, on every entry to the flow. Uses only read-only calls (`cloudformation:DescribeStacks`, `ec2:DescribeInstances`) -- both in the executor policy, so it never fails on permissions. The result decides which path the rest of the skill takes.

```bash
STACK_NAME="${STACK_NAME:-atx-runner}"
REGION="${REGION:-$(aws configure get region || echo us-east-1)}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
  --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

case "$STACK_STATUS" in
  CREATE_COMPLETE|UPDATE_COMPLETE)
    INSTANCE_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
      --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' --output text)
    echo "OPERATE (Case A) -- CFN stack '$STACK_NAME' exists. Instance: $INSTANCE_ID"
    # Skip to Step 6 (Verify the Container is Running). Executor creds suffice.
    ;;
  CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS)
    echo "WAIT -- stack is mid-transition ($STACK_STATUS). Re-run when the admin's"
    echo "       deploy finishes:"
    echo "         aws cloudformation wait stack-create-complete \\"
    echo "           --stack-name $STACK_NAME --region $REGION"
    exit 0
    ;;
  DELETE_IN_PROGRESS)
    echo "WAIT -- stack is being deleted ($STACK_STATUS). Wait for deletion to finish,"
    echo "       then re-run this flow to provision a new stack:"
    echo "         aws cloudformation wait stack-delete-complete \\"
    echo "           --stack-name $STACK_NAME --region $REGION"
    exit 0
    ;;
  CREATE_FAILED|*ROLLBACK*|DELETE_FAILED)
    echo "BLOCKED -- stack is in $STACK_STATUS. The admin must clean it up first:"
    echo "  aws cloudformation describe-stack-events --stack-name $STACK_NAME --region $REGION"
    echo "  aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION   # admin"
    exit 1
    ;;
  "")
    # No CFN stack -- agent asks which of the two remaining paths applies.
    ;;
esac
```

If `STACK_STATUS` was empty, the agent MUST ask the customer:

> "I don't see an `atx-runner` CFN stack in `${REGION}`. Which path applies?
>
> 1. **Reuse an existing EC2 instance** I already have (launched outside CFN -- e.g., my org's standard EC2, or a dev box I already use)
> 2. **Create a new CFN-managed runner from scratch** (requires admin to run a one-time deploy command outside the agent)"

| Customer answer         | Path                                                                                        | Admin needed?                                                                                                                                                        |
| ----------------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Existing instance    | OPERATE -- see [Use Existing Instance (no CFN)](#use-existing-instance-no-cfn), then Step 6 | Only if the instance lacks the `atx-remote-infra=true` tag or the `atx-transform-access` inline policy on its role (Step C.0 detects and emits one combined handoff) |
| 2. Create new CFN stack | PROVISION -- Steps 1–5 below                                                                | **Yes**, for one command at the end of Step 5                                                                                                                        |

Steps 1–5 below only apply to path 2.

## Provision Lifecycle (Steps 1–5, fresh CFN stack)

These steps run **only when the customer chose path 2 in Step 0**. Steps 1–4 stay on executor creds -- they collect inputs and stage credentials. Step 5 then prints a self-contained `aws cloudformation create-stack` command for the customer's **admin** to run; the agent does NOT execute it.

### Step 1: Verify Source and Enumerate Repos

Confirm a source is registered locally (see [continuous-modernization-source.md](continuous-modernization-source.md)) and run discovery (see [continuous-modernization-discovery.md](continuous-modernization-discovery.md)) to get the list of repos. This determines instance size (Step 2) and gives the customer visibility into what will be analyzed.

```bash
atx ct source list
```

Show the list to the customer and ask:

1. **Which source to analyze?** (pick from the list above)
2. **Source type:** GitHub, GitLab, Bitbucket, or local
3. **Analysis type:** `tech-debt-comprehensive`, `tech-debt-quick`, `security`, `agentic-readiness`, `modernization-readiness`, or `custom`

If the list is empty, the customer wants to register a new source, or needs to update the token on an existing source, use the [continuous-modernization-source](continuous-modernization-source.md) skill (`source add` for new, `source update` for existing), then return here.

```bash
LOGICAL_SOURCE_NAME="<picked-source-name>"

atx ct discovery scan --source "$LOGICAL_SOURCE_NAME"

mapfile -t REPOS < <(atx ct repository list --source "$LOGICAL_SOURCE_NAME" --json | jq -r '.items[].full_name')
REPO_COUNT=${#REPOS[@]}

echo "Source ${LOGICAL_SOURCE_NAME} has ${REPO_COUNT} repos"
```

If the customer wants only a subset, set `REPO_FILTER="--repo <source>::<repo>"` for use in Step 8. The `--repo` flag accepts exactly ONE repo per invocation -- to analyze multiple repos in parallel, use the fan-out pattern (one submission per repo across workers). Empty = analyze the whole source.

### Step 2: Determine Instance Size

Default: `m5.2xlarge` (8 vCPU, 32 GB RAM) -- handles repo counts of any size for sequential execution. If a repo is unusually large (>5 GB working tree, e.g., a monorepo), bump up by one tier for RAM headroom.

```bash
INSTANCE_TYPE="m5.2xlarge"
```

### Step 3: Confirm Account and Plan

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region || echo "us-east-1")
```

Tell the user:

> "I'll set up CT analysis on a new EC2 instance in account `${ACCOUNT_ID}`, region `${REGION}`. This includes:
>
> - IAM role + instance profile (`atx-transform-role`, `atx-transform-profile`) with SSM Managed Instance Core for shell access
> - Security group (no inbound ports -- SSM SendCommand handles all access via outbound HTTPS)
> - `${INSTANCE_TYPE}` EC2 instance with 100GB volume
> - S3 source bucket (only if local source) and atx-ct-output bucket (always)
>
> Continue?"

Wait for explicit confirmation.

### Step 4: Prep Credentials

Give the user the relevant command below to run in their own terminal -- do not ask them to paste the token into this chat.

Tokens are stored in AWS Secrets Manager and fetched by the container at job submission time (the EC2 instance role has `secretsmanager:GetSecretValue` for `atx/*`). This is the same pattern as the batch skill -- store once, use for any number of analyses without re-staging files.

**GitHub HTTPS -- store the PAT:**

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/github-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/github-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**GitLab HTTPS -- store the PAT:**

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/gitlab-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/gitlab-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**Bitbucket -- store the API token** (the container fetches it from Secrets Manager at job start). Email and username are injected into the container command directly (not secrets -- they're non-sensitive identifiers):

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/bitbucket-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/bitbucket-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**SSH -- store the private key:**

```bash
aws secretsmanager create-secret --name "atx/ssh-key" \
  --secret-string "$(cat <path-to-private-key>)" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/ssh-key" \
       --secret-string "$(cat <path-to-private-key>)"
```

**Private package registries** (if the analysis builds the project): see [custom-remote-execution#private-package-registries](custom-remote-execution.md#private-package-registries) for the `atx/credentials` JSON pattern.

A single token can be used for any number of sources of the same provider (e.g., one PAT for all your GitHub orgs). The build_command_*() in Step 8 fetches the token and writes it to the source-specific path the CT server expects.

### Step 5: Provision Infrastructure via CloudFormation

Provisioning is done through a single CloudFormation stack -- atomic deploy/rollback, single command teardown, full visibility in the customer's CloudFormation console. The stack provisions:

- IAM role + instance profile (with transform-custom + S3 + KMS + Secrets Manager + securityagent permissions and `AmazonSSMManagedInstanceCore` attached for SSM)
- Security group (no inbound; outbound default allow)
- EC2 instance (Amazon Linux 2023, 100 GB gp3 volume)
- UserData that installs Docker, pulls the atx-ct image, and starts the container

S3 buckets (`atx-source-code-${ACCOUNT_ID}`, `atx-ct-output-${ACCOUNT_ID}`) are managed OUTSIDE the stack -- they hold persistent customer data, must survive stack delete-and-recreate, and are shared across multiple stacks if the customer ever runs more than one.

**Step 5a: Check whether S3 buckets exist (executor: read-only):**

`s3:CreateBucket` and `s3:PutLifecycleConfiguration` are in the **admin** policy, not executor. Bucket creation is bundled into the admin handoff in Step 5d so the admin runs all the privileged setup commands in one shell session. Here, the agent only checks whether the buckets already exist (`head-bucket` is read-only).

```bash
SOURCE_BUCKET_EXISTS=$(aws s3api head-bucket --bucket atx-source-code-${ACCOUNT_ID} 2>/dev/null && echo yes || echo no)
OUTPUT_BUCKET_EXISTS=$(aws s3api head-bucket --bucket atx-ct-output-${ACCOUNT_ID} 2>/dev/null && echo yes || echo no)
echo "atx-source-code-${ACCOUNT_ID}: $SOURCE_BUCKET_EXISTS"
echo "atx-ct-output-${ACCOUNT_ID}:  $OUTPUT_BUCKET_EXISTS"
```

If both are `yes`, the agent omits the bucket-creation lines from Step 5d's admin handoff (they're idempotent, but cleaner to omit). If either is `no`, the admin handoff includes the `aws s3api create-bucket` + `put-bucket-lifecycle-configuration` calls before the `cloudformation create-stack` line.

**Step 5b: Cascading list-and-pick -- VPC, then subnet, then security group, then final confirmation.**

The skill **never creates a VPC, subnet, or NAT** -- those are customer-owned network resources. The agent's job is to **list what already exists in the account**, let the customer pick each, and run validations on the chosen network before the admin handoff fires.

The flow is cascading: pick VPC first (so subnet/SG lists can be filtered to that VPC), then subnet, then SG, then a final summary the customer must explicitly confirm before Step 5c proceeds. Customers with self-hosted / internal git hosts can pick a VPC that has VPN / Direct Connect / peering to that host -- same flow, same UX, the customer just picks a different VPC.

**MANDATORY interaction rules. The agent MUST follow these without exception:**

- **The agent MUST NOT pre-select** a VPC, subnet, or security group -- not even if "obvious," "functionally equivalent," or "sensible default." Every choice belongs to the customer.
- **The agent MUST present each list and STOP**, waiting for the customer to type their explicit choice. No proceeding to the next step until the customer has answered the current one.
- **After the third selection** (security group), the agent MUST display all four selections (VPC, subnet, SG, AZ) in a final summary and **explicitly ask "proceed with these?"**. The agent MUST NOT advance to Step 5c (write CFN template) until the customer types `yes` or equivalent.
- **If the agent is inclined to skip an ask** ("they said use default VPC, I can pick the subnet myself"): STOP. The customer's "use default VPC" answer is ONLY about the VPC. Subnet and SG remain unanswered until the customer types those choices too.

```bash
EXISTING_SG_ID="${EXISTING_SG_ID:-}"   # empty means stack creates a new no-inbound SG

# ──────────────────────────────────────────────────────────────────────────
# 1. List VPCs in the account+region. Show ID, default flag, Name tag.
# ──────────────────────────────────────────────────────────────────────────
echo "VPCs available in account ${ACCOUNT_ID}, region ${REGION}:"
aws ec2 describe-vpcs --region $REGION \
  --query 'Vpcs[*].{VpcId:VpcId,Default:IsDefault,Cidr:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

VPC_COUNT=$(aws ec2 describe-vpcs --region $REGION --query 'length(Vpcs)' --output text)
DEFAULT_VPC_COUNT=$(aws ec2 describe-vpcs --region $REGION --filters Name=isDefault,Values=true --query 'length(Vpcs)' --output text)
```

**Two account-state cases the agent MUST handle explicitly before continuing:**

**Case 1 -- `VPC_COUNT=0`: no VPCs at all in this account+region.**

The skill **never creates VPCs** -- that's an infrastructure decision the customer's network team must make. The agent MUST stop and tell the customer:

> "There are no VPCs in account `${ACCOUNT_ID}`, region `${REGION}`.
>
> The skill cannot proceed without a VPC, and it does NOT auto-create one -- VPCs are foundational network infrastructure that should be set up by your network or platform team, not by an analysis tool.
>
> Ask whoever owns AWS networking in your org to:
>
> 1. Create a VPC (or restore the deleted default VPC) in this region
> 2. Add at least one subnet with outbound internet access (NAT gateway, internet gateway, or transit gateway)
> 3. Optionally, prepare a security group with allow-all-egress on TCP 443 (or scope to specific endpoints)
>
> Once that exists, come back to this conversation and I'll re-run the VPC list."

The agent then STOPS this turn. Don't try to work around it.

**Case 2 -- `VPC_COUNT≥1` but `DEFAULT_VPC_COUNT=0`: VPCs exist but none are marked default.**

This is normal in enterprise accounts where the default VPC was deliberately deleted (security baseline, AWS Landing Zone, Control Tower OUs). The customer just needs to pick one of the non-default VPCs. The agent presents the list with the same ASK as the next step -- the absence of a default VPC isn't an error, just slightly different framing:

> "I don't see a default VPC in this region -- that's normal in enterprise accounts. Here are the VPCs that DO exist; please pick the one your runner should deploy into."

The list-and-pick flow below handles both Case 2 and the simple-default case. Only Case 1 stops the flow.

```bash
if [ "$VPC_COUNT" = "0" ]; then
  echo "ERROR: No VPCs in account ${ACCOUNT_ID}, region ${REGION}."
  echo "       The skill does NOT auto-create VPCs. Ask your network team to provision"
  echo "       a VPC + subnet (with NAT/IGW/TGW egress) before re-running."
  exit 1
fi
```

**STOP HERE.** The agent MUST present the list above and ask the customer which VPC to use. The agent MUST NOT proceed to listing subnets until the customer has typed a VPC ID. Suggested phrasing:

> "Here are the VPCs in your account. Which one should the runner be deployed in?
> If you have a self-hosted git host (GHES, GitLab self-managed, Bitbucket DC), pick the VPC that has VPN / Direct Connect / peering routes to it.
> If you're using public github/gitlab/bitbucket, the default VPC works, but you may prefer a workload VPC for better network isolation.
> Please reply with the VPC ID."

```bash
read -p "VPC ID: " VPC_ID

# Verify the customer's choice exists
VPC_EXISTS=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region $REGION \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ "$VPC_EXISTS" != "$VPC_ID" ]; then
  echo "ERROR: VPC $VPC_ID not found in $REGION."
  exit 1
fi

# ──────────────────────────────────────────────────────────────────────────
# 2. List subnets in the chosen VPC. Show ID, AZ, CIDR, public flag, Name.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Subnets in $VPC_ID:"
aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,Cidr:CidrBlock,Public:MapPublicIpOnLaunch,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table

SUBNET_COUNT=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(Subnets)' --output text)
if [ "$SUBNET_COUNT" = "0" ]; then
  echo "ERROR: VPC $VPC_ID has no subnets. The skill cannot create one."
  echo "       Customer's network team must add a subnet. Bail out."
  exit 1
fi
```

**STOP HERE.** The agent MUST present the list above and ask the customer which subnet to use. The agent MUST NOT pre-pick "the first one" or "any of the AZ-a subnets" -- every subnet is the customer's call. The agent MUST NOT proceed to listing security groups until the customer has typed a subnet ID. Suggested phrasing:

> "Pick a subnet for the runner. The subnet must have outbound internet access (NAT gateway, internet gateway, or transit gateway) so the runner can pull the atx-ct image from ECR Public, reach the atx ct backend, and talk to S3 / Secrets Manager.
> Public subnets (`Public: True`) auto-assign public IPs -- easiest for image pull, but exposes the instance to the internet.
> Private subnets (`Public: False`) need NAT or TGW egress -- typical for production workloads.
> Please reply with the subnet ID."

```bash
read -p "Subnet ID: " SUBNET_ID

# Validation #1: subnet is actually in the chosen VPC.
SUBNET_VPC=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_ID" --region $REGION \
  --query 'Subnets[0].VpcId' --output text 2>/dev/null)
if [ "$SUBNET_VPC" != "$VPC_ID" ]; then
  echo "ERROR: subnet $SUBNET_ID is not in VPC $VPC_ID (or doesn't exist in $REGION)."
  exit 1
fi
SUBNET_AZ=$(aws ec2 describe-subnets --subnet-ids "$SUBNET_ID" --region $REGION \
  --query 'Subnets[0].AvailabilityZone' --output text)
echo "  ✓ Subnet $SUBNET_ID is in $SUBNET_VPC, AZ $SUBNET_AZ."

# Validation #2: subnet has a default route (egress exists).
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $REGION \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)
if [ "$ROUTE_TABLE_ID" = "None" ] || [ -z "$ROUTE_TABLE_ID" ]; then
  # Subnet has no explicit association; it inherits the VPC's main route table.
  ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --region $REGION \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' --output text)
fi
DEFAULT_ROUTE=$(aws ec2 describe-route-tables --route-table-ids "$ROUTE_TABLE_ID" --region $REGION \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'] | [0]" --output json)
EGRESS_TARGET=$(echo "$DEFAULT_ROUTE" | jq -r '.GatewayId // .NatGatewayId // .TransitGatewayId // .VpcPeeringConnectionId // "MISSING"')
if [ "$EGRESS_TARGET" = "MISSING" ] || [ "$EGRESS_TARGET" = "null" ]; then
  echo "ERROR: subnet $SUBNET_ID has no default route (0.0.0.0/0). The runner won't"
  echo "       reach atx ct backend / ECR / S3. The customer's network team must add"
  echo "       a NAT gateway, internet gateway, or transit gateway route before deploying."
  echo "       (We do NOT auto-provision NAT -- those are real network changes.)"
  exit 1
fi
echo "  ✓ Subnet has default route via $EGRESS_TARGET."

# ──────────────────────────────────────────────────────────────────────────
# 3. List security groups in the chosen VPC. Show ID, Name, description.
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "Security groups in $VPC_ID:"
aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[*].{GroupId:GroupId,Name:GroupName,Description:Description}' \
  --output table
```

**STOP HERE.** The agent MUST present the list above and ask the customer which security group to reuse, or whether to let the stack create a new one. The agent MUST NOT default to "let the stack create one" without asking -- that's the customer's choice. The agent MUST NOT proceed to the final confirmation step until the customer has typed an SG ID or `new`. Suggested phrasing:

> "Pick a security group for the runner, or type 'new' to let the stack create a fresh one with no inbound and allow-all outbound.
> If you reuse an existing SG, it MUST allow outbound HTTPS (port 443) to atx ct backend, ECR, S3, Secrets Manager, and (if applicable) your internal git host. I'll verify outbound 443 is allowed before proceeding.
> Please reply with the SG ID or 'new'."

```bash
read -p "Security group ID (or 'new' to create one): " SG_ANSWER
if [ "$SG_ANSWER" = "new" ] || [ -z "$SG_ANSWER" ]; then
  EXISTING_SG_ID=""
  echo "  ✓ Stack will create a new no-inbound, allow-all-egress SG."
else
  EXISTING_SG_ID="$SG_ANSWER"

  # Validation #4: reused SG allows outbound HTTPS.
  EGRESS_443=$(aws ec2 describe-security-groups --group-ids "$EXISTING_SG_ID" --region $REGION \
    --query "SecurityGroups[0].IpPermissionsEgress[?FromPort==\`443\` || FromPort==null || IpProtocol=='-1'] | [0]" \
    --output json 2>/dev/null)
  if [ "$EGRESS_443" = "null" ] || [ -z "$EGRESS_443" ]; then
    echo "ERROR: security group $EXISTING_SG_ID does not appear to allow outbound HTTPS."
    echo "       Add an egress rule for TCP 443 to 0.0.0.0/0 (or to the specific atx ct,"
    echo "       ECR, S3, Secrets Manager, and internal git host CIDRs) before deploying."
    exit 1
  fi
  echo "  ✓ Security group $EXISTING_SG_ID allows outbound HTTPS."
fi

echo ""
echo "Final selections:"
echo "  VPC:    $VPC_ID"
echo "  Subnet: $SUBNET_ID (AZ $SUBNET_AZ)"
[ -n "$EXISTING_SG_ID" ] && echo "  SG:     $EXISTING_SG_ID (reused)" || echo "  SG:     stack will create a new one"
```

**FINAL CONFIRMATION GATE.** The agent MUST present the four selections above (VPC, subnet, SG, AZ) to the customer in a clear summary and ask explicit confirmation before advancing to Step 5c. Suggested phrasing:

> "Here's what I'll deploy with:
>
> - **VPC**: `$VPC_ID`
> - **Subnet**: `$SUBNET_ID` (AZ `$SUBNET_AZ`)
> - **Security Group**: `$EXISTING_SG_ID` (reused) ← OR → stack will create a new no-inbound, allow-all-egress SG
> - **WorkerCount / InstanceType / VolumeSize**: (from Step 2)
>
> Proceed with these? (yes / no -- type yes to continue to the admin handoff, or anything else to revise)"

The agent MUST wait for the customer's explicit `yes` (or equivalent affirmative) before advancing. If the customer says no or wants to change something, the agent MUST loop back to the relevant step and re-ask. **The agent MUST NOT skip this confirmation, even if every selection looks reasonable** -- this is the last chance for the customer to catch a mistake before the admin is asked to deploy infrastructure.

**The skill NEVER creates VPCs, subnets, or NAT gateways.** It only describes them, asks the customer to choose, validates the choice, and (on the SG side) lets the stack create one when the customer doesn't want to reuse one. All other network resources are customer-provisioned, customer-owned. If the account has no VPCs or no subnets in the chosen VPC, the skill bails and tells the customer to provision them first -- those are infrastructure changes that need network-team approval, not something the skill should silently do.

**Step 5c: Write the CFN template and create the stack:**

```bash
STACK_NAME="${STACK_NAME:-atx-runner}"

# Write the template inline. Customer can inspect /tmp/atx-ec2-stack.yaml before deploy.
cat > /tmp/atx-ec2-stack.yaml <<'CFN_EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: ATX CT runner - single EC2 instance with the atx-ct container running.

Parameters:
  InstanceType:
    Type: String
    Default: m5.2xlarge
    AllowedValues: [m5.large, m5.xlarge, m5.2xlarge, m5.4xlarge, m5.8xlarge, m5.12xlarge]
  ImageUri:
    Type: String
    Default: public.ecr.aws/d9h8z6l7/aws-transform:latest
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: VPC where the runner will be deployed. If the git host is private/internal (self-managed GitLab, GHES, Bitbucket DC), provide a VPC with a route to it (VPN, Direct Connect, or peering).
  SubnetId:
    Type: AWS::EC2::Subnet::Id
    Description: Subnet for the runner. Must have outbound internet access (NAT, IGW, or transit gateway) to reach the atx ct backend, ECR (image pulls), S3, and Secrets Manager.
  ExistingSecurityGroupId:
    Type: String
    Default: ''
    Description: Optional. If provided, the stack reuses this security group instead of creating a new one. The reused SG MUST allow outbound HTTPS (port 443) to the atx ct backend, ECR, S3, Secrets Manager, and (if applicable) the customer's internal git host. Leave empty to let the stack create a new no-inbound SG.
  VolumeSizeGB:
    Type: Number
    Default: 100
    MinValue: 50
  WorkerCount:
    Type: Number
    Default: 1
    MinValue: 1
    MaxValue: 5
    Description: Number of parallel atx-ct containers (1-5). Each container is memory-capped at (instance RAM minus 4 GB) divided by WorkerCount, so WorkerCount must be sized to the InstanceType. The template default of 1 is matched to the default InstanceType (m5.2xlarge, 32 GB). IMPORTANT - if you raise WorkerCount, also raise InstanceType so each worker still gets enough RAM (use m5.4xlarge for 2-4 workers, m5.8xlarge for 5); the laptop-side provision script auto-sizes InstanceType from WorkerCount for you. WorkerCount of 1 creates a single container named atx-ct (legacy behavior); WorkerCount above 1 creates atx-ct-1, atx-ct-2, etc. For more than 5 parallel jobs, use the Batch path.

Conditions:
  CreateNewSG: !Equals [!Ref ExistingSecurityGroupId, '']

Resources:
  TransformRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub 'atx-transform-role-${AWS::StackName}'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal: { Service: ec2.amazonaws.com }
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Policies:
        - PolicyName: atx-transform-access
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: 'transform-custom:*'
                Resource: '*'
              - Effect: Allow
                Action: [s3:GetObject, s3:PutObject, s3:ListBucket, s3:DeleteObject]
                Resource:
                  - !Sub 'arn:aws:s3:::atx-source-code-${AWS::AccountId}'
                  - !Sub 'arn:aws:s3:::atx-source-code-${AWS::AccountId}/*'
                  - !Sub 'arn:aws:s3:::atx-ct-output-${AWS::AccountId}'
                  - !Sub 'arn:aws:s3:::atx-ct-output-${AWS::AccountId}/*'
              - Effect: Allow
                Action: [kms:GenerateDataKey, kms:Decrypt, kms:Encrypt, kms:DescribeKey]
                Resource: !Sub 'arn:aws:kms:*:${AWS::AccountId}:key/*'
                Condition:
                  StringLike: { 'kms:ViaService': 's3.*.amazonaws.com' }
              - Effect: Allow
                Action: secretsmanager:GetSecretValue
                Resource: !Sub 'arn:aws:secretsmanager:*:${AWS::AccountId}:secret:atx/*'
              - Effect: Allow
                Action:
                  - securityagent:ListAgentSpaces
                  - securityagent:CreateCodeReview
                  - securityagent:StartCodeReviewJob
                  - securityagent:ListCodeReviewJobsForCodeReview
                  - securityagent:ListFindings
                  - securityagent:BatchGetFindings
                  - securityagent:StartCodeRemediation
                Resource: 'arn:aws:securityagent:*:*:agent-space*'
                Condition:
                  StringEquals: { 'aws:ResourceAccount': !Ref AWS::AccountId }
              - Effect: Allow
                Action: [s3:GetObject, s3:ListBucket]
                Resource:
                  - 'arn:aws:s3:::kct-security-agent-*'
                  - 'arn:aws:s3:::kct-security-agent-*/*'
              - Effect: Allow
                Action: s3:PutObject
                Resource: 'arn:aws:s3:::kct-security-agent-*/security-scans/*'
              - Effect: Allow
                Action: iam:PassRole
                Resource: !Sub 'arn:aws:iam::${AWS::AccountId}:role/security-agent-*'
                Condition:
                  StringEquals:
                    'iam:PassedToService': securityagent.amazonaws.com

  TransformInstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub 'atx-transform-profile-${AWS::StackName}'
      Roles: [!Ref TransformRole]

  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Condition: CreateNewSG
    Properties:
      GroupDescription: ATX Transform EC2 - no inbound (access via SSM)
      VpcId: !Ref VpcId
      Tags:
        - Key: Name
          Value: !Sub 'atx-transform-sg-${AWS::StackName}'

  Instance:
    Type: AWS::EC2::Instance
    CreationPolicy:
      ResourceSignal: { Timeout: PT15M, Count: 1 }
    Properties:
      InstanceType: !Ref InstanceType
      ImageId: '{{resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64}}'
      IamInstanceProfile: !Ref TransformInstanceProfile
      SubnetId: !Ref SubnetId
      SecurityGroupIds:
        - !If [CreateNewSG, !Ref SecurityGroup, !Ref ExistingSecurityGroupId]
      MetadataOptions:
        # Enforce IMDSv2 (token-based, defense against SSRF) and allow 2 hops so
        # containers using bridge networking can reach IMDS for IAM credentials.
        # AWS recommendation for Docker-on-EC2: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
        HttpEndpoint: enabled
        HttpTokens: required
        HttpPutResponseHopLimit: 2
      BlockDeviceMappings:
        - DeviceName: /dev/xvda
          Ebs: { VolumeSize: !Ref VolumeSizeGB, VolumeType: gp3, DeleteOnTermination: true }
      Tags:
        - { Key: Name, Value: !Sub 'atx-ct-runner-${AWS::StackName}' }
        - { Key: ManagedBy, Value: ATX-CFN }
        - { Key: StackName, Value: !Ref AWS::StackName }
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash
          set -e
          trap 'cfn-signal -e $? --stack ${AWS::StackName} --resource Instance --region ${AWS::Region}' ERR EXIT

          # Precheck FIRST (before dnf/docker pull, which take minutes): reject a
          # WorkerCount that does not fit this instance's RAM. Each worker needs
          # >=2048 MB (the per-worker floor applied at launch) plus ~4 GB reserved
          # for the OS/Docker/SSM agent; if the host cannot satisfy that, the 2048
          # MB floor would over-commit RAM and the OOM-killer could take the SSM
          # agent -- exactly the failure this template prevents. Failing here (set
          # -e + ERR/EXIT cfn-signal trap rolls the stack back) surfaces a bad
          # WorkerCount/InstanceType pairing in seconds instead of after the image
          # pull. RAM is static, so nothing below changes this verdict.
          MEM_TOTAL_MB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 ))
          REQUIRED_MB=$(( ${WorkerCount} * 2048 + 4096 ))
          if [ "$MEM_TOTAL_MB" -lt "$REQUIRED_MB" ]; then
            echo "FATAL: host has ${!MEM_TOTAL_MB} MB but WorkerCount=${WorkerCount} requires ${!REQUIRED_MB} MB (2048 MB/worker + 4096 MB reserved). Raise InstanceType or lower WorkerCount." >&2
            exit 1
          fi

          dnf install -y docker
          systemctl start docker
          systemctl enable docker
          usermod -aG docker ec2-user
          docker pull ${ImageUri}

          # Worker naming convention:
          #   WorkerCount=1  -> single container named "atx-ct" (existing behavior)
          #   WorkerCount>1  -> "atx-ct-1", "atx-ct-2", ... "atx-ct-N"
          # Bridge networking (no --net=host) so multiple containers can coexist.
          if [ "${WorkerCount}" -eq 1 ]; then
            CONTAINERS="atx-ct"
          else
            CONTAINERS=$(seq -f "atx-ct-%g" 1 ${WorkerCount})
          fi

          # Cap each container's memory so a runaway analysis (heavy parallel
          # cloning of many/large repos) can only OOM its own container, never
          # the host. An unbounded container can exhaust host RAM, get the SSM
          # agent OOM-killed (severing all access), and -- with the old
          # --restart unless-stopped -- loop forever. Reserve ~4 GB for the OS,
          # Docker daemon, and SSM agent; split the remainder across workers.
          # --restart on-failure:3 bounds that OOM loop (an OOM is exit 137 =
          # failure, retried at most 3x then left down). It intentionally does
          # NOT restart a clean exit 0: `atx ct server` is a forever-daemon, so
          # a clean exit is unexpected and SHOULD surface as a provision failure
          # via the health check below rather than be silently resurrected. A
          # boot-time OOM is not expected (an idle server needs far less than
          # the >=2048 MB floor), so the cap will realistically only bite under
          # a real runaway analysis, not at provision.
          # MEM_TOTAL_MB was computed and range-checked in the precheck at the top
          # of UserData; reuse it to split the budget across workers.
          MEM_PER_WORKER_MB=$(( (MEM_TOTAL_MB - 4096) / ${WorkerCount} ))
          if [ "$MEM_PER_WORKER_MB" -lt 2048 ]; then MEM_PER_WORKER_MB=2048; fi

          for name in $CONTAINERS; do
            docker run -d --name "$name" --restart on-failure:3 \
              --memory="${!MEM_PER_WORKER_MB}m" --memory-swap="${!MEM_PER_WORKER_MB}m" \
              --entrypoint /bin/bash \
              -e CT_OUTPUT_BUCKET=atx-ct-output-${AWS::AccountId} \
              -e AWS_REGION=${AWS::Region} \
              ${ImageUri} \
              -c 'mkdir -p /home/atxuser/.atxct/sources /home/atxuser/.atxct/shared && \
                  source ~/.bashrc && atx ct server'
          done

          # Wait for all containers to report healthy in PARALLEL (background each
          # health-check, then wait on all PIDs). Sequential checking would not fit
          # within the CFN CreationPolicy timeout for higher WorkerCount values.
          # Note: ${!name} is the CFN !Sub escape -- !Sub leaves it as a literal
          # dollar-brace for bash to resolve. An unescaped bash variable in this
          # !Sub block would error with "Unresolved resource dependencies"
          # because !Sub treats dollar-brace refs as CFN resource references.
          # Each worker fast-fails only when its container is TERMINALLY down, so a
          # dead worker surfaces within seconds instead of waiting out the full 300s
          # poll -- WITHOUT tripping on the transient "exited" snapshot a container
          # shows BETWEEN --restart on-failure:3 retries. Terminal = Status=dead, OR
          # Status=exited with either a clean ExitCode 0 (on-failure never restarts a
          # clean exit) or RestartCount>=3 (retries exhausted). A non-zero exit with
          # RestartCount<3 is mid-retry -- keep polling, it may still come up.
          PIDS=()
          for name in $CONTAINERS; do
            (
              for i in $(seq 1 60); do
                STATUS=$(docker inspect "$name" --format '{{.State.Status}}' 2>/dev/null || echo missing)
                EC=$(docker inspect "$name" --format '{{.State.ExitCode}}' 2>/dev/null || echo -1)
                RC=$(docker inspect "$name" --format '{{.RestartCount}}' 2>/dev/null || echo 0)
                if [ "$STATUS" = dead ] || { [ "$STATUS" = exited ] && { [ "$EC" = 0 ] || [ "$RC" -ge 3 ]; }; }; then
                  OOM=$(docker inspect "$name" --format '{{.State.OOMKilled}}' 2>/dev/null)
                  echo "Worker ${!name} terminal: Status=$STATUS OOMKilled=$OOM ExitCode=$EC RestartCount=$RC" >&2
                  exit 1
                fi
                if docker exec "$name" bash -c 'atx ct status --health' > /dev/null 2>&1; then exit 0; fi
                sleep 5
              done
              echo "Worker ${!name} never became healthy within 300s" >&2
              exit 1
            ) &
            PIDS+=($!)
          done
          for pid in "${!PIDS[@]}"; do
            wait "$pid" || { echo "Health check failed for one or more workers" >&2; exit 1; }
          done
          for name in $CONTAINERS; do
            docker ps --filter "name=^${!name}$" --filter status=running --format '{{.Names}}' | grep -q "^${!name}$"
            docker exec "$name" bash -c 'atx ct status --health' > /dev/null 2>&1
          done

          trap - ERR EXIT
          cfn-signal -e 0 --stack ${AWS::StackName} --resource Instance --region ${AWS::Region}

Outputs:
  StackName: { Value: !Ref AWS::StackName }
  InstanceId: { Value: !Ref Instance }
  RoleArn: { Value: !GetAtt TransformRole.Arn }
  InstanceProfileName: { Value: !Ref TransformInstanceProfile }
  SecurityGroupId:
    Value: !If [CreateNewSG, !GetAtt SecurityGroup.GroupId, !Ref ExistingSecurityGroupId]
  AccountId: { Value: !Ref AWS::AccountId }
  Region: { Value: !Ref AWS::Region }
CFN_EOF

# Worker count (default 1; max 5). Default of 1 matches the CFN template default and
# keeps each worker on a right-sized box (InstanceType is auto-sized from WORKER_COUNT
# below, and each container is memory-capped at (instance RAM - 4 GB) / WORKER_COUNT at
# launch). Raise it for more parallelism (e.g. WORKER_COUNT=3 or 5); the auto-sizing
# bumps InstanceType so each worker still gets enough RAM. Changing it after provisioning
# is destructive (see "Changing WorkerCount" section).
WORKER_COUNT="${WORKER_COUNT:-1}"
if [ "$WORKER_COUNT" -lt 1 ] || [ "$WORKER_COUNT" -gt 5 ]; then
  echo "ERROR: WORKER_COUNT must be 1-5. Got: $WORKER_COUNT. For more parallelism, use the Batch path." >&2
  exit 1
fi

# Auto-recommend InstanceType based on WorkerCount if customer did not override.
# Sizing assumes typical analyses (single-repo fan-out). For monorepos or 10x source-wide
# analyses simultaneously, customer should override INSTANCE_TYPE=m5.12xlarge.
if [ -z "$INSTANCE_TYPE" ]; then
  if   [ "$WORKER_COUNT" -le 1 ]; then INSTANCE_TYPE="m5.2xlarge"
  elif [ "$WORKER_COUNT" -le 4 ]; then INSTANCE_TYPE="m5.4xlarge"
  else                                  INSTANCE_TYPE="m5.8xlarge"
  fi
fi

# Auto-recommend disk size: 50 GB per worker (covers typical and heavy use; override
# to 100 GB/worker for monorepos via VOLUME_SIZE env var).
VOLUME_SIZE="${VOLUME_SIZE:-$((50 * WORKER_COUNT))}"

# ──────────────────────────────────────────────────────────────────────────
# Pre-deploy confirmation: ASK THE CUSTOMER before creating the stack.
# Show them the resolved config so they can override WorkerCount, InstanceType,
# or VolumeSize before commit. Customer is responsible for checking AWS pricing.
# ──────────────────────────────────────────────────────────────────────────
cat <<EOF

About to create EC2 stack '$STACK_NAME' with:
  WorkerCount:    $WORKER_COUNT  (parallel atx-ct containers)
  InstanceType:   $INSTANCE_TYPE
  VolumeSizeGB:   $VOLUME_SIZE GB
  Region:         $REGION
  VPC / Subnet:   $VPC_ID / $SUBNET_ID

The EC2 instance runs continuously until the stack is deleted. Check current
AWS EC2 + EBS pricing for $INSTANCE_TYPE in $REGION before confirming:
  https://aws.amazon.com/ec2/pricing/on-demand/

Override before deploying:
  WORKER_COUNT=N    (1-5; smaller = fewer parallel slots, lower cost)
  INSTANCE_TYPE=    (m5.2xlarge | m5.4xlarge | m5.8xlarge | m5.12xlarge)
  VOLUME_SIZE=N     (GB; bump up for monorepos)

Important: Changing WorkerCount LATER requires a stack redeploy that REPLACES
the EC2 instance and EBS volume (warm caches lost). See
"Changing WorkerCount Requires Redeploy" section. Pick the right value now.

EOF
read -p "Proceed with these settings? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Cancelled. Adjust env vars and re-run."
  exit 0
fi
```

### Step 5d: Hand off the create-stack command to an admin

**The agent MUST NOT run `aws cloudformation create-stack` (or `delete-stack`, or any `iam:Create*` / `iam:Put*` / `iam:Attach*` / `iam:Delete*` action) itself, under ANY circumstances.** This is unconditional:

- ❌ NOT if the agent finds an admin profile in `~/.aws/config`. Profile availability does NOT authorize use.
- ❌ NOT if the user volunteers admin credentials mid-conversation.
- ❌ NOT by switching `--profile` flags, assuming a role, or exporting different `AWS_PROFILE` / `AWS_ACCESS_KEY_ID` env vars.
- ❌ NOT by suggesting "let me just run it for you with the admin profile" -- refuse and redirect to the handoff.

The split is **strict mutable / immutable**: the executor policy does not grant ANY resource-lifecycle mutation outside of the `atx-control-tower` schedule group it owns (no IAM mutations, no CFN stack lifecycle, no EC2 RunInstances/CreateSecurityGroup/Terminate, no S3 CreateBucket, no `scheduler:CreateScheduleGroup`/`DeleteScheduleGroup`, no `secretsmanager:CreateSecret`/`DeleteSecret`/`PutSecretValue`). Operate-only carve-outs the executor DOES grant -- `ec2:Start/StopInstances` (power state on tagged instances) and `scheduler:CreateSchedule`/`DeleteSchedule`/`UpdateSchedule` (CRUD on schedules inside the pre-existing `atx-control-tower` group) -- are not escalation paths. Token staging (Step 4) is a customer-runs-locally step that requires admin credentials.

The split exists for **privilege-escalation surface reduction** AND **audit and traceability** -- every resource-creating or destroying action flows through a human who explicitly chose to use admin credentials, so the customer's CloudTrail shows a human identity behind the mutation, not the agent's identity.

What the agent CAN do here:

- ✅ Write `/tmp/atx-ec2-stack.yaml` (filesystem, not AWS).
- ✅ Run `aws cloudformation validate-template` (read-only).
- ✅ Run `aws s3api head-bucket` to check whether buckets already exist (read-only).
- ✅ Print the handoff message and commands below.
- ✅ End its turn and wait for the user to come back.

What the agent CANNOT do here:

- ❌ Run `aws cloudformation create-stack` or `delete-stack`, even via the user's admin profile.
- ❌ Run `aws iam create-role`, `put-role-policy`, `attach-role-policy`, `create-instance-profile`, etc.
- ❌ Run `aws s3api create-bucket` or `put-bucket-lifecycle-configuration`.
- ❌ Run `aws ec2 run-instances`, `create-security-group`, `create-key-pair`, `terminate-instances`, `delete-security-group`, `delete-key-pair`.
- ❌ Run `aws scheduler create-schedule-group` or `delete-schedule-group`.

If the agent has just done one of the forbidden actions, STOP, tell the user, and ask them how they want to proceed.

The agent MUST print the following to the customer:

> **Admin handoff -- one-time setup**
>
> I've written the CloudFormation template to `/tmp/atx-ec2-stack.yaml`. **This stack creates IAM roles, so deploying requires admin / role-creation permissions (`iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole`, instance profiles). Run it with an admin identity. Read-only or runtime credentials are enough for everything afterward.**
>
> The agent MUST include the following sentence verbatim in every Step 5d handoff, immediately after the admin-identity sentence above and before the command block. Do NOT abbreviate, drop, or paraphrase it -- customers onboarding a new executor identity rely on this pointer:
>
> For reference, the executor policy this skill expects is in https://github.com/awslabs/agent-plugins/blob/main/plugins/aws-transform/skills/aws-transform/references/AWSTransformInfrastructureExecutorAccessEC2.json
>
> Those permissions are admin-scope; the executor permissions I'm running under intentionally do not grant them, so day-to-day analysis runs cannot escalate privileges.
>
> Ask someone in your account with admin / role-creation permissions (or yourself if you have a separate admin profile) to run these commands from the same shell, in the same region. **Replace `<your-admin-profile>` with the AWS profile name that has admin / role-creation permissions in your environment.**

**Profile-name guidance for the agent.** When emitting this admin handoff (or any of the other admin handoffs in this skill), the agent MUST use the placeholder `<your-admin-profile>` rather than guessing a profile name from the customer's local AWS config, environment variables, or shell history. Customers commonly have multiple AWS profiles configured locally and the agent has no reliable way to identify which one carries admin permissions. Substituting a wrong name leads to confusing AccessDenied errors during deploy. Examples:

- ❌ `AWS_PROFILE=atx-zerog-admin aws cloudformation create-stack ...` (the agent guessed from `~/.aws/config`)
- ❌ `AWS_PROFILE=admin aws cloudformation create-stack ...` (the agent assumed a name)
- ✅ `AWS_PROFILE=<your-admin-profile> aws cloudformation create-stack ...` (placeholder for the customer to fill in)

This rule applies to **every admin handoff in this skill**: create-stack, delete-stack, instance-tag handoff, instance-role-policy handoff, anywhere else admin is invoked.

The full handoff command set (admin runs in their shell, in `${REGION}`):

> ```bash
> # 1. Create the persistent S3 buckets (only if Step 5a reported them missing).
> #    These live OUTSIDE the CFN stack so they survive delete-and-recreate.
> #    us-east-1 quirk: --create-bucket-configuration LocationConstraint=us-east-1
> #    is rejected by the API; omit the flag in that one region.
> LOC_CONSTRAINT=""
> [ "$REGION" != "us-east-1" ] && LOC_CONSTRAINT="--create-bucket-configuration LocationConstraint=$REGION"
>
> aws s3api create-bucket --bucket atx-source-code-${ACCOUNT_ID} --region $REGION $LOC_CONSTRAINT
> aws s3api put-bucket-lifecycle-configuration --bucket atx-source-code-${ACCOUNT_ID} \
>   --lifecycle-configuration '{"Rules":[{"ID":"expire-7d","Status":"Enabled","Expiration":{"Days":7},"Filter":{"Prefix":""}}]}'
>
> aws s3api create-bucket --bucket atx-ct-output-${ACCOUNT_ID} --region $REGION $LOC_CONSTRAINT
> aws s3api put-bucket-lifecycle-configuration --bucket atx-ct-output-${ACCOUNT_ID} \
>   --lifecycle-configuration '{"Rules":[{"ID":"expire-30d","Status":"Enabled","Expiration":{"Days":30},"Filter":{"Prefix":""}}]}'
>
> # 2. Create the CFN stack (instance, IAM role/profile, security group).
> aws cloudformation create-stack \
>   --stack-name "$STACK_NAME" \
>   --template-body file:///tmp/atx-ec2-stack.yaml \
>   --capabilities CAPABILITY_NAMED_IAM \
>   --parameters \
>       ParameterKey=VpcId,ParameterValue=$VPC_ID \
>       ParameterKey=SubnetId,ParameterValue=$SUBNET_ID \
>       ParameterKey=InstanceType,ParameterValue=$INSTANCE_TYPE \
>       ParameterKey=WorkerCount,ParameterValue=$WORKER_COUNT \
>       ParameterKey=VolumeSizeGB,ParameterValue=$VOLUME_SIZE \
>       ParameterKey=ExistingSecurityGroupId,ParameterValue="$EXISTING_SG_ID" \
>   --region $REGION \
>   --tags Key=atx-remote-infra,Value=true
>
> aws cloudformation wait stack-create-complete \
>   --stack-name "$STACK_NAME" --region $REGION
> ```
>
> When the deploy finishes, come back to this conversation and tell me -- I'll re-detect the stack via `describe-stacks` (which my executor creds CAN do) and continue from Step 6.

The agent then STOPS this turn. The admin runs the commands in their own terminal, outside the chat. On the next user turn, re-run **Step 0 (Detect)** -- the stack should now be `CREATE_COMPLETE` and the flow resumes at Step 6.

**Why CloudFormation:**

| Concern             | CFN advantage                                                                                |
| ------------------- | -------------------------------------------------------------------------------------------- |
| Audit trail         | Single stack event log shows every resource created                                          |
| Atomic deploy       | Failure rolls back entire stack -- no orphaned IAM roles or instances                        |
| Drift detection     | Customer can run `aws cloudformation detect-stack-drift` to see if anything changed manually |
| Teardown            | Single `aws cloudformation delete-stack` cleans up everything in the stack                   |
| Multi-stack support | Customer can run `STACK_NAME=dev`, `STACK_NAME=prod` for isolated runners                    |
| Visibility          | Customer's CloudFormation console shows the resources, parameters, and outputs               |

### Step 6: Verify the Container is Running

The CFN stack's `CreationPolicy` ensures `CREATE_COMPLETE` fires only after the UserData script signals success -- meaning Docker is installed, the image is pulled, and the atx-ct container is up. So verification is a quick confidence check.

```bash
# Define the SSM helpers (used by all subsequent steps for short status calls
# and fire-and-forget submissions of long-running work):
#
#   ssm_submit  -- fire-and-forget. Returns SSM CommandId immediately. NEVER blocks.
#                 Use for build_command_*() submissions.
#   ssm_run     -- submit + wait + get output. Blocks until command completes
#                 (~100s SSM-side timeout). Use for short status commands.
#
# DO NOT use ssm_run for build_command_*() -- the wrapper runs for hours.

ssm_submit() {
  aws ssm send-command --region $REGION \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"$1\"]" \
    --query 'Command.CommandId' --output text
}

ssm_run() {
  local cmd="$1"
  local CMD_ID=$(aws ssm send-command --region $REGION \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"$cmd\"]" \
    --query 'Command.CommandId' --output text)
  aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region $REGION 2>/dev/null || true
  aws ssm get-command-invocation --region $REGION \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text
}

# Resolve CONTAINER_NAME based on stack's WorkerCount + the desired worker.
#   WorkerCount=1 (default): single container "atx-ct" (existing behavior).
#   WorkerCount>1:           containers "atx-ct-1", "atx-ct-2", ..., "atx-ct-N".
# WORKER_NUM is the 1-indexed worker to target (1..WorkerCount). Defaults to 1.
WORKER_COUNT=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
  --query 'Stacks[0].Parameters[?ParameterKey==`WorkerCount`].ParameterValue' --output text 2>/dev/null)
WORKER_COUNT=$(echo "$WORKER_COUNT" | xargs)   # strip whitespace defensively
[ -z "$WORKER_COUNT" ] || [ "$WORKER_COUNT" = "None" ] && WORKER_COUNT=1
WORKER_NUM="${WORKER_NUM:-1}"
if [ "$WORKER_COUNT" -eq 1 ]; then
  CONTAINER_NAME="atx-ct"
else
  if [ "$WORKER_NUM" -lt 1 ] || [ "$WORKER_NUM" -gt "$WORKER_COUNT" ]; then
    echo "ERROR: WORKER_NUM ($WORKER_NUM) must be 1-${WORKER_COUNT}." >&2
    exit 1
  fi
  CONTAINER_NAME="atx-ct-${WORKER_NUM}"
fi

# Confirm container is running and atx ct server is healthy
ssm_run "sudo docker ps --filter \"name=^${CONTAINER_NAME}$\" --filter status=running --format '{{.Names}}: {{.Status}}'"
ssm_run "sudo docker exec ${CONTAINER_NAME} atx ct status --health"
```

If either check fails, inspect the container logs:

```bash
ssm_run "sudo docker logs ${CONTAINER_NAME} 2>&1 | tail -50"
```

For a fully failed bootstrap, the stack would be in `ROLLBACK_COMPLETE` (UserData failed → cfn-signal sent error → stack rolled back). Check stack events:

```bash
aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region $REGION \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[ResourceType,ResourceStatusReason]' --output table
```

**Local source preparation (local provider only):** if `PROVIDER=local`, sync repo bundles into the container after the container is up:

```bash
if [ "$PROVIDER" = "local" ]; then
  # Customer must have already uploaded zips to s3://atx-source-code-${ACCOUNT_ID}/repos/
  ssm_run "sudo docker exec ${CONTAINER_NAME} bash -c 'mkdir -p /home/atxuser/repos /tmp/zips && \
    aws s3 sync s3://atx-source-code-${ACCOUNT_ID}/repos/ /tmp/zips/ && \
    for zip in /tmp/zips/*.zip; do unzip -q -o \"\$zip\" -d /home/atxuser/repos/; done'"
fi
```

#### Security analysis prerequisite

If `ANALYSIS_TYPE=security` (or `agentic-readiness` / `modernization-readiness` which depend on it), the security agent must be set up first. See [continuous-modernization-setup](continuous-modernization-setup.md) for `atx ct setup security-agent`.

The S3 + `iam:PassRole` grants the instance role needs for security analysis are **always-on** in the CFN template (the `securityagent:*` actions, `s3:*` on `kct-security-agent-*`, and `iam:PassRole` on `security-agent-*` are part of the base role policy). No stack redeploy is required if the customer decides to run security analysis after the stack is up -- the role already has what's needed.

The agent space is provisioned during `atx ct setup security-agent`, which writes the populated `agentSpaceId` into `~/.atxct/shared/security_agent_config.json`. The EC2 runtime is read-only -- it finds the existing agent space via `list-agent-spaces` and never creates one. Sync the local config file into the EC2 container so the runtime can find the existing agent space:

```bash
# Sync security agent config from laptop into all atx-ct containers.
# The loop applies to single-worker (just "atx-ct") and multi-worker (atx-ct-1..N) stacks.
aws s3 cp ~/.atxct/shared/security_agent_config.json \
  s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json
ssm_run "aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json /tmp/sa.json && \
  for c in \$(sudo docker ps --filter name=atx-ct --format '{{.Names}}'); do \
    sudo docker cp /tmp/sa.json \$c:/home/atxuser/.atxct/shared/security_agent_config.json && \
    sudo docker exec \$c chown 1000:1000 /home/atxuser/.atxct/shared/security_agent_config.json; \
  done"
aws s3 rm s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json
```

### Step 7: Confirm and Submit

**Validate credentials (non-local providers):** Before confirming, verify that the required secret exists in Secrets Manager. Skip for local provider sources.

| Provider      | Required Secret       |
| ------------- | --------------------- |
| **github**    | `atx/github-token`    |
| **gitlab**    | `atx/gitlab-token`    |
| **bitbucket** | `atx/bitbucket-token` |
| **local**     | (none — skip)         |

```bash
aws secretsmanager describe-secret --secret-id <secret-name> --region $REGION 2>&1
```

- If `ResourceNotFoundException` → inform the user that the secret is missing. Give them the command to run in their own terminal:

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "<secret-name>" \
  --secret-string "$TOKEN" --region $REGION 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "<secret-name>" \
       --secret-string "$TOKEN" --region $REGION; }; unset TOKEN
```

- If the secret exists → ask the customer: "Your `<secret-name>` token was last updated on `<LastChangedDate>`. Would you like to rotate it, or is the current token still valid?" If they want to rotate:

```bash
read -s TOKEN && aws secretsmanager put-secret-value --secret-id "<secret-name>" \
  --secret-string "$TOKEN" --region $REGION; unset TOKEN
```

Tell the customer what will happen and wait for explicit confirmation.

**For GitHub:**

> "I'll submit `<analysis-type>` on EC2 instance `${INSTANCE_ID}` against your GitHub source `<source-name>`. The container is already configured with your GitHub PAT. The submission will:
>
> - Run `atx ct analysis run --type <type> --source <source-name>` in the background
> - Poll status until complete
> - Upload artifacts to `s3://atx-ct-output-${ACCOUNT_ID}/<analysis-id>/<repo>/code.zip`
>
> Continue?"

**For GitLab:** same as GitHub with `atx/gitlab-token`.

**For Bitbucket Cloud:**

> "I'll submit `<analysis-type>` on EC2 instance `${INSTANCE_ID}` against your Bitbucket source `<source-name>`. The container will:
>
> - Place your Bitbucket API token (from Secrets Manager `atx/bitbucket-token`) and inject email/username into config.json
> - Run `atx ct analysis run --type <type> --source <source-name>` in the background
> - Poll status until complete
> - Upload artifacts to S3
>
> Continue?"

**For Bitbucket Data Center:**

> "I'll submit `<analysis-type>` on EC2 instance `${INSTANCE_ID}` against your Bitbucket Data Center source `<source-name>`. The container will:
>
> - Place your HTTP Access Token (from Secrets Manager `atx/bitbucket-token`) and inject base_url into config.json
> - Run `atx ct analysis run --type <type> --source <source-name>` in the background
> - Poll status until complete
> - Upload artifacts to S3
>
> Continue?"

**For Local:** same as GitHub with bundle synced to `/home/atxuser/repos`.

Do NOT submit until the customer confirms.

### Step 8: Submit Work

Build the nohup'd command via `build_command_*()` (returns one self-contained script that runs analysis → polls status → uploads artifacts) and submit via SSM. The SSM call returns immediately because the script is backgrounded. The agent stays free during the long-running work.

```bash
ANALYSIS_TYPE="<analysis-type>"          # tech-debt-quick | tech-debt-comprehensive | security | agentic-readiness | modernization-readiness | custom
AGENT="<AGENT>"  # AI assistant name (kiro, claude, amazonq, etc.)
JOB_ID="atxct-$(date +%s)"               # unique per submission; per-job state files keyed by this
REPO_FILTER=""                           # empty = whole source; or "--repo <source>::<repo>" (ONE repo only, never multiple)
EXTRA_FLAGS=""                           # for --type custom: "--transformation-name <td-name> -g 'KEY=VAL'"
BITBUCKET_WORKSPACE="<workspace>"        # bitbucket only -- workspace (Cloud) or project key (DC)
BITBUCKET_EMAIL="<email>"                # bitbucket cloud only -- email for API auth
BITBUCKET_USERNAME="<username>"          # bitbucket cloud only -- username for git clone/push
BITBUCKET_BASE_URL=""                    # bitbucket DC only -- e.g. https://bitbucket.corp.example.com (empty for Cloud)
```

The script written to the instance follows this shape:

```bash
# (1) Submit analysis (no --wait; returns AID immediately)
sudo docker exec ${CONTAINER_NAME} atx ct analysis run --type $ANALYSIS_TYPE $EXTRA_FLAGS --source $SOURCE $REPO_FILTER > /tmp/run.log 2>&1
AID=$(grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1)

# (2) Poll status until terminal
while true; do
  STATUS=$(sudo docker exec ${CONTAINER_NAME} atx ct analysis get --id $AID --json | jq -r .status)
  case "$STATUS" in
    complete|completed) break ;;
    failed) exit 1 ;;
    *) sleep 60 ;;
  esac
done

# (3) Upload artifacts (skipped for tech-debt-quick -- read-only scan)
sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh $AID atx-ct-output-$ACCOUNT_ID
```

#### `build_command_*()` builders

Each builder writes the wrapper script to the instance via heredoc and launches it via `nohup`. Local-side bash substitutes `${LOGICAL_SOURCE_NAME}`, `${ANALYSIS_TYPE}`, etc.; runtime values like `$AID` and `$STATUS` are escaped (`\$`) so they're evaluated on the instance.

```bash
# Analysis on github / gitlab / local -- same wrapper shape, same upload step.
# Token (github/gitlab) is fetched from Secrets Manager at job time and placed in
# the container's source dir. atx ct's async provider resolution queries the
# backend for source metadata, so no config.json is needed in the container.
#
# IMPORTANT: build_command_analysis() returns the script BODY only (clean bash, no
# heredoc tricks). The skill base64-encodes the body and submits a short SSM command
# that decodes-and-runs it. This avoids the multi-level quote-escaping nightmare that
# happens when you try to pass a multi-line bash script through `aws ssm send-command
# --parameters "commands=[\"...\"]"` (the JSON layer + the bash layer collide).
build_command_analysis() {
  local UPLOAD_LINE="sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh \$AID atx-ct-output-${ACCOUNT_ID}"
  [ "${ANALYSIS_TYPE}" = "tech-debt-quick" ] && UPLOAD_LINE='echo "[skip upload -- tech-debt-quick is read-only]"'

  # Token-injection prelude (runs INSIDE the container at job start)
  local TOKEN_PRELUDE=""
  if [ "$PROVIDER" = "github" ] || [ "$PROVIDER" = "gitlab" ]; then
    local SECRET_ID="atx/${PROVIDER}-token"
    local TOKEN_FILE="${PROVIDER}_token"
    TOKEN_PRELUDE="sudo docker exec ${CONTAINER_NAME} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE} && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE}'"
  elif [ "$PROVIDER" = "bitbucket" ]; then
    # Bitbucket requires token + config.json with email/username (Cloud) or base_url (DC).
    # BITBUCKET_WORKSPACE, BITBUCKET_EMAIL, BITBUCKET_USERNAME, BITBUCKET_BASE_URL must be set by caller.
    local config_json
    if [ -n "${BITBUCKET_BASE_URL}" ]; then
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
    else
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
    fi
    local CONFIG_B64=$(echo "${config_json}" | base64 -w 0)
    TOKEN_PRELUDE="sudo docker exec ${CONTAINER_NAME} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token'"
  fi

  # Return the script body. Local bash substitutes ${ANALYSIS_TYPE}, ${LOGICAL_SOURCE_NAME},
  # ${TOKEN_PRELUDE}, etc.; runtime references like \$AID and \$LOG stay as-is.
  cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-${JOB_ID}.log
echo "=== \$(date) [START] ${ANALYSIS_TYPE} on ${LOGICAL_SOURCE_NAME} ===" >> \$LOG

${TOKEN_PRELUDE}

sudo docker exec ${CONTAINER_NAME} atx ct analysis run --type ${ANALYSIS_TYPE} ${EXTRA_FLAGS} --source ${LOGICAL_SOURCE_NAME} ${REPO_FILTER} --telemetry "agent=${AGENT},executionMode=ec2" >> \$LOG 2>&1
AID=\$(grep -oE '01[A-Z0-9]+' \$LOG | head -1)
[ -z "\$AID" ] && { echo "ERROR: no analysis ID extracted" >> \$LOG; exit 1; }
echo \$AID > /tmp/atxct-${JOB_ID}.aid

while true; do
  STATUS=\$(sudo docker exec ${CONTAINER_NAME} atx ct analysis get --id \$AID --json 2>/dev/null | jq -r .status 2>/dev/null)
  case "\$STATUS" in
    complete|completed) echo "=== \$(date) [DONE] analysis \$AID ===" >> \$LOG; break ;;
    failed|cancelled) echo "=== \$(date) [\$STATUS] analysis \$AID ===" >> \$LOG; exit 1 ;;
    *) echo "\$(date) status=\${STATUS:-pending}" >> \$LOG; sleep 60 ;;
  esac
done

${UPLOAD_LINE} >> \$LOG 2>&1
echo "=== \$(date) [DONE] upload ===" >> \$LOG
EOF
}

# Build the script body, base64-encode it (avoids quoting hell when submitting via SSM),
# and submit a single short SSM command that decodes + runs it.
SCRIPT=$(build_command_analysis)
B64=$(echo "$SCRIPT" | base64 | tr -d '\n')

# Compose a single-line SSM command:
#   1. echo $B64 | base64 -d > /tmp/atxct-<JOB>.sh    (decode script to disk)
#   2. chmod +x ...                                    (make executable)
#   3. ( ( bash ... > log 2>&1 < /dev/null & ) & )    (double-fork orphans wrapper to init)
#   4. echo Started_...                                (so SSM sees a quick exit)
#
# IMPORTANT: the double-fork is required. Without it, SSM's AWS-RunShellScript
# tracks the wrapper via cgroup and keeps the command slot pinned until the
# wrapper exits, saturating the SSM agent's worker pool. The double-fork
# `( ( bash X & ) & )` reparents the wrapper to init (PID 1) so SSM marks
# the launch command Success immediately.
LAUNCH_CMD="echo ${B64} | base64 -d > /tmp/atxct-${JOB_ID}.sh && chmod +x /tmp/atxct-${JOB_ID}.sh && ( ( bash /tmp/atxct-${JOB_ID}.sh > /tmp/atxct-${JOB_ID}.stdout 2>&1 < /dev/null & ) & ) && echo Started_${JOB_ID}"

SUBMIT_ID=$(ssm_submit "$LAUNCH_CMD")
echo "Submitted job $JOB_ID (SSM command: $SUBMIT_ID). Ask me to check status anytime."
```

The agent prints "Submitted job $JOB_ID" and is free to interact with the user. The wrapper continues on the instance independently -- analysis, polling, and upload all happen there.

#### Remediation (instead of analysis)

Same shape. The build differs by source provider -- github / gitlab use the backend's branch-push flow (no `--local`, no S3 upload); `local` uses `--local` and uploads artifacts.

```bash
build_command_remediation() {
  local CREATE_ARGS=""
  if [ -n "$FINDING_IDS" ]; then
    CREATE_ARGS="--ids ${FINDING_IDS}"
    [ -n "${TRANSFORMATION_NAME}" ] && CREATE_ARGS="${CREATE_ARGS} --transformation-name ${TRANSFORMATION_NAME}"
  else
    CREATE_ARGS="--transformation-name ${TRANSFORMATION_NAME} ${REPO_FILTER}"
  fi
  [ -n "${CONFIGURATION}" ] && CREATE_ARGS="${CREATE_ARGS} -g \"${CONFIGURATION}\""

  local LOCAL_FLAG=""
  local UPLOAD_LINE='echo "[skip upload -- github/gitlab remediation pushes a branch]"'
  if [ "$PROVIDER" = "local" ]; then
    LOCAL_FLAG="--local"
    UPLOAD_LINE="sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh \$RID atx-ct-output-${ACCOUNT_ID}"
  fi

  # Token-injection prelude (runs INSIDE the container at job start)
  local TOKEN_PRELUDE=""
  if [ "$PROVIDER" = "github" ] || [ "$PROVIDER" = "gitlab" ]; then
    local SECRET_ID="atx/${PROVIDER}-token"
    local TOKEN_FILE="${PROVIDER}_token"
    TOKEN_PRELUDE="sudo docker exec ${CONTAINER_NAME} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id ${SECRET_ID} --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE} && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/${TOKEN_FILE}'"
  elif [ "$PROVIDER" = "bitbucket" ]; then
    # Bitbucket requires token + config.json with email/username (Cloud) or base_url (DC).
    # BITBUCKET_WORKSPACE, BITBUCKET_EMAIL, BITBUCKET_USERNAME, BITBUCKET_BASE_URL must be set by caller.
    local config_json
    if [ -n "${BITBUCKET_BASE_URL}" ]; then
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
    else
      config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
    fi
    local CONFIG_B64=$(echo "${config_json}" | base64 -w 0)
    TOKEN_PRELUDE="sudo docker exec ${CONTAINER_NAME} bash -c 'mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token && chmod 600 /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token'"
  fi

  # Returns clean script body (no heredoc tricks). The skill base64-encodes and submits
  # via a short SSM command (same pattern as build_command_analysis above).
  cat <<EOF
#!/bin/bash
LOG=/tmp/atxct-${JOB_ID}.log
echo "=== \$(date) [START] remediation on ${LOGICAL_SOURCE_NAME} ===" >> \$LOG

${TOKEN_PRELUDE}

sudo docker exec ${CONTAINER_NAME} atx ct remediation create ${CREATE_ARGS} ${LOCAL_FLAG} --source ${LOGICAL_SOURCE_NAME} --telemetry "agent=${AGENT},executionMode=ec2" >> \$LOG 2>&1
RID=\$(grep -oE '01[A-Z0-9]+' \$LOG | head -1)
[ -z "\$RID" ] && { echo "ERROR: no remediation ID" >> \$LOG; exit 1; }
echo \$RID > /tmp/atxct-${JOB_ID}.rid

while true; do
  STATUS=\$(sudo docker exec ${CONTAINER_NAME} atx ct remediation status --id \$RID --json 2>/dev/null | jq -r .status 2>/dev/null)
  case "\$STATUS" in
    complete|completed) echo "=== \$(date) [DONE] remediation \$RID ===" >> \$LOG; break ;;
    failed|cancelled) echo "=== \$(date) [\$STATUS] remediation \$RID ===" >> \$LOG; exit 1 ;;
    *) sleep 60 ;;
  esac
done

${UPLOAD_LINE} >> \$LOG 2>&1
echo "=== \$(date) [DONE] upload ===" >> \$LOG
EOF
}

# Same base64 pattern as analysis
SCRIPT=$(build_command_remediation)
B64=$(echo "$SCRIPT" | base64 | tr -d '\n')
LAUNCH_CMD="echo ${B64} | base64 -d > /tmp/atxct-${JOB_ID}.sh && chmod +x /tmp/atxct-${JOB_ID}.sh && ( ( bash /tmp/atxct-${JOB_ID}.sh > /tmp/atxct-${JOB_ID}.stdout 2>&1 < /dev/null & ) & ) && echo Started_${JOB_ID}"

SUBMIT_ID=$(ssm_submit "$LAUNCH_CMD")
echo "Submitted remediation job $JOB_ID (SSM command: $SUBMIT_ID). Ask me to check status anytime."
```

### Step 9: Status Checking

When the customer asks for status, ask `atx ct` for the authoritative state. The wrapper's log file is only useful for DEBUGGING the wrapper itself (e.g., "did the wrapper start? did it parse the AID?"); for "is my analysis done?" the answer comes from the atx ct server.

```bash
# Authoritative status. What the customer actually wants to know.
AID=$(ssm_run "cat /tmp/atxct-${JOB_ID}.aid 2>/dev/null" | tr -d '[:space:]')

if [ -z "$AID" ]; then
  # No AID means the wrapper failed before extracting an analysis ID. Most
  # likely cause: instance role lacks a permission needed by the wrapper or
  # by atx ct's first backend call. Surface the specific error from the
  # wrapper log instead of reporting "running" or "pending".
  ssm_run "grep -iE 'AccessDenied|not authorized|Error:' /tmp/atxct-${JOB_ID}.log 2>&1 | head -5"
  echo "Wrapper failed to dispatch the analysis. See the errors above."
  echo "Common causes: missing transform-custom:* (instance role) or secretsmanager:GetSecretValue."
  echo "Tell the customer the specific permission identified in the AccessDenied message and ask them to attach it."
else
  ssm_run "sudo docker exec ${CONTAINER_NAME} atx ct analysis get --id $AID --json" | \
    jq '{status, repos_total: (.repos | length), findings_count}'
fi
```

Or, if you don't have the JOB_ID handy, list all in-flight analyses on the instance:

```bash
ssm_run "sudo docker exec ${CONTAINER_NAME} atx ct analysis list --json | jq '.items[] | select(.status == \"running\" or .status == \"pending\")'"
```

For remediation jobs, swap `analysis get` → `remediation status` and `*.aid` → `*.rid`.

**Wrapper log tail is only for debugging** (when you need to see what the wrapper is doing on the instance, not what the analysis is doing on the server):

```bash
ssm_run "tail -20 /tmp/atxct-${JOB_ID}.log"
```

To list all in-flight jobs on the instance:

```bash
ssm_run "ls -la /tmp/atxct-*.aid /tmp/atxct-*.rid 2>/dev/null"
```

### Step 10: Get Findings and Artifacts

**Findings** are persisted by the analysis runner during execution and queryable from anywhere with CT access. **`atx ct findings list --json` returns a top-level array** (no `.items` wrapper):

```json
[
  {
    "id": "01ABC...",
    "severity": "high|medium|low",
    "category": "security|performance|maintainability|...",
    "repo": "<source>::<repo-name>",
    "title": "Short description",
    "description": "Full description",
    "fix": null | { ... },
    ...
  },
  ...
]
```

> **Heads up -- JSON shape inconsistency across `atx ct` commands.** Some commands return `{"items": [...]}` (e.g., `repository list`, `analysis list`); others return a bare `[...]` (e.g., `findings list`, `source list`). Always assume bare array for `findings list` -- use `.[]` not `.items[]` in jq.

Common queries:

```bash
# Total finding count
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json | jq 'length'

# Group by severity
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json | \
  jq 'group_by(.severity) | map({severity: .[0].severity, count: length})'

# Group by category
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json | \
  jq 'group_by(.category) | map({category: .[0].category, count: length})'

# Auto-remediable findings only (have a fix proposal)
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json | \
  jq '[.[] | select(.fix != null)] | length'

# Per-repo summary as TSV (severity, category, repo, title)
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json | \
  jq -r '.[] | [.severity, .category, .repo, .title] | @tsv'

# Filter to a specific analysis
atx ct findings list --analysis-id ${AID} --json | jq 'length'
```

These commands work from anywhere with `atx ct` CLI access (customer's laptop, the EC2 container via `sudo docker exec ${CONTAINER_NAME} ...`, or any other machine with the same backend access). Findings are server-state, not instance-state.

**S3 artifacts** are uploaded by `/app/upload-ct-artifacts.sh` automatically when the wrapper completes. Analysis artifacts are written for any provider; remediation artifacts are only written for `--local` remediations.

```
s3://atx-ct-output-{account-id}/<analysis-id-or-remediation-id>/<source>::<repo>/
  code.zip   -- the working directory after the analysis or remediation completes,
               including a result branch with auto-committed changes (e.g.,
               `atx-result-staging-<timestamp>` for analysis documentation, or the
               remediation's branch for `--local` runs). The customer can `git log`
               and `git diff` to review what the bot changed. `.git/` is preserved
               for this reason.
               Excludes node_modules/, .env*, *.pem, *.key, .aws/.
  logs.zip   -- cherry-picked debug logs (ATX CLI debug, error log, conversation
               transcript, plan.json, validation_summary.md).
```

To download:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# All artifacts for one analysis
aws s3 sync s3://atx-ct-output-${ACCOUNT_ID}/${AID}/ ./artifacts/

# Just one repo's reports
aws s3 cp s3://atx-ct-output-${ACCOUNT_ID}/${AID}/${SOURCE}::${REPO}/code.zip ./
```

Surface findings to the user as the primary result. Reference S3 artifacts only when the user asks for raw reports/logs.

## Cancellation

To cancel an in-flight job:

```bash
JOB_ID="<job-id>"

# Read the AID/RID and the wrapper PID
AID=$(ssm_run "cat /tmp/atxct-${JOB_ID}.aid 2>/dev/null")
WRAPPER_PID=$(ssm_run "pgrep -f 'atxct-${JOB_ID}.sh'")

# Kill the wrapper (stops the polling loop on the instance)
ssm_run "sudo kill -TERM $WRAPPER_PID 2>/dev/null"

# Cancel the in-flight CT analysis (server-side)
[ -n "$AID" ] && ssm_run "sudo docker exec ${CONTAINER_NAME} atx ct analysis cancel --id $AID"

# Clean up this job's temp files
ssm_run "rm -f /tmp/atxct-${JOB_ID}.*"
```

Findings already persisted (from earlier in the analysis) survive the cancel. The upload step does NOT run if the wrapper is killed -- recover via:

```bash
ssm_run "sudo docker exec ${CONTAINER_NAME} /app/upload-ct-artifacts.sh $AID atx-ct-output-${ACCOUNT_ID}"
```

## Use Existing Instance (no CFN)

Reached when **Step 0 returned no stack** and the customer chose path 1 (existing EC2 instance launched outside CFN). Steps C.1–C.7 verify the instance, bootstrap the atx-ct container, and resume at Step 6.

**At most ONE admin handoff** is needed in this path -- Step C.0 pre-flights both the instance tag and the role permissions in read-only mode, then emits a single combined admin handoff if either is missing. After admin runs that one bundle, the executor proceeds through C.2–C.6 (Docker install, image pull, container start) without further interruption. If both the tag and role were already in place, the handoff is skipped entirely.

### Step C.0: Pre-flight + Combined Admin Handoff

Capture the basics first:

```bash
INSTANCE_ID="<existing-instance-id>"
REGION="<region>"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Discover the instance's IAM role (executor's iam:GetInstanceProfile is account-scoped, so this works).
PROFILE_ARN=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text)
PROFILE_NAME=$(echo "$PROFILE_ARN" | awk -F/ '{print $NF}')
INSTANCE_ROLE_NAME=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" \
  --query 'InstanceProfile.Roles[0].RoleName' --output text)

if [ -z "$INSTANCE_ROLE_NAME" ] || [ "$INSTANCE_ROLE_NAME" = "None" ]; then
  echo "ERROR: instance has no IAM instance profile attached. The customer's admin must"
  echo "       create one and attach it before this skill can proceed. This is a much larger"
  echo "       handoff than tagging or policy-setting; bail out and ask the customer."
  exit 1
fi
```

**Read-only pre-flight checks** (executor creds suffice for all of these):

```bash
# Check 1: Is the instance tagged atx-remote-infra=true?
TAG_VALUE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION \
  --query 'Reservations[0].Instances[0].Tags[?Key==`atx-remote-infra`].Value | [0]' --output text)
TAG_OK="no"; [ "$TAG_VALUE" = "true" ] && TAG_OK="yes"

# Check 2: Does the role have transform-custom:* (the marker action that proves the
#          full Instance Role IAM spec was applied)? Inspect inline policies.
ROLE_POLICIES=$(aws iam list-role-policies --role-name "$INSTANCE_ROLE_NAME" --query 'PolicyNames' --output text)
ROLE_OK="no"
for POLICY in $ROLE_POLICIES; do
  if aws iam get-role-policy --role-name "$INSTANCE_ROLE_NAME" --policy-name "$POLICY" \
       --query 'PolicyDocument.Statement[].Action' --output json 2>/dev/null \
       | grep -q '"transform-custom:\*"'; then
    ROLE_OK="yes"; break
  fi
done

# Check 3: Is AmazonSSMManagedInstanceCore attached?
SSM_OK="no"
aws iam list-attached-role-policies --role-name "$INSTANCE_ROLE_NAME" \
  --query 'AttachedPolicies[?PolicyName==`AmazonSSMManagedInstanceCore`].PolicyName' \
  --output text 2>/dev/null | grep -q AmazonSSMManagedInstanceCore && SSM_OK="yes"

echo "Tag atx-remote-infra=true:           $TAG_OK"
echo "Role has transform-custom:* etc:     $ROLE_OK"
echo "AmazonSSMManagedInstanceCore attached: $SSM_OK"
```

**If all three are `yes`**: skip the handoff and proceed directly to Step C.1.

**If any is `no`**: emit ONE combined admin handoff covering all the missing pieces. Tell the customer:

> **Admin handoff -- one-time setup for `$INSTANCE_ID`**
>
> This bundle (a) tags the instance so the executor can SSM into it, (b) attaches the full ATX Control Tower instance role policy, and (c) ensures `AmazonSSMManagedInstanceCore` is attached. All three are admin-only operations (`ec2:CreateTags`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`). Run with admin / role-creation permissions:
>
> ```bash
> INSTANCE_ID="$INSTANCE_ID"
> INSTANCE_ROLE_NAME="$INSTANCE_ROLE_NAME"
> ACCOUNT_ID="$ACCOUNT_ID"
> REGION="$REGION"
>
> # 1. Tag the instance so executor's tag-conditioned SSM permissions activate
> aws ec2 create-tags \
>   --resources "$INSTANCE_ID" \
>   --tags Key=atx-remote-infra,Value=true \
>   --region "$REGION"
>
> # 2. Attach the full ATX Control Tower instance role policy (the FULL spec from
> #    the Instance Role IAM section -- do NOT subset by analysis type).
> aws iam put-role-policy \
>   --role-name "$INSTANCE_ROLE_NAME" \
>   --policy-name atx-transform-access \
>   --policy-document '{
>     "Version": "2012-10-17",
>     "Statement": [
>       {"Effect": "Allow", "Action": "transform-custom:*", "Resource": "*"},
>       {"Effect": "Allow",
>        "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
>        "Resource": ["arn:aws:s3:::atx-source-code-'$ACCOUNT_ID'",
>                     "arn:aws:s3:::atx-source-code-'$ACCOUNT_ID'/*",
>                     "arn:aws:s3:::atx-ct-output-'$ACCOUNT_ID'",
>                     "arn:aws:s3:::atx-ct-output-'$ACCOUNT_ID'/*"]},
>       {"Effect": "Allow", "Action": "secretsmanager:GetSecretValue",
>        "Resource": "arn:aws:secretsmanager:*:'$ACCOUNT_ID':secret:atx/*"},
>       {"Effect": "Allow",
>        "Action": ["securityagent:ListAgentSpaces",
>                   "securityagent:CreateCodeReview", "securityagent:StartCodeReviewJob",
>                   "securityagent:ListCodeReviewJobsForCodeReview",
>                   "securityagent:ListFindings", "securityagent:BatchGetFindings",
>                   "securityagent:StartCodeRemediation"],
>        "Resource": "arn:aws:securityagent:*:*:agent-space*",
>        "Condition": {"StringEquals": {"aws:ResourceAccount": "'$ACCOUNT_ID'"}}},
>       {"Effect": "Allow",
>        "Action": ["s3:GetObject", "s3:ListBucket"],
>        "Resource": ["arn:aws:s3:::kct-security-agent-*",
>                     "arn:aws:s3:::kct-security-agent-*/*"]},
>       {"Effect": "Allow", "Action": "s3:PutObject",
>        "Resource": "arn:aws:s3:::kct-security-agent-*/security-scans/*"},
>       {"Effect": "Allow", "Action": "iam:PassRole",
>        "Resource": "arn:aws:iam::'$ACCOUNT_ID':role/security-agent-*",
>        "Condition": {"StringEquals": {"iam:PassedToService": "securityagent.amazonaws.com"}}},
>       {"Effect": "Allow", "Action": ["kms:GenerateDataKey", "kms:Decrypt", "kms:Encrypt", "kms:DescribeKey"],
>        "Resource": "arn:aws:kms:*:'$ACCOUNT_ID':key/*",
>        "Condition": {"StringLike": {"kms:ViaService": "s3.*.amazonaws.com"}}}
>     ]
>   }'
>
> # 3. Ensure the SSM agent's managed policy is attached (idempotent).
> aws iam attach-role-policy \
>   --role-name "$INSTANCE_ROLE_NAME" \
>   --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>&1 | grep -v "EntityAlreadyExists" || true
> ```
>
> When this finishes, come back to the conversation. I'll re-run the pre-flight checks and continue from Step C.1.

The handoff bundles all admin operations the existing-instance path needs -- there are no other admin handoffs later in the flow.

The agent MUST omit any block from the handoff that's already correct. Example: if `TAG_OK=yes` but `ROLE_OK=no`, drop block #1, keep #2 and #3. The point is to print exactly what's needed, not the full template every time.

### Step C.1: Customer provides WorkerCount

`INSTANCE_ID`, `REGION`, and `ACCOUNT_ID` were already captured in Step C.0. The remaining input the customer chooses is WorkerCount:

```bash
# WorkerCount: how many parallel atx-ct containers to run on this instance.
# Default 1 (single container). For multi-repo parallelism, customer chooses
# N sized to their instance's vCPU/RAM.
WORKER_COUNT="${WORKER_COUNT:-1}"
```

ALWAYS ask before proceeding: "How many parallel containers do you want on this instance? Each worker uses ~3-4 vCPU and ~4-8 GB RAM. Default 1." Ask explicitly even when the customer is only running a single analysis, so they know multi-worker is an option. Sizing guidance based on instance type:

- t3.medium / t3.large (2 vCPU): 1 worker
- m5.xlarge / m5.2xlarge (4-8 vCPU): 2-4 workers
- m5.4xlarge or larger (16+ vCPU): up to 5 workers (cap; for more parallelism use the Batch path)

For monorepos or memory-heavy analyses, scale down. The skill does NOT auto-detect the instance's capacity for an existing instance; the customer is responsible for sizing.

### Step C.2: Verify SSM is online

```bash
PING=$(aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text --region $REGION)
[ "$PING" = "Online" ] || { echo "ERROR: SSM agent not Online (got: ${PING:-no response})"; exit 1; }
```

If not Online, the instance is missing `AmazonSSMManagedInstanceCore` on its IAM role, or the SSM agent is not running. Customer must fix this before proceeding.

Define the SSM helpers used by the rest of the steps:

```bash
ssm_submit() {
  aws ssm send-command --region $REGION \
    --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "commands=[\"$1\"]" --query 'Command.CommandId' --output text
}

ssm_run() {
  local cmd="$1"
  local CMD_ID=$(aws ssm send-command --region $REGION \
    --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "commands=[\"$cmd\"]" --query 'Command.CommandId' --output text)
  aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" --region $REGION 2>/dev/null || true
  aws ssm get-command-invocation --region $REGION \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text
}
```

### Step C.3: Verify Docker is installed (install if missing)

```bash
DOCKER_STATUS=$(ssm_run "command -v docker >/dev/null 2>&1 && echo INSTALLED || echo MISSING")
```

If `MISSING`, install:

```bash
ssm_run "if command -v dnf >/dev/null; then sudo dnf install -y docker; \
         elif command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y docker.io; \
         elif command -v yum >/dev/null; then sudo yum install -y docker; \
         else echo 'ERROR: unsupported package manager' >&2; exit 1; fi && \
         sudo systemctl start docker && sudo systemctl enable docker"
```

Verify with `ssm_run "docker --version"`. If it fails, ask the customer to install Docker manually and re-try.

### Step C.4: Pull the public docker image

Reachability check (any HTTP response code means reachable; the public ECR API legitimately returns 401 for anonymous requests):

```bash
HTTP_CODE=$(ssm_run "curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://public.ecr.aws/v2/")
```

Expected: `200` or `401`. If `000`, the instance has no path to public.ecr.aws. Mitigation: customer adds NAT, OR mirrors the image to ECR Private and overrides `ATX_IMAGE_URI` in Step C.5 below.

Pull:

```bash
ssm_run "sudo docker pull public.ecr.aws/d9h8z6l7/aws-transform:latest"
```

If the pull fails: typical causes are network egress, insufficient disk space, or a private-registry override needed.

### Step C.5: Launch the atx-ct container(s)

If `WORKER_COUNT=1`, launch a single container named `atx-ct` (matches CFN single-worker naming). If `WORKER_COUNT>1`, launch `atx-ct-1`, `atx-ct-2`, ..., `atx-ct-N`. Each container runs `atx ct server` as the foreground process; this mirrors the CFN UserData pattern: override the image's job-runner entrypoint with bash and run the server (which keeps the container alive). The container image must already contain `atx ct` -- there is no runtime install step.

```bash
if [ "$WORKER_COUNT" -eq 1 ]; then
  CONTAINERS="atx-ct"
else
  CONTAINERS=$(seq -f "atx-ct-%g" 1 $WORKER_COUNT)
fi

for name in $CONTAINERS; do
  # Cap each container's memory so a runaway analysis can only OOM its own
  # container, never the host (which would OOM-kill the SSM agent and sever
  # access). The memory math runs on the REMOTE host (\$-escaped) because an
  # existing instance's RAM is not known laptop-side; ~4 GB is reserved for the
  # OS/Docker/SSM agent and the remainder split across the workers.
  # WORKER_COUNT is the authoritative worker count (Step 2 reads it from the
  # stack/instance). Resolve it on the LAPTOP with a :-1 fallback so a re-paste in
  # a fresh shell where it is unset degrades to 1 instead of rendering "/ ))" --
  # a bash arithmetic syntax error that would leave the container unlaunched with
  # the error buried in SSM StandardErrorContent. (A bare "$WORKER_COUNT" had no
  # such guard.) The fallback resolves laptop-side, so the remote host divides by
  # the real count, never a blind 1 that would over-commit a multi-worker host.
  ssm_run "WC=${WORKER_COUNT:-1}; sudo docker rm -f $name 2>/dev/null; \
    MEM_TOTAL_MB=\$(( \$(awk '/MemTotal/{print \$2}' /proc/meminfo) / 1024 )); \
    MEM_PER_WORKER_MB=\$(( (\$MEM_TOTAL_MB - 4096) / \$WC )); \
    [ \$MEM_PER_WORKER_MB -lt 2048 ] && MEM_PER_WORKER_MB=2048; \
    sudo docker run -d --name $name --restart on-failure:3 \
      --memory=\${MEM_PER_WORKER_MB}m --memory-swap=\${MEM_PER_WORKER_MB}m \
      --entrypoint /bin/bash \
      -e CT_OUTPUT_BUCKET=atx-ct-output-${ACCOUNT_ID} \
      -e AWS_REGION=${REGION} \
      public.ecr.aws/d9h8z6l7/aws-transform:latest \
      -c 'mkdir -p /home/atxuser/.atxct/sources /home/atxuser/.atxct/shared && \
          source ~/.bashrc && atx ct server'"
done
```

Multi-worker uses bridge networking (no `--net=host`) so each container has its own network namespace. Launches happen sequentially via SSM, so total launch time scales with `WORKER_COUNT`.

### Step C.6: Wait for all container(s) healthy

```bash
for name in $CONTAINERS; do
  for i in $(seq 1 18); do
    STATUS=$(ssm_run "sudo docker ps --filter 'name=^${name}$' --format '{{.Status}}'")
    echo "$STATUS" | grep -q '(healthy)' && { echo "$name healthy after $((i*5))s"; break; }
    sleep 5
  done
done
```

If any container fails to reach healthy after 90s, inspect that specific container's logs: `ssm_run "sudo docker logs <name> 2>&1 | tail -30"`. Common causes are install network failure (one container's network namespace differs) and per-worker port conflicts (rare with bridge networking).

Verify the CT CLI in one container (all containers share the same image, so verifying one is enough):

```bash
FIRST_CONTAINER=$(echo $CONTAINERS | awk '{print $1}')
ssm_run "sudo docker exec $FIRST_CONTAINER bash -c 'source ~/.bashrc && atx --version'"
```

### Step C.7: Verify Instance Role Permissions (sanity check)

Step C.0's pre-flight should have caught any missing role permissions before we got here, but the `atx ct server` startup runs real backend calls (resume remediations, list sources) that exercise permissions in ways the static check can't fully simulate. This step is a runtime sanity check.

Check the first container's startup log for AccessDenied errors:

```bash
FIRST_CONTAINER=$(echo $CONTAINERS | awk '{print $1}')
ssm_run "sudo docker logs $FIRST_CONTAINER 2>&1 | grep -iE 'AccessDenied|not authorized' | head -5"
```

If the grep returns empty: server initialized cleanly. Proceed to **Step 7 (Confirm and Submit)**.

If the grep returns matches: this means the role's policy is somehow incomplete relative to the [Instance Role IAM](#instance-role-iam) section, despite Step C.0 saying it had `transform-custom:*`. Most likely cause: a custom inline policy that has only some of the required statements. Re-emit the **same combined admin handoff from Step C.0** (`aws iam put-role-policy --policy-name atx-transform-access ...` with the FULL spec from the Instance Role IAM section -- do NOT subset it). This will overwrite the partial policy with the complete one.

## Instance Role IAM

The EC2 instance's IAM role (`atx-transform-role` from Step 4) needs:

```json
{
  "Statement": [
    { "Effect": "Allow", "Action": "transform-custom:*", "Resource": "*" },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::atx-source-code-${ACCOUNT_ID}",
        "arn:aws:s3:::atx-source-code-${ACCOUNT_ID}/*",
        "arn:aws:s3:::atx-ct-output-${ACCOUNT_ID}",
        "arn:aws:s3:::atx-ct-output-${ACCOUNT_ID}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "arn:aws:secretsmanager:*:${ACCOUNT_ID}:secret:atx/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "securityagent:ListAgentSpaces",
        "securityagent:CreateCodeReview",
        "securityagent:StartCodeReviewJob",
        "securityagent:ListCodeReviewJobsForCodeReview",
        "securityagent:ListFindings",
        "securityagent:BatchGetFindings",
        "securityagent:StartCodeRemediation"
      ],
      "Resource": "arn:aws:securityagent:*:*:agent-space*",
      "Condition": { "StringEquals": { "aws:ResourceAccount": "${ACCOUNT_ID}" } }
    },
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::kct-security-agent-*", "arn:aws:s3:::kct-security-agent-*/*"]
    },
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::kct-security-agent-*/security-scans/*"
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/security-agent-*",
      "Condition": { "StringEquals": { "iam:PassedToService": "securityagent.amazonaws.com" } }
    },
    {
      "Effect": "Allow",
      "Action": ["kms:GenerateDataKey", "kms:Decrypt", "kms:Encrypt", "kms:DescribeKey"],
      "Resource": "arn:aws:kms:*:${ACCOUNT_ID}:key/*",
      "Condition": { "StringLike": { "kms:ViaService": "s3.*.amazonaws.com" } }
    }
  ]
}
```

Plus the AWS-managed policy `arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore` (attached separately) so the SSM agent can phone home.

## Container Customization

The pre-built `public.ecr.aws/d9h8z6l7/aws-transform:latest` image includes Java 8/11/17/21/25, Python 3.8-3.14, Node.js 16-24, Maven, Gradle, common build tools, AWS CLI v2, and AWS Transform CLI. CT CLI is installed at container start time via the curl install.

For continuous modernization analyses, the pre-built image's defaults handle every runtime need. For custom TDs requiring a runtime not in the image (Rust, Go, .NET on Linux), follow [custom-remote-execution#custom-image-path](custom-remote-execution.md#custom-image-path-docker-required).

## Runtime Version Switching

For remediation runs that target a specific language version (e.g., Java 21, Python 3.13), pass the version as an environment variable on the `docker run` (Step 6):

```bash
# Each ssm_run is a separate remote shell, so compute MEM_PER_WORKER_MB in the
# SAME command that launches the container (Step C.5 does the identical compute).
# WORKER_COUNT resolves laptop-side with a :-1 fallback (see Step C.5) so an unset
# value degrades to 1 instead of rendering an empty divisor "/ ))".
ssm_run "WC=${WORKER_COUNT:-1}; MEM_TOTAL_MB=\$(( \$(awk '/MemTotal/{print \$2}' /proc/meminfo) / 1024 )); \
  MEM_PER_WORKER_MB=\$(( (\$MEM_TOTAL_MB - 4096) / \$WC )); \
  [ \$MEM_PER_WORKER_MB -lt 2048 ] && MEM_PER_WORKER_MB=2048; \
  sudo docker run -d --name atx-ct --restart on-failure:3 \
    --memory=\${MEM_PER_WORKER_MB}m --memory-swap=\${MEM_PER_WORKER_MB}m ... \
    -e JAVA_VERSION=21 \
    -e PYTHON_VERSION=3.13 \
    -e NODE_VERSION=22 \
    $IMAGE -c '...'"
```

Available versions:

- **Java**: 8, 11, 17, 21, 25 (Amazon Corretto)
- **Python**: 3.8-3.14 (accepts `3.13` or `13`)
- **Node.js**: 16, 18, 20, 22, 24

For analyses, runtime switching is generally not needed.

## Limits

- Per-job temp files (LOG, AID_FILE, STDOUT_LOG) keyed by JOB_ID let multiple concurrent jobs coexist
- Bedrock throughput is per-account -- running many parallel continuous modernization containers shares the quota; large workloads may throttle

## Error Handling

| Error                                                                                                  | Cause                                                                                                                                                                                                                                                                                                       | Fix                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| SSM agent not Online                                                                                   | Instance role missing `AmazonSSMManagedInstanceCore` or no outbound internet                                                                                                                                                                                                                                | Re-attach the managed policy; verify VPC has NAT or public IP                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Container exits / restarts on launch (or stays `exited`)                                               | `atx ct server` crashed, OR exited cleanly (exit 0) and was intentionally not recovered by `--restart on-failure:3`, OR the image failed to pull                                                                                                                                                            | First triage with `ssm_run "sudo docker inspect <name> --format '{{.State.Status}} ExitCode={{.State.ExitCode}} RestartCount={{.RestartCount}} OOMKilled={{.State.OOMKilled}}'"`. If `OOMKilled=true`, see the OOM row below. If `ExitCode=0`, the server exited cleanly and was correctly NOT auto-restarted -- investigate why it shut down (`docker logs`). If `ExitCode!=0` (often `RestartCount=3`), check `docker logs <name>` for a crash: image-pull failure (verify NAT/public IP to `public.ecr.aws`), port conflict on 8081, or missing env/role perms. If UserData itself failed, the stack is in `ROLLBACK_COMPLETE`; check `aws cloudformation describe-stack-events --stack-name $STACK_NAME` |
| Container OOM-killed (gone after a few restarts; jobs fail with "container not running")               | The workload exceeded the container's per-worker `--memory` cap (e.g. a heavy parallel-clone analysis); `--restart on-failure:3` retried 3x then left it down                                                                                                                                               | `ssm_run "sudo docker inspect <name> --format '{{.State.OOMKilled}} {{.State.ExitCode}} {{.RestartCount}} {{.State.Status}}'"`. If `OOMKilled=true`, the cap was exceeded -- give each worker more RAM: raise `InstanceType` and/or lower `WorkerCount` (each gets `(instance RAM - 4 GB) / WorkerCount`), then re-provision. **If `OOMKilled=false` but `RestartCount=3 Status=exited`, this is NOT an OOM** -- the server crashed for another reason; fall through to "Container exits / restarts on launch" above. Restart a downed container with `ssm_run "sudo docker start <name>"`                                                                                                                   |
| `atx ct analysis run` clone fails                                                                      | PAT expired or repo private to a different account                                                                                                                                                                                                                                                          | Verify customer's PAT has access; re-stage source config (Step 6)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Findings missing after analysis                                                                        | Server crashed before persisting                                                                                                                                                                                                                                                                            | Check `tail /tmp/atxct-<job-id>.log`; recover via `analysis get --id $AID`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Artifacts missing from S3                                                                              | Wrapper killed before upload step                                                                                                                                                                                                                                                                           | Re-run upload manually (see Cancellation section)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Polling never completes                                                                                | atx ct server hung or container down                                                                                                                                                                                                                                                                        | `ssm_run "sudo docker ps"` and `ssm_run "sudo docker logs ${CONTAINER_NAME} \| tail"` to diagnose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Container starts but all AWS API calls return "credentials not available" or fail to reach IMDS        | Bridge networking + IMDSv2 hop limit = 1 (default). Token TTL expires before reaching the container's network namespace.                                                                                                                                                                                    | On an existing instance, the customer can run `aws ec2 modify-instance-metadata-options --instance-id <id> --http-put-response-hop-limit 2 --region <region>`. We do NOT modify metadata options on customer instances automatically; it's a side-effect on resources they own. The CFN-managed flow does not hit this in practice with current Docker bridge defaults.                                                                                                                                                                                                                                                                                                                                      |
| Status-check ssm_run calls hang during fan-out                                                         | Older fan-out submissions kept SSM agent worker slots occupied until each wrapper exited (CommandWorkersLimit default 5). Mitigated by submitting all workers via a single SSM command and using `( ( bash X & ) & )` double-fork to orphan each wrapper to init. SSM marks the launch Success immediately. | If you still observe queueing, list in-flight commands with ``aws ssm list-commands --instance-id <id> --query 'Commands[?Status==`InProgress`].CommandId'`` and cancel orphaned ones via `aws ssm cancel-command --command-id <id>`. Read wrapper progress through a single batched `ssm_run` reading `/tmp/atxct-fan-w*-*.{log,aids,rids}` rather than many small calls.                                                                                                                                                                                                                                                                                                                                   |
| `atx ct analysis run` hangs cloning from internal/self-hosted git host                                 | Subnet has 0.0.0.0/0 egress (Step 5b validation passed) but no route to the customer's internal git host. VPN / Direct Connect / VPC peering missing or filtered.                                                                                                                                           | The skill cannot auto-verify routes to corporate-network git hosts. Confirm with the network team that the subnet's route table includes a path to the git host CIDR. Test from any instance in the same subnet: `nslookup <git-host>` then `curl -v https://<git-host>/`.                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Stack create fails with "no NAT/route" or container UserData times out after Step 5b validation passed | Subnet's 0.0.0.0/0 default route was removed (or the subnet was switched to a different route table) between Step 5b validation and stack deploy.                                                                                                                                                           | Re-run Step 5b validation on the current state of the route table. The check uses `ec2:DescribeRouteTables`; if the network team is making concurrent changes, run validation immediately before the admin handoff.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

## Pricing

Direct customer to:

- EC2 pricing: https://aws.amazon.com/ec2/pricing/
- AWS Transform agent minutes: https://aws.amazon.com/transform/pricing/

Do NOT quote specific dollar amounts or time estimates.

## Cleanup

**Never delete the stack or stop/terminate the instance without explicit customer confirmation.** `delete-stack` is destructive -- it removes the instance, IAM role, and security group, and any in-flight analyses on the instance will be terminated. Even if the customer said "I'm done" earlier in the conversation, ask again before issuing the delete.

When the customer indicates they're finished, prompt with options and **wait for explicit confirmation** before running any of the commands below:

> Your EC2 stack `${STACK_NAME}` is still running and incurring charges. What would you like to do?
>
> 1. **Delete the stack** (admin handoff) -- removes the instance, IAM role, and security group atomically. Stops all charges. Your S3 buckets and Secrets Manager entries persist (so analysis history survives). Requires admin creds -- I'll print the command for someone with `cloudformation:DeleteStack` + `iam:Delete*` to run.
> 2. **Stop the instance** -- keeps the stack but stops the EC2. No compute charges, small EBS storage charge. Container needs to re-initialize after restart. I CAN run this with executor creds (`ec2:StopInstances` on the tagged instance).
> 3. **Keep running** -- instance stays up. Hourly EC2 charges continue. Useful if another analysis is coming.
>
> Reply with 1, 2, or 3.

Do NOT run delete-stack proactively. Do NOT assume option 1 because the customer's last analysis finished. The customer must explicitly choose.

### Option 1: Delete the entire stack -- admin handoff (only after explicit confirmation)

The agent does NOT run `delete-stack` itself. Deleting the stack tears down the IAM role, instance profile, and security group, which requires `iam:DeleteRole`, `iam:DeleteRolePolicy`, `iam:DeleteInstanceProfile`, and `cloudformation:DeleteStack` -- all of these live in the admin policy, not the executor policy. The agent prints the command and the customer's admin runs it:

```bash
# Admin runs:
aws cloudformation delete-stack --stack-name "$STACK_NAME" --region $REGION
aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" --region $REGION
```

This removes everything in the stack atomically. If anything fails to delete, the stack moves to `DELETE_FAILED` and the customer can inspect what's left (executor creds CAN read this):

```bash
aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region $REGION \
  --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]'
```

### Option 2: Stop the instance (only after explicit confirmation)

```bash
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
```

The stack stays in `CREATE_COMPLETE`. Customer can `aws ec2 start-instances` later to bring it back. Note: container needs time to become healthy after start (atx ct server has to re-initialize).

### Option 3: Keep running

No-op. Customer continues to pay EC2 hourly charges. Useful when expecting another analysis soon.

**What persists across delete-stack:**

| Resource                                                                     | Persists?                           | Why                                                  |
| ---------------------------------------------------------------------------- | ----------------------------------- | ---------------------------------------------------- |
| S3 buckets (`atx-source-code-${ACCOUNT_ID}`, `atx-ct-output-${ACCOUNT_ID}`)  | ✅ Yes -- managed outside the stack | Customer's analysis results survive stack lifecycles |
| Secrets Manager (`atx/github-token`, etc.)                                   | ✅ Yes -- managed outside the stack | Customer's tokens persist for next run               |
| Customer-supplied VPC, subnet, security group (when reused)                  | ✅ Yes -- never owned by the skill  | Customer or their network team owns these            |
| Stack-managed resources (instance, IAM role, profile, SG when stack-created) | ❌ No -- deleted with stack         | Recreated on next `create-stack`                     |

**Resources the skill MUST NEVER delete, under any circumstances:**

- **Customer-supplied VPCs, subnets, route tables, NAT gateways, internet gateways, transit gateways, VPC peering connections** -- these are network infrastructure owned by the customer or their network team. The skill never created them (we don't have permission to), and we never delete them. If a customer asks "clean up everything including the VPC," refuse and explain that VPC lifecycle is a network-team responsibility.
- **Customer-supplied security groups** (when the customer chose "reuse" at Step 5b's SG ask) -- these existed before our stack and persist after it. Only stack-created SGs (when the customer typed `new`) get cleaned up via `delete-stack`.
- **S3 buckets** (`atx-source-code-*`, `atx-ct-output-*`) -- these hold customer analysis history and are intentionally outside the stack to survive stack delete-and-recreate. The skill never empties them or removes them. Lifecycle policies auto-expire objects (7 days for source bundles, 30 days for output artifacts), so residual storage cost converges to zero without intervention.
- **Secrets** (`atx/github-token`, `atx/gitlab-token`, etc.) -- these hold customer credentials and persist across stacks. Customers may want to keep them for future analyses on a fresh stack. The skill never deletes them.

If the customer asks for "complete teardown" or "delete everything," the agent's response is: "I can run `delete-stack` which removes the runner instance, IAM role, instance profile, and any stack-created security group. Your S3 buckets, secrets, and customer-owned network resources (VPC/subnets/SGs you supplied) stay -- those aren't owned by this skill. If you want to remove those too, please do it directly in the AWS console or CLI; I won't run those commands because they're destructive of data and infrastructure outside the skill's scope."
