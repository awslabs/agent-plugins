#!/usr/bin/env bash
# List all HyperPod cluster nodes with instance group info (handles pagination)
# Usage: ./list-nodes.sh CLUSTER_NAME [--region REGION] [--instance-group GROUP] [--instance-id ID]
# Output: JSON array of nodes with InstanceId, InstanceGroupName, InstanceStatus, etc.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }

CLUSTER="$1"; shift
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
FILTER_GROUP="" ; FILTER_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)          REGION="$2"; shift 2 ;;
    --instance-group)  FILTER_GROUP="$2"; shift 2 ;;
    --instance-id)     FILTER_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Paginate to collect ALL nodes
NODES='[]'; NEXT=""
while :; do
  CMD=(aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER" --region "$REGION" --output json)
  [[ -n "$NEXT" ]] && CMD+=(--next-token "$NEXT")
  PAGE=$("${CMD[@]}") || { echo "Error: AWS API call failed" >&2; exit 1; }
  echo "$PAGE" | jq -e '.ClusterNodeSummaries' >/dev/null 2>&1 || { echo "Error: Malformed response from AWS (missing ClusterNodeSummaries)" >&2; exit 1; }
  NODES=$(echo "$NODES" "$PAGE" | jq -s '.[0] + .[1].ClusterNodeSummaries')
  NEXT=$(echo "$PAGE" | jq -r '.NextToken // empty')
  [[ -z "$NEXT" ]] && break
done

# Apply filters
if [[ -n "$FILTER_GROUP" ]]; then
  NODES=$(echo "$NODES" | jq --arg g "$FILTER_GROUP" '[.[] | select(.InstanceGroupName==$g)]')
fi
if [[ -n "$FILTER_ID" ]]; then
  NODES=$(echo "$NODES" | jq --arg id "$FILTER_ID" '[.[] | select(.InstanceId==$id)]')
fi

echo "$NODES"
