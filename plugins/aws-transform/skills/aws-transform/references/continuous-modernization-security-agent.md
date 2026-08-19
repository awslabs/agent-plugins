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

The admin provisions the security agent infrastructure: an IAM role, a managed policy, an S3 bucket, and the agent space — all deployed via a single CloudFormation stack.

Tell the customer:

> "This deploys the security agent infrastructure (IAM role, S3 bucket, agent space, CloudFormation stack). It requires admin/role-creation permissions. Run it with an admin identity. Read-only or runtime credentials are enough for everything afterward."
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

# Deploy security agent infrastructure (single CFN deploy — creates IAM role, S3 bucket, agent space)
atx ct setup security-agent
```

### What Admin Setup Creates

| Resource             | Name Pattern                              | Purpose                                          |
| -------------------- | ----------------------------------------- | ------------------------------------------------ |
| CloudFormation stack | `AtxSecurityAgentStack-<suffix>`          | Manages all resources atomically (single deploy) |
| Agent space          | `atx-agent-space-<suffix>`                | The Security Agent workspace (CFN-managed)       |
| IAM role             | `security-agent-atx-agent-space-<suffix>` | Role the security agent service assumes          |
| IAM managed policy   | (inline in stack)                         | Permissions attached to the role                 |
| S3 bucket            | `atx-security-agent-<suffix>`             | Stores source code zips for scanning             |

### Remote Execution (EC2/Batch)

Security agent permissions for EC2 and Batch compute roles are **already included** in the CFN templates deployed by `atx ct remote provision`. No manual `put-role-policy` commands are needed — the BatchJobRole and EC2 TransformRole inline policies include `securityagent:*`, S3 access to the security agent bucket, and `iam:PassRole` for the security agent role.

### Check Admin Setup Status

```bash
atx ct setup security-agent --status
```

Returns: `configured` or `not_configured`.

### Delete (Teardown)

```bash
atx ct setup security-agent --delete
```

This deletes the CloudFormation stack and all resources it manages (agent space, role, bucket, policy).

### Migration from Legacy Setup

If the account has an old `kct-security-agent-*` stack (from a previous CLI version), the CLI will detect it and prompt:

> Delete it with: `aws cloudformation delete-stack --stack-name <legacy-stack-name>`
> Then re-run `atx ct setup security-agent` to provision the new stack.

---

## Executor Flow (Agent-Driven)

This is what the agent does at runtime after admin setup is complete. The agent MAY execute these steps using agentic tools.

### Step 1: Verify Security Agent is Configured

```bash
atx ct setup security-agent --status
```

- If `configured` → proceed to Step 2.
- If `not_configured` → tell the customer:

> "Security agent is not configured in this account. An administrator needs to run the initial setup:"
>
> ```bash
> atx ct setup security-agent
> ```
>
> "Once complete, let me know and I'll continue."

Do NOT proceed until status is `configured`.

### Step 2: Proceed with Analysis

Once setup is verified, proceed with the normal analysis flow using `--type security`. The CLI discovers the security agent configuration from CloudFormation at runtime — no manual config steps are needed.

```bash
atx ct analysis run --type security --sources <source-name>
```

The executor IAM policy required for runtime is documented in `AWSTransformSecurityAgentExecutorAccess.json` (included with this skill).

---

## Error Handling

| Error                                           | Cause                                         | Resolution                                                                                                                          |
| ----------------------------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `Access denied calling Security Agent API`      | Missing SecurityAgent permissions on the role | For local: attach `AWSTransformSecurityAgentExecutorAccess` policy. For remote: update the EC2/Batch stack (`atx ct remote update`) |
| `s3:PutObject` access denied on security bucket | S3 bucket permissions missing                 | Same as above — update stack or attach policy                                                                                       |
| `iam:PassRole` denied                           | Missing PassRole for securityagent service    | Same as above                                                                                                                       |
| `not_configured` status                         | Admin setup never ran or stack was deleted    | Admin must run `atx ct setup security-agent`                                                                                        |
| `Found a legacy "kct-security-agent-*" stack`   | Old stack from previous CLI version           | Delete the old stack, then re-run setup (see Migration section)                                                                     |

---

## IAM Policy Reference

| Policy                | File                                           | Purpose                                                                         | Who Uses It           |
| --------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------- | --------------------- |
| Full admin + executor | `AWSTransformSecurityAnalysisAccess.json`      | All permissions including CFN, CreateRole, CreateBucket                         | Administrator (setup) |
| Executor only         | `AWSTransformSecurityAgentExecutorAccess.json` | Runtime permissions: SecurityAgent API, S3 read/upload, PassRole, CFN discovery | Local executor role   |
| Compute (remote)      | (inline in CFN stack)                          | Same runtime permissions, baked into BatchJobRole / EC2 TransformRole           | EC2/Batch containers  |
