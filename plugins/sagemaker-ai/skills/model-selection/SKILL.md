---
name: model-selection
description: Selects a base model for the user's use case by querying SageMaker Hub. Use when the user asks which model to use, wants to select or change their base model, mentions a model name or family (e.g., "Llama", "Mistral", "Nova"), or wants to evaluate a base model — always activate even for known model names because the exact Hub model ID must be resolved. Queries available models, presents benchmarks and licenses, and confirms selection.
metadata:
  version: "1.0.0"
---

# Model Selection

Guides the user through selecting a base model based on their use case.

## When to Use

- User asks which model to use
- User wants to select or change their base model
- User mentions a model name or family (e.g., "Llama", "Mistral", "Nova") — the exact Hub model ID still needs to be resolved
- User wants to evaluate a base model before deciding whether to finetune

## Prerequisites

- A `use_case_spec.md` file exists. If not, activate the use-case-specification skill to generate it first.

## Workflow

### Step 1: Check Region

Run:

```
python -c "import boto3; print(boto3.session.Session().region_name)"
```

- `None` → STOP. Tell user: "Set your region via `export AWS_DEFAULT_REGION=us-west-2` or `aws configure`."
- Set → store REGION in context, continue.

### Step 2: Discover Hub

1. List all available SageMaker Hubs in the user's region by calling the SageMaker `ListHubs` API using the `aws___call_aws` tool.
2. From the results, filter out any hub whose `HubDescription` contains "AI Registry" — these do not contain JumpStart models.
3. The remaining hubs are eligible (e.g., `SageMakerPublicHub` and any private hubs).
4. If exactly one eligible hub exists, use it automatically — do not ask the user.
5. If multiple eligible hubs exist, present them to the user and ask which one to use. Example:

   ```
   I found the following model hubs:
   - SageMakerPublicHub — SageMaker Public Hub
   - Private-Hub-XYZ — Private Hub models
   Which hub would you like to use?
   ```

6. Store the selected hub name for use in subsequent steps.

### Step 3: Select Base Model

First, retrieve all available SageMaker Hub model names by running: `python model-selection/scripts/get_model_names.py <hub-name>`.

Present all available models to the user with their licenses before making any recommendations. Cross-reference the model list with `references/model-licenses.md` and display each as `<model name> - [<license>](<url>)`. For example: "Qwen3-4B - [Apache 2.0](https://huggingface.co/Qwen/Qwen3-4B/blob/main/LICENSE)"

If you already know the model the user wants to use (from conversation context or planning files), confirm that it's in the list, display its license, and move on. Otherwise, help the user pick a model following the instructions in `references/model-selection.md`.
**Important:** Make sure to remember this list of available models when helping with model selection. Don't recommend a model that's not available to the user.

### Step 4: Confirm Selection

Present a summary to the user:

```
Here's what we've selected:
- Base model: [model name]
```

Ask if they'd like to proceed with this model.

## References

- `references/model-selection.md` — Model selection instructions and benchmark descriptions
- `references/model-licenses.md` — Model license information for display during model selection
