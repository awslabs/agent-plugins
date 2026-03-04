#!/bin/bash
# Validates SAM templates after editing template.yaml or template.yml.
# Runs as a PostToolUse hook on Edit/Write operations.

set -euo pipefail

# Skip if jq is not installed
if ! command -v jq &> /dev/null; then
  echo '{"systemMessage": "jq not found — SAM template validation skipped. Install jq for automatic validation."}'
  exit 0
fi

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only validate SAM template files
case "$FILE_PATH" in
  *template.yaml|*template.yml) ;;
  *) exit 0 ;;
esac

# Skip if SAM CLI is not installed
if ! command -v sam &> /dev/null; then
  echo '{"systemMessage": "SAM CLI not found — template validation skipped. Install SAM CLI for automatic validation."}'
  exit 0
fi

# Skip if file doesn't exist (deleted)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

OUTPUT=$(sam validate --template "$FILE_PATH" --lint 2>&1) && STATUS=0 || STATUS=$?

if [ $STATUS -eq 0 ]; then
  echo '{"systemMessage": "SAM template validation and linting passed."}'
else
  FORMATTED=$(echo "$OUTPUT" | jq -Rs '{systemMessage: ("SAM template validation/linting failed:\n" + .)}' 2>/dev/null) || \
    FORMATTED="{\"systemMessage\": \"SAM template validation/linting failed:\\n$OUTPUT\"}"
  echo "$FORMATTED"
fi

exit 0
