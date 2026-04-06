# MLOps Pipeline Recipes Reference

## SageMaker Pipeline — Full Training Pipeline

### End-to-End Pipeline Definition

```python
import sagemaker
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.parameters import ParameterString, ParameterFloat, ParameterInteger
from sagemaker.workflow.steps import ProcessingStep, TrainingStep, TransformStep
from sagemaker.workflow.step_collections import RegisterModel
from sagemaker.workflow.conditions import ConditionGreaterThanOrEqualTo
from sagemaker.workflow.condition_step import ConditionStep
from sagemaker.workflow.functions import JsonGet
from sagemaker.workflow.properties import PropertyFile
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.pytorch import PyTorch
from sagemaker.inputs import TrainingInput

# ── Pipeline Parameters (parameterize everything for reuse across envs) ──
input_data = ParameterString(name="InputData", default_value=f"s3://{bucket}/raw-data/")
instance_type_training = ParameterString(name="TrainingInstanceType", default_value="ml.g5.2xlarge")
instance_type_processing = ParameterString(name="ProcessingInstanceType", default_value="ml.m5.xlarge")
accuracy_threshold = ParameterFloat(name="AccuracyThreshold", default_value=0.85)
epochs = ParameterInteger(name="Epochs", default_value=10)
model_package_group = ParameterString(name="ModelPackageGroup", default_value="my-model-group")

# ── Step 1: Data Processing ──
sklearn_processor = SKLearnProcessor(
    framework_version="1.2-1",
    role=sagemaker_role,
    instance_type=instance_type_processing,
    instance_count=1,
    sagemaker_session=pipeline_session,
)

processing_step = ProcessingStep(
    name="PreprocessData",
    processor=sklearn_processor,
    code="scripts/preprocess.py",
    inputs=[
        sagemaker.processing.ProcessingInput(
            source=input_data,
            destination="/opt/ml/processing/input",
        )
    ],
    outputs=[
        sagemaker.processing.ProcessingOutput(
            output_name="train", source="/opt/ml/processing/output/train"
        ),
        sagemaker.processing.ProcessingOutput(
            output_name="validation", source="/opt/ml/processing/output/validation"
        ),
        sagemaker.processing.ProcessingOutput(
            output_name="test", source="/opt/ml/processing/output/test"
        ),
    ],
    cache_config=CacheConfig(enable_caching=True, expire_after="P30D"),
)

# ── Step 2: Model Training ──
estimator = PyTorch(
    entry_point="train.py",
    source_dir="src/",
    role=sagemaker_role,
    instance_count=1,
    instance_type=instance_type_training,
    framework_version="2.1.0",
    py_version="py310",
    use_spot_instances=True,
    max_wait=7200,
    max_run=3600,
    checkpoint_s3_uri=f"s3://{bucket}/pipeline-checkpoints/",
    hyperparameters={
        "epochs": epochs,
        "batch-size": 64,
        "learning-rate": 0.001,
    },
    sagemaker_session=pipeline_session,
)

training_step = TrainingStep(
    name="TrainModel",
    estimator=estimator,
    inputs={
        "train": TrainingInput(
            s3_data=processing_step.properties.ProcessingOutputConfig.Outputs["train"].S3Output.S3Uri
        ),
        "validation": TrainingInput(
            s3_data=processing_step.properties.ProcessingOutputConfig.Outputs["validation"].S3Output.S3Uri
        ),
    },
    cache_config=CacheConfig(enable_caching=True, expire_after="P7D"),
)

# ── Step 3: Model Evaluation ──
evaluation_report = PropertyFile(
    name="EvaluationReport",
    output_name="evaluation",
    path="evaluation.json",
)

evaluation_step = ProcessingStep(
    name="EvaluateModel",
    processor=sklearn_processor,
    code="scripts/evaluate.py",
    inputs=[
        sagemaker.processing.ProcessingInput(
            source=training_step.properties.ModelArtifacts.S3ModelArtifacts,
            destination="/opt/ml/processing/model",
        ),
        sagemaker.processing.ProcessingInput(
            source=processing_step.properties.ProcessingOutputConfig.Outputs["test"].S3Output.S3Uri,
            destination="/opt/ml/processing/test",
        ),
    ],
    outputs=[
        sagemaker.processing.ProcessingOutput(
            output_name="evaluation",
            source="/opt/ml/processing/evaluation",
        ),
    ],
    property_files=[evaluation_report],
)

# ── Step 4: Conditional Registration ──
register_step = RegisterModel(
    name="RegisterModel",
    estimator=estimator,
    model_data=training_step.properties.ModelArtifacts.S3ModelArtifacts,
    content_types=["application/json"],
    response_types=["application/json"],
    inference_instances=["ml.g5.xlarge", "ml.inf2.xlarge", "ml.c7g.xlarge"],
    transform_instances=["ml.m5.xlarge"],
    model_package_group_name=model_package_group,
    approval_status="PendingManualApproval",
    model_metrics={
        "ModelQuality": {
            "Statistics": {
                "ContentType": "application/json",
                "S3Uri": f"s3://{bucket}/evaluation/statistics.json",
            }
        }
    },
)

# Quality gate: only register if accuracy exceeds threshold
condition = ConditionGreaterThanOrEqualTo(
    left=JsonGet(
        step_name=evaluation_step.name,
        property_file=evaluation_report,
        json_path="metrics.accuracy.value",
    ),
    right=accuracy_threshold,
)

condition_step = ConditionStep(
    name="CheckAccuracy",
    conditions=[condition],
    if_steps=[register_step],
    else_steps=[],  # Pipeline ends without registration if accuracy is too low
)

# ── Assemble Pipeline ──
pipeline = Pipeline(
    name="my-ml-pipeline",
    parameters=[
        input_data,
        instance_type_training,
        instance_type_processing,
        accuracy_threshold,
        epochs,
        model_package_group,
    ],
    steps=[processing_step, training_step, evaluation_step, condition_step],
    sagemaker_session=pipeline_session,
)

# Create or update the pipeline
pipeline.upsert(role_arn=sagemaker_role)

# Execute the pipeline
execution = pipeline.start(
    parameters={
        "InputData": f"s3://{bucket}/new-data/",
        "Epochs": 20,
        "AccuracyThreshold": 0.90,
    }
)
```

### Evaluation Script (scripts/evaluate.py)

```python
import json
import os
import tarfile
import torch
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score

if __name__ == "__main__":
    # Load model
    model_path = "/opt/ml/processing/model/model.tar.gz"
    with tarfile.open(model_path) as tar:
        tar.extractall(path="/opt/ml/processing/model/extracted")

    model = torch.load("/opt/ml/processing/model/extracted/model.pth")
    model.eval()

    # Load test data
    test_data = load_test_data("/opt/ml/processing/test/")

    # Run predictions
    predictions = []
    labels = []
    with torch.no_grad():
        for batch in test_data:
            outputs = model(batch["inputs"])
            predictions.extend(outputs.argmax(dim=1).tolist())
            labels.extend(batch["labels"].tolist())

    # Calculate metrics
    accuracy = accuracy_score(labels, predictions)
    precision = precision_score(labels, predictions, average="weighted")
    recall = recall_score(labels, predictions, average="weighted")
    f1 = f1_score(labels, predictions, average="weighted")

    # Write evaluation report
    report = {
        "metrics": {
            "accuracy": {"value": accuracy},
            "precision": {"value": precision},
            "recall": {"value": recall},
            "f1": {"value": f1},
        }
    }

    output_dir = "/opt/ml/processing/evaluation"
    os.makedirs(output_dir, exist_ok=True)
    with open(os.path.join(output_dir, "evaluation.json"), "w") as f:
        json.dump(report, f)

    print(f"Accuracy: {accuracy:.4f}, Precision: {precision:.4f}, "
          f"Recall: {recall:.4f}, F1: {f1:.4f}")
```

## Model Registry Workflows

### Register a Model Manually

```python
from sagemaker import ModelPackage

model_package = sm_client.create_model_package(
    ModelPackageGroupName="my-model-group",
    ModelPackageDescription="v2.1 — improved accuracy on edge cases",
    InferenceSpecification={
        "Containers": [
            {
                "Image": container_image_uri,
                "ModelDataUrl": f"s3://{bucket}/models/model-v2.1.tar.gz",
            }
        ],
        "SupportedContentTypes": ["application/json"],
        "SupportedResponseMIMETypes": ["application/json"],
        "SupportedRealtimeInferenceInstanceTypes": [
            "ml.g5.xlarge", "ml.inf2.xlarge",
        ],
        "SupportedTransformInstanceTypes": ["ml.m5.xlarge"],
    },
    ModelApprovalStatus="PendingManualApproval",
    ModelMetrics={
        "ModelQuality": {
            "Statistics": {
                "ContentType": "application/json",
                "S3Uri": f"s3://{bucket}/evaluation/v2.1/metrics.json",
            }
        }
    },
)
```

### Approve a Model

```python
sm_client.update_model_package(
    ModelPackageArn=model_package_arn,
    ModelApprovalStatus="Approved",
    ApprovalDescription="Reviewed by ML team. Accuracy 94.2% on holdout set.",
)
```

### Automated Approval via EventBridge

```python
# EventBridge rule: trigger deployment when a model is approved
import json

rule = {
    "source": ["aws.sagemaker"],
    "detail-type": ["SageMaker Model Package State Change"],
    "detail": {
        "ModelPackageGroupName": ["my-model-group"],
        "ModelApprovalStatus": ["Approved"],
    },
}

# Target: CodePipeline or Lambda that deploys the approved model
events_client.put_rule(
    Name="model-approved-trigger",
    EventPattern=json.dumps(rule),
    State="ENABLED",
)

events_client.put_targets(
    Rule="model-approved-trigger",
    Targets=[
        {
            "Id": "deploy-pipeline",
            "Arn": codepipeline_arn,
            "RoleArn": eventbridge_role_arn,
        }
    ],
)
```

### Cross-Account Model Deployment

```python
# In the model-producing account: grant cross-account access
sm_client.put_model_package_group_policy(
    ModelPackageGroupName="my-model-group",
    ResourcePolicy=json.dumps({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AllowProductionAccountAccess",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::PRODUCTION_ACCOUNT_ID:root"
                },
                "Action": [
                    "sagemaker:DescribeModelPackage",
                    "sagemaker:DescribeModelPackageGroup",
                    "sagemaker:ListModelPackages",
                ],
                "Resource": "*",
            }
        ],
    }),
)

# In the production account: deploy the model using its ARN
model = ModelPackage(
    role=production_role,
    model_package_arn=f"arn:aws:sagemaker:us-east-1:MODEL_ACCOUNT_ID:model-package/my-model-group/3",
)
predictor = model.deploy(
    instance_type="ml.g5.xlarge",
    initial_instance_count=2,
)
```

## CI/CD Integration

### CodePipeline + SageMaker Pipeline

```yaml
# buildspec.yml for CodeBuild stage that triggers SageMaker Pipeline
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.11
    commands:
      - pip install sagemaker boto3

  build:
    commands:
      - echo "Starting SageMaker Pipeline execution"
      - python scripts/start_pipeline.py

  post_build:
    commands:
      - echo "Pipeline execution started"
      - python scripts/wait_for_pipeline.py
```

### Pipeline Trigger Script (scripts/start_pipeline.py)

```python
import boto3
import json
import os

sm = boto3.client("sagemaker")

pipeline_name = os.environ.get("PIPELINE_NAME", "my-ml-pipeline")
commit_id = os.environ.get("CODEBUILD_RESOLVED_SOURCE_VERSION", "unknown")

# Start pipeline execution with parameters
response = sm.start_pipeline_execution(
    PipelineName=pipeline_name,
    PipelineExecutionDisplayName=f"ci-{commit_id[:8]}",
    PipelineParameters=[
        {"Name": "InputData", "Value": f"s3://{os.environ['DATA_BUCKET']}/latest/"},
        {"Name": "Epochs", "Value": "20"},
    ],
    PipelineExecutionDescription=f"Triggered by commit {commit_id}",
)

execution_arn = response["PipelineExecutionArn"]
print(f"Pipeline execution started: {execution_arn}")

# Save ARN for the wait step
with open("pipeline_execution_arn.txt", "w") as f:
    f.write(execution_arn)
```

### GitHub Actions Integration

```yaml
# .github/workflows/ml-pipeline.yml
name: ML Pipeline

on:
  push:
    branches: [main]
    paths:
      - 'src/training/**'
      - 'scripts/**'
      - 'configs/**'

jobs:
  trigger-pipeline:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read

    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.SAGEMAKER_ROLE_ARN }}
          aws-region: us-east-1

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install sagemaker boto3

      - name: Update and start pipeline
        run: |
          python scripts/upsert_pipeline.py
          python scripts/start_pipeline.py
        env:
          DATA_BUCKET: ${{ secrets.DATA_BUCKET }}
          PIPELINE_NAME: my-ml-pipeline

      - name: Wait for pipeline completion
        run: python scripts/wait_for_pipeline.py
        timeout-minutes: 120
```

## MLflow Experiment Tracking

### Managed MLflow on SageMaker Setup

```python
import mlflow
import sagemaker

# Get the MLflow tracking URI from SageMaker
tracking_server_arn = "arn:aws:sagemaker:us-east-1:123456789012:mlflow-tracking-server/my-server"
tracking_uri = sagemaker.session.Session().sagemaker_client.describe_mlflow_tracking_server(
    TrackingServerName="my-server"
)["TrackingServerUrl"]

mlflow.set_tracking_uri(tracking_uri)
```

### Experiment Tracking in Training Script

```python
import mlflow
import mlflow.pytorch

# Set experiment (creates if not exists)
mlflow.set_experiment("my-classification-project")

with mlflow.start_run(run_name="pytorch-v2.1") as run:
    # Log parameters
    mlflow.log_params({
        "learning_rate": 0.001,
        "batch_size": 64,
        "epochs": 20,
        "optimizer": "AdamW",
        "model_architecture": "resnet50",
        "instance_type": "ml.g5.2xlarge",
    })

    # Training loop
    for epoch in range(epochs):
        train_loss = train_one_epoch(model, optimizer, train_loader)
        val_loss, val_accuracy = evaluate(model, val_loader)

        # Log metrics per epoch
        mlflow.log_metrics({
            "train_loss": train_loss,
            "val_loss": val_loss,
            "val_accuracy": val_accuracy,
        }, step=epoch)

    # Log the final model
    mlflow.pytorch.log_model(
        model,
        "model",
        registered_model_name="my-classifier",  # Auto-registers in SageMaker Model Registry
    )

    # Log artifacts
    mlflow.log_artifact("confusion_matrix.png")
    mlflow.log_artifact("classification_report.json")

    print(f"Run ID: {run.info.run_id}")
```

### Compare Experiments

```python
import mlflow

# Search runs across experiments
runs = mlflow.search_runs(
    experiment_names=["my-classification-project"],
    filter_string="metrics.val_accuracy > 0.85",
    order_by=["metrics.val_accuracy DESC"],
    max_results=10,
)

print(runs[["run_id", "params.learning_rate", "params.batch_size",
            "metrics.val_accuracy", "metrics.val_loss"]])
```

### Deploy MLflow Model to SageMaker

```python
import mlflow.sagemaker

# Deploy directly from MLflow model registry
mlflow.sagemaker.deploy(
    model_uri="models:/my-classifier/Production",
    endpoint_name="my-mlflow-endpoint",
    region_name="us-east-1",
    instance_type="ml.g5.xlarge",
    instance_count=1,
    role=sagemaker_role,
)
```

## Model Monitoring Configuration

### Data Quality Monitor

```python
from sagemaker.model_monitor import DefaultModelMonitor
from sagemaker.model_monitor.dataset_format import DatasetFormat

# Create baseline from training data
monitor = DefaultModelMonitor(
    role=sagemaker_role,
    instance_count=1,
    instance_type="ml.m5.xlarge",
    volume_size_in_gb=20,
    max_runtime_in_seconds=3600,
)

monitor.suggest_baseline(
    baseline_dataset=f"s3://{bucket}/data/train/train.csv",
    dataset_format=DatasetFormat.csv(header=True),
    output_s3_uri=f"s3://{bucket}/monitoring/baseline/",
)

# Schedule monitoring
monitor.create_monitoring_schedule(
    monitor_schedule_name="data-quality-monitor",
    endpoint_input=endpoint_name,
    output_s3_uri=f"s3://{bucket}/monitoring/data-quality-reports/",
    statistics=monitor.baseline_statistics(),
    constraints=monitor.suggested_constraints(),
    schedule_cron_expression="cron(0 * ? * * *)",  # Hourly
)
```

### Model Quality Monitor

```python
from sagemaker.model_monitor import ModelQualityMonitor

model_monitor = ModelQualityMonitor(
    role=sagemaker_role,
    instance_count=1,
    instance_type="ml.m5.xlarge",
    volume_size_in_gb=20,
    max_runtime_in_seconds=1800,
    sagemaker_session=sagemaker_session,
)

# Create baseline
model_monitor.suggest_baseline(
    problem_type="BinaryClassification",
    baseline_dataset=f"s3://{bucket}/baseline/predictions-with-labels.csv",
    dataset_format=DatasetFormat.csv(header=True),
    output_s3_uri=f"s3://{bucket}/monitoring/model-quality-baseline/",
    ground_truth_input=f"s3://{bucket}/ground-truth/",
)

# Schedule
model_monitor.create_monitoring_schedule(
    monitor_schedule_name="model-quality-monitor",
    endpoint_input=endpoint_name,
    output_s3_uri=f"s3://{bucket}/monitoring/model-quality-reports/",
    problem_type="BinaryClassification",
    ground_truth_input=f"s3://{bucket}/ground-truth/",
    constraints=model_monitor.suggested_constraints(),
    schedule_cron_expression="cron(0 0 ? * * *)",  # Daily
)
```

### CloudWatch Alarms for Monitoring Violations

```python
import boto3

cloudwatch = boto3.client("cloudwatch")

# Alarm on data quality violations
cloudwatch.put_metric_alarm(
    AlarmName="mlops-data-quality-violation",
    MetricName="data_quality_violations",
    Namespace="aws/sagemaker/Endpoints/data-metrics",
    Statistic="Maximum",
    Period=3600,
    EvaluationPeriods=1,
    Threshold=0,
    ComparisonOperator="GreaterThanThreshold",
    AlarmActions=[sns_topic_arn],
    AlarmDescription="Data quality violation detected — feature distribution drift",
    Dimensions=[
        {"Name": "Endpoint", "Value": endpoint_name},
        {"Name": "MonitoringSchedule", "Value": "data-quality-monitor"},
    ],
)
```

### Automated Retraining on Drift Detection

```python
# EventBridge rule: trigger pipeline when monitoring detects violations
rule = {
    "source": ["aws.sagemaker"],
    "detail-type": ["SageMaker Model Monitor Alert"],
    "detail": {
        "MonitoringScheduleName": ["data-quality-monitor"],
    },
}

# Target: Lambda that starts the SageMaker Pipeline
events_client.put_rule(
    Name="drift-detected-retrain",
    EventPattern=json.dumps(rule),
    State="ENABLED",
)

events_client.put_targets(
    Rule="drift-detected-retrain",
    Targets=[
        {
            "Id": "retrain-trigger",
            "Arn": retrain_lambda_arn,
            "RoleArn": eventbridge_role_arn,
        }
    ],
)
```

## CLI Commands

### Pipeline Management

```bash
# List pipelines
aws sagemaker list-pipelines \
    --sort-by CreationTime \
    --sort-order Descending \
    --max-results 10

# Describe a pipeline
aws sagemaker describe-pipeline \
    --pipeline-name "my-ml-pipeline"

# Start pipeline execution
aws sagemaker start-pipeline-execution \
    --pipeline-name "my-ml-pipeline" \
    --pipeline-parameters '[
        {"Name": "InputData", "Value": "s3://my-bucket/new-data/"},
        {"Name": "Epochs", "Value": "20"}
    ]'

# List executions
aws sagemaker list-pipeline-executions \
    --pipeline-name "my-ml-pipeline" \
    --sort-by CreationTime \
    --sort-order Descending \
    --max-results 5

# Describe execution
aws sagemaker describe-pipeline-execution \
    --pipeline-execution-arn "arn:aws:sagemaker:us-east-1:123456789012:pipeline/my-ml-pipeline/execution/abc123"

# List steps in an execution
aws sagemaker list-pipeline-execution-steps \
    --pipeline-execution-arn "arn:aws:sagemaker:us-east-1:123456789012:pipeline/my-ml-pipeline/execution/abc123"

# Stop a running pipeline
aws sagemaker stop-pipeline-execution \
    --pipeline-execution-arn "arn:aws:sagemaker:us-east-1:123456789012:pipeline/my-ml-pipeline/execution/abc123"
```

### Model Registry

```bash
# List model package groups
aws sagemaker list-model-package-groups \
    --sort-by CreationTime \
    --sort-order Descending

# List model versions in a group
aws sagemaker list-model-packages \
    --model-package-group-name "my-model-group" \
    --sort-by CreationTime \
    --sort-order Descending

# Describe a model version
aws sagemaker describe-model-package \
    --model-package-name "arn:aws:sagemaker:us-east-1:123456789012:model-package/my-model-group/3"

# Approve a model
aws sagemaker update-model-package \
    --model-package-arn "arn:aws:sagemaker:us-east-1:123456789012:model-package/my-model-group/3" \
    --model-approval-status "Approved" \
    --approval-description "Approved after staging validation"
```

### Monitoring

```bash
# List monitoring schedules
aws sagemaker list-monitoring-schedules \
    --endpoint-name "my-endpoint" \
    --sort-by CreationTime

# Describe monitoring schedule
aws sagemaker describe-monitoring-schedule \
    --monitoring-schedule-name "data-quality-monitor"

# List monitoring executions
aws sagemaker list-monitoring-executions \
    --monitoring-schedule-name "data-quality-monitor" \
    --sort-by CreationTime \
    --sort-order Descending \
    --max-results 5

# Check latest violation report
aws s3 cp s3://my-bucket/monitoring/data-quality-reports/latest/constraint_violations.json - | jq .
```
