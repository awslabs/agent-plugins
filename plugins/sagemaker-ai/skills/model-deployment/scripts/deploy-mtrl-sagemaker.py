# MTRL → SageMaker Multi-Adapter Endpoint deployment cells.
#
# This file is **cell-sliced source**. The model-deployment skill reads
# it, splits on the `# Cell N:` comment markers, and renders each slice
# into the project notebook. The bracketed tokens
# (e.g., ``[REGION]``, ``[INSTANCE_TYPE]``) are placeholders that the
# agent must replace before writing the notebook. The full placeholder
# list is documented in ``references/deploy-mtrl-sagemaker.md``.
#
# This file is intentionally not directly executable — `[ACCEPT_EULA]`
# is replaced with the literal Python ``True`` / ``False`` based on the
# user's license acceptance in Step 4 before the cell is written.
# Running the file directly with placeholders intact is not supported.

# Cell 1: Setup

%pip install --upgrade 'sagemaker>=3.7.1,<4.0' boto3 --quiet

# Cell 2: Configuration

import os
import json
import boto3

os.environ["AWS_DEFAULT_REGION"] = "[REGION]"

from sagemaker.serve import ModelBuilder
from sagemaker.core.resources import ModelPackage
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

REGION = "[REGION]"
INSTANCE_TYPE = "[INSTANCE_TYPE]"
MODEL_PACKAGE_ARN = "[MODEL_PACKAGE_ARN]"
ROLE_ARN = "[ROLE_ARN]"
ENDPOINT_NAME = "[ENDPOINT_NAME]"
ACCEPT_EULA = [ACCEPT_EULA]  # True if user accepted the license in Step 4, False otherwise

model_package = ModelPackage.get(model_package_arn=MODEL_PACKAGE_ARN)
print(f"Model package: {model_package.model_package_arn}")

# Cell 3: Build Model

model_builder = ModelBuilder(
    model=model_package,
    role_arn=ROLE_ARN,
    instance_type=INSTANCE_TYPE,
)
model_builder.accept_eula = ACCEPT_EULA
model = model_builder.build(model_name=ENDPOINT_NAME)
print(f"Model: {model}")

# Cell 4: Deploy Endpoint

endpoint = model_builder.deploy(
    endpoint_name=ENDPOINT_NAME,
    instance_type=INSTANCE_TYPE,
    initial_instance_count=1,
)
print(f"Endpoint: {endpoint}")

# Cell 5: Test Inference

runtime = boto3.client("sagemaker-runtime", region_name=REGION)
response = runtime.invoke_endpoint(
    EndpointName=ENDPOINT_NAME,
    ContentType="application/json",
    Body=json.dumps({"inputs": "Hello"}),
)
print(f"Response: {response['Body'].read().decode()}")
