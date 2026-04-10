---
name: bedrock
description: "Amazon Bedrock setup and operations: onboarding, IAM setup, model access, prompt caching, observability, quota optimization, cost analysis, and cross-region inference. Triggers on phrases like: set up bedrock, configure bedrock, bedrock onboarding, prompt caching, bedrock IAM, enable model access, cache management, bedrock observability, bedrock costs, bedrock quota, cross-region inference."
argument-hint: "[what do you need help with?]"
---

# Amazon Bedrock

Guide developers through Amazon Bedrock — from initial setup to ongoing operations. Covers IAM permissions, model access, prompt caching (simplified or explicit), CloudWatch observability, quota optimization, cost analysis, and cross-region inference.

## Knowledge Sources

Use these sources to answer Bedrock questions. Choose the source that best matches the query — you may consult multiple sources or skip sources that aren't relevant.

- **AWS Docs MCP Server** (`mcp__plugin_bedrock_aws-documentation__search_documentation`, `mcp__plugin_bedrock_aws-documentation__read_documentation`) — Official AWS documentation. Best for: API reference, service limits, pricing, IAM permissions, error codes, feature availability.
- **aws-samples prompt caching repo** (https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching) — Working code samples for Converse API and InvokeModel API prompt caching. Best for: caching implementation, code examples, cache configuration patterns.
- **Bedrock Central** (https://aws-samples.github.io/sample-amazon-bedrock-central/) — Curated getting-started guides, model discovery, workshops, and sample applications. Best for: onboarding, model comparison, architecture patterns, workshop walkthroughs.
- **Plugin reference docs** (`${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/`) — Operational runbooks for the plugin's own scripts. Best for: step-by-step guidance on IAM setup, quota optimization, observability, cost analysis, and cross-region inference.
- **Internet search** — Last resort when other sources don't cover the topic. Always state that the answer came from an internet search.

Always cite the source that provided your answer.

**Key capabilities:**

- **IAM Setup**: Generate least-privilege IAM policies scoped to specific Bedrock models and actions
- **Model Access**: Enable foundation model access, understand region availability, and select the right model
- **Prompt Caching**: Configure simplified (Claude-only) or explicit cache management with the Converse API
- **Cache Debugging**: Diagnose prompt caching failures with automated 6-test diagnostic suite
- **Validation**: End-to-end verification that IAM, model access, and prompt caching work correctly
- **Observability**: CloudWatch metrics for cache hit rates, token usage, and latency monitoring
- **Quota Optimization**: Detect max_tokens waste, analyze quota utilization, generate quota increase request data
- **Usage Analysis**: CloudWatch token consumption metrics, invocation counts, and caching efficiency
- **Cost Analysis**: Actual billed amounts from AWS Cost Explorer — no hardcoded pricing
- **Cross-Region Inference**: Claude models are only available through cross-region inference — guidance on IAM, SCPs, and troubleshooting

## Onboarding Workflow

When a user asks to set up Bedrock, follow these steps in order:

### Step 1: AWS CLI Profile Selection

Before any AWS command, ask the developer which AWS CLI profile to use. List available profiles by running `aws configure list-profiles`. **Wait for confirmation** — do not auto-select. Then verify with `aws sts get-caller-identity --profile <PROFILE>` and show the account ID and ARN.

If credentials are missing or the developer needs to create a new profile, load [references/profile-setup.md](references/profile-setup.md) for step-by-step guidance.

### Step 2: IAM Permissions

Load [references/iam-permissions.md](references/iam-permissions.md) and help the user create or verify their IAM policy.

Run the validation script to check permissions:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/validate-bedrock-access.sh
```

### Step 3: Model Access

Load [references/model-access.md](references/model-access.md) and help the user enable their chosen model.

Key points:

- Since October 2025, all Bedrock serverless models are **auto-enabled** — no manual activation needed
- **Anthropic models** (Claude) require a **one-time use case form** (First Time Use) before first invocation — submit via the Bedrock console playground or `PutUseCaseForModelAccess` API
- **All other models** (Amazon Nova, Meta Llama, Mistral, etc.) work immediately with the correct IAM permissions
- Default recommendation: Claude Sonnet 4.6 (`us.anthropic.claude-sonnet-4-6`)

### Step 4: Prompt Caching

Ask the user: **simplified or explicit cache management?**

- **Simplified** (Claude models only): A single `cachePoint` marker; Bedrock automatically checks ~20 preceding blocks for cache hits. Easiest to implement.
- **Explicit**: Manual placement of multiple cache checkpoints with granular TTL control. Works with all supported models.

Load [references/prompt-caching.md](references/prompt-caching.md) for implementation details.

### Step 5: Validation

Run the end-to-end validation script:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt-caching.py --model-id us.anthropic.claude-sonnet-4-6
```

This sends two Converse API requests with identical cached content and verifies:

1. First request: `cacheWriteInputTokens > 0` (cache was written)
2. Second request: `cacheReadInputTokens > 0` (cache was hit)
3. Latency improvement on the second request

### Step 6: Observability

Let the developer know Bedrock publishes metrics to CloudWatch automatically. They can run `/bedrock-usage` to pull token consumption and caching metrics. For metric details, see [references/observability.md](references/observability.md).

## When to Load Reference Files

- **IAM**, **permissions**, **policy**, or **access denied errors** -> see [references/iam-permissions.md](references/iam-permissions.md)
- **Model selection**, **enable model**, **region**, **marketplace**, or **model access** -> see [references/model-access.md](references/model-access.md)
- **Prompt caching**, **cache point**, **TTL**, **simplified caching**, **explicit caching**, or **cache management** -> see [references/prompt-caching.md](references/prompt-caching.md)
- **Cache debug**, **cache not working**, **cache miss**, **no cache tokens**, or **cacheWriteInputTokens is zero** -> run `/bedrock-cache-debug`
- **CloudWatch**, **metrics**, **monitoring**, **dashboard**, **observability**, or **cache hit rate** -> see [references/observability.md](references/observability.md)
- **Quota**, **throttling**, **max_tokens**, **429 error**, **ThrottlingException**, **rate limit**, or **token limit** -> see [references/quota-optimization.md](references/quota-optimization.md)
- **Token usage**, **how many tokens**, **invocations**, or **CloudWatch metrics** -> run `/bedrock-usage`
- **Cost**, **spending**, **billing**, or **how much am I paying** -> run `/bedrock-costs`
- **Pricing**, **how much does a model cost**, or **per-token pricing** -> search AWS Docs MCP for "Amazon Bedrock pricing"; link to https://aws.amazon.com/bedrock/pricing/
- **Cost optimization**, **savings**, **ROI**, or **cheaper model** -> see [references/cost-optimization.md](references/cost-optimization.md)
- **Cross-region**, **inference profile**, **SCP**, **multi-region**, or **higher throughput** -> see [references/cost-optimization.md](references/cost-optimization.md)
- **Code samples**, **how to call Bedrock**, or **example code** -> fetch Bedrock Central; reference https://github.com/aws-samples/amazon-bedrock-samples
- **IAM action names**, **ARN format**, **cross-region prefix**, **CloudWatch metric names**, or **stable Bedrock facts** -> see [references/bedrock-quick-reference.md](references/bedrock-quick-reference.md)

## Best Practices

### Security

- Do: Use `AmazonBedrockLimitedAccess` managed policy for Bedrock permissions
- Do: Use named AWS CLI profiles with `--profile` rather than hardcoded credentials or environment variables
- Do: Scope Bedrock permissions to specific regions where you operate
- Don't: Write custom IAM policies when managed policies cover the use case
- Don't: Store AWS credentials in code or environment variables in production

### Prompt Caching

- Do: Use simplified caching if you only use Claude models — it requires less code and handles checkpoint placement automatically
- Do: Ensure your cached content exceeds the model's minimum token threshold (1,024–4,096 tokens for Claude models; 1,024–1,536 for Nova)
- Do: Place static content (system prompts, large documents, few-shot examples) before the cache point
- Do: Monitor `CacheReadInputTokenCount` in CloudWatch to verify cache hits
- Don't: Cache content that changes frequently — the cache key is based on exact content match
- Don't: Mix TTL durations out of order — longer TTLs must precede shorter TTLs in the message sequence

### Cost Optimization

- Do: Set `max_tokens` to ~1.5x your p90 actual output to avoid quota waste (the #1 optimization for throughput)
- Do: Start with prompt caching on your most repeated prompts first — it reduces costs by up to 90% and latency by up to 85%
- Do: Use the 1-hour TTL for system prompts that rarely change (supported on Claude Sonnet 4.6, Opus 4.6, Sonnet 4.5, Opus 4.5, Haiku 4.5)
- Do: Use cross-region inference (e.g., `us.anthropic.claude-sonnet-4-6`) for higher throughput at no additional routing cost
- Do: Monitor CloudWatch metrics to identify low cache hit rates and adjust accordingly
- Do: Run `/bedrock-quota` periodically to check for quota waste and throttling risks
- Don't: Cache very short content — there's a per-model minimum token threshold
- Don't: Cache single-use content — the 25% write premium increases cost when there are no cache reads
- Don't: Leave `max_tokens` at the default for high-concurrency workloads — it reserves up to 320K quota tokens per request

## Supported Models for Prompt Caching

For current supported models, minimum cache token thresholds, and TTL options, search the AWS Docs MCP Server for "Bedrock prompt caching supported models" or see the [prompt caching documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html).

General patterns (stable):

- Claude models: 1,024–4,096 minimum cache tokens depending on model; most support 5-minute TTL, newer models (Sonnet 4.6, Opus 4.6, Sonnet 4.5, Opus 4.5, Haiku 4.5) also support 1-hour TTL
- Amazon Nova models: 1,024–1,536 minimum cache tokens depending on model; 5-minute TTL

For cross-region inference, add the geo prefix to base model IDs (e.g., `us.` for US regions).

## Configuration

### AWS CLI Setup

This plugin requires AWS credentials configured on the host machine:

**Verify access**: Run `aws sts get-caller-identity --profile PROFILE` to confirm credentials are valid.

### Python Setup

Validation scripts require Python 3.10+ with boto3:

**Verify**: Run `python3 -c "import boto3; print(boto3.__version__)"`

If missing: `pip3 install boto3`

## Troubleshooting Quick Reference

| Error                                             | Cause                       | Solution                                                                                                                                                                       |
| ------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `AccessDeniedException`                           | Missing IAM permissions     | Add `bedrock:InvokeModel` and `bedrock:Converse` to the IAM policy. See [references/iam-permissions.md](references/iam-permissions.md)                                         |
| `ResourceNotFoundException`                       | Model not enabled in region | For Claude models, submit the one-time use case form. Check region availability and ensure you're using the cross-region model ID (e.g., `us.` prefix)                         |
| `ValidationException: cache tokens below minimum` | Cached content too short    | Increase cached content to exceed the model's minimum token threshold                                                                                                          |
| `ThrottlingException`                             | Rate limit exceeded         | Run `/bedrock-quota` to diagnose; likely `max_tokens` is too high or you need cross-region inference. See [references/quota-optimization.md](references/quota-optimization.md) |
| No `cacheReadInputTokens` in response             | Cache miss                  | Verify the cached content is identical between requests and within the TTL window                                                                                              |

## Resources

- [Bedrock Central](https://aws-samples.github.io/sample-amazon-bedrock-central/) — Getting started, model discovery, code samples, workshops
- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/) — Official AWS docs (also available via AWS Docs MCP server)
- [Prompt Caching Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html)
- [Prompt Caching Code Samples](https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching)
- [Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
- [Bedrock Service Quotas](https://docs.aws.amazon.com/bedrock/latest/userguide/quotas.html)
