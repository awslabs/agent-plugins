# Prompt Caching on Amazon Bedrock

Prompt caching stores frequently used input content so subsequent requests can reuse it, reducing latency by up to 85% and costs by up to 90%.

## Two Approaches

### Simplified Cache Management (Claude Models Only)

A single `cachePoint` marker tells Bedrock to automatically check the preceding ~20 content blocks for cacheable content. No need to manually manage multiple checkpoints.

On the first request, `cacheWriteInputTokens` will be > 0 (cache populated).
On subsequent identical requests within the TTL, `cacheReadInputTokens` will be > 0 (cache hit).

### Explicit Cache Management (All Supported Models)

Place multiple `cachePoint` markers at specific positions for granular control. Supports mixed TTL (1h + 5min) for different content sections.

## Code Samples

For working code samples covering both approaches (Converse API and InvokeModel API), see the official AWS samples repository:

**https://github.com/aws-samples/amazon-bedrock-samples/tree/main/introduction-to-bedrock/prompt-caching**

The samples include:

- `converse_api/` — Model-agnostic examples using the Converse and ConverseStream APIs with `cachePoint` syntax
- `invoke_model_api/` — Model-specific examples using the InvokeModel API (Anthropic `cache_control` format, Nova native format)
- Mixed TTL notebooks demonstrating longer TTL checkpoints preceding shorter ones

## Key Concepts

### Cache Point Placement

The `cachePoint` is a standalone content block placed **after** the content to cache. In the Converse API, it looks like `{"cachePoint": {"type": "default"}}`. For 1-hour TTL, add `"ttl": "1h"`.

### TTL Configuration

| TTL             | Supported Models                                             | Use Case                             |
| --------------- | ------------------------------------------------------------ | ------------------------------------ |
| 5 min (default) | All supported models                                         | Dynamic content, short conversations |
| 1 hour          | Claude Sonnet 4.6, Opus 4.6, Sonnet 4.5, Opus 4.5, Haiku 4.5 | System prompts, reference docs       |

When using multiple cache points with different TTLs, longer durations must precede shorter ones.

### Response Fields

Cache metrics appear in the Converse API `usage` object:

- `cacheWriteInputTokens > 0`: Cache was populated (first request or cache expired)
- `cacheReadInputTokens > 0`: Cache was hit (subsequent requests within TTL)
- Both zero: Content didn't meet minimum threshold or caching not supported

For InvokeModel API (Anthropic format), the fields are `cache_creation_input_tokens` and `cache_read_input_tokens`.

## Minimum Token Thresholds

Content before a cache point must meet the model's minimum token count:

| Model                | Minimum Tokens |
| -------------------- | -------------- |
| Claude Sonnet 4.6    | 2,048          |
| Claude Opus 4.6      | 4,096          |
| Claude Opus 4.5      | 4,096          |
| Claude Haiku 4.5     | 4,096          |
| Claude Sonnet 4.5    | 1,024          |
| Claude Opus 4.1      | 1,024          |
| Claude Opus 4        | 1,024          |
| Claude Sonnet 4      | 1,024          |
| Claude 3.7 Sonnet    | 1,024          |
| Claude 3.5 Sonnet v2 | 1,024          |
| Claude 3.5 Haiku     | 2,048          |
| Amazon Nova Pro      | 1,024          |
| Amazon Nova Lite     | 1,536          |
| Amazon Nova Micro    | 1,536          |

If content is below the threshold, the cache point is ignored (no error, just no caching).

## What to Cache

**Good candidates (static, reused across requests):**

- System prompts
- Few-shot examples
- Reference documents / knowledge bases
- Tool definitions
- Long code files for review

**Poor candidates (change frequently):**

- User messages that vary each request
- Dynamic context that updates per call
- Very short content below the token threshold

## Why Isn't My Cache Working?

Prompt caching fails silently in several scenarios. Walk through this checklist:

1. **Is the model supported?** Caching is silently ignored for unsupported models. No error, no warning. Check the supported models table above.

2. **Does content exceed the minimum token threshold?** If content before the cache point is below the model's minimum (e.g., 1,024 for Claude Sonnet 4), the cache point is ignored. The request succeeds normally — you just don't get caching.

3. **Is the cached content identical between requests?** Cache keys are based on exact byte-for-byte prefix match. Even small changes invalidate the cache:
   - Timestamps or request IDs in the system prompt
   - Whitespace differences
   - Reordered JSON keys
   - Session tokens or user-specific content before the cache point

4. **Has the TTL expired?** Default TTL is 5 minutes. If more than 5 minutes pass between requests with the same prefix, the cache expires and the next request is a cache write (not a read).

5. **Is the cache point in the right place?** The `cachePoint` must be a separate content block placed **after** the content to cache, not embedded within it.

Run `/bedrock-cache-debug` for automated diagnosis of all these issues.

## Break-Even Analysis

Cache writes cost **25% more** than standard input tokens. Cache reads cost **90% less**. This means caching only saves money if you have enough reads per write.

| Requests per TTL Window | Cost Without Cache | Cost With Cache | Savings               |
| ----------------------- | ------------------ | --------------- | --------------------- |
| 1 (write only)          | 1.00x              | 1.25x           | **-25% (costs MORE)** |
| 2                       | 2.00x              | 1.35x           | 32%                   |
| 5                       | 5.00x              | 1.65x           | 67%                   |
| 10                      | 10.00x             | 2.15x           | 78%                   |
| 20                      | 20.00x             | 3.15x           | 84%                   |

**Key takeaway**: You need at least **2 requests within the TTL window** to break even. For single-use content (each document analyzed once), do NOT enable caching — it increases cost by 25%.

## Preventing Cache Fragmentation

Cache fragmentation occurs when "static" content varies slightly between requests, causing cache misses. Common causes and fixes:

- **Timestamps in system prompts**: Move timestamps AFTER the cache point.
- **Dynamic user context mixed with static content**: Separate static and dynamic parts.
- **Non-deterministic formatting**: Use sorted keys in JSON, consistent whitespace, and fixed-format strings.
- **Session-specific tokens**: Keep session IDs, user IDs, and auth tokens after the cache point.

## 1-Hour TTL

For content that rarely changes (system prompts, reference docs, tool definitions), 1-hour TTL reduces cache writes and keeps the cache alive across longer idle periods.

Supported models: Claude Sonnet 4.6, Opus 4.6, Sonnet 4.5, Opus 4.5, Haiku 4.5.

When to use 1-hour TTL:

- System prompts that don't change between sessions
- Reference documents loaded for RAG
- Tool definitions that are stable across requests
- Any content where 5 minutes between requests is too short

When to keep 5-minute TTL:

- Content that changes every few minutes
- High-frequency request patterns where 5 minutes is already sufficient
- When you want caches to expire quickly to pick up content updates

## Validation

Run the validation script to verify prompt caching works end-to-end:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt-caching.py --model-id us.anthropic.claude-sonnet-4-6
```

For detailed diagnostics, run the cache debugger:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/debug-prompt-cache.py --model-id us.anthropic.claude-sonnet-4-6
```
