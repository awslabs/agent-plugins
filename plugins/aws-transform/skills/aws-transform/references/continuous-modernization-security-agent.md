---
name: security-agent-setup
description: Set up and use the security agent for vulnerability scanning. Covers admin setup (manual terminal commands) and executor runtime (agent-driven analysis). Replaces the inline security agent steps in EC2/Batch execution skills.
---

# Security Agent Setup

This skill covers the security agent lifecycle with a clear split between **admin** (infrastructure provisioning) and **executor** (runtime analysis) roles.

## ⚠️ MANDATORY: Permission Consent (MUST be first interaction)

**CRITICAL: Before ANY security agent setup or analysis steps, present this consent message and wait for a response.**

"To run security analysis, the executor role needs access to: SecurityAgent APIs (for code review and findings), the security agent S3 bucket (for uploading source code to scan), and iam:PassRole for the security agent role. Do you have these permissions configured?"

- If the customer says **yes** → proceed with the executor flow.
- If the customer says **no** → respond with: "If you don't have sufficient permissions you may encounter errors during the flow. Your administrator can set up the required resources using the Admin Setup commands below." Then proceed with the workflow.

**Record the customer's response** -- if they later file a bug about permission errors, we refer to their choice here.

---

## Admin Setup (Manual Terminal Commands)

**These commands create IAM roles and deploy CloudFormation stacks, so they require admin/role-creation permissions (`iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole`, `cloudformation:CreateChangeSet`). Run them with an admin identity. Read-only or runtime credentials are enough for everything afterward.**

**The agent MUST NOT execute these commands using agentic tools. Instead, present them as instructions for the customer or their administrator to copy and run.**

The admin provisions the security agent infrastructure: an IAM role, a managed policy, and an S3 bucket, all deployed via a CloudFormation stack.

Tell the customer:

> "This deploys the security agent infrastructure (IAM role, S3 bucket, CloudFormation stack). It requires admin/role-creation permissions. Run it with an admin identity. Read-only or runtime credentials are enough for everything afterward."
>
> For reference, the executor policy this skill expects is in https://github.com/awslabs/agent-plugins/blob/main/plugins/aws-transform/skills/aws-transform/references/AWSTransformSecurityAgentExecutorAccess.json

```bash
# Ensure atx ct is installed and up to date
INSTALLED=$(atx ct --version 2>/dev/null | head -1)
LATEST=$(curl -fsSL "https://transform-cli.awsstatic.com/index.json" 2>/dev/null | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
echo "Installed: ${INSTALLED:-not found}, Latest: ${LATEST:-unknown}"

# If not installed or outdated:
curl -fsSL "https://transform-cli.awsstatic.com/install.sh" | bash
source ~/.bashrc

# Start the server if not running
atx ct server &
sleep 5

# Deploy security agent infrastructure (creates IAM role, S3 bucket, CloudFormation stack)
atx ct setup security-agent
```

### What Admin Setup Creates

| Resource             | Name Pattern                              | Purpose                                 |
| -------------------- | ----------------------------------------- | --------------------------------------- |
| CloudFormation stack | `kct-security-agent-<suffix>`             | Manages all resources atomically        |
| IAM role             | `security-agent-kct-agent-space-<suffix>` | Role the security agent service assumes |
| IAM managed policy   | `kct-security-agent-<suffix>`             | Permissions attached to the role        |
| S3 bucket            | `kct-security-agent-<suffix>`             | Stores source code zips for scanning    |

### Admin Setup for EC2/Batch Job Roles

When using security analysis on EC2 or Batch, the **admin** must also attach executor permissions to the compute role. Present these commands as instructions:

> "The compute role needs security agent permissions added. This modifies IAM policies, so it requires admin/role-creation permissions. Run these with an admin identity:"

**For Batch (ATXBatchJobRole):**

```bash
# Get security agent config values
SEC_BUCKET=$(jq -r '.s3Bucket' ~/.atxct/shared/security_agent_config.json)
SEC_AGENT_ROLE_ARN=$(jq -r '.role_arn // .roleArn' ~/.atxct/shared/security_agent_config.json)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Security Agent API access
aws iam put-role-policy --role-name ATXBatchJobRole \
  --policy-name AtxCtSecurityAgentAPI \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"securityagent:ListAgentSpaces\",\"securityagent:CreateAgentSpace\",\"securityagent:CreateCodeReview\",\"securityagent:StartCodeReviewJob\",\"securityagent:ListCodeReviewJobsForCodeReview\",\"securityagent:ListFindings\",\"securityagent:BatchGetFindings\",\"securityagent:StartCodeRemediation\"],\"Resource\":\"arn:aws:securityagent:*:*:agent-space*\",\"Condition\":{\"StringEquals\":{\"aws:ResourceAccount\":\"${ACCOUNT_ID}\"}}}]}"

# 2. S3 access for security agent bucket
aws iam put-role-policy --role-name ATXBatchJobRole \
  --policy-name AtxCtSecurityAgentS3Access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:PutObject\",\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::${SEC_BUCKET}\",\"arn:aws:s3:::${SEC_BUCKET}/*\"]}]}"

# 3. PassRole for security agent role
aws iam put-role-policy --role-name ATXBatchJobRole \
  --policy-name AtxCtSecurityAgentPassRole \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"iam:PassRole\",\"Resource\":\"${SEC_AGENT_ROLE_ARN}\",\"Condition\":{\"StringEquals\":{\"iam:PassedToService\":\"securityagent.amazonaws.com\"}}}]}"
```

**For EC2 (stack-managed role):**

```bash
SEC_BUCKET=$(jq -r '.s3Bucket' ~/.atxct/shared/security_agent_config.json)
SEC_AGENT_ROLE_ARN=$(jq -r '.role_arn // .roleArn' ~/.atxct/shared/security_agent_config.json)
STACK_NAME="<the-ec2-stack-name>"
REGION="${AWS_REGION:-us-east-1}"

ROLE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' --output text | awk -F/ '{print $NF}')

# 1. Security Agent API access
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name AtxCtSecurityAgentAPI \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"securityagent:ListAgentSpaces\",\"securityagent:CreateAgentSpace\",\"securityagent:CreateCodeReview\",\"securityagent:StartCodeReviewJob\",\"securityagent:ListCodeReviewJobsForCodeReview\",\"securityagent:ListFindings\",\"securityagent:BatchGetFindings\",\"securityagent:StartCodeRemediation\"],\"Resource\":\"arn:aws:securityagent:*:*:agent-space*\",\"Condition\":{\"StringEquals\":{\"aws:ResourceAccount\":\"${ACCOUNT_ID}\"}}}]}"

# 2. S3 access to the security agent bucket
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name AtxCtSecurityAgentS3Access \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:PutObject\",\"s3:GetObject\",\"s3:ListBucket\"],\"Resource\":[\"arn:aws:s3:::${SEC_BUCKET}\",\"arn:aws:s3:::${SEC_BUCKET}/*\"]}]}"

# 3. PassRole for security agent role
aws iam put-role-policy --role-name "$ROLE_NAME" \
  --policy-name AtxCtSecurityAgentPassRole \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"iam:PassRole\",\"Resource\":\"${SEC_AGENT_ROLE_ARN}\",\"Condition\":{\"StringEquals\":{\"iam:PassedToService\":\"securityagent.amazonaws.com\"}}}]}"
```

### Check Admin Setup Status

```bash
atx ct setup security-agent --status
```

Returns: `configured`, `setup_in_progress`, `failed`, or `not_configured`.

### Delete (Teardown)

```bash
atx ct setup security-agent --delete
```

---

## Executor Flow (Agent-Driven)

This is what the agent does at runtime after admin setup is complete. The agent MAY execute these steps using agentic tools.

### Step 1: Verify Security Agent is Configured

Check that the security agent config file exists:

```bash
cat ~/.atxct/shared/security_agent_config.json
```

**If the file does NOT exist**: Try to reconstruct it from the existing CloudFormation stack before asking the customer to re-run admin setup. This allows any team member with AWS account access to self-service without needing the original admin.

#### Reconstruct Config from Existing Stack

```bash
# Find the security agent stack (tagged during admin setup)
STACK_NAME=$(aws cloudformation describe-stacks \
  --query "Stacks[?Tags[?Key=='atx-remote-infra' && Value=='true']].StackName" \
  --output text --no-cli-pager --region us-east-1)

# If not found by tag, try prefix match
if [ -z "$STACK_NAME" ]; then
  STACK_NAME=$(aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query "StackSummaries[?starts_with(StackName,'kct-security-agent-')].StackName" \
    --output text --no-cli-pager --region us-east-1)
fi

echo "Found stack: ${STACK_NAME:-none}"
```

**If a stack is found**, extract the config and write it locally:

```bash
# Extract parameters and outputs from the stack
ACCOUNT_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Parameters[?ParameterKey=='AccountId'].ParameterValue" --output text --no-cli-pager)
AGENT_SPACE_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Parameters[?ParameterKey=='AgentSpaceName'].ParameterValue" --output text --no-cli-pager)
S3_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Parameters[?ParameterKey=='S3Resource'].ParameterValue" --output text --no-cli-pager)
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='RoleArn'].OutputValue" --output text --no-cli-pager)
AGENT_SPACE_ID=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-1 \
  --query "Stacks[0].Outputs[?OutputKey=='AgentSpaceId'].OutputValue" --output text --no-cli-pager)

# Write the config file
mkdir -p ~/.atxct/shared
cat > ~/.atxct/shared/security_agent_config.json << EOF
{
  "agentSpaceId": "${AGENT_SPACE_ID}",
  "agentSpaceName": "${AGENT_SPACE_NAME}",
  "s3Bucket": "${S3_BUCKET}",
  "roleArn": "${ROLE_ARN}",
  "accountId": "${ACCOUNT_ID}",
  "stackName": "${STACK_NAME}",
  "configuredAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
}
EOF

cat ~/.atxct/shared/security_agent_config.json
```

**If no stack is found**: Tell the customer:

> "Security agent is not configured and no existing stack was found in this account. An administrator needs to run the initial setup:"
>
> ```bash
> atx ct setup security-agent
> ```
>
> "Once complete, let me know and I'll continue."

Do NOT proceed until the config file exists.

### Step 2: Read Config Values

```bash
SEC_BUCKET=$(jq -r '.s3Bucket' ~/.atxct/shared/security_agent_config.json)
SEC_AGENT_ROLE_ARN=$(jq -r '.role_arn // .roleArn' ~/.atxct/shared/security_agent_config.json)
AGENT_SPACE_NAME=$(jq -r '.agentSpaceName' ~/.atxct/shared/security_agent_config.json)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Step 3: Verify Executor Permissions (Read-Only Check)

For EC2/Batch compute roles, verify the required inline policies exist:

```bash
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name AtxCtSecurityAgentAPI 2>&1
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name AtxCtSecurityAgentS3Access 2>&1
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name AtxCtSecurityAgentPassRole 2>&1
```

**If any returns `NoSuchEntity`**: Do NOT add the policy. Instead, tell the customer:

> "The compute role is missing security agent permissions. This requires admin/role-creation privileges to fix. Run the following with an admin identity:"

Then show the relevant commands from the Admin Setup section above.

### Step 4: Sync Config to Compute (EC2 only)

For EC2, sync the security agent config into the container(s):

```bash
aws s3 cp ~/.atxct/shared/security_agent_config.json \
  s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json

ssm_run "aws s3 cp s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json /tmp/sa.json && \
  for c in \$(sudo docker ps --filter name=atx-ct --format '{{.Names}}'); do \
    sudo docker cp /tmp/sa.json \$c:/home/atxuser/.atxct/shared/security_agent_config.json && \
    sudo docker exec \$c chown 1000:1000 /home/atxuser/.atxct/shared/security_agent_config.json; \
  done"

aws s3 rm s3://atx-source-code-${ACCOUNT_ID}/temp/security_agent_config.json
```

### Step 5: Proceed with Analysis

Once permissions are verified, proceed with the normal analysis flow using `--type security`.

The executor IAM policy required for runtime is documented in `AWSTransformSecurityAgentExecutorAccess.json` in the ATXControlTowerPolicies package.

---

## Error Handling

| Error                                      | Cause                                                  | Resolution                                   |
| ------------------------------------------ | ------------------------------------------------------ | -------------------------------------------- |
| `Access denied calling Security Agent API` | Missing `AtxCtSecurityAgentAPI` policy on compute role | Admin must add the policy (see Admin Setup)  |
| `s3:PutObject` access denied               | Missing `AtxCtSecurityAgentS3Access` policy            | Admin must add S3 policy                     |
| `iam:PassRole` denied                      | Missing `AtxCtSecurityAgentPassRole` policy            | Admin must add PassRole policy               |
| Config file not found                      | Admin setup never ran                                  | Admin must run `atx ct setup security-agent` |
| `not_configured` status                    | Setup failed or never completed                        | Admin must re-run setup                      |

---

## IAM Policy Reference

| Policy                | File                                           | Purpose                                                               | Who Uses It                       |
| --------------------- | ---------------------------------------------- | --------------------------------------------------------------------- | --------------------------------- |
| Full admin + executor | `AWSTransformSecurityAnalysisAccess.json`      | All permissions including CFN, CreateRole, CreateBucket               | Administrator (setup)             |
| Executor only         | `AWSTransformSecurityAgentExecutorAccess.json` | Runtime permissions only: SecurityAgent API, S3 read/upload, PassRole | Compute role (EC2/Batch job role) |
