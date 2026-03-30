# Deploy OSS LoRA to SageMaker Multi-Adapter Endpoint

## Scenario

- **Model Type**: OSS (Open Source)
- **Fine-tuning Method**: LoRA
- **Merge Status**: Unmerged (`merge_weights: false`)
- **Deployment Target**: SageMaker Multi-Adapter Endpoint
- **Approach**: SageMaker PySdk `JumpStartModel`

## Overview

Uses the SageMaker PySdk `JumpStartModel` to resolve the base model S3 URI and container image, rather than manually querying `describe_hub_content` and parsing the hub content document JSON. Requires `sagemaker>=3.7.0`.

**Required inputs** (collected in the steps below):

- Training job name (to resolve JumpStart model ID from tags)
- Instance type
- IAM execution role ARN
- AWS region

## Prerequisites

### SDK Version

Requires `sagemaker>=3.7.0` with `JumpStartModel` support.

## Key Gotchas

- **ArtifactUrl for adapter ICs**: An S3 prefix (directory) works despite docs saying it must be `.tar.gz`. No need to repackage.
- **Container version**: LMI 0.31.0 does NOT have the `vllm_async_service` entrypoint. Use `OPTION_ROLLING_BATCH=lmi-dist` instead.
- **Gated models**: Use JumpStart S3 cache via ModelDataSource to avoid needing HF_TOKEN.
- **Endpoint config**: Including ExecutionRoleArn enables inference-component mode. Do NOT include ModelName in ProductionVariants.

## Workflow

### Step 1: Gather Training Job Name

The training job name was identified in Step 1 of the main workflow. Confirm you have it.

This is needed to look up the JumpStart model ID (from training job tags), which `JumpStartModel` uses to resolve the base model S3 URI and container image automatically.

### Step 2: Determine Instance Type

For this step, you need: **the instance type.**

Recommend an instance based on model size:

- Small models (<3B): `ml.g5.2xlarge` (1 GPU, ~24GB)
- Medium models (<10B): `ml.g5.12xlarge` (4 GPUs, ~96GB)
- Large models (>10B): `ml.g6e.48xlarge` (8 GPUs, ~1TB)

Give your suggestion to the user with reasoning and ask them to confirm. If they would like a different instance type, accept their choice. If you think it will cause issues (e.g., not enough GPU memory for the model), call that out.

⏸ Wait for user to confirm before moving on.

### Step 3: Verify IAM Role

Use the IAM role from the training job (extracted in Step 1 of the main workflow via `describe-training-job`). This role should already have the necessary SageMaker and S3 permissions. Confirm with the user.

### Step 4: Confirm Region

The region was identified in Step 1 of the main workflow. Confirm it with the user.

### Step 5: Confirm Configuration

> "Here's the deployment setup:
>
> - Target: SageMaker Multi-Adapter Endpoint
> - Training Job: [name]
> - Instance Type: [type]
> - IAM Role: [arn]
> - Region: [region]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 6: Generate Notebook

Ask the user if they have an existing notebook to add the deployment cells to, or if they want a new one. If new, suggest a name like `deploy-[model]-[target].ipynb` and ask where to save it.

⏸ Wait for user.

## Notebook Structure

### Markdown Header

```json
{
  "cell_type": "markdown",
  "metadata": {},
  "source": [
    "# Deploy to SageMaker Multi-Adapter Endpoint"
  ]
}
```

### Cells

Each cell's content comes from `../scripts/deploy-oss-sagemaker.py`, split on the `# Cell N:` comments.

- **Cell 1**: Setup (pip install)
- **Cell 2**: Configuration
- **Cell 3**: Create Model and Endpoint
- **Cell 4**: Create Base Model and Adapter Inference Components
- **Cell 5**: Test Inference

### Placeholders

Cell 2:

- `[REGION]` → AWS region
- `[INSTANCE_TYPE]` → SageMaker instance type (e.g., `ml.g5.2xlarge`)
- `[TRAINING_JOB_NAME]` → Training job name (used to look up JumpStart model ID from tags)
- `[ROLE_ARN]` → IAM execution role ARN
- `[ENDPOINT_NAME]` → Name for the endpoint (agent should generate a reasonable default)

### Step 7: Provide Run Instructions

```
To run:
1. Cell 1 — install/upgrade SageMaker SDK
2. Cell 2 — configuration (resolves adapter path and base model metadata via JumpStartModel)
3. Cell 3 — creates model and endpoint (waits for endpoint to be InService, ~5-10 min)
4. Cell 4 — creates base model and adapter inference components (waits for both to be InService, ~5-10 min)
5. Cell 5 — test inference with a sample prompt
```

## Common Issues

- **"No module named 'sagemaker.jumpstart'"**: Upgrade SDK: `pip install --upgrade sagemaker>=3.7.0`
- **"ModuleNotFoundError" for vllm_async_service**: Using LMI 0.31.0 container. Use `OPTION_ROLLING_BATCH=lmi-dist` instead of `OPTION_ENTRYPOINT`.
- **Base IC fails health check**: Check `MinMemoryRequiredInMb` fits within instance memory. Reduce if needed.
- **"Inference Component Name header is required"**: Must pass `InferenceComponentName` when invoking the endpoint.
- **Console shows "Missing required key 'ModelName'"**: This is a console UI issue, not a deployment issue. The endpoint works correctly.
- **Adapter IC fails**: Verify adapter weights exist at `<model-s3-uri>/checkpoints/hf/`. Check that the S3 prefix is accessible.

## Post-Deployment Summary

After the notebook runs successfully, tell the user:

- **Endpoint**: `[ENDPOINT_NAME]` is now InService
- **How to invoke**: Use SageMaker runtime `InvokeEndpoint` with `InferenceComponentName` set to the adapter IC name (derived from the endpoint name)
- **Billing**: This endpoint is billed by the hour while running, even when idle. Delete it when you're done testing.
- **Cleanup**: Delete the adapter inference component first, then the base inference component, then the endpoint using the AWS MCP tool:
  1. Use `delete-inference-component` (SageMaker service) with the adapter IC name
  2. Wait for deletion to complete, then use `delete-inference-component` with the base IC name
  3. Wait for deletion to complete, then use `delete-endpoint` with the endpoint name
