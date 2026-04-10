# Cost Optimization and Cross-Region Inference

## Bedrock Pricing

For current per-token pricing, consult the official sources:

- **AWS Bedrock Pricing Page**: https://aws.amazon.com/bedrock/pricing/
- **AWS Docs MCP Server**: Search for "Amazon Bedrock pricing" using `mcp__aws-documentation__search_documentation`

Bedrock charges per token processed. Input tokens are cheaper than output tokens (typically 3-5x). Prompt caching adds a 25% write premium but offers 90% savings on cache reads.

### Cost Levers (Ranked by Impact)

1. **Model selection**: Haiku 4.5 is ~4x cheaper than Sonnet for input, ~4x cheaper for output. Use Haiku for classification, routing, and short-response tasks.
2. **Prompt caching**: Up to 90% savings on cached input tokens. See [prompt-caching.md](prompt-caching.md).
3. **max_tokens optimization**: Doesn't affect billing directly but prevents throttling that blocks revenue-generating requests. See [quota-optimization.md](quota-optimization.md).
4. **Output length control**: Output tokens cost 5x more than input tokens for Claude models. Instruct the model to be concise when full responses aren't needed.

## Cross-Region Inference

Cross-region inference distributes requests across multiple AWS regions for higher throughput and availability. It uses inference profile IDs with a region prefix.

### Inference Profile IDs

| Type            | Prefix    | Description                                                             |
| --------------- | --------- | ----------------------------------------------------------------------- |
| Geographic (US) | `us.`     | Routes within US regions (us-east-1, us-east-2, us-west-2, etc.)        |
| Geographic (EU) | `eu.`     | Routes within EU regions (eu-central-1, eu-west-1, eu-west-3, etc.)     |
| Geographic (AP) | `ap.`     | Routes within APAC regions                                              |
| Global          | `global.` | Routes to any supported commercial region worldwide (~10% cost savings) |

Claude models require a cross-region prefix. Use the prefix that matches your target geography:

```python
# Cross-region (US group):
model_id = "us.anthropic.claude-sonnet-4-6"

# Cross-region (EU group):
model_id = "eu.anthropic.claude-sonnet-4-6"

# Global (any supported region, ~10% cost savings):
model_id = "global.anthropic.claude-sonnet-4-6"
```

### Benefits

- **Higher throughput**: Distributes requests across multiple regions for better capacity
- **Higher availability**: Automatic failover if one region is under load
- **No additional routing cost**: Price is calculated based on the source region. Global inference offers ~10% savings.
- **No data storage**: Inference data is processed in transit but not stored in destination regions. All data stays on the AWS network.
- **Prompt caching works**: Cache is maintained per-region but cross-region inference is compatible

### Usage

Claude models are only available through cross-region inference. Just use the prefixed model ID — no setup required:

```python
# Use the prefixed model ID directly
model_id = "us.anthropic.claude-sonnet-4-6"
```

To validate access, run `/bedrock-validate-model-access`.

### SCP Gotcha (The #1 Failure Cause)

Cross-region inference requires Bedrock permissions in **ALL regions** in the inference profile group. If a Service Control Policy (SCP) blocks Bedrock in even ONE target region, the entire cross-region feature fails silently with `AccessDeniedException`.

Example: Using `us.anthropic.claude-sonnet-4-6` in `us-east-1`. The model is available in us-east-1, us-east-2, and us-west-2. If your SCP blocks `us-east-2` for all services, cross-region inference fails — even though us-east-1 and us-west-2 are allowed.

**Fix**: If your SCP restricts regions via a Deny statement, add a condition that exempts Bedrock actions from the region restriction:

```json
{
  "Sid": "DenyNonApprovedRegions",
  "Effect": "Deny",
  "NotAction": [
    "bedrock:InvokeModel",
    "bedrock:InvokeModelWithResponseStream",
    "bedrock:Converse",
    "bedrock:ConverseStream"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:RequestedRegion": ["us-east-1"]
    }
  }
}
```

This denies all non-Bedrock actions outside `us-east-1` while allowing Bedrock inference to reach cross-region destinations (us-east-2, us-west-2, etc.). Alternatively, add all destination regions to your existing SCP's allowed region list.

### IAM Requirements

Cross-region inference requires a two-statement IAM policy: one granting access to the inference profile, and one granting access to the foundation model in all destination regions (with an `InferenceProfileArn` condition for least-privilege):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCrossRegionInferenceProfile",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:Converse"],
      "Resource": [
        "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:inference-profile/us.anthropic.claude-sonnet-4-6"
      ]
    },
    {
      "Sid": "AllowFoundationModelInDestinationRegions",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "bedrock:Converse"],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-sonnet-4-6",
        "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-sonnet-4-6",
        "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-6"
      ],
      "Condition": {
        "StringEquals": {
          "bedrock:InferenceProfileArn": "arn:aws:bedrock:us-east-1:<ACCOUNT_ID>:inference-profile/us.anthropic.claude-sonnet-4-6"
        }
      }
    }
  ]
}
```

Replace `<ACCOUNT_ID>` with your AWS account ID.

## When Provisioned Throughput Makes Sense

On-demand inference (default) is billed per token with shared quota. Provisioned throughput reserves dedicated capacity at a fixed hourly rate.

Consider provisioned throughput when:

- You consistently hit on-demand quota limits even after optimization
- You need guaranteed latency SLAs
- Your workload exceeds 1M+ tokens per minute sustained
- You've already optimized max_tokens and enabled cross-region inference

Provisioned throughput is significantly more expensive for low/variable workloads. Start with on-demand and optimize before considering provisioned.

## Tracking Costs and Usage

Use the plugin commands to pull metrics directly:

```bash
# Token usage from CloudWatch
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-usage.py --all-models --period 7

# Actual costs from Cost Explorer
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-costs.py --period 7 --group-by model
```

For details on available CloudWatch metrics, see [observability.md](observability.md).
