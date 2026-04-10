# Bedrock Observability

## Default CloudWatch Metrics

Amazon Bedrock automatically publishes metrics to CloudWatch under the `AWS/Bedrock` namespace. No setup required — these are available as soon as you make inference calls.

### Available Metrics

| Metric                      | Description                            | Unit         | What It Tells You                |
| --------------------------- | -------------------------------------- | ------------ | -------------------------------- |
| `Invocations`               | Number of InvokeModel/Converse calls   | Count        | Request volume                   |
| `InputTokenCount`           | Input tokens per request               | Count        | How much context you're sending  |
| `OutputTokenCount`          | Output tokens per request              | Count        | How much the model is generating |
| `CacheReadInputTokenCount`  | Tokens read from cache (cache hits)    | Count        | Cache effectiveness              |
| `CacheWriteInputTokenCount` | Tokens written to cache (cache misses) | Count        | Cache churn                      |
| `InvocationLatency`         | End-to-end request latency             | Milliseconds | Response time                    |
| `InvocationClientErrors`    | 4xx errors                             | Count        | Permission/validation issues     |
| `InvocationServerErrors`    | 5xx errors                             | Count        | Service-side issues              |
| `InvocationThrottles`       | Throttled requests (429s)              | Count        | Quota pressure                   |

### Dimensions

- `ModelId`: Filter by specific model (e.g., `us.anthropic.claude-sonnet-4-6`)

## Pulling Metrics with the Plugin

The fastest way to see your Bedrock metrics:

```bash
# Usage for a specific model (default: 7 days)
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-usage.py --model-id <MODEL_ID> --region <REGION> --period <DAYS>

# Discover and analyze all active models
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/analyze-bedrock-usage.py --all-models --region <REGION> --period <DAYS>
```

The script pulls directly from CloudWatch and reports:

- Invocation counts and average tokens per request
- Total input and output token consumption
- Prompt caching efficiency (cache hit ratio, write vs read tokens)
- Warnings for low cache hit ratios or missing caching

## Key Metrics to Watch

### Cache Hit Rate

```
Cache Hit Rate = CacheReadInputTokens / (CacheReadInputTokens + CacheWriteInputTokens + non-cached InputTokens)
```

A healthy cache hit rate for repeated system prompts should be > 80%. If it's low, run `/bedrock-cache-debug` to diagnose.

### Throttle Rate

If `InvocationThrottles` is non-zero, you're hitting quota limits. Run `/bedrock-quota` to diagnose — most likely `max_tokens` is set too high.

### Output-to-Input Ratio

High `OutputTokenCount` relative to `InputTokenCount` means output tokens dominate your costs (output is 3-5x more expensive). Consider instructing the model to be concise when full responses aren't needed.

## Querying Metrics Directly via CLI

For quick spot-checks without the plugin script:

```bash
# Total invocations for a model over the last 24 hours
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --dimensions Name=ModelId,Value=us.anthropic.claude-sonnet-4-6 \
  --start-time $(date -u -v-1d +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --profile PROFILE \
  --region us-east-1

# Check for throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationThrottles \
  --dimensions Name=ModelId,Value=us.anthropic.claude-sonnet-4-6 \
  --start-time $(date -u -v-1d +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum \
  --profile PROFILE \
  --region us-east-1
```
