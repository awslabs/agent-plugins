# MTRL → Bedrock Custom Model Import deployment cells.
#
# This file is **cell-sliced source**. The model-deployment skill reads
# it, splits on the `# Cell N:` comment markers, and renders each slice
# into the project notebook. The bracketed tokens
# (e.g., ``[REGION]``, ``[MODEL_PACKAGE_ARN]``) are placeholders that
# the agent must replace before writing the notebook. The full
# placeholder list is documented in
# ``references/deploy-mtrl-bedrock.md``.
#
# Cell 4 is a **template literal** rather than directly executable
# Python, because ``[DEPLOY_KWARG_NAME]=DEPLOYMENT_NAME`` is not a
# valid keyword-argument expression. The agent replaces
# ``[DEPLOY_KWARG_NAME]`` with the literal kwarg name returned by
# ``scripts/bedrock_deploy_selector.py::select_bedrock_deploy_kwarg``
# (``custom_model_name`` for Nova-family models, ``imported_model_name``
# otherwise) when writing the cell into the notebook. Wrapping the
# template in a triple-quoted string keeps this file syntactically
# valid Python while preserving the placeholder for substitution.

# Cell 1: Setup

%pip install --upgrade 'sagemaker>=3.7.1,<4.0' boto3 --quiet

# Cell 2: Configuration

import boto3
import json
from sagemaker.serve.bedrock_model_builder import BedrockModelBuilder
from sagemaker.core.resources import ModelPackage
from sagemaker.core import Attribution, set_attribution

set_attribution(Attribution.SAGEMAKER_AGENT_PLUGIN)

REGION = "[REGION]"
MODEL_PACKAGE_ARN = "[MODEL_PACKAGE_ARN]"
ROLE_ARN = "[ROLE_ARN]"
DEPLOYMENT_NAME = "[DEPLOYMENT_NAME]"

model_package = ModelPackage.get(model_package_arn=MODEL_PACKAGE_ARN)
print(f"Model package: {model_package.model_package_arn}")

# Cell 3: Build

bedrock_builder = BedrockModelBuilder(model=model_package)
print(f"BedrockModelBuilder: {bedrock_builder}")

# Cell 4: Deploy
#
# Nova models use ``custom_model_name``; non-Nova models use
# ``imported_model_name``. The agent picks the correct kwarg name based
# on the JumpStart model id prefix via
# ``scripts/bedrock_deploy_selector.py::select_bedrock_deploy_kwarg`` and
# replaces ``[DEPLOY_KWARG_NAME]`` below with the literal kwarg name
# before writing the cell into the notebook.
"""
response = bedrock_builder.deploy(
    [DEPLOY_KWARG_NAME]=DEPLOYMENT_NAME,
    role_arn=ROLE_ARN,
    deployment_name=DEPLOYMENT_NAME,
)
print(response)
"""

# Cell 5: Test Inference

bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION)
response = bedrock_runtime.invoke_model(
    modelId=DEPLOYMENT_NAME,
    body=json.dumps({"inputText": "Hello"}),
)
print(f"Response: {response['body'].read().decode()}")
