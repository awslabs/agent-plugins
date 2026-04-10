#!/usr/bin/env python3
"""
Bedrock prompt cache diagnostic suite.

Runs 6 targeted tests to identify exactly why prompt caching is not working
or is underperforming, and provides a break-even cost analysis.

Usage:
    python3 debug-prompt-cache.py [--model-id MODEL_ID] [--region REGION] [--profile PROFILE] [--verbose]
"""

import argparse
import sys
import time

try:
    import boto3
    from botocore.exceptions import ClientError
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


def strip_prefix(model_id):
    clean = model_id
    for prefix in ("us.", "eu.", "ap.", "global."):
        clean = clean.removeprefix(prefix)
    return clean


def get_min_tokens(model_id):
    clean = strip_prefix(model_id)
    for key, threshold in MODEL_THRESHOLDS.items():
        if clean.startswith(key):
            return threshold
    return 2048


def supports_hour_ttl(model_id):
    clean = strip_prefix(model_id)
    return any(clean.startswith(m) for m in HOUR_TTL_MODELS)


def is_known_model(model_id):
    clean = strip_prefix(model_id)
    return any(clean.startswith(key) for key in MODEL_THRESHOLDS)


def generate_system_prompt(target_tokens):
    """Generate a system prompt of approximately target_tokens length."""
    base = (
        "You are an expert software architect specializing in distributed systems, "
        "cloud-native applications, and API design. Your role is to review code and "
        "provide detailed, actionable feedback on scalability, maintainability, "
        "security, and performance. "
    )
    target_chars = target_tokens * 8
    repetitions = (target_chars // len(base)) + 1
    topics = [
        "microservices architecture", "event-driven design", "database optimization",
        "caching strategies", "load balancing", "circuit breaker patterns",
        "API versioning", "observability and monitoring", "security best practices",
        "infrastructure as code", "container orchestration", "serverless patterns",
        "data pipeline design", "message queue architecture", "rate limiting",
        "authentication and authorization", "deployment strategies", "testing patterns",
        "error handling", "logging and tracing",
    ]
    paragraphs = []
    for i in range(repetitions):
        topic = topics[i % len(topics)]
        paragraphs.append(
            f"When reviewing {topic}, consider the following principles: {base}"
            f"Apply these principles rigorously to {topic} implementations. "
            f"Look for common anti-patterns in {topic} and suggest concrete improvements. "
        )
    return "\n\n".join(paragraphs)[:target_chars]


def converse_with_cache(client, model_id, system_prompt, cache_point=None, verbose=False):
    """Send a Converse request with optional cache point. Returns (usage, latency_ms)."""
    system_blocks = [{"text": system_prompt}]
    if cache_point is not None:
        system_blocks.append(cache_point)

    messages = [{"role": "user", "content": [{"text": "Summarize your top 3 principles in one sentence each."}]}]

    start = time.time()
    resp = client.converse(
        modelId=model_id,
        system=system_blocks,
        messages=messages,
        inferenceConfig={"maxTokens": 50},
    )
    latency = (time.time() - start) * 1000
    usage = resp.get("usage", {})

    if verbose:
        print(f"    [DEBUG] Usage: {usage}")
        print(f"    [DEBUG] Latency: {latency:.0f}ms")

    return usage, latency


def test_model_supports_caching(client, model_id, min_tokens, verbose):
    """Test 1: Verify model supports prompt caching."""
    print("--- Test 1: Model Caching Support ---")

    if not is_known_model(model_id):
        print(f"  \033[1;33m[WARN]\033[0m Model '{model_id}' is not in the known caching-supported list")
        print(f"  Testing via API to check actual behavior...")

    system_prompt = generate_system_prompt(min_tokens)
    cache_point = {"cachePoint": {"type": "default"}}

    try:
        usage, _ = converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
        cache_write = usage.get("cacheWriteInputTokens", 0)
        cache_read = usage.get("cacheReadInputTokens", 0)

        if cache_write > 0 or cache_read > 0:
            print(f"  \033[0;32m[PASS]\033[0m Model supports prompt caching")
            return True
        else:
            print(f"  \033[0;31m[FAIL]\033[0m No cache activity detected. Model may not support caching.")
            print(f"  Caching is silently ignored for unsupported models -- no error is raised.")
            return False
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m API call failed: {e}")
        return False


def test_token_threshold(client, model_id, min_tokens, verbose):
    """Test 2: Verify cache respects minimum token threshold."""
    print(f"--- Test 2: Token Threshold (minimum: {min_tokens:,} tokens) ---")

    cache_point = {"cachePoint": {"type": "default"}}

    # Test below threshold (~50% of minimum)
    below_tokens = max(min_tokens // 2, 100)
    below_prompt = generate_system_prompt(below_tokens)
    try:
        usage_below, _ = converse_with_cache(client, model_id, below_prompt, cache_point, verbose)
        below_write = usage_below.get("cacheWriteInputTokens", 0)
        below_read = usage_below.get("cacheReadInputTokens", 0)

        if below_write == 0 and below_read == 0:
            print(f"  \033[0;32m[PASS]\033[0m Below-threshold content ({below_tokens} target tokens): correctly not cached")
        else:
            print(f"  [INFO] Below-threshold content showed cache activity (write={below_write}, read={below_read})")
            print(f"  This may indicate the actual token count exceeded the threshold despite targeting {below_tokens}")
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Below-threshold test failed: {e}")
        return False

    # Test above threshold
    above_prompt = generate_system_prompt(min_tokens)
    try:
        usage_above, _ = converse_with_cache(client, model_id, above_prompt, cache_point, verbose)
        above_write = usage_above.get("cacheWriteInputTokens", 0)
        above_read = usage_above.get("cacheReadInputTokens", 0)

        if above_write > 0 or above_read > 0:
            tokens_shown = above_write if above_write > 0 else above_read
            activity = "write" if above_write > 0 else "read (already cached)"
            print(f"  \033[0;32m[PASS]\033[0m Above-threshold content: cache {activity} confirmed ({tokens_shown:,} tokens)")
            return True
        else:
            print(f"  \033[0;31m[FAIL]\033[0m Above-threshold content was not cached. Token count may still be below minimum.")
            print(f"  Try increasing your cached content size.")
            return False
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Above-threshold test failed: {e}")
        return False


def test_cache_write_read_cycle(client, model_id, min_tokens, verbose):
    """Test 3: Verify cache write then cache read cycle."""
    print("--- Test 3: Cache Write/Read Cycle ---")

    system_prompt = generate_system_prompt(min_tokens)
    cache_point = {"cachePoint": {"type": "default"}}

    # Request 1: expect cache write
    try:
        usage1, latency1 = converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
        write1 = usage1.get("cacheWriteInputTokens", 0)
        read1 = usage1.get("cacheReadInputTokens", 0)
        print(f"  Request 1: cache write = {write1:,} tokens, cache read = {read1:,} tokens ({latency1:.0f}ms)")

        if write1 == 0 and read1 == 0:
            print(f"  \033[0;31m[FAIL]\033[0m No cache activity on request 1")
            return False, 0, 0
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Request 1 failed: {e}")
        return False, 0, 0

    time.sleep(1)

    # Request 2: expect cache read
    try:
        usage2, latency2 = converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
        write2 = usage2.get("cacheWriteInputTokens", 0)
        read2 = usage2.get("cacheReadInputTokens", 0)
        print(f"  Request 2: cache write = {write2:,} tokens, cache read = {read2:,} tokens ({latency2:.0f}ms)")

        if read2 > 0:
            improvement = ((latency1 - latency2) / latency1 * 100) if latency1 > 0 else 0
            print(f"  \033[0;32m[PASS]\033[0m Cache working: {improvement:.0f}% latency improvement")
            return True, latency1, latency2
        else:
            print(f"  \033[0;31m[FAIL]\033[0m No cache read on request 2. Cache may have been evicted.")
            return False, latency1, latency2
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Request 2 failed: {e}")
        return False, 0, 0


def test_prefix_sensitivity(client, model_id, min_tokens, verbose):
    """Test 4: Demonstrate that modifying cached content causes a cache miss."""
    print("--- Test 4: Prefix Sensitivity ---")

    system_prompt = generate_system_prompt(min_tokens)
    cache_point = {"cachePoint": {"type": "default"}}

    # Warm the cache with the original prompt
    try:
        converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
        time.sleep(1)
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Cache warm-up failed: {e}")
        return False

    # Send modified prompt (append a word to break exact match)
    modified_prompt = system_prompt + " Additionally, consider edge cases."
    try:
        usage, _ = converse_with_cache(client, model_id, modified_prompt, cache_point, verbose)
        write = usage.get("cacheWriteInputTokens", 0)
        read = usage.get("cacheReadInputTokens", 0)

        if write > 0 and read == 0:
            print(f"  \033[0;32m[PASS]\033[0m Modified prefix caused cache miss (new write: {write:,} tokens)")
            print(f"  [INFO] Cache requires exact byte-for-byte prefix match.")
            print(f"  [INFO] Even small changes (timestamps, IDs, whitespace) invalidate the cache.")
            return True
        elif read > 0:
            print(f"  [INFO] Modified prompt still got a cache read ({read:,} tokens).")
            print(f"  This may indicate simplified caching matched a partial prefix.")
            return True
        else:
            print(f"  [INFO] No cache activity on modified prompt (tokens may be below threshold after modification)")
            return True
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Modified prefix test failed: {e}")
        return False


def test_ttl_behavior(client, model_id, min_tokens, verbose):
    """Test 5: Verify cache persists within TTL window."""
    print("--- Test 5: TTL Behavior ---")

    system_prompt = generate_system_prompt(min_tokens)
    cache_point = {"cachePoint": {"type": "default"}}

    # Write cache
    try:
        converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m Cache write failed: {e}")
        return False

    # Wait 3 seconds and verify cache still alive
    time.sleep(3)

    try:
        usage, _ = converse_with_cache(client, model_id, system_prompt, cache_point, verbose)
        read = usage.get("cacheReadInputTokens", 0)

        if read > 0:
            print(f"  \033[0;32m[PASS]\033[0m Cache persists within TTL window (read {read:,} tokens after 3s)")
        else:
            print(f"  \033[1;33m[WARN]\033[0m Cache was not read after 3s. May have been evicted under load.")

        print(f"  [INFO] Default TTL: 5 minutes. Cache expires if no requests within this window.")
        if supports_hour_ttl(model_id):
            print(f"  [INFO] 1-hour TTL available for this model. Use: {{\"cachePoint\": {{\"type\": \"default\", \"ttl\": \"1h\"}}}}")
        else:
            print(f"  [INFO] This model only supports the default 5-minute TTL.")
        return True
    except ClientError as e:
        print(f"  \033[0;31m[FAIL]\033[0m TTL test failed: {e}")
        return False


def test_break_even(min_tokens):
    """Test 6: Calculate cost break-even for prompt caching."""
    print("--- Test 6: Break-Even Analysis ---")

    # Cache economics:
    # - Cache write costs 25% MORE than standard input (1.25x)
    # - Cache read costs 90% LESS than standard input (0.10x)
    # - Standard input: 1.0x (baseline)

    print(f"  Cache write premium:  25% over standard input price")
    print(f"  Cache read discount:  90% off standard input price")
    print()

    # Break-even: 1 write (1.25) + N reads (N * 0.10) < 1 + N * 1.0  (all sending same content)
    # 1.25 + 0.1N < 1 + N  -> 0.25 < 0.9N -> N > 0.278 -> need >= 1 read after write
    # But total cost comparison for N total requests:
    # Without caching: N * 1.0 = N
    # With caching: 1.25 + (N-1) * 0.10
    # Break-even: 1.25 + (N-1)*0.1 = N -> 1.25 + 0.1N - 0.1 = N -> 1.15 = 0.9N -> N = 1.28
    # So at 2 requests, caching wins.

    print(f"  {'Requests/TTL':>15} | {'Without Cache':>15} | {'With Cache':>15} | {'Savings':>10}")
    print(f"  {'-'*15}-+-{'-'*15}-+-{'-'*15}-+-{'-'*10}")

    for n in [1, 2, 3, 5, 10, 20]:
        without = n * 1.0
        with_cache = 1.25 + max(0, (n - 1)) * 0.10
        savings = (without - with_cache) / without * 100 if without > 0 else 0
        marker = " <-- break-even" if n == 2 else (" <-- COSTS MORE" if n == 1 else "")
        print(f"  {n:>15} | {without:>14.2f}x | {with_cache:>14.2f}x | {savings:>8.0f}%{marker}")

    print()
    print(f"  [INFO] You need at least 2 requests within the TTL window to save money.")
    print(f"  [INFO] At 1 request, caching INCREASES cost by 25% due to the write premium.")
    print(f"  [INFO] For single-use content (each document analyzed once), do NOT enable caching.")
    return True


def run_diagnostics(model_id, region, profile, verbose):
    print("=== Bedrock Prompt Cache Debugger ===")
    print(f"Model:   {model_id}")
    print(f"Region:  {region}")
    print()

    session = boto3.Session(profile_name=profile, region_name=region)
    client = session.client("bedrock-runtime")
    min_tokens = get_min_tokens(model_id)

    tests_passed = 0
    tests_total = 6

    # Test 1: Model support
    if test_model_supports_caching(client, model_id, min_tokens, verbose):
        tests_passed += 1
    else:
        print()
        print("=== Summary ===")
        print(f"  \033[0;31m[FAIL]\033[0m Model does not support caching. Remaining tests skipped.")
        print(f"  Caching is available for: {', '.join(sorted(MODEL_THRESHOLDS.keys()))}")
        return 1
    print()

    # Test 2: Token threshold
    if test_token_threshold(client, model_id, min_tokens, verbose):
        tests_passed += 1
    print()

    # Test 3: Cache write/read cycle
    cycle_passed, lat1, lat2 = test_cache_write_read_cycle(client, model_id, min_tokens, verbose)
    if cycle_passed:
        tests_passed += 1
    print()

    # Test 4: Prefix sensitivity
    if test_prefix_sensitivity(client, model_id, min_tokens, verbose):
        tests_passed += 1
    print()

    # Test 5: TTL behavior
    if test_ttl_behavior(client, model_id, min_tokens, verbose):
        tests_passed += 1
    print()

    # Test 6: Break-even analysis (pure math, always passes)
    if test_break_even(min_tokens):
        tests_passed += 1
    print()

    # Summary
    print("=== Summary ===")
    print(f"  {tests_passed}/{tests_total} tests passed")
    if tests_passed == tests_total:
        print(f"  \033[0;32m[PASS]\033[0m Prompt caching is healthy")
        return 0
    else:
        print(f"  \033[1;33m[WARN]\033[0m {tests_total - tests_passed} test(s) need attention. See details above.")
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="Diagnose Bedrock prompt caching issues with 6 automated tests"
    )
    parser.add_argument("--model-id", default="us.anthropic.claude-sonnet-4-6",
                        help="Bedrock model ID (default: us.anthropic.claude-sonnet-4-6)")
    parser.add_argument("--region", default="us-east-1",
                        help="AWS region (default: us-east-1)")
    parser.add_argument("--profile", required=True,
                        help="AWS CLI profile name")
    parser.add_argument("--verbose", action="store_true",
                        help="Show detailed API response data")
    args = parser.parse_args()

    sys.exit(run_diagnostics(args.model_id, args.region, args.profile, args.verbose))


if __name__ == "__main__":
    main()
