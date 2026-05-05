# Cluster Diagnostics — Detailed Procedures

This file contains the full diagnostic and fix procedures for each section referenced
in the main [SKILL.md](../SKILL.md). Jump to a section using the anchors below.

---

## A: EFA Health Checks

**Signals:** `"EFA health checks did not run successfully. Ensure that your VPC and security groups are properly configured before attempting to create a new cluster."`

**Root cause:** Security group is missing a self-referencing rule that allows nodes to communicate with each other via EFA. This is the #1 most common cluster creation failure.

### Diagnose

```bash
# The diagnostic script auto-checks SG rules. You can also run directly:
bash scripts/diagnose-cluster.sh --cluster <CLUSTER> --region <REGION>

# Or check a specific security group:
SG=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'VpcConfig.SecurityGroupIds[0]' --output text)

aws ec2 describe-security-groups --group-ids $SG --region <REGION> \
  --query 'SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json
```

Look for: self-referencing rules where Source/Destination is the security group itself.

### Fix

Add the required rules to **every** security group used by the cluster:

```bash
SG=<security-group-id>
REGION=<region>

# Rule 1 — Inbound self-reference (required for inter-node communication)
aws ec2 authorize-security-group-ingress --group-id $SG --region $REGION \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'

# Rule 2 — Outbound self-reference (required for EFA RDMA traffic)
aws ec2 authorize-security-group-egress --group-id $SG --region $REGION \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'

# Rule 3 — Outbound internet (required for AWS API calls, package downloads)
aws ec2 authorize-security-group-egress --group-id $SG --region $REGION \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
```

After fixing: verify with `describe-security-groups`, ensure all nodes use the same SG, then **retry cluster creation**. See [cluster-operations.md](cluster-operations.md) § 1 for multi-SG clusters and verification details.

---

## B: Capacity & AZ

**Signals:** `"Insufficient capacity"`, `"We currently do not have sufficient capacity in the Availability Zone you requested"`, `"Cannot provision requested instances"`, `"No subnets in the capacity AZ"`.

### Diagnose

```bash
# Check which AZs have the instance type
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=<INSTANCE_TYPE>" \
  --region <REGION> \
  --query 'InstanceTypeOfferings[*].Location' --output table
```

### Fix

1. **Try a different AZ** — add a subnet where the instance type is available
2. **Flexible Training Plans** (recommended for p4d/p5/trn1) — `aws sagemaker search-training-plan-offerings`, then set `TrainingPlanArn` in cluster config
3. **Reserved capacity** — contact AWS account team for large/long-term needs

If using reserved capacity and still failing: verify subnet AZ matches reservation AZ. See [cluster-operations.md](cluster-operations.md) § 2 for the condensed workflow and [capacity-planning.md](capacity-planning.md) for the full strategy guide (On-Demand vs. Flexible Training Plans vs. ODCR, AZ-ID selection, subnet IP sizing per instance type, relevant service quotas).

---

## C: Lifecycle Scripts

**Signals:** `"Lifecycle scripts did not run successfully"`, `"Lifecycle scripts execution timed out"`, cluster creation fails during provisioning.

### Diagnose

```bash
# Get cluster ID for CloudWatch log group
CLUSTER_ARN=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterArn' --output text)
CLUSTER_ID=$(echo "$CLUSTER_ARN" | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/<CLUSTER_NAME>/${CLUSTER_ID}"

# List lifecycle log streams
aws logs describe-log-streams \
  --log-group-name "$LOG_GROUP" \
  --region <REGION> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].logStreamName' \
  --output table

# Read a specific log stream
aws logs get-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "LifecycleConfig/<group-name>/<instance-id>" \
  --region <REGION> \
  --query 'events[*].message' --output text
```

### Common Errors & Fixes

| Log Error                                | Root Cause                     | Fix                                                                                       |
| ---------------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------- |
| `Connect timeout on endpoint URL: s3://` | No S3 access from VPC          | Add S3 Gateway VPC endpoint to subnet route table                                         |
| `AccessDenied` on S3                     | Missing IAM permissions        | Add `s3:GetObject` + `s3:ListBucket` to execution role for the lifecycle script S3 bucket |
| Script never exits / timeout             | Infinite loop or hung command  | Add proper exit codes; test script locally; add `set -e` to fail fast                     |
| `ASCII text, with CRLF line terminators` | Windows line endings           | Convert: `dos2unix script.sh` before uploading to S3                                      |
| `provisioning_parameters.json mismatch`  | Instance group name mismatch   | Match instance group names exactly between lifecycle script and API call                  |
| `command not found`                      | Missing dependency             | Check if required packages are in the AMI; install in script                              |
| `Permission denied`                      | Missing shebang or permissions | Add `#!/bin/bash` as first line; ensure `chmod +x` before S3 upload                       |

Compare scripts with latest upstream versions — see [cluster-operations.md](cluster-operations.md) § 3 for repo links, testing tips, and execution order. For the full S3 layout, `config.py` toggle reference, per-node-type detection flow, and on-node debug procedures (`/var/log/provision/`, `resource_config.json`), see [lifecycle-scripts.md](lifecycle-scripts.md).

---

## D: EKS Access / kubectl

**Signals:** `"couldn't get current server API group list: the server has asked for the client to provide credentials"`, kubectl auth errors, `kubectl get nodes` returns nothing or errors.

**Root cause:** IAM identity not configured in EKS access entries, or kubeconfig not set up.

### Diagnose

```bash
# Step 1: Check your IAM identity
aws sts get-caller-identity

# Step 2: Get EKS cluster name from HyperPod
EKS_ARN=$(aws sagemaker describe-cluster --cluster-name <HYPERPOD_CLUSTER> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo $EKS_ARN | awk -F'/' '{print $NF}')
echo "EKS cluster: $EKS_NAME"

# Step 3: Check existing access entries
aws eks list-access-entries --cluster-name $EKS_NAME --region <REGION>

# Step 4: Check auth mode
aws eks describe-cluster --name $EKS_NAME --region <REGION> \
  --query 'cluster.accessConfig.authenticationMode' --output text
# Must be API or API_AND_CONFIG_MAP — not CONFIG_MAP
```

### Fix

```bash
# Step 1: Add your IAM identity to EKS access entries
MY_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)

# For IAM users:
aws eks create-access-entry \
  --cluster-name $EKS_NAME \
  --region <REGION> \
  --principal-arn $MY_ARN

# Step 2: Associate admin policy (for full cluster access)
aws eks associate-access-policy \
  --cluster-name $EKS_NAME \
  --region <REGION> \
  --principal-arn $MY_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope '{"type": "cluster"}'

# Step 3: Update kubeconfig
aws eks update-kubeconfig --name $EKS_NAME --region <REGION>

# Step 4: Test access
kubectl get nodes
kubectl get pods -A
```

**If auth mode is CONFIG_MAP** (not supported by HyperPod): change to `API_AND_CONFIG_MAP` via `aws eks update-cluster-config --name $EKS_NAME --access-config authenticationMode=API_AND_CONFIG_MAP`. For IAM roles, use the role ARN (not session ARN). See [cluster-operations.md](cluster-operations.md) § 4 for auth mode details.

---

## E: Cluster Provisioning

**Signals:** Cluster shows `InService` but instances are not visible, `kubectl get nodes` returns no nodes, `list-cluster-nodes` shows fewer nodes than expected.

**Root cause:** This is often expected behavior with **Continuous Provisioning mode** (EKS only). In this mode the cluster transitions to InService before all instances are created. Instance creation happens asynchronously and failures are reported via cluster events, not as cluster creation failures.

### Diagnose

```bash
# Step 1: Check cluster status and provisioning mode
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query '{Status:ClusterStatus,Groups:InstanceGroups[*].{Name:InstanceGroupName,Count:CurrentCount,Target:InstanceCount,Status:InstanceGroupStatus}}' \
  --output table

# Step 2: Check cluster events (EKS — primary source of truth)
aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[*].{Time:EventTime,Type:EventType,Message:Message}' \
  --output table

# Step 3: Check individual node status
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName,Status:InstanceStatus.Status}' \
  --output table
```

### Common Scenarios

| Observation                                               | Cause                                     | Action                                               |
| --------------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------- |
| CurrentCount < InstanceCount, events show provisioning    | Continuous provisioning — still creating  | Wait; monitor events                                 |
| Events show `"Insufficient capacity"`                     | No capacity in AZ                         | See **[B: Capacity & AZ](#b-capacity--az)**          |
| Events show lifecycle script failure                      | Script error during instance provisioning | See **[C: Lifecycle Scripts](#c-lifecycle-scripts)** |
| Events show `"EFA health checks"`                         | SG misconfiguration                       | See **[A: EFA Health Checks](#a-efa-health-checks)** |
| No events, no nodes                                       | Cluster may be stuck                      | Check CloudFormation stack; contact Support          |
| Nodes in `list-cluster-nodes` but not `kubectl get nodes` | EKS registration issue                    | Check lifecycle script logs, kubelet status via SSM  |

See [cluster-operations.md](cluster-operations.md) § 5 for Continuous Provisioning details (EKS only).

---

## F: SSM Connectivity

**Signals:** `"Target is not connected"`, SSM session fails to start, cannot access nodes.

### Diagnose

```bash
# Step 1: Verify SSM plugin installed
session-manager-plugin --version

# Step 2: Get the correct target format
# Target format: sagemaker-cluster:<cluster-id>_<instance-group-name>-<instance-id>
# Do NOT use the EC2 instance ID directly!

CLUSTER_INFO=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION>)
CLUSTER_ID=$(echo "$CLUSTER_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin)['ClusterArn'].split('/')[-1])")

aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName,Status:InstanceStatus.Status}' \
  --output table

# Step 3: Construct target and test
TARGET="sagemaker-cluster:${CLUSTER_ID}_<group-name>-<instance-id>"
aws ssm start-session --target "$TARGET" --region <REGION>
```

### Required IAM Permissions for SSM

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "sagemaker:DescribeCluster",
      "sagemaker:ListClusterNodes",
      "ssm:StartSession",
      "ssm:TerminateSession"
    ],
    "Resource": "*"
  }]
}
```

### Common Errors & Fixes

| Error                                   | Root Cause                                             | Fix                                                                                                                                         |
| --------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `SessionManagerPlugin is not found`     | SSM plugin not installed                               | Install: `brew install --cask session-manager-plugin` (macOS) or download from AWS docs (Linux). Verify: `session-manager-plugin --version` |
| `Target is not connected`               | Wrong target format, wrong region, or node not running | Use `sagemaker-cluster:` prefix (CLUSTER_ID is the ARN suffix, not cluster name); verify region; check node is `Running`                    |
| `InvalidTarget` / `ValidationException` | Malformed target string                                | Format must be `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>` exactly                                                               |
| `Access denied`                         | Missing IAM permissions                                | Need `ssm:StartSession`, `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes` — see IAM policy above                                   |
| Connection timeout                      | SSM agent unreachable                                  | Check VPC endpoints (SSM, SSMMessages, EC2Messages) exist in the cluster VPC; verify node is `Running`                                      |

SSM access is **identical for both EKS and Slurm** clusters — same target format, same plugin, same IAM permissions, same VPC endpoints.

For SSH-over-SSM setup, see [cluster-operations.md](cluster-operations.md) § 6.

---

## G: Node Replacement

**Signals:** Auto-replacement not triggering, `batch-replace-cluster-nodes` not working, node stuck in unhealthy state.

### G.1: Auto-Replacement Not Working

```bash
# Step 1: Check if NodeRecovery is enabled per instance group
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'InstanceGroups[*].{Group:InstanceGroupName,Recovery:NodeRecovery}' --output table

# Step 1a: If NodeRecovery=None, enable it with update-cluster. All required fields
# for each instance group must be supplied (InstanceType/Count/LifeCycleConfig/ExecutionRole) —
# derive them from describe-cluster output first.
aws sagemaker update-cluster --cluster-name <CLUSTER> --region <REGION> \
  --instance-groups '[{"InstanceGroupName":"<G>","InstanceType":"ml.p5.48xlarge",
    "InstanceCount":<N>,"ThreadsPerCore":2,
    "LifeCycleConfig":{"SourceS3Uri":"<URI>","OnCreate":"<SCRIPT>"},
    "ExecutionRole":"<ROLE>",
    "OnStartDeepHealthChecks":["InstanceStress","InstanceConnectivity"],
    "NodeRecovery":"Automatic"}]'

# Step 2: Check cluster events for replacement activity (EKS only — cluster events
# are not available for Slurm as of January 2026)
aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[?contains(Message,`replace`) || contains(Message,`reboot`) || contains(Message,`hardware`) || contains(Message,`recovery`)]' \
  --output table

# Step 3: Check health monitoring agent logs. Log-stream name pattern is
# SagemakerHealthMonitoringAgent/<node-group>/<instance-id>, e.g.
# SagemakerHealthMonitoringAgent/group-g5-8x/i-0aa017cbf6c240f3f
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterArn' --output text | cut -d/ -f2)
aws logs describe-log-streams \
  --log-group-name "/aws/sagemaker/Clusters/<CLUSTER>/${CLUSTER_ID}" \
  --region <REGION> \
  --query 'logStreams[?starts_with(logStreamName,`SagemakerHealthMonitoringAgent`)].logStreamName' \
  --output table

# Step 4: Check EKS node health labels. The label VALUES below indicate the action
# the agent has already decided on — if they are missing, the agent hasn't detected
# a resiliency-worthy issue yet.
#   sagemaker.amazonaws.com/node-health-status=UnschedulablePendingReplacement  → marked for replacement
#   sagemaker.amazonaws.com/node-health-status=UnschedulablePendingReboot       → marked for reboot
# Docs: https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-eks-resiliency-node-labels.html
kubectl get nodes --show-labels
kubectl describe node <NODE>

# Step 5: Check Slurm node reason (Slurm)
# Auto-repair triggers ONLY if node reason is exactly "Action:Reboot" or "Action:Replace"
sinfo -o "%N %T %30E"

# Step 6: Check lifecycle-script CW logs (separate log-stream family from HMA).
# If the lifecycle script fails on the new instance, the replacement can't complete
# and auto-recovery stalls. Stream pattern: LifecycleConfig/<node-group>/<instance-id>
aws logs describe-log-streams \
  --log-group-name "/aws/sagemaker/Clusters/<CLUSTER>/${CLUSTER_ID}" \
  --region <REGION> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].logStreamName' \
  --output table
```

**Common blockers:** `NodeRecovery=None` (enable via Step 1a), health agent hasn't detected (wait for next cycle or trigger manually), lifecycle script failing on new instance (see Step 6), no capacity (see [B](#b-capacity--az)), cluster not InService, Slurm reason not `Action:Reboot`/`Action:Replace`. See [cluster-operations.md](cluster-operations.md) § 7 for full decision tree.

**Manual fallback** — if auto-recovery won't trigger and you need to move now, reboot first (less disruptive), replace only if reboot doesn't clear the fault. See [G.2](#g2-manual-replacement-not-working) for the full manual flow.

```bash
aws sagemaker batch-reboot-cluster-nodes  --cluster-name <CLUSTER> --region <REGION> --node-ids '["<INSTANCE_ID>"]'
aws sagemaker batch-replace-cluster-nodes --cluster-name <CLUSTER> --region <REGION> --node-ids '["<INSTANCE_ID>"]'
```

### G.2: Manual Replacement Not Working

```bash
# Step 1: Verify instance ID is correct and belongs to cluster
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName,Status:InstanceStatus.Status}' \
  --output table

# Step 2: Check cluster state (must be InService)
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterStatus' --output text

# Step 3: Reboot first — less disruptive; preserves instance volumes.
aws sagemaker batch-reboot-cluster-nodes \
  --cluster-name <CLUSTER> \
  --region <REGION> \
  --node-ids '["<INSTANCE_ID>"]'

# Step 4: Monitor progress.
aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[0:5].{Time:EventTime,Message:Message}' --output table

# Step 5: ONLY if reboot did not clear the fault, replace the node.
#   IMPORTANT: replacement destroys all instance-local volumes. Back up any
#   state to S3 or FSx before running this.
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <CLUSTER> \
  --region <REGION> \
  --node-ids '["<INSTANCE_ID>"]'
```

If the command succeeds but node stays, check lifecycle script CW logs for the new instance. If capacity error, see [B](#b-capacity--az). Cluster must be `InService`. Use `batch-reboot` / `batch-replace` over legacy methods (Slurm reason / K8s labels); always reboot first.

---

## H: CloudFormation Errors

**Signals:** `"Embedded stack failed"`, CloudFormation stack in `CREATE_FAILED` or `ROLLBACK_COMPLETE`, vague error from management console.

### Navigate to Root Cause

1. Go to **CloudFormation console** -> correct region
2. Find the HyperPod stack (status `CREATE_FAILED` or `ROLLBACK_COMPLETE`)
3. Click **Events** tab -> filter by "Failed" status
4. If the error is `"Embedded stack failed"`, click **Resources** tab
5. Find resources of type `AWS::CloudFormation::Stack` with `CREATE_FAILED`
6. Click the Physical ID -> opens the nested stack
7. Repeat steps 3-6 until you reach a non-stack resource (the actual failure)
8. Read the **Status reason** — this is the actionable error message

### Common Root Cause Resources

| Failed Resource Type          | Common Errors                                                          |
| ----------------------------- | ---------------------------------------------------------------------- |
| `AWS::SageMaker::Cluster`     | Capacity errors, subnet issues, SG problems, lifecycle script failures |
| `AWS::IAM::Role`              | Permission errors, trust relationship issues                           |
| `AWS::IAM::ServiceLinkedRole` | **Service-linked role creation denied** — see below                    |
| `AWS::Lambda::Function`       | Execution errors, timeout                                              |
| `AWS::EC2::VPC`               | CIDR conflicts, quota limits                                           |
| `Custom::Resource`            | Lambda-backed error — check Lambda CloudWatch logs for details         |

**CLI alternative:** Use `aws cloudformation describe-stack-events --stack-name <STACK> --query 'StackEvents[?ResourceStatus==\`CREATE_FAILED\`]'`and drill into nested stacks. Start with the **earliest** failure (later ones are often cascading). For`Custom::Resource`failures, check the Lambda's CloudWatch logs. See [cloudformation-errors.md](cloudformation-errors.md) for the full resource-by-resource error catalog (`AWS::SageMaker::Cluster`,`AWS::IAM::Role`,`AWS::EC2::VPC/Subnet/SecurityGroup`,`AWS::FSx::FileSystem`,`AWS::Lambda::Function`/`Custom::Resource`, stack-hierarchy navigation, CFN template gotchas like`ThreadsPerCore`).

### Service-Linked Role (SLR) failures

SageMaker HyperPod requires the `AWSServiceRoleForAmazonSageMakerHyperPod` service-linked role in the account. In enterprise accounts, SCPs or permission boundaries often block automatic SLR creation.

**Symptoms:**

- CloudFormation `CREATE_FAILED` on an `AWS::IAM::ServiceLinkedRole` resource
- Error message: `"Service role AWSServiceRoleForAmazonSageMakerHyperPod could not be created"`
- Error message: `"User ... is not authorized to perform: iam:CreateServiceLinkedRole"`

**Fix:**

```bash
# Manual creation — requires iam:CreateServiceLinkedRole
aws iam create-service-linked-role --aws-service-name sagemaker.amazonaws.com

# Verify
aws iam get-role --role-name AWSServiceRoleForAmazonSageMakerHyperPod
```

If the caller lacks `iam:CreateServiceLinkedRole` due to an SCP, have an account admin run the command, or request the SCP be adjusted to allow this specific service-linked role.

### IAM Permission Boundary Denials

Enterprise accounts often attach permission boundaries to roles. Even if the role's inline/attached policy grants a permission, the boundary can deny it.

**Symptoms:**

- `"User ... is not authorized to perform: ..."` — but the inline policy clearly grants the action
- Cluster provisioning fails on an IAM action that should succeed
- `DescribeRole` shows `PermissionsBoundary` field is set

**Diagnosis:**

```bash
ROLE_NAME=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'Orchestrator.Eks.ExecutionRoleArn' --output text | awk -F/ '{print $NF}')
aws iam get-role --role-name "$ROLE_NAME" \
  --query 'Role.PermissionsBoundary'
```

If `PermissionsBoundary` is non-null, inspect the attached policy — denied actions here override any grant elsewhere.

### S3 Bucket Access for Lifecycle Scripts

Lifecycle scripts are pulled from S3 at node boot. Common failure modes:

| Symptom                    | Cause                                                   | Fix                                                                              |
| -------------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `AccessDenied` in node log | IAM role lacks `s3:GetObject`                           | Add `s3:GetObject` to IAM role; verify resource ARN matches the lifecycle bucket |
| `KMS AccessDenied`         | Bucket uses KMS encryption and role lacks `kms:Decrypt` | Add `kms:Decrypt` on the bucket's KMS key; ensure key policy allows the role     |
| Timeout, no error          | Private subnet without S3 Gateway endpoint              | Add S3 Gateway VPC endpoint to the cluster's VPC                                 |
| Bucket in different region | Cross-region S3 calls add latency, may time out         | Move lifecycle script to a bucket in the cluster's region                        |
| Cross-account bucket       | Bucket policy doesn't grant the cluster account         | Add `Principal: arn:aws:iam::<cluster-account>:root` to bucket policy            |

### Service Quotas

HyperPod is gated by several quotas beyond the instance type itself:

```bash
REGION=<region>

# HyperPod instance-type quotas
aws service-quotas list-service-quotas --service-code sagemaker --region "$REGION" \
  --query "Quotas[?contains(QuotaName,'HyperPod')].[QuotaName,Value]" --output table

# EFA per-instance quota (if applicable)
aws service-quotas list-service-quotas --service-code ec2 --region "$REGION" \
  --query "Quotas[?contains(QuotaName,'EFA')].[QuotaName,Value]" --output table

# EIP quota (Elastic IP — relevant if you use internet gateways for NAT)
aws service-quotas get-service-quota --service-code ec2 --region "$REGION" \
  --quota-code L-0263D0A3 --query 'Quota.Value' 2>/dev/null

# VPC quotas (VPCs per region, subnets per VPC)
aws service-quotas list-service-quotas --service-code vpc --region "$REGION" \
  --query "Quotas[?Value<\`200\`].[QuotaName,Value]" --output table
```

If a quota is insufficient, file a service quota increase request at least 3 business days before you need the capacity.

### Cluster in FAILED Terminal State

If `ClusterStatus` is `Failed`, the cluster cannot be updated. Options:

1. Collect diagnostics: `bash scripts/diagnose-cluster.sh --cluster <C> --region <R>` + CloudFormation events from Section H above
2. Delete the cluster: `aws sagemaker delete-cluster --cluster-name <C> --region <R>`
3. Fix the root cause (usually IAM/VPC/SG config) based on diagnostics
4. Recreate the cluster

Do not attempt to delete-and-recreate if the cluster has active workloads unless you have migrated them. The delete is destructive.

### Multi-AZ Considerations for EFA

**EFA does not work across AZs.** If your cluster spans multiple AZs, NCCL falls back to TCP for cross-AZ traffic — silently, with ~100x higher latency. For EFA-accelerated training:

- Keep all training instance groups in a single AZ
- Use `describe-instance-type-offerings` to find an AZ with your instance type available
- For multi-AZ, use separate clusters per AZ and use a higher-level orchestrator to coordinate

The diagnose script surfaces AZ count; any cluster spanning >1 AZ for GPU training should be flagged for review.

---

## I: Utilities

### Find Instance ID from Slurm Node Name

Slurm nodes use private IP names (e.g., `ip-10-1-123-45`). Quick lookup:

```bash
# Option 1 — HyperPod APIs (works from anywhere)
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,DNS:PrivateDnsHostname,Group:InstanceGroupName}' \
  --output table

# Option 2 — On head node
IP=$(echo "ip-10-1-123-45" | sed 's/ip-//; s/-/./g')
sudo cat /opt/ml/config/resource_config.json | jq | grep -A 3 "$IP"
```

For large clusters, use `dump_cluster_nodes_info.py` — see [cluster-operations.md](cluster-operations.md) § 8.

---

## J: AMI & Cluster Updates

`UpdateClusterSoftware` fails silently and rolls back, or the cluster gets stuck in `ClusterMaintenanceRollbackFailed`. Common causes: lifecycle scripts incompatible with the new AMI, insufficient capacity for the rolling update, IAM permission gaps.

### Diagnose

```bash
aws sagemaker list-cluster-events --cluster-name <NAME> --region <REGION> \
  --query 'ClusterEventSummaries[?contains(Message, `Update`) || contains(Message, `Rollback`)]'

aws sagemaker describe-cluster --cluster-name <NAME> --region <REGION> \
  --query '{Status:ClusterStatus,FailureMsg:FailureMessage}'
```

Also check per-instance-group lifecycle CloudWatch logs on the nodes that were rolled over:

```bash
aws logs describe-log-streams \
  --log-group-name "/aws/sagemaker/Clusters/<NAME>/<CLUSTER_ID>" \
  --region <REGION>
```

### Remediation decisions

- **Rolls back silently on new AMI:** lifecycle script failed on the new AMI. Fix the script (test on a single instance group first), then retry `UpdateClusterSoftware`.
- **Stuck in `ClusterMaintenanceRollbackFailed`:** non-terminal state that requires AWS Support intervention. Collect the full diagnostic output and escalate. Do not delete and recreate if the cluster has active nodes.
- **Insufficient capacity during rolling update:** pause the update, use Flexible Training Plans / ODCR for the rolling-capacity pool, then retry.
- **Verify rollout strategy:** `RollingUpdatePolicy.MaximumBatchSize` should be small for first-time upgrades so one bad instance group does not trigger a full rollback.

### Blue/green alternative

For large fleets, a blue/green rollout via a second instance group reduces blast radius: create a new instance group on the new AMI, drain the old, validate, delete the old. This side-steps rolling-update rollback entirely.

---

## K: Dangling Nodes & Cleanup

After a failed scale-up or rollback, EKS may show nodes that HyperPod no longer manages. These "dangling" nodes appear in `kubectl get nodes` but not in `list-cluster-nodes`. The inverse — HyperPod-only nodes not registered in EKS — usually indicates kubelet or bootstrap failure on those instances.

### Diagnose

```bash
kubectl get nodes -l sagemaker.amazonaws.com/compute-type=hyperpod -o name | sort > /tmp/eks-nodes.txt
aws sagemaker list-cluster-nodes --cluster-name <NAME> --region <REGION> \
  --query 'ClusterNodeSummaries[*].InstanceId' --output text | tr '\t' '\n' | sort > /tmp/hp-nodes.txt

# EKS-only (dangling):
comm -13 /tmp/eks-nodes.txt /tmp/hp-nodes.txt

# HyperPod-only (orphaned — kubelet never registered):
comm -23 /tmp/hp-nodes.txt /tmp/eks-nodes.txt
```

The diagnostic script runs this comparison automatically and prints the two lists.

### Remediation

- **Dangling EKS node (no matching HyperPod instance):** safe to delete from EKS after verifying the EC2 instance is terminated or no longer part of the cluster:

  ```bash
  # Confirm the instance is not in the HyperPod cluster:
  aws ec2 describe-instances --instance-ids <IID> --region <REGION> \
    --query 'Reservations[0].Instances[0].State.Name'

  # Remove the ghost node from EKS:
  kubectl delete node <NODE_NAME>
  ```

- **Orphaned HyperPod node (not in EKS):** the kubelet did not register. Triage with the `hyperpod-node-debugger` skill — usual causes are IAM role missing on the instance, VPC endpoint missing, or lifecycle script failure.

### Topology labels missing

New nodes may lack `topology.kubernetes.io/zone` if the HyperPod node-labeling controller didn't run. Check the `aws-hyperpod` namespace for health-monitoring-agent pods and their logs:

```bash
kubectl -n aws-hyperpod get pods
kubectl -n aws-hyperpod logs -l app.kubernetes.io/name=health-monitoring-agent --tail=100
```

Labels typically populate on the next reconciliation cycle (a few minutes).

---

## L: Autoscaler Compatibility

Cluster Autoscaler can conflict with HyperPod-managed node groups because HyperPod controls node lifecycle independently. The autoscaler tries to scale down HyperPod nodes it considers underutilized; HyperPod blocks the operation and the autoscaler stalls.

### Fix (Cluster Autoscaler)

Two options — use whichever fits the existing CAS deployment:

1. **Node-level annotation** (prevents CAS from scaling the node down):

   ```bash
   kubectl annotate node <hyperpod-node> \
     cluster-autoscaler.kubernetes.io/scale-down-disabled=true
   ```

   **Important:** `safe-to-evict` is a **pod** annotation, not a node annotation — do not apply it to nodes. On nodes, use `scale-down-disabled`.

2. **CAS deployment config** — ignore HyperPod nodes via the compute-type label:

   ```yaml
   # Cluster Autoscaler deployment args:
   --balancing-ignore-label=sagemaker.amazonaws.com/compute-type
   ```

   Or use `--node-group-auto-discovery` with tag filters that exclude HyperPod ASGs.

### Karpenter

HyperPod nodes are not managed by Karpenter NodePools and should not conflict. If Karpenter attempts to disrupt HyperPod nodes:

- Add `karpenter.sh/do-not-disrupt: "true"` to HyperPod training pods, or
- Configure the NodePool `requirements` to exclude `sagemaker.amazonaws.com/compute-type=hyperpod`.

### Verify

```bash
# CAS should skip HyperPod nodes from now on:
kubectl -n kube-system logs -l app=cluster-autoscaler --tail=200 | grep -iE 'hyperpod|skip|ignore'
```
