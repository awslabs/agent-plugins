# Deploy OSS Merged LoRA to Bedrock CMI

## Scenario

- **Model Type**: OSS (Open Source)
- **Fine-tuning Method**: LoRA
- **Merge Status**: Merged (`merge_weights: true`)
- **Deployment Target**: Bedrock Custom Model Import (CMI)
- **Approach**: SageMaker PySdk `BedrockModelBuilder`

## Overview

Uses the SageMaker PySdk `BedrockModelBuilder` to import a fine-tuned model into Bedrock as a Custom Model Import (CMI). The builder auto-resolves model artifacts from a training job.

**Required inputs** (collected in the steps below):

- Training job name
- Model name
- IAM role ARN (with Bedrock trust policy and S3 read access)
- AWS region (must be us-east-1, us-east-2, us-west-2, or eu-central-1)

## Prerequisites

### Model Size Limit

Bedrock CMI has a 200GB limit for text models (100GB for multimodal). Check before proceeding using the AWS MCP tool `list-objects-v2` (S3 service) with the bucket and prefix `<prefix>/checkpoints/hf_merged/`. Sum the `Size` field from all returned objects to determine total size.
If the model exceeds 200GB, this pathway cannot be used.

### Required Files

The `hf_merged/` folder must contain: `.safetensors` files, `config.json`, `tokenizer.json`, `tokenizer_config.json`.

### SDK Version

Requires `sagemaker>=3.7.0` with `BedrockModelBuilder` support.

## Workflow

### Step 1: Gather Training Job Name

The training job name was identified in Step 1 of the main workflow. Confirm you have it.

### Step 2: Gather Model Name

Suggest a name for the deployed model based on the training job or use case. Format: lowercase, alphanumeric with hyphens. Confirm with the user.

### Step 3: Verify IAM Role

Use the IAM role from the training job (extracted in Step 1 of the main workflow via `describe-training-job`). We'll assume this role has the necessary permissions for Bedrock deployment.

### Step 4: Confirm Region

Bedrock CMI is available in: us-east-1, us-east-2, us-west-2, eu-central-1.

The region was identified in Step 1. Confirm it's in the supported list. If not, tell the user that Bedrock deployment is not supported for this model in this region.

### Step 5: Confirm Configuration

> "Here's the deployment setup:
>
> - Deployment target: Bedrock
> - Training Job: [job-name]
> - Model Name: [name]
> - IAM Role: [arn]
> - Region: [region]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 6: Generate Notebook

If a project directory already exists (from earlier in the workflow), use it. Otherwise, activate the **directory-management** skill to set one up.

Check if the project notebook already exists at `<project-dir>/notebooks/<project-name>.ipynb`.

- If it exists → ask: _"Would you like me to append the deployment cells to the existing notebook, or create a new one?"_
- If it doesn't exist → create it

When appending, add a markdown header cell `## Model Deployment — Bedrock` as a section divider before the new cells.

⏸ Wait for user.

## Notebook Structure

### Markdown Header

```json
{
  "cell_type": "markdown",
  "metadata": {},
  "source": [
    "# Deploy to Bedrock"
  ]
}
```

### Cells

Each cell's content comes from `../scripts/deploy-oss-bedrock.py`, split on the `# Cell N:` comments.

- **Cell 1**: Setup (pip install)
- **Cell 2**: Configuration
- **Cell 3**: Flatten S3 Structure and Start Import
- **Cell 4**: Wait for Import to Complete
- **Cell 5**: Test Inference

### Placeholders

Cell 2:

- `[REGION]` → AWS region
- `[TRAINING_JOB_NAME]` → SageMaker training job name
- `[ROLE_ARN]` → IAM role ARN with Bedrock trust policy and S3 read permissions
- `[MODEL_NAME]` → Name for the imported model

All other cells have no placeholders.

### Step 7: Provide Run Instructions

```
To run:
1. Cell 1 — install/upgrade SageMaker SDK
2. Cell 2 — configuration and imports
3. Cell 3 — flattens S3 structure and starts import job via BedrockModelBuilder
4. Cell 4 — waits for import to complete (typically a few minutes)
5. Cell 5 — test inference with a sample prompt
```

## Common Issues

- **"Model weights are larger than 200GB"**: Cannot use this pathway.
- **"No module named 'sagemaker.serve.bedrock_model_builder'"**: Upgrade SDK: `pip install --upgrade sagemaker>=3.7.1`
- **Import starts but uses wrong region**: Known issue — `BedrockModelBuilder` defaults to us-east-1. The notebook code overrides this.
- **"Access denied to S3"**: Add S3 read permissions to the IAM role for the model bucket.
- **"Provided IAM role could not be assumed"**: Ensure role has trust policy for `bedrock.amazonaws.com`.

## Post-Deployment Summary

After the notebook runs successfully, tell the user:

- **Model**: `[MODEL_NAME]` has been imported to Bedrock
- **How to invoke**: Use the Bedrock `invoke_model` API with the imported model ARN
- **Billing**: Pay per request — no cost while idle
- **Cleanup**: When done, delete the imported model using the AWS MCP tool `delete-imported-model` (Bedrock service) with the model name.
