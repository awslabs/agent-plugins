#!/usr/bin/env python3
"""
Bedrock token usage analysis from CloudWatch metrics.

Queries CloudWatch for token consumption, invocation counts, and prompt caching
efficiency. Does not calculate costs — use /bedrock-costs for actual spend.

Required IAM permissions:
    cloudwatch:GetMetricStatistics (Resource: *)

Usage:
    python3 analyze-bedrock-usage.py [--model-id MODEL_ID] [--region REGION] [--profile PROFILE] [--period DAYS] [--all-models]
"""

import argparse
import sys
from datetime import datetime, timedelta, timezone

try:
    import boto3
    from botocore.exceptions import ClientError
except ImportError:
    print("[FAIL] boto3 not installed. Run: pip3 install boto3")
    sys.exit(1)

KNOWN_MODELS = [
    "anthropic.claude-sonnet-4-6",
    "anthropic.claude-opus-4-6",
    "anthropic.claude-haiku-4-5",
    "anthropic.claude-sonnet-4-5",
    "anthropic.claude-opus-4-5",
    "anthropic.claude-3-7-sonnet",
    "anthropic.claude-3-5-sonnet-v2",
    "anthropic.claude-3-5-haiku",
    "amazon.nova-pro",
    "amazon.nova-lite",
    "amazon.nova-micro",
]


def strip_prefix(model_id):
    clean = model_id
    for prefix in ("us.", "eu.", "ap.", "global."):
        clean = clean.removeprefix(prefix)
    return clean


def get_metric(cw, model_id, metric_name, start_time, end_time, period):
    """Query a single CloudWatch metric and return the sum."""
    try:
        resp = cw.get_metric_statistics(
            Namespace="AWS/Bedrock",
            MetricName=metric_name,
            Dimensions=[{"Name": "ModelId", "Value": model_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=period,
            Statistics=["Sum"],
        )
        datapoints = resp.get("Datapoints", [])
        return sum(d.get("Sum", 0) for d in datapoints)
    except ClientError:
        return 0


def get_all_metrics(session, region, model_id, period_days):
    """Fetch all token usage metrics for a model."""
    cw = session.client("cloudwatch", region_name=region)
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=period_days)
    period = 3600

    return {
        "input_tokens": get_metric(cw, model_id, "InputTokenCount", start_time, end_time, period),
        "output_tokens": get_metric(cw, model_id, "OutputTokenCount", start_time, end_time, period),
        "cache_read_tokens": get_metric(cw, model_id, "CacheReadInputTokenCount", start_time, end_time, period),
        "cache_write_tokens": get_metric(cw, model_id, "CacheWriteInputTokenCount", start_time, end_time, period),
        "invocations": get_metric(cw, model_id, "Invocations", start_time, end_time, period),
    }


def discover_active_models(session, region, period_days):
    """Find all models with CloudWatch metrics in the given period."""
    cw = session.client("cloudwatch", region_name=region)
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=period_days)

    active = []
    for base_model in KNOWN_MODELS:
        for prefix in ["", "us.", "eu.", "ap.", "global."]:
            model_id = f"{prefix}{base_model}"
            try:
                resp = cw.get_metric_statistics(
                    Namespace="AWS/Bedrock",
                    MetricName="Invocations",
                    Dimensions=[{"Name": "ModelId", "Value": model_id}],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=86400,
                    Statistics=["Sum"],
                )
                total = sum(d.get("Sum", 0) for d in resp.get("Datapoints", []))
                if total > 0:
                    active.append({"model_id": model_id, "invocations": int(total)})
            except ClientError:
                pass
    return active


def print_report(model_id, region, period_days, metrics):
    print(f"=== Bedrock Usage Report ===")
    print(f"Model:   {model_id}")
    print(f"Region:  {region}")
    print(f"Period:  Last {period_days} day(s)")
    print()

    if metrics["invocations"] == 0:
        print("  [INFO] No usage data found for this model/region/period.")
        print("  Metrics appear automatically after your first Bedrock API call.")
        print()
        return 0

    print("--- Invocations ---")
    print(f"  Total requests:       {metrics['invocations']:>12,.0f}")
    avg_input = metrics["input_tokens"] / max(metrics["invocations"], 1)
    avg_output = metrics["output_tokens"] / max(metrics["invocations"], 1)
    print(f"  Avg input tokens:     {avg_input:>12,.0f}")
    print(f"  Avg output tokens:    {avg_output:>12,.0f}")
    print()

    print("--- Token Consumption ---")
    print(f"  Input tokens:         {metrics['input_tokens']:>12,.0f}")
    print(f"  Output tokens:        {metrics['output_tokens']:>12,.0f}")
    total_tokens = metrics["input_tokens"] + metrics["output_tokens"]
    print(f"  Total tokens:         {total_tokens:>12,.0f}")
    print()

    total_cache = metrics["cache_read_tokens"] + metrics["cache_write_tokens"]
    if total_cache > 0:
        print("--- Prompt Caching ---")
        print(f"  Cache write tokens:   {metrics['cache_write_tokens']:>12,.0f}")
        print(f"  Cache read tokens:    {metrics['cache_read_tokens']:>12,.0f}")
        hit_ratio = metrics["cache_read_tokens"] / total_cache if total_cache > 0 else 0
        print(f"  Cache hit ratio:      {hit_ratio:>11.0%}")
        if hit_ratio < 0.5:
            print(f"  \033[1;33m[WARN]\033[0m Low cache hit ratio — more writes than reads.")
            print(f"         Run /bedrock-cache-debug to diagnose.")
        elif hit_ratio >= 0.8:
            print(f"  \033[0;32m[GOOD]\033[0m High cache hit ratio — caching is working well.")
        print()
    else:
        if metrics["input_tokens"] > 100000:
            print("--- Prompt Caching ---")
            print(f"  \033[1;33m[WARN]\033[0m No caching detected on {metrics['invocations']:,.0f} requests.")
            print(f"         Run /bedrock-cache to enable prompt caching.")
            print()

    print("--- For Cost Analysis ---")
    print(f"  Run /bedrock-costs to see actual spend from AWS Cost Explorer.")
    print(f"  Current pricing: https://aws.amazon.com/bedrock/pricing/")
    print()

    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Bedrock token usage from CloudWatch metrics"
    )
    parser.add_argument("--model-id", default="us.anthropic.claude-sonnet-4-6",
                        help="Bedrock model ID (default: us.anthropic.claude-sonnet-4-6)")
    parser.add_argument("--region", default="us-east-1",
                        help="AWS region (default: us-east-1)")
    parser.add_argument("--profile", required=True,
                        help="AWS CLI profile name")
    parser.add_argument("--period", type=int, default=7,
                        help="Analysis period in days (default: 7)")
    parser.add_argument("--all-models", action="store_true",
                        help="Scan all models with CloudWatch metrics")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile, region_name=args.region)

    if args.all_models:
        print("=== Discovering Active Models ===")
        print(f"Region:  {args.region}")
        print(f"Period:  Last {args.period} day(s)")
        print()

        active = discover_active_models(session, args.region, args.period)
        if not active:
            print("  [INFO] No models with traffic found in this region/period.")
            sys.exit(0)

        print(f"  Found {len(active)} active model(s):")
        for m in sorted(active, key=lambda x: x["invocations"], reverse=True):
            print(f"    {m['model_id']}: {m['invocations']:,} invocations")
        print()

        for m in sorted(active, key=lambda x: x["invocations"], reverse=True):
            metrics = get_all_metrics(session, args.region, m["model_id"], args.period)
            print_report(m["model_id"], args.region, args.period, metrics)
    else:
        metrics = get_all_metrics(session, args.region, args.model_id, args.period)
        exit_code = print_report(args.model_id, args.region, args.period, metrics)
        sys.exit(exit_code)


if __name__ == "__main__":
    main()
