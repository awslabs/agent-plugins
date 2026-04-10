---
name: bedrock-costs
description: "Analyze actual Bedrock spend from AWS Cost Explorer — real billed amounts, not estimates"
---

# Bedrock Cost Analysis

Query AWS Cost Explorer for the developer's actual Bedrock charges. All cost data comes directly from the AWS bill — no hardcoded pricing.

## Required Permissions

```json
{
  "Effect": "Allow",
  "Action": "ce:GetCostAndUsage",
  "Resource": "*"
}
```

**Prerequisite**: Cost Explorer must be enabled in the account. Enable via: AWS Console > Billing > Cost Explorer > Enable Cost Explorer. Takes up to 24 hours to activate.

## Step 1: Run Cost Analysis

Ask the user for the time period (default: 7 days).

Aggregate Bedrock spend:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-costs.py --period <DAYS>
```

Grouped by usage type (shows per-model breakdown):

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-costs.py --period <DAYS> --group-by model
```

## Step 2: Interpret Results

The report shows:

- Total Amazon Bedrock spend for the period (actual billed amounts)
- Daily cost breakdown
- Per-model cost breakdown (when using `--group-by model`)

## Step 3: Optimize

For cost optimization guidance:

- **Token-level metrics**: Run `/bedrock-usage` for CloudWatch token consumption data
- **Enable caching**: Run `/bedrock-cache` to set up prompt caching
- **Reduce quota waste**: Run `/bedrock-quota` for max_tokens optimization
- **Current pricing**: Use the AWS Docs MCP server to search for "Amazon Bedrock pricing" or visit https://aws.amazon.com/bedrock/pricing/
- **Optimization strategies**: Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/cost-optimization.md`
