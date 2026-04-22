---
name: model-evaluation
description: Generates python code that evaluates SageMaker models. Supports two evaluation types: LLM-as-Judge and Custom Scorer. Use when the user says "evaluate my model", "test model performance", "how did my model perform", "compare models", or other similar requests.
metadata:
  version: "2.0.0"
---

# Model Evaluation

Generate code that evaluates a SageMaker model.

## Principles

1. **One thing at a time.** Each response advances exactly one decision. Never combine multiple questions in a single turn.
2. **Confirm before proceeding.** Wait for the user to agree before moving to the next step.
3. **Don't read files until you need them.** Only read reference files when you've reached the step that requires them.
4. **Don't ask what you already know.** If the answer is in conversation history, workflow_state.json, plan.md, or any file you've already read — use it. Confirm if unsure, but don't re-ask.
5. **No narration.** Share outcomes and ask questions. Keep responses short.
6. **Notebook writing.** Write notebooks using your standard file write tool to create the `.ipynb` file with the complete notebook JSON, OR use notebook MCP tools (e.g., `create_notebook`, `add_cell`) if available. Do NOT use bash commands, shell scripts, or `echo`/`cat` piping to generate notebooks.

## Limitations

This skill supports the evaluation feature for Sagemaker Serverless Model Customization. Thus it can help evaluate any Sagemaker Jumpstart models that are supported by sagemaker serverless model customization. Tell this to the user when the skill is activated:

> "This skill can help us evaluate any base or finetuned model that is supported by sagemaker serverless model customization"

If the user requests help evaluating a different type of model, explain to them that this is not supported by the skill.

## Evaluation Types

There are two evaluation types that can be used to evaluate a model:

- **LLM-as-Judge** — an LLM grades your model's responses.
- **Custom Scorer** — programmatic evaluation via Lambda function (includes built-in math and code scorers).

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

1. **What model type are we evaluating?** LLM-as-Judge is not supported for Nova models. To determine model type (if you don't already know it):
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
