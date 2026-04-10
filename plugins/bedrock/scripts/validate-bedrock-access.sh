#!/usr/bin/env bash
# Validates AWS credentials, Bedrock access, and model availability.
# Usage: validate-bedrock-access.sh [MODEL_ID] [REGION]

set -euo pipefail

MODEL_ID="${1:-us.anthropic.claude-sonnet-4-6}"
REGION="${2:-us-east-1}"
PROFILE="${3:-}"

# Never read AWS_PROFILE from the environment — it may be set for unrelated purposes.
# Profile must be passed as arg 3 or confirmed via the session lock file.
if [ -z "$PROFILE" ]; then
  echo "[bedrock] No AWS profile specified. Run /bedrock:bedrock-setup to configure Bedrock access."
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=== Bedrock Access Validation ==="
echo "Model:   $MODEL_ID"
echo "Region:  $REGION"
echo "Profile: $PROFILE"
echo ""

ERRORS=0

# Step 1: AWS credentials
echo "--- Step 1: AWS Credentials ---"
if IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" --output json 2>&1); then
    ACCOUNT=$(echo "$IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
    ARN=$(echo "$IDENTITY" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])" 2>/dev/null || echo "unknown")
    pass "AWS credentials valid (Account: $ACCOUNT)"
    pass "Identity: $ARN"
else
    fail "AWS credentials not configured or invalid"
    echo "  Run: aws configure --profile $PROFILE"
    exit 1
fi
echo ""

# Step 2: Bedrock service access
echo "--- Step 2: Bedrock Service Access ---"
if aws bedrock list-foundation-models --profile "$PROFILE" --region "$REGION" --output json >/dev/null 2>&1; then
    pass "Bedrock service accessible in $REGION"
else
    fail "Cannot access Bedrock service in $REGION"
    echo "  Check IAM policy includes bedrock:ListFoundationModels"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Step 3: Model availability
echo "--- Step 3: Model Availability ---"
# Strip cross-region prefix for foundation model lookup
BASE_MODEL_ID="${MODEL_ID#us.}"
BASE_MODEL_ID="${BASE_MODEL_ID#eu.}"
BASE_MODEL_ID="${BASE_MODEL_ID#ap.}"
BASE_MODEL_ID="${BASE_MODEL_ID#global.}"

if MODEL_INFO=$(aws bedrock get-foundation-model --model-identifier "$BASE_MODEL_ID" --profile "$PROFILE" --region "$REGION" --output json 2>&1); then
    MODEL_NAME=$(echo "$MODEL_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['modelDetails']['modelName'])" 2>/dev/null || echo "$BASE_MODEL_ID")
    pass "Model found: $MODEL_NAME ($BASE_MODEL_ID)"
else
    fail "Model $BASE_MODEL_ID not found in $REGION"
    echo "  Check model ID and region. List available models:"
    echo "  aws bedrock list-foundation-models --profile $PROFILE --region $REGION"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Step 4: InvokeModel permission test (dry run via Converse with minimal input)
echo "--- Step 4: Invoke Permission Check ---"
CONVERSE_BODY=$(python3 -c "
import json
print(json.dumps({
    'modelId': '$MODEL_ID',
    'messages': [{'role': 'user', 'content': [{'text': 'Say hello'}]}],
    'inferenceConfig': {'maxTokens': 1}
}))
")

if CONVERSE_RESULT=$(aws bedrock-runtime converse \
    --model-id "$MODEL_ID" \
    --messages '[{"role":"user","content":[{"text":"Say hello"}]}]' \
    --inference-config '{"maxTokens":1}' \
    --profile "$PROFILE" \
    --region "$REGION" \
    --output json 2>&1); then
    pass "InvokeModel/Converse permission confirmed"
else
    if echo "$CONVERSE_RESULT" | grep -q "AccessDeniedException"; then
        fail "Missing bedrock:Converse permission"
        echo "  Add bedrock:Converse and bedrock:InvokeModel to IAM policy"
        ERRORS=$((ERRORS + 1))
    elif echo "$CONVERSE_RESULT" | grep -q "ResourceNotFoundException"; then
        fail "Model not enabled for inference"
        echo "  For Claude: submit the one-time use case form in Bedrock console: https://console.aws.amazon.com/bedrock/"
        echo "  Ensure you're using the cross-region model ID (e.g., us.anthropic.claude-sonnet-4-6)"
        ERRORS=$((ERRORS + 1))
    else
        fail "Converse call failed: $CONVERSE_RESULT"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

# Summary
echo "=== Summary ==="
if [ "$ERRORS" -eq 0 ]; then
    pass "All checks passed. Bedrock is ready to use."
else
    fail "$ERRORS check(s) failed. See details above."
fi

exit "$ERRORS"
