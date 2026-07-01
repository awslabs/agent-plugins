# LMI Configuration Guide

## Instance Type Decision Tree

- **CPU-intensive** (encoding, ML, compression) → C-series, 2:1 ratio, concurrency=1/vCPU
- **Memory-intensive** (caching, large datasets) → R-series, 8:1 ratio
- **Network-intensive** (streaming, data transfer) → Use AllowedInstanceTypes for n-suffix types, 4:1 ratio
- **General/balanced** (web APIs, microservices) → M-series, 2:1 ratio (default), default concurrency

Architecture: ARM (Graviton, g-suffix) for price-performance. x86 (i=Intel, a=AMD) when dependencies require it.

## Memory-to-vCPU Ratios

| Ratio | Profile | When to use                      | Memory examples       |
| ----- | ------- | -------------------------------- | --------------------- |
| 2:1   | Compute | CPU-bound work (default)         | 2GB/1vCPU, 4GB/2vCPU  |
| 4:1   | General | Mixed CPU/memory-heavy workloads | 4GB/1vCPU, 8GB/2vCPU  |
| 8:1   | Memory  | Memory-heavy or Python apps      | 8GB/1vCPU, 16GB/2vCPU |

Min: 2 GB / 1 vCPU. Max: 32 GB. Memory must align with ratio multiples.

## Memory Sizing from Existing Lambda

| Current Lambda | LMI memory    | Ratio      | Rationale                                    |
| -------------- | ------------- | ---------- | -------------------------------------------- |
| 128-512 MB     | 2048 MB       | 4:1        | LMI minimum; multi-concurrency shares memory |
| 512 MB-1 GB    | 2048 MB       | 4:1        | Room for concurrent requests                 |
| 1-2 GB         | 4096 MB       | 4:1        | Standard upgrade path                        |
| 2-4 GB         | 4096-8192 MB  | 4:1 or 8:1 | Depends on memory vs CPU bottleneck          |
| 4-10 GB        | 8192-16384 MB | 8:1        | Likely memory-heavy workload                 |

## Concurrency Tuning

| Runtime | Default/vCPU | I/O-bound        | CPU-bound  |
| ------- | ------------ | ---------------- | ---------- |
| Node.js | 64           | Keep or increase | 1 per vCPU |
| Java    | 32           | Keep             | 1 per vCPU |
| .NET    | 32           | Keep             | 1 per vCPU |
| Python  | 16           | Keep             | 1 per vCPU |

Total capacity = MinExecutionEnvironments × PerExecutionEnvironmentMaxConcurrency

## Capacity Provider Scaling Controls

| Control                   | Default       | Guidance                                              |
| ------------------------- | ------------- | ----------------------------------------------------- |
| MinExecutionEnvironments  | 3             | Min 1 (non-prod); 3+ recommended for prod AZ coverage |
| MaxExecutionEnvironments  | —             | Set based on cost budget                              |
| MaxVCpuCount              | 400           | Set to control cost ceiling; adjust by load           |
| TargetResourceUtilization | ~50% headroom | Raise for cost savings (less burst tolerance)         |
| AllowedInstanceTypes      | All           | Restrict only for specific hardware needs             |
| ExcludedInstanceTypes     | None          | Exclude expensive types in dev/test                   |

## Scheduled Scaling (Predictable Traffic)

For workloads with known traffic patterns (business hours, marketing events, batch windows), use [Amazon EventBridge Scheduler](https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-targets-universal.html) to adjust a function's `MinExecutionEnvironments` and `MaxExecutionEnvironments` on a one-time or recurring schedule. A schedule (cron or rate expression) targets the Lambda `PutFunctionScalingConfig` API as an EventBridge Scheduler universal target, passing new Min/Max values in the input payload.

**Behavior:**

- Scheduled scaling sets the provisioned floor and ceiling. Actual scaling between Min and Max still responds to CPU utilization and concurrency saturation.
- If traffic more than doubles within 5 minutes of a scheduled scale-up, you may still see throttles while capacity provisions.
- Setting both `MinExecutionEnvironments` and `MaxExecutionEnvironments` to 0 deactivates the function version (instances terminate). A deactivated function does NOT auto-recover — schedule a separate action with non-zero values to reactivate it.

**Common patterns:**

| Pattern                | Scale-up schedule                   | Scale-down schedule              |
| ---------------------- | ----------------------------------- | -------------------------------- |
| Business hours         | Raise Min/Max before work starts    | Lower Min/Max after hours        |
| Marketing/launch event | Raise Min ahead of the campaign     | Restore baseline after the event |
| Idle scale-to-zero     | Reactivate (non-zero) before demand | Set Min=Max=0 when idle          |

See [infrastructure-setup.md](infrastructure-setup.md) for the EventBridge Scheduler IAM role and `create-schedule` CLI examples.

## Monitoring Thresholds

- **CPU > 80%**: reduce concurrency or add vCPUs
- **CPU < 20%**: increase concurrency for better utilization
- **Throttle rate (429s) > 1%**: increase MinExecutionEnvironments or reduce utilization target
- **Memory > 90%**: increase memory or reduce concurrency
- **ExecutionEnvironmentConcurrency near ExecutionEnvironmentConcurrencyLimit**: saturation — reduce concurrency or scale out

## CloudWatch Metrics Dimensions

LMI metrics are split across two CloudWatch dimensions:

- **Alias (live)**: Invocations, Errors, Throttles, Duration
- **Version ($LATEST or numbered)**: CPUUtilization, MemoryUtilization, ExecutionEnvironmentConcurrency, ExecutionEnvironmentCount

Create a unified dashboard combining both views to monitor LMI performance effectively.
