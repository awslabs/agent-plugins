# Cluster Diagnostics — Detailed Procedures

Full diagnostic and fix procedures for each section referenced from [SKILL.md](../SKILL.md).

---

## A: EFA Health Checks

**Signals:** `"EFA health checks did not run successfully. Ensure that your VPC and security groups are properly configured before attempting to create a new cluster."`

**Root cause:** Security group missing self-referencing rules — a common cluster-creation failure.

### Diagnose

```bash
bash scripts/diagnose-cluster.sh --cluster <CLUSTER> --region <REGION>

# Or directly:
SG=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'VpcConfig.SecurityGroupIds[0]' --output text)
aws ec2 describe-security-groups --group-ids $SG --region <REGION> \
  --query 'SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json
```

Look for self-referencing rules where source/destination is the SG itself.

### Fix — apply to every SG on the cluster

Customer-run. Apply the two self-ref rules to each SG in `describe-cluster → VpcConfig.SecurityGroupIds`, then add **least-privilege egress** for the AWS APIs the node needs to reach. Idempotent: `InvalidPermission.Duplicate` = already exists, treat as success.

```bash
SG=<security-group-id>
REGION=<region>

# Inbound self-ref (inter-node communication, EFA)
aws ec2 authorize-security-group-ingress --group-id $SG --region $REGION \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'

# Outbound self-ref (EFA RDMA)
aws ec2 authorize-security-group-egress --group-id $SG --region $REGION \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'
```

**Egress for AWS APIs.** The node needs HTTPS (443) outbound to reach the AWS services HyperPod uses: S3 (lifecycle scripts), ECR (container images), SageMaker (HyperPod control plane), SSM / SSMMessages / EC2Messages (Session Manager), STS, and CloudWatch Logs. The narrowest practical rule is **TCP 443 to the VPC-endpoint prefix-lists** for those services (`com.amazonaws.<region>.<service>` resolves to a `pl-XXXXXXXX` ID via `aws ec2 describe-prefix-lists`), referenced in `authorize-security-group-egress --ip-permissions` as `PrefixListIds`. See the AWS docs on [VPC endpoint prefix lists](https://docs.aws.amazon.com/vpc/latest/privatelink/vpce-gateway.html#vpc-endpoints-security) for the exact CLI shape. `aws ec2 describe-vpc-endpoints` lists which services the cluster VPC already has endpoints for.

Self-ref opens all ports between instances in this SG (intended for intra-cluster EFA). For multi-SG clusters see [cluster-operations.md § 1](cluster-operations.md#1-efa-security-group-multi-sg-clusters).

---

## B: Capacity & AZ

**Signals:** `"We currently do not have sufficient capacity in the Availability Zone you requested"` (public doc); also seen: subnets not in the AZ where capacity is available.

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=<INSTANCE_TYPE>" \
  --region <REGION> \
  --query 'InstanceTypeOfferings[*].Location' --output table
```

Fix: add subnet in an AZ where the type is available, or use Flexible Training Plans / ODCR. Full strategy: [capacity-planning.md](capacity-planning.md).

---

## C: Lifecycle Scripts

**Signals:** cluster-creation event indicates lifecycle script execution error or timeout; creation fails during provisioning.

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterArn' --output text | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/<CLUSTER_NAME>/${CLUSTER_ID}"

aws logs describe-log-streams --log-group-name "$LOG_GROUP" --region <REGION> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].logStreamName' --output table

aws logs get-log-events --log-group-name "$LOG_GROUP" \
  --log-stream-name "LifecycleConfig/<group-name>/<instance-id>" \
  --region <REGION> --query 'events[*].message' --output text
```

| Log error                                | Fix                                                         |
| ---------------------------------------- | ----------------------------------------------------------- |
| `Connect timeout on endpoint URL: s3://` | Add S3 Gateway VPC endpoint to subnet route table           |
| `AccessDenied` on S3                     | Add `s3:GetObject` + `s3:ListBucket` to execution role      |
| Script never exits / timeout             | Add `set -euo pipefail`; test locally; add network timeouts |
| `ASCII text, with CRLF line terminators` | `dos2unix script.sh` before uploading                       |
| `provisioning_parameters.json` mismatch  | Instance group names must match between config and API call |

Full S3 layout, node-type detection, and on-node debug: [lifecycle-scripts.md](lifecycle-scripts.md).

---

## D: EKS Access / kubectl

**Signals:** `"couldn't get current server API group list: the server has asked for the client to provide credentials"`, `kubectl get nodes` fails or returns nothing.

```bash
# Your identity
aws sts get-caller-identity

# EKS cluster behind the HyperPod cluster
EKS_ARN=$(aws sagemaker describe-cluster --cluster-name <HYPERPOD> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo $EKS_ARN | awk -F'/' '{print $NF}')

# Existing access entries
aws eks list-access-entries --cluster-name $EKS_NAME --region <REGION>

# Auth mode
aws eks describe-cluster --name $EKS_NAME --region <REGION> \
  --query 'cluster.accessConfig.authenticationMode' --output text
```

### Suggested command — grant yourself EKS access (run this yourself)

**Preconditions:** `$MY_ARN` is the IAM **role ARN**, not the assumed-role session ARN. EKS auth mode is `API` or `API_AND_CONFIG_MAP`.

**Command:**

```bash
MY_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)

aws eks create-access-entry \
  --cluster-name $EKS_NAME --region <REGION> --principal-arn $MY_ARN

aws eks associate-access-policy \
  --cluster-name $EKS_NAME --region <REGION> --principal-arn $MY_ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope '{"type": "cluster"}'

aws eks update-kubeconfig --name $EKS_NAME --region <REGION>
kubectl get nodes
```

**Blast radius:** `AmazonEKSClusterAdminPolicy` grants cluster-wide admin on the EKS cluster — use a narrower policy (`AmazonEKSEditPolicy` / `AmazonEKSViewPolicy` + namespace scope) for day-to-day operators. `update-kubeconfig` overwrites the current `kubectl` context.

If the EKS cluster's auth mode is `CONFIG_MAP` only, access entries are not available. Switching auth mode is a cluster-level, administrator-level change — review the EKS access-entries documentation before proceeding and coordinate with anyone who depends on the existing `aws-auth` ConfigMap.

---

## E: Cluster Provisioning

**Signals:** Cluster `InService` but instances not visible, `kubectl get nodes` returns nothing, `list-cluster-nodes` shows fewer nodes than expected.

With **Continuous Provisioning**, the cluster goes `InService` before all instances are created. Instance creation is asynchronous; failures appear as events.

```bash
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query '{Status:ClusterStatus,Groups:InstanceGroups[*].{Name:InstanceGroupName,Count:CurrentCount,Target:InstanceCount,Status:InstanceGroupStatus}}' \
  --output table

aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[*].{Time:EventTime,Type:EventType,Message:Message}' \
  --output table

aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName,Status:InstanceStatus.Status}' \
  --output table
```

| Observation                                               | Cause                               | Action                                |
| --------------------------------------------------------- | ----------------------------------- | ------------------------------------- |
| `CurrentCount < InstanceCount`, events show provisioning  | Continuous provisioning in progress | Wait; monitor events                  |
| Events: `"Insufficient capacity"`                         | No capacity in AZ                   | See **[B](#b-capacity--az)**          |
| Events: lifecycle script failure                          | Script error                        | See **[C](#c-lifecycle-scripts)**     |
| Events: `"EFA health checks"`                             | SG misconfiguration                 | See **[A](#a-efa-health-checks)**     |
| Nodes in `list-cluster-nodes` but not `kubectl get nodes` | EKS registration issue              | Check lifecycle logs, kubelet via SSM |

See [cluster-operations.md § 5](cluster-operations.md#5-continuous-provisioning-eks-only).

---

## F: SSM Connectivity

**Signals:** `"Target is not connected"`, SSM session fails.

> **For interactive shell or repeated SSM access, use the [`hyperpod-ssm`](../../hyperpod-ssm/SKILL.md) skill** — it wraps the cluster-ID derivation, target-format construction, and session start shown below. The block here is for one-off connectivity diagnosis; `hyperpod-ssm` is the right tool for actually working on nodes.

---

## G: Node Replacement

### G.1: Auto-replacement not triggering

Diagnose (read-only):

```bash
# Is NodeRecovery enabled?
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'InstanceGroups[*].{Group:InstanceGroupName,Recovery:NodeRecovery}' --output table

# Replacement activity
aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[?contains(Message,`replace`) || contains(Message,`reboot`) || contains(Message,`hardware`) || contains(Message,`recovery`)]' \
  --output table

# Health-monitoring-agent logs (pattern: SagemakerHealthMonitoringAgent/<group>/<instance>)
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterArn' --output text | cut -d/ -f2)
aws logs describe-log-streams \
  --log-group-name "/aws/sagemaker/Clusters/<CLUSTER>/${CLUSTER_ID}" \
  --region <REGION> \
  --query 'logStreams[?starts_with(logStreamName,`SagemakerHealthMonitoringAgent`)].logStreamName' \
  --output table

# EKS node health labels — the sagemaker.amazonaws.com/node-health-status
# label on each node indicates the action HyperPod has decided on.
kubectl get nodes --show-labels
kubectl describe node <NODE>

sinfo -o "%N %T %30E"
```

**Common blockers:** `NodeRecovery=None`, health agent hasn't detected (wait for next cycle), lifecycle script failing on new instance (same log group, `LifecycleConfig/...` stream), no capacity (see [B](#b-capacity--az)), cluster not `InService`.

### Suggested command — enable NodeRecovery (run this yourself)

> **Destructive — replaces the whole `InstanceGroups` list.** Any group omitted from the payload is deleted; any field drift (instance type, count, lifecycle config) is applied as-is. Re-run `describe-cluster` first and copy every existing field into the payload below before adding `NodeRecovery=Automatic`. If unsure, use the SageMaker console — it preserves existing fields by default. Never run this command yourself; present it to the customer.

**Preconditions:** `NodeRecovery=None` confirmed above. **Derive every field for every instance group from the current `describe-cluster` output** — `update-cluster` replaces the whole `InstanceGroups` list; any field drift is applied as-is.

**Command:**

```bash
aws sagemaker update-cluster --cluster-name <CLUSTER> --region <REGION> \
  --instance-groups '[{"InstanceGroupName":"<G>","InstanceType":"ml.p5.48xlarge",
    "InstanceCount":<N>,
    "LifeCycleConfig":{"SourceS3Uri":"<URI>","OnCreate":"<SCRIPT>"},
    "ExecutionRole":"<ROLE>",
    "OnStartDeepHealthChecks":["InstanceStress","InstanceConnectivity"],
    "NodeRecovery":"Automatic"}]'
```

**Blast radius:** any instance group omitted from the list is deleted; any field drift (instance type, count, lifecycle config) is applied as-is. If unsure, use the console, which preserves existing fields by default.

### G.2: Manual replacement

Diagnose (read-only):

```bash
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName,Status:InstanceStatus.Status}' \
  --output table

aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterStatus' --output text
```

### Suggested command — reboot (run this yourself)

**Preconditions:** `<INSTANCE_ID>` belongs to the cluster (confirmed from `list-cluster-nodes` above); workload can tolerate a restart; on Slurm clusters, rebooting will not disrupt critical cluster operations (per the API doc). `NodeIds` batch size: 1-25 per call.

**Command:**

```bash
aws sagemaker batch-reboot-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --node-ids '["<INSTANCE_ID>"]'

aws sagemaker list-cluster-events --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterEventSummaries[0:5].{Time:EventTime,Message:Message}' --output table
```

**Blast radius:** soft recovery via EC2 `RebootInstances` — preserves instance identity, root volume, and secondary volumes. Training processes on the node are interrupted.

### Suggested command — replace (run this yourself, only if reboot did not clear the fault)

**Preconditions:**

- Reboot attempted first and did not clear the fault.
- Hardware fault confirmed (uncorrectable ECC, GPU-bus errors, EFA hardware failure); not a software / config issue.
- Data on root + secondary volumes is backed up — per the API doc: "Replacing nodes destroys all instance volumes, including both root and secondary volumes. All data stored on these volumes will be permanently lost and cannot be recovered."
- Cluster has been patched via `UpdateClusterSoftware` — per the API doc: "If you want to invoke this API on an existing cluster, you'll first need to patch the cluster by running the UpdateClusterSoftware API."
- Target is **NOT** a Slurm controller — per the API doc: "For SageMaker HyperPod clusters using the Slurm workload manager, you cannot replace instances that are configured as Slurm controller nodes."
- `NodeIds` batch size: 1-25 per call (API limit).

**Command:**

```bash
aws sagemaker batch-replace-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --node-ids '["<INSTANCE_ID>"]'
```

**Blast radius:** destroys root + secondary volumes on the replaced instance (permanent data loss). New hardware is provisioned with the same AMI and instance configuration.

**Karpenter note** (per the HyperPod EKS manual-recovery doc): on Karpenter-managed clusters, `BatchReplaceClusterNodes` terminates the node but does **not** guarantee a replacement — Karpenter only creates a new node if pending pods cannot be rescheduled onto remaining capacity. Per-workload configuration (pod anti-affinity, resource requests) can force a new node.

---

## H: CloudFormation Errors

**Signals:** `"Embedded stack failed"`, `CREATE_FAILED` / `ROLLBACK_COMPLETE`, generic console error.

### Navigate to root cause

1. CloudFormation console → correct region
2. Find the failed HyperPod stack
3. **Events** tab → filter by `CREATE_FAILED` (earliest failure is the real one; later ones are cascades)
4. If error is `"Embedded stack failed"`, open **Resources** → find `AWS::CloudFormation::Stack` with `CREATE_FAILED`
5. Click Physical ID → opens the nested stack
6. Repeat until you reach a non-stack leaf resource
7. The **Status reason** on the leaf is the actionable error

CLI alternative:

```bash
aws cloudformation describe-stack-events --stack-name <STACK> --region <REGION> \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

For Custom::Resource failures, find the Lambda function name and check its logs.

| Failed resource type          | Common errors                                      |
| ----------------------------- | -------------------------------------------------- |
| `AWS::SageMaker::Cluster`     | Capacity, subnet, SG, lifecycle script             |
| `AWS::IAM::Role`              | Permissions, trust relationship                    |
| `AWS::IAM::ServiceLinkedRole` | SLR creation denied — see below                    |
| `AWS::Lambda::Function`       | Execution error, timeout                           |
| `AWS::EC2::VPC`               | CIDR conflict, quota                               |
| `Custom::Resource`            | Lambda-backed error — check Lambda CloudWatch logs |

Full resource-by-resource catalog: [cloudformation-errors.md](cloudformation-errors.md).

### Service-linked role (SLR)

SageMaker HyperPod uses the SLR `AWSServiceRoleForSageMakerHyperPod` (attached to the `AmazonSageMakerHyperPodServiceRolePolicy` managed policy). It is **created automatically** on first cluster creation — you do not need to pre-create it. If cluster creation fails with an SLR error, the cause is almost always an SCP or permission boundary blocking `iam:CreateServiceLinkedRole` for the caller.

```bash
# Verify the SLR exists in the account
aws iam get-role --role-name AWSServiceRoleForSageMakerHyperPod
```

If `iam:CreateServiceLinkedRole` is denied by an SCP, have an account admin either:

- Grant the permission to the caller and retry cluster creation, or
- Request the SCP be adjusted to allow the specific SLR creation.

### Permission boundary denials

Even when a role's inline policy grants a permission, an attached permission boundary can deny it.

```bash
ROLE_NAME=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'Orchestrator.Eks.ExecutionRoleArn' --output text | awk -F/ '{print $NF}')
aws iam get-role --role-name "$ROLE_NAME" --query 'Role.PermissionsBoundary'
```

If `PermissionsBoundary` is non-null, inspect the boundary policy — any denial there overrides all grants.

### Cluster in `Failed` terminal state

`ClusterStatus=Failed` cannot be updated. Options:

1. Collect diagnostics (`diagnose-cluster.sh` + CFN events above)
2. Fix root cause (usually IAM / VPC / SG)
3. `aws sagemaker delete-cluster` and recreate

Deletion is destructive — migrate active workloads first.

### Multi-AZ and EFA

EFA is intra-AZ only. Cross-AZ collectives fall back to TCP. For EFA-accelerated training, keep all training instance groups in a single AZ. `describe-instance-type-offerings` to pick one.

### Service quotas

Check SageMaker HyperPod, EC2 EFA, and VPC quotas before creation — see [capacity-planning.md § service quotas](capacity-planning.md#service-quotas). Quota increases take 1-3 business days.

---

## I: Utilities

### Slurm node name → instance ID

Slurm nodes use IP-named hostnames (`ip-10-1-123-45`). Quick lookup:

```bash
# Works from anywhere
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,DNS:PrivateDnsHostname,Group:InstanceGroupName}' \
  --output table

# On head node
IP=$(echo "ip-10-1-123-45" | sed 's/ip-//; s/-/./g')
sudo cat /opt/ml/config/resource_config.json | jq | grep -A 3 "$IP"
```

For bulk lookups, `list-cluster-nodes` output can be piped to `jq` to produce a CSV of node → instance ID (there are also community scripts in public AWS sample repositories).

---

## J: AMI & Cluster Updates

`UpdateClusterSoftware` fails and rolls back, or the cluster remains in a post-maintenance rollback state. Common causes: lifecycle script incompatible with new AMI, insufficient capacity during rolling update, IAM gaps.

```bash
aws sagemaker list-cluster-events --cluster-name <NAME> --region <REGION> \
  --query 'ClusterEventSummaries[?contains(Message, `Update`) || contains(Message, `Rollback`)]'

aws sagemaker describe-cluster --cluster-name <NAME> --region <REGION> \
  --query '{Status:ClusterStatus,FailureMsg:FailureMessage}'

# Per-instance-group lifecycle logs on the nodes that were rolled over:
aws logs describe-log-streams \
  --log-group-name "/aws/sagemaker/Clusters/<NAME>/<CLUSTER_ID>" \
  --region <REGION>
```

### Decisions

| Symptom                                            | Likely cause                                             | Action                                                                                 |
| -------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Rollback on new AMI                                | Lifecycle script failed on new AMI                       | Fix the script (test on one instance group), retry `UpdateClusterSoftware`             |
| Cluster stays in a post-maintenance rollback state | Cluster-state machine requires service-side intervention | Collect diagnostics and escalate; do not delete and recreate if there are active nodes |
| Insufficient capacity mid-update                   | No rolling-update capacity                               | Pause the update; use Flexible Training Plans / ODCR; retry                            |
| Large-fleet migration                              | Rolling update is high-risk at scale                     | Blue/green: new instance group on the new AMI, drain old, validate, delete old         |

---

## K: Dangling Nodes & Cleanup

After a failed scale-up or rollback, EKS may show nodes that HyperPod no longer manages ("dangling"). The inverse — HyperPod nodes not registered in EKS — usually means kubelet or bootstrap failed.

```bash
kubectl get nodes -l sagemaker.amazonaws.com/compute-type=hyperpod \
  -o jsonpath='{range .items[*]}{.spec.providerID}{"\n"}{end}' \
  | sed 's|.*/||' | sort > /tmp/eks-nodes.txt

aws sagemaker list-cluster-nodes --cluster-name <NAME> --region <REGION> \
  --query 'ClusterNodeSummaries[*].InstanceId' --output text \
  | tr '\t' '\n' | sort > /tmp/hp-nodes.txt

# EKS-only (dangling) — registered in EKS but not in HyperPod
comm -23 /tmp/eks-nodes.txt /tmp/hp-nodes.txt

# HyperPod-only (kubelet never registered) — in HyperPod but not in EKS
comm -13 /tmp/eks-nodes.txt /tmp/hp-nodes.txt
```

### Remediation

### Fix — delete a dangling EKS node

Customer-run. Only delete when the EKS node has no matching HyperPod instance (confirmed by `comm` above) AND the EC2 instance is terminated — confirm with the first command below.

```bash
aws ec2 describe-instances --instance-ids <IID> --region <REGION> \
  --query 'Reservations[0].Instances[0].State.Name'
kubectl delete node <NODE_NAME>
```

If the EC2 instance is still running and registered, kubelet re-registers the node — the delete is a no-op with transient scheduling churn.

**Orphaned HyperPod node (not in EKS):** kubelet never registered. Triage with `hyperpod-node-debugger` — common causes are instance IAM role misconfigured, VPC endpoints missing, or lifecycle script failure.

---

## L: Autoscaler Compatibility

Cluster Autoscaler (CAS) in the same EKS cluster can fail to parse HyperPod node provider IDs, which can break autoscaling for every node group in the cluster — not only HyperPod. Diagnose via CAS logs: look for node-info parse errors tied to HyperPod-managed nodes. If hit, escalate to AWS Support; do not apply untested CAS flags.

Karpenter does not manage HyperPod nodes directly and should not conflict. If Karpenter is attempting to disrupt HyperPod training pods, the standard Karpenter annotation `karpenter.sh/do-not-disrupt: "true"` on the pod prevents disruption (see the Karpenter upstream documentation for current annotation syntax).
