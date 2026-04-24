# Benchmark Workflow

Guide the user through creating and running an AI Benchmark Job.

## Step 1: Gather Endpoint Information

You need:

- **Endpoint name** — The SageMaker endpoint to benchmark
- **Inference components** (optional) — If the endpoint uses inference components, which ones to target

If not already known, ask:

> "What's the name of the SageMaker endpoint you want to benchmark? If it uses inference components, let me know which ones to target."

Use the AWS MCP tool `describe-endpoint` to verify the endpoint exists and is InService. If the user specified inference components, also use `describe-inference-component` to verify they exist on the endpoint.

## Step 2: Create a Workload Config

A workload config defines the traffic pattern. Key parameters:

| Parameter                    | Description                | Default |
| ---------------------------- | -------------------------- | ------- |
| `prompt_input_tokens_mean`   | Average input token count  | 512     |
| `prompt_input_tokens_stddev` | Std dev of input tokens    | 50      |
| `output_tokens_mean`         | Average output token count | 256     |
| `output_tokens_stddev`       | Std dev of output tokens   | 30      |
| `concurrency`                | Concurrent requests        | 1       |
| `request_count`              | Total requests to send     | 100     |

Ask the user:

> "What's the typical input/output length (in tokens) and concurrency? Or I can use sensible defaults."

⏸ Wait for user.

Generate a notebook cell that creates the workload config:

```python
import boto3
import json

sm = boto3.client("sagemaker")

workload_spec = {
    "benchmark": {"type": "aiperf"},
    "parameters": {
        "prompt_input_tokens_mean": 512,       # Adjust based on user input
        "prompt_input_tokens_stddev": 50,
        "output_tokens_mean": 256,             # Adjust based on user input
        "output_tokens_stddev": 30,
        "concurrency": 1,                      # Adjust based on user input
        "request_count": 100,
    },
}

sm.create_ai_workload_config(
    AIWorkloadConfigName="my-workload-config",
    AIWorkloadConfigs={"WorkloadSpec": {"Inline": json.dumps(workload_spec)}},
)
```

## Step 3: Create the Benchmark Job

Generate a notebook cell that creates and monitors the benchmark job:

```python
import time

sm.create_ai_benchmark_job(
    AIBenchmarkJobName="my-benchmark-job",
    AIWorkloadConfigIdentifier="my-workload-config",
    RoleArn="<ROLE_ARN>",                      # User's IAM role
    BenchmarkTarget={
        "Endpoint": {"Identifier": "<ENDPOINT_NAME>"}
    },
    OutputConfig={
        "S3OutputLocation": "s3://<BUCKET>/benchmark-results/"
    },
)

# Poll until complete (timeout after 1 hour)
MAX_WAIT = 3600
start = time.time()
while time.time() - start < MAX_WAIT:
    resp = sm.describe_ai_benchmark_job(AIBenchmarkJobName="my-benchmark-job")
    status = resp["AIBenchmarkJobStatus"]
    print(f"Status: {status} ({int(time.time() - start)}s elapsed)")
    if status in ("Completed", "Failed", "Stopped"):
        break
    time.sleep(30)
else:
    raise TimeoutError("Benchmark job did not complete within 1 hour")

if status == "Failed":
    print(f"Benchmark failed: {resp.get('FailureReason', 'Unknown')}")
elif status == "Stopped":
    print("Benchmark was stopped before completion.")
else:
    print("Benchmark completed successfully.")
```

## Step 4: Present Results

When the job completes, read `benchmark-results.md` for the code to download and display results.

Return to the main SKILL.md Step 3 (Review Results).
