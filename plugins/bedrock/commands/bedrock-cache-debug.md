---
name: bedrock-cache-debug
description: "Diagnose prompt caching issues: model support, thresholds, TTL, and cost analysis"
---

# Bedrock Cache Debugger

Run 6 automated diagnostic tests to identify exactly why prompt caching is not working or is underperforming.

## Required Permissions

```json
{
  "Effect": "Allow",
  "Action": ["bedrock:Converse"],
  "Resource": "arn:aws:bedrock:<REGION>::foundation-model/<MODEL_ID>"
}
```

## Step 1: Run Cache Diagnostics

Ask the user which model they're using (default: Claude Sonnet 4.6).

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/debug-prompt-cache.py --model-id <MODEL_ID> --region <REGION>
```

The 6 tests:

1. **Model Support** — Does the model support caching? (silently ignored if not)
2. **Token Threshold** — Is content above the minimum? (silently ignored if below)
3. **Cache Write/Read** — Does the cache write-then-read cycle work?
4. **Prefix Sensitivity** — Demonstrates that even small content changes break the cache
5. **TTL Behavior** — Confirms cache persists within the TTL window
6. **Break-Even** — How many requests per TTL window before caching saves money?

## Step 2: Diagnose Failures

If any test fails, load the reference doc for targeted guidance:

Load `${CLAUDE_PLUGIN_ROOT}/skills/bedrock/references/prompt-caching.md` and focus on:

- "Why Isn't My Cache Working?" for the specific failure mode
- "Preventing Cache Fragmentation" if prefix sensitivity is the issue
- "Break-Even Analysis" if the cost math doesn't work for their use case

## Step 3: Recommend Strategy

Based on the results, advise on:

- Simplified vs explicit caching for their model
- 5-minute vs 1-hour TTL for their request pattern
- Whether caching is cost-effective at their request volume
