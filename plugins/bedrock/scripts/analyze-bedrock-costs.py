#!/usr/bin/env python3
"""
Bedrock cost analysis using AWS Cost Explorer.

Queries Cost Explorer for actual billed amounts filtered by Amazon Bedrock.
No hardcoded pricing — all cost data comes directly from your AWS bill.

Prerequisites:
    - Cost Explorer must be enabled in the AWS account (free, but not on by default).
      Enable via: AWS Console > Billing > Cost Explorer > Enable Cost Explorer

Required IAM permissions:
    ce:GetCostAndUsage (Resource: *)

Usage:
    python3 analyze-bedrock-costs.py [--region REGION] [--profile PROFILE] [--period DAYS] [--group-by model]
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


def get_bedrock_costs(session, period_days, group_by_model=False):
    """Query Cost Explorer for Bedrock costs."""
    # Cost Explorer endpoint is always us-east-1
    ce = session.client("ce", region_name="us-east-1")

    end_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    start_date = (datetime.now(timezone.utc) - timedelta(days=period_days)).strftime("%Y-%m-%d")

    filter_expr = {
        "Dimensions": {
            "Key": "SERVICE",
            "Values": ["Amazon Bedrock"],
        }
    }

    group_by = []
    if group_by_model:
        group_by = [{"Type": "DIMENSION", "Key": "USAGE_TYPE"}]

    try:
        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": start_date, "End": end_date},
            Granularity="DAILY",
            Metrics=["UnblendedCost", "UsageQuantity"],
            Filter=filter_expr,
            GroupBy=group_by if group_by else None,
        ) if group_by else ce.get_cost_and_usage(
            TimePeriod={"Start": start_date, "End": end_date},
            Granularity="DAILY",
            Metrics=["UnblendedCost", "UsageQuantity"],
            Filter=filter_expr,
        )
        return resp
    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        if error_code == "AccessDeniedException":
            print("[FAIL] Access denied to Cost Explorer.")
            print("       Ensure your IAM role has ce:GetCostAndUsage permission.")
            print()
            print("  Minimum IAM policy:")
            print('  {"Effect": "Allow", "Action": "ce:GetCostAndUsage", "Resource": "*"}')
            sys.exit(1)
        elif "not subscribed" in str(e).lower() or "not enabled" in str(e).lower():
            print("[FAIL] Cost Explorer is not enabled in this account.")
            print("       Enable it: AWS Console > Billing > Cost Explorer > Enable Cost Explorer")
            print("       It takes up to 24 hours to activate after enabling.")
            sys.exit(1)
        else:
            raise


def print_summary_report(period_days, response):
    """Print aggregate Bedrock cost summary."""
    print("=== Bedrock Cost Report (AWS Cost Explorer) ===")
    print(f"Period:  Last {period_days} day(s)")
    print(f"Source:  AWS Cost Explorer (actual billed amounts)")
    print()

    total_cost = 0.0
    daily_costs = []

    for result in response.get("ResultsByTime", []):
        date = result["TimePeriod"]["Start"]
        amount = float(result["Total"]["UnblendedCost"]["Amount"])
        total_cost += amount
        if amount > 0:
            daily_costs.append((date, amount))

    if total_cost == 0:
        print("  [INFO] No Bedrock charges found for this period.")
        print("  Cost Explorer data can take up to 24 hours to appear.")
        print()
        print("  For token-level usage metrics, run /bedrock-usage instead.")
        return 0

    print("--- Total Spend ---")
    print(f"  Amazon Bedrock:       ${total_cost:>10.2f}")
    if daily_costs:
        avg_daily = total_cost / len(daily_costs)
        print(f"  Daily average:        ${avg_daily:>10.2f}")
    print()

    if daily_costs:
        print("--- Daily Breakdown ---")
        for date, amount in sorted(daily_costs):
            print(f"  {date}:  ${amount:>10.4f}")
        print()

    print("--- Next Steps ---")
    print("  Run /bedrock-usage for token-level consumption metrics.")
    print("  Run /bedrock-quota to check for max_tokens waste.")
    print(f"  Current pricing: https://aws.amazon.com/bedrock/pricing/")
    print()

    return 0


def print_grouped_report(period_days, response):
    """Print Bedrock costs grouped by usage type (model)."""
    print("=== Bedrock Cost Report by Usage Type (AWS Cost Explorer) ===")
    print(f"Period:  Last {period_days} day(s)")
    print(f"Source:  AWS Cost Explorer (actual billed amounts)")
    print()

    usage_totals = {}
    grand_total = 0.0

    for result in response.get("ResultsByTime", []):
        for group in result.get("Groups", []):
            usage_type = group["Keys"][0]
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                usage_totals[usage_type] = usage_totals.get(usage_type, 0) + amount
                grand_total += amount

    if not usage_totals:
        print("  [INFO] No Bedrock charges found for this period.")
        print("  Cost Explorer data can take up to 24 hours to appear.")
        return 0

    print("--- Cost by Usage Type ---")
    for usage_type, amount in sorted(usage_totals.items(), key=lambda x: x[1], reverse=True):
        pct = (amount / grand_total * 100) if grand_total > 0 else 0
        print(f"  {usage_type:<55} ${amount:>10.4f}  ({pct:>5.1f}%)")
    print(f"  {'─' * 75}")
    print(f"  {'Total':<55} ${grand_total:>10.4f}")
    print()

    print("--- Next Steps ---")
    print("  Run /bedrock-usage for token-level consumption metrics.")
    print(f"  Current pricing: https://aws.amazon.com/bedrock/pricing/")
    print()

    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Bedrock costs from AWS Cost Explorer"
    )
    parser.add_argument("--region", default="us-east-1",
                        help="AWS region for session (default: us-east-1)")
    parser.add_argument("--profile", required=True,
                        help="AWS CLI profile name")
    parser.add_argument("--period", type=int, default=7,
                        help="Analysis period in days (default: 7)")
    parser.add_argument("--group-by", choices=["model"], default=None,
                        help="Group costs by usage type (model)")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile, region_name=args.region)

    group_by_model = args.group_by == "model"
    response = get_bedrock_costs(session, args.period, group_by_model=group_by_model)

    if group_by_model:
        exit_code = print_grouped_report(args.period, response)
    else:
        exit_code = print_summary_report(args.period, response)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
