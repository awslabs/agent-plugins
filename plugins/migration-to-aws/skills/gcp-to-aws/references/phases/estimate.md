# Phase 4: Estimate AWS Costs

## Step 0: Validate Design Output

Before pricing queries, validate inputs:

**0a. Validate `aws-design.json`:**

1. **File exists**: If missing, **STOP**. Output: "Phase 3 (Design) not completed. Run Phase 3 first."
2. **Valid JSON**: If parse fails, **STOP**. Output: "Design file corrupted (invalid JSON). Re-run Phase 3."
3. **Required fields**:
   - `clusters` array is not empty: If empty, **STOP**. Output: "No clusters in design. Re-run Phase 3."
   - Each cluster has `resources` array: If missing, **STOP**. Output: "Cluster [id] missing resources. Re-run Phase 3."
   - Each resource has `aws_service` field: If missing, **STOP**. Output: "Resource [address] missing aws_service. Re-run Phase 3."
   - Each resource has `aws_config` field: If missing, **STOP**. Output: "Resource [address] missing aws_config. Re-run Phase 3."

**0b. Validate `clarified.json`:**

1. **File exists**: If missing, **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."
2. **Valid JSON**: If parse fails, **STOP**. Output: "Clarified file corrupted (invalid JSON). Re-run Phase 2."

If all validations pass, proceed to Step 1.

## Step 1: Check Pricing Availability

Call MCP `awspricing` with `get_pricing_service_codes()`:

### Retry Logic

Attempt to reach awspricing with **up to 2 retries** (3 total attempts):

1. **Attempt 1**: Call `get_pricing_service_codes()`
2. **If timeout/error**: Wait 1 second, retry (Attempt 2)
3. **If still fails**: Wait 2 seconds, retry (Attempt 3)
4. **If all 3 attempts fail**: Proceed to fallback

### Success Path

- **If any attempt succeeds**: Use live AWS pricing for all estimates
- **Pricing source**: Mark as `live` in estimation.json

### Fallback Path

- **If all 3 attempts fail**:
  1. Load `shared/pricing-fallback.json`
  2. **Check staleness**:
     - Read `metadata.last_updated` (e.g., "2026-02-24")
     - Calculate days since update: `today - last_updated`
     - If > 60 days: Add to estimation report: "⚠️ Cached pricing data is >60 days old; accuracy may be significantly degraded"
     - If 30-60 days: Add to estimation report: "⚠️ Cached pricing data is 30-60 days old; accuracy may be reduced"
     - If ≤ 30 days: Add to estimation report: "Note: Using cached rates (±15-25% accuracy)"
  3. Log warning: "AWS pricing API unavailable; using cached rates from [last_updated]"
  4. **Display to user**: Add visible warning to estimation report with staleness notice
  5. **Pricing source**: Mark as `fallback` in estimation.json with note
  6. Proceed to Step 2

## Step 2: Extract Services from Design

Read `aws-design.json`. Build list of unique AWS services mapped:

- Fargate
- RDS (Aurora Serverless v2)
- S3
- ALB
- Lambda
- ECS
- VPC / NAT Gateway
- etc.

## Step 3: Query Pricing

For each service:

1. Determine usage scenario from `aws-design.json` config (e.g., Fargate: 0.5 CPU, 1 GB memory, assumed 24/7)
2. Query pricing and track source:
   - **If live API available**: Call awspricing with appropriate filters
     - Region: extracted from design (default `us-east-1`)
     - Service attributes: CPU, memory, storage, etc.
     - Mark: `pricing_source: "live"`
   - **If using fallback**: Look up in `shared/pricing-fallback.json`
     - Check if service exists in fallback data:
       - **If found**: Use cached price, mark: `pricing_source: "fallback"`
       - **If NOT found**:
         1. Add to `services_with_missing_fallback[]` in estimation.json
         2. Use conservative estimate (e.g., AWS average tier pricing or ask user)
         3. Mark: `pricing_source: "estimated"`
         4. Add warning: "Service [X] not in cached fallback data; cost estimated conservatively"
3. Calculate monthly cost per service

Handle 3 cost tiers (to show optimization range):

- **Premium**: Latest generation, highest availability (e.g., db.r6g, Fargate Spot disabled)
- **Balanced**: Standard generation, typical setup (e.g., db.t4g, Fargate on-demand)
- **Optimized**: Cost-minimized (e.g., db.t4g with reserved, Fargate Spot 70%)

## Step 4: Calculate Summary

**Monthly operational cost:**

```
Sum of all service monthly costs (Balanced tier)
```

**One-time migration cost:**

```
Development hours: X hours × $150/hour (assume 10-15 weeks)
Data transfer: Y GB × $0.02/GB (egress from GCP)
```

**ROI (vs GCP):**

Monthly GCP cost determination (in priority order):

1. **From inventory**: If `gcp-resource-inventory.json` contains pricing data, sum all service costs
2. **From clarified.json**: If user provided "current GCP monthly spend" in Phase 2 answers, use that value
3. **From user prompt**: If neither available, ask user: "What is your current monthly GCP spend? (This is used for ROI; provide best estimate)"
4. **Cannot calculate**: If user cannot provide, set `roi.status: "cannot_calculate"` and `roi.message: "GCP monthly cost unavailable. Provide your current GCP spend to calculate ROI."` Skip payback and savings calculations.

Then calculate:

```
Monthly GCP cost: (from above)
AWS monthly cost: (from Step 3)
Monthly savings: GCP - AWS
Payback period: One-time cost / Monthly savings (in months)
5-year savings: (Monthly savings × 60) - One-time cost
```

Add to assumptions: "GCP monthly cost: [SOURCE - actual, user estimate, or default]"

## Step 5: Write Estimation Output

Write `estimation.json` (schema must match `references/shared/output-schema.md`):

```json
{
  "pricing_source": {
    "status": "live|fallback",
    "message": "Using live AWS pricing API|Using cached rates from [date] (±15-25% accuracy)",
    "fallback_staleness": {
      "last_updated": "2026-02-24",
      "days_old": 3,
      "is_stale": false,
      "staleness_warning": null
    },
    "services_by_source": {
      "live": ["Fargate", "RDS Aurora", "S3", "ALB"],
      "fallback": [],
      "estimated": []
    },
    "services_with_missing_fallback": []
  },
  "monthly_costs": {
    "premium": { "total": 5000, "breakdown": {"Fargate": 1200, "RDS": 2500, ...} },
    "balanced": { "total": 3500, "breakdown": {"Fargate": 800, "RDS": 1800, ...} },
    "optimized": { "total": 2200, "breakdown": {"Fargate": 400, "RDS": 1200, ...} }
  },
  "one_time_costs": {
    "dev_hours": "150 hours @ $150/hr = $22,500",
    "data_transfer": "500 GB @ $0.02/GB = $10",
    "training": "Team AWS training = $5,000",
    "total": 27510
  },
  "roi": {
    "assumed_gcp_monthly": 4500,
    "aws_monthly_balanced": 3500,
    "monthly_savings": 1000,
    "payback_months": 27.51,
    "five_year_savings": 32490
  },
  "assumptions": [
    "24/7 workload usage",
    "No Reserved Instances",
    "No Spot instances (Balanced tier)",
    "Region: us-east-1",
    "GCP monthly cost: user estimate"
  ],
  "timestamp": "2026-02-26T14:30:00Z"
}
```

Write `estimation-report.md`:

```
# AWS Cost Estimation

## Monthly Operating Costs

### Balanced Tier (Recommended)
- Fargate: $800
- RDS Aurora: $1,800
- S3: $500
- ALB: $200
- NAT Gateway: $200
- **Total: $3,500/month**

### Comparison Tiers
- Premium: $5,000/month
- Optimized: $2,200/month

## One-Time Migration Costs
- Dev: 150 hours @ $150/hr = $22,500
- Data transfer: 500 GB @ $0.02/GB = $10
- Training: $5,000
- **Total: $27,510**

## ROI Analysis
- Assumed GCP cost: $4,500/month
- AWS Balanced: $3,500/month
- **Savings: $1,000/month**
- **Payback: 27.5 months**
- **5-year savings: $32,490**
```

## Step 6: Update Phase Status

Update `.phase-status.json`:

```json
{
  "phase": "estimate",
  "status": "completed",
  "timestamp": "2026-02-26T14:30:00Z",
  "version": "1.0.0"
}
```

Output to user: "Cost estimation complete. Balanced tier: $X/month, Payback: X months. Proceeding to Phase 5: Execution Plan."
