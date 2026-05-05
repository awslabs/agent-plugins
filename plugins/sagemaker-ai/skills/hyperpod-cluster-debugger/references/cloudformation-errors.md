# CloudFormation Error Reference for HyperPod Deployments

Deep-dive companion to the main [SKILL.md](../SKILL.md) § H (CloudFormation Errors). When deploying HyperPod via the SageMaker console or CloudFormation templates, failures surface as `CREATE_FAILED` or `ROLLBACK_COMPLETE` at the top-level stack. The actual root cause is usually buried several levels deep in nested stacks.

---

## Navigating Nested Stacks

### Stack Hierarchy (Console Deployments)

Typical HyperPod console deployment creates this stack structure:

```
Top-Level Stack (HyperPod-<name>)
├── NetworkStack (VPC, subnets, IGW, NAT, SG, S3 endpoint)
├── StorageStack (FSx Lustre, optional OpenZFS)
├── IAMStack (execution role, instance profile)
├── S3Stack (lifecycle scripts bucket + upload)
└── ClusterStack (AWS::SageMaker::Cluster resource)
    └── [The cluster resource itself — most failures end here]
```

### Step-by-Step Navigation

1. **CloudFormation Console** → ensure correct region → find the HyperPod stack
2. **Status filter:** look for `CREATE_FAILED` or `ROLLBACK_COMPLETE`
3. **Events tab** → filter by `CREATE_FAILED` → note the earliest failure timestamp
4. **Resources tab** → find `AWS::CloudFormation::Stack` type entries with `CREATE_FAILED`
5. **Click Physical ID** of the failed nested stack
6. **Repeat** until reaching a stack with only leaf resources (no further `AWS::CloudFormation::Stack`)
7. **Read Status Reason** on the failed leaf resource — this is the root cause

### Tip: Find Root Cause via CLI

```bash
# List all failed events across all stacks (requires stack name or ID):
aws cloudformation describe-stack-events \
  --stack-name <TOP_LEVEL_STACK_NAME> \
  --region <REGION> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Time:Timestamp,Resource:LogicalResourceId,Type:ResourceType,Reason:ResourceStatusReason}' \
  --output table

# For nested stacks — get the nested stack's name from Resources tab:
aws cloudformation describe-stack-events \
  --stack-name <NESTED_STACK_ID> \
  --region <REGION> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

---

## Resource Error Catalog

### AWS::SageMaker::Cluster

| Status Reason                                               | Root Cause                                         | Fix                                                                          |
| ----------------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------------------------------- |
| `Insufficient capacity in the Availability Zone`            | No on-demand instances available in AZ             | Add subnet in different AZ; use Flexible Training Plans or reserved capacity |
| `No subnets in the capacity AZ`                             | Cluster subnet not in the AZ where capacity exists | Create subnet in the AZ where instances are available                        |
| `EFA health checks did not run successfully`                | Security group missing self-referencing rules      | Add inbound + outbound self-ref rules on SG (protocol: All, source: self)    |
| `Lifecycle scripts did not run successfully`                | Script error, S3 access, or timeout                | Check CloudWatch logs: `/aws/sagemaker/Clusters/<name>/<id>`                 |
| `Instance bootstrap failed due to network misconfiguration` | VPC routing or SG issue                            | Verify NAT Gateway route, S3 VPC endpoint, SG rules                          |
| `The security group 'sg-xxx' does not exist`                | SG ID is wrong or in different region              | Verify SG exists in the same region and VPC                                  |
| `The subnet 'subnet-xxx' does not exist`                    | Subnet ID is wrong or in different region          | Verify subnet exists in the same region                                      |
| `You are not authorized to perform this operation`          | Execution role missing permissions                 | Add `AmazonSageMakerClusterInstanceRolePolicy` + VPC permissions             |
| `The maximum number of instances ... has been reached`      | Service quota exceeded                             | Request quota increase via Service Quotas console                            |

### AWS::IAM::Role

| Status Reason                             | Root Cause                            | Fix                                                        |
| ----------------------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| `Cannot exceed quota for PoliciesPerRole` | Too many managed policies attached    | Consolidate inline policies; limit is 10 managed per role  |
| `Invalid principal in policy`             | Trust policy references wrong service | Use `"Service": "sagemaker.amazonaws.com"` in trust policy |
| `MalformedPolicyDocument`                 | JSON syntax error in inline policy    | Validate JSON; check for trailing commas, missing quotes   |
| `EntityAlreadyExists`                     | Role name already taken               | Use unique name or import existing role                    |

### AWS::EC2::VPC / Subnet / SecurityGroup

| Status Reason                                        | Root Cause                                | Fix                                                          |
| ---------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------ |
| `The CIDR 'x.x.x.x/y' conflicts with another subnet` | Overlapping CIDR in same VPC              | Use non-overlapping CIDR blocks                              |
| `The maximum number of VPCs has been reached`        | VPC quota per region (default: 5)         | Request VPC quota increase                                   |
| `InvalidGroup.Duplicate`                             | SG rule already exists                    | Skip — not a real error (idempotency issue in template)      |
| `RulesPerSecurityGroupLimitExceeded`                 | More than 60 inbound or 60 outbound rules | Consolidate rules; use CIDR ranges instead of individual IPs |

### AWS::FSx::FileSystem

| Status Reason                                   | Root Cause                              | Fix                                                  |
| ----------------------------------------------- | --------------------------------------- | ---------------------------------------------------- |
| `The subnet is not in a supported AZ`           | FSx Lustre not available in subnet's AZ | Use a subnet in an AZ that supports FSx Lustre       |
| `The security group does not belong to the VPC` | SG and subnet in different VPCs         | Move SG or subnet to same VPC                        |
| `Insufficient storage capacity`                 | FSx Lustre capacity exhausted in AZ     | Try different AZ or reduce storage size              |
| `Invalid deployment type for storage type`      | Template uses incompatible FSx config   | PERSISTENT_2 requires SSD; check template parameters |

### AWS::Lambda::Function (Custom Resources)

| Status Reason                                    | Root Cause                           | Fix                                                       |
| ------------------------------------------------ | ------------------------------------ | --------------------------------------------------------- |
| `<error message from Lambda>` (Custom::Resource) | Lambda-backed custom resource failed | Find the Lambda function name → check its CloudWatch logs |
| `Timed out`                                      | Lambda exceeded 15-minute limit      | Custom resource handler is too slow; check what it does   |

**To debug Custom::Resource failures:**

```bash
# Find Lambda function name from CFN Resources tab, then:
aws logs tail /aws/lambda/<FUNCTION_NAME> --region <REGION> --since 1h
```

---

## Rolled-Back Stacks

When a stack rolls back, CloudFormation deletes the resources it created. To view rolled-back stacks:

1. CloudFormation Console → **Deleted** filter (top-right dropdown)
2. Or via CLI:

   ```bash
   aws cloudformation list-stacks \
     --stack-status-filter ROLLBACK_COMPLETE DELETE_COMPLETE \
     --region <REGION> \
     --query 'StackSummaries[?contains(StackName,`HyperPod`) || contains(StackName,`hyperpod`)].{Name:StackName,Status:StackStatus,Time:CreationTime}' \
     --output table
   ```

---

## CFN Template Gotchas

### ThreadsPerCore

`ThreadsPerCore` defaults to 1 (hyperthreading disabled) when set via console "Advanced Configuration." This makes p5.48xlarge show 96 vCPU instead of 192. Fix: set `ThreadsPerCore: 2` explicitly.

Any `UpdateCluster` call via CFN **must include ThreadsPerCore** even if not originally set — omitting it resets to default.

### S3 Bucket Naming

The `SourceS3Uri` must match pattern `s3://sagemaker-*` per API validation. CFN templates typically create a bucket named `sagemaker-lifecycle-<guid>`.

### Condition-Dependent Resources

If using the reference HyperPod CFN template, some resources are conditional:

- FSx OpenZFS: only created if `CreateOpenZFS=true`
- S3 VPC Endpoint: only created if `CreateS3Endpoint=true`
- SSM Session Document: only if `CreateSSMSessionDocument=true`

A condition evaluating to `false` means the resource is skipped (not failed).
