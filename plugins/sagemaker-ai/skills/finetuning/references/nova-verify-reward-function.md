# verify_reward_function() API Reference

Verifies a reward function with sample data before using it in RFT training or evaluation.

## Signature

```python
from amzn_nova_forge import verify_reward_function
from amzn_nova_forge import Platform

result = verify_reward_function(
    reward_function="arn:aws:lambda:us-east-1:123456789012:function:MyReward",
    sample_data=[
        {
            "id": "sample_1",
            "reference_answer": "correct answer",
            "messages": [
                {"role": "user", "content": "question"},
                {"role": "assistant", "content": "response"}
            ]
        }
    ],
    region="us-east-1",
    validate_format=True,
    platform=Platform.SMHP,
)
```

## Parameters

- `reward_function` (str): Lambda ARN (starts with `arn:aws:lambda:`) or path to a local `.py` file
- `sample_data` (List[Dict]): List of conversation samples with `id`, `messages`, and optionally `reference_answer`
- `region` (str): AWS region for Lambda invocation (default: `us-east-1`)
- `validate_format` (bool): Validate input/output format (default: `True`)
- `platform` (Platform): `Platform.SMHP` or `Platform.SMTJ`. **Required when using Lambda ARN.** For SMHP, validates Lambda name contains "SageMaker". Optional for local files.

## Returns

```python
{
    "success": True,
    "results": [...],
    "total_samples": 1,
    "successful_samples": 1,
    "warnings": []
}
```

## Expected Lambda Output Format

```python
{
    "id": "sample_1",
    "aggregate_reward_score": 0.75,
    "metrics_list": [
        {"name": "accuracy", "value": 0.85, "type": "Metric"}
    ]
}
```

- `id` (str): Required — must match input sample id
- `aggregate_reward_score` (float|int): Required — overall reward score
- `metrics_list` (list): Optional — list of dicts with `name` (str), `value` (float|int), `type` ("Metric" or "Reward")

## Common Validation Errors

- Missing `messages` field in input
- Missing `id` or `aggregate_reward_score` in output
- `aggregate_reward_score` is not a number
- Missing `platform` parameter when using Lambda ARN
- SMHP Lambda ARN doesn't contain "SageMaker" in function name
- Invalid `metrics_list` structure

---

## Creating and Deploying a Reward Lambda

### Step 1: Write the Reward Function

Create a `.py` file with a `lambda_handler(event, context)` function. It receives a list of samples and must return a list of dicts with `id` and `aggregate_reward_score`.

For a full production-ready template with content normalization, ground truth extraction, and error handling, see `../model-evaluation/scripts/nova_reward_function_source_template.py`. The example below is a minimal quickstart:

```python
# rft_training_reward.py
from dataclasses import asdict, dataclass

@dataclass
class RewardOutput:
    id: str
    aggregate_reward_score: float

def lambda_handler(event, context):
    scores = []
    for sample in event:
        sample_id = sample.get("id", "unknown")
        messages = sample.get("messages", [])
        reference = sample.get("reference_answer", "")

        # Extract the model's response (last assistant message)
        completion = ""
        for msg in reversed(messages):
            if msg.get("role") in ["assistant", "nova_assistant"]:
                completion = msg.get("content", "")
                break

        # Score the response
        if completion.strip().lower() == reference.strip().lower():
            reward = 1.0
        elif reference.lower() in completion.lower():
            reward = 0.5
        else:
            reward = -1.0

        scores.append(RewardOutput(id=sample_id, aggregate_reward_score=reward))

    return [asdict(s) for s in scores]
```

### Step 2: Pass to Runtime Manager

Pass the local `.py` file path as `rft_lambda` on the runtime manager:

```python
from amzn_nova_forge import SMTJRuntimeManager

runtime = SMTJRuntimeManager(
    instance_type="ml.p5.48xlarge",
    instance_count=4,
    rft_lambda="rft_training_reward.py",
)
```

**Lambda naming (SMHP only):** Function name must contain `SageMaker` (exact casing), e.g. `my-SageMaker-rft-reward`. No restrictions for SMTJ.

### Step 3: Validate Locally

Test the reward function against sample training data without deploying:

```python
runtime.validate_lambda(
    data_s3_path='s3://my-bucket/rft_train.jsonl',
    validation_samples=5,
)
```

### Step 4: Deploy to AWS Lambda

Deploy the `.py` file as a Lambda function. `runtime.rft_lambda_arn` is set automatically.

```python
LAMBDA_NAME = "my-SageMaker-rft-reward"

lambda_arn = runtime.deploy_lambda(lambda_name=LAMBDA_NAME)
print(f"Deployed: {lambda_arn}")
print(f"ARN stored: {runtime.rft_lambda_arn}")
```

### Step 5: Train

`runtime.rft_lambda_arn` is automatically used by `trainer.train()` — no need to pass it explicitly.

### Using an Existing Lambda ARN

If you already have a deployed Lambda, pass the ARN directly:

```python
runtime = SMTJRuntimeManager(
    instance_type="ml.p5.48xlarge",
    instance_count=4,
    rft_lambda="arn:aws:lambda:us-east-1:123456789012:function:my-SageMaker-rft-reward",
)
# No deploy needed — runtime.rft_lambda_arn is already set
```
