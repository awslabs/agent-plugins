---
name: hyperpod-ssm
description: Remote command execution and file transfer on SageMaker HyperPod cluster nodes via AWS Systems Manager (SSM). This is the primary interface for accessing HyperPod nodes — direct SSH is not available. Use when any skill, workflow, or user request needs to execute commands on cluster nodes, upload files to nodes, read/download files from nodes, run diagnostics, install packages, or perform any operation requiring shell access to HyperPod instances. Other HyperPod skills depend on this skill for all node-level operations.
metadata:
  version: "1.0.0"
---

# HyperPod SSM Access

## SSM Target Format

Target: `sagemaker-cluster:<CLUSTER_ID>_<GROUP_NAME>-<INSTANCE_ID>`

- `CLUSTER_ID`: Last segment of cluster ARN (NOT the cluster name). Extract via `get-cluster-info.sh`.
- `GROUP_NAME`: Instance group name — retrieve via `list-nodes.sh`.
- `INSTANCE_ID`: EC2 instance ID (e.g., `i-0123456789abcdef0`)

## Scripts

Three scripts under `scripts/`. Resolve cluster info and nodes **once**, then execute per node.

### get-cluster-info.sh — Resolve cluster name → ID (call once)

```bash
scripts/get-cluster-info.sh CLUSTER_NAME [--region REGION]
# Output: {"cluster_id":"...","cluster_arn":"...","cluster_name":"...","region":"..."}
```

### list-nodes.sh — List all nodes with pagination (call once)

```bash
scripts/list-nodes.sh CLUSTER_NAME [--region REGION] [--instance-group GROUP] [--instance-id ID]
# Output: JSON array of ClusterNodeSummaries (InstanceId, InstanceGroupName, InstanceStatus, etc.)
```

`list-cluster-nodes` paginates at 100 nodes. This script handles pagination automatically.

### ssm-exec.sh — Execute command on a node (call per node)

```bash
# Execute — with pre-built target
scripts/ssm-exec.sh --target "sagemaker-cluster:CLUSTERID_GROUP-INSTANCEID" 'command' [--region REGION]

# Execute — with parts
scripts/ssm-exec.sh --cluster-id ID --group GROUP --instance-id INSTANCE_ID 'command' [--region REGION]

# Upload
scripts/ssm-exec.sh --target TARGET --upload LOCAL_PATH REMOTE_PATH [--region REGION]

# Read remote file
scripts/ssm-exec.sh --target TARGET --read REMOTE_PATH [--region REGION]
```

## Running Commands Across Many Nodes

SSM `start-session` rate limit: **3 TPS** per account. Plan batch size and delay accordingly.

`aws ssm send-command` does NOT support `sagemaker-cluster:` targets — only `start-session` works.

## Manual SSM Commands

When the scripts aren't suitable, use `aws ssm start-session` directly with `AWS-StartNonInteractiveCommand`:

```bash
cat > /tmp/cmd.json << 'EOF'
{"command": ["bash -c 'echo hello && whoami'"]}
EOF

aws ssm start-session \
  --target sagemaker-cluster:{CLUSTER_ID}_{GROUP_NAME}-{INSTANCE_ID} \
  --region REGION \
  --document-name AWS-StartNonInteractiveCommand \
  --parameters file:///tmp/cmd.json
```

Always use a JSON file for `--parameters` — inline parameters break with special characters.

## Common Diagnostic Commands

| Task             | Command                                                        |
| ---------------- | -------------------------------------------------------------- |
| Lifecycle logs   | `cat /var/log/provision/provisioning.log`                      |
| Memory           | `free -h`                                                      |
| Disk/mounts      | `df -h && lsblk`                                               |
| GPU status       | `nvidia-smi`                                                   |
| GPU memory       | `nvidia-smi --query-gpu=memory.used,memory.total --format=csv` |
| EFA/network      | `fi_info -p efa`                                               |
| CloudWatch agent | `sudo systemctl status amazon-cloudwatch-agent`                |
| Top processes    | `ps aux --sort=-%mem \| head -20`                              |

## Key Details

- Default SSM non-interactive user is `root`.
- SSM rate limit: **3 TPS** per account.
- For interactive sessions (rare), omit `--document-name` to get a shell.
- Interactive commands (vim, top) are not supported via `AWS-StartNonInteractiveCommand`.
- Large outputs may be truncated by SSM.
- For troubleshooting common errors, see [references/troubleshooting.md](references/troubleshooting.md).
