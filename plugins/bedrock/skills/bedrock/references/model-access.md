# Model Access and Selection

## Recommended Starting Model

**Claude Sonnet 4.6** (`us.anthropic.claude-sonnet-4-6`)

- Best balance of capability and cost for startups
- Available via cross-region inference (`us.` prefix for geographic, `global.` for global routing)
- 1M token context window, 64K max output

## Enabling Model Access

Since October 2025, all Bedrock serverless models are **auto-enabled** — no manual toggle in the console needed. However, some models have one-time prerequisites before your first API call will succeed. You need:

1. IAM policy allowing `bedrock:InvokeModel` / `bedrock:Converse` (see [iam-permissions.md](iam-permissions.md))
2. `aws-marketplace:Subscribe` and `aws-marketplace:ViewSubscriptions` IAM permissions for auto-enablement to succeed on first invocation

### Anthropic Models (Claude)

In addition to auto-enablement, Anthropic requires a **one-time use case form** (First Time Use) before first invocation:

- Submit by selecting any Anthropic model in the [Bedrock console](https://console.aws.amazon.com/bedrock/) playground
- Or via the `PutUseCaseForModelAccess` API
- If submitted from the AWS Organization management account, it applies to all member accounts
- Once submitted, access to all Anthropic models is granted immediately

### Models Without Marketplace Product IDs

Models from Amazon (Nova, Titan), Meta (Llama), Mistral AI, DeepSeek, Qwen, and OpenAI don't have AWS Marketplace product IDs and work immediately with the correct IAM permissions — no marketplace subscription or use case form needed. By invoking a model for the first time, you agree to its applicable EULA (see [AWS Service Terms](https://aws.amazon.com/service-terms/)).

### Via CLI

```bash
# List available models
aws bedrock list-foundation-models \
    --profile PROFILE \
    --region us-east-1 \
    --query 'modelSummaries[*].[modelId,modelName,providerName]' \
    --output table

# Check model availability status
aws bedrock get-foundation-model-availability \
    --model-id anthropic.claude-sonnet-4-6 \
    --profile PROFILE \
    --region us-east-1

# Enable model access programmatically (third-party models)
aws bedrock create-foundation-model-agreement \
    --model-id MODEL_ID \
    --offer-token OFFER_TOKEN \
    --profile PROFILE \
    --region us-east-1
```

See [Access Amazon Bedrock foundation models](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) for details.

## Model Selection Guide

### For Prompt Caching

| Priority | Model             | Min Tokens | 1h TTL | Cost Tier | Best For                                                          |
| -------- | ----------------- | ---------- | ------ | --------- | ----------------------------------------------------------------- |
| 1        | Claude Sonnet 4.6 | 2,048      | Yes    | Mid       | General purpose, best cost/capability ratio (recommended default) |
| 2        | Claude Haiku 4.5  | 4,096      | Yes    | Low       | High-volume, cost-sensitive workloads                             |
| 3        | Nova Pro          | 1,000      | No     | Low       | No use case form needed                                           |
| 4        | Claude Opus 4.6   | 4,096      | Yes    | High      | Complex reasoning tasks                                           |

### Model Access by Provider

**Auto-enabled, no form needed** (Amazon, Meta, Mistral, DeepSeek, Qwen, OpenAI):

- Work immediately with correct IAM permissions
- Simplest setup

**Anthropic (Claude)**:

- Requires `aws-marketplace:Subscribe` and `aws-marketplace:ViewSubscriptions` IAM permissions for auto-enablement
- One-time use case form (First Time Use) required per account (or per AWS Organization from management account)
- After form submission, all Anthropic models are available immediately

## Cross-Region Inference

Claude models are **only available through cross-region inference** — you must use a prefixed model ID (e.g., `us.anthropic.claude-sonnet-4-6`). The bare base model ID (`anthropic.claude-sonnet-4-6`) **cannot be used for inference** and will return `ResourceNotFoundException`. No inference profile needs to be created; AWS provides system-defined inference profiles automatically.

| Prefix    | Use when target region is                               | Example                              |
| --------- | ------------------------------------------------------- | ------------------------------------ |
| `us.`     | `us-east-1`, `us-east-2`, `us-west-2`, or any US region | `us.anthropic.claude-sonnet-4-6`     |
| `eu.`     | `eu-west-1`, `eu-central-1`, or any EU region           | `eu.anthropic.claude-sonnet-4-6`     |
| `ap.`     | `ap-northeast-1`, `ap-southeast-1`, or any AP region    | `ap.anthropic.claude-sonnet-4-6`     |
| `global.` | Any region (~10% cost savings via global routing)       | `global.anthropic.claude-sonnet-4-6` |

Both the geographic prefix (`us.`, `eu.`, `ap.`) and `global.` are valid for any region in that geography. Choose `global.` for cost savings or geographic prefix for data residency.

Non-Claude models (Amazon Nova, Titan, etc.) do not support cross-region inference and use bare model IDs with no prefix (e.g., `amazon.nova-pro-v1:0`).

For IAM and SCP requirements for cross-region inference, see [cost-optimization.md](cost-optimization.md).

## Region Availability

Primary regions with broadest model availability:

- `us-east-1` (N. Virginia) — most models available first
- `us-west-2` (Oregon) — second broadest availability
- `eu-west-1` (Ireland) — for EU data residency requirements
- `ap-northeast-1` (Tokyo) — for APAC

Check current availability:

```bash
aws bedrock list-foundation-models \
    --profile PROFILE \
    --region us-east-1 \
    --query 'modelSummaries[?contains(modelId, `claude`) || contains(modelId, `nova`)].modelId' \
    --output table
```

## Verifying Model Access

```bash
# Check if a specific model is accessible (will fail with ResourceNotFoundException if not enabled)
aws bedrock get-foundation-model \
    --model-identifier anthropic.claude-sonnet-4-6 \
    --profile PROFILE \
    --region us-east-1

# Or run the full validation script
${CLAUDE_PLUGIN_ROOT}/scripts/validate-bedrock-access.sh <MODEL_ID> <REGION> <PROFILE>
```
