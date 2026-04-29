# Deploy Nova LoRA to SageMaker

## Scenario

- **Model Type**: Nova
- **Fine-tuning Method**: LoRA
- **Deployment Target**: SageMaker Single Model Endpoint
- **Approach**: SageMaker ModelBuilder

## Overview

Deploys a Nova fine-tuned model to a SageMaker endpoint using `ModelBuilder`.

Nova deploys as a model-on-variant (no inference components), so you invoke the endpoint directly without specifying an `InferenceComponentName`.

**Required inputs** (collected in the steps below):

- Training job name
- Instance type
- IAM execution role ARN
- AWS region
- Endpoint name

## Prerequisites

Requires SageMaker Python SDK >= 3.7.0 (installed by Cell 1).

## Workflow

### Important Instructions

- Make sure to use dedicated tools instead of bash commands whenever possible

### Step 1: Gather Training Job Name

The training job name was identified in Step 1 of the main workflow. Confirm you have it.

### Step 2: Determine Instance Type

For this step, you need: **the instance type.**

First, determine the Nova variant from the training job's model package. Use your AWS tool to run `sagemaker describe-training-job` for the training job name and extract the `OutputModelPackageArn` from the response. Then inspect the model package to find the `hub_content_name` (e.g., `nova-textgeneration-micro`).

Supported instances by Nova variant (smallest to largest). Larger instances support longer context lengths.

Nova Micro (`nova-textgeneration-micro`): ml.g5.12xlarge, ml.g5.24xlarge, ml.g6.12xlarge, ml.g6.24xlarge, ml.g6.48xlarge, ml.p5.48xlarge

Nova Lite (`nova-textgeneration-lite`): ml.g6.48xlarge, ml.p5.48xlarge

Nova Lite v2 (`nova-textgeneration-lite-v2`): ml.p5.48xlarge

Nova Pro (`nova-textgeneration-pro`): ml.g6.48xlarge, ml.p5.48xlarge

Present the supported instance types and ask which one the user would like to use. The larger instances will be more expensive, but have larger context windows.

⏸ Wait for user to confirm before moving on.

### Step 3: Verify IAM Role

Use the IAM role from the training job (extracted in Step 1 of the main workflow via `describe-training-job`). This role should already have the necessary SageMaker and S3 permissions. Confirm with the user.

### Step 4: Confirm Region

The region was identified in Step 1 of the main workflow. Nova deployment is only supported in: us-east-1, us-west-2, eu-west-2, ap-northeast-1. If the region isn't supported, tell the user that SageMaker deployment is not supported for this model in this region.

### Step 5: Choose Endpoint Name

Suggest a name based on the model, e.g., `nova-micro-deploy-<timestamp>`. Ask the user to confirm or provide their own.

⏸ Wait for user before moving on.

### Step 6: Confirm Configuration

> "Here's the deployment setup:
>
> - Model: [base-model-name] fine-tuned with LoRA (e.g., "Nova Micro fine-tuned with LoRA")
> - Deployment target: SageMaker Endpoint
> - Training Job: [name]
> - Instance Type: [type]
> - IAM Role: [arn]
> - Region: [region]
> - Endpoint Name: [name]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 7: Generate Notebook

If a project directory already exists (from earlier in the workflow), use it. Otherwise, activate the **directory-management** skill to set one up.

Check if the project notebook already exists at `<project-dir>/notebooks/<project-name>.ipynb`.

- If it exists → ask: _"Would you like me to append the deployment cells to the existing notebook, or create a new one?"_
- If it doesn't exist → create it

When appending, add a markdown header cell `## Model Deployment — SageMaker` as a section divider before the new cells.

⏸ Wait for user.

## Notebook Structure

### Markdown Header

```json
{
  "cell_type": "markdown",
  "metadata": {},
  "source": [
    "# Deploy Nova Fine-Tuned Model to SageMaker"
  ]
}
```

### Cells

Each cell's content comes from `../scripts/deploy-nova-sagemaker.py`, split on the `# Cell N:` comments.

- **Cell 1**: Setup (pip install)
- **Cell 2**: Configuration
- **Cell 3**: Build Model
- **Cell 4**: Deploy Endpoint
- **Cell 5**: Test Inference

### Placeholders

Cell 2:

- `[REGION]` → AWS region
- `[TRAINING_JOB_NAME]` → Training job name
- `[ROLE_ARN]` → IAM execution role ARN
- `[INSTANCE_TYPE]` → SageMaker instance type (e.g., `ml.g5.12xlarge`)
- `[ENDPOINT_NAME]` → Endpoint name

## Step 8: Provide Run Instructions

```
To run:
1. Cell 1 — install SDK packages, then restart the kernel before continuing
2. Cell 2 — set configuration values
3. Cell 3 — build model via ModelBuilder (~30s, creates SageMaker Model resource)
4. Cell 4 — deploy endpoint (waits for InService, ~10-15 min)
5. Cell 5 — test inference with a sample prompt
```

## Common Issues

- **"No module named 'sagemaker.core'" or "No module named 'sagemaker.train'"**: Re-run Cell 1 to install the required packages, then restart the kernel.
- **"Must setup local AWS configuration with a region"**: Set `AWS_DEFAULT_REGION` env var or configure `~/.aws/config`
- **"Cannot create already existing endpoint configuration"**: An endpoint with that name already exists. Use a different name or delete the existing one first.
- **Endpoint fails to reach InService**: Check CloudWatch logs for the endpoint. Common causes: wrong instance type for the model size, or IAM role missing permissions.
