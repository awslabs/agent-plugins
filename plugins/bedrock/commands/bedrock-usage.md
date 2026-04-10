---
name: bedrock-usage
description: "Analyze Bedrock token consumption, invocation counts, and prompt caching efficiency from CloudWatch"
---

# Bedrock Usage Analysis

Query CloudWatch for token consumption metrics — what the developer used, not what they paid.

## Required Permissions

```json
{
  "Effect": "Allow",
  "Action": "cloudwatch:GetMetricStatistics",
  "Resource": "*"
}
```

## Step 1: Run Usage Analysis

Ask the user for the time period and model (defaults: 7 days, Claude Sonnet 4.6).

For a specific model:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-usage.py --model-id <MODEL_ID> --region <REGION> --period <DAYS>
```

To discover and analyze all active models:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-usage.py --all-models --region <REGION> --period <DAYS>
```

## Step 2: Interpret Results

The report shows:

- Invocation counts and average tokens per request
- Total input and output token consumption
- Prompt caching efficiency (cache hit ratio, write vs read tokens)
- Warnings for low cache hit ratios or missing caching

## Step 3: Act on Findings

Based on the results, suggest next steps:

- **No caching detected**: Run `/bedrock-cache` to set up prompt caching
- **Low cache hit ratio (<80%)**: Run `/bedrock-cache-debug` to diagnose
- **High token consumption or throttling**: Run `/bedrock-quota` to check for max_tokens waste
- **Want to see actual costs**: Run `/bedrock-costs` for Cost Explorer data

For deeper metric interpretation, read `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/observability.md`.
