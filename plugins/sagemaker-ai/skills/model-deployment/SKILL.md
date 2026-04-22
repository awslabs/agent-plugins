---
name: model-deployment
description: Generates a Jupyter notebook that deploys fine-tuned models from SageMaker Serverless Model Customization to SageMaker endpoints or Bedrock. Use when the user says "deploy my model", "create an endpoint", "make it available", or asks about deployment options. Identifies the correct deployment pathway (Nova vs OSS), generates deployment code, and handles endpoint configuration.
metadata:
  version: "1.0.0"
---

# Model Deployment

Identifies the correct deployment pathway based on model characteristics and generates deployment code.

## Scope

This skill supports deploying Nova and OSS models that were fine-tuned through **SageMaker Serverless Model Customization** only.

**Not supported:**

- Base models (not fine-tuned)
- Models fine-tuned through other processes
- Full Fine-Tuning (FFT) — only LoRA fine-tuned models are supported

## Principles

1. **One thing at a time.** Each response advances exactly one decision.
2. **Confirm before proceeding.** Wait for the user to agree before moving on. But don't re-ask questions already answered in the conversation — use what you know.
3. **Don't read files until you need them.** Only read pathway references after the pathway is confirmed.
4. **Use what you know.** If conversation history or artifacts already answer a question, confirm your understanding instead of asking again.
5. **Notebook writing.** Write notebooks using your standard file write tool to create the `.ipynb` file with the complete notebook JSON, OR use notebook MCP tools (e.g., `create_notebook`, `add_cell`) if available. Do NOT use bash commands, shell scripts, or `echo`/`cat` piping to generate notebooks.

## Workflow

### Step 1: Identify the Training Job

You need the training job name or ARN. Check the conversation history first — the user may have already mentioned it, or it may be available from earlier steps in the workflow (e.g., fine-tuning). If not, ask the user.

Once you have the training job name or ARN, use the AWS MCP tool to look it up:

1. Use the AWS MCP tool `describe-training-job` and extract:
   - **S3 output path** (from `ModelArtifacts.S3ModelArtifacts` or `OutputDataConfig.S3OutputPath`)
   - **IAM role ARN** (from `RoleArn`)
   - **Region**
2. Use the AWS MCP tool `list-tags` on the training job ARN and extract:
   - **Model ID** from the `sagemaker-studio:jumpstart-model-id` tag
3. Determine the **model type** from the model ID:
   - Contains "nova" (nova-micro, nova-lite, nova-pro) → **Nova**
   - Llama, Mistral, Qwen, GPT-OSS, DeepSeek, etc. → **OSS**

**Unsupported models:** This skill only supports OSS and Nova models that were LoRA fine-tuned through SageMaker Serverless Model Customization. If the model doesn't match, tell the user this skill can't help and suggest the finetuning skill.

### Step 2: Determine Eligible Deployment Targets

Use the following table:

| Model Type | Eligible Targets   |
| ---------- | ------------------ |
| OSS        | SageMaker, Bedrock |
| Nova       | SageMaker, Bedrock |

If only one target is eligible, confirm it with the user. Use details from Step 5.

If multiple targets are eligible, help the user decide. Use details from Step 5.

If no targets are eligible, tell the user and explain why.

### Step 3: Let the User Choose a Deployment Target

Present the eligible options to the user. Present these details to help them decide between SageMaker and Bedrock, if both are available options:

**SageMaker Endpoint:**

- Dedicated compute resources for consistent performance
- Control instance types and scaling
- Best for predictable workloads with specific latency requirements

**Bedrock:**

- Fully managed serverless inference
- Auto-scales instantly with no capacity planning
- Pay per request
- Best for variable workloads with fluctuating demand

Do NOT make a recommendation. Let the user choose.

Do NOT mention technical details like merged/unmerged weights, reference files, or APIs, unless the user asks.

⏸ Wait for user to select a deployment option.

### Step 4: Display License Agreement

Before proceeding to deployment, display the model's license or service terms to the user.

1. Read `references/model-licenses.md` and look up the model by its model ID (determined in Step 1).
2. Follow the instructions in the Notes column — use the exact phrasing provided.
3. If the model ID is not found in the table, warn the user that you could not find license information for their model and recommend they verify the license independently before proceeding.

⏸ Wait for the user to confirm before proceeding.

### Step 5: Follow Pathway Workflow

Read the reference file for the selected pathway and follow its instructions.

| Model Type | Deployment Target | Reference                             |
| ---------- | ----------------- | ------------------------------------- |
| OSS        | SageMaker         | `references/deploy-oss-sagemaker.md`  |
| OSS        | Bedrock           | `references/deploy-oss-bedrock.md`    |
| Nova       | SageMaker         | `references/deploy-nova-sagemaker.md` |
| Nova       | Bedrock           | `references/deploy-nova-bedrock.md`   |

### Step 6: Post-Deployment Summary

After deployment completes, provide the user with a summary. Cover these topics, using details from the pathway reference doc you followed in Step 5:

- **What was deployed** — endpoint or model name, ARN, status
- **How to use it** — sample invoke code for the specific deployment target
- **Cost** — billing model (instance-based vs. pay-per-request) and what to expect
- **Cleanup** — how to delete the endpoint or model when done

## Troubleshooting

### How to check if a model was LoRA or FFT fine-tuned

If deployment fails unexpectedly, the model may have been full fine-tuned (FFT) rather than LoRA. To check, download the training job's hydra config from its S3 output path at `.hydra/config.yaml`:

- `peft_config` populated (r, alpha, dropout, etc.) → **LoRA** (supported)
- `peft_config: null` → **FFT** (not supported by this skill)
