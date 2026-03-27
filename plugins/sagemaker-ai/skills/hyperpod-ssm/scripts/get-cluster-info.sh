#!/usr/bin/env bash
# Get HyperPod cluster ID and metadata
# Usage: ./get-cluster-info.sh CLUSTER_NAME [--region REGION]
# Output: JSON with cluster_id extracted from ARN
set -euo pipefail

CLUSTER="$1"; shift
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="$2"; shift 2 ;;
    *) shift ;;
  esac
done

ARN=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER" --region "$REGION" \
  --query 'ClusterArn' --output text)
CLUSTER_ID=$(echo "$ARN" | cut -d'/' -f2)

echo "{\"cluster_id\":\"${CLUSTER_ID}\",\"cluster_arn\":\"${ARN}\",\"cluster_name\":\"${CLUSTER}\",\"region\":\"${REGION}\"}"
