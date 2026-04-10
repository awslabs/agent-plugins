---
name: bedrock-cache
description: "Set up and validate prompt caching (simplified or explicit)"
---

# Bedrock Prompt Caching Setup

Help the developer configure and validate prompt caching on Bedrock.

## Step 1: Choose Caching Strategy

Ask the developer:

**Simplified caching** (recommended for Claude models):

- Single `cachePoint` marker in the system or message blocks
- Bedrock automatically checks ~20 preceding blocks for cache hits
- Easiest to implement, fewer lines of code
- Claude models only

**Explicit caching** (for all supported models):

- Place `cachePoint` markers at specific positions
- Granular control over what gets cached
- Supports mixed TTL (1h + 5min) for different content sections
- Works with Claude, Nova, and other supported models

## Required Permissions

```json
{
  "Effect": "Allow",
  "Action": ["bedrock:Converse", "bedrock:ConverseStream"],
  "Resource": "arn:aws:bedrock:<REGION>::foundation-model/<MODEL_ID>"
}
```

## Step 2: Fetch Latest Implementation Guidance

**Before giving any implementation advice**, fetch the latest prompt caching guidance from the aws-samples repo. This is the authoritative source and takes priority over any other knowledge:

1. Use the context7 MCP tool to resolve and query `amazon-bedrock-samples` for prompt caching documentation:
   - `mcp__plugin_context7_context7__resolve-library-id` with query `amazon-bedrock-samples prompt caching`
   - Then `mcp__plugin_context7_context7__query-docs` for the resolved library, topic `prompt caching`
2. If context7 doesn't return results, use WebFetch to read the README at: https://raw.githubusercontent.com/aws-samples/amazon-bedrock-samples/main/introduction-to-bedrock/prompt-caching/README.md
3. For specific code samples, fetch directly from the repo:
   - `converse_api/` — Model-agnostic examples using Converse API with `cachePoint` syntax (recommended starting point)
   - `invoke_model_api/` — Model-specific examples using InvokeModel API (Anthropic `cache_control` format)
   - Mixed TTL notebooks for advanced configurations

Only after reviewing the upstream samples, read `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/prompt-caching.md` for additional conceptual guidance.

Help the developer adapt the samples to their specific model, region, and use case.

## Step 3: TTL Configuration

If using Claude Sonnet 4.6, Opus 4.6, Sonnet 4.5, Opus 4.5, or Haiku 4.5, offer the 1-hour TTL option for rarely-changing content. For older Claude models that support caching, only the default 5-minute TTL is available.

Remind: when mixing TTLs, longer durations must come before shorter ones.

## Step 4: Validate

Run:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt-caching.py --model-id <MODEL_ID> --region <REGION>
```

Confirm cache write on first request and cache read on second.

## Step 5: Verify Metrics (Optional)

Offer to run `/bedrock-usage` to confirm cache metrics are appearing in CloudWatch after the first cached requests.
