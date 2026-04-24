---
name: ai-optimization
description: Guides users through SageMaker AI Optimization APIs for benchmarking and optimizing LLM inference. Covers workload configuration, benchmark jobs, and recommendation jobs that find the best instance type, optimization strategy, and serving configuration for a model. Use when the user says "benchmark my model", "optimize inference", "find the best instance", "recommendation job", "workload config", "AI benchmark", "AI recommendation", "reduce inference cost", "improve latency", or "optimize throughput".
metadata:
  version: "1.0.0"
---

# AI Optimization

Guide users through SageMaker AI Optimization APIs to benchmark LLM inference performance and get deployment recommendations.

## Scope

This skill covers the **SageMaker AI Optimization** APIs, which help users:

- **Benchmark** an existing SageMaker endpoint to measure inference performance (latency, throughput, cost)
- **Get recommendations** for the best instance type, serving configuration, and optional optimizations (kernel tuning, speculative decoding) for deploying a model

### Three Resource Types

| Resource                | Purpose                                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------------------------- |
| **AIWorkloadConfig**    | Defines the traffic pattern (request shape, concurrency, dataset) for benchmarking                       |
| **AIBenchmarkJob**      | Runs a benchmark against a live SageMaker endpoint using a workload config                               |
| **AIRecommendationJob** | Analyzes a model, deploys it on candidate instances, benchmarks each, and returns ranked recommendations |

### 14 API Operations

| Resource            | Create | Describe | Delete | List | Stop |
| ------------------- | ------ | -------- | ------ | ---- | ---- |
| AIWorkloadConfig    | ✓      | ✓        | ✓      | ✓    |      |
| AIBenchmarkJob      | ✓      | ✓        | ✓      | ✓    | ✓    |
| AIRecommendationJob | ✓      | ✓        | ✓      | ✓    | ✓    |

## Principles

1. **One thing at a time.** Each response advances exactly one decision.
2. **Confirm before proceeding.** Wait for the user to agree before moving to the next step.
3. **Don't read files until you need them.** Only read reference files when you've reached the step that requires them.
4. **Use what you know.** If the answer is in conversation history or any file you've already read, use it.
5. **No narration.** Share outcomes and ask questions. Keep responses short.
6. **Notebook writing.** Write notebooks using your standard file write tool to create the `.ipynb` file with the complete notebook JSON, OR use notebook MCP tools if available. Do NOT use bash commands to generate notebooks.

## Workflow

### Step 1: Determine the User's Goal

Check conversation history first. The user typically wants one of:

1. **Benchmark an existing endpoint** — They already have a deployed model and want performance metrics.
2. **Get deployment recommendations** — They have a model in S3 and want to know the best instance type and configuration.
3. **Both** — Benchmark first, then optimize.

If unclear, ask:

> "What would you like to do?
>
> 1. **Benchmark** — Measure performance of an existing SageMaker endpoint
> 2. **Get recommendations** — Find the best instance type and configuration for a model in S3
>
> Pick one, or describe what you're trying to achieve."

⏸ Wait for user.

- If benchmark → go to Step 2A.
- If recommendations → go to Step 2B.

### Step 2A: Benchmark an Existing Endpoint

Read `references/benchmark-workflow.md` and follow its instructions.

### Step 2B: Get Deployment Recommendations

Read `references/recommendation-workflow.md` and follow its instructions.

### Step 3: Review Results

After the job completes:

- For **benchmark jobs**: present the performance metrics (latency percentiles, throughput, cost estimates).
- For **recommendation jobs**: present the ranked recommendations with instance type, expected performance, and optimization details.

Read `references/interpreting-results.md` for guidance on presenting results to the user.

### Step 4: Next Steps

After presenting results, offer relevant next steps:

> "What would you like to do next?
>
> - **Deploy the recommended configuration** — I can help create a SageMaker endpoint using the top recommendation
> - **Run another benchmark** — Test with different parameters or a different workload
> - **Compare results** — Run recommendations with different performance targets (cost vs latency vs throughput)"

## Prerequisites

- **AWS credentials** configured (via AWS CLI, environment variables, or SageMaker Space)
- **IAM role** with SageMaker permissions (`AmazonSageMakerFullAccess` or equivalent)
- For benchmarking: a deployed SageMaker endpoint
- For recommendations: a model stored in S3 (HuggingFace format)

## Troubleshooting

### Common Issues

| Issue                                   | Cause                                                  | Fix                                                                 |
| --------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------- |
| Job stuck in Pending                    | No available capacity for the requested instance type  | Try a different instance type or wait for capacity                  |
| Job failed with "ResourceLimitExceeded" | Account quota exceeded                                 | Request a quota increase for the instance type                      |
| Benchmark metrics look wrong            | Workload config doesn't match the model's capabilities | Adjust token counts and concurrency in the workload config          |
| Recommendation job failed               | Model format not supported or S3 path incorrect        | Verify the model is in HuggingFace format and the S3 URI is correct |
