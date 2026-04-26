---
name: finetuning-setup
description: Selects a base model and fine-tuning technique (SFT, DPO, or RLVR) for the user's use case by querying SageMaker Hub. Use when the user asks which model or technique to use, wants to start fine-tuning, or mentions a model name or family (e.g., "Llama", "Mistral") — always activate even for known model names because the exact Hub model ID must be resolved. Queries available models, validates technique compatibility, and confirms selections.
metadata:
  version: "1.0.0"
---

# Finetuning Setup

Guides the user through selecting a base model and fine-tuning technique based on their use case.

## When to Use

- User asks which fine-tuning technique to use
- User wants to select or change their base model
- User mentions a model name or family (e.g., "Llama", "Mistral") — the exact Hub model ID still needs to be resolved

## Prerequisites

- A `use_case_spec.md` file exists. If not, activate the use-case-specification skill to generate it first.

## Workflow

### Step 1: Discover Hub

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

### Step 2: Select Base Model

First, retrieve all available SageMaker Hub model names by running: `python finetuning-setup/scripts/get_model_names.py <hub-name>`.

Present all available models to the user with their licenses before making any recommendations. Cross-reference the model list with `references/model-licenses.md` and display each as `<model name> - [<license>](<url>)`. For example: "Qwen3-4B - [Apache 2.0](https://huggingface.co/Qwen/Qwen3-4B/blob/main/LICENSE)"

If you already know the model the user wants to use (from conversation context or planning files), confirm that it's in the list, display its license, and move on. Otherwise, help the user pick a model following the instructions in `references/model-selection.md`.
**Important:** Make sure to remember this list of available models when helping with model selection. Don't recommend a model that's not available to the user.

### Step 3: Determine Finetuning Technique

1. Consult `references/finetune_technique_selection_guide.md` and recommend the best-fit technique (SFT, DPO, or RLVR) for the use case. Present the recommendation and reasoning to the user.
2. Ask the user if they'd like to go with the recommendation or prefer a different technique.
3. Once the user confirms a technique, retrieve the finetuning techniques available for the selected model by running: `python finetuning-setup/scripts/get_recipes.py <model-name> <hub-name>`
   - This returns only the techniques the model actually supports, filtered to SFT, DPO, and RLVR. Only these three techniques are supported — ignore any other techniques even if the model's recipes include them.
4. If the chosen technique is available for the model, proceed to Step 4.
5. If the chosen technique is not available for the model, explain that the selected model does not support it on SageMaker and offer to go back to Step 2 to pick a different model that supports the chosen technique.

### Step 4: Confirm Selections

Present a summary to the user:

```
Here's what we've selected:
- Base model: [model name]
- Fine-tuning technique: [SFT/DPO/RLVR]
```

## References

- `references/model-selection.md` — Model selection instructions and benchmark descriptions
- `references/finetune_technique_selection_guide.md` — Technique guidance
- `references/model-licenses.md` — Model license information for display during model selection
