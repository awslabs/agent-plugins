#!/usr/bin/env bash
# Amplify prerequisite check script
# Runs deterministic checks so the agent doesn't need to execute them ad-hoc.
# Exit code 0 = all checks passed; non-zero = at least one failed.

set -euo pipefail

PASS=0
FAIL=0
RESULTS=""

check() {
  local label="$1"
  shift
  if output=$("$@" 2>&1); then
    RESULTS="${RESULTS}\n  PASS: ${label} (${output})"
    PASS=$((PASS + 1))
  else
    RESULTS="${RESULTS}\n  FAIL: ${label}"
    FAIL=$((FAIL + 1))
  fi
}

# Node.js >= 18
check "Node.js >= 18" node -e "
  const v = parseInt(process.versions.node.split('.')[0], 10);
  if (v < 18) { process.exit(1); }
  process.stdout.write('v' + process.versions.node);
"

# npm available
check "npm available" npm --version

# AWS CLI installed
check "AWS CLI installed" aws --version

# AWS credentials configured
check "AWS credentials" bash -c 'AWS_PAGER="" aws sts get-caller-identity --query Account --output text'

echo ""
echo "Amplify prerequisite check results:"
echo -e "$RESULTS"
echo ""
echo "Passed: ${PASS}  Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Some prerequisites are missing. Please fix the failures above before proceeding."
  exit 1
fi
