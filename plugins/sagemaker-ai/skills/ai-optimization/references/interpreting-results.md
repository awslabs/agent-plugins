# Interpreting Results

Guide for presenting benchmark and recommendation results to users.

## Benchmark Job Results

Present metrics in a clear table format:

| Metric                | Stat | Value | Unit       |
| --------------------- | ---- | ----- | ---------- |
| TimeToFirstToken      | p50  | 120   | ms         |
| TimeToFirstToken      | p90  | 180   | ms         |
| TimeToFirstToken      | p99  | 250   | ms         |
| InterTokenLatency     | p50  | 15    | ms         |
| OutputTokenThroughput | avg  | 45.2  | tokens/s   |
| RequestThroughput     | avg  | 2.1   | requests/s |
| RequestLatency        | p50  | 3200  | ms         |

Key insights to highlight:

- **TTFT p50 vs p99** — Large gaps indicate inconsistent performance (possibly due to batching or cold starts)
- **OutputTokenThroughput** — Higher is better for batch workloads
- **Concurrency impact** — If the user ran multiple benchmarks at different concurrency levels, compare how metrics scale

## Recommendation Job Results

Present recommendations as a ranked table:

> "Here are the recommendations, ranked by [cost/latency/throughput]:
>
> | # | Instance Type  | TTFT p50 | Throughput | Optimizations | Est. Cost |
> | - | -------------- | -------- | ---------- | ------------- | --------- |
> | 1 | ml.g6.xlarge   | 95ms     | 42 tok/s   | Kernel Tuning | $1.20/hr  |
> | 2 | ml.g5.xlarge   | 110ms    | 38 tok/s   | None          | $1.00/hr  |
> | 3 | ml.g6.12xlarge | 45ms     | 120 tok/s  | Kernel Tuning | $7.20/hr  |

### What Each Field Means

- **Instance Type** — The GPU instance the model was tested on
- **TTFT (Time to First Token)** — How long until the first token is generated. Lower is better for interactive use cases.
- **Throughput (Output Token Throughput)** — Tokens generated per second. Higher is better for batch processing.
- **Optimizations** — What the service applied:
  - **Kernel Tuning** — GPU kernel optimizations specific to the hardware. Improves throughput with no quality impact.
  - **Speculative Decoding** — Uses a smaller draft model to predict tokens ahead. Improves latency but requires a compatible draft model.
- **CopyCountPerInstance** — How many model copies fit on one instance. More copies = higher throughput per instance.

### Helping the User Choose

Guide based on their performance target:

- **Cost target** → Recommend #1 (lowest cost that meets baseline performance)
- **Latency target** → Recommend the one with lowest TTFT at the user's target percentile
- **Throughput target** → Recommend the one with highest OutputTokenThroughput

If the user is unsure, suggest:

> "For interactive applications (chatbots, real-time), prioritize low TTFT.
> For batch processing (summarization, translation), prioritize high throughput.
> For cost-sensitive workloads, the cost-optimized recommendation balances both."

### ModelPackage Deployment

Every recommendation includes a `ModelPackageArn` and `InferenceSpecificationName`. Explain:

> "Each recommendation is packaged as a deployable ModelPackage. You can deploy any of them directly — the model weights, container image, environment variables, and optimization artifacts are all bundled together.
>
> Would you like me to generate deployment code for one of these recommendations?"

## Performance Metrics Reference

| Metric                | Description                                | Unit       | Stats Available                   |
| --------------------- | ------------------------------------------ | ---------- | --------------------------------- |
| TimeToFirstToken      | Time from request to first generated token | ms         | p50, p90, p95, p99, avg, min, max |
| InterTokenLatency     | Time between consecutive tokens            | ms         | p50, p90, p95, p99, avg, min, max |
| OutputTokenThroughput | Tokens generated per second                | tokens/s   | avg                               |
| RequestThroughput     | Requests completed per second              | requests/s | avg                               |
| RequestLatency        | Total time for a complete request          | ms         | p50, p90, p95, p99, avg, min, max |
| ClientSideConcurrency | Concurrency level used during benchmarking | count      | —                                 |
