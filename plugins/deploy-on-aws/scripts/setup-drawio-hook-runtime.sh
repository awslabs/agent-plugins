#!/usr/bin/env bash
# Install hook dependencies in a private virtual environment, outside ambient
# Python and PATH. This script is intentionally run explicitly by the user.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${HOME:-}" ]]; then
    echo "HOME must be set to install the isolated draw.io hook runtime." >&2
    exit 1
fi

if [[ "${OSTYPE:-}" == darwin* ]]; then
    CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/Library/Caches}"
else
    CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}"
fi

VENV_DIR="${CACHE_ROOT}/awslabs/agent-plugins-for-aws/deploy-on-aws/drawio-hook/venv"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Python 3.9 or newer is required to install the draw.io hook runtime." >&2
    exit 1
fi

umask 077
mkdir -p "$(dirname "$VENV_DIR")"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --disable-pip-version-check --upgrade \
    --requirement "$SCRIPT_DIR/requirements.txt"

printf 'Installed the isolated draw.io hook runtime at: %s\n' "$VENV_DIR"
