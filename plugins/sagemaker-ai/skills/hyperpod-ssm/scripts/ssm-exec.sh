#!/usr/bin/env bash
# Execute SSM command on a HyperPod node using a pre-resolved target
# Usage:
#   Execute:  ./ssm-exec.sh --target TARGET 'command' [--region REGION]
#   Upload:   ./ssm-exec.sh --target TARGET --upload LOCAL_PATH REMOTE_PATH [--region REGION]
#   Read:     ./ssm-exec.sh --target TARGET --read REMOTE_PATH [--region REGION]
#
# Target format: sagemaker-cluster:<CLUSTER_ID>_<GROUP_NAME>-<INSTANCE_ID>
# Build target from parts: use --cluster-id, --group, --instance-id instead of --target
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }

REGION="${AWS_DEFAULT_REGION:-us-west-2}"
TARGET="" ; CLUSTER_ID="" ; GROUP="" ; INSTANCE_ID=""
MODE="exec" ; CMD="" ; LOCAL_PATH="" ; REMOTE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)      TARGET="$2"; shift 2 ;;
    --cluster-id)  CLUSTER_ID="$2"; shift 2 ;;
    --group)       GROUP="$2"; shift 2 ;;
    --instance-id) INSTANCE_ID="$2"; shift 2 ;;
    --upload)      MODE="upload"; LOCAL_PATH="$2"; REMOTE_PATH="$3"; shift 3 ;;
    --read)        MODE="read"; REMOTE_PATH="$2"; shift 2 ;;
    --region)      REGION="$2"; shift 2 ;;
    -*)            echo "Unknown option: $1" >&2; exit 1 ;;
    *)             [[ -n "$CMD" ]] && { echo "Error: Unexpected argument: $1 (command already set)" >&2; exit 1; }
                   CMD="$1"; shift ;;
  esac
done

# Build target from parts if --target not provided
if [[ -z "$TARGET" ]]; then
  [[ -z "$CLUSTER_ID" || -z "$GROUP" || -z "$INSTANCE_ID" ]] && \
    echo "Error: Provide --target or all of --cluster-id, --group, --instance-id" >&2 && exit 1
  TARGET="sagemaker-cluster:${CLUSTER_ID}_${GROUP}-${INSTANCE_ID}"
fi

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/ssm-cmd-XXXXXXXXXX.json")
chmod 600 "$TMPFILE"
trap 'rm -f "$TMPFILE"' EXIT

# Cross-platform base64 encode with no line wrapping (GNU: -w0, macOS: -b0)
# Usage: b64_encode FILE  or  cmd | b64_encode
b64_encode() {
  if base64 --help 2>&1 | grep -q '\-w'; then
    if [[ $# -gt 0 ]]; then base64 -w 0 "$1"; else base64 -w 0; fi
  else
    if [[ $# -gt 0 ]]; then base64 -b 0 -i "$1"; else base64 -b 0; fi
  fi
}

json_cmd() {
  local cmd="$1"
  jq -n --arg c "$cmd" '{"command":[$c]}'
}

safe_quote() {
  # Shell-safe quoting via jq @sh (handles all special characters)
  jq -n --arg s "$1" '$s | @sh' -r
}

case "$MODE" in
  exec)
    [[ -z "$CMD" ]] && echo "Error: No command specified" >&2 && exit 1
    json_cmd "$CMD" > "$TMPFILE"
    ;;
  upload)
    [[ ! -f "$LOCAL_PATH" ]] && echo "Error: Local file not found: $LOCAL_PATH" >&2 && exit 1
    SAFE_REMOTE=$(safe_quote "$REMOTE_PATH")
    ENCODED=$(b64_encode "$LOCAL_PATH")
    # Compress large files to stay within SSM command limits (~64KB)
    if [[ ${#ENCODED} -gt 8000 ]]; then
      ENCODED=$(gzip -c "$LOCAL_PATH" | b64_encode)
      # ENCODED is base64 (only A-Za-z0-9+/=), safe inside single quotes
      json_cmd "echo '${ENCODED}' | base64 -d | gunzip > ${SAFE_REMOTE}" > "$TMPFILE"
    else
      # ENCODED is base64 (only A-Za-z0-9+/=), safe inside single quotes
      json_cmd "echo '${ENCODED}' | base64 -d > ${SAFE_REMOTE}" > "$TMPFILE"
    fi
    ;;
  read)
    SAFE_REMOTE=$(safe_quote "$REMOTE_PATH")
    json_cmd "cat ${SAFE_REMOTE}" > "$TMPFILE"
    ;;
esac

aws ssm start-session \
  --target "$TARGET" \
  --region "$REGION" \
  --document-name AWS-StartNonInteractiveCommand \
  --parameters "file://$TMPFILE"
