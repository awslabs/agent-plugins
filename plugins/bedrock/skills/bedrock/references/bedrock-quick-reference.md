# Bedrock Quick Reference

Stable facts for frequent lookups. These rarely change but ALWAYS verify against the AWS Docs MCP Server if the information seems outdated or if more than 6 months have passed since the "Last verified" date.

Last verified: 2026-04-08

## IAM Action Names for Bedrock

| Action                                  | Used For                       |
| --------------------------------------- | ------------------------------ |
| `bedrock:InvokeModel`                   | Single inference request       |
| `bedrock:InvokeModelWithResponseStream` | Streaming inference            |
| `bedrock:Converse`                      | Converse API (recommended)     |
| `bedrock:ConverseStream`                | Streaming Converse API         |
| `bedrock:ListFoundationModels`          | Model discovery                |
| `bedrock:GetFoundationModel`            | Model details                  |
| `bedrock:ListInferenceProfiles`         | Cross-region profile discovery |
| `bedrock:ListModelAccessStatus`         | Check model enablement status  |

These are API action names tied to the Bedrock API surface. New actions are added when AWS ships new API operations, but existing actions are not renamed or removed.

## ARN Format Patterns

| Resource           | Pattern                                                          |
| ------------------ | ---------------------------------------------------------------- |
| Foundation model   | `arn:aws:bedrock:REGION::foundation-model/MODEL_ID`              |
| Cross-region model | `arn:aws:bedrock:REGION::foundation-model/PREFIX.MODEL_ID`       |
| Custom model       | `arn:aws:bedrock:REGION:ACCOUNT_ID:custom-model/MODEL_NAME`      |
| Inference profile  | `arn:aws:bedrock:REGION:ACCOUNT_ID:inference-profile/PROFILE_ID` |

## Cross-Region Prefix Conventions

| Prefix    | Region Group | Regions                                        |
| --------- | ------------ | ---------------------------------------------- |
| `us.`     | US           | us-east-1, us-east-2, us-west-2                |
| `eu.`     | Europe       | eu-central-1, eu-west-1, eu-west-3             |
| `ap.`     | Asia Pacific | ap-northeast-1, ap-southeast-1, ap-southeast-2 |
| `global.` | Global       | All Bedrock regions                            |

Example: `us.anthropic.claude-sonnet-4-6` routes to any US region.

## CloudWatch Metrics

Namespace: `AWS/Bedrock`

| Metric                      | Description                          |
| --------------------------- | ------------------------------------ |
| `Invocations`               | Number of InvokeModel/Converse calls |
| `InputTokenCount`           | Input tokens per request             |
| `OutputTokenCount`          | Output tokens per request            |
| `CacheReadInputTokenCount`  | Tokens read from cache               |
| `CacheWriteInputTokenCount` | Tokens written to cache              |
| `InvocationLatency`         | End-to-end latency in ms             |
| `InvocationClientErrors`    | 4xx errors                           |
| `InvocationServerErrors`    | 5xx errors                           |
| `InvocationThrottles`       | Throttled requests                   |

## Default Recommendations

- **Region**: `us-east-1` (broadest model availability and earliest feature launches)
- **Caching approach**: Simplified for Claude-only workloads; explicit for multi-model
- **Inference routing**: Cross-region (`us.` prefix) for startups — better availability, no routing cost

## What Is NOT in This File

The following change frequently. Always query the AWS Docs MCP Server for current values:

- Model IDs, model capabilities, minimum cache tokens, supported TTL durations
- Per-token pricing
- Service quota default values
- Feature availability dates and region rollout status
- Specific model version strings

## Verification Instructions

If any fact above seems wrong or a user reports an issue:

1. Search the AWS Docs MCP Server for the specific topic
2. Update this file with corrected information and a new "Last verified" date
3. Cite the AWS documentation URL that confirmed the correction
