# MTRL (Multi-Turn Reinforcement Learning) Notebook Template

This template provides the complete cell structure for an MTRL finetuning notebook. MTRL trains a model by letting it interact with an agent environment (Bedrock AgentCore or a custom agent reachable through a Lambda forwarder) over multiple turns and rewarding it on the resulting episodes.

---

## Cell 1: Install Dependencies

```python
!pip install --upgrade 'sagemaker>=3.7.1,<4.0' boto3 -q
```

---

## Cell 2: Setup & Credentials

```python
import boto3
from botocore.exceptions import ClientError
from sagemaker.ai_registry.dataset import DataSet
from sagemaker.core.resources import ModelPackageGroup
from sagemaker.core.helper.session_helper import Session, get_execution_role
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

# Setup
sm_client = boto3.Session().client("sagemaker")
sagemaker_session = Session(sagemaker_client=sm_client)
bucket = sagemaker_session.default_bucket()

# Configuration - USER please fill in these fields with your information:

BASE_MODEL = ""  # e.g., "openai-reasoning-gpt-oss-20b" or "nova-textgeneration-lite-v2"
TRAINING_DATA_S3 = ""  # S3 path to .parquet (or .jsonl/.json/.csv)
S3_OUTPUT_PATH = f"s3://{bucket}/finetuning-output/"
ROLE_ARN = get_execution_role()  # You can change this to a specific role.
ACCEPT_EULA = False  # Set to True to accept the base model's End-User License Agreement
MODEL_PACKAGE_GROUP_NAME = ""  # Auto-generated based on use case
```

---

## Cell 3: Agent Environment

MTRL training requires an agent environment to be configured. Choose one of the
options below. Only one of cells 3a, 3b, or 3c should remain in the final
notebook — the agent will pick the right one based on the user's choice during
the agent-environment setup sub-flow.

### 3a) Bedrock AgentCore (managed agent runtime)

```python
# Bedrock AgentCore ARN
AGENT_ENV = "<filled by agent>"  # e.g., "arn:aws:bedrock-agentcore:us-west-2:123456789012:runtime/my-runtime"

# Or provide just the runtime ID (will be resolved to the full ARN automatically)
# AGENT_ENV = "myRuntime-aBcDeFgHiJ"
```

### 3b) Custom Lambda agent (existing Lambda)

```python
# Lambda function ARN of an existing agent forwarder
AGENT_ENV = "arn:aws:lambda:<region>:<account>:function:<name>"
```

### 3c) Custom Lambda agent (create new from template)

```python
from sagemaker.train.custom_agent_lambda import CustomAgentLambda

# Create a Lambda forwarder from the template at
# ../templates/mtrl_lambda_forwarder_template.py — copy it into your project
# scripts directory and customize _call_agent / _handle_agent_error before
# running this cell.
adapter = CustomAgentLambda.create(
    source="../scripts/agent_lambda_forwarder.py",
    function_name="rft-agent-forwarder",
    timeout=900,
    memory_size=1024,
    # role="arn:aws:iam::123456789012:role/LambdaForwarderRole",
    # environment={"AGENT_ENDPOINT": "https://your-agent-loadbalancer-url"},
)
AGENT_ENV = adapter
print(f"Agent: {adapter}")
```

---

## Cell 4: Create Dataset and Model Package Group(s)

```python
# Create the output Model Package Group (final trained model lands here).
try:
    output_mpg = ModelPackageGroup.create(
        model_package_group_name=MODEL_PACKAGE_GROUP_NAME,
        model_package_group_description="",
    )
    print(f"Created new model package group named {MODEL_PACKAGE_GROUP_NAME}")
except ClientError as e:
    if e.response['Error']['Code'] in ('ResourceInUse', 'ValidationException'):
        output_mpg = ModelPackageGroup.get(model_package_group_name=MODEL_PACKAGE_GROUP_NAME)
        print(
            f"There is already a model package group with the name {MODEL_PACKAGE_GROUP_NAME}.\n"
            f"If you want to save your finetuned model under a different name, change the value "
            f"of MODEL_PACKAGE_GROUP_NAME in the previous cell."
        )
    else:
        raise

# Optional: create a separate Model Package Group for intermediate checkpoints.
# If omitted, MultiTurnRLTrainer auto-creates one named
# "{model}-mtrl-checkpoint-mpg".
# checkpoint_mpg = ModelPackageGroup.create(
#     model_package_group_name=f"{MODEL_PACKAGE_GROUP_NAME}-checkpoints",
# )

# Register the training dataset in SageMaker AI Registry. This creates a
# versioned dataset that can be referenced by ARN.
dataset = DataSet.create(
    name=MODEL_PACKAGE_GROUP_NAME,
    source=TRAINING_DATA_S3,
    wait=True,
)
TRAINING_DATASET_ARN = dataset.arn

print(f"Output Model Package Group ARN: {output_mpg.model_package_group_arn}")
print(f"Training dataset ARN:           {dataset.arn}")
```

---

## Cell 5: Configure Trainer

```python
from sagemaker.train.multi_turn_rl_trainer import MultiTurnRLTrainer

trainer = MultiTurnRLTrainer(
    model=BASE_MODEL,
    agent_env=AGENT_ENV,
    training_dataset=TRAINING_DATASET_ARN,
    s3_output_path=S3_OUTPUT_PATH,
    sagemaker_session=sagemaker_session,
    role=ROLE_ARN,
    output_model_package_group=output_mpg,
    # accept_eula=ACCEPT_EULA,                                # Uncomment for Meta models
    # intermediate_checkpoint_model_package_group=checkpoint_mpg,
    # validation_dataset=VAL_DATASET_ARN,                     # Optional validation prompts
    # mlflow_resource_arn=MLFLOW_ARN,                         # MLflow App ARN (auto-resolved if absent)
    # mlflow_experiment_name="my-mtrl-exp",
    # mlflow_run_name="my-mtrl-run",
)
print("Recommended hyperparameters for the current training job:")
print(trainer.hyperparameters.to_dict())
```

---

## Cell 6: Hyperparameter Overrides

```python
# To change a hyperparameter, uncomment its corresponding line and set the value you want.
# Note: If the value is not supported for your model, the SDK will surface the allowed range.

# Uncomment to change the number of epochs
# trainer.hyperparameters.max_epochs = 1

# Uncomment to change the global batch size
# trainer.hyperparameters.global_batch_size = 16

# Uncomment to change the maximum number of steps
# trainer.hyperparameters.max_steps = 100
```

---

## Cell 7: Start Training

```python
# Launch training (set wait=False to return immediately and poll the job manually).
training_job = trainer.train(wait=True)

print(f"Training Job Name:     {training_job.training_job_name}")
print(f"Training Status:       {training_job.training_job_status}")
print(f"Output ModelPackage:   {training_job.output_model_package_arn}")
# Render a clickable MLflow link in Jupyter (returns the URL string in plain Python).
training_job.get_mlflow_url()
```

---

## Cell 8: (Optional) Inspect Job Status

```python
# Re-attach to the job from a fresh kernel:
# job = MultiTurnRLTrainer.attach("<training_job_name>")
# print(job.training_job_status)
# job.get_mlflow_url()
#
# View per-step training metrics from MLflow:
# job.get_training_metrics()
```
