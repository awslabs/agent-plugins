---
name: bedrock-quota
description: "Check quota health, detect max_tokens waste, and generate quota increase data"
---

# Bedrock Quota Health Check

Analyze the developer's Bedrock quota utilization, detect the max_tokens pre-reservation trap, and generate data for quota increase requests.

## Required Permissions

```json
{
  "Effect": "Allow",
  "Action": [
    "cloudwatch:GetMetricStatistics",
    "servicequotas:ListServiceQuotas"
  ],
  "Resource": "*"
}
```

## Step 1: Run Quota Health Check

Ask the user which model and region they're using (defaults: Claude Sonnet 4.6 in us-east-1).

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/check-quota-health.py --model-id <MODEL_ID> --region <REGION>
```

This checks:

1. Current quota limits (TPM, RPM)
2. Actual token usage from CloudWatch
3. Whether max_tokens is set too high (the #1 cause of throttling)
4. Burndown rate impact (5x for Claude 3.7+ models)
5. Whether cross-region inference would help

## Step 2: Explain Findings

If the max_tokens trap is detected, explain using the reference doc:

Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/quota-optimization.md` and walk the developer through:

- Why their default max_tokens is wasting quota
- The specific max_tokens value to set based on their actual output distribution
- The burndown rate for their model

## Step 3: Quota Increase (if needed)

If the developer needs more quota, the script generates the exact data AWS requires. Guide them through the Service Quotas console request process.

## Step 4: Cross-Region Inference

Claude models are only available through cross-region inference (prefixed model IDs like `us.anthropic.claude-sonnet-4-6`). If the developer is having access issues, run `/bedrock-validate-model-access`. For cross-region IAM and SCP guidance, load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/cost-optimization.md`.
