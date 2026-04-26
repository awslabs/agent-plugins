# Create Reward Function

Help the user create and register a Lambda reward function as a SageMaker Hub Evaluator.

## Principles

1. **One thing at a time.** Each response advances exactly one decision.
2. **Confirm before proceeding.** Wait for the user to agree before moving to the next step.
3. **No narration.** Share outcomes and ask questions. Keep responses short.

## Prerequisites

The caller must know the base model being used (needed for template selection).

## Workflow

### Step 1: Copy Template to Project

Select the reward function template based on the base model:

- **Nova 2.0 Lite** → `scripts/nova_reward_function_source_template.py`
- **All other models** → `scripts/reward_function_source_template.py`

Copy the selected template as `lambda_function.py` into the project's scripts directory.

- Read the `directory-management` skill to determine the correct directory for storing scripts.

### Step 2: Generate Notebook Cell

Create a single notebook cell that registers the local file as a SageMaker Hub Evaluator. Set `reward_function_path` to the path where `lambda_function.py` was saved in Step 1.

```python
from sagemaker.ai_registry.evaluator import Evaluator

reward_function_path = ""  # Path to lambda_function.py from Step 1

evaluator = Evaluator.create(
    name="[GENERATE A NAME FOR THE EVALUATOR HERE]",
    type="RewardFunction",
    source=reward_function_path,
)
print(f"Reward Function ARN: {evaluator.arn}")
```

Remember to set an appropriate name for the Evaluator by yourself in the above code, based on the use case and the current context.

- Format: lowercase, alphanumeric with hyphens only, 1-20 characters
- Pattern: `[a-zA-Z0-9](-*[a-zA-Z0-9]){0,20}`

### Step 3: Inform User About TODOs

After copying the template and generating the notebook cell, inform the user that `lambda_function.py` contains `TODO` sections that they
must customize for their use case before running the notebook. The sections that need customization include helper functions,
reward logic, input parsing, score computation, and the return statement. Direct the user to edit `lambda_function.py` directly.
Wait for the user's acknowledgment before proceeding.

## Output

The output of this workflow is a reference to `evaluator.arn`. Embed the `Evaluator.create` cell as the first cell of the evaluation notebook so that subsequent cells can reference `evaluator.arn` directly as a variable.

## References

- `scripts/reward_function_source_template.py` — Lambda source template for open-weights models
- `scripts/nova_reward_function_source_template.py` — Lambda source template for Nova 2.0 Lite
