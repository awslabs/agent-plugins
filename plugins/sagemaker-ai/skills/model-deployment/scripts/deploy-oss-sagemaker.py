# Cell 1: Setup

%pip install --upgrade sagemaker>=3.7.1 --quiet

# Cell 2: Configuration

import os
import json

os.environ["AWS_DEFAULT_REGION"] = "[REGION]"

from sagemaker.core.resources import TrainingJob
from sagemaker.serve import ModelBuilder
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

TRAINING_JOB_NAME = "[TRAINING_JOB_NAME]"
ROLE_ARN = "[ROLE_ARN]"
INSTANCE_TYPE = "[INSTANCE_TYPE]"
ENDPOINT_NAME = "[ENDPOINT_NAME]"
ADAPTER_IC_NAME = f"{ENDPOINT_NAME}-adapter"
ACCEPT_EULA = [ACCEPT_EULA]  # True if user accepted the license in Step 4, False otherwise

# Cell 3: Build Model

training_job = TrainingJob.get(training_job_name=TRAINING_JOB_NAME)
print(f"Training job: {training_job.training_job_name}")
print(f"Model package: {training_job.output_model_package_arn}")

model_builder = ModelBuilder(
    model=training_job,
    role_arn=ROLE_ARN,
    instance_type=INSTANCE_TYPE,
)
model_builder.accept_eula = ACCEPT_EULA
model = model_builder.build(model_name=ENDPOINT_NAME)
print(f"Model: {model.model_arn}")

# Cell 4: Deploy Endpoint

endpoint = model_builder.deploy(
    endpoint_name=ENDPOINT_NAME,
    inference_component_name=ADAPTER_IC_NAME,
)
print(f"Endpoint: {endpoint.endpoint_name}")

# Cell 5: Test Inference

output = endpoint.invoke(
    body=json.dumps({
        "inputs": "What is the capital of France?",
        "parameters": {"max_new_tokens": 50},
    }),
    inference_component_name=ADAPTER_IC_NAME,
)
print(f"Response: {output.body.read()}")
