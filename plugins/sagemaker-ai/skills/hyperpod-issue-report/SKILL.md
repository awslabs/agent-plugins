---
name: hyperpod-issue-report
description: Generate comprehensive issue reports from HyperPod clusters (EKS and Slurm) by collecting diagnostic logs and configurations for troubleshooting and AWS Support cases. Use when users need to collect diagnostics from HyperPod cluster nodes, generate issue reports for AWS Support, investigate node failures or performance problems, document cluster state, or create diagnostic snapshots. Triggers on requests involving issue reports, diagnostic collection, support case preparation, or cluster troubleshooting that requires gathering logs and system information from multiple nodes.
metadata:
  version: "1.0.0"
---

# HyperPod Issue Report

Collect diagnostic logs from HyperPod cluster nodes via SSM, store results in S3. Supports both EKS and Slurm clusters with auto-detection. Uses the bundled `scripts/hyperpod_issue_report.py` for reliable parallel collection.

## Prerequisites

- AWS CLI configured with permissions: `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`, `ssm:StartSession`, `s3:PutObject`, `s3:GetObject`, `eks:DescribeCluster`
- Python 3.8+ and [uv](https://docs.astral.sh/uv/) (see [uv installation docs](https://docs.astral.sh/uv/getting-started/installation/) for install options)
- SSM Agent running on target nodes; node IAM roles need `s3:GetObject`/`s3:PutObject` on the report bucket
- For EKS clusters: kubectl installed and configured (see Workflow step 2)

## Workflow

### 1. Gather Information

Collect from the user:

- **Cluster identifier** (required): accepts cluster name or full cluster ARN (e.g., `arn:aws:sagemaker:us-west-2:123456789012:cluster/abc123`)
- **AWS region** (required unless extractable from ARN)
- **S3 path** for report storage (required, e.g. `s3://bucket/prefix`). If the user doesn't have a bucket, create one (e.g., `s3://hyperpod-diagnostics-<account-id>-<region>`)
- **Issue description** (optional)
- **Target scope**: all nodes, specific instance groups, or specific node IDs (optional)
- **Additional commands** to run on nodes (optional)

### 2. Verify Environment

```bash
aws sts get-caller-identity
aws sagemaker describe-cluster --cluster-name <name-or-arn> --region <region>
```

If the S3 bucket doesn't exist, create it:

```bash
aws s3 mb s3://<bucket-name> --region <region>
```

**For EKS clusters** (check `Orchestrator.Eks` in describe-cluster output):

1. Ensure kubectl is installed (`which kubectl`). If missing, install it for the current platform.
2. Configure kubeconfig using the EKS cluster name from the describe-cluster response:

   ```bash
   aws eks update-kubeconfig --name <eks-cluster-name> --region <region>
   ```

### 3. Run the Collection Script

```bash
uv run scripts/hyperpod_issue_report.py \
  --cluster <cluster-name-or-arn> \
  --region <region> \
  --s3-path s3://<bucket>[/prefix]
```

Use `--help` for all options including `--instance-groups`, `--nodes`, `--command`, `--max-workers`, and `--debug`. Note: `--instance-groups` and `--nodes` are mutually exclusive. Node identifiers accept instance IDs (`i-*`), EKS names (`hyperpod-i-*`), or Slurm names (`ip-*`).

### 4. Present Results

After collection, the script shows statistics and offers interactive download. Report the S3 location and offer to:

- Download the report locally
- Help analyze collected diagnostics (see [references/collection-details.md](references/collection-details.md) for what's in each file)
- Prepare a summary for AWS Support

## Troubleshooting

See [references/troubleshooting.md](references/troubleshooting.md) for error handling, large cluster tuning, and known limitations.
