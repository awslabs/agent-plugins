#!/usr/bin/env bash
# validate-drawio.sh - PostToolUse hook for validating draw.io XML files
# Receives JSON on stdin with tool_input.file_path
# Outputs JSON with systemMessage field
# After validation passes, generates a draw.io URL for instant browser preview

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure defusedxml is available (required for safe XML parsing)
# See scripts/requirements.txt or plugin README for installation instructions
python3 -c "import defusedxml" 2>/dev/null || {
  echo '{"systemMessage": "Missing required dependency: defusedxml. Install it with: pip3 install defusedxml>=0.7.1"}'
  exit 0
}

# Read stdin (hook input JSON)
INPUT=$(cat)

# Extract file path from the hook input
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    path = data.get('tool_input', {}).get('file_path', '')
    print(path)
except (json.JSONDecodeError, KeyError, TypeError, ValueError):
    print('')
" 2>/dev/null || echo "")

# Only validate .drawio or .drawio.xml files
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

if [[ ! "$FILE_PATH" =~ \.(drawio|drawio\.xml)$ ]]; then
    exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Step 0: Run post-processing fixers BEFORE validation
# This fixes badge overlaps, external actor placement, and legend sizing
# timeout prevents runaway processes from blocking the hook indefinitely
POST_RESULT=$(timeout 10 python3 "$SCRIPT_DIR/lib/post_process_drawio.py" "$FILE_PATH" 2>&1) || true

# Step 1: Run the Python validator on the post-processed file
VALIDATE_RESULT=$(timeout 10 python3 "$SCRIPT_DIR/lib/validate_drawio.py" "$FILE_PATH" 2>&1) || true
VALIDATION_PASSED=false
if echo "$VALIDATE_RESULT" | grep -q "VALIDATION PASSED"; then
    VALIDATION_PASSED=true
fi

# Step 2: Only generate draw.io preview URL AFTER validation passes
URL_RESULT=""
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    URL_RESULT=$(timeout 5 python3 "$SCRIPT_DIR/lib/drawio_url.py" "$FILE_PATH" 2>/dev/null) || true
fi

# Build the response message
FULL_RESULT=""
if [[ -n "$POST_RESULT" ]] && [[ "$POST_RESULT" != *"no changes needed"* ]]; then
    FULL_RESULT="POST-PROCESSING: ${POST_RESULT}
"
fi
FULL_RESULT="${FULL_RESULT}${VALIDATE_RESULT}"
if [[ -n "$URL_RESULT" ]]; then
    FULL_RESULT="${FULL_RESULT}
PREVIEW URL: ${URL_RESULT}"
fi

if [[ -n "$FULL_RESULT" ]]; then
    ESCAPED=$(echo "$FULL_RESULT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null)
    if [[ -z "$ESCAPED" ]]; then
        ESCAPED='"draw.io validation completed but output encoding failed. Run validator manually for details."'
    fi
    echo "{\"systemMessage\": $ESCAPED}"
else
    echo '{"systemMessage": "draw.io XML validation passed. All AWS shapes are valid."}'
fi

exit 0
