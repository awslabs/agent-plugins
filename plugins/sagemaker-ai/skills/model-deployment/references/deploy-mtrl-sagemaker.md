# Deploy MTRL-trained Model to SageMaker Endpoint

## Scenario

- **Model Type**: MTRL (Multi-Turn Reinforcement Learning)
- **Fine-tuning Method**: LoRA
- **Deployment Target**: SageMaker Endpoint
- **Approach**: SageMaker PySdk `ModelBuilder` from `sagemaker.serve`

## Overview

Uses the SageMaker PySdk `ModelBuilder` to deploy an MTRL-trained model to a
SageMaker endpoint. The MTRL training output is a `ModelPackage` (already
registered in a `ModelPackageGroup` by `MultiTurnRLTrainer`), so the builder
takes the `ModelPackage` directly and resolves the container image and
artifact location automatically. Requires `sagemaker>=3.7.0`.

This pathway does **not** route through `JumpStartModel` because the
training output is a packaged model package, not a JumpStart hub artifact.
That is the same `ModelBuilder(model=ModelPackage.get(...))` pattern used
in the `s1-deploy` / `s2-deploy` cells of
`mtrl_dogfooding_notebook.ipynb`.

**Required inputs** (collected in the steps below):

- Model package ARN (from the MTRL training job's
  `output_model_package_arn`)
- Instance type (deterministic via `scripts/instance_recommender.py`)
- IAM execution role ARN
- AWS region
- Endpoint name (suggested by the agent, confirmed by the user)

## Prerequisites

### SDK Version

Requires `sagemaker>=3.7.1` with `ModelBuilder.deploy()` support.

## Workflow

### Step 1: Gather Training Job and Model Package ARN

The training job name was identified in Step 1 of the main workflow.
Confirm you have it.

Resolve the **output model package ARN** for the MTRL run by either:

1. Reading `output_model_package_arn` from the training job's metadata
   (the `MultiTurnRLTrainer` records it in `plan.md` and as a tag on the
   training job).
2. Falling back to `describe-training-job` and inspecting the
   `OutputDataConfig` / `ModelArtifacts` — for MTRL runs, the output
   model package is also registered in the `ModelPackageGroup` chosen at
   training time.

Confirm the resolved `MODEL_PACKAGE_ARN` with the user before proceeding.

### Step 2: Determine Instance Type

For this step, you need: **the SageMaker instance type.**

Recommend an instance based on model size, using the deterministic helper
`scripts/instance_recommender.py::recommend_instance_type(model_size_b)`.
The helper encodes the same table the OSS LoRA pathway uses (Property 11
parity):

| Model size       | Instance type     | GPUs / VRAM      |
| ---------------- | ----------------- | ---------------- |
| Small (< 3B)     | `ml.g5.2xlarge`   | 1 GPU, ~24GB     |
| Medium (< 10B)   | `ml.g5.12xlarge`  | 4 GPUs, ~96GB    |
| Large (≥ 10B)    | `ml.g6e.48xlarge` | 8 GPUs, ~1TB     |

Pass the recommendation to the user with reasoning and ask them to confirm.
If they would like a different instance type, accept their choice. If you
think it will cause issues (for example, not enough GPU memory for the
model), call that out.

⏸ Wait for user to confirm before moving on.

### Step 3: Verify IAM Role

Use the IAM role from the training job (extracted in Step 1 of the main
workflow via `describe-training-job`). This role should already have the
necessary SageMaker and S3 permissions. Confirm with the user.

### Step 4: Confirm Region

The region was identified in Step 1 of the main workflow. Confirm it with
the user.

### Step 5: Suggest Endpoint Name

Suggest an endpoint name based on the project (lowercase, alphanumeric
with hyphens). Confirm with the user.

### Step 6: Confirm Configuration

> "Here's the deployment setup:
>
> - Target: SageMaker Endpoint
> - Model Type: MTRL
> - Model Package ARN: [arn]
> - Instance Type: [type]
> - IAM Role: [arn]
> - Region: [region]
> - Endpoint Name: [name]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 7: Generate Notebook

If a project directory already exists (from earlier in the workflow), use
it. Otherwise, activate the **directory-management** skill to set one up.

Check if the project notebook already exists at
`<project-dir>/notebooks/<project-name>.ipynb`.

- If it exists → ask: _"Would you like me to append the deployment cells to
  the existing notebook, or create a new one?"_
- If it doesn't exist → create it.

When appending, add a markdown header cell `## Model Deployment — SageMaker
(MTRL)` as a section divider before the new cells.

⏸ Wait for user.

## Notebook Structure

### Markdown Header

```json
{
  "cell_type": "markdown",
  "metadata": {},
  "source": [
    "# Deploy MTRL Model to SageMaker Endpoint"
  ]
}
```

### Cells

Each cell's content comes from `../scripts/deploy-mtrl-sagemaker.py`,
split on the `# Cell N:` comments.

- **Cell 1**: Setup (pip install)
- **Cell 2**: Configuration (REGION, INSTANCE_TYPE, MODEL_PACKAGE_ARN,
  ROLE_ARN, ENDPOINT_NAME, ACCEPT_EULA)
- **Cell 3**: Build Model (`ModelBuilder(model=ModelPackage.get(...))`)
- **Cell 4**: Deploy Endpoint
  (`model_builder.deploy(endpoint_name=..., instance_type=...,
  initial_instance_count=1)`)
- **Cell 5**: Test Inference
  (`sagemaker-runtime invoke_endpoint`)

### Placeholders

Cell 2:

- `[REGION]` → AWS region (string)
- `[INSTANCE_TYPE]` → SageMaker instance type (e.g., `ml.g5.2xlarge`)
- `[MODEL_PACKAGE_ARN]` → ARN of the MTRL training output model package
- `[ROLE_ARN]` → IAM execution role ARN
- `[ENDPOINT_NAME]` → Name for the endpoint (agent generates a default,
  user confirms)
- `[ACCEPT_EULA]` → Python literal `True` if the user accepted the
  license in Step 4 of the main workflow, `False` otherwise.

### Step 8: Explicitly State EULA Acceptance

Before the user runs the notebook, confirm the EULA acceptance from Step 4
of the main workflow. Tell the user:

> "Since you accepted the license agreement, I've set EULA acceptance to
> `True` in the deployment code."

If the user did not accept the license, tell them deployment cannot
continue without license acceptance.

For Meta/Llama base models, the EULA cannot be auto-accepted — the helper
returns `(False, "...")` regardless of confirmation state, and the user
must manually flip `ACCEPT_EULA = True` in the cell after reading the
license. Surface this to the user verbatim using the helper's message.

### Step 9: Provide Run Instructions

```
To run:
1. Cell 1 — install/upgrade SageMaker SDK
2. Cell 2 — configuration and imports (resolves ModelPackage)
3. Cell 3 — builds the model via ModelBuilder
4. Cell 4 — deploys to endpoint (waits for endpoint to be InService,
   ~5-10 min)
5. Cell 5 — test inference with a sample prompt
```

## Common Issues

- **"No module named 'sagemaker.serve'"**: Upgrade SDK:
  `pip install --upgrade 'sagemaker>=3.7.1,<4.0'`
- **"Provided IAM role could not be assumed"**: Ensure the role's trust
  policy allows `sagemaker.amazonaws.com`.
- **Endpoint creation fails with "Insufficient capacity"**: Try a
  different instance type or region.
- **EULA not accepted**: For gated base models, the SDK raises a
  `ValidationException`. Re-run with `ACCEPT_EULA = True` after reading
  the license, or use the helper's confirmation flow.

## Post-Deployment Summary

After the notebook runs successfully, tell the user:

- **Endpoint**: `[ENDPOINT_NAME]` is now InService
- **How to invoke**: Use SageMaker runtime `InvokeEndpoint` with a JSON
  body matching the model's input schema (see Cell 5 for an example).
- **Billing**: This endpoint is billed by the hour while running, even
  when idle. Delete it when you're done testing.
- **Cleanup**: Delete the endpoint using the AWS MCP tool
  `delete-endpoint` (SageMaker service) with `[ENDPOINT_NAME]`.
