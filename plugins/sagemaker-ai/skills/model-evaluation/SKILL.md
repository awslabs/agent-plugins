---
name: model-evaluation
description: Generates python code that evaluates SageMaker models. For OSS models, supports LLM-as-Judge and Custom Scorer. For Nova models, supports built-in benchmarks (MMLU, GPQA, MATH), BYOD, Custom Scorer. Use when the user says "evaluate my model", "run a benchmark", "test model performance", "how did my model perform", or "compare models".
metadata:
  version: "2.0.0"
---

# Model Evaluation

Generate code that evaluates a SageMaker model.

## Prerequisites

- The SDK environment has been verified (SDK version, region, execution role). If not done, activate the `sdk-getting-started` skill first.

## Principles

1. **One thing at a time.** Each response advances exactly one decision. Never combine multiple questions in a single turn.
2. **Confirm before proceeding.** Wait for the user to agree before moving to the next step.
3. **Don't read files until you need them.** Only read reference files when you've reached the step that requires them.
4. **Don't ask what you already know.** If the answer is in conversation history, workflow_state.json, plan.md, or any file you've already read — use it. Confirm if unsure, but don't re-ask.
5. **No narration.** Share outcomes and ask questions. Keep responses short.
6. **No repetition.** If you said something before a tool call, don't repeat it after.

## Scope

This skill supports two evaluation paths:

- **OSS models** — evaluation via SageMaker Serverless Model Customization (LLM-as-Judge, Custom Scorer)
- **Nova models** — evaluation via the Nova Forge SDK's `ForgeEvaluator` (built-in benchmarks, BYOD, Custom Scorer)

Tell the user when the skill is activated:

> "I can help evaluate any base or fine-tuned model — either OSS models via SageMaker evaluation, or Nova models via Forge evaluation."

If the user requests help evaluating a model that doesn't fall into either path, explain that it is not supported by this skill.

## Evaluation Types

There are evaluation types that can be used depending on the model family:

**For OSS models (Llama, Mistral, Qwen, etc.):**

- **LLM-as-Judge** — an LLM grades your model's responses.
- **Custom Scorer** — programmatic evaluation via Lambda function (includes built-in math and code scorers).

**For Nova models (Nova Micro, Lite, Lite 2, Pro):**

- **Nova Forge Evaluation** — uses `ForgeEvaluator.evaluate()` via the Forge SDK. Supports:
  - Built-in benchmarks: MMLU, MMLU_PRO, BBH, GPQA, MATH, STRONG_REJECT, IFEVAL, MMMU
  - Bring Your Own Data (BYOD) with GEN_QA
  - Custom Scorer with reward Lambda

## Model Path Dispatch

Determine the model family. If the model is Nova → follow the Nova evaluation path. If OSS → follow the OSS evaluation path below.

**Nova path:** The Nova Forge SDK provides evaluation via `ForgeEvaluator`. Read `references/nova-evaluation-api.md` and construct the code, then write it to a file following `references/code_output_guide.md` conventions (notebook or script mode).

**Runtime platform selection:** Before generating code, determine which runtime platform to use. If already established from a prior training step, reuse it. Otherwise, ask:

> "Which runtime platform would you like to use for evaluation?
>
> - **SMTJ Serverless** — Simplest, no instance management (recommended if unsure)
> - **SMTJ** — Full instance control (if you have dedicated capacity)
> - **SMHP (HyperPod)** — If you have reserved HyperPod capacity"

If the user says they don't know, default to `SMTJServerlessRuntimeManager`.

**If user selects SMHP:** A pre-existing HyperPod cluster with a Restricted Instance Group (RIG) is required. Do NOT offer to create a cluster or RIG — advise the user to work with their infrastructure team if none exists. Ask for: cluster name, namespace, instance type, and instance count.

**Base model evaluation** (evaluate-first, before training):

1. Create a `ForgeEvaluator` with model, infra, and config
2. Run `evaluator.evaluate(job_name=..., eval_task=...)` — no `model_path` needed
3. View results with `eval_result.show()`

**Fine-tuned model evaluation** (after training):

1. Load the training result: `TrainingResult.load("<project-dir>/manifests/training-<job-name>.json")`
2. Create a `ForgeEvaluator` with model, infra, and config
3. Run `evaluator.evaluate(job_name=..., eval_task=..., model_path=checkpoint_path)`
4. View results with `eval_result.show()`

For valid enum values: `references/nova-eval-enums.md` (EvaluationTask) and `../finetuning/references/nova-enums.md` (Model, TrainingMethod). Nova supports LLM-as-a-Judge via `EvaluationTask.LLM_JUDGE` (different from the OSS LLM-as-Judge workflow below).

**OSS path:** Continue with the OSS evaluation workflow below.

---

## Workflow

### Step 1: Determine evaluation type

**Do you already know which evaluation type to use?**

Check conversation history, plan.md, workflow_state.json, or anything else you've already read.

**If yes:** confirm with the user.

> "It sounds like you want to run [evaluation type]. Is that right?"

⏸ Wait for confirmation. If confirmed → go to Step 2.

**If no:** ask.

> "What kind of evaluation would you like to run? I support:
>
> 1. **LLM-as-Judge** — an LLM grades your model's responses
> 2. **Custom Scorer** — programmatic scoring (math, code, or your own logic)
>
> Pick one, or say 'help me decide' if you're not sure."

⏸ Wait for user.

- If user picks one → go to Step 2.
- If user indicates uncertainty, by saying something like "help me decide," "whatever you think," "I'm not sure" → read `references/evaluation-type-guide.md` and follow its instructions. It will guide the user to a choice and then return here.
  You MUST NEVER make a recommendation to the user on eval type without reading `references/evaluation-type-guide.md`.

### Step 2: Validate and hand off to evaluation workflow

Before reading the reference file, validate that the chosen evaluation type is compatible with the user's situation. You may already know these answers from conversation context — don't ask if you don't need to.

#### LLM-as-Judge validation

1. **What model type are we evaluating?** To determine model type (if you don't already know it):
   - If you have the **training job name or ARN**, use the AWS MCP tool `list-tags` on the training job ARN and look for the `sagemaker-studio:jumpstart-model-id` tag. Contains "nova" → Nova. Anything else → OSS.
   - If you have a **Model Package ARN**, use the AWS MCP tool `describe-model-package` and check the model description or source tags.
   - If neither is available, ask the user.
2. **Does the user have an evaluation dataset?** LLM-as-Judge requires one.

#### Custom Scorer validation

1. **Does the user have an evaluation dataset?** Custom Scorer requires one. (No model type restriction — works with Nova.)

---

If validation fails, tell the user which requirement(s) aren't met and offer alternatives:

> "[Evaluation type] won't work because [reason]."

If the failure reason was lack of an eval dataset, there's nothing we can do. Inform the user:

> "Unfortunately all of the supported eval types require an eval dataset. I can't help you with model evaluation."

If the failure reason is something else, offer to help them pick a different evaluation type.

⏸ Wait for user.

If they say they do want help choosing a different eval type → read `references/evaluation-type-guide.md`.

If validation passes, read the corresponding reference file:

| User chose    | Read                                     |
| ------------- | ---------------------------------------- |
| LLM-as-Judge  | `references/llmaaj-evaluation.md`        |
| Custom Scorer | `references/custom-scorer-evaluation.md` |

Follow the reference file's instructions from the beginning.
