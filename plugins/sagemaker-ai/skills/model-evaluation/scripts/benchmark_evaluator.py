
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

from sagemaker.train.evaluate import BenchMarkEvaluator, get_benchmarks
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

# Suppress verbose logging from SageMaker SDK
import logging
logging.getLogger('sagemaker').setLevel(logging.WARNING)
logging.getLogger('botocore').setLevel(logging.WARNING)

# Evaluation configuration
MODEL = "[MODEL]" # <Fine-tuned ModelPackage ARN> or <Base Model JumpStart model ID>
BENCHMARK_TYPE = "[BENCHMARK_TYPE]"  # e.g. mmlu, math, mmlu_pro, bbh, gpqa, strong_reject, ifeval, mmmu
S3_OUTPUT = "[S3_OUTPUT_PATH]"
EVALUATE_BASE = "[EVALUATE_BASE]"

# MLflow configuration (optional - set to None to disable)
MLFLOW_ARN = "[MLFLOW_ARN]"
MLFLOW_EXPERIMENT_NAME = "[MLFLOW_EXPERIMENT_NAME]"
MLFLOW_RUN_NAME = "[MLFLOW_RUN_NAME]"

# ==============================================================================
# Cell 2: Start Evaluation

Benchmark = get_benchmarks()
benchmark_enum = Benchmark(BENCHMARK_TYPE)

# If MODEL is a base model ID (not an ARN), override EVALUATE_BASE to False
is_finetuned = MODEL.startswith("arn:")
if not is_finetuned:
    EVALUATE_BASE = False

mlflow_kwargs = {}
if MLFLOW_ARN is not None and not MLFLOW_ARN.startswith("["):
    mlflow_kwargs["mlflow_resource_arn"] = MLFLOW_ARN
if MLFLOW_EXPERIMENT_NAME is not None and not MLFLOW_EXPERIMENT_NAME.startswith("["):
    mlflow_kwargs["mlflow_experiment_name"] = MLFLOW_EXPERIMENT_NAME
if MLFLOW_RUN_NAME is not None and not MLFLOW_RUN_NAME.startswith("["):
    mlflow_kwargs["mlflow_run_name"] = MLFLOW_RUN_NAME

evaluator = BenchMarkEvaluator(
    model=MODEL,
    benchmark=benchmark_enum,
    s3_output_path=S3_OUTPUT,
    evaluate_base_model=EVALUATE_BASE,
    region=REGION,
    **mlflow_kwargs,
)

print("✅ Starting benchmark evaluation...")
print(f"Model: {MODEL}")
print(f"Benchmark: {BENCHMARK_TYPE}")
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
