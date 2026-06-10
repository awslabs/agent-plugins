---
name: finetuning-technique
description: Selects a fine-tuning technique (SFT, DPO, RLVR, or RLAIF) for the user's use case and validates it against the selected model's available recipes. Use when the user has decided to finetune and needs to choose a technique, or when the technique needs to be validated against a model. Requires a base model to already be selected (via model-selection skill).
metadata:
  version: "1.0.0"
---

# Finetuning Technique

Guides the user through selecting a fine-tuning technique based on their use case and validates compatibility with the selected model.

## When to Use

- User has decided to finetune and needs to choose a technique
- User wants to change their finetuning technique
- Technique needs to be validated against a selected model

## Prerequisites

- A base model has been selected (via model-selection skill). The model name and hub must be known.
- A `use_case_spec.md` file exists. If not, activate the use-case-specification skill to generate it first.

## Workflow

### Step 1: Determine Finetuning Technique

Consult `references/finetune_technique_selection_guide.md` to recommend the best-fit technique based on the use case and the user's needs (SFT, DPO, RLVR, RLAIF).

Present the recommendation and reasoning to the user. Ask if they'd like to go with the recommendation or prefer a different technique.

### Step 2: Validate Technique Availability

1. Once the user confirms a technique, retrieve the finetuning techniques available for the selected model by running: `python finetuning-technique/scripts/get_recipes.py <model-name> <hub-name>`
   - This returns only the techniques the model actually supports, filtered to SFT, DPO, RLVR, and RLAIF. Only these four techniques are supported — ignore any other techniques even if the model's recipes include them.
2. If the chosen technique is available for the model, proceed to Step 3.
3. If the chosen technique is not available for the model, explain that the selected model does not support it on SageMaker and offer to go back to model-selection to pick a different model that supports the chosen technique.

### Step 3: Confirm Selections

Present a summary to the user:

```
Here's what we've selected:
- Base model: [model name]
- Fine-tuning technique: [SFT/DPO/RLVR/RLAIF]
```

## References

- `references/finetune_technique_selection_guide.md` — Technique guidance (SFT/DPO/RLVR/RLAIF)
