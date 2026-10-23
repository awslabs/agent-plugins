# IAM Permissions Required

Read-only diagnostic:

```json
{
  "Action": [
    "sagemaker:DescribeCluster",
    "sagemaker:ListClusterNodes",
    "sagemaker:ListClusterEvents",
    "sagemaker:ListClusters",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeVpcs",
    "ec2:DescribeVpcEndpoints",
    "ec2:DescribeInstances",
    "ec2:DescribeInstanceTypeOfferings",
    "eks:DescribeCluster",
    "eks:ListAccessEntries",
    "eks:ListAddons",
    "eks:DescribeAddon",
    "iam:GetRole",
    "iam:ListAttachedRolePolicies",
    "s3:ListBucket",
    "s3:GetObject",
    "logs:DescribeLogGroups",
    "logs:DescribeLogStreams",
    "logs:GetLogEvents",
    "cloudformation:DescribeStackEvents",
    "cloudformation:DescribeStacks",
    "servicequotas:ListServiceQuotas",
    "ssm:StartSession",
    "ssm:TerminateSession"
  ]
}
```

> SSM on HyperPod uses `start-session` with `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets — not `send-command` against plain instance IDs. Grant `ssm:StartSession` / `ssm:TerminateSession`.

For remediations the operator runs, add the matching write permission (e.g. `ec2:AuthorizeSecurityGroupIngress`, `eks:CreateAccessEntry`).
