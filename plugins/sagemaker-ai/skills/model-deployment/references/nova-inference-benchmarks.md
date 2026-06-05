---
description: >
  Real inference benchmark data for Nova Micro, Lite, and Lite 2 models across
  AWS GPU instances. The agent reads this file to provide measured cost, latency,
  and throughput numbers when helping customers choose inference configurations.
  Includes pricing, curated benchmarks, regression formulas, and data-quality caveats.
---

# Inference Benchmark Reference Data

All benchmarks below were collected using the **Nova SageMaker Inference container** deployed on SageMaker real-time endpoints.

**Container image** (must use this for Nova models):

- us-east-1: `708977205387.dkr.ecr.us-east-1.amazonaws.com/nova-inference-repo:SM-Inference-latest`
- us-west-2: `176779409107.dkr.ecr.us-west-2.amazonaws.com/nova-inference-repo:SM-Inference-latest`
- eu-west-2: `470633809225.dkr.ecr.eu-west-2.amazonaws.com/nova-inference-repo:SM-Inference-latest`

The SDK's `deploy(deploy_platform=DeployPlatform.SAGEMAKER)` selects the correct image automatically. For raw boto3 deploys, set the image URI explicitly in `create_model()`.

**Required environment variables** (set in `sagemaker_environment_variables` or `create_model` Environment):

- `CONTEXT_LENGTH` — max total token length (input + output) per request. Must match the benchmark context length.
- `MAX_CONCURRENCY` — max concurrent requests. Must match the benchmark concurrency.

**Supported model × instance × max concurrency**:

| Model       | Instance                                       | Max Context | Max Concurrency                    |
| ----------- | ---------------------------------------------- | ----------- | ---------------------------------- |
| Nova Micro  | ml.g5.12xlarge, ml.g6.12xlarge                 | 8k          | 32 (at 4k), 16 (at 8k)             |
| Nova Micro  | ml.g5.24xlarge, ml.g6.24xlarge, ml.g6.48xlarge | 8k          | 32                                 |
| Nova Micro  | ml.p5.48xlarge                                 | 24k         | 32 (at 8k), 2 (at 16k), 1 (at 24k) |
| Nova Lite   | ml.g6.48xlarge                                 | 8k          | 32 (at 4k), 16 (at 8k)             |
| Nova Lite   | ml.p5.48xlarge                                 | 24k         | 32 (at 8k), 2 (at 16k)             |
| Nova 2 Lite | ml.p5.48xlarge                                 | 24k         | 32 (at 8k), 2 (at 16k)             |

Only **full-rank custom models and LoRA-merged models** are supported on SageMaker. Unmerged LoRA adapters and base models must use Bedrock.

## Instance Pricing

SageMaker real-time inference pricing (us-west-2, on-demand):

| Instance    | $/hr    |
| ----------- | ------- |
| p5.48xlarge | $63.296 |
| g5.12xlarge | $7.090  |
| g5.24xlarge | $10.180 |
| g6.12xlarge | $5.752  |
| g6.24xlarge | $8.344  |
| g6.48xlarge | $16.688 |

---

## Curated Benchmark Table

### With RAI

| Model      | Instance    | Context | Conc | TTFT (ms) | TPOT (ms) | Throughput (tok/s) | $/1M tokens | Notes                   |
| ---------- | ----------- | ------- | ---- | --------- | --------- | ------------------ | ----------- | ----------------------- |
| Nova Micro | p5.48xlarge | 8k      | 1    | 69        | 2.04      | 444                | $39.60      | Baseline single-request |
| Nova Micro | p5.48xlarge | 8k      | 8    | 88        | 2.84      | 2562               | $6.86       | Good mid-concurrency    |
| Nova Micro | p5.48xlarge | 8k      | 16   | 102       | 3.64      | 4000               | $4.40       | Near-peak throughput    |
| Nova Micro | g5.12xlarge | 4k      | 1    | 167       | 10.3      | 92                 | $21.41      | Budget baseline         |
| Nova Micro | g5.12xlarge | 4k      | 8    | 371       | 29        | 266                | $7.40       | TPOT degrades fast      |
| Nova Micro | g6.12xlarge | 4k      | 1    | 135       | 14        | 69                 | $23.16      | Single-request baseline |
| Nova Micro | g6.12xlarge | 4k      | 8    | 260       | 28        | 280                | $5.71       | Reasonable mid-load     |
| Nova Micro | g6.48xlarge | 8k      | 1    | 145       | 9.3       | 103                | $45.01      | Single-request baseline |
| Nova Micro | g6.48xlarge | 8k      | 8    | 286       | 24        | 323                | $14.35      | Mid-concurrency         |
| Nova Micro | g6.48xlarge | 8k      | 16   | 402       | 39        | 397                | $11.68      | TTFT climbing           |
| Nova Lite  | p5.48xlarge | 8k      | 1    | 77        | 2.4       | 378                | $46.51      | Baseline single-request |
| Nova Lite  | p5.48xlarge | 8k      | 8    | 89        | 3.4       | 2144               | $8.20       | Strong scaling          |
| Nova Lite  | p5.48xlarge | 8k      | 16   | 100       | 4.2       | 3469               | $5.07       | Excellent throughput    |
| Nova Lite  | g6.48xlarge | 8k      | 2    | 247       | 15.5      | 123                | $37.69      | Low-concurrency         |
| Nova Lite  | g6.48xlarge | 8k      | 8    | 362       | 29        | 259                | $17.90      | TPOT degrades notably   |

### Without RAI (includes cost data)

| Model       | Instance    | Context | Conc | TTFT (ms) | TPOT (ms) | Throughput (tok/s) | $/hr   | Cost per 1M tokens | Notes                      |
| ----------- | ----------- | ------- | ---- | --------- | --------- | ------------------ | ------ | ------------------ | -------------------------- |
| Nova Micro  | p5.48xlarge | 8k      | 2    | 36        | 2.14      | 861                | 63.296 | $20.43             | Low utilization            |
| Nova Micro  | p5.48xlarge | 8k      | 32   | 56        | 2.67      | 10804              | 63.296 | $1.63              | Likely most balanced       |
| Nova Micro  | p5.48xlarge | 8k      | 128  | 259       | 5.46      | 20756              | 63.296 | $0.85              | High concurrency           |
| Nova Micro  | g5.12xlarge | 8k      | 2    | 185       | 9.65      | 201                | 7.090  | $9.81              | Low utilization            |
| Nova Micro  | g5.12xlarge | 8k      | 16   | 279       | 23.4      | 665                | 7.090  | $2.96              | Mid-concurrency            |
| Nova Micro  | g5.12xlarge | 8k      | 32   | 442       | 36.0      | 868                | 7.090  | $2.27              | Good cost point            |
| Nova Micro  | g6.24xlarge | 8k      | 2    | 174       | 13.3      | 145                | 8.344  | $16.01             | Low utilization            |
| Nova Micro  | g6.24xlarge | 8k      | 16   | 237       | 23.0      | 679                | 8.344  | $3.41              | Mid-concurrency            |
| Nova Micro  | g6.24xlarge | 8k      | 64   | 577       | 54.8      | 1143               | 8.344  | $2.03              | Best cost/tok              |
| Nova Micro  | g6.48xlarge | 16k     | 2    | 162       | 9.25      | 206                | 16.688 | $22.55             | Low utilization, long ctx  |
| Nova Micro  | g6.48xlarge | 16k     | 32   | 421       | 38.3      | 816                | 16.688 | $5.68              | Mid-concurrency            |
| Nova Micro  | g6.48xlarge | 16k     | 64   | 705       | 69.5      | 900                | 16.688 | $5.15              | Marginal gain past 32      |
| Nova 2 Lite | p5.48xlarge | 16k     | 2    | 58        | 5.07      | 378                | 63.296 | $46.47             | Very low utilization       |
| Nova 2 Lite | p5.48xlarge | 16k     | 32   | 87        | 6.84      | 4429               | 63.296 | $3.97              | Mid-concurrency            |
| Nova 2 Lite | p5.48xlarge | 16k     | 64   | 147       | 9.14      | 6627               | 63.296 | $2.65              | Good cost point            |
| Nova 2 Lite | p5.48xlarge | 4k      | 2    | 57        | 4.98      | 385                | 63.296 | $45.62             | Low utilization, short ctx |
| Nova 2 Lite | p5.48xlarge | 4k      | 64   | 151       | 9.07      | 6701               | 63.296 | $2.62              | Good cost point            |
| Nova 2 Lite | p5.48xlarge | 4k      | 512  | 2594      | 43.2      | 10378              | 63.296 | $1.69              | Lowest cost/tok            |
| Nova Lite   | p5.48xlarge | 8k      | 2    | 39        | 2.29      | 803                | 63.296 | $21.90             | Low utilization            |
| Nova Lite   | p5.48xlarge | 8k      | 32   | 66        | 3.21      | 9111               | 63.296 | $1.93              | Balanced                   |
| Nova Lite   | p5.48xlarge | 8k      | 128  | 182       | 6.88      | 17224              | 63.296 | $1.02              | Lowest cost/tok            |
| Nova Lite   | p5.48xlarge | 16k     | 2    | 41        | 2.28      | 798                | 63.296 | $22.03             | Low utilization            |
| Nova Lite   | p5.48xlarge | 16k     | 32   | 80        | 3.23      | 9065               | 63.296 | $1.94              | Balanced                   |
| Nova Lite   | p5.48xlarge | 16k     | 64   | 105       | 4.43      | 13360              | 63.296 | $1.32              | Good cost point            |
| Nova Lite   | g6.48xlarge | 16k     | 2    | 218       | 13.2      | 146                | 16.688 | $31.74             | Low utilization            |
| Nova Lite   | g6.48xlarge | 16k     | 16   | 335       | 28.9      | 536                | 16.688 | $8.65              | Best available             |

---

## Estimation Formulas

Use these log-linear regression models to estimate metrics at concurrency levels not directly benchmarked.

```
TPOT  = a_tpot  + b_tpot  × ln(concurrency)
Throughput = exp(a_thr + b_thr × ln(concurrency))
TTFT  = a_ttft  + b_ttft  × ln(concurrency)
```

### Coefficient Table (curated — R² > 0.85 for ≥2 of 3 metrics)

| Coeff Key                                | a_tpot  | b_tpot | R²_tpot | a_thr | b_thr | R²_thr | Data Pts | Min Conc | Max Conc |
| ---------------------------------------- | ------- | ------ | ------- | ----- | ----- | ------ | -------- | -------- | -------- |
| with RAI · Micro · p5.48xlarge · 8k      | 1.644   | 0.808  | 0.857   | 6.173 | 0.756 | 0.992  | 6        | 1        | 32       |
| with RAI · Micro · g5.12xlarge · 4k      | -0.681  | 20.346 | 0.857   | 4.653 | 0.394 | 0.963  | 6        | 1        | 32       |
| with RAI · Micro · g6.12xlarge · 8k      | 6.305   | 11.002 | 0.936   | 4.452 | 0.559 | 0.991  | 7        | 2        | 16       |
| with RAI · Micro · g6.48xlarge · 8k      | 0.663   | 15.722 | 0.841   | 4.770 | 0.431 | 0.960  | 6        | 1        | 32       |
| with RAI · Micro · g6.24xlarge · 8k      | 12.423  | 5.919  | 0.894   | 4.305 | 0.691 | 0.986  | 4        | 1        | 8        |
| with RAI · Lite · p5.48xlarge · 8k       | 2.008   | 0.854  | 0.895   | 6.010 | 0.766 | 0.996  | 6        | 1        | 32       |
| with RAI · Lite · g6.48xlarge · 8k       | 2.150   | 14.710 | 0.924   | 4.551 | 0.471 | 0.974  | 4        | 2        | 16       |
| without RAI · Micro · g5.12xlarge · 8k   | -0.495  | 9.385  | 0.889   | 5.056 | 0.518 | 0.971  | 5        | 2        | 32       |
| without RAI · Micro · g6.24xlarge · 8k   | -0.454  | 11.009 | 0.826   | 4.701 | 0.604 | 0.974  | 6        | 2        | 64       |
| without RAI · Micro · g6.48xlarge · 16k  | -10.776 | 16.060 | 0.833   | 5.178 | 0.427 | 0.957  | 6        | 2        | 64       |
| without RAI · Lite · p5.48xlarge · 16k   | 1.586   | 0.556  | 0.802   | 6.190 | 0.827 | 0.993  | 6        | 2        | 64       |
| without RAI · Lite 2 · p5.48xlarge · 16k | 3.794   | 1.040  | 0.794   | 5.423 | 0.841 | 0.994  | 6        | 2        | 64       |

---

## Data Quality Warnings

- **Low R² groups excluded.** Some coefficient groups had R² < 0.7 for all 3 metrics and are omitted. Do not assume all model×instance combos have reliable regressions.
- **Extrapolation is unreliable.** Formulas are fit within the Min/Max Concurrency range shown. Estimates outside that range may diverge significantly from reality.
- **'With RAI' cost-per-token values are computed from throughput and pricing table**, not directly measured. Small throughput measurement variance will affect the cost estimate.
- **Success rate < 100% at high concurrency indicates instability.** The curated table only includes 100% success-rate rows. If you push concurrency beyond the max shown, expect request failures.
- **p5.48xlarge at $63.30/hr is expensive.** Only justified for high-throughput production workloads where the per-token cost drops below cheaper instances (typically concurrency ≥ 32).

---

## Agent Usage Guide

When helping a customer choose an inference configuration:

1. **Use the benchmark table for exact matches.** If the customer's model, instance, context length, and concurrency match a row, cite the measured numbers directly.
2. **Use formulas to estimate at non-benchmarked concurrency levels.** Apply the regression coefficients for the matching group. Always state that the result is an estimate, not a measurement.
3. **Always show both $/hr AND $/1M tokens.** Customers with steady traffic care about $/hr; customers with bursty or low-volume traffic care about $/1M tokens.
4. **Flag extrapolated vs measured values.** When a number comes from the formula (especially outside the min/max concurrency range), say so explicitly.
5. **To compute cost for non-benchmarked configs**, use: `cost_per_1M = ($/hr / throughput) × (1e6 / 3600)`.
6. **Recommend starting at the "balanced" concurrency point** (marked in Notes) and scaling from there based on latency requirements.
