---
name: deployment-inference
description: Deploying trained models and running inference on SageMaker or Bedrock using ForgeDeployer and ForgeInference.
triggers:
  keywords: [deploy, endpoint, inference, invoke, batch, sagemaker, bedrock, production, unit_count, speculative decoding]
  task_types: [deployment, inference]
  error_patterns: ["unit_count required", "endpoint", "InvokeEndpoint"]
  methods: [SFT, RFT, DPO]
prerequisites: [training-workflow]
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

# Deployment and Inference

## Key Concepts

### ForgeDeployer

Handles model deployment (replaces deprecated `customizer.deploy()`):

- `deploy()` — Deploy to SageMaker endpoint
- `create_custom_model()` — Import model to Bedrock
- `deploy_to_bedrock()` — Create Bedrock provisioned throughput
- `find_published_model()` — Find a model in SageMaker Model Registry
- `get_status()` — Check deployment status

### ForgeInference

Handles invocation (replaces deprecated `customizer.invoke_inference()` and `customizer.batch_inference()`):

- `invoke()` — Single real-time inference request
- `invoke_batch()` — Process large datasets in batch
- `get_logs()` — Retrieve inference job logs

### Deployment Platforms

- **SageMaker**: Full control, custom instance types, pay per instance hour
- **Bedrock Provisioned Throughput**: Managed service, pay per model unit
- **Bedrock On-Demand**: Serverless, pay per token (base models only)

## Step-by-Step Guide

### 1. Deploy to SageMaker

```python
from amzn_nova_forge import ForgeDeployer
from amzn_nova_forge import Model, DeployPlatform
from amzn_nova_forge import TrainingResult

deployer = ForgeDeployer(
    region="us-east-1",
    model=Model.NOVA_LITE_2
)

# Load training result
training_result = TrainingResult.load("<project-dir>/manifests/training-<job-name>.json")
checkpoint_path = training_result.model_artifacts.checkpoint_s3_path

# Deploy to SageMaker
deploy_result = deployer.deploy(
    model_artifact_path=checkpoint_path,
    deploy_platform=DeployPlatform.SAGEMAKER,
    sagemaker_instance_type="ml.p5.48xlarge",
    unit_count=1
)

print(f"Endpoint: {deploy_result.endpoint_name}")
```

**SageMaker Endpoint Environment (optional):**

Configure inference behavior via `sagemaker_environment`:

```python
deploy_result = deployer.deploy(
    model_artifact_path=checkpoint_path,
    deploy_platform=DeployPlatform.SAGEMAKER,
    sagemaker_instance_type="ml.p5.48xlarge",
    sagemaker_environment={
        "CONTEXT_LENGTH": 4000,
        "MAX_CONCURRENCY": 1,
        # Speculative decoding (faster inference)
        "SPECULATIVE_DECODING_METHOD": "eagle3",  # or "suffix"
        "NUM_SPECULATIVE_TOKENS": 5,
        # FP8 quantization (reduced memory)
        "KV_CACHE_DTYPE": "fp8",
        "QUANTIZATION_DTYPE": "fp8",
    }
)
```

### 2. Deploy to Bedrock

```python
from amzn_nova_forge import ForgeDeployer
from amzn_nova_forge import Model, DeployPlatform

deployer = ForgeDeployer(
    region="us-east-1",
    model=Model.NOVA_LITE_2
)

# Step 1: Import custom model
custom_model_result = deployer.create_custom_model(
    model_artifact_path=checkpoint_path,
    # job_result=training_result # can also provide the training job result json file
)

# Step 2: Deploy with provisioned throughput
deploy_result = deployer.deploy_to_bedrock(
    model_arn=custom_model_result.model_arn,
    # model_deploy_result=custom_model_result # can also pass the create model result
    pt_units=2
)

print(f"Provisioned throughput Endpoint: {deploy_result.endpoint.uri}")
```

### 3. Real-Time Inference

```python
from amzn_nova_forge import ForgeInference
from amzn_nova_forge import DeployPlatform

inference = ForgeInference(
    region="us-east-1",
    model=Model.NOVA_LITE_2
)

response = inference.invoke(
    endpoint_arn=deploy_result.endpoint.uri,
    request_body={
        "messages": [{"role": "user", "content": "Hello! How are you?"}],
        "max_tokens": 100,
        "stream": False,
    },
)

print(response)
```

### 4. Batch Inference

```python
batch_result = inference.invoke_batch(
    model_path=checkpoint_path,
    input_s3_path='s3://my-bucket/batch_input.jsonl',
    output_s3_path='s3://my-bucket/batch_output/'
)

print(f"Batch job: {batch_result.job_id}")
```

## Troubleshooting

### Missing unit_count

**Problem:** `ValueError: unit_count required for BEDROCK_PT and SAGEMAKER platforms`

**Solution:** Always provide `unit_count` when deploying:

```python
deployer.deploy(model_artifact_path=path, deploy_platform=DeployPlatform.SAGEMAKER, unit_count=1)
```

### Manual Bedrock Deployment (Permission Issues)

If `deploy()` fails due to IAM permission issues, use the manual workaround:

1. **Locate checkpoint:** For SMTJ, find `checkpoint_s3_path` in the training result. For SMHP, download `manifest.json` from the output path and extract the checkpoint URI.

1. **Import via Bedrock API:**

```python
import boto3
bedrock = boto3.client('bedrock')
response = bedrock.create_custom_model(
    modelName='my-custom-model',
    modelSourceConfig={'s3Uri': checkpoint_path}
)
```

1. **Deploy via Console or CLI** — create provisioned throughput from the custom model.

### Batch Input Format

Batch input must be JSONL with a `prompt` field:

```jsonl
{"prompt": "What is machine learning?"}
{"prompt": "Explain neural networks."}
```

## Platform Comparison

| Feature          | SageMaker         | Bedrock PT     | Bedrock On-Demand |
| ---------------- | ----------------- | -------------- | ----------------- |
| Custom models    | Yes               | Yes            | Base models only  |
| Instance control | Full control      | Managed        | Serverless        |
| Pricing          | Per instance hour | Per model unit | Per token         |
| Setup time       | ~10 minutes       | ~20 minutes    | Instant           |
| Scaling          | Manual            | Manual         | Automatic         |
| Best for         | Development       | Production     | Variable load     |

## Best Practices

1. **Start with 1 unit** — scale up based on load testing
2. **Test with real-time first** — verify model works before batch
3. **Use batch for scale** — more cost-effective for large datasets
4. **Delete unused endpoints** — avoid unnecessary charges
5. **Use Bedrock PT for production** — managed service, less operational overhead
6. **Use SageMaker for development** — more control, easier debugging

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
