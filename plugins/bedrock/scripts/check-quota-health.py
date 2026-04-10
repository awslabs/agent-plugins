#!/usr/bin/env python3
"""
Bedrock quota health check and max_tokens optimization analysis.

Queries AWS Service Quotas and CloudWatch to diagnose quota utilization,
detect the max_tokens pre-reservation trap, and generate data for quota
increase requests.

Usage:
    python3 check-quota-health.py [--model-id MODEL_ID] [--region REGION] [--profile PROFILE] [--period HOURS]
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

# Burndown rate: Claude 3.7+ uses 5x for output tokens; all others use 1x.
# See: https://docs.aws.amazon.com/bedrock/latest/userguide/quotas-token-burndown.html
BURNDOWN_5X_MODELS = [
    "anthropic.claude-sonnet-4-6",
    "anthropic.claude-opus-4-6",
    "anthropic.claude-haiku-4-5",
    "anthropic.claude-sonnet-4-5",
    "anthropic.claude-opus-4-5",
    "anthropic.claude-3-7-sonnet",
]

# Default max_tokens when not explicitly set by the developer
DEFAULT_MAX_TOKENS = {
    "anthropic.claude-sonnet-4-6": 64000,
    "anthropic.claude-opus-4-6": 64000,
    "anthropic.claude-haiku-4-5": 64000,
    "anthropic.claude-sonnet-4-5": 64000,
    "anthropic.claude-opus-4-5": 64000,
    "anthropic.claude-3-7-sonnet": 64000,
    "anthropic.claude-3-5-sonnet-v2": 8192,
    "anthropic.claude-3-5-haiku": 8192,
    "amazon.nova-pro": 5120,
    "amazon.nova-lite": 5120,
    "amazon.nova-micro": 5120,
}


def strip_cross_region_prefix(model_id):
    clean = model_id
    for prefix in ("us.", "eu.", "ap.", "global."):
        clean = clean.removeprefix(prefix)
    return clean


def get_burndown_rate(model_id):
    """Return output token burndown multiplier for quota calculation."""
    clean = strip_cross_region_prefix(model_id)
    for model in BURNDOWN_5X_MODELS:
        if clean.startswith(model):
            return 5
    return 1


def get_default_max_tokens(model_id):
    clean = strip_cross_region_prefix(model_id)
    for key, val in DEFAULT_MAX_TOKENS.items():
        if clean.startswith(key):
            return val
    return 4096


def model_display_name(model_id):
    """Map model ID to the name AWS uses in Service Quotas."""
    clean = strip_cross_region_prefix(model_id)
    name_map = {
        "anthropic.claude-sonnet-4-6": "Claude Sonnet 4.6",
        "anthropic.claude-opus-4-6": "Claude Opus 4.6",
        "anthropic.claude-haiku-4-5": "Claude Haiku 4.5",
        "anthropic.claude-sonnet-4-5": "Claude Sonnet 4.5 V1",
        "anthropic.claude-opus-4-5": "Claude Opus 4.5",
        "anthropic.claude-3-7-sonnet": "Claude 3.7 Sonnet",
        "anthropic.claude-3-5-sonnet-v2": "Claude 3.5 Sonnet V2",
        "anthropic.claude-3-5-haiku": "Claude 3.5 Haiku",
        "amazon.nova-pro": "Amazon Nova Pro",
        "amazon.nova-lite": "Amazon Nova Lite",
        "amazon.nova-micro": "Amazon Nova Micro",
    }
    for key, name in name_map.items():
        if clean.startswith(key):
            return name
    return clean


def get_quota_limits(session, region, model_id):
    """Query Service Quotas for Bedrock TPM and RPM limits."""
    sq = session.client("service-quotas", region_name=region)
    quotas = {}

    display_name = model_display_name(model_id).lower()
    # Build tight search terms from the model's display name
    # e.g., "Claude Sonnet 4.6" -> match only quotas with that exact model name
    try:
        paginator = sq.get_paginator("list_service_quotas")
        for page in paginator.paginate(ServiceCode="bedrock"):
            for q in page.get("Quotas", []):
                name_lower = q["QuotaName"].lower()
                if not any(kw in name_lower for kw in ["tokens per minute", "requests per minute"]):
                    continue
                # Match against the specific model display name
                if display_name in name_lower:
                    quotas[q["QuotaName"]] = {
                        "value": q["Value"],
                        "code": q["QuotaCode"],
                        "adjustable": q.get("Adjustable", False),
                    }
    except ClientError as e:
        if "NoSuchResourceException" in str(e) or "AccessDeniedException" in str(e):
            pass
        else:
            raise

    return quotas


def get_usage_metrics(session, region, model_id, period_hours):
    """Query CloudWatch for Bedrock token usage metrics."""
    cw = session.client("cloudwatch", region_name=region)
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=period_hours)
    period = 300 if period_hours <= 24 else 3600  # 5min or 1hr granularity

    metrics_config = {
        "InputTokenCount": ["Sum", "Average", "Maximum"],
        "OutputTokenCount": ["Sum", "Average", "Maximum"],
        "Invocations": ["Sum"],
        "InvocationLatency": ["Average", "Maximum"],
    }

    results = {}
    for metric_name, stats in metrics_config.items():
        try:
            resp = cw.get_metric_statistics(
                Namespace="AWS/Bedrock",
                MetricName=metric_name,
                Dimensions=[{"Name": "ModelId", "Value": model_id}],
                StartTime=start_time,
                EndTime=end_time,
                Period=period,
                Statistics=stats,
            )
            datapoints = resp.get("Datapoints", [])
            if datapoints:
                results[metric_name] = {
                    "datapoints": sorted(datapoints, key=lambda x: x["Timestamp"]),
                    "count": len(datapoints),
                }
                for stat in stats:
                    values = [d[stat] for d in datapoints if stat in d]
                    if values:
                        results[metric_name][f"{stat}_all"] = values
                        results[metric_name][stat] = sum(values) / len(values) if stat == "Average" else (
                            sum(values) if stat == "Sum" else max(values)
                        )
        except ClientError:
            pass

    return results


def analyze(model_id, metrics, burndown_rate, default_max_tokens, period_hours):
    """Analyze metrics and produce recommendations."""
    recommendations = []
    analysis = {}

    total_invocations = metrics.get("Invocations", {}).get("Sum", 0)
    total_input = metrics.get("InputTokenCount", {}).get("Sum", 0)
    total_output = metrics.get("OutputTokenCount", {}).get("Sum", 0)

    if total_invocations == 0:
        return analysis, recommendations

    avg_input = total_input / total_invocations
    avg_output = total_output / total_invocations

    # Estimate p90 output from maximum average per period
    max_avg_output = metrics.get("OutputTokenCount", {}).get("Maximum", avg_output)
    p90_output_estimate = max_avg_output  # Conservative: use max observed per-period average

    analysis["avg_input_tokens"] = avg_input
    analysis["avg_output_tokens"] = avg_output
    analysis["p90_output_estimate"] = p90_output_estimate
    analysis["total_invocations"] = total_invocations

    # max_tokens trap analysis
    recommended_max_tokens = int(p90_output_estimate * 1.5)
    recommended_max_tokens = max(recommended_max_tokens, 256)

    reserved_with_default = avg_input + (burndown_rate * default_max_tokens)
    reserved_with_optimal = avg_input + (burndown_rate * recommended_max_tokens)
    actual_usage = avg_input + (burndown_rate * avg_output)

    analysis["default_max_tokens"] = default_max_tokens
    analysis["recommended_max_tokens"] = recommended_max_tokens
    analysis["reserved_with_default"] = reserved_with_default
    analysis["reserved_with_optimal"] = reserved_with_optimal
    analysis["actual_usage"] = actual_usage

    waste_ratio = (reserved_with_default - actual_usage) / reserved_with_default if reserved_with_default > 0 else 0
    analysis["waste_ratio"] = waste_ratio

    if waste_ratio > 0.5:
        recommendations.append({
            "severity": "HIGH",
            "title": "Set max_tokens to reduce quota waste",
            "detail": (
                f"Default max_tokens ({default_max_tokens:,}) reserves {reserved_with_default:,.0f} quota tokens/request "
                f"(with {burndown_rate}x burndown), but actual usage is only {actual_usage:,.0f}. "
                f"Setting max_tokens to {recommended_max_tokens:,} would reduce reservation to {reserved_with_optimal:,.0f} "
                f"({waste_ratio:.0%} less waste)."
            ),
        })

    if burndown_rate > 1:
        recommendations.append({
            "severity": "INFO",
            "title": f"This model uses {burndown_rate}x output token burndown",
            "detail": (
                f"Each output token consumes {burndown_rate} tokens from your quota. "
                f"With avg {avg_output:,.0f} output tokens/request, that's {avg_output * burndown_rate:,.0f} quota tokens "
                f"for output alone. This is a quota management concern, not a billing concern."
            ),
        })

    # Cross-region inference check
    clean = strip_cross_region_prefix(model_id)
    if model_id == clean:
        recommendations.append({
            "severity": "MED",
            "title": "Consider cross-region inference for higher throughput",
            "detail": (
                f"You're using a bare model ID '{model_id}'. Claude models require a cross-region "
                f"prefix (e.g., 'us.{clean}'). Use the prefixed model ID for access, higher "
                f"throughput, and automatic failover. Run /bedrock-validate-model-access to test."
            ),
        })

    # Peak TPM analysis
    input_per_period = metrics.get("InputTokenCount", {}).get("Sum_all", [])
    output_per_period = metrics.get("OutputTokenCount", {}).get("Sum_all", [])
    if input_per_period and output_per_period:
        # Calculate tokens per minute from 5-min period sums
        period_minutes = 5 if period_hours <= 24 else 60
        tpm_values = []
        for i_dp, o_dp in zip(
            metrics["InputTokenCount"]["datapoints"],
            metrics["OutputTokenCount"]["datapoints"]
        ):
            tokens_in_period = i_dp.get("Sum", 0) + o_dp.get("Sum", 0) * burndown_rate
            tpm_values.append(tokens_in_period / period_minutes)

        if tpm_values:
            analysis["peak_tpm"] = max(tpm_values)
            analysis["avg_tpm"] = sum(tpm_values) / len(tpm_values)

    return analysis, recommendations


def generate_quota_increase_data(analysis, model_id, region, period_hours):
    """Generate the data AWS requires for quota increase requests."""
    data = {
        "model_id": model_id,
        "region": region,
        "observation_period": f"Last {period_hours} hours",
        "total_requests": int(analysis.get("total_invocations", 0)),
        "avg_input_tokens_per_request": int(analysis.get("avg_input_tokens", 0)),
        "avg_output_tokens_per_request": int(analysis.get("avg_output_tokens", 0)),
        "steady_state_tpm": int(analysis.get("avg_tpm", 0)),
        "peak_tpm": int(analysis.get("peak_tpm", 0)),
    }
    return data


def print_report(model_id, region, period_hours, burndown_rate, quotas, metrics, analysis, recommendations):
    print("=== Bedrock Quota Health Check ===")
    print(f"Model:   {model_id}")
    print(f"Region:  {region}")
    print(f"Period:  Last {period_hours} hours")
    print(f"Burndown rate: {burndown_rate}x for output tokens")
    print()

    # Quota limits
    print("--- Quota Limits ---")
    if quotas:
        for name, info in quotas.items():
            adjustable = " (adjustable)" if info["adjustable"] else ""
            print(f"  {name}: {info['value']:,.0f}{adjustable}")
    else:
        print("  [INFO] Could not retrieve quota limits. Check service-quotas:ListServiceQuotas permission.")
        print("  View quotas: https://console.aws.amazon.com/servicequotas/home/services/bedrock/quotas")
    print()

    # Usage metrics
    print("--- Current Usage ---")
    total_invocations = metrics.get("Invocations", {}).get("Sum", 0)
    if total_invocations == 0:
        print("  [INFO] No CloudWatch metrics found for this model/region/period.")
        print("  This is normal for new accounts or if model invocation logging is not yet active.")
        print("  Metrics appear automatically after your first Bedrock API call.")
        print()
        print("=== Summary ===")
        print("  [INFO] No usage data to analyze. Run some Bedrock requests first, then re-run this check.")
        return 0

    print(f"  Total requests:       {total_invocations:,.0f}")
    print(f"  Avg input tokens:     {analysis.get('avg_input_tokens', 0):,.0f}")
    print(f"  Avg output tokens:    {analysis.get('avg_output_tokens', 0):,.0f}")
    if "peak_tpm" in analysis:
        print(f"  Peak TPM (estimated): {analysis['peak_tpm']:,.0f}")
        print(f"  Avg TPM:              {analysis['avg_tpm']:,.0f}")
    print()

    # max_tokens analysis
    print("--- max_tokens Analysis ---")
    default_mt = analysis.get("default_max_tokens", 0)
    rec_mt = analysis.get("recommended_max_tokens", 0)
    reserved_default = analysis.get("reserved_with_default", 0)
    actual = analysis.get("actual_usage", 0)
    waste = analysis.get("waste_ratio", 0)

    if waste > 0.5:
        print(f"  \033[1;33m[WARN]\033[0m Default max_tokens ({default_mt:,}) reserves {reserved_default:,.0f} quota tokens/request")
        print(f"         Actual usage is only {actual:,.0f} quota tokens/request ({waste:.0%} wasted)")
        print(f"         Recommendation: set max_tokens to {rec_mt:,}")
    elif waste > 0.2:
        print(f"  [INFO] max_tokens reservation is {waste:.0%} above actual usage. Consider setting to {rec_mt:,}")
    else:
        print(f"  \033[0;32m[PASS]\033[0m max_tokens appears well-sized for your workload")
    print()

    # Recommendations
    if recommendations:
        print("--- Recommendations ---")
        for i, rec in enumerate(recommendations, 1):
            severity_color = {"HIGH": "\033[0;31m", "MED": "\033[1;33m", "INFO": "\033[0;36m"}.get(rec["severity"], "")
            print(f"  {i}. {severity_color}[{rec['severity']}]\033[0m {rec['title']}")
            # Wrap detail text
            detail = rec["detail"]
            indent = "     "
            words = detail.split()
            line = indent
            for word in words:
                if len(line) + len(word) + 1 > 100:
                    print(line)
                    line = indent + word
                else:
                    line = line + " " + word if line.strip() else indent + word
            if line.strip():
                print(line)
            print()

    # Quota increase data
    if "peak_tpm" in analysis:
        qi_data = generate_quota_increase_data(analysis, model_id, region, period_hours)
        print("--- Quota Increase Request Data ---")
        print("  Copy-paste this data when requesting a quota increase via AWS Service Quotas console:")
        print()
        for key, val in qi_data.items():
            label = key.replace("_", " ").title()
            print(f"  {label}: {val:,}" if isinstance(val, int) else f"  {label}: {val}")
        print()
        print("  Request quotas: https://console.aws.amazon.com/servicequotas/home/services/bedrock/quotas")
    print()

    # Summary
    print("=== Summary ===")
    high_count = sum(1 for r in recommendations if r["severity"] == "HIGH")
    med_count = sum(1 for r in recommendations if r["severity"] == "MED")
    if high_count > 0:
        print(f"  \033[1;33m[WARN]\033[0m {high_count} high-priority optimization(s) found. See recommendations above.")
        return 1
    elif med_count > 0:
        print(f"  [INFO] {med_count} suggestion(s) for improvement. See recommendations above.")
        return 0
    else:
        print("  \033[0;32m[PASS]\033[0m Quota utilization looks healthy.")
        return 0


def main():
    parser = argparse.ArgumentParser(
        description="Check Bedrock quota health and detect max_tokens waste"
    )
    parser.add_argument("--model-id", default="us.anthropic.claude-sonnet-4-6",
                        help="Bedrock model ID (default: us.anthropic.claude-sonnet-4-6)")
    parser.add_argument("--region", default="us-east-1",
                        help="AWS region (default: us-east-1)")
    parser.add_argument("--profile", required=True,
                        help="AWS CLI profile name")
    parser.add_argument("--period", type=int, default=24,
                        help="Analysis period in hours (default: 24)")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    burndown_rate = get_burndown_rate(args.model_id)

    quotas = get_quota_limits(session, args.region, args.model_id)
    metrics = get_usage_metrics(session, args.region, args.model_id, args.period)
    analysis_result, recommendations = analyze(
        args.model_id, metrics, burndown_rate,
        get_default_max_tokens(args.model_id), args.period
    )

    exit_code = print_report(
        args.model_id, args.region, args.period,
        burndown_rate, quotas, metrics, analysis_result, recommendations
    )
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
