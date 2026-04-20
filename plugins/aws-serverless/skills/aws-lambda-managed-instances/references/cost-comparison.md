# Lambda vs LMI Cost Comparison

## Pricing Components

**Standard Lambda:** $0.20/M requests + $0.0000166667/GB-sec (x86) or $0.0000133334 (ARM). Compute Savings Plans give ~17% discount on duration.

**LMI:** $0.20/M requests + EC2 instance cost (24/7) + 15% management fee on EC2 on-demand price. No per-request duration charge. Savings Plans/RIs discount up to 72% on EC2 compute. 15% fee always on on-demand price.

## Discount Comparison

| Option | Lambda discount | LMI discount |
|--------|----------------|--------------|
| On-demand | 0% | 0% |
| Compute Savings Plan (1yr) | ~17% on duration | ~40-50% on EC2 |
| Compute Savings Plan (3yr) | ~17% on duration | ~60-72% on EC2 |
| Reserved Instances (1yr) | N/A | ~40% on EC2 |
| Reserved Instances (3yr) | N/A | ~60-65% on EC2 |

Compute Savings Plans apply to both Lambda duration AND EC2 instances. One commitment can cover both.

## Calculation Formulas

```
# Lambda on-demand
duration_cost = requests × avg_duration_sec × memory_GB × $0.0000166667
request_cost  = requests × $0.20 / 1,000,000
total         = duration_cost + request_cost

# Lambda + Savings Plan (17% on duration)
total         = (duration_cost × 0.83) + request_cost

# LMI on-demand
ec2_cost      = num_instances × hourly_price × 730
mgmt_fee      = ec2_cost × 0.15
total         = ec2_cost + mgmt_fee + request_cost

# LMI + 3yr Savings Plan (65% discount on EC2)
total         = (ec2_cost × 0.35) + mgmt_fee + request_cost
```

## Comparison Table Template

Present this for every assessment:

```
| Component          | Lambda OD | Lambda+SP | LMI OD | LMI+3yr SP |
|--------------------|-----------|-----------|--------|------------|
| Requests           | $X        | $X        | $X     | $X         |
| Duration/compute   | $X        | $X        | $X     | $X         |
| Management fee     | —         | —         | $X     | $X         |
| Monthly total      | $X        | $X        | $X     | $X         |
| Annual total       | $X        | $X        | $X     | $X         |
| Savings vs Lambda  | baseline  | X%        | X%     | X%         |
```

## Worked Example

Node.js API, 100 req/s steady (259M req/mo), 200ms avg, 512 MB, x86:

| Scenario | Monthly | Annual | Savings |
|----------|---------|--------|---------|
| Lambda on-demand | $484 | $5,808 | baseline |
| Lambda + 3yr SP | $411 | $4,932 | 15% |
| LMI on-demand (3× m7i.large) | $288 | $3,456 | 40% |
| LMI + 3yr SP | $155 | $1,860 | 68% |

## When LMI is NOT Cheaper

- < 50M req/month (fixed 3-instance cost exceeds Lambda)
- Very short functions (< 100ms duration)
- Highly bursty, unpredictable traffic
- Workloads needing scale-to-zero
