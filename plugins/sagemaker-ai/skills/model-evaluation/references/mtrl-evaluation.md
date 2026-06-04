# MTRL Evaluation

Guide the user through the process for evaluating a model with MTRL Evaluation
(`MultiTurnRLEvaluator`).

MTRL Evaluation runs an end-to-end **multi-turn rollout** of the model
against an agent environment. The score is the success of the rollout — the
agent environment owns reward and trajectory bookkeeping. There are two
shapes:

- **Trainer-resolved** (the model under evaluation was just trained with
  MTRL). The evaluator reuses the trainer's `agent_env` and auto-resolves
  the output model package. No `agent_config` is needed.
- **Base JumpStart model with explicit `agent_config`** (the user wants to
  measure a base model that supports MTRL without prior training, per
  Scenario 3 of `mtrl_dogfooding_notebook.ipynb`). The user must provide
  an agent environment value (AgentCore ARN or Lambda ARN).

## Workflow

### Step 0: Consider prior context

Before proceeding, silently think about the context you have about the user's
project, including conversation history and file reads. You should use that
knowledge, and avoid asking questions you already know the answer to.

In particular, check whether you already know:

- Whether the model under evaluation was trained with MTRL (training-job
  tags, plan.md, or the user's earlier statements).
- The training job name or ARN (so a trainer can be re-attached).
- The agent environment value, if one was already configured during the
  finetuning skill's Section 1A.

### Step 1: Determine evaluation mode

For this step, you need: **whether to use the trainer-resolved path or the
base-model path.**

If you already know from context (e.g., the user finished an MTRL training
run earlier in the conversation, or `plan.md` records an MTRL trainer), use
the trainer-resolved path and confirm with the user.

Otherwise, ask:

> "Are you evaluating a model you trained with MTRL, or a base JumpStart
> model that supports MTRL?
>
> 1. **Trained with MTRL** — I'll re-attach to the training job and the
>    evaluator will reuse the trainer's agent environment automatically.
> 2. **Base JumpStart model** — I'll need a JumpStart model ID and an
>    agent environment value (AgentCore ARN or Lambda ARN)."

⏸ Wait for user.

### Step 2: Resolve the dataset

For this step, you need: **the evaluation dataset path** (Parquet preferred,
or any other supported format with a `prompt` column).

If you already know the dataset path from context, confirm it with the user
and move on.

Otherwise, ask:

> "Where's your evaluation dataset stored? Parquet is preferred, but JSONL,
> JSON, or CSV with a `prompt` column also work."

⏸ Wait for user.

**MTRL evaluation requires a dataset of prompts.** If the user does not have
one, inform them and stop (R7.7):

> "MTRL evaluation requires a dataset of prompts. I can't generate the
> evaluation cells without one."

If the dataset was already validated via the **dataset-evaluation** skill —
either earlier in this conversation, or in a previous session (recorded in
`plan.md`) — skip the next step.

Otherwise, activate the **dataset-evaluation** skill to validate the dataset.
If validation fails, offer to activate the **dataset-transformation** skill
to convert it to MTRL-compatible Parquet. Do not proceed until the dataset
is valid.

### Step 3: Resolve the model

#### Step 3a (trainer-resolved): Re-attach to the training job

For this step, you need: **the MTRL training job name.**

If you already know it from context, confirm with the user. Otherwise, ask:

> "What's the name of the MTRL training job I should re-attach to?"

The notebook re-attaches via:

```python
trainer = MultiTurnRLTrainer.attach(job_name="<training_job_name>")
```

The evaluator will be constructed with `model=trainer`. No `agent_config` is
needed — the evaluator auto-resolves both the output model package and the
agent environment from the trainer.

Skip Step 3b. Continue to Step 4.

#### Step 3b (base-model): Resolve model ID and agent environment

For this step, you need: **the JumpStart model ID** and an
**`agent_config`** value (AgentCore ARN or Lambda ARN).

If you already know the model ID from context (e.g., the user mentioned
which base model they wanted to evaluate), confirm. Otherwise, ask:

> "What's the JumpStart model ID of the base model you'd like to evaluate?"

If you already know an agent environment value from a prior agent-env setup
(e.g., the finetuning skill's Section 1A captured one earlier in the
conversation), confirm with the user.

Otherwise, the user needs to set up an agent environment first. Delegate to
the finetuning skill's agent-environment-setup sub-flow:

> "Evaluating a base MTRL model needs an agent environment. Let me walk
> you through setting one up."

Read
`agent-plugins/plugins/sagemaker-ai/skills/finetuning/references/agent_environment_setup.md`
and follow its instructions to capture an `AGENT_ENV` value. Then return
here. The captured value becomes the evaluator's `agent_config`.

Continue to Step 4.

### Step 4: Resolve standard evaluation inputs

For this step, you need: **IAM role ARN, AWS region, S3 output path, and
(optionally) MLflow resource ARN.**

For each, use what you already know from context (e.g., the training job's
role / region / output bucket) and confirm with the user. Only ask for
inputs you do not already have.

- **IAM role**: prefer the role attached to the source training job
  (look it up via `describe-training-job` if you have the job name).
- **Region**: prefer the training job's region.
- **S3 output**: a path under the user's project bucket like
  `s3://<bucket>/mtrl-eval/`.
- **MLflow resource ARN** (optional): if `plan.md` records an MLflow
  experiment, reuse it.

### Step 5: Confirm configuration and write the cells

Summarize everything and ask for approval:

> "Here's the MTRL evaluation setup:
>
> - Mode: [trainer-resolved / base-JumpStart-model]
> - [If trainer] Training job: [name]
> - [If base] Base model ID: [id]
> - [If base] Agent config: [AGENT_ENV]
> - Dataset: [path]
> - IAM role: [ARN]
> - Region: [region]
> - S3 output: [path]
> - MLflow ARN: [ARN or 'None']
>
> Does this look right?"

⏸ Wait for user approval.

If a project directory already exists (from earlier in the workflow), use
it. Otherwise, activate the **directory-management** skill to set one up.

Check if the project notebook already exists at
`<project-dir>/notebooks/<project-name>.ipynb`.

- If it exists → ask: _"Would you like me to append the evaluation cells to
  the existing notebook, or create a new one?"_
- If it doesn't exist → create it.

When appending, add a markdown header cell `## Model Evaluation — MTRL` as a
section divider before the new cells.

⏸ Wait for user.

## Notebook Cells

Render the cells below into the project notebook, picking **either** Cell 3a
(trainer-resolved, Step 3a) **or** Cell 3b (base-model, Step 3b). The other
cells are identical for both modes.

### Cell 1: Install dependencies

```python
!pip install --upgrade 'sagemaker>=3.7.1,<4.0' boto3 -q
```

### Cell 2: Setup and credentials

```python
import boto3
from sagemaker.train.evaluate import MultiTurnRLEvaluator
from sagemaker.train.multi_turn_rl_trainer import MultiTurnRLTrainer
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

REGION = boto3.Session().region_name
ROLE = get_execution_role()
S3_OUTPUT = "s3://<bucket>/mtrl-eval/"
DATASET = "<S3 URI or DataSet ARN of eval prompts>"
MLFLOW_ARN = ""  # Optional MlflowApp ARN; leave empty to skip
```

### Cell 3a: Trainer-resolved evaluator (Step 3a only)

```python
# Re-attach to the MTRL training job. The evaluator will reuse the trainer's
# agent environment and auto-resolve the output model package.
trainer = MultiTurnRLTrainer.attach(job_name="<training_job_name>")

evaluator = MultiTurnRLEvaluator(
    model=trainer,
    dataset=DATASET,
    s3_output_path=S3_OUTPUT,
    mlflow_resource_arn=MLFLOW_ARN or None,
)
```

### Cell 3b: Base JumpStart model with explicit `agent_config` (Step 3b only)

```python
# Evaluate a base JumpStart model that supports MTRL. The agent_config is
# the AGENT_ENV captured in the agent-environment-setup sub-flow — either
# an AgentCore ARN or a Lambda ARN.
AGENT_ENV = "<AgentCore ARN or Lambda ARN>"

evaluator = MultiTurnRLEvaluator(
    model="<jumpstart-model-id>",
    dataset=DATASET,
    agent_config=AGENT_ENV,
    s3_output_path=S3_OUTPUT,
    mlflow_resource_arn=MLFLOW_ARN or None,
)
```

### Cell 4: Launch evaluation

```python
exec = evaluator.evaluate()
print(f"Evaluation execution: {exec}")
```

### Cell 5: Wait for completion and print status

```python
exec.wait()
print(f"Evaluation status: {exec.status.overall_status}")
```

## Listing prior runs

To list past MTRL evaluation runs in your account, use:

```python
from sagemaker.train.evaluate import MultiTurnRLEvaluator

for run in MultiTurnRLEvaluator.get_all(region=REGION):
    print(run)
```

This is useful for re-attaching to a long-running evaluation from a fresh
kernel, or for surfacing prior results when comparing models.

## Run instructions

```
To run:
1. Cell 1 — install/upgrade SageMaker SDK
2. Cell 2 — configuration and imports
3. Cell 3 — construct the evaluator (3a if trainer-resolved, 3b if base-model)
4. Cell 4 — launch evaluation
5. Cell 5 — wait for completion (~10-60 min depending on dataset size and
   agent-environment latency) and print the overall status
```

## FAQ

**Q: Do I need an `agent_config` for the trainer-resolved path?**
A: No. The evaluator reads the agent environment off the trainer object and
reuses it. You only need to provide `agent_config` when evaluating a base
JumpStart model directly (Step 3b).

**Q: What dataset format does MTRL evaluation accept?**
A: Parquet is preferred. JSONL, JSON-array, and CSV are also accepted as
long as the file has a `prompt` column. The prompt content is forwarded
verbatim to the agent environment, which owns parsing — encode structured
prompts (conversation history, tool configs) as a single
`json.dumps(task_data)` string per record.

**Q: How does MTRL evaluation differ from LLM-as-Judge?**
A: LLM-as-Judge scores a single response with a judge model. MTRL
evaluation runs an end-to-end multi-turn rollout against an agent
environment and scores the trajectory. Use MTRL evaluation when the model
was trained with MTRL or when measuring multi-turn agent behaviour.

## Troubleshooting

### Evaluation fails with "agent_config is required"

You hit Step 3b without providing an `agent_config`. Re-run the
agent-environment-setup sub-flow (see Step 3b) and pass the resulting
`AGENT_ENV` as `agent_config=...`.

### Evaluation fails with "model is not MTRL-trained"

The trainer-resolved path (Step 3a) requires that the attached training job
was an MTRL run. If the job is SFT/DPO/RLVR, switch to one of the existing
LLM-as-Judge or Custom Scorer evaluation types.
