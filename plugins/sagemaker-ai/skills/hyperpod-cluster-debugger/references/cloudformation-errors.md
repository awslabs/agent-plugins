# CloudFormation Error Reference

Deep-dive companion to [SKILL.md](../SKILL.md) § H. HyperPod console deployments create nested CloudFormation stacks; the root-cause error is typically in a nested stack's leaf resource.

---

## Navigate to the real failure

1. CloudFormation console → correct region → find the failed HyperPod stack (`CREATE_FAILED` or `ROLLBACK_COMPLETE`)
2. **Events tab** → filter by `CREATE_FAILED` → note the earliest failure
3. **Resources tab** → find `AWS::CloudFormation::Stack` entries with `CREATE_FAILED`
4. Click the Physical ID → opens the nested stack
5. Repeat until you reach a stack with only leaf resources
6. The **Status reason** on the failed leaf resource is the root cause

CLI alternative (per stack — nested stacks need to be iterated):

```bash
aws cloudformation describe-stack-events --stack-name <STACK> --region <REGION> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].{Time:Timestamp,Resource:LogicalResourceId,Type:ResourceType,Reason:ResourceStatusReason}' \
  --output table
```

---

## Resource error catalog

### AWS::SageMaker::Cluster

| Status reason                                      | Root cause                             | Fix                                                                 |
| -------------------------------------------------- | -------------------------------------- | ------------------------------------------------------------------- |
| `Insufficient capacity in the Availability Zone`   | No on-demand instances available in AZ | Different AZ, Flexible Training Plans, or reserved capacity         |
| `No subnets in the capacity AZ`                    | Cluster subnet not in capacity AZ      | Create subnet in the AZ where instances are available               |
| `EFA health checks did not run successfully`       | SG missing self-referencing rules      | Add inbound + outbound self-ref rules (protocol: All, source: self) |
| `Lifecycle scripts did not run successfully`       | Script error, S3 access, or timeout    | Check CloudWatch: `/aws/sagemaker/Clusters/<name>/<id>`             |
| `The security group 'sg-xxx' does not exist`       | Wrong SG ID or different region        | Verify SG exists in same region and VPC                             |
| `The subnet 'subnet-xxx' does not exist`           | Wrong subnet ID or different region    | Verify subnet exists in same region                                 |
| `You are not authorized to perform this operation` | Execution role missing permissions     | Add required SageMaker + VPC permissions to the execution role      |

### AWS::IAM::Role

| Status reason                             | Root cause                                                           | Fix                                                          |
| ----------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------ |
| `Cannot exceed quota for PoliciesPerRole` | Managed-policy-per-role quota reached (default 10; can be increased) | Consolidate into inline policies or request a quota increase |
| `Invalid principal in policy`             | Wrong service in trust policy                                        | Use `"Service": "sagemaker.amazonaws.com"` in trust policy   |
| `MalformedPolicyDocument`                 | JSON syntax error                                                    | Validate JSON; check trailing commas and quotes              |
| `EntityAlreadyExists`                     | Role name already taken                                              | Use unique name or import existing role                      |

### AWS::EC2::VPC / Subnet / SecurityGroup

| Status reason                                        | Root cause                                                       | Fix                                                      |
| ---------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------- |
| `The CIDR 'x.x.x.x/y' conflicts with another subnet` | Overlapping CIDR in same VPC                                     | Use non-overlapping CIDR blocks                          |
| `InvalidGroup.Duplicate`                             | SG rule already exists                                           | Treat as success (template idempotency)                  |
| `RulesPerSecurityGroupLimitExceeded`                 | Per-SG rule quota reached (default 60 per direction; adjustable) | Consolidate with CIDR ranges or request a quota increase |

### AWS::FSx::FileSystem

| Status reason                                   | Root cause                          | Fix                                        |
| ----------------------------------------------- | ----------------------------------- | ------------------------------------------ |
| `The subnet is not in a supported AZ`           | FSx Lustre not available in that AZ | Use a subnet in an AZ that supports Lustre |
| `The security group does not belong to the VPC` | SG and subnet in different VPCs     | Move SG or subnet to same VPC              |

### Custom::Resource / AWS::Lambda::Function

Lambda-backed custom resources fail with the underlying Lambda error. Find the function name in the Resources tab, then:

```bash
aws logs tail /aws/lambda/<FUNCTION_NAME> --region <REGION> --since 1h
```

---

## Rolled-back stacks

When a stack rolls back, CloudFormation deletes what it created. List them:

```bash
aws cloudformation list-stacks \
  --stack-status-filter ROLLBACK_COMPLETE DELETE_COMPLETE \
  --region <REGION> \
  --query 'StackSummaries[?contains(StackName,`HyperPod`) || contains(StackName,`hyperpod`)].{Name:StackName,Status:StackStatus,Time:CreationTime}' \
  --output table
```
