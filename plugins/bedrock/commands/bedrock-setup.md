---
name: bedrock-setup
description: "Interactive Bedrock onboarding: IAM, model access, prompt caching, and validation"
---

# Bedrock Setup

Guide the developer through a complete Amazon Bedrock setup. Follow these steps in order, confirming each before proceeding.

## Required Permissions

The full setup requires the **`AmazonBedrockLimitedAccess`** AWS managed policy (covers inference, model discovery, and marketplace permissions) plus a supplemental inline policy for observability and cost commands. See `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/iam-permissions.md` for the complete permissions reference.

## AWS CLI Profile Selection

Before any AWS command, ask the developer which AWS CLI profile to use. List available profiles by running `aws configure list-profiles`. **Wait for confirmation** — do not auto-select. Then verify with `aws sts get-caller-identity --profile <PROFILE>`. If it fails or no profiles exist, load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/profile-setup.md` to guide the developer through profile creation.

## Step 1: Check Region

Ask which region they want to use. Recommend `us-east-1` for broadest model availability.

Run: `aws configure get region --profile <PROFILE>`

## Step 2: IAM Permissions

Read the IAM setup reference at `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/iam-permissions.md`.

The developer needs two things attached to their IAM user or role:

1. **`AmazonBedrockLimitedAccess`** managed policy — covers inference, model discovery, and marketplace permissions
2. **Supplemental inline policy** (from `iam-permissions.md`) — covers CloudWatch, Service Quotas, Cost Explorer, and STS for the plugin's observability and cost commands

Walk the developer through attaching both. Default model: `us.anthropic.claude-sonnet-4-6`

## Step 3: Enable Model Access

Read the model access reference at `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/model-access.md`.

Remind the developer:

- All Bedrock serverless models are auto-enabled on first invocation with the correct AWS Marketplace permissions
- **Anthropic models (Claude)**: require a one-time use case form (First Time Use) before first invocation — submit via the Bedrock console or `PutUseCaseForModelAccess` API
- **All other models** (Amazon Nova, Meta Llama, Mistral, DeepSeek, Qwen, OpenAI): work immediately with correct IAM permissions — no marketplace subscription or use case form needed

## Step 4: Validate Bedrock Access

Run the validation script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-bedrock-access.sh <MODEL_ID> <REGION> <PROFILE>
```

All 4 checks must pass before proceeding.

## Step 5: Configure Prompt Caching

Ask the developer: **Do you want simplified or explicit prompt caching?**

- **Simplified** (recommended for Claude models): Single cache point, automatic cache management
- **Explicit**: Manual checkpoint placement, works with all supported models

Read `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/prompt-caching.md` for conceptual guidance. For working code samples, reference: https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching

## Step 6: Validate Prompt Caching

Run the end-to-end validation:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt-caching.py --model-id <MODEL_ID> --region <REGION> --profile <PROFILE>
```

Verify that cache write succeeds on the first request and cache read succeeds on the second.

## Step 7: Check Metrics (Optional)

Let the developer know they can run `/bedrock-usage` at any time to pull token consumption and caching metrics from CloudWatch. Bedrock publishes metrics automatically — no setup needed.
