#!/usr/bin/env bash
# validate-drawio.sh - PostToolUse hook for validating draw.io XML files
# Receives JSON on stdin with tool_input.file_path
# Outputs JSON with systemMessage field
# After validation passes, generates a draw.io URL for instant browser preview

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Only validate .drawio or .drawio.xml files -- exit early for all other files
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

if [[ ! "$FILE_PATH" =~ \.(drawio|drawio\.xml)$ ]]; then
    exit 0
fi

if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

if [[ -z "${HOME:-}" ]]; then
    echo '{"systemMessage": "HOME is not set, so the isolated draw.io hook runtime cannot be located."}'
    exit 0
fi

# The hook runtime is installed explicitly into a private virtual environment;
# never install plugin dependencies into the user's ambient Python.
if [[ "${OSTYPE:-}" == darwin* ]]; then
    CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/Library/Caches}"
else
    CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}"
fi
HOOK_PYTHON="${CACHE_ROOT}/awslabs/agent-plugins-for-aws/deploy-on-aws/drawio-hook/venv/bin/python"

if [[ ! -x "$HOOK_PYTHON" ]]; then
  echo '{"systemMessage": "The isolated draw.io hook runtime is not installed. Run scripts/setup-drawio-hook-runtime.sh from the deploy-on-aws plugin, as described in its README."}'
  exit 0
fi

exec "$HOOK_PYTHON" "$SCRIPT_DIR/lib/run_drawio_hook.py" "$FILE_PATH"
