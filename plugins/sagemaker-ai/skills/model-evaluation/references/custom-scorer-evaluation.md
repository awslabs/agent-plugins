# Custom Scorer Evaluation

Guide the user through the process for evaluating a model with Custom Scorer (built-in Prime Math/Code or custom Lambda).

## Workflow

### Step 0: Consider prior context

Before proceeding, silently think about the context you have about the user's project, including conversation history and file reads. You should use that knowledge, and avoid asking questions you already know the answer to.

### Step 1: Validate Custom Scorer compatibility

Before proceeding, confirm one thing:

1. **Does the user have an evaluation dataset?**

If the check fails (the user has no eval dataset), tell the user and offer to help them pick an alternative:

> "Custom Scorer evaluation requires an evaluation dataset. Would you like help choosing a different evaluation type?"

If they want help choosing a different evaluation type → break this workflow and read `references/evaluation-type-guide.md`.

If the check passes, proceed.

### Step 2: Understand the task

For this step, you need: to understand **the task the model is trained to do.**
If you know this already, skip this step. If not, ask the user:

> "What task is this model trained to do?"

### Step 3: Get evaluation dataset

For this step, you need: **the evaluation dataset S3 path.**
If you know this already, skip this step. If not, ask the user:

> "Where's your evaluation dataset stored in S3?"

### Step 4: Choose scorer type

For this step, you need to know **which scorer to use.**

If you already know from context, confirm and move on. Otherwise, ask:

> "Which type of scorer would you like to use?
>
> 1. **Prime Math** — built-in scorer for math problems (checks answer correctness)
> 2. **Prime Code** — built-in scorer for coding problems (executes code against test cases)
> 3. **Custom Lambda** — your own scoring logic as a Lambda function. You can use an existing registered evaluator or create a new one.
>
> Which would you prefer?"

- If built-in (Prime Math or Prime Code) → note the choice and proceed to Step 5.
- If custom Lambda → read `references/custom-lambda-scorer.md` and follow its instructions to resolve the evaluator. Then return here and proceed to Step 5. You MUST follow these instructions before moving on.

### Step 5: Validate dataset format

If the evaluation dataset was already validated via the **dataset-evaluation** skill — either earlier in this conversation, or in a previous session (as recorded in plan.md) — skip this step.

Otherwise, activate the **dataset-evaluation** skill to validate it. If it fails, offer to activate the **dataset-transformation** skill to convert it. Do not proceed until the dataset is valid.

**Note for scorer type:** Some scorer types have specific dataset format requirements. Be sure to consider this when you activate dataset-evaluation.

### Step 6: Determine evaluation scope

For this step, you need to know **which model(s) to evaluate.**

If you already know from context, confirm and move on. Otherwise, ask:

> "Would you like to evaluate:
>
> 1. **Just your fine-tuned model**
> 2. **Just a base model**
> 3. **Both, with a comparison**

⏸ Wait for user approval.

### Step 7: Resolve Model Package ARN

**This step only applies if the evaluation scope includes the fine-tuned model (option 1 or 3 from Step 6).** If the user chose base model only, skip to Step 8.

For this step, you need: **the Model Package ARN of the fine-tuned model.**

If you already have it from prior context, confirm with the user and move on. Otherwise, ask:

> "What's the Model Package ARN (or group name) of your fine-tuned model?"

If they provide a group name, resolve the ARN by calling `list-model-packages` via the AWS tool. Use the latest version's `ModelPackageArn`.

**Validate the resolved ARN:**

- Must look like: `arn:aws:sagemaker:REGION:ACCOUNT:model-package/NAME/VERSION`
- If it's a group ARN (`:model-package-group/`), resolve to a package ARN by calling `list-model-packages` via the AWS tool. Use the latest version's `ModelPackageArn`.
- If it contains `:model-package/` but does NOT end with a version number (e.g., `/1`), resolve it: extract the group name and use `list-model-packages`.
- If it contains `/DataSet/`, `/TrainingJob/`, or other non-model-package resource types, flag it: "That looks like a [Dataset/TrainingJob] ARN, not a model package ARN. Could you double-check?"
- Verify it exists by calling `describe-model-package` via the AWS tool. If this fails, tell the user the ARN wasn't found and ask them to double-check.

### Step 8: Resolve base model

**This step only applies if the evaluation scope includes the base model (option 2 or 3 from Step 6).** If the user chose fine-tuned only, skip to Step 9.

For **comparison mode** (option 3): the base model is resolved automatically from the fine-tuned model's lineage — no additional input needed.

For **base model only** (option 2): you need a JumpStart model ID (e.g., `meta-textgeneration-llama-3-2-1b-instruct`). Check if you already know it from context. If not, ask:

> "What's the JumpStart model ID of the base model you'd like to evaluate?"

<!-- TODO: Add guidance for helping the user find their JumpStart model ID. -->

### Step 9: Resolve IAM role ARN

For this step, you need: **an IAM role ARN with permissions for evaluation.**

If you already know the IAM role ARN from conversation context, confirm with the user and move on.

If not, but you know the training job name, look up the role from that training job, since it should be a suitable role:

- Call `describe-training-job` via the AWS tool and extract `RoleArn`.
- Confirm with the user.

If you don't have either, ask:

> "What IAM role ARN should I use for the evaluation job?"

**Important:** If the user chose a custom Lambda scorer, the IAM role must also have `lambda:InvokeFunction` permission for the scorer's Lambda function. Mention this to the user:

> "Note: since you're using a custom Lambda scorer, this role needs `lambda:InvokeFunction` permission for your scorer function. Does your role have that?"

### Step 10: Resolve AWS Region

For this step, you need: **the AWS region for the evaluation job.**
If you already know it from context, confirm and move on. Otherwise, ask.

### Step 11: Resolve S3 output path

For this step, you need: **an S3 path for evaluation output.**
If you already know it from context, confirm and move on. Otherwise, ask.

### Step 12: MLflow experiment name (optional)

For this step, you need to know: **the MLflow experiment name.**
If you already know this from context, confirm and move on. If not, the name should follow this pattern:
`<project-name>-eval`.

Perform this step quietly. The user does not need to know about this. This is to make sure their results are viewable alongside other experimental work they're doing.

### Step 13: Confirm configuration

Summarize everything and ask for approval:

> "Here's the evaluation setup:
>
> - Task: [task]
> - Dataset: [path]
> - Scorer: [Prime Math / Prime Code / Custom Lambda ARN]
> - Model: [Model Package ARN or JumpStart model ID]
> - Evaluation scope: [fine-tuned only / base only / both with comparison]
> - IAM role: [ARN]
> - Region: [region]
> - S3 output: [path]
> - MLflow experiment name: [MLflow experiment name]
>
> Does this look right?"

⏸ Wait for user approval.

### Step 14: Generate notebook

If you already know which notebook to write to (e.g., the user has been appending to an existing notebook throughout this workflow), confirm and proceed. Otherwise, ask if they have an existing notebook to add evaluation cells to, or want a new one. If new, check if a project directory already exists. If not, suggest activating the **directory-management** skill to set up a project structure. Then suggest a name like `<project-name>/notebooks/<project-name>_custom-scorer-evaluation.ipynb`.

Read `scripts/custom_scorer_evaluator.py`, substitute the collected values into the placeholders, and write the cells.

### Step 15: Provide run instructions

```
To run:
1. Cell 1 — configuration and SDK install
2. Cell 2 — start evaluation
3. Cell 3 — polls status automatically (~25-60 min)
4. Cell 4 — show results
```

## FAQ

**Q: What metrics do I get with Custom Scorer?**
A: Both built-in and custom scorers automatically produce standard NLP metrics (F1, ROUGE, BLEU) alongside your custom scores.

**Q: Does my IAM role need special permissions for Custom Scorer?**
A: Yes — if using a custom Lambda scorer, the IAM role needs `lambda:InvokeFunction` permission for the scorer's Lambda function. Built-in scorers (Prime Math/Code) don't require additional permissions.

**Q: Can I create a new reward function through this skill?**
A: Yes — if you choose Custom Lambda and don't have an existing evaluator, the agent will walk you through creating one from a template and registering it via `Evaluator.create`.
