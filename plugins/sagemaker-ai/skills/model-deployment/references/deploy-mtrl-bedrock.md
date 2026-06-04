# Deploy MTRL-trained Model to Bedrock

## Scenario

- **Model Type**: MTRL (Multi-Turn Reinforcement Learning)
- **Fine-tuning Method**: LoRA
- **Deployment Target**: Bedrock (Custom Model or Custom Model Import)
- **Approach**: SageMaker PySdk `BedrockModelBuilder` from
  `sagemaker.serve.bedrock_model_builder`

## Overview

Uses the SageMaker PySdk `BedrockModelBuilder` to register an
MTRL-trained model package with Bedrock. The builder takes the
`ModelPackage` directly (the MTRL trainer registers the output as a
package in a `ModelPackageGroup`), and the deploy call picks one of two
kwarg shapes depending on the source JumpStart model family:

- **Nova-family** base models (id starts with `nova-`) → register as a
  Bedrock **custom model** via `custom_model_name=`.
- **All other** base models (Llama, Mistral, GPT-OSS, Qwen, etc.) →
  register as a Bedrock **imported model** via `imported_model_name=`.

Both calls also pass `role_arn=` and `deployment_name=`. The selection is
deterministic and is computed by
`scripts/bedrock_deploy_selector.py::select_bedrock_deploy_kwarg(jumpstart_model_id)`.

This pattern matches the `bedrock-s1-deploy` / `bedrock-s2-deploy` cells
in `mtrl_dogfooding_notebook.ipynb`. Requires `sagemaker>=3.7.0`.

**Required inputs** (collected in the steps below):

- Model package ARN (from the MTRL training job's
  `output_model_package_arn`)
- IAM role ARN (with Bedrock trust policy and S3 read access)
- AWS region
- Deployment name (suggested by the agent, confirmed by the user)
- JumpStart model id (used by the agent to pick the right deploy kwarg)

## Prerequisites

### Region

Bedrock Custom Model Import is available in: `us-east-1`, `us-east-2`,
`us-west-2`, `eu-central-1`. Bedrock custom-model registration for Nova
follows Bedrock's regional availability for Nova; check with the user.

### SDK Version

Requires `sagemaker>=3.7.1` with `BedrockModelBuilder` support.

## Workflow

### Step 1: Gather Training Job and Model Package ARN

The training job name was identified in Step 1 of the main workflow.
Confirm you have it. Resolve the **output model package ARN** for the
MTRL run by reading `output_model_package_arn` from the training job's
metadata. Confirm `MODEL_PACKAGE_ARN` with the user.

### Step 2: Determine the Bedrock Deploy Kwarg

For this step, you need: **the JumpStart model id of the base model the
MTRL run started from.** Look it up from the training job's
`sagemaker-studio:jumpstart-model-id` tag (already gathered in Step 1 of
the main workflow).

Pick the right deploy kwarg using
`scripts/bedrock_deploy_selector.py::select_bedrock_deploy_kwarg(jumpstart_model_id)`:

- `jumpstart_model_id` starts with `nova-` → `custom_model_name`
- otherwise → `imported_model_name`

Both calls also pass `role_arn=` and `deployment_name=`.

The selected kwarg name fills the `[DEPLOY_KWARG_NAME]` placeholder in
Cell 4 of `../scripts/deploy-mtrl-bedrock.py`. Do not present this
choice to the user — it is deterministic — but record it in the
configuration summary so the user can verify.

### Step 3: Suggest Deployment Name

Suggest a deployment name based on the project (lowercase, alphanumeric
with hyphens). Confirm with the user.

### Step 4: Verify IAM Role

Use the IAM role from the training job (extracted in Step 1 of the main
workflow via `describe-training-job`). The role must have
`bedrock.amazonaws.com` in its trust policy and S3 read permissions on
the model bucket. Confirm with the user.

### Step 5: Confirm Region

The region was identified in Step 1 of the main workflow. Confirm it is
in the supported list above. If not, tell the user that Bedrock
deployment is not supported for this model in this region.

### Step 6: Confirm Configuration

> "Here's the deployment setup:
>
> - Target: Bedrock
> - Model Type: MTRL
> - Model Package ARN: [arn]
> - Base model id: [jumpstart_model_id]
> - Deploy kwarg: [custom_model_name | imported_model_name]
> - IAM Role: [arn]
> - Region: [region]
> - Deployment Name: [name]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 7: Generate Notebook

If a project directory already exists (from earlier in the workflow), use
it. Otherwise, activate the **directory-management** skill to set one up.

Check if the project notebook already exists at
`<project-dir>/notebooks/<project-name>.ipynb`.

- If it exists → ask: _"Would you like me to append the deployment cells
  to the existing notebook, or create a new one?"_
- If it doesn't exist → create it.

When appending, add a markdown header cell `## Model Deployment — Bedrock
(MTRL)` as a section divider before the new cells.

⏸ Wait for user.

## Notebook Structure

### Markdown Header

```json
{
  "cell_type": "markdown",
  "metadata": {},
  "source": [
    "# Deploy MTRL Model to Bedrock"
  ]
}
```

### Cells

Each cell's content comes from `../scripts/deploy-mtrl-bedrock.py`,
split on the `# Cell N:` comments.

- **Cell 1**: Setup (pip install)
- **Cell 2**: Configuration (REGION, MODEL_PACKAGE_ARN, ROLE_ARN,
  DEPLOYMENT_NAME)
- **Cell 3**: Build
  (`BedrockModelBuilder(model=ModelPackage.get(...))`)
- **Cell 4**: Deploy (template literal — replace
  `[DEPLOY_KWARG_NAME]` with `custom_model_name` or
  `imported_model_name` before writing into the notebook)
- **Cell 5**: Test Inference (`bedrock-runtime invoke_model`)

### Placeholders

Cell 2:

- `[REGION]` → AWS region (string)
- `[MODEL_PACKAGE_ARN]` → ARN of the MTRL training output model package
- `[ROLE_ARN]` → IAM role ARN with Bedrock trust policy
- `[DEPLOYMENT_NAME]` → Name for the Bedrock deployment

Cell 4:

- `[DEPLOY_KWARG_NAME]` → either `custom_model_name` (Nova-family) or
  `imported_model_name` (everything else). The agent computes this with
  `scripts/bedrock_deploy_selector.py::select_bedrock_deploy_kwarg`.
  Cell 4 in the source file is a **template literal** (wrapped in a
  triple-quoted string) so the unrendered file parses as valid Python;
  unwrap and substitute when writing the cell into the notebook.

### Step 8: Provide Run Instructions

```
To run:
1. Cell 1 — install/upgrade SageMaker SDK
2. Cell 2 — configuration and imports (resolves ModelPackage)
3. Cell 3 — builds the model via BedrockModelBuilder
4. Cell 4 — deploys to Bedrock (with the substituted deploy kwarg;
   ~5-10 min)
5. Cell 5 — test inference with a sample prompt
```

## Common Issues

- **"No module named 'sagemaker.serve.bedrock_model_builder'"**:
  Upgrade SDK: `pip install --upgrade 'sagemaker>=3.7.1,<4.0'`.
- **"Provided IAM role could not be assumed"**: Ensure the role's trust
  policy allows `bedrock.amazonaws.com`.
- **"Access denied to S3"**: Add S3 read permissions to the IAM role for
  the model bucket.
- **Wrong deploy kwarg**: If Bedrock returns a validation error about
  `imported_model_name` vs `custom_model_name`, check the JumpStart
  model id prefix — Nova models must use `custom_model_name`.
- **Region not supported**: Bedrock CMI is limited to the regions listed
  in Prerequisites. Choose a different region or pick the SageMaker
  endpoint pathway.

## Post-Deployment Summary

After the notebook runs successfully, tell the user:

- **Deployment**: `[DEPLOYMENT_NAME]` is now registered with Bedrock.
- **How to invoke**: Use Bedrock runtime `invoke_model` with the
  deployment name as `modelId` (see Cell 5 for an example).
- **Billing**: Pay per request — no cost while idle.
- **Cleanup**: When done, delete the deployment using the AWS MCP tool
  `delete-imported-model` (Bedrock service, for `imported_model_name`)
  or `delete-custom-model` (for `custom_model_name`) with
  `[DEPLOYMENT_NAME]`.
