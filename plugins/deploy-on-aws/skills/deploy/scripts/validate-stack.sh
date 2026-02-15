#!/bin/bash

# CDK Stack Validation Script for deploy-on-aws
#
# Pre-deployment validation of synthesized CDK stacks.
# Checks synthesis success, template size, resource counts,
# and cdk-nag integration.
#
# Usage: ./scripts/validate-stack.sh [project-root]

set -e

PROJECT_ROOT="${1:-$(pwd)}"

echo "🔍 CDK Stack Validation"
echo "========================"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VALIDATION_PASSED=true

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; VALIDATION_PASSED=false; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
info() { echo "ℹ $1"; }

# Check CDK CLI
if ! command -v cdk &> /dev/null; then
    error "AWS CDK CLI not found. Install with: npm install -g aws-cdk"
    exit 1
fi
success "AWS CDK CLI found ($(cdk --version 2>/dev/null | head -1))"

# Detect language
CDK_LANG="unknown"
if [ -f "${PROJECT_ROOT}/package.json" ]; then
    CDK_LANG="typescript"
    info "Detected TypeScript/JavaScript CDK project"
elif [ -f "${PROJECT_ROOT}/requirements.txt" ] || [ -f "${PROJECT_ROOT}/setup.py" ]; then
    CDK_LANG="python"
    info "Detected Python CDK project"
elif [ -f "${PROJECT_ROOT}/pom.xml" ]; then
    CDK_LANG="java"
    info "Detected Java CDK project"
elif [ -f "${PROJECT_ROOT}/go.mod" ]; then
    CDK_LANG="go"
    info "Detected Go CDK project"
else
    warning "Could not detect CDK project language"
fi

# Run synthesis (uses app command from cdk.json)
echo ""
info "Running CDK synthesis..."
if cdk synth --quiet > /dev/null 2>&1; then
    success "CDK synthesis successful"
else
    error "CDK synthesis failed — run 'cdk synth' for details"
    exit 1
fi

# Check cdk-nag integration
echo ""
info "Checking cdk-nag integration..."
case "$CDK_LANG" in
    typescript)
        if grep -q "cdk-nag" "${PROJECT_ROOT}/package.json" 2>/dev/null; then
            success "cdk-nag found in package.json"
        else
            warning "cdk-nag not found — recommended: npm install --save-dev cdk-nag"
        fi
        ;;
    python)
        if grep -q "cdk-nag" "${PROJECT_ROOT}/requirements.txt" 2>/dev/null; then
            success "cdk-nag found in requirements.txt"
        else
            warning "cdk-nag not found — recommended: pip install cdk-nag"
        fi
        ;;
esac

# Validate synthesized templates
echo ""
info "Checking synthesized templates..."

TEMPLATES=$(find "${PROJECT_ROOT}/cdk.out" -name "*.template.json" 2>/dev/null || echo "")

if [ -z "$TEMPLATES" ]; then
    error "No CloudFormation templates found in cdk.out/"
    exit 1
fi

TEMPLATE_COUNT=$(echo "$TEMPLATES" | wc -l)
success "Found ${TEMPLATE_COUNT} template(s)"

for template in $TEMPLATES; do
    STACK_NAME=$(basename "$template" .template.json)
    TEMPLATE_SIZE=$(wc -c < "$template")

    if [ "$TEMPLATE_SIZE" -gt 51200 ]; then
        warning "${STACK_NAME}: Template ${TEMPLATE_SIZE} bytes (large — consider nested stacks)"
    fi

    if command -v jq &> /dev/null; then
        RESOURCE_COUNT=$(jq '.Resources | length' "$template" 2>/dev/null || echo 0)
        if [ "$RESOURCE_COUNT" -gt 200 ]; then
            warning "${STACK_NAME}: ${RESOURCE_COUNT} resources (consider splitting)"
        else
            success "${STACK_NAME}: ${RESOURCE_COUNT} resources"
        fi
    else
        success "${STACK_NAME}: template OK (${TEMPLATE_SIZE} bytes)"
    fi
done

# Summary
echo ""
echo "========================"
if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "${GREEN}✓ Validation passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation failed${NC}"
    exit 1
fi
