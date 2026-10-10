# Troubleshooting

## TargetNotConnected

```
An error occurred (TargetNotConnected) when calling the StartSession operation
```

Causes:

- Wrong target format — verify underscore between cluster ID and group name, hyphen before instance ID
- Cluster ID is wrong — must be extracted from ARN, not the cluster name
- Node not in `Running` state — check with `list-cluster-nodes`
- SSM agent not running on the node

Verify:

```bash
aws sagemaker list-cluster-nodes --cluster-name CLUSTER --region REGION \
  --query 'ClusterNodeSummaries[?InstanceId==`INSTANCE_ID`].[InstanceGroupName,InstanceStatus.Status]' \
  --output text
```

## AccessDeniedException

Ensure IAM permissions include:

- `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`
- `ssm:StartSession`, `ssm:TerminateSession`

## Command Timeout / Hangs

- Long-running commands without output can cause SSM to hang
- Add periodic output or redirect to file then cat: `bash -c 'cmd > /tmp/out.log 2>&1 && cat /tmp/out.log'`

## Base64 Upload Corruption

- Always use `base64 -w 0` (no line wrapping)
- For large files (>256KB), SSM parameter size limits may apply — split into chunks or use shared filesystem (FSx/EFS) instead

## RunAs User Error

```
Unable to start command: failed to start pty since RunAs user does not exist
```

SSM Run-as-user is configured but user doesn't exist on the node. Use default (root) and `sudo -u USERNAME` explicitly.

## ThrottlingException on StartSession

```
An error occurred (ThrottlingException) when calling the StartSession operation: Rate exceeded
```

Cause: Too many concurrent `start-session` calls. SSM has per-account rate limits.

Fix: Use batched parallel execution with a delay between batches (see "Running Commands Across Many Nodes" in SKILL.md). A batch size of 20 with a 2-second delay between batches works reliably for clusters of 100+ nodes.

## send-command Not Supported

`aws ssm send-command` does not support `sagemaker-cluster:` targets and will return a `ValidationException`. Use `start-session` with `AWS-StartNonInteractiveCommand` instead.
