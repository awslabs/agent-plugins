# RFT Multiturn

The Nova Forge SDK supports RFT (Reinforcement Fine-Tuning) multiturn training for multi-turn conversational tasks. This module provides infrastructure management and orchestration for running RFT training with custom reward environments.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Infrastructure Setup](#infrastructure-setup)
- [Dataset Format](#dataset-format)
- [Training](#training)
- [Evaluation](#evaluation)
- [Monitoring](#monitoring)
- [Custom Environments](#custom-environments)
- [Helper Functions](#helper-functions)
- [Cleanup](#cleanup)
- [Platform Support](#platform-support)

## Overview

RFT Multiturn enables you to fine-tune Nova models using reinforcement learning with custom reward functions. The infrastructure can be deployed on three platforms:

- **LOCAL**: Runs on your local machine
- **EC2**: Runs on an AWS EC2 instance
- **ECS**: Runs on AWS ECS Fargate

## Prerequisites

### General Requirements

- Python 3.12 or higher
- AWS credentials configured
- The SDK requires specific IAM permissions. See the [IAM Roles/Policies section in the main README](../README.md#iam-rolespolicies) for the complete list of required permissions.
  dditional SSM and ECS permissions are required - see the "If performing RFT Multiturn training" section in the README
- SageMaker HyperPod cluster (for training)

### Platform-Specific Requirements

#### For LOCAL Platform or SageMaker Notebook

- Python 3.12 or higher installed locally
- Sufficient local compute resources

#### For EC2 Platform

Requirements:

- EC2 instance launched with **Amazon Linux 2023** ([guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/LaunchingAndUsingInstances.html))
- Recommended instance type: `r5.24xlarge` or similar
- SSM access enabled on the instance
- IAM permissions for SSM commands

#### For ECS Platform

- ECS cluster with Fargate ([guide](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-cluster-console-v2.html))
- VPC with subnets and security groups configured
- IAM permissions for ECS task management

## Quick Start

```python
from amzn_nova_forge import *

# 1. Setup infrastructure (LOCAL example)
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE  # Built-in environment
)

# Deploy infrastructure
rft_infra.setup()

# Start training environment
rft_infra.start_environment(env_type=EnvType.TRAIN)

# 2. Train model
trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_MULTITURN_LORA,
    infra=SMHPRuntimeManager(
        cluster_name="my-cluster",
        namespace="kubeflow",
        instance_type="ml.p5.48xlarge",
        instance_count=2
    ),
    training_data_s3_path="s3://bucket/data.jsonl",
    config=ForgeConfig(output_s3_path="s3://bucket/output/")
)

training_result = trainer.train(
    job_name="rft-training",
    rft_multiturn_infra=rft_infra
)

# 3. Cleanup
rft_infra.cleanup(delete_stack=True)
```

## Infrastructure Setup

### RFTMultiturnInfrastructure Constructor

The `RFTMultiturnInfrastructure` class is the main entry point for managing RFT multiturn infrastructure.

**Parameters:**

- `stack_name` (str, required): CloudFormation stack name for Lambda/SQS/DynamoDB resources. Automatically appends `-NovaForgeSDK` suffix if not present.
- `region` (str, required): AWS region for infrastructure deployment (e.g., `"us-east-1"`).
- `infrastructure_arn` (str, optional, default: `None`): Platform identifier: EC2 instance ID/ARN or ECS cluster ARN. If `None`, uses LOCAL platform.
- `python_venv_name` (str, conditional, default: `None`): Python virtual environment name. **Required for LOCAL and EC2**, optional for ECS.
- `vf_env_id` (VFEnvId or str, optional, default: `None`): Built-in environment ID (e.g., `VFEnvId.WORDLE`). Mutually exclusive with `custom_env`.
- `custom_env` (CustomEnvironment, optional, default: `None`): Custom environment object. Mutually exclusive with `vf_env_id`.
- `starter_kit_path` (str, optional, default: `None`): Custom starter kit path. If not provided, uses default AWS starter kit.
  - **LOCAL**: Local file path (e.g., `"~/my-starter-kit"` or `"/path/to/v1"`)
  - **EC2/ECS**: Local path (auto-uploaded to S3) or S3 URI (e.g., `"s3://bucket/path/v1.tar.gz"`)
- `rft_role_name` (str, optional, default: `"RFTExecutionRoleNovaSDK"`): IAM role name for RFT infrastructure permissions.
- `custom_policy_path` (str, optional, default: `None`): Path to custom IAM policy JSON file. If not provided, uses SDK default policy.
- `vpc_config` (dict, optional, default: uses cluster's default): **ECS only**: VPC configuration with `subnets` and `security_groups` keys.
- `cpu` (str, optional, default: `"2048"`): **ECS only**: CPU units for Fargate task (e.g., `"4096"`).
- `memory` (str, optional, default: `"4096"`): **ECS only**: Memory in MB for Fargate task (e.g., `"8192"`).

#### Platform Detection

The platform is automatically detected based on `infrastructure_arn`:

- **LOCAL**: `infrastructure_arn` is `None`
- **EC2**: `infrastructure_arn` which is ARN of EC2 instance or instance id starting with `i-`
- **ECS**: `infrastructure_arn` which is ARN of ECS cluster

### LOCAL Platform

```python
from amzn_nova_forge import RFTMultiturnInfrastructure, VFEnvId

rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",  # Required for LOCAL
    vf_env_id=VFEnvId.WORDLE
)

rft_infra.setup()
```

### EC2 Platform

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="i-1234567890abcdef0",  # EC2 instance ID or full ARN
    python_venv_name="my_rft_venv",  # Required for EC2
    vf_env_id=VFEnvId.WORDLE 
)

rft_infra.setup()
```

### ECS Platform

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster",
    vf_env_id=VFEnvId.WORDLE,
    vpc_config={
        "subnets": ["subnet-12345", "subnet-67890"],
        "security_groups": ["sg-12345"]
    },  # Optional, uses cluster defaults if not provided
    cpu="4096",      # Optional, defaults to "2048"
    memory="8192"    # Optional, defaults to "4096"
)

rft_infra.setup()
```

### Custom Starter Kit Path

You can provide a custom starter kit path instead of using the default AWS starter kit:

```python
# LOCAL: Use local file path
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE,
    starter_kit_path="~/my-custom-starter-kit"  # Local path
)

# EC2: Use local path (auto-uploaded to S3)
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="i-1234567890abcdef0",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE,
    starter_kit_path="/path/to/v1"  # Local path, will be uploaded to S3
)

# ECS: Use S3 URI directly
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster",
    vf_env_id=VFEnvId.WORDLE,
    starter_kit_path="s3://my-bucket/custom-starter-kits/v1.tar.gz"  # S3 URI
)
```

### Custom IAM Role

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE,
    rft_role_name="MyCustomRFTRole",  # Custom role name
    custom_policy_path="path/to/custom-policy.json"  # Custom policy JSON
)
```

## Dataset Format

RFT Multiturn training requires a dataset with specific fields. The SDK supports both flat and nested formats, as well as OpenAI message format for prompts.

### Required Fields

- `id` (str): Unique identifier for each sample
- `prompt` (str or list): The input prompt
  - Can be a simple string: `"What is 2+2?"`
  - Can be OpenAI message format: `[{"role": "user", "content": "What is 2+2?"}]`

### Optional Fields

- `answer` (str): Expected answer or completion
- `task` (str): Task category or type
- `info` (dict or str): Additional metadata
  - Can be a dictionary: `{"difficulty": "easy"}`
  - Can be a valid JSON string: `"{\"difficulty\": \"easy\"}"`

**Important**: If any sample includes an optional field (answer, task, or info), ALL samples must include that field for consistency.

**Loader initialization:**

```python
loader = CSVDatasetLoader(id="id", prompt="prompt", answer="answer", task="task", info="info")
```

### Dataset Validation

The SDK automatically validates your dataset:

```python
from amzn_nova_forge import JSONLDatasetLoader
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import EvaluationTask

# Load dataset
loader = JSONLDatasetLoader(id="id", prompt="prompt", answer="answer")
loader.load("data.jsonl")

# Transform to RFT Multiturn format for training
loader.transform(method=TrainingMethod.RFT_MULTITURN_LORA, model=Model.NOVA_LITE_2)

# Transform to RFT Multiturn format for evaluation
# loader.transform(method=TrainingMethod.EVALUATION, eval_task=EvaluationTask.RFT_MULTITURN_EVAL, model=Model.NOVA_LITE_2)


# Validate dataset for training
loader.validate(method=TrainingMethod.RFT_MULTITURN_LORA, model=Model.NOVA_LITE_2)

# Validate dataset for evaluation
# loader.validate(method=TrainingMethod.EVALUATION, eval_task=EvaluationTask.RFT_MULTITURN_EVAL, model=Model.NOVA_LITE_2)

# Upload to S3
s3_path = loader.save_data("s3://my-bucket/data/training_data.jsonl")
print(f"Dataset uploaded to: {s3_path}")
```

### Validation Rules

- `id`: Must be unique across all samples
- `prompt`: Cannot be empty
  - String prompts must be non-empty
  - OpenAI format must have valid roles (system, user, assistant, tool, function)
  - Tool messages must have `tool_call_id` and non-empty `content`
  - Assistant messages with tool_calls must have valid structure
- `answer`: Optional, but if present in any sample, must be present in all samples
- `task`: Optional, but if present in any sample, must be present in all samples
- `info`: Optional, but if present in any sample, must be present in all samples
  - Must be a dict or valid JSON string

## Training

### setup() Method

Deploys the SAM stack and validates platform requirements.

**Parameters:**

This method takes no parameters.

**Returns:**

- `None`

**Behavior:**

1. Validates starter kit S3 access
2. Validates platform-specific requirements (EC2 instance status, ECS cluster, etc.)
3. Deploys CloudFormation stack with Lambda, SQS, and DynamoDB resources
4. Waits for stack deployment to complete (up to 10 minutes)
5. Retrieves stack outputs (queue URLs, Lambda ARN, etc.)
6. It should take 3-5 minutes to complete full stack deployment

**Example:**

```python
rft_infra.setup()
```

### start_environment() Method

Starts the training or evaluation environment on the configured platform using the unified environment client.

**Parameters:**

- `env_type` (`EnvType`, required): Environment type - `EnvType.TRAIN` or `EnvType.EVAL`.
- `vf_env_args` (`dict`, optional, default: `{}`): Environment-specific arguments passed to the verifier environment.
- `max_concurrent_rollouts` (`int`, optional, default: `40`): Maximum number of concurrent rollouts. Replaces the old `groups_per_batch × max_concurrent_batches × max_workers` pattern.
- `max_rollout_timeout` (`float`, optional, default: `300.0`): Per-rollout timeout in seconds. Prevents stuck rollouts from blocking others.
- `completion_poll_timeout` (`float`, optional, default: `600.0`): Timeout in seconds for completion polling.
- `completion_poll_interval` (`float`, optional, default: `0.5`): Interval in seconds between completion polling attempts.
- `rollout_poll_interval` (`float`, optional, default: `1.0`): Interval in seconds between SQS message polling.
- `log_output_directory` (`str`, optional, default: `None`): Directory for logs and metrics. Recommended: `"/opt/ml/output/logs"` for SageMaker, `"./logs"` for local.
- `config_name` (`str`, optional, default: `None`): Use YAML config instead of CLI flags. If provided, loads config from `configs/{config_name}.yaml`.
- `config_path` (`str`, optional, default: `None`): Custom config directory path. Use with `config_name` to load from custom location.
- `queue_url` (`str`, optional, default: `None`): SQS queue URL. Defaults to training queue from stack.

**Returns:**

- **LOCAL/EC2**: Process ID or command invocation ID
- **ECS**: Task ARN

**Example:**

```python
from amzn_nova_forge import EnvType

# Start training environment with default parameters
rft_infra.start_environment(env_type=EnvType.TRAIN)

# Start training with custom parameters
rft_infra.start_environment(
    env_type=EnvType.TRAIN,
    vf_env_args={"use_think": True, "max_turns": 10},
    max_concurrent_rollouts=60,
    max_rollout_timeout=600.0,
    log_output_directory="/opt/ml/output/logs"
)

# Start evaluation environment
rft_infra.start_environment(
    env_type=EnvType.EVAL,
    vf_env_args={"num_eval_examples": 200},
    max_concurrent_rollouts=100
)
```

### start_training_environment() Method (DEPRECATED)

**DEPRECATED**: This method is deprecated and will be removed in a future version. Use `start_environment(env_type=EnvType.TRAIN, ...)` instead.

This is now a simple wrapper that calls `start_environment()` with `env_type=EnvType.TRAIN`.

**Parameters:**

Same as `start_environment()` but without the `env_type` parameter (automatically set to `EnvType.TRAIN`).

**Example:**

```python
# Old way (deprecated)
rft_infra.start_training_environment(
    vf_env_args={"use_think": True, "max_turns": 10}
)

# New way (recommended)
from amzn_nova_forge import EnvType
rft_infra.start_environment(
    env_type=EnvType.TRAIN,
    vf_env_args={"use_think": True, "max_turns": 10}
)
```

### start_evaluation_environment() Method (DEPRECATED)

**DEPRECATED**: This method is deprecated and will be removed in a future version. Use `start_environment(env_type=EnvType.EVAL, ...)` instead.

This is now a simple wrapper that calls `start_environment()` with `env_type=EnvType.EVAL`.

**Parameters:**

Same as `start_environment()` but without the `env_type` parameter (automatically set to `EnvType.EVAL`).

**Example:**

```python
# Old way (deprecated)
rft_infra.start_evaluation_environment(
    vf_env_args={"num_eval_examples": 200}
)

# New way (recommended)
from amzn_nova_forge import EnvType
rft_infra.start_environment(
    env_type=EnvType.EVAL,
    vf_env_args={"num_eval_examples": 200}
)
```

### get_recipe_overrides() Method

Gets recipe parameter overrides for RFT multiturn training jobs.

**Parameters:**

This method takes no parameters.

**Returns:**

- `dict`: Dictionary containing:
  - `rollout_request_arn`: Lambda function ARN for rollout requests
  - `rollout_response_sqs_url`: SQS URL for rollout responses
  - `rollout_request_queue_url`: SQS URL for rollout requests
  - `generate_request_sqs_url`: SQS URL for generation requests
  - `generate_response_sqs_url`: SQS URL for generation responses

**Example:**

```python
overrides = rft_infra.get_recipe_overrides()
print(f"Lambda ARN: {overrides['rollout_request_arn']}")
```

### Train with ForgeTrainer

Use the `train()` method of `ForgeTrainer` with the `rft_multiturn_infra` parameter.

**Parameters (RFT-specific):**

- `rft_multiturn_infra` (`RFTMultiturnInfrastructure`, required): RFT infrastructure instance with training environment started.
- `job_name` (`str`, required): Unique name for the training job.
- `model_path` (`str`, optional, default: `None`): S3 path to checkpoint for iterative training.

**Example:**

```python
from amzn_nova_forge import (
    ForgeTrainer,
    ForgeConfig,
    Model,
    TrainingMethod,
    SMHPRuntimeManager
)

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_MULTITURN_LORA,
    infra=SMHPRuntimeManager(
        cluster_name="my-cluster",
        namespace="kubeflow",
        instance_type="ml.p5.48xlarge",
        instance_count=2
    ),
    training_data_s3_path="s3://bucket/data.jsonl",
    config=ForgeConfig(output_s3_path="s3://bucket/output/")
)

training_result = trainer.train(
    job_name="rft-training",
    rft_multiturn_infra=rft_infra
)

# Wait for completion
training_result.wait()

# Get checkpoint path
checkpoint_path = training_result.model_artifacts.checkpoint_s3_path
```

## Evaluation

### Starting Evaluation Environment

Use the `start_environment()` method with `env_type=EnvType.EVAL` to start the evaluation environment.

**Important Notes:**

- Kill the training environment before starting evaluation if using the same stack
- Flush queues if you encounter "queues have inflight messages" errors after training completes

**Example:**

```python
from amzn_nova_forge import EnvType

# Stop training environment first (recommended if using same stack)
rft_infra.kill_task(env_type=EnvType.TRAIN)

# Flush queues if needed
rft_infra.flush_all_queues()

# Start evaluation environment with default parameters
rft_infra.start_environment(env_type=EnvType.EVAL)

# Start with custom parameters
rft_infra.start_environment(
    env_type=EnvType.EVAL,
    vf_env_args={"num_eval_examples": 200},
    max_concurrent_rollouts=100,
    max_rollout_timeout=600.0,
    log_output_directory="/opt/ml/output/logs"
)
```

### start_evaluation_environment() Method (DEPRECATED)

**DEPRECATED**: Use `start_environment(env_type=EnvType.EVAL, ...)` instead. See the [start_environment() documentation](#start_environment-method) for details.

### Evaluate with ForgeEvaluator

Use the `evaluate()` method of `ForgeEvaluator` with the `rft_multiturn_infra` parameter.

**Parameters (RFT-specific):**

- `rft_multiturn_infra` (`RFTMultiturnInfrastructure`, required): RFT infrastructure instance with evaluation environment started.
- `job_name` (`str`, required): Unique name for the evaluation job.
- `eval_task` (`EvaluationTask`, required): Must be `EvaluationTask.RFT_MULTITURN_EVAL`.
- `model_path` (`str`, required): S3 path to trained model checkpoint.

**Example:**

```python
from amzn_nova_forge import EvaluationTask

eval_result = evaluator.evaluate(
    job_name="rft-eval",
    eval_task=EvaluationTask.RFT_MULTITURN_EVAL,
    model_path=checkpoint_path,
    rft_multiturn_infra=rft_infra
)

# Wait for completion
eval_result.wait()

# View results
eval_result.show()
```

## Monitoring

### Session Persistence

The SDK provides `dump()` and `load()` methods to save and restore infrastructure state across sessions (e.g., after notebook restarts).

#### dump() Method

Saves infrastructure state to a JSON file for session recovery.

**Parameters:**

- `file_path` (`str`, optional, default: `None`): Directory path to save the state file. Saves to current directory if not provided.
- `file_name` (`str`, optional, default: `None`): File name. If `None`, auto-generates with session ID.
- `include_session_id` (`bool`, optional, default: `True`): If `True`, includes session ID in filename.

**Returns:**

- `Path`: Path to saved state file

**Example:**

```python
# Save to current directory with auto-generated name
state_file = rft_infra.dump()
# Saves as: rft_state_my-stack_a1b2c3d4.json

# Save to specific directory
state_file = rft_infra.dump(file_path="/home/user/workspace")
# Saves as: /home/user/workspace/rft_state_my-stack_a1b2c3d4.json

# Save with custom filename
state_file = rft_infra.dump(
    file_name="my_state.json",
    include_session_id=False
)
# Saves as: my_state.json
```

#### load() Method (Class Method)

Loads infrastructure state from a file and reconnects to running processes.

**Parameters:**

- `file_path` (`str`, required): Path to state file.
- `auto_reconnect` (`bool`, optional, default: `True`): If `True`, verify and reconnect to running processes.

**Returns:**

- `RFTMultiturnInfrastructure`: Reconstructed infrastructure instance

**Example:**

```python
# After notebook restart or session interruption
from amzn_nova_forge import RFTMultiturnInfrastructure

# Load saved state
rft_infra = RFTMultiturnInfrastructure.load(
    "rft_state_my-stack_a1b2c3d4.json"
)

print(f"Reconnected to session: {rft_infra.session_id}")

# Continue working with the infrastructure
logs = rft_infra.get_logs(env_type=EnvType.TRAIN, limit=50)
```

**Use Cases:**

- Recover from notebook kernel restarts
- Share infrastructure state between team members
- Resume monitoring after disconnection
- Debug issues by loading historical states

### get_logs() Method

Retrieves logs from training, evaluation, or SAM deployment environments.

**Parameters:**

- `env_type` (`EnvType`, required): Environment type: `EnvType.TRAIN`, `EnvType.EVAL`, or `EnvType.SAM`.
- `limit` (`int`, optional, default: `100`): Maximum number of log lines to retrieve.
- `start_from_head` (`bool`, optional, default: `False`): If `True`, retrieves logs from the beginning. If `False`, retrieves most recent logs.
- `log_stream_name` (`str`, optional, default: `None`): **ECS only**: Specific log stream name to retrieve. If `None`, uses latest stream.
- `tail` (`bool`, optional, default: `False`): If `True`, continuously streams logs in real-time (blocks until Ctrl+C).

**Returns:**

- `list[str]`: List of log lines (empty list if `tail=True`)

**Platform Differences:**

- **LOCAL/EC2**: Reads from log files (`rft_train.log`, `rft_eval.log`, `rft_sam.log`)
- **ECS**: Retrieves from CloudWatch Logs

**Examples:**

```python
from amzn_nova_forge import EnvType

# Get last 100 lines from training environment
logs = rft_infra.get_logs(env_type=EnvType.TRAIN, limit=100)
for log in logs:
    print(log)

# Get logs from evaluation environment
logs = rft_infra.get_logs(env_type=EnvType.EVAL, limit=50)

# Tail logs in real-time (blocks until Ctrl+C)
rft_infra.get_logs(env_type=EnvType.TRAIN, tail=True)

# Get logs from beginning
logs = rft_infra.get_logs(
    env_type=EnvType.TRAIN,
    start_from_head=True,
    limit=200
)

# ECS: Get logs from specific stream
logs = rft_infra.get_logs(
    env_type=EnvType.TRAIN,
    log_stream_name="ecs/my-task/abc123",
    limit=100
)
```

### check_all_queues() Method

Checks message counts in all SQS queues.

**Parameters:**

This method takes no parameters.

**Returns:**

- `dict`: Dictionary mapping queue names to message counts:

  ```json
  {
    "rollout_request": { "visible": 0, "in_flight": 5, "last_receive_timestamp": 1234567890 },
    "rollout_response": { "visible": 10, "in_flight": 0, "last_receive_timestamp": 1234567890 },
    "generate_request": { "visible": 0, "in_flight": 0, "last_receive_timestamp": 1234567890 },
    "generate_response": { "visible": 0, "in_flight": 0, "last_receive_timestamp": 1234567890 }
  }
  ```

**Example:**

```python
# Check all queue message counts
queue_status = rft_infra.check_all_queues()
for queue_name, counts in queue_status.items():
    print(f"{queue_name}:")
    print(f"  Visible: {counts['visible']}")
    print(f"  In-flight: {counts['in_flight']}")
    print(f"  Last modified: {counts['last_receive_timestamp']}")
```

### flush_all_queues() Method

Purges all messages from all SQS queues.

**Parameters:**

This method takes no parameters.

**Returns:**

- `None`

**Important Notes:**

- Use this when you encounter "queues have inflight messages" errors
- All messages will be permanently deleted
- Cannot be undone

**Example:**

```python
# Flush all queues (clear all messages)
rft_infra.flush_all_queues()
```

### get_configuration() Method

Gets complete infrastructure configuration.

**Parameters:**

This method takes no parameters.

**Returns:**

- `dict`: Dictionary containing:
  - `stack_name`: CloudFormation stack name
  - `region`: AWS region
  - `platform`: Platform type (LOCAL, EC2, or ECS)
  - `vf_env_id`: Environment ID (if using built-in environment)
  - `custom_env`: Custom environment details (if using custom environment)
  - `rft_role_name`: IAM role name
  - Additional platform-specific configuration

**Example:**

```python
# Get complete configuration
config = rft_infra.get_configuration()
print(f"Stack: {config['stack_name']}")
print(f"Region: {config['region']}")
print(f"Platform: {config['platform']}")
```

## Custom Environments

### CustomEnvironment Class

The `CustomEnvironment` class allows you to create and package custom reward environments.

**Constructor Parameters:**

- `env_id` (`str`, required): Unique identifier for the environment (alphanumeric, hyphens, underscores only). Must be a valid Python package name.
- `local_path` (`str`, optional, default: `None`): Path to **existing** environment directory. Use this when loading a pre-existing environment. For LOCAL platform, this points to where the environment is installed.
- **s3_uri** (`str`, optional, default: `None`): S3 URI where packaged environment is stored (e.g., `s3://bucket/path/env.tar.gz`). Required for EC2/ECS platforms. Set automatically by `package_and_upload()`.
- `output_dir` (`str`, optional, default: `"~/custom_envs"`): Base directory where **new** environments will be created by `create()`. The actual environment will be at `{output_dir}/{env_id}/`.
- `env_type` (`str`, optional, default: `"single_turn"`): Environment type: `"single_turn"` or `"multi_turn"`. Determines interaction pattern and template used.

**Examples:**

```python
# Scenario 1: Create a NEW environment
custom_env = CustomEnvironment(
    env_id="my-custom-env",
    output_dir="~/my_environments"  # Base directory
).create(overwrite=True) # Overwrite=True will overwrite the environment directory
# Creates: ~/my_environments/my-custom-env/
# local_path is automatically set to: ~/my_environments/my-custom-env/

# Scenario 2: Load an EXISTING environment
custom_env = CustomEnvironment(
    env_id="my-custom-env",
    local_path="~/my_environments/my-custom-env"  # Full path to existing env
).load()
```

**Methods:**

#### create()

Creates the custom environment structure.

**Parameters**: None

**Returns**: `self` (for method chaining)

**Example**:

```python
custom_env = CustomEnvironment(
    env_id="my-custom-env",
    output_dir="~/custom_envs",  # Base directory only
    env_type="single_turn"
).create()
# Creates: ~/custom_envs/my-custom-env/
```

#### validate()

Validates the environment structure and required files.

**Parameters**: None

**Returns**: `bool` - `True` if valid, raises exception otherwise

**Checks**:

- Environment directory exists
- Required files present (`__init__.py`, `environment.py`)
- Valid Python package structure

**Example**:

```python
custom_env.validate()
```

#### package_and_upload()

Packages the environment as a tarball and uploads to S3, this is needed for EC2 and ECS.

**Parameters**:

- **s3_bucket** (`str`, optional, default: `None`): S3 bucket name. If `None`, uses default SageMaker bucket.
- **s3_prefix** (`str`, optional, default: `"rft-custom-envs"`): S3 prefix for uploaded tarball.

**Returns**: `str` - S3 URI of uploaded tarball

**Example**:

```python
s3_uri = custom_env.package_and_upload(
    s3_bucket="my-bucket",
    s3_prefix="custom-environments"
)
print(f"Uploaded to: {s3_uri}")
```

### Create Custom Environment

```python
from amzn_nova_forge import CustomEnvironment

# Create single-turn environment
custom_env = CustomEnvironment(
    env_id="my-custom-env",
    output_dir="~/custom_envs",  # Base directory only
    env_type="single_turn"
).create()
# Creates: ~/custom_envs/my-custom-env/

# Validate environment
custom_env.validate()

# Package and upload to S3 (required for EC2/ECS)
s3_uri = custom_env.package_and_upload()
print(f"Environment uploaded to: {s3_uri}")
```

### Use Custom Environment

```python
# For LOCAL platform
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    custom_env=custom_env
)

# For EC2/ECS platforms (requires S3 upload)
custom_env.package_and_upload()  # Must be called first
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="i-1234567890abcdef0",
    python_venv_name="my_rft_venv",
    custom_env=custom_env  # Must have s3_uri set
)
```

### Built-in Environments

The SDK provides two built-in environments via the `VFEnvId` enum:

#### VFEnvId.WORDLE

A Wordle game environment for word-guessing tasks.

**Environment Arguments** (`vf_env_args`):

- `use_think`: `bool` - Enable thinking steps (default: `False`)
- `max_turns`: `int` - Maximum turns per game (default: 6)

**Example**:

```python
from amzn_nova_forge import VFEnvId, EnvType

rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE
)

# Start with custom arguments
rft_infra.start_environment(
    env_type=EnvType.TRAIN,
    vf_env_args={"use_think": True, "max_turns": 8}
)
```

#### VFEnvId.TERMINAL_BENCH

A terminal benchmark environment for command-line tasks.

**Environment Arguments** (`vf_env_args`):

- `num_eval_examples`: `int` - Number of evaluation examples (default: 100)
- `timeout`: `float` - Timeout per example in seconds (default: 60.0)

**Example**:

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.TERMINAL_BENCH
)

# Start evaluation with custom arguments
rft_infra.start_environment(
    env_type=EnvType.EVAL,
)
```

## Helper Functions

### create_rft_execution_role()

Creates an IAM role with required permissions for RFT multiturn infrastructure.

**Parameters:**

- `region` (`str`, optional, default: `"us-east-1"`): AWS region for the RFT infrastructure.
- `role_name` (`str`, optional, default: `"RFTExecutionRoleNovaSDK"`): Name of the IAM role to create.
- `custom_policy_path` (`str`, optional, default: `None`): Path to custom policy JSON file. If not provided, uses SDK default policy.

**Returns:**

- `str`: ARN of the created/existing role

**Behavior:**

1. Checks if role already exists
2. Creates role with trust policy for SageMaker, ECS, and Lambda services
3. Creates and attaches combined policy with permissions for:
   - CloudFormation stack management
   - DynamoDB table operations
   - IAM role management
   - Lambda function operations
   - SQS queue operations
   - CloudWatch Logs access
   - ECR repository access
   - ECS task management
   - S3 bucket access
4. Waits for IAM propagation (15 seconds)

**Example:**

```python
from amzn_nova_forge import create_rft_execution_role

# Create role with default name
role_arn = create_rft_execution_role(region="us-east-1")
print(f"Created role: {role_arn}")

# Create role with custom name
role_arn = create_rft_execution_role(
    region="us-east-1",
    role_name="my-custom-rft-role"
)

# Create role with custom policy
role_arn = create_rft_execution_role(
    region="us-east-1",
    role_name="my-custom-rft-role",
    custom_policy_path="path/to/custom-policy.json"
)

# Use the role
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-stack",
    region="us-east-1",
    rft_role_name=role_arn.split('/')[-1],  # Extract role name from ARN
    python_venv_name="my_venv",
    vf_env_id=VFEnvId.WORDLE
)
```

### list_rft_stacks()

Lists CloudFormation stacks related to RFT multiturn infrastructure.

**Parameters:**

- `region` (`str`, optional, default: `"us-east-1"`): AWS region to list stacks from.
- `all_stacks` (`bool`, optional, default: `False`): If `True`, lists all CloudFormation stacks. If `False`, only lists Nova SDK-managed stacks (ending with `-NovaForgeSDK`).

**Returns:**

- `list[str]`: List of stack names

**Example:**

```python
from amzn_nova_forge import list_rft_stacks

# List only Nova Forge SDK stacks
nova_stacks = list_rft_stacks(region="us-east-1")
print(f"Found {len(nova_stacks)} Nova SDK stacks:")
for stack_name in nova_stacks:
    print(f"  - {stack_name}")

# List all CloudFormation stacks
all_stacks = list_rft_stacks(region="us-east-1", all_stacks=True)
print(f"Found {len(all_stacks)} total stacks")
```

## Cleanup

### kill_task() Method

Stops a running training or evaluation task.

**Parameters:**

- `env_type` (`EnvType`, required): Environment type to stop: `EnvType.TRAIN` or `EnvType.EVAL`.

**Returns:**

- `None`

**Platform Behavior:**

- **LOCAL**: Terminates the local process
- **EC2**: Cancels the SSM command invocation
- **ECS**: Stops the ECS task

**Example:**

```python
from amzn_nova_forge import EnvType

# Stop training task
rft_infra.kill_task(env_type=EnvType.TRAIN)

# Stop evaluation task
rft_infra.kill_task(env_type=EnvType.EVAL)
```

### cleanup() Method

Cleans up infrastructure resources.

**Parameters:**

- `delete_stack` (`bool`, optional, default: `False`): If `True`, deletes the CloudFormation stack (Lambda, SQS, DynamoDB).
- `cleanup_environment` (`bool`, optional, default: `False`): If `True`, removes environment files and directories.

**Returns:**

- `None`

**Cleanup Levels:**

**Level 1: Processes Only** (`delete_stack=False`, `cleanup_environment=False`)

- Stops running tasks
- Keeps CloudFormation stack
- Keeps environment files

**Level 2: Processes + Environment** (`delete_stack=False`, `cleanup_environment=True`)

- Stops running tasks
- Keeps CloudFormation stack
- **LOCAL/EC2**: Deletes virtual environment and starter kit directories
- **ECS**: Deregisters task definitions

**Level 3: Complete Cleanup** (`delete_stack=True`, `cleanup_environment=True`)

- Stops running tasks
- Deletes CloudFormation stack (Lambda, SQS, DynamoDB)
- **LOCAL/EC2**: Deletes virtual environment and starter kit directories
- **ECS**: Deregisters task definitions

**Examples:**

```python
# Clean up processes only (keeps CloudFormation stack and environment)
rft_infra.cleanup(delete_stack=False, cleanup_environment=False)

# Clean up and delete environment files
# - LOCAL/EC2: Deletes venv and starter kit directories
# - ECS: Deregisters task definitions
rft_infra.cleanup(delete_stack=False, cleanup_environment=True)

# Delete everything including CloudFormation stack
rft_infra.cleanup(delete_stack=True, cleanup_environment=True)

# Shorthand for complete cleanup
rft_infra.cleanup(delete_stack=True)  # cleanup_environment defaults to False
```

**Important Notes:**

- Always stop tasks before cleanup to avoid orphaned processes
- CloudFormation stack deletion removes Lambda functions, SQS queues, and DynamoDB tables
- Environment cleanup is irreversible - you'll need to run `setup()` again
- Use `delete_stack=False` if you plan to reuse the stack for another training/evaluation run

## Platform Support

### Supported Models

- Nova 2.0 models only:
  - `NOVA_LITE_2`

### Supported Training Methods

- `RFT_MULTITURN_LORA` - RFT Multiturn with LoRA
- `RFT_MULTITURN_FULL` - Full RFT Multiturn

### Supported Platforms

- **Training**: SageMaker HyperPod (SMHP) only
- **Infrastructure**: LOCAL, EC2, or ECS

### Platform Comparison

| Feature           | LOCAL    | EC2      | ECS                                           |
| ----------------- | -------- | -------- | --------------------------------------------- |
| Setup Complexity  | Low      | Medium   | Medium with default network configs else High |
| Scalability       | Limited  | Medium   | High                                          |
| Cost              | Low      | Medium   | Medium-High                                   |
| python_venv_name  | Required | Required | Optional                                      |
| VPC Config        | N/A      | N/A      | Required                                      |
| CPU/Memory Config | N/A      | N/A      | Optional                                      |

## Examples

### Complete Training Workflow

```python
from amzn_nova_forge import (
    ForgeTrainer,
    ForgeConfig,
    RFTMultiturnInfrastructure,
    Model,
    TrainingMethod,
    SMHPRuntimeManager,
    VFEnvId,
    EnvType,
    EvaluationTask
)

# 1. Setup infrastructure
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE
)

rft_infra.setup()

# Start training environment
rft_infra.start_environment(env_type=EnvType.TRAIN)

# Save state for recovery (optional)
state_file = rft_infra.dump()
print(f"State saved to: {state_file}")

# 2. Train
trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_MULTITURN_LORA,
    infra=SMHPRuntimeManager(
        cluster_name="my-cluster",
        namespace="kubeflow",
        instance_type="ml.p5.48xlarge",
        instance_count=2
    ),
    training_data_s3_path="s3://bucket/data.jsonl",
    config=ForgeConfig(output_s3_path="s3://bucket/output/")
)

training_result = trainer.train(
    job_name="rft-training",
    rft_multiturn_infra=rft_infra
)

training_result.wait()
checkpoint_path = training_result.model_artifacts.checkpoint_s3_path

# 3. Evaluate
rft_infra.kill_task(env_type=EnvType.TRAIN)
rft_infra.start_environment(env_type=EnvType.EVAL)

eval_result = evaluator.evaluate(
    job_name="rft-eval",
    eval_task=EvaluationTask.RFT_MULTITURN_EVAL,
    model_path=checkpoint_path,
    rft_multiturn_infra=rft_infra
)

eval_result.wait()
eval_result.show()

# 4. Cleanup
rft_infra.kill_task(env_type=EnvType.EVAL)
rft_infra.cleanup(delete_stack=True, cleanup_environment=True)
```

### Session Recovery Example

```python
from amzn_nova_forge import RFTMultiturnInfrastructure, EnvType

# Save the config
state_file = rft_infra.dump()

# After notebook restart or interruption
rft_infra = RFTMultiturnInfrastructure.load(
    state_file
)

# Check logs to see current status
logs = rft_infra.get_logs(env_type=EnvType.TRAIN, limit=100)
for log in logs:
    print(log)

# Continue with evaluation or cleanup
rft_infra.kill_task(env_type=EnvType.TRAIN)
rft_infra.start_environment(env_type=EnvType.EVAL)
```

## Troubleshooting

### Common Issues

**Issue**: Stack deployment fails with "queues are not empty"

```python
# Solution: Flush queues before reusing existing stack
rft_infra.flush_all_queues()
```

**Issue**: Custom environment not found on EC2/ECS

```python
# Solution: Ensure you've uploaded to S3
custom_env.package_and_upload()
```

**Issue**: Permission denied errors

```python
# Solution: Ensure RFT execution role has required permissions
from amzn_nova_forge import create_rft_execution_role
role_arn = create_rft_execution_role(region="us-east-1")
```

**Issue**: Training environment not starting

```python
# Solution: Check logs for errors
get_logs(env_type=EnvType.TRAIN, tail=True)
```

## Additional Resources

- [Main SDK Documentation](../README.md) - Complete SDK overview and getting started guide
- [API Specification](spec.md) - Detailed API documentation for all modules
- [Quick Start Notebook](../samples/nova_quickstart.ipynb) - General Nova customization examples
- [RFT Multiturn Notebook](../samples/rft_multiturn_quickstart.ipynb) - RFT multiturn specific examples
