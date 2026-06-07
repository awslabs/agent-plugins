---
name: finetuning
description: Generates code that fine-tunes a base model using SageMaker serverless training jobs. Use when the user says "start training", "fine-tune my model", "I'm ready to train", or when the plan reaches the finetuning step. Supports SFT, DPO, RLVR, and RLAIF trainers, including RLVR Lambda reward function and RLAIF custom prompt creation.
metadata:
  version: "1.0.0"
---

# Prerequisites

Before starting this workflow, verify:

1. A `use_case_spec.md` file exists
   - If missing: Activate the `use-case-specification` skill first, then resume
   - DON'T EVER offer to create a use case spec without activating the use-case-specification skill.

2. A fine-tuning technique (SFT, DPO, RLVR, RLAIF, or CPT/RFT (for Nova)) and base model have already been selected
   - If missing: Activate the `model-selection` and/or `finetuning-technique` skills to collect what's missing, then resume
   - Don't make recommendations on the spot. You MUST activate the appropriate skill.

3. A base model name available on SageMakerHub has been identified
   - If missing: Activate the `model-selection` skill to get it
   - **Important:** Only use the model name that `model-selection` retrieves, as it may differ from other commonly used names for the same model

4. The SDK environment has been verified (SDK version, region, execution role)
   - If not done: Activate the `sdk-getting-started` skill first, then resume

5. A training dataset uploaded to a bucket in the environment's default region.
   - If not met: Help the user upload the dataset to the correct S3

## Model Path Dispatch

Determine the model family from the model-selection results.

**If the selected model is Nova** (Nova Micro, Lite, Lite 2, Pro) → Use the Nova path below. The Nova path uses the Forge SDK (`amzn-nova-forge`) and `ForgeTrainer`. Read `references/code_output_guide.md` for mode selection (notebook vs script) and formatting rules. Construct the code from the Nova reference files, then write it to a file following `code_output_guide.md` conventions.

**Nova path prerequisite:** The Nova Forge SDK must be installed before proceeding. If the user hasn't completed the `sdk-getting-started` skill yet, instruct them to run `pip install amzn-nova-forge` and verify with `from amzn_nova_forge import ForgeTrainer`. For HyperPod (SMHP) workflows, the Forge-specific HyperPod CLI must also be installed — see the `sdk-getting-started` skill for details.

**Runtime platform selection:** Before generating code, determine which runtime platform to use. If the user hasn't specified, ask:

> "Which runtime platform would you like to use?
>
> - **SMTJ (SageMaker Training Jobs) Serverless** — Simplest, no instance management (recommended if unsure)
> - **SMTJ (SageMaker Training Jobs)** — Full instance control (SFT/RFT/DPO)
> - **SMHP (SageMaker HyperPod)** — Required for CPT, data mixing, RFT Multiturn
> - **Bedrock** — Fully managed"

If the user says they don't know or want the simplest option, default to `SMTJServerlessRuntimeManager`. Platform-to-class mapping:

| User selects    | Use class                      | Notes                                         |
| --------------- | ------------------------------ | --------------------------------------------- |
| SMTJ Serverless | `SMTJServerlessRuntimeManager` | Default, no instance config needed            |
| SMTJ            | `SMTJRuntimeManager`           | Requires `instance_type` and `instance_count` |
| SMHP (HyperPod) | `SMHPRuntimeManager`           | Required for CPT, data mixing, RFT Multiturn  |
| Bedrock         | `BedrockRuntimeManager`        | Fully managed, no instance config needed      |

**If user selects SMHP:** A pre-existing HyperPod cluster with a Restricted Instance Group (RIG) is required — Nova customization on HyperPod only works with RIGs. The SDK connects to an existing cluster, it does not create one. Do NOT offer to create a HyperPod cluster or RIG — this is an infrastructure task outside this skill's scope. If the user doesn't have a cluster with RIG, advise them to work with their infrastructure team. Ask the user for:

- **Cluster name** (e.g., `my-hyperpod-cluster`)
- **Namespace** (e.g., `default` or `kubeflow`)
- **Instance type** (e.g., `ml.p5.48xlarge`)
- **Instance count** (e.g., 4)

The HyperPod CLI must also be installed (handled by `sdk-getting-started` skill Step 5).

### Nova Reference Loading Guide

| User's task                            | Read this reference                                                                     |
| -------------------------------------- | --------------------------------------------------------------------------------------- |
| Standard training (SFT, RFT, DPO, CPT) | `references/nova-training-workflow.md`                                                  |
| Hyperparameter selection / tuning      | `references/nova-hyperparameter-guidance.md`                                            |
| Valid enum values for code generation  | `references/nova-enums.md`                                                              |
| Multi-stage / checkpoint chaining      | `references/nova-iterative-training.md`                                                 |
| RFT Multiturn (requires SMHP)          | `references/nova-rft-multiturn-setup.md` + `references/nova-rft-multiturn-reference.md` |
| Instance type questions                | `references/nova-instance-types.md`                                                     |
| Reward function testing (RFT)          | `references/nova-verify-reward-function.md`                                             |

**If the selected model is OSS** (Llama, Mistral, Qwen, etc.) → Follow the OSS workflow below, which generates a Jupyter notebook using SageMaker SDK v3.

---

# Critical Rules

## Code Generation Rules

- ✅ Use EXACTLY the imports shown in each code template
- ❌ Do NOT add additional imports even if they seem helpful
- ❌ Do NOT create variables before they're needed in that section
- 📋 Copy the code structure precisely - no improvisation
- 🎯 Follow the minimal code principle strictly
- ✅ When writing code, make sure the indentation and f strings are correct

## User Communication Rules

- ❌ NEVER offer to move on to a downstream skill while training is in progress (logically impossible)
- ❌ NEVER set ACCEPT_EULA to True without explicit user confirmation in the conversation
- ✅ Always mention both the number AND title of sections you reference
- ✅ If user asks how to run (notebook): If `run_cell` is available, offer to run it. Otherwise, tell them to run cells one by one (mention ipykernel requirement).
- ✅ If user asks how to run (script): Tell them to run with `python3 <script>.py`

---

# Workflow

## 1. Code Generation Setup

### 1.1 Directory Setup

1. Identify project directory from conversation context
   - If unclear (multiple relevant directories exist) → Ask user which folder to use
   - If no project directory exists → activate the **directory-management** skill to set one up

⏸ Wait for user.

### 1.2 Select Code Template

Read `references/code_output_guide.md` for output format rules, then read the code template matching the finetuning strategy:

- SFT → `code_templates/sft.py`
- DPO → `code_templates/dpo.py`
- RLVR → `code_templates/rlvr.py`
- RLAIF with built-in rewards → `code_templates/rlaif_builtin.py`
- RLAIF with custom prompt → `code_templates/rlaif_custom_prompt.py`

The template is a Python file where each `# Cell N: Label` comment marks the start of a new section. Split on these markers — everything between one marker and the next becomes one unit of output.

### 1.3 Generate Code

1. Write the code from the template following the rules in `code_output_guide.md`
2. Use same order, dependencies, and imports as the template
3. DO NOT improvise or add extra code
4. If the model is **NOT** a Meta/Llama model (model ID does NOT start with `meta-`):
   - Omit the `ACCEPT_EULA = False` line from the config cell
   - Omit the `accept_eula=ACCEPT_EULA,` line from the trainer call

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

1. Follow workflow in `references/rlvr_reward_function.md` section "Helping Users Create Custom Reward Functions"

### 2.3 Set CUSTOM_REWARD_FUNCTION value

1. Set the value for `CUSTOM_REWARD_FUNCTION` in the Notebook with the ARN of the reward function (either given directly by the user, or from the function generation code as `evaluator.arn`).

## 3. RLAIF (for RLAIF only, skip this section if technique is not RLAIF)

Read `references/rlaif_guide.md` and follow its instructions.

## 4. EULA review and acceptance

1. Look up the official license link for the selected base model from references/eula_links.md
2. Display the license to the user following the phrasing in references/eula_links.md. For OSS models: "This model is licensed under **{License}**. Please review the license terms here: {URL}." For Nova models: "This model is subject to the AWS Service Terms: {URL}."
3. Check if the selected base model is a Meta/Llama model (model ID starts with `meta-`)
   - **If Meta/Llama**: Tell the user they must read and agree to the EULA before using this model. Ask: "Do you accept the license terms? (yes/no)". If the user confirms, set `ACCEPT_EULA = True` and uncomment `accept_eula=ACCEPT_EULA` in the generated notebook. If the user declines, leave `ACCEPT_EULA = False` and warn that training will fail without acceptance.
   - **If non-Meta**: Inform the user of the license for their awareness. No code-level action needed — the `ACCEPT_EULA` variable and `accept_eula` parameter should already be omitted from the notebook (see Step 1.3).

## 5. Post-Generation

After generating the code, offer to run it. Training can take hours depending on your dataset and model.

**Notebook mode:** If `run_cell` is available, offer to run the cells. Otherwise tell the user to run cells themselves.

**Script mode:** Present the user with options:

> "Would you like me to:
>
> 1. Leave it to you — run with `python scripts/[script_name]`
> 2. Run it and wait until it's done
> 3. Start it but don't wait — we can check status later"

- **Option 1:** Done. Wait for user to come back.
- **Option 2:** Execute the script as-is. `trainer.train(wait=True)` blocks until complete. Report final status.
- **Option 3:** Change `wait=True` to `wait=False` in the script, execute, report the training job name.

**Checking status:**

- `describe-training-job --training-job-name NAME` → `TrainingJobStatus`, `FailureReason`, `SecondaryStatusTransitions`
- For model package ARN after completion: `list-model-packages --model-package-group-name GROUP_NAME --sort-by CreationTime --sort-order Descending --max-results 1`

**Showing results after completion:**

- Use `scripts/mlflow_reference.py` as the pattern to query MLflow metrics
- Present loss by epoch as a text table (total_loss, val_eval_total_loss for SFT; rewards/margins for DPO; critic/rewards/mean for RLVR)

**CRITICAL:**

- DON'T suggest moving to next steps before training completes
- DON'T elaborate on the next steps unless the user specifically asks you about them.

## 6. Continuous Customization

If the user wants to finetune a model they had already customized, follow the instructions in references/continuous_customization.md

---

# References

- `rlvr_reward_function.md` - Lambda reward function creation guide (RLVR only)
- `templates/rlvr_reward_function_source_template.py` - Lambda reward function source template for open-weights models (RLVR only)
- `templates/nova_rlvr_reward_function_source_template.py` - Lambda reward function source template for Nova 2.0 Lite (RLVR only)
- `code_templates/sft.py` - Complete notebook template for Supervised Fine-Tuning (OSS path)
- `code_templates/dpo.py` - Complete notebook template for Direct Preference Optimization (OSS path)
- `code_templates/rlvr.py` - Complete notebook template for Reinforcement Learning from Verifiable Rewards (OSS path)
- `references/continuous_customization.md` - Instructions on fine-tuning an already fine-tuned model.
- `references/nova-training-workflow.md` - Complete Nova Forge SDK training workflow (Nova path)
- `references/nova-iterative-training.md` - Multi-stage checkpoint chaining for Nova (Nova path)
- `references/nova-instance-types.md` - Allowed instance types per Nova model/method/platform (Nova path)
- `references/nova-verify-reward-function.md` - verify_reward_function() API for testing RFT reward functions (Nova RFT path)
- `references/nova-rft-multiturn-setup.md` - RFT Multiturn infrastructure setup, training, and evaluation (Nova RFT Multiturn path)
- `references/nova-rft-multiturn-reference.md` - RFT Multiturn complete API reference (Nova RFT Multiturn path)
- `rlaif_guide.md` - instructions on RLAIF finetuning options
- `rlaif_builtin.py` - Code template for RLAIF with built-in judge prompt
- `rlaif_custom_prompt.py` - Code template for RLAIF with custom judge prompt
