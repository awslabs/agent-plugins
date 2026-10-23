#!/usr/bin/env bash
set -euo pipefail

# Setup script for AWS Lambda Managed Instances (LMI)
# Usage: ./setup-lmi.sh <function-name> <capacity-provider-name> <architecture>
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - VPC subnets and security group created
#   - IAM roles created (see references/infrastructure-setup.md)
#
# Environment variables (required):
#   SUBNET_IDS       - Comma-separated subnet IDs (3+ AZs)
#   SECURITY_GROUP_ID - Security group ID
#   ACCOUNT_ID       - AWS account ID
#   OPERATOR_ROLE_ARN - ARN of the LMI operator role
#   EXECUTION_ROLE_ARN - ARN of the Lambda execution role
#
# Environment variables (optional):
#   AWS_REGION       - AWS region (default: from AWS CLI config)
#   MAX_VCPU_COUNT   - Max vCPU limit (default: 30)
#   MEMORY_SIZE      - Function memory in MB (default: 4096)
#   RUNTIME          - Lambda runtime (default: python3.13)
#   HANDLER          - Function handler (default: app.handler)

FUNCTION_NAME="${1:?Usage: $0 <function-name> <capacity-provider-name> <architecture>}"
CP_NAME="${2:?Usage: $0 <function-name> <capacity-provider-name> <architecture>}"
ARCHITECTURE="${3:-arm64}"

: "${SUBNET_IDS:?Set SUBNET_IDS (comma-separated, 3+ AZs)}"
: "${SECURITY_GROUP_ID:?Set SECURITY_GROUP_ID}"
: "${ACCOUNT_ID:?Set ACCOUNT_ID}"
: "${OPERATOR_ROLE_ARN:?Set OPERATOR_ROLE_ARN}"
: "${EXECUTION_ROLE_ARN:?Set EXECUTION_ROLE_ARN}"

MAX_VCPU_COUNT="${MAX_VCPU_COUNT:-30}"
MEMORY_SIZE="${MEMORY_SIZE:-4096}"
RUNTIME="${RUNTIME:-python3.13}"
HANDLER="${HANDLER:-app.handler}"
REGION="${AWS_REGION:-$(aws configure get region)}"

echo "==> Creating capacity provider: ${CP_NAME}"
aws lambda create-capacity-provider \
  --capacity-provider-name "${CP_NAME}" \
  --vpc-config "SubnetIds=[${SUBNET_IDS}],SecurityGroupIds=[${SECURITY_GROUP_ID}]" \
  --permissions-config "CapacityProviderOperatorRoleArn=${OPERATOR_ROLE_ARN}" \
  --instance-requirements "Architectures=[${ARCHITECTURE}]" \
  --capacity-provider-scaling-config "MaxVCpuCount=${MAX_VCPU_COUNT}"

CP_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:capacity-provider:${CP_NAME}"

echo "==> Creating function: ${FUNCTION_NAME}"
aws lambda create-function \
  --function-name "${FUNCTION_NAME}" \
  --runtime "${RUNTIME}" \
  --handler "${HANDLER}" \
  --zip-file fileb://function.zip \
  --role "${EXECUTION_ROLE_ARN}" \
  --architectures "${ARCHITECTURE}" \
  --memory-size "${MEMORY_SIZE}" \
  --capacity-provider-config \
    "LambdaManagedInstancesCapacityProviderConfig={CapacityProviderArn=${CP_ARN}}"

echo "==> Publishing version (triggers instance provisioning — may take several minutes)"
VERSION=$(aws lambda publish-version --function-name "${FUNCTION_NAME}" --query 'Version' --output text)

echo "==> Done. Function version: ${VERSION}"
echo "    Invoke with: aws lambda invoke --function-name ${FUNCTION_NAME}:${VERSION} --payload '{}' response.json"
echo "    Monitor provisioning: aws lambda get-capacity-provider --capacity-provider-name ${CP_NAME}"
