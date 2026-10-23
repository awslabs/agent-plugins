# NCCL Operations Reference

Operational procedures and lookup tables for the NCCL skill.

---

## 1. Getting cluster names

The HyperPod cluster name ≠ the EKS cluster name.

```bash
# List HyperPod clusters:
aws sagemaker list-clusters --region <REGION> \
  --query 'ClusterSummaries[*].[ClusterName,ClusterStatus,CreationTime]' --output table

# EKS cluster behind a HyperPod cluster:
EKS_ARN=$(aws sagemaker describe-cluster \
  --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo $EKS_ARN | awk -F'/' '{print $NF}')

aws eks update-kubeconfig --name $EKS_NAME --region <REGION>
```

---

## 2. IAM

### Read-only diagnostic

```json
{
  "Version": "2012-10-17",
  "Statement": [{
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
  }]
}
```

### Per-remediation permissions

Granted only if the operator applies the suggested fix:

| Suggested command                                   | Required action                                |
| --------------------------------------------------- | ---------------------------------------------- |
| `aws ec2 authorize-security-group-{ingress,egress}` | `ec2:AuthorizeSecurityGroupIngress` / `Egress` |
| `aws sagemaker batch-reboot-cluster-nodes`          | `sagemaker:BatchRebootClusterNodes`            |
| `aws sagemaker batch-replace-cluster-nodes`         | `sagemaker:BatchReplaceClusterNodes`           |
| `aws eks update-kubeconfig`                         | `eks:DescribeCluster`                          |
| `kubectl delete/create networkpolicy`               | EKS access entry + RBAC on `networkpolicies`   |

### kubectl RBAC (EKS read — write only if operator applies a fix)

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

If the operator deletes/creates a NetworkPolicy, grant `delete`/`create` on `networkpolicies` scoped to the training namespace.

---

## 3. SSM target format (HyperPod)

```
sagemaker-cluster:<CLUSTER_ID>_<INSTANCE_GROUP>-<INSTANCE_ID>
```

`CLUSTER_ID` is the ARN suffix — not the cluster name. Full connect procedure is in the node-debugger skill (`references/node-diagnostics-detail.md § K`). `send-command` against a bare instance ID will fail with `ValidationException` — HyperPod's managed fleet requires `start-session` with the prefixed target.

---

## 4. CloudWatch — NCCL log collection

NCCL logs are not collected by HyperPod by default. Add this to the lifecycle script so logs ship to the same log group as lifecycle/health-monitoring logs:

```bash
# Amazon Linux: yum install -y amazon-cloudwatch-agent
# Ubuntu:       apt-get install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {"file_path": "/var/log/nccl.log",
           "log_group_name": "/aws/sagemaker/Clusters/${CLUSTER_NAME}/${CLUSTER_ID}",
           "log_stream_name": "{instance_id}/nccl"},
          {"file_path": "/var/log/training/*.log",
           "log_group_name": "/aws/sagemaker/Clusters/${CLUSTER_NAME}/${CLUSTER_ID}",
           "log_stream_name": "{instance_id}/training"}
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

### Query NCCL errors

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <NAME> --region <R> \
  --query 'ClusterArn' --output text | awk -F'/' '{print $NF}')

aws logs filter-log-events \
  --log-group-name "/aws/sagemaker/Clusters/<NAME>/${CLUSTER_ID}" \
  --filter-pattern '"NCCL WARN"' \
  --start-time $(($(date +%s) - 7200))000 \
  --region <R> \
  --query 'events[*].[timestamp,logStreamName,message]' --output table
```

---

## 5. NCCL environment variable reference

### Required

| Variable      | Value                        | Purpose             |
| ------------- | ---------------------------- | ------------------- |
| `MASTER_ADDR` | IP or hostname of rank-0 pod | Rendezvous endpoint |
| `MASTER_PORT` | `29500`                      | Rendezvous port     |
| `WORLD_SIZE`  | `pods × GPUs_per_pod`        | Total process count |
| `RANK`        | `0` to `WORLD_SIZE-1`        | Global rank         |
| `LOCAL_RANK`  | `0` to `GPUs_per_pod-1`      | Local rank          |

### EFA (p4d / p5 / p3dn)

| Variable                 | Value                                     | Purpose                                |
| ------------------------ | ----------------------------------------- | -------------------------------------- |
| `NCCL_SOCKET_IFNAME`     | `^lo,docker,efa,veth,virbr`               | Exclude non-VPC interfaces             |
| `FI_PROVIDER`            | `efa`                                     | Use EFA libfabric provider             |
| `FI_EFA_USE_DEVICE_RDMA` | `1`                                       | Enable EFA RDMA (required for full bw) |
| `FI_EFA_FORK_SAFE`       | `1`                                       | Required with Python multiprocessing   |
| `NCCL_NET_PLUGIN`        | `/opt/amazon/ofi-nccl/lib/libnccl-net.so` | Explicit OFI plugin path               |

### Collective-op timeout (PyTorch)

`NCCL_TIMEOUT` is **not** a standard NCCL or PyTorch env var — some launchers (DeepSpeed, AWS samples) wrap it, but setting it alone has no effect in pure PyTorch. Control the collective timeout via `init_process_group` and the `TORCH_*` env vars:

```python
# In training code — replaces any NCCL_TIMEOUT env var:
import datetime, torch.distributed as dist
dist.init_process_group("nccl", timeout=datetime.timedelta(seconds=1800))
```

```bash
# Surfaces hangs as Python exceptions instead of silent waits:
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export TORCH_NCCL_BLOCKING_WAIT=1   # debug only — has perf cost at scale
```

### Performance tuning

| Variable                  | Value                 | Purpose                                                                                                                                              |
| ------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NCCL_DEBUG`              | `WARN`                | Production-safe logging. `INFO` / `TRACE` add runtime overhead; enable only for debug                                                                |
| `NCCL_BUFFSIZE`           | bytes (power-of-2)    | Collective-op buffer size. NCCL default is `4194304` (4 MiB). Tune only after baseline measurement, and align to the NCCL user guide recommendations |
| `NCCL_P2P_LEVEL`          | `NVL` / `PIX` / other | `NVL` = P2P only over NVLink; `PIX` = same PCI switch. See the NCCL user guide for the full LOC/NVL/PIX/PXB/PHB/SYS ladder                           |
| `TORCH_DISTRIBUTED_DEBUG` | `DETAIL`              | PyTorch detailed distributed debug (dev only)                                                                                                        |
| `NCCL_CUMEM_HOST_ENABLE`  | `0` / `1`             | Default flipped to `1` in NCCL 2.24 when CUDA driver ≥ 12.6 and runtime ≥ 12.2; set `0` to work around NUMA cuMem issues on older stacks             |
| `NCCL_IB_DISABLE`         | `1`                   | Disable InfiniBand verbs; forces IP-socket transport on non-IB/non-EFA clusters                                                                      |

### EFA network-card counts per instance type

Used to populate `vpc.amazonaws.com/efa` requests in K8s pod specs. The canonical EC2 EFA doc enumerates which types support EFA but doesn't always state the per-instance card count; counts below are taken from authoritative AWS sources where available. Always count with `ls /dev/infiniband/uverbs* | wc -l` on a live node and adjust if your build differs.

| Instance type        | EFA adapters | Aggregate bandwidth |
| -------------------- | ------------ | ------------------- |
| `p4d.24xlarge`       | 4            | 400 Gbps            |
| `p5.48xlarge`        | 32           | 3200 Gbps           |
| `p5e.48xlarge`       | 32           | 3200 Gbps           |
| `p5en.48xlarge`      | 16           | 3200 Gbps           |
| `p6-b200.48xlarge`   | 8            | 3200 Gbps           |
| `p6-b300.48xlarge`   | 17           | 6400 Gbps           |
| `p6e-gb200.36xlarge` | 17           | 1600 Gbps EFA       |

For other types in the EFA-supported list (e.g. `p4de.24xlarge`, `p5.4xlarge`, `trn1.32xlarge`, `trn1n.32xlarge`, `trn2.48xlarge`) — check the current EC2 instance-types doc and confirm with `ls /dev/infiniband/uverbs* | wc -l` on the node before pinning a value.

### K8s pod spec (EFA-enabled)

```yaml
env:
- { name: MASTER_ADDR,            value: "my-job-svc.my-ns.svc.cluster.local" }
- { name: MASTER_PORT,            value: "29500" }
- { name: WORLD_SIZE,             value: "16" }        # 2 nodes × 8 GPUs
- { name: NCCL_SOCKET_IFNAME,     value: "^lo,docker,efa,veth,virbr" }
- { name: FI_PROVIDER,            value: "efa" }
- { name: FI_EFA_USE_DEVICE_RDMA, value: "1" }
- { name: FI_EFA_FORK_SAFE,       value: "1" }
- { name: NCCL_DEBUG,             value: "WARN" }
# Set PyTorch collective timeout via init_process_group(timeout=1800s) in training code
# (NCCL_TIMEOUT env var is a non-standard convention — not read by NCCL or PyTorch directly)
resources:
  limits:
    nvidia.com/gpu: 8
    vpc.amazonaws.com/efa: <N>   # match the EFA-adapter count for the instance type (table above)
  requests:
    nvidia.com/gpu: 8
    vpc.amazonaws.com/efa: <N>
volumes:
- { name: dshm, emptyDir: { medium: Memory, sizeLimit: "10Gi" } }
volumeMounts:
- { name: dshm, mountPath: /dev/shm }
```

---

## 6. HyperPod node health labels (EKS)

| Label                                              | Value                              | Meaning                                                                            |
| -------------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------------- |
| `sagemaker.amazonaws.com/node-health-status`       | `Schedulable`                      | Healthy, accepts pods                                                              |
|                                                    | `Unschedulable`                    | Node is running deep health checks (~2 h stress test); not available for workloads |
|                                                    | `UnschedulablePendingReplacement`  | Failed health check — will be replaced                                             |
|                                                    | `UnschedulablePendingReboot`       | Rebooting to re-run checks                                                         |
| `sagemaker.amazonaws.com/deep-health-check-status` | `Passed` / `Failed` / `InProgress` | Deep-health-check outcome                                                          |
| `sagemaker.amazonaws.com/fault-types`              | (value)                            | High-level fault category (plural label key)                                       |
| `sagemaker.amazonaws.com/fault-reasons`            | (value)                            | Detailed fault reason (plural label key)                                           |

HMA also writes a `sagemaker.amazonaws.com/fault-details` annotation on the node with the full JSON (`timestamp`, `type`, `reason`, `message`) — see the node-debugger skill § F.

**NodeRecovery modes** (per instance group): `Automatic` (replace failed nodes) or `None` (manual). Toggle via `update-cluster` — fetch the current instance-group spec first (`describe-cluster`), edit only `NodeRecovery`, push back.

---

## 7. Slurm — NCCL-specific operations

Diagnose (read-only):

```bash
sinfo -o "%10N %10T %10C %30E" --noheader
squeue -o "%10i %20j %8T %12R %N" --noheader
scontrol show node <NODE> | grep Reason
```

### Suggested command — resume a DRAINING node (run this yourself)

**Preconditions:** the original drain reason no longer applies (the underlying issue — straggler bandwidth, hardware fault, RemoveIPC, etc. — has been investigated and resolved); the customer accepts that pending jobs may schedule onto this node immediately; you are running on the Slurm controller via SSM.

**Command:**

```bash
scontrol update nodename=<NODE> state=resume
```

**Blast radius:** node returns to the idle pool. Reversible by setting `state=drain` again. If the original cause is unfixed, the node will likely re-fail; resume only after a clean diagnostic.

### Suggested command — disable RemoveIPC for NCCL persistence (run this yourself)

**Preconditions:** NCCL job is terminating with "unlink shared memory" or `/dev/shm/nccl-*` disappearing mid-training; confirmed that `RemoveIPC=yes` is set in `/etc/systemd/logind.conf`; node is quiescent or a brief `systemd-logind` restart is acceptable.

**Command:**

```bash
grep RemoveIPC /etc/systemd/logind.conf   # diagnose
echo "RemoveIPC=no" >> /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
```

**Blast radius:** persistent change to the node's systemd configuration — logs out anyone in a systemd user session during the restart. Change survives reboot. For new nodes, add the same commands to the lifecycle script so the setting persists across replacements.

### Slurm prolog for NCCL env

```bash
#!/bin/bash
# /etc/slurm/prolog.sh
export NCCL_SOCKET_IFNAME=^lo,docker
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
# Collective timeout is set in training code: init_process_group(timeout=timedelta(seconds=1800))
mount -o remount,size=10G /dev/shm 2>/dev/null || true
```

---

## 8. NCCL-specific remediations

### Security group self-reference

**Detected when:** `[FAIL] SG sg-xxx missing inbound/outbound self-reference` — NCCL rendezvous or EFA RDMA blocked.

**Root cause:** EFA requires the SG to reference itself with `AllTraffic (-1)` on both ingress and egress. Without this, NCCL packets between nodes are dropped.

### Suggested command — apply self-ref to every cluster SG (run this yourself)

**Preconditions:** the rule check (e.g. `nccl-diagnose.sh` Check 4 or `hyperpod-node-debugger`'s `check-efa-sg.sh`) reports `[FAIL]` on inbound or outbound self-ref for `<SG>`; `<SG>` is one of the security groups attached to the HyperPod cluster (`describe-cluster → VpcConfig.SecurityGroupIds`); apply once **per SG** if multiple are attached; for IaC-managed SGs, see the operating-policy IaC note before running directly. Per the HyperPod prerequisites doc, do **not** add a `0.0.0.0/0` outbound rule on the EFA SG.

**Command:**

```bash
# Inbound self-ref (NCCL rendezvous)
aws ec2 authorize-security-group-ingress --group-id <SG> --region <R> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG>"}]}]'

# Outbound self-ref (EFA RDMA)
aws ec2 authorize-security-group-egress --group-id <SG> --region <R> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG>"}]}]'
```

**Blast radius:** opens all protocols between instances that share this SG (intended scope for intra-cluster EFA / NCCL). Idempotent: `InvalidPermission.Duplicate` = the rule already exists. Reversible with `revoke-security-group-ingress`/`revoke-security-group-egress` using the same `--ip-permissions` payload.

### NetworkPolicy blocking NCCL

**Detected when:** `[WARN] NetworkPolicies found in <ns>` + a `[FAIL]` indicating blocked inter-pod NCCL traffic.

**Before deleting any NetworkPolicy, read it** — it may be intentional tenant isolation or compliance-required. Confirm with the customer.

```bash
kubectl get networkpolicy -n <NS> -o yaml
```

Allow-all intra-namespace policy for NCCL training namespaces:

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
            matchLabels: { kubernetes.io/metadata.name: <NS> }
  egress:
    - to:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: <NS> }
    - ports:
        - { port: 53, protocol: UDP }
```

### Suggested command — delete a blocking NetworkPolicy (run this yourself)

**Preconditions:** the policy has been read (`kubectl get networkpolicy <NAME> -n <NS> -o yaml`) and confirmed not to be intentional tenant isolation or compliance-required; customer has explicitly approved removal; a replacement allow-list policy (if needed) is already applied.

**Command:**

```bash
kubectl delete networkpolicy <NAME> -n <NS>
```

**Blast radius:** changes default-deny traffic rules for every pod matched by the policy's `podSelector` in namespace `<NS>`. Cannot be reverted by a single command — the original YAML must be re-applied. Misdiagnosis can expose production traffic.

### Node reboot / replacement for GPU faults

Ordering and commands are in node-debugger: [references/node-diagnostics-detail.md § F](../../hyperpod-node-debugger/references/node-diagnostics-detail.md). Reboot first (clears transient GPU/EFA faults, preserves data); replace only if reboot doesn't clear the fault.
