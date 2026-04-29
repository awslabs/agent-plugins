# Cell 1: Setup

%pip install --upgrade sagemaker>=3.7.1 --quiet

# Cell 2: Configuration

import os
import boto3

os.environ["AWS_DEFAULT_REGION"] = "[REGION]"

from sagemaker.core.resources import TrainingJob
from sagemaker.serve.bedrock_model_builder import BedrockModelBuilder
from sagemaker.core import Attribution, set_attribution
from pprint import pprint

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

REGION = "[REGION]"
TRAINING_JOB_NAME = "[TRAINING_JOB_NAME]"
ROLE_ARN = "[ROLE_ARN]"
CUSTOM_MODEL_NAME = "[CUSTOM_MODEL_NAME]"

# Cell 3: Build and Deploy to Bedrock

training_job = TrainingJob.get(training_job_name=TRAINING_JOB_NAME)
print(f"Training job status: {training_job.training_job_status}")

bedrock_builder = BedrockModelBuilder(model=training_job)

deployment_result = bedrock_builder.deploy(
    role_arn=ROLE_ARN,
    custom_model_name=CUSTOM_MODEL_NAME,
)

deployment_arn = deployment_result["customModelDeploymentArn"]
pprint(f"Deployment Result: {deployment_result}")

# Cell 4: Test Inference

bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION)
message = "What is the capital of France?"
print(f"Model Inference Message: {message}")
resp = bedrock_runtime.converse(
    modelId=deployment_arn,
    messages=[{"role": "user", "content": [{"text": message}]}],
    inferenceConfig={"maxTokens": 100, "temperature": 0.7},
)

response_str = resp["output"]["message"]["content"][0]["text"]
print(f"Model Response: {response_str}")
