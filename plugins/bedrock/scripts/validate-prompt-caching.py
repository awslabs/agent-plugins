#!/usr/bin/env python3
"""
End-to-end validation of Bedrock prompt caching.

Sends two Converse API requests with identical cached content.
Verifies cache write on first request and cache read on second.

Usage:
    python3 validate-prompt-caching.py [--model-id MODEL_ID] [--region REGION] [--profile PROFILE] [--ttl TTL]
"""

import argparse
import sys
import time

try:
    import boto3
except ImportError:
    print("[FAIL] boto3 not installed. Run: pip3 install boto3")
    sys.exit(1)

MODEL_THRESHOLDS = {
    "anthropic.claude-sonnet-4-6": 2048,
    "anthropic.claude-opus-4-6": 4096,
    "anthropic.claude-haiku-4-5": 4096,
    "anthropic.claude-sonnet-4-5": 1024,
    "anthropic.claude-opus-4-5": 4096,
    "anthropic.claude-3-7-sonnet": 1024,
    "anthropic.claude-3-5-sonnet-v2": 1024,
    "anthropic.claude-3-5-haiku": 2048,
    "amazon.nova-pro": 1024,
    "amazon.nova-lite": 1536,
    "amazon.nova-micro": 1536,
}

HOUR_TTL_MODELS = [
    "anthropic.claude-sonnet-4-6",
    "anthropic.claude-sonnet-4-5",
    "anthropic.claude-opus-4-6",
    "anthropic.claude-opus-4-5",
    "anthropic.claude-haiku-4-5",
]


def get_min_tokens(model_id):
    """Look up minimum cache tokens for a model ID (handles cross-region prefixes)."""
    clean = model_id
    for prefix in ("us.", "eu.", "ap.", "global."):
        clean = clean.removeprefix(prefix)
    for key, threshold in MODEL_THRESHOLDS.items():
        if clean.startswith(key):
            return threshold
    return 2048


def supports_hour_ttl(model_id):
    clean = model_id
    for prefix in ("us.", "eu.", "ap.", "global."):
        clean = clean.removeprefix(prefix)
    return any(clean.startswith(m) for m in HOUR_TTL_MODELS)


def generate_system_prompt(min_tokens):
    """Generate a system prompt that exceeds the minimum token threshold.
    Roughly 1 token ~ 4 chars, so we generate 5x chars to be safe."""
    base = (
        "You are an expert software architect specializing in distributed systems, "
        "cloud-native applications, and API design. Your role is to review code and "
        "provide detailed, actionable feedback on scalability, maintainability, "
        "security, and performance. "
    )
    # ~3-4 chars per token on average; use 8x multiplier to safely exceed the threshold
    target_chars = min_tokens * 8
    repetitions = (target_chars // len(base)) + 1
    paragraphs = []
    topics = [
        "microservices architecture", "event-driven design", "database optimization",
        "caching strategies", "load balancing", "circuit breaker patterns",
        "API versioning", "observability and monitoring", "security best practices",
        "infrastructure as code", "container orchestration", "serverless patterns",
        "data pipeline design", "message queue architecture", "rate limiting",
        "authentication and authorization", "deployment strategies", "testing patterns",
        "error handling", "logging and tracing",
    ]
    for i in range(repetitions):
        topic = topics[i % len(topics)]
        paragraphs.append(
            f"When reviewing {topic}, consider the following principles: {base}"
            f"Apply these principles rigorously to {topic} implementations. "
            f"Look for common anti-patterns in {topic} and suggest concrete improvements. "
        )
    return "\n\n".join(paragraphs)[:target_chars]


def run_validation(model_id, region, profile, ttl):
    print("=== Bedrock Prompt Caching Validation ===")
    print(f"Model:   {model_id}")
    print(f"Region:  {region}")
    print(f"Profile: {profile}")
    print(f"TTL:     {ttl}")
    print()

    min_tokens = get_min_tokens(model_id)
    print(f"Minimum cache tokens for this model: {min_tokens}")

    if ttl == "1h" and not supports_hour_ttl(model_id):
        print(f"[WARN] Model {model_id} does not support 1-hour TTL. Falling back to default (5min).")
        ttl = None

    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client("bedrock-runtime")

    system_prompt = generate_system_prompt(min_tokens)
    approx_tokens = len(system_prompt) // 4
    print(f"Generated system prompt: ~{approx_tokens} tokens ({len(system_prompt)} chars)")
    print()

    system_blocks = [{"text": system_prompt}]
    cache_point = {"cachePoint": {"type": "default"}}
    if ttl:
        cache_point["cachePoint"]["ttl"] = ttl
    system_blocks.append(cache_point)

    messages = [
        {"role": "user", "content": [{"text": "What are the top 3 principles you follow?"}]}
    ]

    inference_config = {"maxTokens": 50}

    # Request 1: should write to cache
    print("--- Request 1 (expect cache write) ---")
    try:
        start = time.time()
        resp1 = client.converse(
            modelId=model_id,
            system=system_blocks,
            messages=messages,
            inferenceConfig=inference_config,
        )
        latency1 = (time.time() - start) * 1000

        usage1 = resp1.get("usage", {})
        cache_write = usage1.get("cacheWriteInputTokens", 0)
        cache_read = usage1.get("cacheReadInputTokens", 0)
        input_tokens = usage1.get("inputTokens", 0)

        print(f"  Latency:           {latency1:.0f}ms")
        print(f"  Input tokens:      {input_tokens}")
        print(f"  Cache write:       {cache_write}")
        print(f"  Cache read:        {cache_read}")

        if cache_write > 0:
            print(f"  [PASS] Cache write confirmed ({cache_write} tokens written)")
        elif cache_read > 0:
            print(f"  [PASS] Cache already populated from prior run ({cache_read} tokens read)")
        else:
            print(f"  [WARN] No cache activity detected. Content may be below {min_tokens} token threshold.")
    except Exception as e:
        print(f"  [FAIL] Request 1 failed: {e}")
        return 1

    print()

    # Brief pause to ensure cache is available
    time.sleep(1)

    # Request 2: should read from cache
    print("--- Request 2 (expect cache read) ---")
    try:
        start = time.time()
        resp2 = client.converse(
            modelId=model_id,
            system=system_blocks,
            messages=messages,
            inferenceConfig=inference_config,
        )
        latency2 = (time.time() - start) * 1000

        usage2 = resp2.get("usage", {})
        cache_write2 = usage2.get("cacheWriteInputTokens", 0)
        cache_read2 = usage2.get("cacheReadInputTokens", 0)
        input_tokens2 = usage2.get("inputTokens", 0)

        print(f"  Latency:           {latency2:.0f}ms")
        print(f"  Input tokens:      {input_tokens2}")
        print(f"  Cache write:       {cache_write2}")
        print(f"  Cache read:        {cache_read2}")

        if cache_read2 > 0:
            print(f"  [PASS] Cache read confirmed ({cache_read2} tokens from cache)")
        else:
            print(f"  [FAIL] No cache read detected. Cache may not be working.")
            return 1
    except Exception as e:
        print(f"  [FAIL] Request 2 failed: {e}")
        return 1

    print()

    # Summary
    print("=== Results ===")
    latency_improvement = ((latency1 - latency2) / latency1) * 100 if latency1 > 0 else 0
    print(f"  Latency improvement:  {latency_improvement:.1f}% ({latency1:.0f}ms -> {latency2:.0f}ms)")
    print(f"  Cache tokens:         {cache_read2} tokens served from cache")
    print(f"  [PASS] Prompt caching is working correctly.")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Validate Bedrock prompt caching")
    parser.add_argument("--model-id", default="us.anthropic.claude-sonnet-4-6")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--profile", required=True, help="AWS CLI profile name")
    parser.add_argument("--ttl", default=None, help="Cache TTL: '1h' or omit for default 5min")
    args = parser.parse_args()

    sys.exit(run_validation(args.model_id, args.region, args.profile, args.ttl))


if __name__ == "__main__":
    main()
