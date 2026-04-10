# IAM Permissions Reference

What Bedrock permissions are needed to use this plugin's commands, and how to troubleshoot when they're wrong.

## Quick Start: AWS Managed Policy

Attach the **`AmazonBedrockLimitedAccess`** managed policy to the IAM user or role used with this plugin. This covers:

- `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream` — inference via Converse and InvokeModel APIs
- `bedrock:Get*`, `bedrock:List*` — model discovery and metadata
- `aws-marketplace:Subscribe`, `aws-marketplace:ViewSubscriptions` — Anthropic model auto-enablement (conditioned on `CalledViaLast: bedrock.amazonaws.com`)

Attach via CLI:

```bash
aws iam attach-user-policy \
    --user-name <USER> \
    --policy-arn arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess \
    --profile <PROFILE>

# Or for a role:
aws iam attach-role-policy \
    --role-name <ROLE> \
    --policy-arn arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess \
    --profile <PROFILE>
```

For full admin access (includes model management, provisioned throughput, guardrails), use **`AmazonBedrockFullAccess`** instead.

## Supplemental Policy for Observability and Cost Commands

`AmazonBedrockLimitedAccess` does not include CloudWatch, Service Quotas, Cost Explorer, or STS permissions. If you want to use `/bedrock-usage`, `/bedrock-quota`, or `/bedrock-costs`, create and attach this inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockPluginObservability",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:GetMetricStatistics",
        "servicequotas:ListServiceQuotas",
        "ce:GetCostAndUsage",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

`ce:GetCostAndUsage` requires Cost Explorer to be enabled in the account (free, but not on by default). Enable via: AWS Console > Billing > Cost Explorer > Enable Cost Explorer.

## Per-Command Permissions

Each `/bedrock-*` command requires specific IAM actions. Use this to understand what the managed policy and supplemental policy cover:

| Command                          | IAM Actions Required                                                                                         | Covered By                                            |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------- |
| `/bedrock-validate-model-access` | `sts:GetCallerIdentity`, `bedrock:ListFoundationModels`, `bedrock:GetFoundationModel`, `bedrock:InvokeModel` | Managed policy (Bedrock actions) + supplemental (STS) |
| `/bedrock-cache`                 | `bedrock:InvokeModel`, `bedrock:InvokeModelWithResponseStream`                                               | Managed policy                                        |
| `/bedrock-cache-debug`           | `bedrock:InvokeModel`                                                                                        | Managed policy                                        |
| `/bedrock-usage`                 | `cloudwatch:GetMetricStatistics`                                                                             | Supplemental policy                                   |
| `/bedrock-costs`                 | `ce:GetCostAndUsage`                                                                                         | Supplemental policy                                   |
| `/bedrock-quota`                 | `cloudwatch:GetMetricStatistics`, `servicequotas:ListServiceQuotas`                                          | Supplemental policy                                   |
| `/bedrock-setup`                 | All of the above                                                                                             | Both policies                                         |

Note: The Converse and ConverseStream APIs require `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` respectively — they are not separate IAM actions.

### Cross-Region Inference Permissions

Cross-region model IDs (e.g., `us.anthropic.claude-sonnet-4-6`) require IAM policies that grant access to both the inference profile ARN and the foundation model ARN in destination regions. See [cost-optimization.md](cost-optimization.md) (IAM Requirements section) for the full policy template.

## Anthropic Model Prerequisites

In addition to IAM permissions, Anthropic models require:

- `aws-marketplace:Subscribe` and `aws-marketplace:ViewSubscriptions` IAM permissions for auto-enablement (included in `AmazonBedrockLimitedAccess`)
- A one-time use case form (First Time Use) before first invocation — submit via the [Bedrock console](https://console.aws.amazon.com/bedrock/) or `PutUseCaseForModelAccess` API
- If submitted from the AWS Organization management account, applies to all member accounts

Models from Amazon, Meta, Mistral, DeepSeek, Qwen, and OpenAI work immediately with correct IAM permissions — no marketplace subscription or use case form needed.

## Common Permission Errors

| Error                                                                            | Likely Cause                           | Fix                                                                         |
| -------------------------------------------------------------------------------- | -------------------------------------- | --------------------------------------------------------------------------- |
| `AccessDeniedException` on InvokeModel                                           | Missing `bedrock:InvokeModel`          | Verify `AmazonBedrockLimitedAccess` is attached                             |
| `AccessDeniedException` on Converse                                              | Missing `bedrock:InvokeModel`          | Converse requires `bedrock:InvokeModel` — verify managed policy is attached |
| `AccessDeniedException` on ListFoundationModels                                  | Missing `bedrock:ListFoundationModels` | Verify `AmazonBedrockLimitedAccess` is attached                             |
| `AccessDeniedException` on cross-region model ID (e.g., `us.anthropic.claude-*`) | SCP or IAM blocks destination regions  | See [cost-optimization.md](cost-optimization.md) SCP Gotcha section         |
| Model not in list despite permissions                                            | Model not enabled                      | Submit use case form for Anthropic models, or check region availability     |

## Validation Passes but Application Still Fails

If `validate-bedrock-access.sh` passes but your application still gets errors:

1. **IAM principal mismatch**: The validation script runs under your CLI user/role, but your app may use a different principal (Lambda execution role, ECS task role, etc.). Check with `aws sts get-caller-identity` from your app's runtime.
2. **API action mismatch**: The script tests via Converse (`bedrock:InvokeModel`), but your app may use streaming (`bedrock:InvokeModelWithResponseStream`). Ensure the managed policy is attached (it includes both).
3. **SCP restrictions**: Organization-level Service Control Policies may block Bedrock in certain regions or for certain principals, even when IAM allows it. SCPs are invisible in IAM policy simulation.
4. **Streaming permissions**: If your app uses streaming (`ConverseStream` or `InvokeModelWithResponseStream`), ensure the policy includes `bedrock:InvokeModelWithResponseStream` (included in `AmazonBedrockLimitedAccess`).
5. **Model ID format**: Cross-region model IDs (e.g., `us.anthropic.claude-sonnet-4-6`) require IAM policies that grant access to both the inference profile ARN and the foundation model ARN in all destination regions. See [cost-optimization.md](cost-optimization.md) IAM Requirements section.
