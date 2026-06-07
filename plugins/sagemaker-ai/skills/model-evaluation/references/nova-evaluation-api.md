---
name: nova-evaluation-api
description: Evaluating trained Nova models using ForgeEvaluator. Use when running evaluation benchmarks on Nova fine-tuned models.
triggers:
  keywords: [evaluate, evaluation, benchmark, eval, scores, nova eval, ForgeEvaluator]
  task_types: [evaluation]
  error_patterns: ["Could not resolve model checkpoint", "EvaluationTask"]
  methods: [EVALUATION]
prerequisites: [training-workflow]
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

# Nova Evaluation API

## Key Concepts

### ForgeEvaluator

The evaluation service class (replaces deprecated `customizer.evaluate()`):

- `evaluate()` — Launch an evaluation job against a trained checkpoint
- `get_logs()` — Retrieve evaluation job logs

### EvaluationTask

For the full list of evaluation task enum values (including model-specific constraints), see `nova-eval-enums.md`.

### Evaluation Types

Nova supports 4 evaluation combinations:

| Type                           | What it does                                          | EvaluationTask                                                               | Requires                                                                   | Metrics                                                                                |
| ------------------------------ | ----------------------------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Built-in Benchmark**         | Evaluates on standard benchmarks                      | `MMLU`, `MMLU_PRO`, `BBH`, `GPQA`, `MATH`, `STRONG_REJECT`, `IFEVAL`, `MMMU` | Nothing extra                                                              | accuracy / exact_match (depends on task)                                               |
| **Bring Your Own Data (BYOD)** | Evaluates on your custom dataset                      | `GEN_QA`                                                                     | `EvalTaskConfig(override_data_s3_path=...)`                                | rouge1, rouge2, rougeL, exact_match, quasi_exact_match, f1_score, f1_score_quasi, bleu |
| **Custom Scorer**              | Evaluates with your custom reward Lambda              | `GEN_QA`                                                                     | `EvalTaskConfig(override_data_s3_path=..., processor={"lambda_arn": ...})` | User-defined metrics returned by Lambda                                                |
| **LLM-as-a-Judge**             | Pairwise comparison using platform-managed Nova judge | `LLM_JUDGE`                                                                  | `EvalTaskConfig(override_data_s3_path=...)`                                | winrate, a_scores, b_scores, ties, score                                               |

### When to use LLM-as-a-Judge vs Custom Scorer

- **`LLM_JUDGE` / `RUBRIC_LLM_JUDGE`** — Pairwise comparison using a platform-managed Nova judge. The user provides a dataset with two pre-generated responses (`response_A`, `response_B`) and the judge picks the preferred one. No custom metrics, no Lambda. Best for: comparing two model outputs side-by-side when you already have both responses.
- **Custom Scorer** — A user-defined Lambda function that receives each model output and returns custom metric scores. The Lambda can implement:
  - **Verifiable reward** — deterministic programmatic scoring (regex matching, JSON validation, code execution, exact answer checks). No LLM needed.
  - **LLM-based scoring** — invokes a Bedrock model (or any model) to score outputs against user-defined criteria and prompts.
  - **Hybrid** — combines programmatic checks with LLM judgment.

  Best for: any custom evaluation logic, whether programmatic or LLM-based.

**Recommendation:**

- User already has a dataset with two model outputs and wants to compare them → `LLM_JUDGE`
- User wants programmatic scoring (regex, code execution, structured output validation) → Custom Scorer with verifiable reward Lambda
- User wants to define their own LLM-based judging criteria and prompts → Custom Scorer with Lambda calling Bedrock

## Step-by-Step Guide

### 0. Choose Evaluation Approach (2-step funnel)

**Step 0a — Choose evaluation type:**

> "What kind of evaluation would you like to run?
>
> 1. **Built-in Benchmark** — evaluate on standard industry benchmarks (MMLU, MMLU_PRO, BBH, GPQA, MATH, STRONG_REJECT, IFEVAL, MMMU). No custom data needed.
> 2. **Bring Your Own Data (BYOD)** — evaluate on your own dataset. The model generates responses for your prompts and scores are computed against your reference answers.
> 3. **LLM-as-Judge** — a Nova Judge model performs **pairwise comparison** between two model outputs (response_A vs response_B) to determine which is preferred. Requires a dataset with both outputs already generated. Returns a win rate.
>
> Pick one, or say 'help me decide' if you're not sure."

⏸ Wait for user.

- If user chose Built-in Benchmark → proceed to Step 1, then use Example 1.
- If user chose LLM-as-Judge → proceed to Step 1, then use Example 4. Note: this requires a dataset with `prompt`, `response_A`, and `response_B` fields already populated.
- If user chose BYOD → continue to Step 0b.
- If user provides or references their own evaluation dataset (e.g., "I have eval data", shares an S3 path, or dataset was prepared in an earlier step) → this is effectively BYOD. Continue to Step 0b.

**Step 0b — If BYOD, clarify metrics:**

> "With BYOD, the following text-overlap metrics are computed automatically by comparing the model's output to your reference `response`:
>
> | Metric            | What it measures                                            |
> | ----------------- | ----------------------------------------------------------- |
> | rouge1            | Unigram (single word) overlap                               |
> | rouge2            | Bigram (two consecutive words) overlap                      |
> | rougeL            | Longest common subsequence (allows gaps)                    |
> | exact_match       | Binary 0/1 — character-for-character match                  |
> | quasi_exact_match | Lenient exact match (ignores case, punctuation, whitespace) |
> | f1_score          | Harmonic mean of precision and recall on word overlap       |
> | f1_score_quasi    | Lenient f1 with normalized text comparison                  |
> | bleu              | N-gram precision (common in translation evaluation)         |
>
> Do these metrics work for your use case, or would you prefer to define custom metrics?
>
> With custom metrics (BYO Metrics), you provide a Lambda function that receives each model output and computes your own scoring logic. Common patterns:
>
> - **Verifiable reward** — deterministic programmatic scoring (regex, JSON validation, code execution, structured output checks)
> - **LLM-based scoring** — invoke a Bedrock model to score individual outputs against criteria you define (this is different from LLM-as-Judge above, which does pairwise comparison between two models)"

⏸ Wait for user.

- If default metrics are fine → proceed to Step 1, then use Example 2 (BYOD without processor).
- If user wants custom metrics → proceed to Step 1, then use Example 3 (Custom Scorer with processor/lambda_arn). The Lambda uses the custom eval SDK schema — see Example 3 for the contract and reference `../finetuning/references/nova-verify-reward-function.md` for deployment.

---

### 1. Create Evaluator

```python
from amzn_nova_forge import ForgeEvaluator
from amzn_nova_forge import ForgeConfig, EvaluationTask, EvalTaskConfig
from amzn_nova_forge import Model
from amzn_nova_forge import SMTJServerlessRuntimeManager
from amzn_nova_forge import TrainingResult

# Serverless (simplest — no instance management)
infra = SMTJServerlessRuntimeManager(
    model_package_group_name='<project-name>-models',  # Reuse from training if exists
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole'
)
# model_package_group_name: alphanumeric with hyphens, max 63 chars
# Recommend lowercase (e.g., 'customer-support-chatbot-v1')
# Reuse the same group name used during training for consistency

# Alternative: SMTJ with instance control
# from amzn_nova_forge import SMTJRuntimeManager
# infra = SMTJRuntimeManager(
#     execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
#     instance_count=1,
#     instance_type='ml.p5.48xlarge'
# )

evaluator = ForgeEvaluator(
    model=Model.NOVA_LITE_2,
    infra=infra,
    config=ForgeConfig(output_s3_path='s3://<your-bucket>/eval-output/')
)
# IMPORTANT: output_s3_path must be a WRITABLE location in the user's account.
# It must NOT be the same as model_path (checkpoint location). The checkpoint
# is read-only input; output_s3_path is where evaluation results are written.
```

### 2a. Evaluate Base Model (no training result needed)

Use this when evaluating the base model before any fine-tuning (evaluate-first workflow):

```python
eval_result = evaluator.evaluate(
    job_name='baseline-eval',
    eval_task=EvaluationTask.MMLU
    # No model_path → evaluates the base model directly
)

eval_result.show()

# Save evaluation result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

### 2b. Evaluate Fine-Tuned Model (after training)

Use this when evaluating a trained checkpoint. Follow this decision flow:

**How to resolve the model to evaluate:**

1. If user provides a **checkpoint S3 path** directly (especially if it contains "escrow" in the path) → use `model_path=<path>` directly. No verification needed.
1. If user references a **training job name** → check the job status first:

```python
from amzn_nova_forge import TrainingResult
# Load from manifest if available
training_result = TrainingResult.load("<project-dir>/manifests/training-<job-name>.json")
status = training_result.get_job_status()
# Ensure job is completed before proceeding
assert status == 'Completed', f"Training job not complete: {status}"
```

1. If **no training result file exists in `manifests/`** for the job → the training result JSON should be in the `output_s3_path` of the training job. Read it from there.

**Always dry run first** to verify the checkpoint resolves:

```python
training_result = TrainingResult.load("<project-dir>/manifests/training-<job-name>.json")

# Dry run to verify checkpoint resolution
dry_result = evaluator.evaluate(
    job_name='my-eval-job-dryrun',
    eval_task=EvaluationTask.MMLU,
    job_result=training_result,
    dry_run=True
)
```

> **If dry run says** "Could not resolve model checkpoint path for evaluate job! Falling back to base model" → the checkpoint could not be extracted from the job result. Ask the user to provide the checkpoint S3 path explicitly, then use `model_path=<user-provided-path>` instead of `job_result`.

**Submit the actual evaluation (after dry run succeeds):**

```python
# Option A: Pass job_result (preferred — SDK extracts checkpoint automatically)
eval_result = evaluator.evaluate(
    job_name='my-eval-job',
    eval_task=EvaluationTask.MMLU,
    job_result=training_result
)

# Option B: Pass model_path directly (if user provided checkpoint path or dry run failed)
# eval_result = evaluator.evaluate(
#     job_name='my-eval-job',
#     eval_task=EvaluationTask.MMLU,
#     model_path='s3://customer-escrow-.../checkpoint/step_N'
# )

eval_result.show()

# Save evaluation result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

### 3. Monitor Evaluation

```python
status = eval_result.get_job_status()
print(f"Eval status: {status}")

evaluator.get_logs(limit=100, start_from_head=True)
```

## Troubleshooting

### Checkpoint Resolution Failures

**Symptoms:**

- Evaluation uses base model instead of trained checkpoint
- `Could not resolve model checkpoint path`
- Evaluation results don't reflect training

**Solutions:**

1. **Wait for training to complete:**

```python
import time
while result.get_job_status() != 'Completed':
    print(f"Status: {result.get_job_status()}")
    time.sleep(60)
```

1. **Verify checkpoint path exists:**

```python
print(f"Checkpoint: {training_result.model_artifacts.checkpoint_s3_path}")
```

1. **Ensure execution role has S3 read access** to the checkpoint location.

### Evaluation Results Disappointing

Consider:

- Iterative training — see `nova-iterative-training.md`
- Revisit technique selection in the finetuning-technique skill
- Check data quality — more or higher-quality training data may be needed

## Examples

### Example 1: Built-in Benchmark (MMLU)

Evaluates using a standard benchmark — no custom data needed.

```python
eval_result = evaluator.evaluate(
    job_name='eval-mmlu',
    eval_task=EvaluationTask.MMLU,
    # model_path=checkpoint_path  # Optional: omit for base model, provide for fine-tuned
)

eval_result.show()

# Save result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

### Example 2: Bring Your Own Data (BYOD)

Evaluates on your custom dataset using GEN_QA task.

**Agent instruction — BYOD metric decision:** When the user selects BYOD (GEN_QA) evaluation, explain the default metrics that will be computed automatically, then ask if they align with the user's needs:

> "With BYOD evaluation, the following text-overlap metrics are computed automatically by comparing your model's output to the reference `response` field in your dataset:
>
> | Metric                | What it measures                                                   |
> | --------------------- | ------------------------------------------------------------------ |
> | **rouge1**            | Unigram (single word) overlap between generated and reference text |
> | **rouge2**            | Bigram (two consecutive words) overlap                             |
> | **rougeL**            | Longest common subsequence (allows gaps)                           |
> | **exact_match**       | Binary 0/1 — character-for-character match                         |
> | **quasi_exact_match** | Lenient exact match (ignores case, punctuation, whitespace)        |
> | **f1_score**          | Harmonic mean of precision and recall on word overlap              |
> | **f1_score_quasi**    | Lenient f1 with normalized text comparison                         |
> | **bleu**              | N-gram precision (common in translation evaluation)                |
>
> Do these metrics work for your use case, or would you prefer to define custom metrics?
>
> If custom metrics are needed, you can provide a **reward Lambda** that either:
>
> 1. **Verifiable reward** — programmatic logic that scores the output (e.g., regex match, JSON validation, code execution)
> 2. **LLM-based judge** — a Bedrock model call that evaluates the output against criteria you define
>
> Which approach works best for you?"

⏸ Wait for user response.

- If user says the default metrics are fine → proceed with BYOD (Example 2 below).
- If user wants custom metrics → proceed with Custom Scorer (Example 3 below), which uses a reward Lambda with `EvalTaskConfig(processor={"lambda_arn": ...})`.

```python
from amzn_nova_forge import EvalTaskConfig

eval_result = evaluator.evaluate(
    job_name='eval-byod',
    eval_task=EvaluationTask.GEN_QA,
    task_config=EvalTaskConfig(
        override_data_s3_path='s3://my-bucket/eval/gen_qa.jsonl',
    ),
    overrides={'max_new_tokens': 2048},
    # model_path=checkpoint_path  # Optional: omit for base model
)

eval_result.show()

# Save result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

### Example 3: Custom Scorer — Custom Reward Lambda

Evaluates with your own reward function deployed as a Lambda. For creating the Lambda, use `scripts/nova_reward_function_source_template.py` as a starting template, or see `../finetuning/references/nova-verify-reward-function.md` for the deploy workflow.

```python
from amzn_nova_forge import EvalTaskConfig

eval_result = evaluator.evaluate(
    job_name='eval-byom',
    eval_task=EvaluationTask.GEN_QA,
    task_config=EvalTaskConfig(
        override_data_s3_path='s3://my-bucket/eval/byom_data.jsonl',
        processor={
            'lambda_arn': 'arn:aws:lambda:us-east-1:123456789012:function:my-reward-fn'
        },
    ),
    # model_path=checkpoint_path  # Optional: omit for base model
)

eval_result.show()

# Save result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

### Example 4: LLM-as-a-Judge

Pairwise comparison using a platform-managed Nova judge model. The dataset must contain both responses already generated — the judge compares them.

**Required dataset format** (`llm_judge.jsonl`):

```jsonl
{"prompt": "What is machine learning?", "response_A": "ML is...", "response_B": "Machine learning is..."}
{"prompt": "Explain neural networks.", "response_A": "Neural nets...", "response_B": "A neural network is..."}
```

Each record needs `prompt`, `response_A`, and `response_B`. The judge returns which response is preferred (win rate).

```python
from amzn_nova_forge import EvalTaskConfig

eval_result = evaluator.evaluate(
    job_name='eval-llm-judge',
    eval_task=EvaluationTask.LLM_JUDGE,
    task_config=EvalTaskConfig(
        override_data_s3_path='s3://my-bucket/eval/llm_judge.jsonl',
    ),
    # model_path=checkpoint_path  # Optional: omit for base model
)

eval_result.show()

# Save result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
eval_result.dump(file_path="<project-dir>/manifests", file_name=f"eval-{eval_result.job_id}.json")
```

## Best Practices

1. **Always evaluate before deploying** — verify model quality with benchmarks
1. **Save training results** — `result.dump()` so you can load the checkpoint path later
1. **Wait for training completion** — evaluation requires a completed checkpoint
1. **Compare to baseline** — evaluate the base model too for comparison
1. **Use appropriate eval task** — match the benchmark to your use case

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
