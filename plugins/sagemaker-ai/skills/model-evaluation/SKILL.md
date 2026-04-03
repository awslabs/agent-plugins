---
name: model-evaluation
description: Generates a Jupyter notebook that evaluates a fine-tuned SageMaker model using LLM-as-a-Judge. Use when the user says "evaluate my model", "how did my model perform", "compare models", or after a training job completes. Supports built-in and custom evaluation metrics, evaluation dataset setup, and judge model selection.
metadata:
  version: "1.0.0"
---

# Model Evaluation Code Generator

Generate a Jupyter notebook that evaluates a SageMaker fine-tuned model using LLM-as-Judge via sagemaker-python-sdk v3.

## Principles

1. **One thing at a time.** Each response advances exactly one decision. Never combine multiple questions or recommendations in a single turn.
2. **Confirm before proceeding.** Wait for the user to agree before moving to the next step. You are a guide, not a runaway train.
3. **Don't read files until you need them.** Only read reference files when you've reached the workflow step that requires them and the user has confirmed the direction. Never read ahead.
4. **No narration.** Don't explain what you're about to do or what you just did. Share outcomes and ask questions. Keep responses short and focused.
5. **No repetition.** If you said something before a tool call, don't repeat it after. Only share new information.

## Workflow

### Step 0: Check for prior context

Before starting the conversation, silently check for `workflow_state.json` in the project directory.
If it exists, read it and remember any useful information (such as model package ARN, model package group name, training job name, dataset paths).

### Step 1: Understand the task

For this step, you need: **what task the model is trained to do.**
If you know this already, skip this step. If not, ask the user:

> "What task is this model trained to do?"

⏸ Wait for user.

### Step 2: Get evaluation dataset

For this step, you need: **the evaluation dataset S3 path.**
If you know this already, skip this step. If not, ask the user:

> "Where's your evaluation dataset stored in S3?"

⏸ Wait for user.

### Step 3: Understand the data

For this step, you need: **to understand what the data looks like to inform metric recommendations.**
If you already know what the data looks like, skip this step. If not, ask the user:

> "Can you tell me a bit about your evaluation dataset — what format is it in, and what do the input/output fields look like?"

If the user isn't sure, offer to peek at the data:

> "May I read a few records of your dataset to help inform my recommendations?"

If they say yes, use the AWS tool to call `s3api get-object` with a `Range` header to read the first few KB.
If you fail to get a sample, move on and rely on the user's description.

### Step 4: Validate dataset format

If the evaluation dataset was already validated via the **dataset-evaluation** skill earlier in the conversation, skip this step.

Otherwise, activate the **dataset-evaluation** skill to validate it. If it fails, offer to activate the **dataset-transformation** skill to convert it. Do not proceed until the dataset is valid.

### Step 5: Check for custom metrics

For this step, you need: **whether the user has predefined custom metrics.**

> "Do you have predefined custom metrics you'd like to use? If so, they must follow the Bedrock custom metrics format: https://docs.aws.amazon.com/bedrock/latest/userguide/model-evaluation-custom-metrics-prompt-formats.html
>
> If not, no worries — I can recommend built-in metrics for your task."

⏸ Wait for user.

- If the user has custom metrics → Read `references/llmaaj-custom-evaluation.md` and follow its instructions to collect and validate the metrics JSON.
- If the user does not have custom metrics → Move to Step 6.

### Step 6: Select built-in metrics

For this step, you need: **user agreement on which built-in metrics to use (if any).**

If the user provided custom metrics in Step 5, ask whether they also want built-in metrics:

> "Would you also like to include any built-in metrics alongside your custom ones?"

If they say no, skip to Step 7.

For built-in metric selection, read `references/llmaaj-builtin-evaluation.md` and follow its instructions.

⏸ Wait for user to confirm metrics.

### Step 7: Resolve Model Package ARN

For this step, you need: **the Model Package ARN of the fine-tuned model.**

**Use this priority order:**

1. **Model Package ARN from workflow state or conversation**: If you already have a model package ARN from Step 0 (workflow state) or from earlier in the conversation, confirm it with the user and move on.
2. **Ask the user**: If you don't have the ARN, ask:
   > "What's the Model Package ARN (or group name) of your fine-tuned model?"
   > If they provide a group name, resolve the ARN by calling `list-model-packages` via the AWS tool with the group name.
   > Use the latest version's `ModelPackageArn` from the response.

**Validate the resolved ARN** (whether from API lookup, workflow state, or user input):

- A valid versioned model package ARN looks like: `arn:aws:sagemaker:REGION:ACCOUNT:model-package/NAME/VERSION`
- If the ARN contains `:model-package-group/`, the user provided a group ARN, not a package ARN. Resolve it using the lookup in #2.
- If the ARN contains `:model-package/` but does NOT end with a version number (e.g., `/1`), resolve it: extract the group name from the ARN and use the lookup in #2.
- If it contains `/DataSet/`, `/TrainingJob/`, or other non-model-package resource types, flag it: "That looks like a [Dataset/TrainingJob] ARN, not a model package ARN. Could you double-check?"
- **Verify the ARN exists** before proceeding by calling `describe-model-package` via the AWS tool.
  If this fails, tell the user the ARN wasn't found and ask them to double-check.

⏸ Wait for confirmation before proceeding.

### Step 8: Select judge model

For this step, you need: **which judge model to use for evaluation.**
This step always runs — both built-in and custom metrics require a judge model.

Read `references/supported-judge-models.md` for the canonical list, selection guidance, and validation steps.

Before presenting options, run the validation checks from the reference doc against the user's account and region. Only include models that pass all checks.

Present the available models as a numbered list:

> "Here are the judge models available in your region:
>
> 1. [model A]
> 2. [model B]
>    ...
>
> Which model would you like to use? Please type the exact model name from the above list."

**EXTREMELY IMPORTANT: NEVER recommend or suggest any particular model based on the context you have. YOU ARE ALLOWED ONLY to display the list of models. DO NOT add your own recommendation or suggestion after displaying the list.**

⏸ Wait for user to confirm.

### Step 9: Collect remaining parameters

For this step, you need: **AWS Region and S3 output path.**
For each value you don't already have, ask one at a time.

⏸ Wait for each answer before asking the next.

### Step 10: Confirm configuration

Summarize everything and ask for approval:

> "Here's the evaluation setup:
>
> - Task: [task]
> - Dataset: [path]
> - Custom metrics: [Yes — N metrics / No]
> - Built-in metrics: [list, or None]
> - Judge: [model]
> - Model Package ARN: [arn]
> - Region: [region]
> - S3 output: [path]
>
> Your fine-tuned model will automatically be compared against its base model.
>
> Does this look right?"

⏸ Wait for user approval.

### Step 11: Bedrock Evaluations agreement

**This step is mandatory. Do not skip it. Do not proceed without explicit user confirmation.**

Before generating the notebook, present the following agreement language:

> **Important: Amazon Bedrock Evaluations Terms**
>
> This feature is powered by Amazon Bedrock Evaluations. Your use of this feature is subject to pricing of Amazon Bedrock Evaluations, the [Service Terms](https://aws.amazon.com/service-terms/) applicable to Amazon Bedrock, and the terms that apply to your usage of third-party models. Amazon Bedrock Evaluations may securely transmit data across AWS Regions within your geography for processing. For more information, access [Amazon Bedrock Evaluations documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation-judge.html).
>
> Do you acknowledge and agree to proceed?

⏸ **Hard stop.** Wait for the user to explicitly confirm. Acceptable responses include "yes", "I agree", "proceed", "ok", or similar affirmative statements. If the user asks questions about the terms, answer them, then re-ask for confirmation. Do NOT generate the notebook until the user has confirmed.

### Step 12: Generate notebook

If a project directory already exists (from earlier in the workflow), use it. Otherwise, activate the **directory-management** skill to set one up.

Check for existing notebooks in `<project-name>/notebooks/`. Then ask:

> "Would you like to append to an existing notebook, or create a new one: `<project-name>/notebooks/<project-name>_model-evaluation.ipynb`?"

⏸ Wait for user.

**Before writing the notebook, read:**

- `references/notebook_structure.md` (cell order, placeholders, JSON formatting)
- `scripts/notebook_cells.py` (all cell code templates)

### Step 13: Provide run instructions

```
To run:
1. Cell 1 — configuration and SDK install
2. Cell 2 — start evaluation
3. Cell 3 — polls status automatically (~25-60 min)
4. Cell 4 — show base vs custom model comparison
```

## Notes

- Not all models support serverless evaluation. If job fails with "DownstreamServiceUnavailable", the model doesn't have evaluation recipes.
- Jobs stuck in "Executing" is normal — inference takes 15-30+ minutes.
- For faster iteration, use a small dataset (5-10 examples).
- Known working models: DeepSeek R1 Distilled Qwen 32B
- Expected duration: small model (<10B) 25-40 min, large model (>30B) 40-60 min, with base comparison 2x.

## FAQ

**Q: Can I use benchmarks or custom scorer evaluations?**
A: Not yet — this skill currently supports LLM-as-Judge evaluations only (built-in and custom metrics). Benchmark and custom scorer support will be added in a future version. In the meantime, you can set these up through the SageMaker console or refer to the [SageMaker evaluation documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/model-evaluation.html).

**Q: Can I combine custom and built-in metrics in the same evaluation?**
A: Yes. You can use up to 10 custom metrics alongside any number of built-in metrics in a single evaluation job.

## Troubleshooting

### Evaluation job fails with "access denied when attempting to assume role"

The Bedrock evaluation job needs to assume your IAM role, which requires `bedrock.amazonaws.com` in the role's trust policy. This is common when running from a local IDE with temporary or SSO credentials.

To check, inspect your current role's trust policy using the AWS MCP tool:

1. Use the AWS MCP tool `get-caller-identity` (STS service) to get your current role ARN.
2. Extract the role name from the ARN (the part after `role/` or `assumed-role/`).
3. Use the AWS MCP tool `get-role` (IAM service) with the role name, and extract `Role.AssumeRolePolicyDocument` from the response.

Look for `bedrock.amazonaws.com` in `Principal.Service`. If it's missing, either add it to the trust policy or switch to a role that already trusts Bedrock (e.g., your SageMaker execution role).

### Helping a user find their Model Package ARN

If the user doesn't know their model package ARN and can only provide partial info (dataset ARN, training job name, etc.), guide them through these steps:

1. **Ask for keywords** from the model or training job name (e.g., "medication-simplification").
2. **Search model package groups** via the AWS tool: `list-model-package-groups` with `name-contains <keyword>`.
3. **List packages in the group** via the AWS tool: `list-model-packages` with the group name.
4. **Verify the match** via the AWS tool: `describe-model-package` with the ARN. Check that the `S3Uri` in `InferenceSpecification.Containers` matches the expected training output path.

Always confirm the resolved ARN with the user before proceeding.
