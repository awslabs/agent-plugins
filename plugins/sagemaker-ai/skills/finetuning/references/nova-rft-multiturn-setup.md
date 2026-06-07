---
name: rft-multiturn-setup
description: Setting up RFT Multiturn infrastructure for multi-turn conversational reinforcement learning using ForgeTrainer.
triggers:
  keywords: [rft multiturn, multi-turn, custom environment, reward, wordle, terminal bench, verifier]
  task_types: [training, infrastructure]
  error_patterns: ["RFT_MULTITURN", "Queue has inflight", "kill_task", "flush_all_queues"]
  methods: [RFT_MULTITURN]
prerequisites: [training-workflow]
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

# RFT Multiturn Setup

## Prerequisites

- **HyperPod cluster with RIG**: A pre-existing HyperPod cluster with a Restricted Instance Group (RIG) must be provisioned and in `InService` state. RFT Multiturn requires SMHP — do NOT offer to create a cluster. Ask the user for: cluster name, namespace, instance type, and instance count.
- **HyperPod CLI (Forge version)**: Required for SMHP. See `sdk-getting-started` skill (Step 5).
- **EKS Cluster Access**: Execution role must have cluster access.
- **RFT Multiturn IAM**: Additional SSM, ECS, and CloudFormation permissions (see IAM setup reference).

## Quick Start

```python
from amzn_nova_forge import RFTMultiturnInfrastructure, VFEnvId, EnvType
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMHPRuntimeManager

# 1. Setup infrastructure (LOCAL)
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE
)
rft_infra.setup()
rft_infra.start_environment(env_type=EnvType.TRAIN)

# 2. Train
infra = SMHPRuntimeManager(
    cluster_name="my-cluster",
    namespace="kubeflow",
    instance_type="ml.p5.48xlarge",
    instance_count=2
)

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_MULTITURN_LORA,
    infra=infra,
    training_data_s3_path="s3://bucket/data.jsonl",
    config=ForgeConfig(output_s3_path="s3://bucket/output/")
)

result = trainer.train(
    job_name="rft-training",
    rft_multiturn_infra=rft_infra
)
result.wait()
result.dump(file_path=".", file_name=f"{result.job_id}_result.json")

# 3. Cleanup
rft_infra.kill_task(env_type=EnvType.TRAIN)
rft_infra.cleanup(delete_stack=True)
```

## Step-by-Step Guide

### 1. Choose Platform

| Platform | `infrastructure_arn`             | Best For               |
| -------- | -------------------------------- | ---------------------- |
| LOCAL    | `None` (default)                 | Development, testing   |
| EC2      | EC2 instance ID (`i-...`) or ARN | Production, persistent |
| ECS      | ECS cluster ARN                  | Production, scalable   |

### 2. Create Infrastructure

**LOCAL:**

```python
from amzn_nova_forge import RFTMultiturnInfrastructure, VFEnvId

rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE
)
```

**EC2:**

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="i-1234567890abcdef0",
    python_venv_name="my_rft_venv",
    vf_env_id=VFEnvId.WORDLE
)
```

**ECS:**

```python
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    infrastructure_arn="arn:aws:ecs:us-east-1:123456789012:cluster/my-cluster",
    vf_env_id=VFEnvId.WORDLE,
    vpc_config={
        "subnets": ["subnet-12345"],
        "security_groups": ["sg-12345"]
    }
)
```

### 3. Deploy and Start

```python
rft_infra.setup()

from amzn_nova_forge import EnvType
rft_infra.start_environment(
    env_type=EnvType.TRAIN,
    vf_env_args={"use_think": True, "max_turns": 10},
    max_concurrent_rollouts=60
)
```

### 4. Train with ForgeTrainer

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMHPRuntimeManager

infra = SMHPRuntimeManager(
    cluster_name="my-cluster",
    namespace="kubeflow",
    instance_type="ml.p5.48xlarge",
    instance_count=2
)

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_MULTITURN_LORA,
    infra=infra,
    training_data_s3_path="s3://bucket/data.jsonl",
    config=ForgeConfig(output_s3_path="s3://bucket/output/")
)

result = trainer.train(
    job_name="rft-multiturn-training",
    rft_multiturn_infra=rft_infra
)
result.wait()
result.dump(file_path=".", file_name=f"{result.job_id}_result.json")
```

### 5. Evaluate

```python
from amzn_nova_forge import ForgeEvaluator
from amzn_nova_forge import EvaluationTask
from amzn_nova_forge import TrainingResult

# Switch environments
rft_infra.kill_task(env_type=EnvType.TRAIN)
rft_infra.flush_all_queues()
rft_infra.start_environment(env_type=EnvType.EVAL)

evaluator = ForgeEvaluator(
    model=Model.NOVA_LITE_2,
    infra=infra,
    config=ForgeConfig(output_s3_path="s3://bucket/eval_output/")
)

training_result = TrainingResult.load("<job-name>_result.json")
eval_result = evaluator.evaluate(
    job_name="rft-eval",
    eval_task=EvaluationTask.RFT_MULTITURN_EVAL,
    model_path=training_result.model_artifacts.checkpoint_s3_path,
    rft_multiturn_infra=rft_infra
)
eval_result.wait()
eval_result.show()
```

### 6. Cleanup

```python
rft_infra.kill_task(env_type=EnvType.EVAL)
rft_infra.cleanup(delete_stack=True, cleanup_environment=True)
```

## Custom Environments

```python
from amzn_nova_forge import CustomEnvironment

# Create
custom_env = CustomEnvironment(
    env_id="my-custom-env",
    output_dir="~/custom_envs",
    env_type="multi_turn"
).create()

# Validate
custom_env.validate()

# Package for EC2/ECS (not needed for LOCAL)
custom_env.package_and_upload()

# Use
rft_infra = RFTMultiturnInfrastructure(
    stack_name="my-rft-stack",
    region="us-east-1",
    python_venv_name="my_rft_venv",
    custom_env=custom_env
)
```

## Session Persistence

```python
# Save state (before notebook restart)
state_file = rft_infra.dump()

# Restore (after restart)
rft_infra = RFTMultiturnInfrastructure.load(state_file)
```

## Troubleshooting

### Queue Errors

**Symptoms:** `Queue has inflight messages`, training doesn't progress.

**Solution:**

```python
rft_infra.kill_task(env_type=EnvType.TRAIN)
rft_infra.flush_all_queues()
```

### SMTJ Not Supported

**Problem:** `ValueError: RFT_MULTITURN_* not supported with SMTJRuntimeManager`

**Solution:** Use `SMHPRuntimeManager` — RFT Multiturn requires HyperPod.

### Custom Environment Not Found (EC2/ECS)

**Solution:** Call `custom_env.package_and_upload()` before passing to infrastructure.

## Best Practices

1. **Always flush queues** between training and evaluation
2. **Use LOCAL for development** — faster iteration
3. **Save state with `dump()`** — recover from notebook restarts
4. **Monitor queue status** — `check_all_queues()` to verify flow
5. **Clean up after training** — avoid charges from orphaned resources
6. **Test custom envs locally first** — validate before EC2/ECS

## References

- `references/nova-rft-multiturn-reference.md` — Complete API reference with all parameters
- For the full RFT Multiturn spec, see `docs/sdk/reference/rft_multiturn.md`

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
