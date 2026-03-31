---
name: finetuning
description: Generates a Jupyter notebook that fine-tunes a base model using SageMaker serverless training jobs. Use when the user says "start training", "fine-tune my model", "I'm ready to train", or when the plan reaches the finetuning step. Supports SFT, DPO, and RLVR trainers, including RLVR Lambda reward function creation.
metadata:
  version: "1.0.0"
---

# Prerequisites

Before starting this workflow, verify:

1. A `use_case_spec.md` file exists
   - If missing: Activate the `use-case-specification` skill first, then resume
   - DON'T EVER offer to create a use case spec without activating the use-case-specification skill.

2. A fine-tuning technique (SFT, DPO, or RLVR) and base model have already been selected
   - If missing: Activate the `finetuning-setup` skill to collect what's missing, then resume
   - Don't make recommendations on the spot. You MUST activate the finetuning-setup skill.

3. A base model name available on SageMakerHub has been identified
   - If missing: Activate the `finetuning-setup` skill to get it
   - **Important:** Only use the model name that `finetuning-setup` retrieves, as it may differ from other commonly used names for the same model

# Critical Rules

## Code Generation Rules

- ✅ Use EXACTLY the imports shown in each cell template
- ❌ Do NOT add additional imports even if they seem helpful
- ❌ Do NOT create variables before they're needed in that cell
- 📋 Copy the code structure precisely - no improvisation
- 🎯 Follow the minimal code principle strictly
- ✅ When writing a notebook cell, make sure the indentation and f strings are correct

## User Communication Rules

- ❌ NEVER offer to run the notebook for the user (you don't have the tools)
- ❌ NEVER offer to move on to a downstream skill while training is in progress (logically impossible)
- ❌ NEVER set ACCEPT_EULA to True yourself (user must read and agree)
- ✅ Always mention both the number AND title of cells you reference
- ✅ If user asks how to run: Tell them to run cells one by one, mention ipykernel requirement

---

# Workflow

## 1. Notebook Setup

### 1.1 Directory Setup

1. Identify project directory from conversation context
   - If unclear (multiple relevant directories exist) → Ask user which folder to use
2. Create Jupyter notebook: `[title]_finetuning.ipynb`
   - `[title]` = snake_case name derived from use case
   - Save under the identified directory

### 1.2 Select Reference Template

Read the example notebook matching the finetuning strategy:

- SFT → `references/sft_example.md`
- DPO → `references/dpo_example.md`
- RLVR → `references/rlvr_example.md`

### 1.3 Copy Notebook Structure

1. Write the exact cells from the example to `[title]_finetuning.ipynb`
2. Use same order, dependencies, and imports as the example
3. DO NOT improvise or add extra code

### 1.4 Auto-Generate Configuration Values

**In the 'Setup & Credentials' cell, populate:**

1. **BASE_MODEL**
   - Use the exact SageMakerHub model name from context

2. **MODEL_PACKAGE_GROUP_NAME**
   - Generate from use case (read `use_case_spec.md` if needed)
   - Format rules:
     - Lowercase, alphanumeric with hyphens only
     - 1-63 characters
     - Pattern: `[a-zA-Z0-9](-*[a-zA-Z0-9]){0,62}`
     - Example: "Customer Support Chatbot" → `customer-support-chatbot-v1`

3. Save notebook

## 2. RLVR Reward Function (for RLVR only, skip this section if technique is SFT or DPO)

### 2.1 Check Reward Function Status

- Ask if user has a reward function already, or would like help creating one.
  - If user says they have one → Ask for the SageMaker Hub Evaluator ARN. Only proceed to Section 2.3 once the user provides a valid Evaluator ARN. If they don't have it registered as a SageMaker Hub Evaluator, continue to 2.2.
  - If user says they do not have one → Continue to 2.2

### 2.2 Generate Reward Function From Template

1. Follow workflow in `references/rlvr_reward_function.md` section "Helping Users Create Lambda Functions"

### 2.3 Set CUSTOM_REWARD_FUNCTION value

1. Set the value for `CUSTOM_REWARD_FUNCTION` in the Notebook with the ARN of the reward function (either given directly by the user, or from the function generation code as `evaluator.arn`).

## 3. EULA review and acceptance

1. Look up the official EULA link for the selected base model from references/eula_links.md
2. Display the EULA link(s) to the user in your message as clickable markdown links
3. Tell the user they must read and agree to the EULA before using this model (one sentence)
4. Ask them to manually change `ACCEPT_EULA` to `True` in the notebook after reviewing the license
5. **NEVER set ACCEPT_EULA to True yourself**

## 4. Notebook Execution

1. **Display the following to the user:**: `A Jupyter notebook has now been generated which will help you finetune your model. You are free to run it now. Please let me know once the training is complete.`
2. Wait for user's confirmation about training completion. Once the user has confirmed this, you are free to move to the next step of the plan.

**CRITICAL:**

- DON'T suggest moving to next steps before training completes
- DON'T elaborate on the next steps unless the user specifically asks you about them.

---

# References

- `rlvr_reward_function.md` - Lambda reward function creation guide (RLVR only)
- `templates/rlvr_reward_function_source_template.py` - Lambda reward function source template for open-weights models (RLVR only)
- `templates/nova_rlvr_reward_function_source_template.py` - Lambda reward function source template for Nova 2.0 Lite (RLVR only)
- `sft_example.md` - Complete notebook template for Supervised Fine-Tuning
- `dpo_example.md` - Complete notebook template for Direct Preference Optimization
- `rlvr_example.md` - Complete notebook template for Reinforcement Learning from Verifiable Rewards
