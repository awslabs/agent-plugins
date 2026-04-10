# Quota Optimization and Throttling Guide

Bedrock enforces per-model quotas on tokens per minute (TPM), tokens per day (TPD), and requests per minute (RPM). Understanding how these quotas work — especially the `max_tokens` pre-reservation and burndown rates — is the single most impactful optimization for production throughput.

## The max_tokens Trap

When you send a request, Bedrock **immediately reserves** quota for the maximum possible response:

```
Initial reservation = total_input_tokens + max_tokens
```

Where `total_input_tokens` includes input tokens, cache read tokens, and cache write tokens. After the response completes, the final adjusted deduction is calculated with the burndown rate applied to actual output:

```
Final deduction = input_tokens + cache_write_tokens + (actual_output_tokens × burndown_rate)
```

Cache read tokens don't count toward the final deduction. Unused reserved tokens are returned to your quota, but during processing the initial reservation blocks other concurrent requests.

### Example: The Default Disaster

Assume: 8,000 input tokens, actual output 1,200 tokens, default `max_tokens` of 64,000, Claude Sonnet 4.6 (5x burndown):

| Scenario                     | Initial Reservation         | Final Deduction          | Wasted Reservation             |
| ---------------------------- | --------------------------- | ------------------------ | ------------------------------ |
| Default max_tokens (64,000)  | 8,000 + 64,000 = **72,000** | 8,000 + 5×1,200 = 14,000 | 80%                            |
| Optimized max_tokens (1,800) | 8,000 + 1,800 = **9,800**   | 8,000 + 5×1,200 = 14,000 | 0% (final > initial, no waste) |

With the default, a single request temporarily consumes **72,000 quota tokens**, leaving less room for concurrent requests. With an optimized `max_tokens`, the reservation is much smaller. Note: when the final deduction exceeds the initial reservation (due to burndown rate on output), the extra tokens are still deducted from your quota.

### How to Right-Size max_tokens

1. Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/check-quota-health.py` to see your actual output distribution
2. Set `max_tokens` to approximately **1.5× your p90 actual output**:

| Typical Output      | Recommended max_tokens |
| ------------------- | ---------------------- |
| < 500 tokens        | 750                    |
| 500–2,000 tokens    | 3,000                  |
| 2,000–5,000 tokens  | 7,500                  |
| 5,000–10,000 tokens | 15,000                 |
| > 10,000 tokens     | p90 × 1.5              |

Minimum floor: 256 tokens. Always leave headroom above your p90 to avoid truncating long responses.

## Burndown Rates

Not all models consume quota equally. Claude 3.7 and later models use a **5x burndown rate** for output tokens:

| Model Family                            | Input Rate | Output Rate | Impact                          |
| --------------------------------------- | ---------- | ----------- | ------------------------------- |
| Claude Sonnet 4.6, Opus 4.6, Haiku 4.5  | 1:1        | **1:5**     | 1 output token = 5 quota tokens |
| Claude Sonnet 4.5, Opus 4.5, 3.7 Sonnet | 1:1        | **1:5**     | 1 output token = 5 quota tokens |
| Claude 3.5 Sonnet v2, 3.5 Haiku         | 1:1        | 1:1         | Standard rate                   |
| Amazon Nova Pro, Lite, Micro            | 1:1        | 1:1         | Standard rate                   |

The 5x burndown is a **quota management** concern, not a billing concern. You are billed for actual tokens at standard rates. The multiplier only affects how fast you consume your per-minute quota.

## Cross-Region Inference for Quota Relief

Cross-region inference profiles (e.g., `us.anthropic.claude-sonnet-4-6` instead of `anthropic.claude-sonnet-4-6`) provide higher throughput by distributing requests across multiple regions. Check default quotas for cross-region profiles in [Amazon Bedrock service quotas](https://docs.aws.amazon.com/general/latest/gr/bedrock.html#limits_bedrock).

Benefits:

- Higher TPM and RPM quota than single-region inference
- Automatic regional failover for higher availability
- Same per-token pricing (no additional cost)
- Prompt caching works with cross-region inference

For cross-region IAM and SCP guidance, see [cost-optimization.md](cost-optimization.md). To validate access, run `/bedrock-validate-model-access`.

## Requesting a Quota Increase

AWS requires specific data when reviewing quota increase requests. Run the quota health check to generate this data automatically:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/check-quota-health.py --model-id MODEL_ID --region REGION
```

The script generates these fields, which you paste into the AWS Service Quotas console:

- **Steady-state TPM**: Average tokens per minute during normal operation
- **Peak TPM**: Maximum tokens per minute during traffic spikes
- **Average input tokens per request**: Helps AWS understand request shape
- **Average output tokens per request**: Affects burndown rate impact
- **Total requests in observation period**: Demonstrates actual demand

Request quotas at: https://console.aws.amazon.com/servicequotas/home/services/bedrock/quotas

## Handling ThrottlingException

A 429 `ThrottlingException` means your request was rejected because quota is exhausted. This is not a transient error — retrying immediately will fail again.

### Retry Pattern

```python
import time
import random
from botocore.exceptions import ClientError
from botocore.config import Config

# Configure SDK-level retries with adaptive backoff
config = Config(retries={"max_attempts": 5, "mode": "adaptive"})
client = boto3.client("bedrock-runtime", config=config)

# For application-level retries beyond SDK defaults:
def invoke_with_backoff(client, max_retries=5, **kwargs):
    for attempt in range(max_retries):
        try:
            return client.converse(**kwargs)
        except ClientError as e:
            if e.response["Error"]["Code"] == "ThrottlingException":
                if attempt == max_retries - 1:
                    raise
                # Exponential backoff with jitter, aligned to 60s quota window
                delay = min(60, (2 ** attempt) + random.uniform(0, 1))
                time.sleep(delay)
            else:
                raise
```

Key points:

- Quota refreshes every **60 seconds** — retrying within the same minute rarely helps
- Use **exponential backoff with jitter** to avoid thundering herd effects
- Set `max_tokens` properly to reduce the reservation that causes throttling in the first place
- Consider queuing requests with SQS to smooth out spikes

## Monitoring Quota Usage

Set up CloudWatch alarms to catch throttling before it impacts users:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "BedrockThrottling" \
  --namespace "AWS/Bedrock" \
  --metric-name "InvocationThrottles" \
  --dimensions Name=ModelId,Value=us.anthropic.claude-sonnet-4-6 \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "YOUR_SNS_TOPIC_ARN"
```
