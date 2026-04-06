#!/usr/bin/env bash
# Get HyperPod cluster ID and metadata
# Usage: ./get-cluster-info.sh CLUSTER_NAME [--region REGION]
# Output: JSON with cluster_id extracted from ARN
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }

CLUSTER="$1"; shift
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ARN=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER" --region "$REGION" \
  --query 'ClusterArn' --output text)
[[ -z "$ARN" || "$ARN" == "None" ]] && { echo "Error: Could not retrieve cluster ARN for '$CLUSTER' (cluster not found or permission denied)" >&2; exit 1; }
CLUSTER_ID=$(echo "$ARN" | cut -d'/' -f2)

jq -n --arg id "$CLUSTER_ID" --arg arn "$ARN" --arg name "$CLUSTER" --arg region "$REGION" \
  '{cluster_id: $id, cluster_arn: $arn, cluster_name: $name, region: $region}'
