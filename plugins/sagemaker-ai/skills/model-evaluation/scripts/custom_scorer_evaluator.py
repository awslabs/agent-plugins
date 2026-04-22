
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

from sagemaker.train.evaluate import CustomScorerEvaluator, get_builtin_metrics
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

# Suppress verbose logging from SageMaker SDK
import logging
logging.getLogger('sagemaker').setLevel(logging.WARNING)
logging.getLogger('botocore').setLevel(logging.WARNING)

# Evaluation configuration
MODEL = "[MODEL]" # <Fine-tuned ModelPackage ARN> or <Base Model JumpStart model ID>
DATASET = "[DATASET_S3_URI]"  # S3 URI to your .jsonl dataset
S3_OUTPUT = "[S3_OUTPUT_PATH]"
EVALUATE_BASE = "[EVALUATE_BASE]"
EVALUATOR = "[EVALUATOR]" # "prime_math" or "prime_code" or <custom Evaluator ARN>

# MLflow configuration
MLFLOW_EXPERIMENT_NAME = "[MLFLOW_EXPERIMENT_NAME]"

# ==============================================================================
# Cell 2: Start Evaluation

BuiltInMetric = get_builtin_metrics()

# Resolve evaluator: built-in metric name or custom ARN
if EVALUATOR.startswith("arn:"):
    resolved_evaluator = EVALUATOR
else:
    resolved_evaluator = BuiltInMetric(EVALUATOR)

# If MODEL is a base model ID (not an ARN), override EVALUATE_BASE to False
is_finetuned = MODEL.startswith("arn:")
if not is_finetuned:
    EVALUATE_BASE = False

evaluator = CustomScorerEvaluator(
    model=MODEL,
    evaluator=resolved_evaluator,
    dataset=DATASET,
    s3_output_path=S3_OUTPUT,
    evaluate_base_model=EVALUATE_BASE,
    region=REGION,
    mlflow_experiment_name=MLFLOW_EXPERIMENT_NAME
)

print("✅ Starting custom scorer evaluation...")
print(f"Model: {MODEL}")
print(f"Dataset: {DATASET}")
print(f"Evaluator: {EVALUATOR}")
print(f"Evaluate base model: {EVALUATE_BASE}")

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

execution.show_results()
