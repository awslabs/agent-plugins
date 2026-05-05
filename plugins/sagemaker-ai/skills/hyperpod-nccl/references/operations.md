# NCCL HyperPod — Operations Reference

Complete operational guide for running the NCCL diagnostic skill on SageMaker HyperPod clusters.
Covers setup, IAM, SSM, CloudWatch, common environments, and decision trees.

---

## 1. Pre-Flight Checklist

Before running `nccl-diagnose.sh`, verify all of these:

```
[ ] aws CLI configured and authenticated
      aws sts get-caller-identity  # must return your account + role

[ ] For EKS: kubectl authenticated to the right cluster
      kubectl get nodes            # must list cluster nodes — not an empty list

[ ] jq installed
      jq --version

[ ] python3 installed
      python3 --version

[ ] (Optional) SSM Session Manager plugin installed — required for hardware checks
      session-manager-plugin --version
      # Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html
```

---

## 2. Getting Cluster Names

**The HyperPod cluster name ≠ EKS cluster name.** You need both for EKS clusters.

```bash
# List all HyperPod clusters in a region:
aws sagemaker list-clusters --region <REGION> \
  --query 'ClusterSummaries[*].[ClusterName,ClusterStatus,CreationTime]' \
  --output table

# Get the EKS cluster name from a HyperPod cluster:
EKS_ARN=$(aws sagemaker describe-cluster \
  --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo $EKS_ARN | awk -F'/' '{print $NF}')
echo "EKS cluster: $EKS_NAME"

# Update kubeconfig:
aws eks update-kubeconfig --name $EKS_NAME --region <REGION>
```

---

## 3. IAM Permissions

### Read-only diagnostic

The diagnostic script never modifies state. It needs only read permissions plus SSM to run commands on compute nodes for hardware checks.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "NCCLSkillReadOnly",
      "Effect": "Allow",
      "Action": [
        "sagemaker:DescribeCluster",
        "sagemaker:ListClusters",
        "sagemaker:ListClusterNodes",
        "sagemaker:ListClusterEvents",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeInstances",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:FilterLogEvents",
        "logs:GetLogEvents",
        "ssm:StartSession",
        "ssm:DescribeSessions",
        "ssm:TerminateSession"
      ],
      "Resource": "*"
    }
  ]
}
```

### Per-remediation permissions (only if the operator applies the suggested fix)

The script prints commands; the operator runs them with whatever role is already authorized. For each class of remediation the script suggests, the caller needs:

| Suggested command                                   | Required action                                |
| --------------------------------------------------- | ---------------------------------------------- |
| `aws ec2 authorize-security-group-{ingress,egress}` | `ec2:AuthorizeSecurityGroupIngress` / `Egress` |
| `aws sagemaker batch-reboot-cluster-nodes`          | `sagemaker:BatchRebootClusterNodes`            |
| `aws sagemaker batch-replace-cluster-nodes`         | `sagemaker:BatchReplaceClusterNodes`           |
| `aws eks update-kubeconfig`                         | `eks:DescribeCluster`                          |
| `kubectl delete/create networkpolicy`               | EKS access entry + RBAC on `networkpolicies`   |

### kubectl RBAC (EKS — read for diagnostic, write only if the operator applies a fix)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nccl-skill-read
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "pods/log", "namespaces", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["daemonsets"]
  verbs: ["get", "list"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list"]
```

If the operator needs to delete/create a NetworkPolicy as part of remediation, grant `delete`/`create` on the `networkpolicies` resource — scope it to the training namespace rather than cluster-wide.

---

## 4. SSM Setup for Node Hardware Checks

SSM allows the skill to run diagnostics directly on compute nodes without SSH.

### Install Session Manager Plugin (local machine)

```bash
# Linux (Amazon Linux / RHEL / CentOS):
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
  -o /tmp/session-manager-plugin.rpm
sudo yum install -y /tmp/session-manager-plugin.rpm

# Ubuntu/Debian:
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o /tmp/session-manager-plugin.deb
sudo dpkg -i /tmp/session-manager-plugin.deb

# macOS:
brew install --cask session-manager-plugin

# Verify:
session-manager-plugin --version
```

### Verify SSM agent on cluster nodes

HyperPod nodes have SSM agent pre-installed. Verify it's running:

```bash
# Test manually:
CLUSTER_ID=$(aws sagemaker describe-cluster \
  --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'ClusterArn' --output text | awk -F'/' '{print $NF}')

INSTANCE_ID=$(aws sagemaker list-cluster-nodes \
  --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'ClusterNodeSummaries[0].InstanceId' --output text)

GROUP=$(aws sagemaker list-cluster-nodes \
  --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'ClusterNodeSummaries[0].InstanceGroupName' --output text)

# SSM target format for HyperPod:
TARGET="sagemaker-cluster:${CLUSTER_ID}_${GROUP}-${INSTANCE_ID}"

aws ssm start-session --target "$TARGET" --region <REGION>
# Should open a shell on the compute node
```

---

## 5. CloudWatch Log Setup

CloudWatch is the fallback when kubectl is unavailable (e.g., running from outside VPC).
Also used for Slurm NCCL log analysis at scale.

### Enable CloudWatch on HyperPod cluster

Add to your lifecycle script (`/opt/ml/scripts/on_create.sh` or lifecycle config):

```bash
# Install CloudWatch agent:
yum install -y amazon-cloudwatch-agent  # Amazon Linux
# or
apt-get install -y amazon-cloudwatch-agent  # Ubuntu

# Configure for NCCL logs:
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nccl.log",
            "log_group_name": "/aws/sagemaker/Clusters/${CLUSTER_NAME}/${CLUSTER_ID}",
            "log_stream_name": "{instance_id}/nccl"
          },
          {
            "file_path": "/var/log/training/*.log",
            "log_group_name": "/aws/sagemaker/Clusters/${CLUSTER_NAME}/${CLUSTER_ID}",
            "log_stream_name": "{instance_id}/training"
          }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
```

### Query CloudWatch manually

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster \
  --cluster-name <NAME> --region <REGION> \
  --query 'ClusterArn' --output text | awk -F'/' '{print $NF}')

LOG_GROUP="/aws/sagemaker/Clusters/<NAME>/${CLUSTER_ID}"
START=$(date -d '2 hours ago' +%s)000  # Linux
# START=$(date -v-2H +%s)000           # macOS

# Search for NCCL errors:
aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --filter-pattern '"NCCL WARN"' \
  --start-time $START \
  --region <REGION> \
  --query 'events[*].[timestamp,logStreamName,message]' \
  --output table
```

---

## 6. Decision Tree: Which Flags to Use

The script is read-only. It never modifies cluster state. For remediation, read the reference section that each `[FAIL]` points to and apply the fix manually with explicit customer approval.

```
User reports NCCL issue
│
├─ "I don't know what's wrong"
│   └─ bash nccl-diagnose.sh --cluster <NAME> --region <REGION>
│
├─ "Training job <JOB> is hanging in namespace <NS>"
│   └─ bash nccl-diagnose.sh --cluster <NAME> --region <REGION> \
│          --namespace <NS> --job <JOB>
│
├─ "It's a Slurm cluster"
│   └─ bash nccl-diagnose.sh --cluster <NAME> --region <REGION> \
│          --orchestrator slurm
│
├─ "One specific node is slow / suspect hardware"
│   └─ bash nccl-diagnose.sh --cluster <NAME> --region <REGION> \
│          --node <INSTANCE-ID> --sample-nodes 1
│
└─ "Large cluster (50+ nodes), check more hardware"
    └─ bash nccl-diagnose.sh --cluster <NAME> --region <REGION> \
           --sample-nodes 10
```

---

## 7. Environment Variable Quick Reference

### Required for all distributed training

| Variable      | Value                        | Purpose                              |
| ------------- | ---------------------------- | ------------------------------------ |
| `MASTER_ADDR` | IP or hostname of rank-0 pod | Rendezvous endpoint                  |
| `MASTER_PORT` | `29500`                      | Rendezvous port (change if conflict) |
| `WORLD_SIZE`  | `pods × GPUs_per_pod`        | Total process count                  |
| `RANK`        | `0` to `WORLD_SIZE-1`        | This process's global rank           |
| `LOCAL_RANK`  | `0` to `GPUs_per_pod-1`      | This process's local rank            |

### For EFA instances (p4d, p5, p3dn)

| Variable                 | Value                                     | Purpose                                       |
| ------------------------ | ----------------------------------------- | --------------------------------------------- |
| `NCCL_SOCKET_IFNAME`     | `^lo,docker,efa,veth,virbr`               | Exclude non-VPC interfaces                    |
| `FI_PROVIDER`            | `efa`                                     | Use EFA libfabric provider                    |
| `FI_EFA_USE_DEVICE_RDMA` | `1`                                       | Enable EFA RDMA (required for full bandwidth) |
| `FI_EFA_FORK_SAFE`       | `1`                                       | Required when using Python multiprocessing    |
| `NCCL_NET_PLUGIN`        | `/opt/amazon/ofi-nccl/lib/libnccl-net.so` | Explicit OFI plugin path                      |
| `NCCL_TIMEOUT`           | `1800` or `$(( nodes*5+600 ))`            | Increase for large clusters                   |

### Performance tuning

| Variable                  | Value     | Purpose                                       |
| ------------------------- | --------- | --------------------------------------------- |
| `NCCL_DEBUG`              | `WARN`    | Production (not INFO/TRACE — 10-80% overhead) |
| `NCCL_BUFFSIZE`           | `8388608` | Larger buffer for 100Gbps+ networks           |
| `NCCL_P2P_LEVEL`          | `NVL`     | Force NVLink P2P (avoids PCIe on multi-GPU)   |
| `TORCH_DISTRIBUTED_DEBUG` | `DETAIL`  | PyTorch detailed distributed debug (dev only) |
| `NCCL_CUMEM_HOST_ENABLE`  | `0`       | Workaround for NUMA cuMem errors              |
| `NCCL_IB_DISABLE`         | `1`       | Force TCP (for non-IB/EFA clusters)           |

### K8s pod spec template (EFA-enabled)

```yaml
env:
- name: MASTER_ADDR
  value: "my-job-svc.my-namespace.svc.cluster.local"
- name: MASTER_PORT
  value: "29500"
- name: WORLD_SIZE
  value: "16"        # 2 nodes × 8 GPUs
- name: NCCL_SOCKET_IFNAME
  value: "^lo,docker,efa,veth,virbr"
- name: FI_PROVIDER
  value: "efa"
- name: FI_EFA_USE_DEVICE_RDMA
  value: "1"
- name: FI_EFA_FORK_SAFE
  value: "1"
- name: NCCL_DEBUG
  value: "WARN"
- name: NCCL_TIMEOUT
  value: "1800"
resources:
  limits:
    nvidia.com/gpu: 8
    vpc.amazonaws.com/efa: 4     # p4d=4, p5=32
  requests:
    nvidia.com/gpu: 8
    vpc.amazonaws.com/efa: 4
volumes:
- name: dshm
  emptyDir:
    medium: Memory
    sizeLimit: "10Gi"
volumeMounts:
- name: dshm
  mountPath: /dev/shm
```

---

## 8. HyperPod Node Health Labels Reference

The skill checks these labels on every K8s node:

| Label                                              | Value                             | Meaning                                                    |
| -------------------------------------------------- | --------------------------------- | ---------------------------------------------------------- |
| `sagemaker.amazonaws.com/node-health-status`       | `Schedulable`                     | Node healthy, accepts pods                                 |
|                                                    | `Unschedulable`                   | Running deep health checks (~2h), temporarily unavailable  |
|                                                    | `UnschedulablePendingReplacement` | Failed health checks — NodeRecovery=Automatic will replace |
|                                                    | `UnschedulablePendingReboot`      | Rebooting to re-run health checks                          |
| `sagemaker.amazonaws.com/deep-health-check-status` | `Passed`                          | Deep health check succeeded                                |
|                                                    | `Failed`                          | Deep health check FAILED — node will be replaced           |
|                                                    | `InProgress`                      | Deep health check running                                  |
| `sagemaker.amazonaws.com/fault-type`               | (any value)                       | Hardware fault type detected                               |
| `sagemaker.amazonaws.com/fault-reason`             | (any value)                       | Hardware fault reason                                      |

**NodeRecovery modes:**

- `Automatic` — HyperPod automatically replaces failed nodes (recommended)
- `None` — failed nodes stay down; manual intervention required

> NodeRecovery is set per instance group and can be toggled via `aws sagemaker update-cluster --instance-groups '[{"InstanceGroupName":"<group>","OnStart…,"ExecutionRole":…,"InstanceCount":…,"InstanceType":…,"LifeCycleConfig":…, "NodeRecovery":"Automatic"}]'`. Note: `update-cluster` replaces the entire instance-group spec — fetch the current spec via `describe-cluster`, edit only the `NodeRecovery` field, and push back.

---

## 9. Slurm-Specific Operations

### Check cluster state

```bash
sinfo -o "%10N %10T %10C %30E" --noheader   # nodes, state, CPUs, reason
squeue -o "%10i %20j %8T %12R %N" --noheader  # jobs, state, reason, nodelist
scontrol show job <JOBID>                       # detailed job info
scontrol show node <NODE>                       # detailed node info
```

### Common Slurm NCCL fixes

```bash
# Resume drained/down node:
scontrol update nodename=<NODE> state=resume

# Drain node for maintenance:
scontrol update nodename=<NODE> state=drain reason="hardware-check"

# Cancel stuck job:
scancel <JOBID>

# Check NCCL-relevant Slurm config:
scontrol show config | grep -E "SlurmdTimeout|KillWait|MessageTimeout|TaskPlugin"
```

### Slurm prolog/epilog for NCCL setup

Add to `/etc/slurm/prolog.sh`:

```bash
#!/bin/bash
# Set NCCL env for all jobs
export NCCL_SOCKET_IFNAME=^lo,docker
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_TIMEOUT=1800
# Ensure /dev/shm is large enough
mount -o remount,size=10G /dev/shm 2>/dev/null || true
```

---

## 10. Troubleshooting the Skill Itself

### kubectl not authenticating

```bash
# Symptom: [FAIL] kubectl NOT authenticated to EKS cluster
# Fix:
aws eks update-kubeconfig --name <EKS-CLUSTER-NAME> --region <REGION>
# Verify: kubectl get nodes
```

### SSM connection fails

```bash
# Symptom: [WARN] SSM connection failed for i-0abc123
# Check 1: SSM plugin installed?
session-manager-plugin --version

# Check 2: Node SSM agent running?
aws ssm describe-instance-information --region <REGION> \
  --filters Key=InstanceIds,Values=<INSTANCE-ID> \
  --query 'InstanceInformationList[0].PingStatus'
# Should return "Online"

# Check 3: IAM allows ssm:StartSession?
aws iam simulate-principal-policy \
  --policy-source-arn <YOUR-ROLE-ARN> \
  --action-names ssm:StartSession \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision'
# Should return "allowed"
```

### AWS API returns empty (cluster not found)

```bash
# Verify cluster exists:
aws sagemaker list-clusters --region <REGION> \
  --query 'ClusterSummaries[*].ClusterName' --output text

# Common mistake: using EKS cluster name instead of HyperPod name
# HyperPod name is the name you gave when calling create-cluster
```

### Cluster status shows UNKNOWN

```bash
# Usually means: IAM lacks sagemaker:DescribeCluster
# Test:
aws sagemaker describe-cluster \
  --cluster-name <NAME> --region <REGION> \
  --query 'ClusterStatus' --output text
# If AccessDenied: add sagemaker:DescribeCluster to IAM policy
```

---

## 11. Remediation Runbooks

The diagnostic script does not print remediation commands — it prints findings with pointers into this section. For each class of issue the script can detect, the subsection below gives the full runbook: root cause, preconditions, exact commands, verification, and blast radius.

### Security Groups

**Detected when:** `[FAIL] SG sg-xxx missing inbound/outbound self-reference` — NCCL inter-node rendezvous or EFA traffic fails.

**Root cause:** EFA requires the instance security group to reference itself with `AllTraffic (-1)` on both inbound and outbound. Without this rule, NCCL packets between nodes are dropped.

**Remediation:**

```bash
# Inbound self-ref (required for NCCL rendezvous):
aws ec2 authorize-security-group-ingress --group-id <SG> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG>"}]}]'

# Outbound self-ref (required for EFA traffic):
aws ec2 authorize-security-group-egress --group-id <SG> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG>"}]}]'
```

The call is idempotent — if the rule already exists, AWS returns `InvalidPermission.Duplicate`; treat that as success.

**Verify:**

```bash
aws ec2 describe-security-groups --group-ids <SG> --region <REGION> \
  --query 'SecurityGroups[0].{In:IpPermissions,Out:IpPermissionsEgress}'
```

Re-run `nccl-diagnose.sh`; the corresponding `[FAIL]` should flip to `[PASS]`.

**Preconditions:** Caller needs `ec2:AuthorizeSecurityGroupIngress` / `Egress`. Schedule during a training pause if possible; rule propagation is seconds but active NCCL rendezvous may already be timing out.

### NetworkPolicy

**Detected when:** `[WARN] NetworkPolicies found in <ns>` together with a `[FAIL]` indicating blocked NCCL traffic.

**Before deleting any NetworkPolicy:** read it — the policy may be intentional tenant isolation or compliance-required. Confirm with the customer.

```bash
# Inspect all NetworkPolicies in the training namespace:
kubectl get networkpolicy -n <NS> -o yaml
```

**Replace with an allow-all intra-namespace policy (only for NCCL training namespaces):**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nccl-intranamespace
  namespace: <NS>
spec:
  podSelector: {}
  policyTypes: ["Ingress", "Egress"]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: <NS>
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: <NS>
    - ports:
        - port: 53
          protocol: UDP
```

Apply with `kubectl apply -f <file>.yaml`. Delete a blocking policy only after the customer confirms it is not load-bearing:

```bash
kubectl delete networkpolicy <NAME> -n <NS>
```

**Verify:** rerun `nccl-diagnose.sh`; the `[WARN] NetworkPolicies found` should go away for the training namespace, and blocked-communication `[FAIL]` signals should clear.

### Slurm Node Management

**Detected when:** `[FAIL] Slurm nodes DOWN/DRAINING: <nodelist>`.

**Never resume a node without first understanding why it went down.** Resuming a node that failed due to hardware error, OOM, or NCCL crash will just repeat the failure.

```bash
# On the controller:
sinfo -R                     # reason for each drained node
scontrol show node <NODE>    # full state
```

If the reason is something transient (e.g. a one-off user job error) and the underlying fault is resolved:

```bash
scontrol update nodename=<NODE> state=resume
```

If the node was drained due to hardware fault, go to [Node Reboot & Replacement](#node-reboot--replacement) first.

**Verify:**

```bash
sinfo -o '%N %T' --noheader | grep <NODE>   # should show idle/alloc/mixed
```

### Node Reboot & Replacement

**Detected when:** `[FAIL]` lines mentioning `SYSTEM_ERROR`, GPU XID errors, or `EFA provider failure`. These indicate a hardware or driver fault on a specific node.

**Start with the least-destructive action.**

1. **Verify the fault is real** (via SSM into the affected instance). HyperPod nodes are only reachable through `start-session` against a `sagemaker-cluster:` target — `ssm send-command` against a bare instance ID will fail with `ValidationException`:

   ```bash
   # Resolve CLUSTER_ID (ARN suffix) and the instance group once:
   CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION> \
     --query 'ClusterArn' --output text | awk -F/ '{print $2}')
   GROUP=$(aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
     --query "ClusterNodeSummaries[?InstanceId=='<IID>'].InstanceGroupName" --output text)

   # Non-interactive remote command via SSM:
   cat > /tmp/fault-check.json <<'EOF'
   {"command":["dmesg | grep -iE 'xid|nvrm' | tail -20; fi_info -p efa 2>&1 | head -20; nvidia-smi -q | grep -A3 'Xid|ECC'"]}
   EOF
   aws ssm start-session \
     --target "sagemaker-cluster:${CLUSTER_ID}_${GROUP}-<IID>" \
     --document-name AWS-StartNonInteractiveCommand \
     --parameters file:///tmp/fault-check.json \
     --region <REGION>
   ```

2. **Reboot first** — reboot clears most transient GPU/EFA faults without destroying data:

   ```bash
   aws sagemaker batch-reboot-cluster-nodes \
     --cluster-name <CLUSTER> --region <REGION> \
     --node-ids '["<IID>"]'
   ```

3. **Replace only if reboot does not clear the fault.** Replacement destroys all instance volumes — back up any state to S3 or FSx first:

   ```bash
   aws sagemaker batch-replace-cluster-nodes \
     --cluster-name <CLUSTER> --region <REGION> \
     --node-ids '["<IID>"]'
   ```

   HyperPod replaces up to 25 node IDs per call.

**Dedup rule:** If multiple pods on the same node reported `SYSTEM_ERROR`, reboot the instance once, not once per pod.

**Verify:**

```bash
# After reboot, wait for node to return to Running:
aws sagemaker describe-cluster-node --cluster-name <CLUSTER> \
  --node-id <IID> --region <REGION> \
  --query 'NodeDetails.InstanceStatus'

# Then rerun the diagnostic — the SYSTEM_ERROR signals should be gone.
```

**Blast radius:** reboot interrupts every workload on that node; replacement destroys instance-local storage. Always get explicit customer approval before running either.
