# MLOps Training Patterns Reference

## Single-Instance Training Job

### Basic Training Job (PyTorch)

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point="train.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=1,
    instance_type="ml.g5.2xlarge",
    framework_version="2.1.0",
    py_version="py310",
    # Spot training — 60-90% savings
    use_spot_instances=True,
    max_wait=7200,       # 2x expected training time
    max_run=3600,        # max training time in seconds
    # Checkpointing for Spot resilience
    checkpoint_s3_uri=f"s3://{bucket}/checkpoints/{job_name}",
    checkpoint_local_path="/opt/ml/checkpoints",
    # Environment
    hyperparameters={
        "epochs": 10,
        "batch-size": 64,
        "learning-rate": 0.001,
    },
    tags=[{"Key": "project", "Value": "my-ml-project"}],
)

estimator.fit({
    "train": f"s3://{bucket}/data/train/",
    "validation": f"s3://{bucket}/data/validation/",
})
```

### Training with Trainium (ml.trn1)

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point="train_neuron.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=1,
    instance_type="ml.trn1.32xlarge",  # 16 Trainium chips, 512 GB accelerator memory
    framework_version="2.1.0",
    py_version="py310",
    # Neuron SDK is included in the SageMaker Trainium DLC
    image_uri=sagemaker.image_uris.retrieve(
        framework="pytorch",
        region=region,
        version="2.1.0",
        instance_type="ml.trn1.32xlarge",
    ),
    use_spot_instances=True,
    max_wait=14400,
    max_run=7200,
    checkpoint_s3_uri=f"s3://{bucket}/checkpoints/{job_name}",
    hyperparameters={
        "epochs": 10,
        "batch-size": 128,
    },
    distribution={
        "torch_distributed": {
            "enabled": True,
        }
    },
)
```

### Classical ML Training (XGBoost)

```python
from sagemaker.xgboost import XGBoost

estimator = XGBoost(
    entry_point="train.py",
    role=sagemaker_role,
    instance_count=1,
    instance_type="ml.m5.2xlarge",  # CPU only — no GPU needed for tree models
    framework_version="1.7-1",
    use_spot_instances=True,
    max_wait=3600,
    max_run=1800,
    hyperparameters={
        "max_depth": 6,
        "eta": 0.3,
        "num_round": 200,
        "objective": "binary:logistic",
        "eval_metric": "auc",
    },
)
```

## Distributed Training

### Data Parallel Training (SageMaker Distributed Data Parallelism)

Use when the model fits in one GPU but training is slow due to dataset size.

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point="train_ddp.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=4,              # 4 nodes
    instance_type="ml.p4d.24xlarge",  # 8x A100 per node = 32 GPUs total
    framework_version="2.1.0",
    py_version="py310",
    use_spot_instances=True,
    max_wait=14400,
    max_run=7200,
    checkpoint_s3_uri=f"s3://{bucket}/checkpoints/{job_name}",
    distribution={
        "smdistributed": {
            "dataparallel": {
                "enabled": True,
            }
        }
    },
    hyperparameters={
        "epochs": 20,
        "batch-size": 256,  # Global batch size = 256 * 32 GPUs
        "learning-rate": 0.001,
    },
)
```

**Training script changes for SMDDP:**

```python
import torch
import smdistributed.dataparallel.torch.torch_smddp  # Initialize SMDDP

# Use PyTorch DDP as normal — SMDDP replaces the backend
torch.distributed.init_process_group(backend="smddp")

local_rank = int(os.environ["LOCAL_RANK"])
torch.cuda.set_device(local_rank)

model = MyModel().to(local_rank)
model = torch.nn.parallel.DistributedDataParallel(model, device_ids=[local_rank])
```

### Model Parallel Training (SageMaker Model Parallelism)

Use when the model does not fit in a single GPU's memory.

```python
from sagemaker.pytorch import PyTorch

estimator = PyTorch(
    entry_point="train_mp.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=2,
    instance_type="ml.p5.48xlarge",  # 8x H100 per node, EFA enabled
    framework_version="2.1.0",
    py_version="py310",
    use_spot_instances=True,
    max_wait=28800,
    max_run=14400,
    checkpoint_s3_uri=f"s3://{bucket}/checkpoints/{job_name}",
    distribution={
        "smdistributed": {
            "modelparallel": {
                "enabled": True,
                "parameters": {
                    "tensor_parallel_degree": 8,
                    "pipeline_parallel_degree": 2,
                    "ddp": True,
                }
            }
        }
    },
)
```

### PyTorch Native Distributed (torchrun)

Use when you want framework-native distributed training without SageMaker libraries.

```python
estimator = PyTorch(
    entry_point="train.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=2,
    instance_type="ml.g5.12xlarge",  # 4x A10G per node
    framework_version="2.1.0",
    py_version="py310",
    use_spot_instances=True,
    max_wait=7200,
    max_run=3600,
    distribution={
        "torch_distributed": {
            "enabled": True,
        }
    },
)
```

## Managed Spot Training

### Checkpointing Setup

Checkpointing is mandatory for Spot training. Without it, a Spot interruption restarts training from epoch 0.

**In the training script:**

```python
import os
import torch

CHECKPOINT_DIR = "/opt/ml/checkpoints"

def save_checkpoint(model, optimizer, epoch, loss):
    """Save checkpoint to local path — SageMaker syncs to S3 automatically."""
    checkpoint = {
        "epoch": epoch,
        "model_state_dict": model.state_dict(),
        "optimizer_state_dict": optimizer.state_dict(),
        "loss": loss,
    }
    path = os.path.join(CHECKPOINT_DIR, f"checkpoint-{epoch}.pt")
    torch.save(checkpoint, path)

def load_latest_checkpoint(model, optimizer):
    """Resume from latest checkpoint if one exists (Spot restart)."""
    if not os.path.exists(CHECKPOINT_DIR):
        return 0
    checkpoints = sorted(
        [f for f in os.listdir(CHECKPOINT_DIR) if f.startswith("checkpoint-")],
        key=lambda x: int(x.split("-")[1].split(".")[0]),
    )
    if not checkpoints:
        return 0
    latest = os.path.join(CHECKPOINT_DIR, checkpoints[-1])
    checkpoint = torch.load(latest)
    model.load_state_dict(checkpoint["model_state_dict"])
    optimizer.load_state_dict(checkpoint["optimizer_state_dict"])
    return checkpoint["epoch"] + 1

# In training loop
start_epoch = load_latest_checkpoint(model, optimizer)
for epoch in range(start_epoch, total_epochs):
    train_one_epoch(model, optimizer, train_loader)
    save_checkpoint(model, optimizer, epoch, loss)
```

### Spot Savings Calculation

```
On-Demand ml.p4d.24xlarge: ~$32.77/hour
Spot ml.p4d.24xlarge: ~$9.83/hour (typical 70% savings)

10-hour training job:
  On-Demand: $327.70
  Spot: $98.30
  Savings: $229.40 per job
```

With checkpointing, even if the job is interrupted twice (adding 30 min overhead each time), total cost is still ~$108 — 67% less than On-Demand.

## Hyperparameter Tuning

### Bayesian Optimization (Default)

```python
from sagemaker.tuner import (
    HyperparameterTuner,
    ContinuousParameter,
    CategoricalParameter,
    IntegerParameter,
)

hyperparameter_ranges = {
    "learning-rate": ContinuousParameter(1e-5, 1e-2, scaling_type="Logarithmic"),
    "batch-size": CategoricalParameter([32, 64, 128, 256]),
    "weight-decay": ContinuousParameter(1e-6, 1e-2, scaling_type="Logarithmic"),
    "num-layers": IntegerParameter(2, 8),
}

tuner = HyperparameterTuner(
    estimator=estimator,
    objective_metric_name="validation:accuracy",
    objective_type="Maximize",
    hyperparameter_ranges=hyperparameter_ranges,
    max_jobs=50,          # Total trials
    max_parallel_jobs=5,  # Parallel trials (Bayesian benefits from sequential info)
    strategy="Bayesian",  # Default and recommended
    early_stopping_type="Auto",  # Stop poor trials early
)

tuner.fit({
    "train": train_input,
    "validation": validation_input,
})
```

### Hyperband Strategy

Use for faster results on a budget. Automatically allocates more resources to promising configurations.

```python
from sagemaker.tuner import HyperparameterTuner

tuner = HyperparameterTuner(
    estimator=estimator,
    objective_metric_name="validation:loss",
    objective_type="Minimize",
    hyperparameter_ranges=hyperparameter_ranges,
    strategy="Hyperband",
    max_jobs=100,
    max_parallel_jobs=10,
    strategy_config={
        "HyperbandStrategyConfig": {
            "MinResource": 1,   # Min epochs before early stop
            "MaxResource": 50,  # Max epochs for best configs
        }
    },
)
```

## SageMaker Processing Jobs

### Data Preparation with sklearn

```python
from sagemaker.processing import ScriptProcessor
from sagemaker.sklearn import SKLearnProcessor

processor = SKLearnProcessor(
    framework_version="1.2-1",
    role=sagemaker_role,
    instance_type="ml.m5.xlarge",
    instance_count=1,
)

processor.run(
    code="scripts/preprocess.py",
    inputs=[
        ProcessingInput(
            source=f"s3://{bucket}/raw-data/",
            destination="/opt/ml/processing/input",
        )
    ],
    outputs=[
        ProcessingOutput(
            output_name="train",
            source="/opt/ml/processing/output/train",
            destination=f"s3://{bucket}/processed/train/",
        ),
        ProcessingOutput(
            output_name="validation",
            source="/opt/ml/processing/output/validation",
            destination=f"s3://{bucket}/processed/validation/",
        ),
        ProcessingOutput(
            output_name="test",
            source="/opt/ml/processing/output/test",
            destination=f"s3://{bucket}/processed/test/",
        ),
    ],
)
```

### Spark Processing for Large Datasets

```python
from sagemaker.spark.processing import PySparkProcessor

spark_processor = PySparkProcessor(
    base_job_name="spark-preprocessing",
    framework_version="3.3",
    role=sagemaker_role,
    instance_count=4,
    instance_type="ml.m5.4xlarge",
    max_runtime_in_seconds=7200,
)

spark_processor.run(
    submit_app="scripts/spark_preprocess.py",
    arguments=[
        "--input-path", f"s3://{bucket}/raw-data/",
        "--output-path", f"s3://{bucket}/processed/",
    ],
    spark_event_logs_s3_uri=f"s3://{bucket}/spark-logs/",
)
```

## CLI Commands

### Launch a Training Job

```bash
aws sagemaker create-training-job \
    --training-job-name "my-training-$(date +%Y%m%d-%H%M%S)" \
    --algorithm-specification \
        TrainingImage="763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-training:2.1.0-gpu-py310-cu118-ubuntu20.04-sagemaker" \
        TrainingInputMode=File \
    --role-arn "$SAGEMAKER_ROLE_ARN" \
    --resource-config \
        InstanceType=ml.g5.2xlarge,InstanceCount=1,VolumeSizeInGB=50 \
    --input-data-config '[{
        "ChannelName": "train",
        "DataSource": {
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://my-bucket/data/train/"
            }
        }
    }]' \
    --output-data-config S3OutputPath="s3://my-bucket/output/" \
    --stopping-condition MaxRuntimeInSeconds=3600 \
    --enable-managed-spot-training \
    --checkpoint-config S3Uri="s3://my-bucket/checkpoints/"
```

### Monitor a Training Job

```bash
# Watch training job status
aws sagemaker describe-training-job \
    --training-job-name "my-training-job" \
    --query '{Status: TrainingJobStatus, Secondary: SecondaryStatus, Metrics: FinalMetricDataList}'

# Stream training logs
aws logs tail /aws/sagemaker/TrainingJobs --follow \
    --log-stream-name-prefix "my-training-job"

# List recent training jobs
aws sagemaker list-training-jobs \
    --sort-by CreationTime \
    --sort-order Descending \
    --max-results 10 \
    --query 'TrainingJobSummaries[].{Name:TrainingJobName,Status:TrainingJobStatus,Instance:ResourceConfig.InstanceType}'
```

### Hyperparameter Tuning Job Status

```bash
aws sagemaker describe-hyper-parameter-tuning-job \
    --hyper-parameter-tuning-job-name "my-tuning-job" \
    --query '{
        Status: HyperParameterTuningJobStatus,
        BestTrainingJob: BestTrainingJob.{Name:TrainingJobName,Metric:FinalHyperParameterTuningJobObjectiveMetric},
        Completed: TrainingJobStatusCounters.Completed,
        InProgress: TrainingJobStatusCounters.InProgress
    }'
```
