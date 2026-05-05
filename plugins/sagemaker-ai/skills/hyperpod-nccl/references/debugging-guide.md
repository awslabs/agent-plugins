# NCCL HyperPod — Detailed Debugging Guide

Detailed procedures for each failure type. See `SKILL.md` for the quick reference.

## Table of Contents

| #  | Section                                                                                                        | Key Symptoms                                        |
| -- | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 1  | [NCCL Timeout / Rendezvous Hang](#1-nccl-timeout--rendezvous-hang)                                             | Training hangs, AllReduce stuck, rendezvous timeout |
| 2  | [Security Group Self-Reference Rules](#2-security-group-self-reference-rules)                                  | NCCL always times out, new cluster                  |
| 3  | [NCCL_SOCKET_IFNAME — Interface Selection](#3-nccl_socket_ifname--interface-selection)                         | Wrong NIC, binding to eth0 instead of EFA           |
| 4  | [Container OOM (exit code 137)](#4-container-oom--pod-killed-mid-training-exit-code-137)                       | OOMKilled, exit code 137                            |
| 5  | [Wrong Results — Gradient Sync](#5-wrong-results--gradient-sync-issues)                                        | Loss not converging, inconsistent results           |
| 6  | [EFA Configuration](#6-efa-configuration)                                                                      | EFA not working, slow training, FI_PROVIDER         |
| 7  | [Node Hardware Failures](#7-node-hardware-failures)                                                            | XID errors, ECC, NVLink errors                      |
| 8  | [Slurm-Specific Procedures](#8-slurm-specific-procedures)                                                      | Slurm batch script, node management, RemoveIPC      |
| 9  | [NCCL RAS — Live Job Health](#9-nccl-ras--live-job-health-nccl-224)                                            | Live health query, straggler detection              |
| 10 | [NCCL Version Mismatch](#10-nccl-version-mismatch-nccl-function-not-found)                                     | `NCCL function not found`, mixed images             |
| 11 | [GPU OOM — CUDA out of memory](#11-gpu-oom--cuda-out-of-memory--cudamalloc-failed)                             | `cudaMalloc failed`, VRAM exhausted                 |
| 12 | [DNS Resolution Failure](#12-dns-resolution-failure-name-or-service-not-known)                                 | `Name or service not known`, headless service       |
| 13 | [EFA TCP Fallback](#13-efa-tcp-fallback-netofi-using-tcp)                                                      | `NET/OFI Using TCP`, 10x slower                     |
| 14 | [GPU P2P Access Blocked (ACS)](#14-gpu-p2p-access-blocked-acsiommu)                                            | P2P not supported, intra-node slow                  |
| 15 | [Stale Shared Memory](#15-stale-shared-memory-unlink-shared-memory)                                            | `/dev/shm/nccl-*` errors, RemoveIPC                 |
| 16 | [Host Firewall Blocking NCCL](#16-host-firewall-blocking-nccl-iptablesnftables)                                | iptables DROP/REJECT                                |
| 17 | [RDMA Memory Registration Failure](#17-rdma-memory-registration-failure-ibv_reg_mr-failed)                     | `ibv_reg_mr failed`, memlock                        |
| 18 | [Distributed Training Frameworks](#18-distributed-training-frameworks--nccl-tuning)                            | FSDP, DeepSpeed, Megatron-LM tuning                 |
| 19 | [Advanced NCCL Tuning](#19-advanced-nccl-tuning-nvls-pxn-topology-cross-nic)                                   | NVLS, PXN, topology, cross-NIC                      |
| 20 | [Pending / CrashLoopBackOff / Init-Container Failures](#20-pending--crashloopbackoff--init-container-failures) | Pods stuck Pending, init containers failing         |
| 21 | [GPU Row-Remap / DCGM Health](#21-gpu-row-remap--dcgm-health-marginal-memory-silent-degrader)                  | Silent NaNs, pending row-remap, DCGM false-Pass     |

---

## 1. NCCL Timeout / Rendezvous Hang

**Always start minimal:** Reproduce with 2 ranks and `torch.ones(100)` before debugging full training.

```python
import os, torch, torch.distributed as dist, datetime
rank = int(os.environ.get('RANK', 0))
world_size = int(os.environ.get('WORLD_SIZE', 2))
master = os.environ.get('MASTER_ADDR', 'localhost')
port  = os.environ.get('MASTER_PORT', '29500')
dist.init_process_group('gloo',
    init_method=f'tcp://{master}:{port}',
    world_size=world_size, rank=rank,
    timeout=datetime.timedelta(seconds=120))
t = torch.ones(100) * rank
dist.all_reduce(t, op=dist.ReduceOp.SUM)
expected = sum(range(world_size))
assert t[0].item() == expected, f"Got {t[0].item()}, expected {expected}"
print(f"[Rank {rank}] [PASS] AllReduce PASSED", flush=True)
dist.destroy_process_group()
```

**Debug env vars:**

```bash
export NCCL_DEBUG=INFO          # verbose NCCL output
export NCCL_DEBUG_SUBSYS=ALL    # all subsystems
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export NCCL_TIMEOUT=1800        # 30 min during debug
export NCCL_DEBUG_FILE=/tmp/nccl_rank${RANK}.log
```

**Dump call stack of hung process:**

```bash
# Inside the pod (EKS):
kubectl exec -n <ns> <pod> -- pip install py-spy -q
kubectl exec -n <ns> <pod> -- py-spy dump --pid $(pgrep -f python | head -1)

# On the node via SSM (both orchestrators):
aws ssm start-session --target sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>
# On node:
py-spy dump --pid $(pgrep -f python | head -1)
py-spy record -o /tmp/profile.svg --pid <PID> --duration 30
```

**Root cause matrix:**

| Timeout fires when            | Root cause                          | Fix                                                              |
| ----------------------------- | ----------------------------------- | ---------------------------------------------------------------- |
| Before init completes         | SG missing self-ref / NetworkPolicy | Fix SG or remove blocking NetworkPolicy                          |
| Before init completes         | Wrong MASTER_ADDR / DNS failure     | Fix headless service; use `<job>-0.<svc>.<ns>.svc.cluster.local` |
| Before init completes         | WORLD_SIZE > actual pods            | Match WORLD_SIZE to `spec.completions`                           |
| After init, during AllReduce  | One rank crashed (OOM/CUDA)         | Check pod logs for exit code 137                                 |
| After init, during AllReduce  | Straggler node (slow NIC)           | Run nccl-tests, drain slow node                                  |
| On large cluster (128+ nodes) | NCCL_TIMEOUT too low                | Set `NCCL_TIMEOUT = node_count * 5 + 600`                        |

**Slurm MASTER_ADDR setup** (no headless service needed — Slurm resolves hostnames natively):

```bash
# In your sbatch script:
export MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -1)
export MASTER_PORT=29500
# Verify DNS works from all nodes:
srun --overlap bash -c "nslookup $MASTER_ADDR"
```

**For 100+ node clusters — prioritized fix order:**

1. Check `NCCL_TIMEOUT` (most common) — set `NCCL_TIMEOUT=$(( nodes * 5 + 600 ))`
2. Check `memlock` — set to `8388608` (not `unlimited`) — see Section 17
3. Run straggler detection — see `references/performance-testing.md` pairwise bandwidth test
4. Check for NCCL version drift after rolling node replacements — see Section 10

---

## 2. Security Group Self-Reference Rules

**Required rules — without these NCCL will always timeout:**

```bash
SG=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'VpcConfig.SecurityGroupIds[0]' --output text)

# Inbound (inter-node TCP/UDP):
aws ec2 authorize-security-group-ingress --group-id $SG --region <R> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'$SG'"}]}]'

# Outbound (EFA RDMA):
aws ec2 authorize-security-group-egress --group-id $SG --region <R> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'$SG'"}]}]'

# Also needed: outbound 0.0.0.0/0 for SageMaker/S3 API calls
aws ec2 authorize-security-group-egress --group-id $SG --region <R> \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]'
```

**Verify rules are present:**

```bash
aws ec2 describe-security-groups --group-ids $SG --region <R> \
  --query 'SecurityGroups[0].{Inbound:IpPermissions,Outbound:IpPermissionsEgress}' \
  --output json | python3 -c "
import sys, json
d = json.load(sys.stdin)
def has_self_ref(rules, sg_id):
    return any(any(p.get('GroupId') == sg_id for p in r.get('UserIdGroupPairs', []))
               for r in rules)
sg_id = '$SG'
print('Inbound self-ref:', has_self_ref(d['Inbound'], sg_id))
print('Outbound self-ref:', has_self_ref(d['Outbound'], sg_id))
"
```

---

## 3. NCCL_SOCKET_IFNAME — Interface Selection

**On EFA nodes (p4d/p5), always set explicitly:**

```bash
# Correct for EFA nodes — exclude non-VPC interfaces:
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth,virbr

# Find the correct VPC interface name:
ip -br addr show | grep -vE "^lo|docker|br-|virbr|veth|efa" | grep UP | awk '{print $1}'
```

**Validate the setting works (leaves at least one interface):**

```bash
# After setting NCCL_SOCKET_IFNAME, verify it leaves interfaces:
PATTERN="${NCCL_SOCKET_IFNAME#^}"
ip -br addr show | grep UP | awk '{print $1}' | \
  grep -vE "$(echo "$PATTERN" | tr ',' '|')"
# Must show at least one interface (e.g., ens5)
```

**Also set matching MPI variable:**

```bash
export OMPI_MCA_btl_tcp_if_include=ens5   # match your VPC ENI
# OR:
export OMPI_MCA_btl_tcp_if_exclude=lo,docker0,virbr0
```

---

## 4. Container OOM — Pod Killed Mid-Training (exit code 137)

**Symptom:** Pod status = OOMKilled, exit code 137. The Linux kernel killed the process due to cgroup memory limit.
This is different from GPU OOM (see section 11).

**Detect:**

```bash
# EKS: check container termination reason
kubectl describe pod <POD> -n <NS> | grep -A5 "Last State:"
# Shows: Reason: OOMKilled, Exit Code: 137

# On node via SSM:
dmesg | grep -i "oom\|killed process" | tail -10
free -h
```

**Fix options (in order of impact):**

```python
# 1. Gradient checkpointing (most impact, slower backward pass)
model.gradient_checkpointing_enable()

# 2. FSDP (shard model across all GPUs in job)
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
model = FSDP(model, device_id=torch.cuda.current_device())

# 3. Mixed precision (halve activation memory)
from torch.cuda.amp import autocast, GradScaler
scaler = GradScaler()
with autocast():
    loss = model(inputs)

# 4. Reduce batch size
batch_size = batch_size // 2  # halve until OOM resolves
```

```yaml
# Increase K8s memory limits:
resources:
  limits:
    memory: "64Gi"   # increase as needed
    nvidia.com/gpu: "8"
```

---

## 5. Wrong Results — Gradient Sync Issues

**Verify AllReduce is actually happening:**

```python
def check_allreduce_consistency(tensor, name, rank, world_size):
    """Verify all ranks have same values after AllReduce."""
    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)
    results = [None] * world_size
    dist.all_gather_object(results, tensor.sum().item())
    if rank == 0:
        if len(set(round(r, 4) for r in results)) > 1:
            print(f"[FAIL] INCONSISTENT '{name}': {results}", flush=True)
        else:
            print(f"[PASS] CONSISTENT '{name}': {results[0]:.4f}", flush=True)
```

**Check FSDP/DTensor placements:**

```python
from torch.distributed.tensor import DTensor
for name, param in model.named_parameters():
    if isinstance(param, DTensor):
        print(f"[Rank {dist.get_rank()}] {name}: placements={param.placements}")
    else:
        print(f"[Rank {dist.get_rank()}] {name}: NOT sharded (unexpected for FSDP)")
```

**Print from all ranks in order (debugging):**

```python
def print_all_ranks(msg):
    for r in range(dist.get_world_size()):
        if dist.get_rank() == r:
            print(f"[Rank {r}] {msg}", flush=True)
        dist.barrier()
```

---

## 6. EFA Configuration

**Required for full performance on p4d/p5:**

```bash
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1     # GPU Direct RDMA
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth
export NCCL_PROTO=simple            # optimal for EFA
export NCCL_TIMEOUT=1800
```

**K8s pod spec for EFA (p4d has 4 EFA ports):**

```yaml
resources:
  limits:
    vpc.amazonaws.com/efa: 4        # p4d: 4, p5: 32
  requests:
    vpc.amazonaws.com/efa: 4
```

**Install EFA K8s device plugin:**

```bash
# Helm (recommended):
helm repo add eks https://aws.github.io/eks-charts
helm install aws-efa-k8s-device-plugin --namespace kube-system \
  eks/aws-efa-k8s-device-plugin

# kubectl:
kubectl apply -f https://raw.githubusercontent.com/aws/aws-efa-k8s-device-plugin/main/main.yaml
```

**Verify EFA on node:**

```bash
fi_info -p efa                              # lists EFA endpoints
cat /opt/amazon/efa_installed_packages      # EFA installer version
lsmod | grep efa                            # kernel module loaded
ls /dev/infiniband/uverbs*                  # device files exist
nvidia-smi nvlink --status                  # NVLink (p4d/p5)
```

---

## 7. Node Hardware Failures

**XID error detection:**

```bash
# Via SSM on any node:
nvidia-smi -q | grep -E "Xid|Error Type|ECC"
dmesg | grep -iE "xid|nvrm|hardware" | tail -20
nvidia-smi nvlink -e   # NVLink error counters
```

**Replace bad node via HyperPod API:**

```bash
# Get instance ID from K8s node name:
kubectl get node <NODE_NAME> -o jsonpath='{.spec.providerID}' | cut -d'/' -f5

# Reboot first (less disruptive, preserves data):
aws sagemaker batch-reboot-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["<INSTANCE_ID>"]'

# Full replacement (if reboot doesn't help):
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["<INSTANCE_ID>"]'
```

**Drain before replace (EKS):**

```bash
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
```

---

## 8. Slurm-Specific Procedures

**NCCL batch script template:**

```bash
#!/bin/bash
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-node=8
#SBATCH --job-name=nccl-training

# EFA settings (p4d/p5):
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth
export NCCL_TIMEOUT=1800
export NCCL_DEBUG=WARN

# Rendezvous (torchrun manages RANK/WORLD_SIZE automatically):
export MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -1)
export MASTER_PORT=29500

srun torchrun \
  --nnodes=$SLURM_NNODES \
  --nproc_per_node=8 \
  --rdzv_backend=c10d \
  --rdzv_endpoint=$MASTER_ADDR:$MASTER_PORT \
  train.py
```

**Node management:**

```bash
sinfo -o "%N %T %30E"                           # all node states
scontrol show node <NODE> | grep Reason          # why node is down
scontrol update nodename=<NODE> state=resume     # resume drained node
sudo systemctl restart slurmctld                 # fix stuck jobs
sudo systemctl status slurmd                     # check on compute node
squeue -o "%i %j %T %R %N" | grep PENDING       # stuck pending jobs
```

**systemd RemoveIPC (must be disabled for Slurm):**

```bash
# Check:
grep RemoveIPC /etc/systemd/logind.conf

# Fix:
echo "RemoveIPC=no" >> /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
```

---

## 9. NCCL RAS — Live Job Health (NCCL 2.24+)

```bash
# Query while training job is running:
echo "verbose status" | nc localhost 28028

# With ncclras binary:
ncclras -h localhost -p 28028 -v

# Inside K8s pod:
kubectl exec -n <NS> <POD> -- \
  sh -c "echo 'verbose status' | nc -w 3 localhost 28028"

# JSON output (NCCL 2.28+):
ncclras -f json | python3 -m json.tool

# Monitor mode (NCCL 2.29+) — real-time events:
ncclras -m
# Shows: PEER_DEAD when a rank dies
```

**Interpret output:**

- `RUNNING OK` — all ranks alive, progressing normally
- `MISMATCH` — some ranks behind → possible straggler
- `INCOMPLETE` — missing rank data → one rank unresponsive
- `DEAD` / `PEER_DEAD` — rank process confirmed dead → this is why you're hanging

---

## 10. NCCL Version Mismatch (`NCCL function not found`)

**Symptom:** `NCCL function not found` or `Incompatible NCCL version` at job startup.
**Cause:** Different NCCL builds across nodes — mixed container images or manual installs.

**Diagnose:**

```bash
# Check NCCL version per running pod:
for pod in $(kubectl get pods -n <NS> -l job-name=<JOB> --no-headers | awk '{print $1}'); do
    echo -n "$pod: "
    kubectl exec -n <NS> "$pod" -- \
        python3 -c "import torch; print(torch.cuda.nccl.version())" 2>/dev/null \
        || echo "unavailable"
done

# Check via library file:
kubectl exec -n <NS> <POD> -- \
    find /usr/local/cuda/lib64 /usr/lib -name "libnccl.so*" 2>/dev/null | head -3

# Check CUDA driver version per node:
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,DRIVER:.metadata.labels.nvidia\.com/cuda\.driver-version' \
2>/dev/null || kubectl get nodes -o wide
```

**Fix:**

```bash
# All pods in a job MUST use identical container images.
# Verify your job spec uses the same image for all replicas:
kubectl get pod -n <NS> -l job-name=<JOB> \
    -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.containers[0].image}{"\n"}{end}'
# Every line must show the same image:tag

# If different, update your job spec to pin to one image:
# spec.template.spec.containers[0].image: 763104351884.dkr.ecr.us-east-1.amazonaws.com/pytorch-training:2.3.0-gpu-py311-cu121-ubuntu20.04-ec2
```

**Common cause on HyperPod:** Rolling node replacement installs a new AMI with a different NCCL version while old nodes are still in the cluster. Use lifecycle scripts to pin NCCL versions.

---

## 11. GPU OOM — `CUDA out of memory` / `cudaMalloc failed`

**Symptom:** `CUDA out of memory`, `cudaMalloc failed`, or `RuntimeError: CUDA error: out of memory`.
This is GPU VRAM exhaustion — distinct from container OOMKill (section 4).
The process does NOT get killed by the kernel; PyTorch raises a Python exception.

**Diagnose:**

```bash
# Check GPU memory usage on all GPUs:
kubectl exec -n <NS> <POD> -- \
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu \
    --format=csv,noheader

# In training script — add before suspected OOM:
import torch
for i in range(torch.cuda.device_count()):
    used = torch.cuda.memory_allocated(i) / 1e9
    reserved = torch.cuda.memory_reserved(i) / 1e9
    total = torch.cuda.get_device_properties(i).total_memory / 1e9
    print(f"GPU {i}: allocated={used:.1f}GB reserved={reserved:.1f}GB total={total:.1f}GB")
    print(torch.cuda.memory_summary(i))
```

**Fix options (in order of impact):**

```python
# 1. Gradient checkpointing — trade compute for memory (most impactful)
model.gradient_checkpointing_enable()

# 2. ZeRO optimizer — shard optimizer states across ranks (DeepSpeed)
# In deepspeed config:
# "zero_optimization": {"stage": 3}   # ZeRO-3: shards params, grads, optimizer states

# 3. FSDP — shard model weights across all GPUs
from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
model = FSDP(model)

# 4. Mixed precision — halve activation memory
from torch.cuda.amp import autocast
with autocast(dtype=torch.bfloat16):
    loss = model(inputs)

# 5. Reduce batch size — simplest fix
batch_size = batch_size // 2

# 6. Clear cache between steps (if fragmentation is the issue)
torch.cuda.empty_cache()
```

**Memory fragmentation fix:**

```python
# If OOM happens after many steps (fragmentation):
import gc
gc.collect()
torch.cuda.empty_cache()
# Or: set PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

---

## 12. DNS Resolution Failure (`Name or service not known`)

**Symptom:** `Name or service not known`, `getaddrinfo failed`, or rendezvous hangs forever.
**Cause:** MASTER_ADDR hostname cannot be resolved. Most common on EKS when no headless Service exists.

**Diagnose:**

```bash
# Check DNS from inside a pod:
kubectl exec -n <NS> <POD> -- nslookup $MASTER_ADDR
kubectl exec -n <NS> <POD> -- getent hosts $MASTER_ADDR

# Check if headless service exists:
kubectl get svc -n <NS> -o wide | grep None
# Should show: ClusterIP: None with selector matching training pods

# Check CoreDNS is healthy:
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
```

**Fix:**

```yaml
# Create headless service for training job DNS:
apiVersion: v1
kind: Service
metadata:
  name: my-training-svc
  namespace: <NS>
spec:
  clusterIP: None
  selector:
    app: my-training-job   # must match training pod labels
  ports:
  - port: 29500
    name: nccl-rendezvous
```

```bash
# Set MASTER_ADDR using the service DNS:
export MASTER_ADDR="<job-name>-0.<service-name>.<namespace>.svc.cluster.local"
```

---

## 13. EFA TCP Fallback (`NET/OFI Using TCP`)

**Symptom:** In NCCL_DEBUG=INFO output, you see `NET/OFI Using TCP` instead of `NET/OFI Using EFA`.
Training runs but at 10-100x lower bandwidth than expected.

**Diagnose:**

```bash
# Check if EFA device plugin is installed:
kubectl get daemonset -A | grep -i efa

# Check if pod requests EFA:
kubectl get pod <POD> -n <NS> -o jsonpath='{.spec.containers[0].resources.limits}'
# Must include: vpc.amazonaws.com/efa

# Check EFA env vars:
kubectl exec -n <NS> <POD> -- env | grep FI_

# Check on node via SSM:
fi_info -p efa  # Must list EFA endpoints
```

**Fix checklist:**

```bash
# 1. Install EFA device plugin:
helm repo add eks https://aws.github.io/eks-charts
helm install aws-efa-k8s-device-plugin --namespace kube-system eks/aws-efa-k8s-device-plugin

# 2. Request EFA in pod spec:
# resources.limits: {vpc.amazonaws.com/efa: 4}  # p4d=4, p5=32

# 3. Set env vars:
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth

# 4. Ensure aws-ofi-nccl plugin is in container:
# find /opt/amazon -name "libnccl-net.so" 2>/dev/null
```

---

## 14. GPU P2P Access Blocked (ACS/IOMMU)

**Symptom:** `NCCL WARN P2P not supported between dev X and dev Y` or `peer access is not supported`.
Intra-node AllReduce is 10-50x slower because GPU Direct P2P transfers are blocked by PCI ACS.

**Diagnose:**

```bash
# Check ACS on node via SSM:
lspci -vvv 2>/dev/null | grep -A20 "PCI bridge" | grep "ACSCtl:"
# If "SrcValid+" appears → ACS is enabled → P2P blocked

# Check IOMMU:
dmesg | grep -i iommu
grep -oE "intel_iommu=[^ ]+" /proc/cmdline

# Check P2P topology:
nvidia-smi topo -m
# NV# = NVLink (fast), PIX/PXB/PHB = PCIe (slow)
```

**Fix:**

```bash
# Disable ACS on NVIDIA GPU upstream bridges only — scoping to 10de: avoids
# weakening IOMMU isolation on unrelated PCI devices.
for BDF in $(lspci -D -d 10de: | awk '{print $1}'); do
  sudo setpci -s "$BDF" ECAP_ACS+0x6.w=0000 2>/dev/null
done

# Add to lifecycle script for persistence (same NVIDIA-only scope):
echo 'for BDF in $(lspci -D -d 10de: | awk "{print \$1}"); do setpci -s $BDF ECAP_ACS+0x6.w=0000 2>/dev/null; done' \
  >> /opt/ml/scripts/on_create.sh
```

> **WARNING:** disabling ACS weakens IOMMU isolation for the affected PCI bridges.
> Do not apply cluster-wide on a multi-tenant host. Scope to GPU bridges only,
> as shown above.

---

## 15. Stale Shared Memory (`unlink shared memory`)

**Symptom:** `unlink shared memory /dev/shm/nccl-* failed: No such file` or new training job
fails with `File exists` on /dev/shm/nccl-* files left by a previous crash.

**Cause:** Either systemd `RemoveIPC=yes` (default on RHEL/Amazon Linux) deletes NCCL shm
mid-training, or a crashed training process left orphaned shm files.

**Diagnose:**

```bash
# Check on node:
ls -la /dev/shm/nccl-*
grep RemoveIPC /etc/systemd/logind.conf
```

**Fix:**

```bash
# Clean up stale files (safe when no training running):
rm -f /dev/shm/nccl-*

# Prevent systemd from deleting shm mid-training:
echo "RemoveIPC=no" >> /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# Add to lifecycle script:
echo 'echo "RemoveIPC=no" >> /etc/systemd/logind.conf && systemctl restart systemd-logind' \
  >> /opt/ml/scripts/on_create.sh
```

---

## 16. Host Firewall Blocking NCCL (iptables/nftables)

**Symptom:** NCCL timeout even though SG rules and NetworkPolicy are correct.
Root cause: host-level iptables or nftables DROP/REJECT rules blocking NCCL ports.

**Diagnose:**

```bash
# On node via SSM:
iptables -L -n | grep -E "DROP|REJECT"
nft list ruleset 2>/dev/null | grep -E "drop|reject"
```

**Fix:**

```bash
# Identify the specific blocking rule, then delete only that rule:
iptables -L -n --line-numbers
iptables -D INPUT <rule_number>

# Preferred: add explicit allow for NCCL ports instead of touching existing rules:
iptables -I INPUT -p tcp --dport 29400:29500 -j ACCEPT
iptables -I INPUT -p tcp --dport 28028 -j ACCEPT  # NCCL RAS
```

> **IMPORTANT:** do not run `iptables -F` on an EKS worker. It flushes
> kube-proxy's service rules and VPC CNI NetworkPolicy enforcement, breaking
> pod networking cluster-wide. Always delete individual rules by line number.

---

## 17. RDMA Memory Registration Failure (`ibv_reg_mr failed`)

**Symptom:** `NCCL WARN Call to ibv_reg_mr failed` followed by EFA falling back to TCP — training continues but at 10-100x lower bandwidth.

**Cause:** The Linux `memlock` limit prevents the EFA driver from pinning memory for RDMA DMA transfers. With `memlock=0` or very low values, EFA cannot register any memory buffers.

**Diagnose:**

```bash
# Check current memlock limit:
ulimit -l
# Should be: unlimited or ≥8388608 (8GB in KB)
# If 0 or 64 → FAIL

# Check on the actual node via SSM:
aws ssm start-session --target sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>
# On node:
ulimit -l
cat /proc/$(pgrep -f python | head -1)/limits | grep "Max locked"

# In NCCL debug output (NCCL_DEBUG=INFO):
# "NCCL WARN Call to ibv_reg_mr failed, got error (12)" → errno 12 = ENOMEM (memlock)
```

**Fix — immediate (session only):**

```bash
ulimit -l 8388608       # 8GB in KB
# OR:
ulimit -l unlimited     # See warning below
```

**Fix — permanent (system-wide):**

```bash
# Add to /etc/security/limits.conf:
echo "* soft memlock 8388608" >> /etc/security/limits.conf
echo "* hard memlock 8388608" >> /etc/security/limits.conf
# Requires re-login to take effect

# For Slurm: add to /etc/slurm/prolog.sh
echo "ulimit -l 8388608" >> /etc/slurm/prolog.sh
```

**Fix — K8s pod spec:**

```yaml
# Add IPC_LOCK capability to allow large memlock:
securityContext:
  capabilities:
    add: ["IPC_LOCK"]
```

**Note on `memlock=unlimited`:** GNU libc sets a hard limit of 2MB stack for threads when memlock is unlimited (a known quirk). For NCCL this means background threads may get only 2MB stack, which can cause topology graph search failures on large clusters. Use a large fixed value (8388608) instead of unlimited.

**Verify fix worked:**

```bash
# After fix, NCCL_DEBUG=INFO should show:
# "NCCL INFO NET/OFI Using EFA RDMA" (not TCP fallback)
# No more "ibv_reg_mr failed" warnings

# Check effective bandwidth after fix:
/opt/nccl-tests/build/all_reduce_perf -b 1G -e 8G -f 2 -g 1
# Should match expected algbw for your instance type
```

---

## 18. Distributed Training Frameworks — NCCL Tuning

NCCL issues often surface differently depending on the distributed training framework. Framework-specific guidance:

### FSDP (Fully Sharded Data Parallel — PyTorch native)

**Common NCCL issues with FSDP:**

| Symptom                                      | Cause                               | Fix                                                                            |
| -------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------------ |
| Hang at `_init_intra_and_inter_node_groups`  | NCCL can't form process groups      | Check `MASTER_ADDR`, `MASTER_PORT`, firewall rules, and headless service (EKS) |
| OOM during FSDP wrapping                     | All-gather materializes full params | Use `sharding_strategy=FULL_SHARD`, enable `cpu_offload` if needed             |
| Slow FSDP training vs DDP                    | Excessive all-gather/reduce-scatter | Tune `limit_all_gathers=True`, increase `forward_prefetch=True`                |
| `NCCL watchdog timeout` during checkpointing | Distributed checkpoint blocks NCCL  | Use `StateDictType.SHARDED_STATE_DICT` for async checkpoint save               |

**Recommended NCCL env vars for FSDP on HyperPod:**

```bash
export NCCL_SOCKET_IFNAME=^lo,docker
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1
export NCCL_ALGO=Ring           # Ring is generally better for FSDP all-gather patterns
export NCCL_PROTO=Simple        # Simple protocol for large message FSDP comms
export NCCL_TIMEOUT=1800        # 30 min — FSDP checkpoint can be slow at scale
```

### DeepSpeed

**Common NCCL issues with DeepSpeed:**

| Symptom                                       | Cause                                 | Fix                                                                                                                                                                    |
| --------------------------------------------- | ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RuntimeError: NCCL communicator was aborted` | Timeout during ZeRO all-gather        | Increase `NCCL_TIMEOUT`; check for straggler nodes                                                                                                                     |
| OOM with ZeRO Stage 3                         | Parameter partitioning + NCCL buffers | Reduce `stage3_max_live_parameters`, enable `offload_optimizer`                                                                                                        |
| Slow DeepSpeed init on 100+ nodes             | Sequential NCCL group creation        | Set `TORCH_NCCL_ASYNC_ERROR_HANDLING=1` (was `NCCL_ASYNC_ERROR_HANDLING` on PyTorch < 2.2 — old name still works but deprecated), increase `init_timeout` in ds_config |
| `ncclInternalError` with pipeline parallelism | Cross-node P2P fails                  | Ensure `NCCL_P2P_LEVEL=NVL` for intra-node, check EFA for inter-node                                                                                                   |

**DeepSpeed config tuning for HyperPod:**

```json
{
  "comms_config": {
    "comms_backend": "nccl",
    "timeout": 1800
  },
  "zero_optimization": {
    "stage": 3,
    "stage3_max_live_parameters": 1e8,
    "stage3_prefetch_bucket_size": 5e7,
    "reduce_bucket_size": 5e8
  }
}
```

### Megatron-LM

**Common NCCL issues with Megatron-LM:**

| Symptom                                     | Cause                                           | Fix                                                                |
| ------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------ |
| Hang at `initialize_model_parallel`         | NCCL group creation fails across nodes          | Verify world size = TP \* PP \* DP, check network connectivity     |
| Slow tensor-parallel matmul                 | NCCL all-reduce on small tensors is inefficient | Increase TP group size to stay intra-node (TP ≤ GPUs/node)         |
| Pipeline bubble > 40%                       | PP schedule inefficiency                        | Reduce PP stages, increase micro-batches, try interleaved schedule |
| `ncclGroupEnd failed` during 3D parallelism | Too many simultaneous NCCL groups               | Ensure `NCCL_MAX_NCHANNELS=2` for memory-constrained setups        |

**Megatron-LM parallelism mapping for HyperPod:**

```
Rule of thumb:
  TP (tensor parallel) = within a single node (8 GPUs on p5)
  PP (pipeline parallel) = across nodes (minimizes cross-node comms volume)
  DP (data parallel) = remaining nodes
  
  World size = TP × PP × DP
  Example: 32 p5.48xlarge (256 GPUs)
    TP=8, PP=4, DP=8 → 8×4×8 = 256
```

---

## 19. Advanced NCCL Tuning (NVLS, PXN, Topology, Cross-NIC)

### NVLS — NVLink SHARP (GPU-to-GPU hardware offload)

NVLS is NVIDIA's in-network aggregation over NVLink, enabled by default in NCCL 2.19+. It speeds up small-message AllReduce on H100/H200 nodes but **requires matching driver and container versions**. On HyperPod, driver/container mismatch is the #1 cause of NVLS-related hangs.

**Symptoms:**

- Hang inside `ncclAllReduce` on p5/p5e/p5en
- `NCCL INFO ... NVLS ... failed`
- Fine on 1 node, hang on 2+ nodes

**Diagnosis:**

```bash
# Check NCCL version (container side)
python3 -c "import torch; print(torch.cuda.nccl.version())"
# Check driver version (node side, via SSM)
nvidia-smi --query-gpu=driver_version --format=csv
```

**Mitigations:**

1. Disable NVLS temporarily to isolate:

   ```bash
   export NCCL_NVLS_ENABLE=0
   ```

2. Pin NCCL version across all pods/jobs (match container image digest, not tag).
3. Upgrade the NVIDIA driver on the AMI via `UpdateClusterSoftware` if the container expects a newer driver.

### PXN — P2P Cross-NUMA (p5.48xlarge optimal config)

PXN lets NCCL route inter-node traffic via an intermediary GPU on a different NUMA node to maximize NIC utilization. For p5.48xlarge (8 GPUs, 32 EFA), `NCCL_PXN_LEVEL=2` and `NCCL_CROSS_NIC=1` are recommended.

```bash
# Recommended defaults for p5.48xlarge
export NCCL_PXN_LEVEL=2
export NCCL_CROSS_NIC=1
# Optional: increase channel count for large messages
export NCCL_MIN_NCHANNELS=4
```

If these cause regressions on smaller jobs (< 16 nodes), set `NCCL_PXN_LEVEL=0` and measure.

### NCCL_TOPO_FILE — Custom Topology

NCCL auto-discovers topology on p-family instances and usually picks the right plan. Use a custom topology file only when:

- Running in containers that hide the PCIe topology from NCCL
- Using an instance type NCCL doesn't recognize
- Debugging suboptimal ring/tree selection

To export the topology NCCL sees for manual inspection:

```bash
export NCCL_TOPO_DUMP_FILE=/tmp/nccl-topo.xml
# Run any NCCL op (e.g., all_reduce_perf), then inspect /tmp/nccl-topo.xml
```

Do **not** ship a hand-edited topology file unless you've confirmed the default is wrong — this is an advanced-user escape hatch.

### NCCL_SOCKET_FAMILY — IPv4 Forcing

Dual-stack environments (IPv6 enabled on the VPC but IPv4 intended for NCCL) can cause silent TCP fallback. Force IPv4:

```bash
export NCCL_SOCKET_FAMILY=AF_INET
```

### Mixed Instance Families

**Do not** mix p5 and p4d in the same NCCL communicator. Asymmetric topology causes algorithm selection failures (`NCCL WARN ... unable to find a working algorithm`). Launch separate jobs per instance family.

### SHARP on EFA

SHARP (Scalable Hierarchical Aggregation and Reduction Protocol) is **not supported on EFA**. If your job environment sets `NCCL_COLLNET_ENABLE=1` on HyperPod, disable it:

```bash
export NCCL_COLLNET_ENABLE=0
```

### Instance family EFA counts (reference)

Used for validating that all EFA devices are attached and visible. Run
`ls /dev/infiniband/uverbs* | wc -l` on a node and compare:

| Instance type | Expected EFA count |
| ------------- | ------------------ |
| p5.48xlarge   | 32                 |
| p5e.48xlarge  | 32                 |
| p5en.48xlarge | 16                 |
| p4d.24xlarge  | 4                  |
| p4de.24xlarge | 4                  |
| trn1.32xlarge | 8                  |
| trn2.48xlarge | 16                 |

Mismatch → EFA driver not loaded, or a subset of NICs didn't attach at boot. Replace the node.

---

## 20. Pending / CrashLoopBackOff / Init-Container Failures

Pod lifecycle failures surface as `Pending`, `CrashLoopBackOff`, or stuck in an init container. These are NOT NCCL bugs per se — they block the NCCL job from starting. Diagnose in this order:

### Pending pods

```bash
# Why is it pending?
kubectl describe pod <POD> -n <NS> | sed -n '/Events:/,$p' | head -40
```

Common reasons and where to fix:

| Event message                                                                  | Root cause                                                       | Where to fix                                                                                                    |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `0/N nodes are available: N Insufficient <resource>`                           | Not enough CPU/mem/GPU free                                      | Wait for other jobs, or scale the cluster                                                                       |
| `0/N nodes are available: N node(s) didn't match Pod's node affinity/selector` | Affinity/selector too strict                                     | Fix `nodeSelector` / `nodeAffinity` in the pod spec                                                             |
| `0/N nodes are available: N node(s) had untolerated taint`                     | Taints on HyperPod nodes (common: `hyperpod.amazonaws.com/node`) | Add matching `tolerations` to the pod spec                                                                      |
| `failed to create pod sandbox: ... CNI`                                        | VPC CNI problem                                                  | Delegate to `hyperpod-node-debugger` § O                                                                        |
| `MountVolume.SetUp failed for volume`                                          | PVC binding issue                                                | Check PVC status, StorageClass, EBS/FSx availability                                                            |
| `ImagePullBackOff` / `ErrImagePull`                                            | Container image pull failed                                      | Check ECR pull permissions on the node role; check image URI; confirm VPC endpoint for ECR if in private subnet |
| (no events; just stuck)                                                        | Scheduler starved or no matching pool                            | `kubectl get events -A --sort-by=.lastTimestamp \| tail -50` for cluster-wide scheduler state                   |

### CrashLoopBackOff

```bash
kubectl logs <POD> -n <NS> --previous | tail -100   # logs from the crashed container
kubectl describe pod <POD> -n <NS>                   # last termination state + exit code
```

Map the exit code to the guide section:

| Exit code       | Meaning                                       | Section                                                |
| --------------- | --------------------------------------------- | ------------------------------------------------------ |
| 137 (OOMKilled) | Container OOM                                 | § 4 Container OOM                                      |
| 143 (SIGTERM)   | Liveness probe failed or graceful termination | Check liveness probe; check preceding SIGTERM in logs  |
| 139 (SIGSEGV)   | Segfault — often CUDA / driver mismatch       | § 10 NCCL Version Mismatch                             |
| 1 / 2 / other   | Application error                             | Read `kubectl logs --previous` for the app-level error |

### Stuck in init container

```bash
kubectl get pod <POD> -n <NS> -o jsonpath='{.status.initContainerStatuses}' | python3 -m json.tool
kubectl logs <POD> -n <NS> -c <INIT_CONTAINER_NAME>
```

Common init-container failures:

- Fetching model weights from S3 — check IAM, VPC endpoint, bucket policy.
- Downloading dataset — DNS / network / auth.
- Running a `chown`/`chmod` on a large volume — timeout.
- Waiting for another pod (headless service / init-container-as-gate pattern) — the dependency pod never became Ready.

### Remediation is always customer-driven

None of these states have a one-command fix. Walk the customer through the diagnosis above, identify the specific cause, then apply the targeted fix. Do not `kubectl delete` pods without understanding why.

---

## 21. GPU Row-Remap / DCGM Health (Marginal Memory Silent Degrader)

### When this applies

NCCL aborts or training accuracy regressions that aren't explained by Xid or ECC counts. Classic pattern: sporadic NaNs, intermittent AllReduce hangs, DCGM default `medium,memtest` passes, but one or more GPUs are silently returning bad data.

### Root cause

- **Pending row-remaps**: H100 / A100 GPUs stage a memory-row replacement when marginal memory is detected. The remap is **pending** until a GPU reset or reboot finalizes it. While pending, the memory is still marginal — training drifts.
- **Stuck pending**: A known firmware edge case keeps the remap in "Pending" across reboots instead of promoting to "Failure". The GPU is effectively failing but neither `nvidia-smi` nor a DCGM health check flags it.
- **DCGM `medium,memtest` bug (≤ 3.3.9)**: Combined-run `dcgmi diag -r medium,memtest` can pass even when `memtest` alone would fail. The diagnostic bucket that covers row-remap in memtest gets masked.

### Diagnose

```bash
# Query remap state on every GPU in the node:
nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
  --format=csv

# DCGM health (JSON form is parseable):
dcgmi health --check -j

# Work around the medium,memtest combined-run bug by splitting:
dcgmi diag -r medium
dcgmi diag -r memtest

# Latest DCGM validation-suite log:
ls -1t /var/log/nvidia-dcgm/ | head
tail -n 200 "$(ls -1t /var/log/nvidia-dcgm/nvvs*.log 2>/dev/null | head -1)"
```

### Remediation by state

| Remap state                          | Action                                                                                                                                                                          |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pending = 0`, `failure = No`        | Healthy. If symptoms persist, look elsewhere (§ 4 OOM, § 10 version mismatch, § 17 RDMA, § 19 topology).                                                                        |
| `pending > 0`                        | Reboot the node via `batch-reboot-cluster-nodes`. Re-check; pending should drop to 0.                                                                                           |
| `pending > 0` persists across reboot | Firmware edge case. Drain and replace the node via `batch-replace-cluster-nodes`; open an AWS Support case with `nvidia-bug-report.sh` output + `/var/log/nvidia-dcgm/` bundle. |
| `failure = Yes`                      | GPU has exceeded remap capacity. Drain and replace the node.                                                                                                                    |

### Data to collect before escalating

```bash
# Authoritative NVIDIA diagnostic bundle:
sudo nvidia-bug-report.sh   # produces nvidia-bug-report.log.gz

# Full DCGM log set:
sudo tar -czf /tmp/nvidia-dcgm-logs.tgz /var/log/nvidia-dcgm/
```

Attach both plus the `nccl-diagnose.sh` output and the `nvidia-smi --query-remapped-rows` CSV to the AWS Support case. Row-remap data is the single most useful signal for diagnosing these silent failures.
