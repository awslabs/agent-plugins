# MLOps Inference Deployment Reference

## Real-Time Endpoint

### Basic Endpoint Deployment

```python
from sagemaker.pytorch import PyTorchModel

model = PyTorchModel(
    model_data=f"s3://{bucket}/output/model.tar.gz",
    role=sagemaker_role,
    framework_version="2.1.0",
    py_version="py310",
    entry_point="inference.py",
    source_dir="src/",
)

predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.g5.xlarge",
    endpoint_name="my-model-endpoint",
    wait=True,
)

# Invoke
response = predictor.predict({"inputs": "Hello world"})
```

### Deploying with Inferentia2 (ml.inf2)

```python
from sagemaker.pytorch import PyTorchModel

# Model must be compiled with Neuron SDK
model = PyTorchModel(
    model_data=f"s3://{bucket}/output/neuron-model.tar.gz",
    role=sagemaker_role,
    image_uri=sagemaker.image_uris.retrieve(
        framework="pytorch",
        region=region,
        version="2.1.0",
        instance_type="ml.inf2.xlarge",
    ),
    entry_point="inference_neuron.py",
    source_dir="src/",
)

predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.inf2.xlarge",  # 1 Inferentia2 chip, cost-effective inference
    endpoint_name="my-inf2-endpoint",
)
```

### Deploy from Model Registry

```python
from sagemaker import ModelPackage

model_package_arn = (
    "arn:aws:sagemaker:us-east-1:123456789012:model-package/my-model-group/1"
)

model = ModelPackage(
    role=sagemaker_role,
    model_package_arn=model_package_arn,
    sagemaker_session=sagemaker_session,
)

predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.g5.xlarge",
    endpoint_name="my-production-endpoint",
)
```

## Auto-Scaling Configuration

### Target Tracking on InvocationsPerInstance

```python
import boto3

client = boto3.client("application-autoscaling")

# Register the endpoint as a scalable target
client.register_scalable_target(
    ServiceNamespace="sagemaker",
    ResourceId=f"endpoint/{endpoint_name}/variant/AllTraffic",
    ScalableDimension="sagemaker:variant:DesiredInstanceCount",
    MinCapacity=1,
    MaxCapacity=10,
)

# Target tracking scaling policy
client.put_scaling_policy(
    PolicyName="InvocationsPerInstanceScaling",
    ServiceNamespace="sagemaker",
    ResourceId=f"endpoint/{endpoint_name}/variant/AllTraffic",
    ScalableDimension="sagemaker:variant:DesiredInstanceCount",
    PolicyType="TargetTrackingScaling",
    TargetTrackingScalingPolicyConfiguration={
        "TargetValue": 750.0,  # Target invocations per instance per minute
        "PredefinedMetricSpecification": {
            "PredefinedMetricType": "SageMakerVariantInvocationsPerInstance",
        },
        "ScaleInCooldown": 300,   # 5 min cooldown before scaling in
        "ScaleOutCooldown": 60,   # 1 min cooldown before scaling out
    },
)
```

### Step Scaling for More Control

```python
# Step scaling — add 2 instances when invocations > 1000/min
client.put_scaling_policy(
    PolicyName="HighTrafficStepScaling",
    ServiceNamespace="sagemaker",
    ResourceId=f"endpoint/{endpoint_name}/variant/AllTraffic",
    ScalableDimension="sagemaker:variant:DesiredInstanceCount",
    PolicyType="StepScaling",
    StepScalingPolicyConfiguration={
        "AdjustmentType": "ChangeInCapacity",
        "StepAdjustments": [
            {
                "MetricIntervalLowerBound": 0,
                "MetricIntervalUpperBound": 500,
                "ScalingAdjustment": 1,
            },
            {
                "MetricIntervalLowerBound": 500,
                "ScalingAdjustment": 2,
            },
        ],
        "Cooldown": 120,
    },
)
```

## Serverless Inference

### Deployment

```python
from sagemaker.serverless import ServerlessInferenceConfig

serverless_config = ServerlessInferenceConfig(
    memory_size_in_mb=4096,       # 1024, 2048, 3072, 4096, 5120, or 6144
    max_concurrency=10,            # Max concurrent invocations
    provisioned_concurrency=0,     # 0 = no provisioned (pure on-demand)
)

predictor = model.deploy(
    serverless_inference_config=serverless_config,
    endpoint_name="my-serverless-endpoint",
)
```

### When Serverless is Cost-Effective

```
Comparison at 100 requests/day, 500ms avg inference time:

Real-time ml.m5.large (always on):
  $0.134/hour * 730 hours = ~$98/month

Serverless (4 GB memory):
  Compute: 100 req * 500ms * $0.00001667/ms = $0.83/month
  Request: 100 req * $0.0000002 = negligible
  Total: ~$1/month

Break-even: Serverless is cheaper until ~60,000 requests/day at 500ms latency
```

### Cold Start Mitigation

- **Provisioned concurrency**: Pre-warms a specified number of instances. Eliminates cold start but adds baseline cost.
- **Model optimization**: Smaller model artifacts load faster. Quantize or distill models to reduce cold start time.
- **Warm-up invocations**: Schedule periodic invocations via EventBridge to keep instances warm (workaround, not recommended for production SLAs).

## Batch Transform

### Basic Batch Transform

```python
transformer = model.transformer(
    instance_count=4,
    instance_type="ml.m5.4xlarge",
    output_path=f"s3://{bucket}/batch-output/",
    strategy="MultiRecord",        # Process multiple records per request
    max_payload=6,                  # Max payload in MB
    max_concurrent_transforms=4,   # Parallel requests per instance
    assemble_with="Line",          # How to assemble output
)

transformer.transform(
    data=f"s3://{bucket}/batch-input/",
    content_type="text/csv",
    split_type="Line",             # Split input by line
    wait=True,
)
```

### Batch Transform for Large Datasets

```python
# For very large datasets, increase parallelism
transformer = model.transformer(
    instance_count=10,
    instance_type="ml.g5.2xlarge",     # GPU for DL models
    output_path=f"s3://{bucket}/batch-output/",
    max_concurrent_transforms=8,
    max_payload=100,                    # Up to 100 MB per record
)
```

### CLI: Start a Batch Transform Job

```bash
aws sagemaker create-transform-job \
    --transform-job-name "batch-$(date +%Y%m%d-%H%M%S)" \
    --model-name "my-model" \
    --transform-input '{
        "DataSource": {
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://my-bucket/batch-input/"
            }
        },
        "ContentType": "text/csv",
        "SplitType": "Line"
    }' \
    --transform-output '{
        "S3OutputPath": "s3://my-bucket/batch-output/",
        "AssembleWith": "Line"
    }' \
    --transform-resources '{
        "InstanceType": "ml.m5.4xlarge",
        "InstanceCount": 4
    }'
```

## Async Inference

### Deployment

```python
from sagemaker.async_inference import AsyncInferenceConfig

async_config = AsyncInferenceConfig(
    output_path=f"s3://{bucket}/async-output/",
    failure_path=f"s3://{bucket}/async-failures/",
    max_concurrent_invocations_per_instance=4,
    notification_config={
        "SuccessTopic": success_sns_topic_arn,
        "ErrorTopic": error_sns_topic_arn,
    },
)

predictor = model.deploy(
    initial_instance_count=1,
    instance_type="ml.g5.2xlarge",
    async_inference_config=async_config,
    endpoint_name="my-async-endpoint",
)
```

### Scale-to-Zero for Async Endpoints

```python
# Async endpoints can scale to 0 instances when idle
client.register_scalable_target(
    ServiceNamespace="sagemaker",
    ResourceId=f"endpoint/{endpoint_name}/variant/AllTraffic",
    ScalableDimension="sagemaker:variant:DesiredInstanceCount",
    MinCapacity=0,   # Scale to zero
    MaxCapacity=5,
)

# Scale based on queue depth
client.put_scaling_policy(
    PolicyName="QueueBasedScaling",
    ServiceNamespace="sagemaker",
    ResourceId=f"endpoint/{endpoint_name}/variant/AllTraffic",
    ScalableDimension="sagemaker:variant:DesiredInstanceCount",
    PolicyType="TargetTrackingScaling",
    TargetTrackingScalingPolicyConfiguration={
        "TargetValue": 5.0,
        "CustomizedMetricSpecification": {
            "MetricName": "ApproximateBacklogSizePerInstance",
            "Namespace": "AWS/SageMaker",
            "Dimensions": [
                {"Name": "EndpointName", "Value": endpoint_name},
            ],
            "Statistic": "Average",
        },
        "ScaleInCooldown": 600,
        "ScaleOutCooldown": 60,
    },
)
```

### Invoke Async Endpoint

```python
import boto3
import json

runtime = boto3.client("sagemaker-runtime")

# Upload input to S3
s3 = boto3.client("s3")
s3.put_object(
    Bucket=bucket,
    Key="async-input/request-001.json",
    Body=json.dumps({"inputs": "Large input data here..."}),
)

# Invoke — returns immediately with output location
response = runtime.invoke_endpoint_async(
    EndpointName="my-async-endpoint",
    InputLocation=f"s3://{bucket}/async-input/request-001.json",
    ContentType="application/json",
)

output_location = response["OutputLocation"]
# Poll output_location or use SNS notification to know when result is ready
```

## Multi-Model Endpoints (MME)

### Deployment

```python
from sagemaker.multidatamodel import MultiDataModel

mme = MultiDataModel(
    name="my-multi-model",
    model_data_prefix=f"s3://{bucket}/models/",  # Directory containing model.tar.gz files
    model=model,  # Base model for container config
    sagemaker_session=sagemaker_session,
)

predictor = mme.deploy(
    initial_instance_count=2,
    instance_type="ml.g5.xlarge",
    endpoint_name="my-mme-endpoint",
)
```

### Invoke a Specific Model

```python
# Specify which model to invoke via TargetModel
response = predictor.predict(
    data=payload,
    target_model="customer-123/model.tar.gz",  # Relative path under model_data_prefix
)
```

### Adding/Removing Models Dynamically

```python
# Add a new model — just upload to S3, MME loads on first request
mme.add_model(
    model_data_source=f"s3://{bucket}/new-models/customer-456/model.tar.gz",
    model_data_path="customer-456/model.tar.gz",
)

# List loaded models
models = mme.list_models()
```

## Shadow Testing

### Create a Shadow Variant

```python
import boto3

sm = boto3.client("sagemaker")

# Create endpoint with production + shadow variant
sm.create_endpoint_config(
    EndpointConfigName="shadow-test-config",
    ProductionVariants=[
        {
            "VariantName": "production",
            "ModelName": "current-model",
            "InstanceType": "ml.g5.xlarge",
            "InitialInstanceCount": 2,
            "InitialVariantWeight": 1.0,
        },
    ],
    ShadowProductionVariants=[
        {
            "VariantName": "shadow",
            "ModelName": "candidate-model",
            "InstanceType": "ml.g5.xlarge",
            "InitialInstanceCount": 1,
            "SamplingPercentage": 100,  # % of production traffic to mirror
        },
    ],
)

sm.update_endpoint(
    EndpointName="my-production-endpoint",
    EndpointConfigName="shadow-test-config",
)
```

### Compare Shadow Results

Shadow variant responses are logged to S3 via Data Capture. Compare production vs shadow predictions:

```python
# Enable data capture on both variants
data_capture_config = {
    "EnableCapture": True,
    "InitialSamplingPercentage": 100,
    "DestinationS3Uri": f"s3://{bucket}/data-capture/",
    "CaptureOptions": [
        {"CaptureMode": "Input"},
        {"CaptureMode": "Output"},
    ],
}
```

After collecting sufficient data (recommend at least 1 week of production traffic), compare metrics:
- Prediction distribution differences
- Latency p50/p95/p99
- Error rates
- Business metric impact (if measurable)

## Inference Recommender

### Run a Benchmark

```python
sm = boto3.client("sagemaker")

# Default job — tests a curated set of instance types
response = sm.create_inference_recommendations_job(
    JobName="my-model-benchmark",
    JobType="Default",  # or "Advanced" for custom configs
    RoleArn=sagemaker_role,
    InputConfig={
        "ModelPackageVersionArn": model_package_arn,
        "JobDurationInSeconds": 7200,
    },
)

# Check results
result = sm.describe_inference_recommendations_job(
    JobName="my-model-benchmark"
)

for rec in result["InferenceRecommendations"]:
    print(f"Instance: {rec['EndpointConfiguration']['InstanceType']}")
    print(f"  Cost/hour: ${rec['Metrics']['CostPerHour']}")
    print(f"  Cost/inference: ${rec['Metrics']['CostPerInference']}")
    print(f"  Latency p50: {rec['Metrics']['ModelLatency']}ms")
    print(f"  Max invocations: {rec['Metrics']['MaxInvocations']}/min")
```

### Advanced Benchmark with Custom Traffic

```python
response = sm.create_inference_recommendations_job(
    JobName="my-model-advanced-benchmark",
    JobType="Advanced",
    RoleArn=sagemaker_role,
    InputConfig={
        "ModelPackageVersionArn": model_package_arn,
        "JobDurationInSeconds": 7200,
        "EndpointConfigurations": [
            {"InstanceType": "ml.g5.xlarge"},
            {"InstanceType": "ml.g5.2xlarge"},
            {"InstanceType": "ml.inf2.xlarge"},
            {"InstanceType": "ml.c7g.2xlarge"},
        ],
        "TrafficPattern": {
            "TrafficType": "PHASES",
            "Phases": [
                {"InitialNumberOfUsers": 1, "SpawnRate": 1, "DurationInSeconds": 300},
                {"InitialNumberOfUsers": 10, "SpawnRate": 2, "DurationInSeconds": 300},
                {"InitialNumberOfUsers": 50, "SpawnRate": 5, "DurationInSeconds": 300},
            ],
        },
    },
)
```

## CLI Commands

### Endpoint Management

```bash
# Create endpoint
aws sagemaker create-endpoint \
    --endpoint-name "my-endpoint" \
    --endpoint-config-name "my-config"

# Describe endpoint
aws sagemaker describe-endpoint \
    --endpoint-name "my-endpoint" \
    --query '{Status: EndpointStatus, Instance: ProductionVariants[0].CurrentInstanceCount}'

# Update endpoint (zero-downtime via rolling update)
aws sagemaker update-endpoint \
    --endpoint-name "my-endpoint" \
    --endpoint-config-name "my-new-config"

# Delete endpoint
aws sagemaker delete-endpoint \
    --endpoint-name "my-endpoint"

# List endpoints
aws sagemaker list-endpoints \
    --sort-by CreationTime \
    --sort-order Descending \
    --max-results 10
```

### Invoke Endpoint

```bash
# Real-time invocation
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name "my-endpoint" \
    --content-type "application/json" \
    --body '{"inputs": "test input"}' \
    output.json

# Check response
cat output.json
```

### Endpoint Metrics

```bash
# Get invocation metrics for the last hour
aws cloudwatch get-metric-statistics \
    --namespace "AWS/SageMaker" \
    --metric-name "Invocations" \
    --dimensions Name=EndpointName,Value=my-endpoint Name=VariantName,Value=AllTraffic \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Sum

# Get model latency p99
aws cloudwatch get-metric-statistics \
    --namespace "AWS/SageMaker" \
    --metric-name "ModelLatency" \
    --dimensions Name=EndpointName,Value=my-endpoint Name=VariantName,Value=AllTraffic \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics p99
```
