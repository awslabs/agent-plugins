# Combined Notebook Scripts
# Each section corresponds to one notebook cell.
# The agent should copy each section into the corresponding cell.

# ==============================================================================
# Cell 1: Configuration

# Set AWS region before importing SageMaker SDK
import os
REGION = "[REGION]"
os.environ['AWS_DEFAULT_REGION'] = REGION

%pip install --upgrade sagemaker>=3.7.1 --quiet

import json
from sagemaker.train.evaluate import LLMAsJudgeEvaluator
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

# Suppress verbose logging from SageMaker SDK
import logging
logging.getLogger('sagemaker').setLevel(logging.WARNING)
logging.getLogger('botocore').setLevel(logging.WARNING)

# Evaluation configuration
MODEL = "[MODEL_ARN]"
DATASET = "[DATASET_S3_URI]"
EVALUATOR_MODEL = "[JUDGE_MODEL]"
BUILTIN_METRICS = [METRICS_LIST]
CUSTOM_METRICS = [CUSTOM_METRICS_JSON]
S3_OUTPUT = "[S3_OUTPUT_PATH]"
EVALUATE_BASE = [TRUE_OR_FALSE]

# MLflow configuration
MLFLOW_EXPERIMENT_NAME = "[MLFLOW_EXPERIMENT_NAME]"

# ==============================================================================
# Cell 2: Start Evaluation

# Build evaluator kwargs
evaluator_kwargs = dict(
    model=MODEL,
    evaluator_model=EVALUATOR_MODEL,
    dataset=DATASET,
    s3_output_path=S3_OUTPUT,
    evaluate_base_model=EVALUATE_BASE,
    region=REGION,
    mlflow_experiment_name=MLFLOW_EXPERIMENT_NAME,
)

if BUILTIN_METRICS:
    evaluator_kwargs["builtin_metrics"] = BUILTIN_METRICS
if CUSTOM_METRICS:
    evaluator_kwargs["custom_metrics"] = json.dumps(CUSTOM_METRICS)

evaluator = LLMAsJudgeEvaluator(**evaluator_kwargs)

print("✅ Starting evaluation...")
print(f"Model: {MODEL}")
print(f"Dataset: {DATASET}")
print(f"Judge: {EVALUATOR_MODEL}")
if BUILTIN_METRICS:
    print(f"Built-in metrics: {BUILTIN_METRICS}")
if CUSTOM_METRICS:
    print(f"Custom metrics: {len(CUSTOM_METRICS)} defined")

execution = evaluator.evaluate()

print(f"\n✅ Evaluation job started!")
print(f"Job ARN: {execution.arn}")
print(f"Job Name: {execution.name}")
print(f"Status: {execution.status.overall_status}")

# ==============================================================================
# Cell 3: Wait for Completion

execution.wait(target_status="Succeeded", poll=60, timeout=7200)

# ==============================================================================
# Cell 4: Show Results

# Display evaluation results
# If evaluate_base_model was True, this shows a comparison between base and custom model
execution.show_results()
