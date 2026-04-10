---
name: bedrock-validate-model-access
description: "Validate IAM permissions and model access for Amazon Bedrock"
---

# Bedrock Model Access Validation

Verify that the developer's IAM permissions and model access are configured correctly.

## Required Permissions

Attach the **`AmazonBedrockLimitedAccess`** managed policy to the developer's IAM user or role. This covers `bedrock:InvokeModel`, `bedrock:ListFoundationModels`, and `bedrock:GetFoundationModel`. The Converse API requires `bedrock:InvokeModel` (not a separate IAM action).

For identity verification (`sts:GetCallerIdentity`), attach the supplemental policy from [iam-permissions.md](${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/iam-permissions.md).

## Step 1: Run Access Validation

Extract model and region from the developer's question. Build the model ID:

1. **Resolve the base model ID** from the natural name (e.g. "sonnet 4.6" → `anthropic.claude-sonnet-4-6`). If unsure of the exact model ID, search the AWS Docs MCP server for the current model ID.
2. **Select the cross-region prefix** based on the target region. Claude models **cannot** be invoked with the bare base model ID — `anthropic.claude-sonnet-4-6` will return `ResourceNotFoundException`. You must add a prefix:
   - US regions (`us-east-1`, `us-west-2`, etc.) → `us.` prefix
   - EU regions (`eu-west-1`, `eu-central-1`, etc.) → `eu.` prefix
   - AP regions (`ap-northeast-1`, `ap-southeast-1`, etc.) → `ap.` prefix
   - `global.` prefix works for all regions (~10% cost savings via global routing)
   - Amazon models (Nova, Titan) use bare model IDs with no prefix
3. **Combine**: `<prefix><base_model_id>` (e.g. `us.anthropic.claude-sonnet-4-6`)

Defaults: `us.anthropic.claude-sonnet-4-6` in `us-east-1`.

Always use the validation script — never improvise raw AWS CLI calls:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-bedrock-access.sh <MODEL_ID> <REGION> <PROFILE>
```

This checks:

1. AWS credentials are valid (`sts:GetCallerIdentity`)
2. Bedrock service is accessible (`bedrock:ListFoundationModels`)
3. Target model is available (`bedrock:GetFoundationModel`)
4. Inference permissions work (`bedrock:Converse`)

## Step 2: Diagnose Failures

If any check fails, load the relevant reference:

- Credentials invalid → help configure via `aws configure --profile <PROFILE>`
- Model not found → load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/model-access.md`
- Access denied → load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/iam-permissions.md`

## Step 3: Report

Summarize: pass/fail for each of the 4 checks, and specific fix instructions for any failures.
