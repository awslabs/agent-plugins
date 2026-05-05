# IAM Permissions Required

## Read-only diagnostic

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
    "logs:DescribeLogGroups",
    "logs:DescribeLogStreams",
    "cloudformation:DescribeStackEvents",
    "cloudformation:DescribeStacks",
    "servicequotas:ListServiceQuotas",
    "ssm:StartSession",
    "ssm:TerminateSession"
  ]
}
```

> SSM on HyperPod uses `start-session` against `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets, not `send-command` against plain instance IDs (HyperPod's managed instance fleet does not expose bare instance IDs to customer `SendCommand` calls). Grant `ssm:StartSession` and `ssm:TerminateSession` — not `ssm:SendCommand` / `ssm:GetCommandInvocation`.

For each remediation the operator may run, the matching write permission is required (for example `ec2:AuthorizeSecurityGroupIngress` / `Egress`, `eks:CreateAccessEntry`, `iam:CreateServiceLinkedRole`).
