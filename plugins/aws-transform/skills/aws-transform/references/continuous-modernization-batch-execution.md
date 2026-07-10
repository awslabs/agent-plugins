---
name: batch-execution
description: Run continuous modernization analysis on AWS Batch (Fargate) using one container per submission. Each container runs `atx ct analysis run` (or `remediation create`) on the customer's logical source, then uploads artifacts via the upload script baked into the image at `/app/upload-ct-artifacts.sh`.
---

# continuous modernization Batch/Fargate Execution

## ⚠️ MANDATORY: Permission Consent (MUST be first interaction with customer)

**CRITICAL: The VERY FIRST thing the agent says after the customer chooses Batch/Fargate is the consent message below. Do NOT ask ANY questions (source, analysis type, region, etc.) before showing this message and getting confirmation. No exceptions.**

"To run the analysis on Batch/Fargate, I will need to create and manage the following resources in your account: AWS Transform API access, CloudFormation stacks, a VPC with subnets and NAT gateway, Batch compute environments and job queues, a Batch job definition, Lambda functions for job management, S3 buckets for source code and results, a KMS key for encryption, IAM roles for task execution, CloudWatch logs and dashboard, secrets for source credentials, and security agent resources for vulnerability scanning. Do you have permissions to create and manage these resources?"

If the customer says **yes** → proceed with the rest of the workflow.
If the customer says **no** → respond with: "You may encounter permission errors during the setup process. We'll continue, but some steps may fail if permissions are missing." Then proceed with the workflow.

## Telemetry

When running `atx ct analysis run` or `atx ct remediation create`, always include `--telemetry`.

Format: `--telemetry "agent=<agent>,executionMode=<mode>"`

- `agent` — the AI assistant driving this session (lowercase, no spaces). Use the real assistant name — e.g. kiro, claude, amazonq, copilot.
- `executionMode` — `fargate`

If the user explicitly asks to disable telemetry, omit `--telemetry` for the rest of the session.

Run continuous modernization analysis or remediation on AWS Batch (Fargate) with **one container per submission** (default). Each container starts an `atx ct server`, sets up the source's local config + credentials, and runs analysis or remediation across all repos in the source. For analysis on any provider, and for remediation on `local`-provider sources, artifacts are uploaded to S3. For remediation on `github` / `gitlab` sources, the backend pushes to a result branch — no S3 upload needed. Multiple parallel containers per batch are supported via the submission patterns (B/C) when the customer wants multiple analysis types on one source or multiple sources in one batch.

## When to Use

- Analyzing or remediating one or more sources at scale on AWS-managed compute (no EC2 to provision)
- Running multiple analysis types in parallel on the same source
- Running analysis/remediation across multiple sources in parallel (e.g., team-A's github + team-B's gitlab)
- Running per-repo parallel analysis (one container per repo via `--repo`) when the customer wants maximum parallelism or per-repo failure isolation
- Customer already has the Custom CDK stack deployed (reuses infrastructure)
- Source contains many repos (atx ct parallelizes up to 8 inside a single container; use per-repo Pattern D for more parallelism)

## Architecture

```
Customer's local machine
  ↓ atx ct source add (registers source with the backend)
  ↓ "Run analysis on Batch"
  ↓ aws lambda invoke atx-trigger-batch-jobs (one job per submission)
AWS Batch (Fargate) -- single container per submission
  └── Container (public.ecr.aws/d9h8z6l7/aws-transform:latest)
      ├── JOB_COMMAND (analysis):
      │     - Install / upgrade atx ct CLI
      │     - Start atx ct server
      │     - github / gitlab: place token in ~/.atxct/sources/<src>/<provider>_token
      │     - local:           pull repo bundle from S3, discovery scan with --path override
      │     - atx ct analysis run --type <type> --source <src> --wait
      │       └─ CT server clones each repo as needed (github / gitlab) and performs analysis
      │     - curl + /app/upload-ct-artifacts.sh -- zips each repo's working dir to S3
      │       └─ skipped for tech-debt-quick (no analysis artifacts to capture)
      └── Container exits
```

This pattern keeps `atx ct analysis run` as the unit of work. Source attribution is preserved end-to-end — findings carry the customer's source name.

## Provider Compatibility

| Provider   | Container setup                                                                                  | Analysis output           | Remediation flag     | Remediation output                                   |
| ---------- | ------------------------------------------------------------------------------------------------ | ------------------------- | -------------------- | ---------------------------------------------------- |
| **github** | Place `github_token` (no `source add` in container)                                              | `code.zip` per repo in S3 | NO `--local`         | Result branch pushed to source repo and PR is opened |
| **gitlab** | Place `gitlab_token` (no `source add` in container)                                              | `code.zip` per repo in S3 | NO `--local`         | Result branch pushed to source repo and MR is opened |
| **local**  | Pull bundle from S3, `discovery scan --path` (idempotent — creates/updates local config + scans) | `code.zip` per repo in S3 | `--local` (required) | `code.zip` per repo in S3                            |

For github / gitlab, the customer must register the source on their own machine first via `atx ct source add --provider github|gitlab --org <name> --token <pat> [--url <base-url>]`. The container only injects the token at runtime; everything else (provider type, base URL, identifier) comes from the backend's source record at clone time.

## Step 0: Detect Infrastructure, Then Branch (Provision vs Operate)

This is the entry gate for every Batch run. It is read-only and safe under any
credentials, including ReadOnly.

**Network contract:** AWS Transform creates Batch, Lambdas, S3, KMS, IAM, and
security groups via CloudFormation. It does NOT create VPCs, subnets, NAT gateways,
or internet gateways — you provide those. If you don't specify a VPC, deployment
will fail rather than auto-provision.

**Constraints:**

- You MUST run this detection BEFORE asking the user anything about jobs, because
  the answer decides whether the user needs to provision first or can submit work now.
- You MUST run:

  ```bash
  aws cloudformation describe-stacks --stack-name AtxInfrastructureStack \
    --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_DEPLOYED"
  ```

- If the status is `CREATE_COMPLETE` or `UPDATE_COMPLETE`, You MUST treat the stack
  as live and proceed to the OPERATE lifecycle (Step 1 onward — job submission).
- If the status is `NOT_DEPLOYED` or any non-complete state, You MUST enter the
  PROVISION lifecycle (Step 0a–0c below) and You MUST NOT attempt to submit jobs,
  because the Batch infrastructure does not yet exist.
- You MUST NOT run any provisioning command yourself in this step; detection is
  read-only.
- You MUST NEVER run `aws ec2 create-default-vpc` or create any VPC, subnet, NAT
  gateway, internet gateway, or route on the user's behalf. If the account has no
  suitable VPC, surface the situation to the user and refuse to proceed.

### Step 0a: Clone repo and discover VPCs

**Constraints:**

- You MUST clone (or update) the infra repo FIRST, before any reference to files
  inside it:

  ```bash
  ATX_INFRA_DIR="$HOME/.aws/atx/custom/remote-infra"
  [ -d "$ATX_INFRA_DIR" ] || git clone -b atx-remote-infra --single-branch \
    https://github.com/aws-samples/aws-transform-custom-samples.git "$ATX_INFRA_DIR"
  ```

- You MUST then discover the user's available VPCs by running:

  ```bash
  aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,IsDefault,Tags[?Key==`Name`].Value|[0]]' --output table
  ```

- Show the results to the user. If no VPCs exist (or none have private subnets with
  NAT for Fargate), direct the user to the helper script:

  ```
  A utility script is available to create a Fargate-ready VPC with private subnets,
  NAT gateway, and security group:

  cd "$HOME/.aws/atx/custom/remote-infra" && ./create-vpc.sh

  Run this from another terminal with admin credentials. It will print the VPC,
  subnet, and security group IDs to use in cdk.json.
  ```

  You MUST NOT run `create-vpc.sh` yourself — present it for the user to run from
  another terminal. After they run it, ask them for the output values to continue.
- Ask the user which VPC to use (MANDATORY). You MUST NOT recommend, suggest, or
  guide the user toward any VPC (including the default VPC). Present all VPCs
  neutrally without commentary on which is "simplest", "easiest", or "looks
  pre-configured". The user must make their own informed choice.
- After the user picks a VPC, show its **private** subnets and security groups:

  ```bash
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpcId>" "Name=map-public-ip-on-launch,Values=false" \
    --query 'Subnets[*].[SubnetId,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpcId>" \
    --query 'SecurityGroups[*].[GroupId,GroupName,Description]' --output table
  ```

- You MUST only present **private subnets** (`MapPublicIpOnLaunch=false`) to the user.
  The query above filters them via `map-public-ip-on-launch=false`. This is a hard
  requirement: the CDK stack sets `assignPublicIp: DISABLED` on Fargate tasks, so tasks
  in public subnets get a private IP that cannot route through an internet gateway.
  If the result set is empty (all subnets in the VPC are public), tell the user:
  "No private subnets found in this VPC. This stack does not support public subnets —
  Fargate tasks require private subnets with NAT gateway for outbound connectivity."
  Then direct them to `create-vpc.sh`.
  If the VPC contained public subnets that were filtered out, include this note when
  presenting results: "Some subnets in this VPC were not shown because they are public
  (auto-assign public IP enabled). This stack does not support public subnets — Fargate
  tasks require private subnets with NAT gateway for outbound connectivity."
- Then ask the user to select:
  1. `existing_subnet_ids`: which subnets (MANDATORY).
  2. `existing_security_group_id`: which security group (MANDATORY).
  3. Source provider: `github`, `gitlab`, `bitbucket`, or `local`.
- You MUST refuse to proceed without explicit VPC, subnet, and security group
  selection — there is no default or fallback path.
- You MUST NOT choose the VPC, subnets, or security group on the user's behalf, even
  if only one option exists or one appears obvious. Always ask and wait for the user
  to explicitly state their selection before writing to cdk.json.
- You MUST NOT write VPC/subnet/SG values to cdk.json until the user has explicitly
  confirmed their choice. Show them what you will write and get a "yes" before
  proceeding.

### Step 0b: Validate network inputs and rewrite cdk.json

**Constraints:**

- You MUST verify, and report results to the user, the following BEFORE rewriting
  config, because each is a silent deploy-time or runtime failure if wrong:
  - The selected subnets do NOT route to an internet gateway. Run:

    ```bash
    aws ec2 describe-route-tables \
      --filters "Name=association.subnet-id,Values=<subnet-id-1>,<subnet-id-2>" \
      --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[GatewayId]' --output text
    ```

    If no explicit association exists for a subnet, also check the VPC's main route
    table:

    ```bash
    aws ec2 describe-route-tables \
      --filters "Name=vpc-id,Values=<vpcId>" "Name=association.main,Values=true" \
      --query 'RouteTables[*].Routes[?DestinationCidrBlock==`0.0.0.0/0`].[GatewayId]' --output text
    ```

    If any result starts with `igw-`, REJECT and tell the user: "Subnet `<id>` has a
    default route to an internet gateway (igw-...). This stack does not support public
    subnets — Fargate tasks deployed here would have no outbound network path. Please
    select subnets that route through a NAT gateway or VPC endpoints."
    You MUST NOT proceed to cdk.json rewrite if any selected subnet has an IGW route.
  - The supplied subnets are in availability zones `${REGION}a` and `${REGION}b`,
    because the stack hardcodes those AZs (`lib/infrastructure-stack.ts`).
  - The subnets have egress (NAT gateway or VPC endpoints), because the stack does
    NOT provision NAT. Tasks need outbound reach to the `atx ct` backend, ECR, S3,
    and Secrets Manager.
  - If the source is internal/self-hosted: a route exists from those subnets to the
    internal git host (VPN / Direct Connect / peering).
  - The security group's egress rules permit all of the above.
- You MUST NOT create NAT gateways, routes, VPNs, Direct Connect, or any other
  network infrastructure on the user's behalf, because these are production network
  changes with cost and blast-radius implications that require explicit human action.
  If a precondition is missing, You MUST surface it and hand it to the user or their
  network team.
- You MUST rewrite `$ATX_INFRA_DIR/cdk.json` `context` keys from the user's answers
  and You MUST show the diff before deploy:

  ```json
  "existingVpcId": "<existing_vpc_id>",
  "existingSubnetIds": ["<existing_subnet_ids...>"],
  "existingSecurityGroupId": "<existing_security_group_id>"
  ```

- You SHOULD leave `prebuiltImageUri` unchanged unless the user needs a runtime not
  in the pre-built image, because blanking it switches to the Docker-required custom
  image path.

### Step 0c: Hand off the deploy (admin-gated) — DO NOT run it yourself

**Constraints:**

- You MUST present the deploy command for the user to run, and You MUST NOT run it
  yourself, because the stack creates IAM roles and therefore requires admin /
  role-creation permissions the agent should not assume.
- You MUST include this caveat verbatim in intent: "This stack creates IAM roles, so
  deploying requires admin / role-creation permissions (`iam:CreateRole`,
  `iam:PutRolePolicy`, `iam:PassRole`, instance profiles). Run it with an admin
  identity. ReadOnly or runtime credentials are sufficient for everything afterward."
- You MUST present the command in in-session form so its output returns to the
  conversation:

  ```
  ! cd "$HOME/.aws/atx/custom/remote-infra" && ./setup.sh
  ```

- After deploy, You MUST direct the user to attach the executor policy
  (`$HOME/.aws/atx/custom/remote-infra/AWSTransformInfrastructureExecutorAccessBatch.json`)
  to their IAM role/user, so day-to-day job submission needs only least-privilege.
- You MUST stop the PROVISION lifecycle here and wait for the user to confirm the
  deploy succeeded before entering the OPERATE lifecycle.
- On success You SHOULD persist `{executionModel:"batch", stackName, region, source,
  byoNetwork}` to `.atx/context.json`, so a later session detects and reuses the stack.

## Step 1: Verify Source and Enumerate Repos

Before submitting jobs, confirm a source is registered locally (see [continuous-modernization-source.md](continuous-modernization-source.md)) and run discovery (see [continuous-modernization-discovery.md](continuous-modernization-discovery.md)) to get the list of repos. This determines what the container will analyze (Step 5).

First, list existing registered sources to show the customer what's available:

```bash
atx ct source list
```

Show the list to the customer and ask:

1. **Which source to analyze?** (pick from the list above)
2. **Source type:** GitHub, GitLab, or local
3. **Repos to analyze:** all repos in source, or a specific subset
4. **Analysis type:** `tech-debt-comprehensive`, `tech-debt-quick`, `security`, `agentic-readiness`, `modernization-readiness`

If the list is empty, the customer wants to register a new source, or needs to update the token on an existing source, use the [continuous-modernization-source](continuous-modernization-source.md) skill (`source add` for new, `source update` for existing), then return here.

Once the source is selected, run discovery and enumerate:

```bash
LOGICAL_SOURCE_NAME="<picked-source-name>"

# Run discovery
atx ct discovery scan --source "$LOGICAL_SOURCE_NAME"

# Enumerate the discovered repos
mapfile -t REPOS < <(atx ct repository list --source "$LOGICAL_SOURCE_NAME" --json | jq -r '.items[].full_name')
REPO_COUNT=${#REPOS[@]}
```

Works for all source providers (github, gitlab, local) — no provider-specific API calls. See [continuous-modernization-discovery](continuous-modernization-discovery.md) for scan details.

If the customer wants only a subset of repos, filter `${REPOS[@]}` before submitting.

## Step 2: Prep Credentials

Give the user the relevant command below to run in their own terminal — do not ask them to paste the token into this chat.

**GitHub HTTPS — store the PAT** (the container fetches it from Secrets Manager at job start):

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/github-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/github-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**GitHub SSH — store the private key:**

```bash
aws secretsmanager create-secret --name "atx/ssh-key" \
  --secret-string "$(cat <path-to-private-key>)" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/ssh-key" \
       --secret-string "$(cat <path-to-private-key>)"
```

**GitLab HTTPS — store the PAT** (separate secret, the container fetches it from Secrets Manager at job start):

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/gitlab-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/gitlab-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**Bitbucket — store the API token** (the container fetches it from Secrets Manager at job start). Email and username are injected into the container command directly (not secrets — they're non-sensitive identifiers):

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "atx/bitbucket-token" \
  --secret-string "$TOKEN" 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "atx/bitbucket-token" \
       --secret-string "$TOKEN"; }; unset TOKEN
```

**Private package registries** (if the analysis builds the project): see [custom-remote-execution#private-package-registries](custom-remote-execution.md#private-package-registries) for the `atx/credentials` JSON pattern.

## Step 2b: Validate Credentials (MANDATORY)

**MANDATORY**: The agent MUST verify that the required secret exists in Secrets Manager BEFORE proceeding to Step 4 (Confirm and Submit). Do NOT submit jobs without confirming the credential is present. If the secret is missing, give the user the command to run in their own terminal to create it (do not ask them to paste the token into this chat).

The required secret depends on the source provider:

| Provider      | Required Secret          |
| ------------- | ------------------------ |
| **github**    | `atx/github-token`       |
| **gitlab**    | `atx/gitlab-token`       |
| **bitbucket** | `atx/bitbucket-token`    |
| **local**     | (none — no token needed) |

**Step A — Check secret exists:**

```bash
# Replace <secret-name> with the provider-specific secret from the table above
aws secretsmanager describe-secret --secret-id <secret-name> --region <region> 2>&1
```

- If `ResourceNotFoundException` → inform the user that the secret is missing. Give them the command below to run in their own terminal (do not ask them to paste the token into this chat):

```bash
read -s TOKEN && { aws secretsmanager create-secret --name "<secret-name>" \
  --secret-string "$TOKEN" --region <region> 2>/dev/null \
  || aws secretsmanager put-secret-value --secret-id "<secret-name>" \
       --secret-string "$TOKEN" --region <region>; }; unset TOKEN
```

- If the secret exists → ask the customer: "Your `<secret-name>` token was last updated on `<LastChangedDate>`. Would you like to rotate it, or is the current token still valid?" If they want to rotate:

```bash
read -s TOKEN && aws secretsmanager put-secret-value --secret-id "<secret-name>" \
  --secret-string "$TOKEN" --region <region>; unset TOKEN
```

**Step B — Confirm SCM configuration with user (MANDATORY for non-local providers):**

Before submitting any batch job (analysis or remediation), ask the user to confirm the SCM provider config that will be injected into the container. An incorrect identifier, email, or username causes clone failures inside the container after the setup phase.

Present the config to the user via AskUserQuestion:

| Provider                                | Fields to confirm                                                                                                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **github**                              | `identifier` (GitHub org or username that owns the repos)                                                                                                                  |
| **gitlab**                              | `identifier` (GitLab group or username that owns the repos)                                                                                                                |
| **bitbucket cloud**                     | `identifier` (Bitbucket workspace), `email` (Atlassian account email for API auth), `username` (Bitbucket username for git clone — visible in clone URLs at bitbucket.org) |
| **bitbucket self-hosted (Data Center)** | `identifier` (Bitbucket project key), `base_url` (instance URL, e.g. `https://bitbucket.corp.example.com`)                                                                 |

Example confirmation prompt:

> "I'll use this config for the Batch job:
>
> - Provider: github
> - Identifier: `github-username`
>
> Is this correct?"

## Step 3: Prep Local Sources (local source only)

The single container needs all repos on disk. The skill zips ALL repos in the source as one bundle and uploads it to the managed source bucket:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ZIP_NAME="<source-name>-bundle"   # name the bundle (e.g., my-bundle)

# Zip all repos as siblings in one archive (preserves .git in each)
cd /path/to/repos
zip -qr "/tmp/${ZIP_NAME}.zip" */ -x '*/node_modules/*'
aws s3 cp "/tmp/${ZIP_NAME}.zip" "s3://atx-source-code-${ACCOUNT_ID}/repos/${ZIP_NAME}.zip"
rm -f "/tmp/${ZIP_NAME}.zip"
```

> **Important:** The zip MUST include each repo's `.git/` directory. atx ct's local-provider discovery scanner identifies repos by the presence of `.git`. If the customer pre-emptively excludes `.git`, the scan finds zero repos and analysis fails with `Available: (none)`.

The skill runs this on the customer's machine. GitHub and GitLab sources don't need this step — the container clones directly from the source provider via PAT.

## Step 3b: Security Analysis Prerequisites (security type only)

When `ANALYSIS_TYPE` is `security`, verify the security agent is configured before submitting:

1. Verify `~/.atxct/shared/security_agent_config.json` exists locally (created during security agent setup via `atx ct analysis configure-security`). If missing, the customer must run security agent setup first.

Skip this step for non-security analysis types.

## Step 4: Confirm and Submit

**Gate checks** (only the checks relevant to the source provider must pass):

| Check                                                         | github             | gitlab             | bitbucket cloud               | bitbucket self-hosted | local |
| ------------------------------------------------------------- | ------------------ | ------------------ | ----------------------------- | --------------------- | ----- |
| **Credentials (Step 2b-A):** secret exists in Secrets Manager | `atx/github-token` | `atx/gitlab-token` | `atx/bitbucket-token`         | `atx/bitbucket-token` | skip  |
| **SCM config (Step 2b-B):** confirmed with user               | identifier         | identifier         | identifier + email + username | identifier + base_url | skip  |

Tell the customer what will happen and wait for explicit confirmation. The exact prompt depends on provider:

**For GitHub:**

> "I'll submit a Batch job to run `<analysis-type>` on Fargate against your GitHub source `<source-name>`. The container will:
>
> - Place your GitHub PAT (from Secrets Manager `atx/github-token`) — your existing source `<source-name>` is preserved (no new source created)
> - Run `atx ct analysis run --source <source-name>` — atx ct will clone each repo and analyze it
>
> Continue?"

**For GitLab:**

> "I'll submit a Batch job to run `<analysis-type>` on Fargate against your GitLab source `<source-name>`. The container will:
>
> - Place your GitLab PAT (from Secrets Manager `atx/gitlab-token`) — your existing source `<source-name>` is preserved (no new source created)
> - Run `atx ct analysis run --source <source-name>` — atx ct will clone each repo and analyze it
>
> Continue?"

**For Bitbucket Cloud:**

> "I'll submit a Batch job to run `<analysis-type>` on Fargate against your Bitbucket source `<source-name>`. The container will:
>
> - Place your Bitbucket API token (from Secrets Manager `atx/bitbucket-token`) and inject email/username into config.json
> - Run `atx ct analysis run --source <source-name>` — atx ct will clone each repo and analyze it
>
> Continue?"

**For Bitbucket Data Center:**

> "I'll submit a Batch job to run `<analysis-type>` on Fargate against your Bitbucket Data Center source `<source-name>`. The container will:
>
> - Place your HTTP Access Token (from Secrets Manager `atx/bitbucket-token`) and inject base_url into config.json
> - Run `atx ct analysis run --source <source-name>` — atx ct will clone each repo and analyze it
>
> Continue?"

**For Local:**

> "I'll zip your repos at `<path>` (with `.git` included) into a single bundle and upload to `s3://atx-source-code-${ACCOUNT_ID}/repos/<bundle-name>.zip`, then submit a Batch job to run `<analysis-type>` on Fargate. The container will:
>
> - Download + unzip the bundle
> - Register a new local source named `<source-name>` in the backend (pointing at the container's `/home/atxuser/repos`)
> - Run discovery to enumerate the repos
> - Run `atx ct analysis run --source <source-name>` — atx ct analyzes all repos
> - Upload artifacts to `s3://atx-ct-output-${ACCOUNT_ID}/<analysis-id>/<source>::<repo>/code.zip`
>
> Continue?"

Do NOT submit until the customer confirms.

## Step 5: Submit Per-Repo Batch Jobs

Build one entry per repo and invoke `atx-trigger-batch-jobs`. The Lambda has strict input validation — to pass it, the per-job command must:

- Start with an allowed prefix (`atx ct` or `atx custom def *`)
- Contain no `$VAR` references, no `$(...)` command substitution, no `${VAR}` brace expansion, no `()` subshells, no `{}` braces, no `*` glob, no `^` regex anchor, no backticks, no `-c` flag (e.g., `sh -c '...'`)
- Contain only ASCII characters — no em-dash `—`, en-dash `–`, smart quotes `""` `''`, or any other Unicode (these get rejected by the Lambda's character allowlist)
- Be on a single line (no `\\` continuations, since post-`tr` they become literal escape-space characters)

The skill therefore substitutes ALL variables (account ID, source name, repo name, etc.) into the command string locally, before submission. Runtime values that aren't known until the container runs (e.g., the analysis ID printed by `atx ct analysis run`) are extracted into temp files and fed to subsequent commands via `xargs -I VAR command VAR ...`.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BATCH_NAME="atxct-$(date +%s)"
ANALYSIS_TYPE="<analysis-type>"      # tech-debt-quick | tech-debt-comprehensive | security | agentic-readiness | modernization-readiness | custom
AGENT="<AGENT>"  # AI assistant name (kiro, claude, amazonq, etc.)
LOGICAL_SOURCE_NAME="<source-name>"  # the source already registered with atx ct (used as-is)
GITHUB_ORG="<org>"                   # github source only -- used to build config.json for remediation chains
GITLAB_GROUP="<group>"               # gitlab source only -- used to build config.json for remediation chains
BITBUCKET_WORKSPACE="<workspace>"    # bitbucket source only -- workspace (Cloud) or project key (DC)
BITBUCKET_EMAIL="<email>"            # bitbucket cloud only -- email for API auth
BITBUCKET_USERNAME="<username>"      # bitbucket cloud only -- username for git clone/push
BITBUCKET_BASE_URL=""                # bitbucket DC only -- e.g. https://bitbucket.corp.example.com (empty for Cloud)
ZIP_NAME="<zip-bundle-name>"         # local source only -- name of the bundle uploaded in Step 3

# Security analysis only -- base64-encode the security agent config for injection.
# Not a secret (contains resource identifiers only), so no Secrets Manager needed.
SEC_CONFIG_B64=""
if [[ "${ANALYSIS_TYPE}" == "security" ]]; then
  SEC_CONFIG_B64=$(base64 < ~/.atxct/shared/security_agent_config.json | tr -d '\n')
fi

# Upload script -- /app/upload-ct-artifacts.sh is baked into the container image.
# It iterates analysis.repos[] (or remediation.repos.keys[]), zips each repo's
# working directory, and uploads to s3://<bucket>/<id>/<source>::<repo>/code.zip.
# Auto-detects analysis vs remediation, resolves per-provider repo path.

# Helper: security config injection snippet. Returns the command fragment to inject
# security_agent_config.json into the container when ANALYSIS_TYPE is "security".
# Empty string for non-security types.
sec_config_inject() {
  if [[ -n "${SEC_CONFIG_B64}" ]]; then
    echo " && mkdir -p /home/atxuser/.atxct/shared && echo ${SEC_CONFIG_B64} | base64 -d > /home/atxuser/.atxct/shared/security_agent_config.json"
  fi
}

# GitHub source (analysis) -- inject token (no source-add, no discovery), then run analysis.
# Source must be pre-registered locally by the customer (Step 1 verifies this).
# atx ct internally clones each repo as needed. Analysis details: see [continuous-modernization-analysis.md](continuous-modernization-analysis.md).
# Server log is written to ~/.aws/atx/logs/server.log so it gets included in the upload zip for debugging.
build_command_github() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/github-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/github_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --wait --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log${upload}"
}

# GitLab source (analysis) -- same injection pattern as GitHub, just different secret/file names.
# atx ct's async provider resolution queries the backend for the source's provider type,
# so we don't need source-add or config.json injection in the container -- the locally-registered
# source's metadata (provider=gitlab, base_url, identifier) is fetched at clone time.
build_command_gitlab() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/gitlab-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/gitlab_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --wait --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log${upload}"
}

# Bitbucket source (analysis) -- inject token + config.json with email/username (Cloud) or base_url (DC).
# atx ct's async provider resolution queries the backend for the source's provider type.
# Cloud needs email (API auth) and username (git auth). DC needs base_url only.
build_command_bitbucket() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local config_json
  if [[ -n "${BITBUCKET_BASE_URL}" ]]; then
    # Data Center: provider_config has base_url
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
  else
    # Cloud: provider_config has email and username
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
  fi
  local CONFIG_B64=$(echo "${config_json}" | base64)
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --wait --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log${upload}"
}

# Local source -- sync repo bundle from atx-source-code, unzip, source-add + discovery, run analysis.
# The bundle is a single zip containing all repos as subdirectories (zipped in Step 3).
# Source semantics: see [continuous-modernization-source.md](continuous-modernization-source.md). Discovery: see [continuous-modernization-discovery.md](continuous-modernization-discovery.md). Analysis: see [continuous-modernization-analysis.md](continuous-modernization-analysis.md).
build_command_local() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/repos && aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/repos/${ZIP_NAME}.zip /tmp/${ZIP_NAME}.zip && unzip -q /tmp/${ZIP_NAME}.zip -d /home/atxuser/repos/ && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} --path /home/atxuser/repos${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --wait --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log${upload}"
}

# Single container per submission. Source-level analysis runs on ALL repos in the source
# (atx ct internally parallelizes repos within the container).
CMD=$(build_command_local)   # or build_command_github, build_command_gitlab, build_command_bitbucket
JOB_NAME="atxct-${BATCH_NAME}"
JOBS_JSON=$(jq -nc --arg cmd "$CMD" --arg name "$JOB_NAME" '[{command: $cmd, jobName: $name}]')
PAYLOAD=$(jq -nc --arg bn "$BATCH_NAME" --argjson jobs "$JOBS_JSON" '{batchName: $bn, jobs: $jobs}')

aws lambda invoke --function-name atx-trigger-batch-jobs \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

The Lambda returns a `batchId`. Track it for status polling (Step 6).

### Security analysis: automatic concurrency enforcement

**When `ANALYSIS_TYPE` is `security`, jobs are automatically routed to a dedicated job queue (`atx-security-job-queue`)** backed by a compute environment capped at 5 concurrent tasks (`maxvCpus = 5 * fargateVcpu`). This means:

- Submit ALL security jobs in a single batch — no chunking, no polling, no terminal blocking
- AWS Batch queues them and only runs 5 at a time
- As one completes, the next in queue starts immediately (no wasted slots)
- The Security Agent's concurrency limit is respected at the infrastructure level

The Lambda detects security jobs by checking if the command contains `--type security` and routes them to `atx-security-job-queue` automatically. No special handling needed in the submission script.

**This automatic routing applies only to security analysis.** For all other analysis types (tech-debt-quick, tech-debt-comprehensive, agentic-readiness, modernization-readiness), jobs go to the general queue with the full 128-job concurrency.

### Submission patterns

The Lambda's `jobs: [...]` array supports up to 128 jobs per batch. Jobs in a batch run **in parallel** (no `dependsOn` between them — all dispatch simultaneously, scheduled by AWS Batch as queue capacity allows). Pick the pattern that matches the workload:

| Pattern                                              | When to use                                                                                                                                                                                               | Jobs per batch                                     |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| **A. Single analysis on one source** (default above) | One source, one analysis type. Parallelism comes from atx ct's internal handling of repos within the container.                                                                                           | 1                                                  |
| **B. Multiple analysis types on one source**         | E.g., quick + comprehensive on the same repos. Findings persist independently with their own analysis_id, queryable separately.                                                                           | N (one per type)                                   |
| **C. Multiple sources in one batch**                 | E.g., team-A's github source + team-B's gitlab source. Each source gets its own container with its own logical source name and credentials.                                                               | N (one per source, or one per source × type combo) |
| **D. Per-repo parallel analysis**                    | Customer wants maximum parallelism — one container per repo. Each container analyzes a single repo via `--repo`. Useful when repos are large or the customer wants per-repo isolation/failure boundaries. | N (one per repo)                                   |

**Pattern B example** — quick + comprehensive on the same source, parallel containers:

```bash
ANALYSIS_TYPE="tech-debt-quick"
JOB1_CMD=$(build_command_github)

ANALYSIS_TYPE="tech-debt-comprehensive"
JOB2_CMD=$(build_command_github)

JOBS_JSON=$(jq -nc \
  --arg cmd1 "$JOB1_CMD" --arg name1 "atxct-quick-${BATCH_NAME}" \
  --arg cmd2 "$JOB2_CMD" --arg name2 "atxct-comp-${BATCH_NAME}" \
  '[
    {command: $cmd1, jobName: $name1},
    {command: $cmd2, jobName: $name2}
  ]')
PAYLOAD=$(jq -nc --arg bn "$BATCH_NAME" --argjson jobs "$JOBS_JSON" '{batchName: $bn, jobs: $jobs}')

aws lambda invoke --function-name atx-trigger-batch-jobs \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

**Pattern C example** — different sources (and providers) in parallel:

```bash
LOGICAL_SOURCE_NAME="team-a-github"
JOB1_CMD=$(build_command_github)

LOGICAL_SOURCE_NAME="team-b-gitlab"
JOB2_CMD=$(build_command_gitlab)

JOBS_JSON=$(jq -nc \
  --arg cmd1 "$JOB1_CMD" --arg name1 "atxct-team-a-${BATCH_NAME}" \
  --arg cmd2 "$JOB2_CMD" --arg name2 "atxct-team-b-${BATCH_NAME}" \
  '[
    {command: $cmd1, jobName: $name1},
    {command: $cmd2, jobName: $name2}
  ]')
PAYLOAD=$(jq -nc --arg bn "$BATCH_NAME" --argjson jobs "$JOBS_JSON" '{batchName: $bn, jobs: $jobs}')

aws lambda invoke --function-name atx-trigger-batch-jobs \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

**Pattern D** — per-repo parallel analysis (one container per repo):

The `--repo` flag requires the repo's `slug` value from `atx ct repository list`. Always run `atx ct repository list --source <source> --json` and use the `.slug` field (format: `<source>::<repo_name>`).

Per-repo build command variants — same as the source-level builders but insert `--repo <slug>` before `--wait`:

```bash
# GitHub source (per-repo analysis) -- one container per repo for maximum parallelism.
# repoSlug must be set before calling (from `atx ct repository list --json | jq -r '.items[].slug'`).
build_command_github_per_repo() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/github-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/github_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --repo ${repoSlug} --wait 2>&1 | tee /tmp/run.log${upload}"
}

# GitLab source (per-repo analysis)
build_command_gitlab_per_repo() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && aws secretsmanager get-secret-value --secret-id atx/gitlab-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/gitlab_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --repo ${repoSlug} --wait 2>&1 | tee /tmp/run.log${upload}"
}

# Bitbucket source (per-repo analysis)
build_command_bitbucket_per_repo() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local config_json
  if [[ -n "${BITBUCKET_BASE_URL}" ]]; then
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
  else
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
  fi
  local CONFIG_B64=$(echo "${config_json}" | base64)
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --repo ${repoSlug} --wait 2>&1 | tee /tmp/run.log${upload}"
}

# Local source (per-repo analysis)
build_command_local_per_repo() {
  local upload=""
  if [[ "${ANALYSIS_TYPE}" != "tech-debt-quick" ]]; then
    upload=" && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 | xargs -I AID /app/upload-ct-artifacts.sh AID atx-ct-output-${ACCOUNT_ID}"
  fi
  local sec_inject=$(sec_config_inject)
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/repos && aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/repos/${ZIP_NAME}.zip /tmp/${ZIP_NAME}.zip && unzip -q /tmp/${ZIP_NAME}.zip -d /home/atxuser/repos/ && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} --path /home/atxuser/repos${sec_inject} && atx ct analysis run --type ${ANALYSIS_TYPE} --source ${LOGICAL_SOURCE_NAME} --repo ${repoSlug} --wait 2>&1 | tee /tmp/run.log${upload}"
}
```

**Pattern D usage** — iterate repos and build per-repo jobs:

```bash
JOBS="[]"
while IFS= read -r REPO; do
  [ -z "$REPO" ] && continue
  repoSlug="$REPO"
  REPO_SLUG=$(echo "$REPO" | tr '/:' '-')
  CMD=$(build_command_github_per_repo)   # or _gitlab_per_repo, _bitbucket_per_repo, _local_per_repo
  JOBS=$(echo "$JOBS" | jq --arg cmd "$CMD" --arg name "$REPO_SLUG" '. + [{command: $cmd, jobName: $name}]')
done <<< "$REPOS"

PAYLOAD=$(jq -nc --arg bn "$BATCH_NAME" --argjson jobs "$JOBS" '{batchName: $bn, jobs: $jobs}')

aws lambda invoke --function-name atx-trigger-batch-jobs \
  --payload "$PAYLOAD" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

**Why each piece is shaped this way:**

| Concern                                               | How addressed                                                                                                                                                                                                                                   |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lambda allowlist requires `atx ...` prefix            | Command starts with `atx ct --version > /dev/null 2>&1 ;` (allowlist token; exit code intentionally suppressed)                                                                                                                                 |
| Image's `atx ct` is pre-baked                         | The container image `public.ecr.aws/d9h8z6l7/aws-transform:latest` ships with the production CLI pre-installed; no runtime install step is required. If the image lacks the CLI, the job fails fast with `command not found` and exit code 127. |
| atx ct 3.1+ requires Node 22                          | `source nvm.sh && nvm use 22` switches Node version                                                                                                                                                                                             |
| Env from background subshell doesn't reach foreground | PATH + nvm setup in foreground BEFORE backgrounding the server                                                                                                                                                                                  |
| Server needs to be up before commands                 | `atx ct server > /tmp/server.log 2>&1 &` then `sleep 15`                                                                                                                                                                                        |
| AID capture without `$()`                             | `atx ct analysis run 2>&1 \| tee /tmp/run.log` then `grep ... \| xargs -I AID`                                                                                                                                                                  |
| Per-repo scoping                                      | Use `--repo <slug>` (singular). Do NOT use `--repos` (does not exist). The slug comes from `atx ct repository list --json \| jq -r '.items[].slug'` (format: `<source>::<repo_name>`).                                                          |
| Customer's source name preserved (no per-repo suffix) | GitHub/GitLab: token-file injection bypasses `source add`'s backend conflict. Local: `discovery scan --path` overrides the path on the existing source without conflicting (idempotent across runs).                                            |
| Re-running batch on the same source                   | Local provider: `discovery scan --path` updates the registered source's path without 409 errors. GitHub/GitLab: token injection has no equivalent conflict — works every run.                                                                   |

**Container's IAM role (`ATXBatchJobRole`)** auto-provides credentials for `aws s3 cp`, `aws secretsmanager get-secret-value`, and `atx ct` backend calls. Defined in the Custom CDK stack (`lib/infrastructure-stack.ts`) — no per-job credential setup needed.

**MCP configuration (optional):** If the customer has a local MCP config (`~/.aws/atx/mcp.json`), include it on each job:

```bash
MCP_CONFIG=$(cat ~/.aws/atx/mcp.json 2>/dev/null || echo "null")
# Add "mcpConfig": $MCP_CONFIG to each job entry above
```

### Remediation jobs (instead of analysis)

**Gate check**: Before submitting any remediation batch job, the agent MUST confirm that Step 2b was completed for the relevant provider (see gate checks table in Step 4). Local providers skip credentials and SCM config checks.

To run a remediation that fixes findings produced by a prior analysis, swap the `analysis run` block for `remediation create --ids` (see [continuous-modernization-remediation.md](continuous-modernization-remediation.md) and [continuous-modernization-findings.md](continuous-modernization-findings.md)).

The remediation flow differs by source provider:

| Provider      | Pattern                                                                               | Output                                               |
| ------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| **github**    | NO `--local` — backend pushes to a result branch                                      | Result branch pushed to source repo and PR is opened |
| **gitlab**    | NO `--local` — backend pushes to a result branch                                      | Result branch pushed to source repo and MR is opened |
| **bitbucket** | NO `--local` — backend pushes to a result branch                                      | Result branch pushed to source repo and PR is opened |
| **local**     | `--local` (required) — transform runs in the container, working dir is captured to S3 | `code.zip` per repo in S3                            |

We poll until terminal status (`complete`, `failed`, or `cancelled`). Use `while true` (no iteration cap) — AWS Batch's job timeout is the upper safety net.

### Three remediation flag combinations

`atx ct remediation create` accepts three valid flag combinations. Pick based on whether findings have `.fix` populated:

| Combination                        | When to use                                                                                                                                                                             | Capture pattern                                                                      |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `--ids X` (alone)                  | Findings have `.fix` populated (typical for `tech-debt-quick`). Backend uses each finding's `.fix.transform_name` to pick the transformation.                                           | `jq -r '.[] \| select(.fix != null) \| .id'`                                         |
| `--ids X --transformation-name Y`  | Findings WITHOUT `.fix` (typical for `tech-debt-comprehensive`, `security` issues without auto-fix). Customer overrides with an explicit transformation that applies to those findings. | `jq -r '.[] \| select(.category == "Java") \| .id'` (filter by category, not `.fix`) |
| `--transformation-name Y --repo Z` | No findings dependency. Run a transformation directly on a specific repo.                                                                                                               | (no findings capture)                                                                |

Set `TRANSFORMATION_NAME` to use the override; leave it empty to rely on each finding's `.fix`.

```bash
# On customer's laptop: collect finding IDs to remediate

# Pattern 1 (default): all auto-remediable findings (.fix populated)
FINDING_IDS=$(atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json \
  | jq -r '.[] | select(.fix != null) | .id' \
  | tr '\n' ',' | sed 's/,$//')
TRANSFORMATION_NAME=""

# Pattern 2 (hybrid): specific category of findings + explicit transformation override
# Example: all Java-category findings, regardless of .fix populated. Apply java-version-upgrade.
# FINDING_IDS=$(atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json \
#   | jq -r '.[] | select(.category == "Java") | .id' \
#   | tr '\n' ',' | sed 's/,$//')
# TRANSFORMATION_NAME="AWS/java-version-upgrade"

# Or filter by severity / repo / specific finding IDs

REMEDIATION_NAME="multi-fix-$(date +%s)"   # unique per submission

# GitHub source (remediation) -- no --local, no upload. Backend dispatches a GitHub Actions
# workflow that runs the transform and pushes a result branch to the source repo.
# The customer reviews and opens a PR in github.
#
# WORKAROUND: atx ct discovery scan throws SETUP_REQUIRED for github sources when local
# config.json is missing -- even when the github_token file is present.
# We inject a minimal config.json via base64 to satisfy the local-config check.
build_command_remediation_github() {
  local CONFIG_B64=$(printf '{"provider":"github","identifier":"%s"}' "${GITHUB_ORG}" | base64)
  # Optional transformation override (for findings without .fix populated, e.g. tech-debt-comprehensive)
  local TRANSFORM_FLAG=""
  [ -n "${TRANSFORMATION_NAME}" ] && TRANSFORM_FLAG="--transformation-name ${TRANSFORMATION_NAME} "
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/github-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/github_token && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} && atx ct remediation create --ids ${FINDING_IDS} ${TRANSFORM_FLAG}--name ${REMEDIATION_NAME} --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 > /tmp/rid.txt && while true ; do cat /tmp/rid.txt | xargs -I RID atx ct remediation status --id RID > /tmp/status.txt ; grep -qE 'complete|completed|failed|cancelled' /tmp/status.txt && break ; sleep 30 ; done"
}

# GitLab source (remediation) -- same as github with gitlab_token. Backend pushes to a
# result branch and MR is opened.
# Same SETUP_REQUIRED workaround as github -- minimal config.json injected via base64.
build_command_remediation_gitlab() {
  local CONFIG_B64=$(printf '{"provider":"gitlab","identifier":"%s"}' "${GITLAB_GROUP}" | base64)
  # Optional transformation override (for findings without .fix populated, e.g. tech-debt-comprehensive)
  local TRANSFORM_FLAG=""
  [ -n "${TRANSFORMATION_NAME}" ] && TRANSFORM_FLAG="--transformation-name ${TRANSFORMATION_NAME} "
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/gitlab-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/gitlab_token && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} && atx ct remediation create --ids ${FINDING_IDS} ${TRANSFORM_FLAG}--name ${REMEDIATION_NAME} --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 > /tmp/rid.txt && while true ; do cat /tmp/rid.txt | xargs -I RID atx ct remediation status --id RID > /tmp/status.txt ; grep -qE 'complete|completed|failed|cancelled' /tmp/status.txt && break ; sleep 30 ; done"
}

# Bitbucket source (remediation) -- inject token + config.json, run remediation.
# Same pattern as github/gitlab -- config.json injected via base64.
# Cloud: email + username in provider_config. DC: base_url in provider_config.
build_command_remediation_bitbucket() {
  local config_json
  if [[ -n "${BITBUCKET_BASE_URL}" ]]; then
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"base_url":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_BASE_URL}")
  else
    config_json=$(printf '{"provider":"bitbucket","identifier":"%s","provider_config":{"email":"%s","username":"%s"}}' "${BITBUCKET_WORKSPACE}" "${BITBUCKET_EMAIL}" "${BITBUCKET_USERNAME}")
  fi
  local CONFIG_B64=$(echo "${config_json}" | base64)
  # Optional transformation override (for findings without .fix populated, e.g. tech-debt-comprehensive)
  local TRANSFORM_FLAG=""
  [ -n "${TRANSFORMATION_NAME}" ] && TRANSFORM_FLAG="--transformation-name ${TRANSFORMATION_NAME} "
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME} && echo ${CONFIG_B64} | base64 -d > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/config.json && aws secretsmanager get-secret-value --secret-id atx/bitbucket-token --query SecretString --output text > /home/atxuser/.atxct/sources/${LOGICAL_SOURCE_NAME}/bitbucket_token && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} && atx ct remediation create --ids ${FINDING_IDS} ${TRANSFORM_FLAG}--name ${REMEDIATION_NAME} --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 > /tmp/rid.txt && while true ; do cat /tmp/rid.txt | xargs -I RID atx ct remediation status --id RID > /tmp/status.txt ; grep -qE 'complete|completed|failed|cancelled' /tmp/status.txt && break ; sleep 30 ; done"
}

# Local source (remediation) -- `--local` runs the transform in the container; results are
# zipped from the container's working dir and uploaded to S3.
build_command_remediation_local() {
  # Optional transformation override (for findings without .fix populated, e.g. tech-debt-comprehensive)
  local TRANSFORM_FLAG=""
  [ -n "${TRANSFORMATION_NAME}" ] && TRANSFORM_FLAG="--transformation-name ${TRANSFORMATION_NAME} "
  echo "atx ct --version > /dev/null 2>&1 ; set -o pipefail && source /home/atxuser/.bashrc && export PATH=/home/atxuser/.local/bin:/usr/local/bin:/usr/bin:/bin && source /home/atxuser/.nvm/nvm.sh && nvm use 22 ; mkdir -p /home/atxuser/.aws/atx/logs ; atx ct server > /home/atxuser/.aws/atx/logs/server.log 2>&1 & sleep 15 ; mkdir -p /home/atxuser/repos && aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/repos/${ZIP_NAME}.zip /tmp/${ZIP_NAME}.zip && unzip -q /tmp/${ZIP_NAME}.zip -d /home/atxuser/repos/ && atx ct discovery scan --source ${LOGICAL_SOURCE_NAME} --path /home/atxuser/repos && atx ct remediation create --ids ${FINDING_IDS} ${TRANSFORM_FLAG}--name ${REMEDIATION_NAME} --local --telemetry \"agent=${AGENT},executionMode=fargate\" 2>&1 | tee /tmp/run.log && grep -oE '01[A-Z0-9]+' /tmp/run.log | head -1 > /tmp/rid.txt && while true ; do cat /tmp/rid.txt | xargs -I RID atx ct remediation status --id RID > /tmp/status.txt ; grep -qE 'complete|completed|failed|cancelled' /tmp/status.txt && break ; sleep 30 ; done && cat /tmp/rid.txt | xargs -I RID /app/upload-ct-artifacts.sh RID atx-ct-output-${ACCOUNT_ID}"
}
```

Then call `build_command_remediation_github`, `build_command_remediation_gitlab`, `build_command_remediation_bitbucket`, or `build_command_remediation_local` instead of the analysis builder. Everything else (Lambda invoke, polling, status retrieval) is identical to analysis.

**Why `while true` instead of a bounded loop:**

| Concern                                             | Resolution                                                                         |
| --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Remediation duration is unpredictable               | No iteration cap — poll until terminal status                                      |
| Container could hang forever on a stuck remediation | AWS Batch's Job Definition timeout (default 12h, configurable) is the upper bound  |
| Customer wants to cancel                            | `aws batch terminate-job` from outside; or `atx ct remediation cancel` server-side |

The container exits ONLY when:

1. Status reaches `complete`/`failed`/`cancelled` → upload runs (local only) → exit 0
2. Batch hits its job timeout → forced kill → exit non-zero (no upload)

Keep your Job Definition timeout generous for remediation jobs.

## Step 6: Poll Status

Poll every 60 seconds for the first 10 polls, then every 5 minutes. Report only on status changes.

```bash
aws lambda invoke --function-name atx-get-batch-status \
  --payload "{\"batchId\":\"${BATCH_ID}\"}" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

Job statuses: `SUBMITTED`, `PENDING`, `RUNNABLE`, `STARTING`, `RUNNING`, `SUCCEEDED`, `FAILED`.

## Step 7: Get Findings and Artifacts

**Findings** are persisted by the analysis runner during execution and queryable via:

```bash
atx ct findings list --source <source-name> --json
```

All findings are persisted under the customer's `LOGICAL_SOURCE_NAME` (single container does the analysis). One query gets everything (see [continuous-modernization-findings.md](continuous-modernization-findings.md)):

```bash
atx ct findings list --source ${LOGICAL_SOURCE_NAME} --json
```

**S3 artifacts** are uploaded by `/app/upload-ct-artifacts.sh` (baked into the container image). Analysis artifacts are written for any provider; remediation artifacts are only written for `local`-provider remediations (github/gitlab remediations push a result branch instead — no S3):

```
s3://atx-ct-output-{account-id}/<analysis-id-or-remediation-id>/<repo-slug>/
  code.zip   -- the working directory after the analysis or remediation completes,
               including a result branch with auto-committed changes (e.g.,
               `atx-result-staging-<timestamp>` for analysis documentation, or the
               remediation's branch for `--local` runs). The customer can `git log`
               and `git diff` to review what the bot changed. `.git/` is preserved
               for this reason.
               Excludes node_modules/, .env*, *.pem, *.key, .aws/.
  logs.zip   -- cherry-picked debug logs:
               ATX CLI debug logs, error log, conversation transcript,
               plan.json, validation_summary.md.
```

To download:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# All artifacts for one analysis
aws s3 sync s3://atx-ct-output-${ACCOUNT_ID}/${ANALYSIS_ID}/ ./artifacts/

# Just one repo's reports
aws s3 cp s3://atx-ct-output-${ACCOUNT_ID}/${ANALYSIS_ID}/${REPO_SLUG}/code.zip ./
```

Surface findings to the user as the primary result. Reference S3 artifacts only if the user asks for raw reports/logs or you need to debug a finding.

**Cancellation note:** If a Batch job is terminated mid-run, the upload step does not run and that container's artifacts are lost. Findings already persisted survive (the analysis runner pushes them mid-flight, before the upload step).

## Cancellation

```bash
# Cancel one job
aws lambda invoke --function-name atx-terminate-job \
  --payload "{\"jobId\":\"<id>\"}" \
  --cli-binary-format raw-in-base64-out /dev/stdout

# Cancel all jobs in a batch
aws lambda invoke --function-name atx-terminate-batch-jobs \
  --payload "{\"batchId\":\"<batch-id>\"}" \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

## Container Customization

The Batch container is the pre-built `public.ecr.aws/d9h8z6l7/aws-transform:latest` image, which includes Java 8/11/17/21/25, Python 3.8-3.14, Node.js 16-24, Maven, Gradle, common build tools, AWS CLI v2, and the AWS Transform CLI (including `atx ct`) pre-installed. The JOB_COMMAND runs `atx ct --version` as a smoke test at job start — no runtime install step is required.

For continuous modernization analyses, the pre-built image's defaults handle every runtime need. No customization required.

If a customer brings their own TD that requires a runtime or tool not in the pre-built image (e.g., Rust, Go, .NET on Linux), follow the Custom Image Path in [custom-remote-execution](custom-remote-execution.md#custom-image-path-docker-required):

1. Clone the infrastructure repo (already done if Custom is set up)
2. Edit the Dockerfile to add the required runtime/tool — see [Adding Languages or Tools](custom-remote-execution.md#adding-languages-or-tools)
3. Re-run `./setup.sh` from the cloned directory

## Runtime Version Switching

For remediation runs that target a specific language version (e.g., `AWS/java-version-upgrade` targeting Java 21), pass the version as an environment variable on each job in the `jobs` array:

```json
{
  "command": "...",
  "jobName": "...",
  "environment": {
    "JAVA_VERSION": "21",
    "NODE_VERSION": "22",
    "PYTHON_VERSION": "3.13"
  }
}
```

Available versions:

- **Java**: 8, 11, 17, 21, 25 (Amazon Corretto)
- **Python**: 3.8-3.14 (accepts `3.13` or `13`)
- **Node.js**: 16, 18, 20, 22, 24

For analyses (tech-debt-comprehensive, agentic-readiness, modernization-readiness), runtime switching is generally not needed. Pass these env vars only when running remediation TDs that need a specific target version.

See [custom-remote-execution#version-switching-at-runtime](custom-remote-execution.md#version-switching-at-runtime) for the full reference.

## Limits

- Max 128 concurrent Batch jobs (per the existing CDK config)
- **Max 5 concurrent Batch jobs for `--type security` (infrastructure-enforced)** — the Security Agent backend caps concurrent code-review executions at 5. A dedicated compute environment (`atx-fargate-security`, `maxvCpus = 5 * fargateVcpu`) and job queue (`atx-security-job-queue`) enforce this at the AWS Batch level. The Lambda automatically routes security jobs to this queue — no client-side chunking needed. Submit all security jobs in one batch; AWS Batch queues excess jobs and runs them as slots free up.
- Max job duration: defined by the CDK stack
- Bedrock throughput is per-account — running many parallel continuous modernization containers shares the quota; large batches may throttle
- Backend (atx ct API) rate limits at ~30+ concurrent calls. Step 5's chunked-submit pattern (chunks of 8) keeps within limits

## Error Handling

| Error                                 | Cause                                                             | Fix                                                                                |
| ------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Job stuck in `RUNNABLE`               | No Fargate capacity                                               | Wait or check service quota                                                        |
| Job fails with auth error             | Task role missing Bedrock, SecurityAgent, or atx-ct-output access | Update task role; customer re-runs `setup.sh`                                      |
| Container can't fetch PAT             | `atx/github-token` (or `atx/gitlab-token`) secret missing         | Customer creates the secret (see Step 2)                                           |
| Container can't fetch SSH key         | `atx/ssh-key` secret missing                                      | Customer creates the secret (see Step 2)                                           |
| Container can't read local source zip | S3 path incorrect or zip not uploaded                             | Verify `s3://atx-source-code-${ACCOUNT_ID}/repos/<repo>.zip` exists                |
| `atx ct discovery scan` fails         | Source registration failed (bad PAT, bad path, etc.)              | Check container logs; fix credentials or path                                      |
| `atx ct analysis run` clone fails     | PAT expired, repo private to a different account, etc.            | Verify customer's PAT has access to the repo                                       |
| Findings missing after analysis       | Server crashed before persisting                                  | Check CloudWatch logs for errors                                                   |
| Artifacts missing from S3             | Upload script failed                                              | Check container logs for `[date] Uploaded` or `Skip` lines from the staging script |

## Pricing

Direct customer to:

- AWS Batch / Fargate pricing: https://aws.amazon.com/fargate/pricing/
- AWS Transform agent minutes: https://aws.amazon.com/transform/pricing/

Do NOT quote specific dollar amounts or time estimates.

## Cleanup

After every Batch run completes, prompt the user with the following:

> Your remote infrastructure is still deployed in your AWS account. All services
> are pay-per-use only — there are no fixed costs when idle. You can leave it in
> place for future analyses, or tear it down now.
>
> For pricing details: https://aws.amazon.com/transform/pricing/
>
> If you tear down:
>
> - All AWS Transform resources are completely removed from your account
> - KMS key deletion is scheduled
> - S3 buckets, secrets, IAM policies, log groups — all deleted
> - You'll need to re-run setup next time you use remote mode
>
> Would you like to keep the infrastructure or tear it down?

If the user chooses to tear down:

```bash
cd "$HOME/.aws/atx/custom/remote-infra" && ./teardown.sh
```

If the user chooses to keep it: "Infrastructure will stay deployed. Next time you run a remote analysis, everything will be ready immediately."
