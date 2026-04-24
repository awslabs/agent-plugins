# Recommendation Workflow

Guide the user through creating and running an AI Recommendation Job.

## Step 1: Gather Model Information

You need:

- **Model S3 URI** — S3 path to the model weights (HuggingFace format)
- **IAM Role ARN** — Execution role with SageMaker and S3 permissions

If not already known, ask:

> "I need two things to get started:
>
> 1. **Model location** — The S3 URI where your model weights are stored (e.g., `s3://my-bucket/models/llama-3-8b/`)
> 2. **IAM Role** — An execution role ARN with SageMaker permissions
>
> The model should be in HuggingFace format (config.json + model weights)."

⏸ Wait for user.

## Step 2: Choose a Performance Target

| Target         | Metric       | What It Optimizes                                                   |
| -------------- | ------------ | ------------------------------------------------------------------- |
| **Cost**       | `cost`       | Lowest cost per hour while meeting baseline performance             |
| **Latency**    | `ttft-ms`    | Lowest time-to-first-token (with optional stat: p50, p90, p95, p99) |
| **Throughput** | `throughput` | Highest output tokens per second                                    |

Ask the user:

> "What's most important for your use case?
>
> 1. **Cost** — Find the cheapest instance that meets performance requirements
> 2. **Latency** — Minimize time-to-first-token (best for interactive/chat)
> 3. **Throughput** — Maximize tokens per second (best for batch processing)"

⏸ Wait for user.

## Step 3: Configure Options

For instance types, optimization, dataset, workload config, and inference framework options, read `recommendation-options.md`.

## Step 4: Create the Recommendation Job

Generate a notebook that creates and monitors the job:

```python
import boto3
import json
import time

sm = boto3.client("sagemaker")

config_name = "my-rec-workload-config"
job_name = "my-recommendation-job"
sm.create_ai_recommendation_job(
    AIRecommendationJobName=job_name,
    ModelSource={"S3": {"S3Uri": "<MODEL_S3_URI>"}},
    OutputConfig={"S3OutputLocation": "s3://<BUCKET>/rec-output/"},
    RoleArn="<ROLE_ARN>",
    AIWorkloadConfigIdentifier=config_name,
    PerformanceTarget={"Constraints": [{"Metric": "cost"}]},
    # ComputeSpec={"InstanceTypes": ["ml.g6.12xlarge"]},
    # OptimizeModel=False,
    # InferenceSpecification={"Framework": "VLLM"},
)

# Poll until complete (timeout after 2 hours — optimization jobs can take longer)
MAX_WAIT = 7200
start = time.time()
while time.time() - start < MAX_WAIT:
    resp = sm.describe_ai_recommendation_job(AIRecommendationJobName=job_name)
    status = resp["AIRecommendationJobStatus"]
    print(f"Status: {status} ({int(time.time() - start)}s elapsed)")
    if status in ("Completed", "Failed", "Stopped"):
        break
    time.sleep(60)
else:
    raise TimeoutError("Recommendation job did not complete within 2 hours")

if status == "Failed":
    print(f"Failed: {resp.get('FailureReason')}")
else:
    print(f"Completed with {len(resp.get('Recommendations', []))} recommendations")
```

## Step 5: Present Recommendations

The `DescribeAIRecommendationJob` response contains:

- **Recommendations** — Ranked list with `DeploymentConfiguration`, `ExpectedPerformance`, `OptimizationDetails`, `ModelDetails`
- **OutputConfig** — S3 location and `ModelPackageGroupIdentifier`

Return to the main SKILL.md Step 3 (Review Results).

## Step 6: Deploy from ModelPackage

Read `recommendation-deploy.md` for deployment code.
