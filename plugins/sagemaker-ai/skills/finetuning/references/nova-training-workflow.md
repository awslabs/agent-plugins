---
name: training-workflow
description: Training jobs using ForgeTrainer for Nova models. Use when launching, monitoring, or configuring training jobs.
triggers:
  keywords: [train, training, job, run, launch, monitor, logs, hyperparameter, data mixing, job caching, mlflow, batch tracing]
  task_types: [training]
  error_patterns: ["ValueError: Instance type", "Training job", "job_status"]
  methods: [CPT, SFT, RFT, DPO]
prerequisites: []
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

> Ensure you've loaded best practices from the agent-memory skill before guiding the customer.

# Training Workflow

## Key Concepts

### ForgeTrainer

The training service class (replaces deprecated `NovaModelCustomizer` for training):

- `train()` — Launch or dry-run a training job
- `get_logs()` — Retrieve CloudWatch logs
- `trace_batch()` — Trace which training data lines were used in a specific step (requires `enable_batch_sample_tracing=True`)

### ForgeConfig

Shared configuration passed to service classes:

- `output_s3_path` — Where to write training artifacts
- `kms_key_id` — Optional encryption key
- `enable_job_caching` — Cache completed job results for reuse
- `job_cache_dir` — Custom cache directory (default: `.cached-nova-jobs/`)
- `mlflow_monitor` — MLflow tracking configuration
- `validation_config` — Pre-flight validation toggles

### Runtime Managers

| Need                                     | Recommended Runtime            |
| ---------------------------------------- | ------------------------------ |
| Simplest start, no reserved capacity     | `SMTJServerlessRuntimeManager` |
| SFT/RFT/DPO with specific instance types | `SMTJRuntimeManager`           |
| CPT, data mixing, RFT Multiturn          | `SMHPRuntimeManager`           |
| Fully managed Bedrock service            | `BedrockRuntimeManager`        |

### Data Mixing (SMHP Only)

Mix training data with Nova's built-in code and general data during CPT or SFT:

- Only supported on `SMHPRuntimeManager`
- Supported methods: CPT, SFT_LORA, SFT_FULL
- Enable at initialization: `data_mixing_enabled=True`

### Batch Sample Tracing

Diagnose gradient spikes by identifying which training data lines were used in a specific step:

- Enable with `enable_batch_sample_tracing=True` on `ForgeTrainer`
- After training, call `trainer.trace_batch(result, step=N)` to extract batch contents
- Outputs JSONL with matched lines sorted by line number
- Logs stored at `{output_s3_path}/{job_id}/batch_tracing/`

### MLflow Integration

Track experiments with MLflow on SageMaker:

- Works with all Sagemaker-based runtime managers (`SMTJServerlessRuntimeManager`, `SMTJRuntimeManager`, `SMHPRuntimeManager`)
- Pass `MLflowMonitor` to `ForgeConfig`
- **Agent instruction:** Ask the user if they have an existing MLflow app ARN they'd like to use, or if they'd like to use the default (`DefaultMLFlowApp`). If they have a specific ARN, pass it as `tracking_uri`. If they want the default, omit `tracking_uri` — the SDK will auto-discover `DefaultMLFlowApp`. Warn them that the default only works if a `DefaultMLFlowApp` already exists in their account (created via SageMaker console).

### RFT Reward Lambda

For RFT (singleturn) training:

- **`rft_lambda`** on runtime manager: Set to a Lambda ARN or local `.py` file path
- **`deploy_lambda()`**: Packages and deploys a local `.py` as Lambda, sets `rft_lambda_arn` automatically
- **`validate_lambda()`**: Tests reward function with sample data (locally or against deployed Lambda)
- **`rft_lambda_arn`** on `train()`: Optionally override the lambda at train time

### Dry Run Mode

Always test with `dry_run=True` first:

- Validates configuration
- Generates recipe
- Doesn't start actual job
- Catches errors before spending compute

## Step-by-Step Guide

### 1. Prepare Infrastructure

#### Option A: Serverless (simplest — no instance management)

```python
from amzn_nova_forge import SMTJServerlessRuntimeManager

infra = SMTJServerlessRuntimeManager(
    model_package_group_name='<project-name>-models',
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole'
)
```

> **`model_package_group_name`**: A unique name for the SageMaker Model Registry group. Allowed pattern: `[a-zA-Z0-9](-*[a-zA-Z0-9]){0,62}` (alphanumeric with hyphens, max 63 chars). Recommend lowercase with hyphens for consistency (e.g., `customer-support-chatbot-v1`). Ensure the execution role has `sagemaker:CreateModelPackageGroup` and `sagemaker:DescribeModelPackageGroup` permissions (see `iam-setup.md`).

#### Option B: SMTJ (full control of instances)

```python
from amzn_nova_forge import SMTJRuntimeManager

infra = SMTJRuntimeManager(
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
    instance_count=4,
    instance_type='ml.p5.48xlarge'
)
```

#### Option C: SMHP (CPT, data mixing, RFT Multiturn)

```python
from amzn_nova_forge import SMHPRuntimeManager

# Pre-existing cluster required — ask user for these values
infra = SMHPRuntimeManager(
    cluster_name='<cluster-name>',       # Ask user
    namespace='<namespace>',             # Ask user (e.g., 'default', 'kubeflow')
    instance_type='ml.p5.48xlarge',      # Ask user
    instance_count=4                     # Ask user
)

# Cluster scaling (Restricted Instance Groups only, optional)
instance_groups = infra.get_instance_groups()
infra.scale_cluster(instance_group_name="worker-group", target_instance_count=8)
```

### 2. Create Trainer

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/output/')
)
```

**With data mixing (SMHP only, CPT or SFT):**

```python
trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=smhp_infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/output/'),
    data_mixing_enabled=True
)
```

**With job caching:**

```python
trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(
        output_s3_path='s3://my-bucket/output/',
        enable_job_caching=True
    )
)
```

**With MLflow:**

```python
from amzn_nova_forge import MLflowMonitor

# Uses DefaultMLFlowApp if it exists in your account
mlflow_monitor = MLflowMonitor(
    experiment_name="nova-customization",
    run_name="sft-run-1"
)
# To use a specific MLflow app, set tracking_uri explicitly:
# mlflow_monitor = MLflowMonitor(
#     tracking_uri="arn:aws:sagemaker:us-east-1:123456789012:mlflow-app/app-xxx",
#     experiment_name="nova-customization",
#     run_name="sft-run-1"
# )

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(
        output_s3_path='s3://my-bucket/output/',
        mlflow_monitor=mlflow_monitor
    )
)
```

**With batch sample tracing:**

```python
trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/output/'),
    enable_batch_sample_tracing=True
)
```

### 3. Dry Run (Always Do This First!)

```python
result = trainer.train(
    job_name='my-sft-job-dryrun',
    overrides={
        'max_steps': 100,
        'lr': 1e-5,
        'global_batch_size': 32
    },
    dry_run=True
)
```

### 4. Launch Training

> **Hyperparameter guidance:** For recommended starting values by technique (SFT, RFT, CPT) including learning rate, epochs, batch size, and LoRA settings, consult `nova-hyperparameter-guidance.md`.

```python
result = trainer.train(
    job_name='my-sft-job',
    overrides={
        'max_steps': 100,
        'lr': 1e-5,
        'global_batch_size': 32
    },
)

# Save training result to manifests
from pathlib import Path
Path("<project-dir>/manifests").mkdir(parents=True, exist_ok=True)
result.dump(file_path="<project-dir>/manifests", file_name=f"training-{result.job_id}.json")
```

> **If the job fails:** Start with `trainer.get_logs(limit=200, start_from_head=True)`.

### 4b. Configure Data Mixing (Optional, SMHP Only)

```python
config = trainer.get_data_mixing_config()
print(config)

trainer.set_data_mixing_config({
    "customer_data_percent": 50,
    "nova_code_percent": 30,
    "nova_general_percent": 70
})
```

### 4c. Enable Job Notifications (Optional)

```python
result.enable_job_notifications(
    emails=["user@example.com", "team@example.com"]
)
```

### 5. Monitor Progress

```python
status = result.get_job_status()
print(f"Job status: {status}")

trainer.get_logs(limit=50, start_from_head=True)

# CloudWatch log monitor for detailed analysis
from amzn_nova_forge import CloudWatchLogMonitor
from amzn_nova_forge import Platform

# From result object (same session)
monitor = CloudWatchLogMonitor.from_job_result(job_result=result)

# Or from job ID (returning to a completed job)
monitor = CloudWatchLogMonitor.from_job_id(job_id=result.job_id, platform=Platform.SMTJ)

monitor.show_logs(start_from_head=True)

# Plot training metrics (loss curves, learning rate)
monitor.plot_metrics(training_method=TrainingMethod.SFT_LORA)

# Save plot to file
from matplotlib import pyplot
monitor.plot_metrics(training_method=TrainingMethod.SFT_LORA)
pyplot.savefig("<project-dir>/manifests/training_metrics.png", dpi=150, bbox_inches="tight")
```

> **Important:** Don't set a low `limit` when pulling logs for metric plotting — training metrics span the entire job.

### 5b. Trace Batch Samples (If Enabled)

```python
# After training completes — identify data lines used in a specific step
trace_result = trainer.trace_batch(result, step=100)
print(f"Batch trace output: {trace_result}")
```

## Troubleshooting

### Instance Type Errors

**Symptoms:** `ValueError: Instance type ... not supported`

**Solutions:**

1. Check `references/nova-instance-types.md` for allowed types per model/method
2. Common mappings:
   - SFT LoRA (Lite 2): `ml.p5.48xlarge` or `ml.p5en.48xlarge` (counts: 4, 8, 16)
   - RFT LoRA (Lite 2): `ml.p5.48xlarge` (counts: 2, 4, 8, 16)
3. Request quota increase in AWS Service Quotas if needed

### HyperPod Job Submission Failures

**Symptoms:** `EKS access denied`, `Namespace not found`

**Solutions:**

1. Grant EKS access:

   ```bash
   aws eks create-access-entry \
     --cluster-name <cluster-name> \
     --principal-arn arn:aws:iam::<account>:role/<execution-role>

   aws eks associate-access-policy \
     --cluster-name <cluster-name> \
     --principal-arn arn:aws:iam::<account>:role/<execution-role> \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
     --access-scope type=cluster
   ```

2. Verify HyperPod CLI is installed (see `sdk-getting-started` skill)
3. Check namespace exists and you have access

### MLflow Not Showing Data

**Problem:** MLflow experiment created but no data appears.

**Solutions:**

1. Verify the `tracking_uri` ARN is correct and the MLflow app exists in your account
2. Ensure the execution role has `sagemaker-mlflow:*` permissions (see `iam-setup.md`)
3. Check that the MLflow tracking server is in the same region as your training job

## Examples

### Example 1: Complete SFT Workflow (Serverless with MLflow)

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMTJServerlessRuntimeManager
from amzn_nova_forge import CloudWatchLogMonitor, MLflowMonitor

infra = SMTJServerlessRuntimeManager(
    model_package_group_name='<project-name>-models',
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole'
)

# Uses DefaultMLFlowApp if it exists in your account
mlflow_monitor = MLflowMonitor(
    experiment_name="nova-customization",
    run_name="financial-sft-run-1"
)
# To use a specific MLflow app, set tracking_uri explicitly:
# mlflow_monitor = MLflowMonitor(
#     tracking_uri="arn:aws:sagemaker:us-east-1:123456789012:mlflow-app/app-xxx",
#     experiment_name="nova-customization",
#     run_name="financial-sft-run-1"
# )

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/financial_qa_train.jsonl',
    config=ForgeConfig(
        output_s3_path='s3://my-bucket/output/',
        mlflow_monitor=mlflow_monitor
    )
)

# Dry run
trainer.train(
    job_name='financial-sft-dryrun',
    overrides={
        'max_steps': 100,
        'lr': 1e-5,
        'global_batch_size': 32
    },
   dry_run=True
)

# Train
result = trainer.train(
    job_name='financial-sft',
    overrides={
        'max_steps': 100,
        'lr': 1e-5,
        'global_batch_size': 32
    }
)
result.dump(file_path="<project-dir>/manifests", file_name=f"training-{result.job_id}.json")

# Monitor
print(f"Training job: {result.job_id}")
monitor = CloudWatchLogMonitor.from_job_result(job_result=result)
monitor.show_logs(start_from_head=True)
monitor.plot_metrics(training_method=TrainingMethod.SFT_LORA)

# Access MLflow UI
mlflow_url = mlflow_monitor.get_presigned_url()
print(f"Access MLflow UI at: {mlflow_url}")
```

### Example 2: SFT Workflow (SMTJ with MLflow)

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMTJRuntimeManager
from amzn_nova_forge import CloudWatchLogMonitor, MLflowMonitor

infra = SMTJRuntimeManager(
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
    instance_count=4,
    instance_type='ml.p5.48xlarge'
)

# Uses DefaultMLFlowApp if it exists in your account
mlflow_monitor = MLflowMonitor(
    experiment_name="nova-customization",
    run_name="sft-smtj-run-1"
)
# To use a specific MLflow app, set tracking_uri explicitly:
# mlflow_monitor = MLflowMonitor(
#     tracking_uri="arn:aws:sagemaker:us-east-1:123456789012:mlflow-app/app-xxx",
#     experiment_name="nova-customization",
#     run_name="sft-smtj-run-1"
# )

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/train.jsonl',
    config=ForgeConfig(
        output_s3_path='s3://my-bucket/output/',
        mlflow_monitor=mlflow_monitor
    )
)

# Dry run
trainer.train(job_name='sft-smtj-dryrun', dry_run=True)

# Train
result = trainer.train(
    job_name='sft-smtj',
    overrides={
        'max_steps': 100,
        'lr': 1e-5,
        'global_batch_size': 32
    }
)
result.dump(file_path="<project-dir>/manifests", file_name=f"training-{result.job_id}.json")

# Monitor
monitor = CloudWatchLogMonitor.from_job_result(job_result=result)
monitor.show_logs(start_from_head=True)
monitor.plot_metrics(training_method=TrainingMethod.SFT_LORA)

# Access MLflow UI
mlflow_url = mlflow_monitor.get_presigned_url()
print(f"Access MLflow UI at: {mlflow_url}")
```

### Example 3: RFT Workflow with Reward Lambda

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMTJRuntimeManager

# Option A: Lambda ARN directly
infra = SMTJRuntimeManager(
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
    instance_count=2,
    instance_type='ml.p5.48xlarge',
    rft_lambda='arn:aws:lambda:us-east-1:123456789012:function:my-reward-fn'
)

# Option B: Deploy a local reward function
infra = SMTJRuntimeManager(
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
    instance_count=2,
    instance_type='ml.p5.48xlarge'
)
infra.rft_lambda = 'rft_training_reward.py'
infra.validate_lambda(data_s3_path='s3://my-bucket/rft_train.jsonl')
lambda_arn = infra.deploy_lambda(lambda_name='my-reward-fn')

trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/rft_train.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/rft_output/')
)

result = trainer.train(
    job_name='my-rft-job',
    overrides={
        'max_steps': 100,
        'save_steps': 30,
        'lr': 5e-6,
        'global_batch_size': 64,
    }
)
result.dump(file_path="<project-dir>/manifests", file_name=f"training-{result.job_id}.json")
```

## Best Practices

1. **Always dry run first** — catches config errors before spending compute
2. **Always save training results** — `result.dump(file_path="<project-dir>/manifests", file_name=f"training-{result.job_id}.json")`
3. **Pull all logs for metric plotting** — don't set a low `limit`; training metrics span the entire job
4. **Use appropriate instance types** — check `references/nova-instance-types.md`
5. **Start with LoRA** — cheaper and faster than full-rank for initial experiments
6. **Use meaningful job names** — include method, model, and date
7. **Enable job caching for iteration** — `enable_job_caching=True` skips re-running identical configs
8. **Enable email notifications for long jobs** — `result.enable_job_notifications()`

## Proactive Next Steps

| Current Stage      | Next Step                                                         |
| ------------------ | ----------------------------------------------------------------- |
| Training started   | Enable notifications, monitor with `get_logs()`, `plot_metrics()` |
| Training completed | Run evaluation with ForgeEvaluator, or deploy if eval not needed  |
| Job failed         | Check `trainer.get_logs(limit=200, start_from_head=True)`         |

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
