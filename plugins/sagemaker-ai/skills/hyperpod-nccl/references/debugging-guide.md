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
| 9  | [NCCL RAS — Live Job Health](#9-nccl-ras--live-job-health)                                                     | Live health query, straggler detection              |
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
export NCCL_DEBUG=INFO              # verbose NCCL output
export NCCL_DEBUG_SUBSYS=ALL        # all subsystems
export TORCH_DISTRIBUTED_DEBUG=DETAIL
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1    # surface NCCL timeouts as exceptions
export NCCL_DEBUG_FILE=/tmp/nccl_rank${RANK}.log
# Extend PyTorch collective timeout in training code:
#   dist.init_process_group("nccl", timeout=timedelta(seconds=1800))
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

| Timeout fires when            | Root cause                                                   | Fix                                                                                                                    |
| ----------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| Before init completes         | SG missing self-ref / NetworkPolicy                          | Fix SG or remove blocking NetworkPolicy                                                                                |
| Before init completes         | Wrong MASTER_ADDR / DNS failure                              | Fix headless service; use `<job>-0.<svc>.<ns>.svc.cluster.local`                                                       |
| Before init completes         | WORLD_SIZE > actual pods                                     | Match WORLD_SIZE to `spec.completions`                                                                                 |
| After init, during AllReduce  | One rank crashed (OOM/CUDA)                                  | Check pod logs for exit code 137                                                                                       |
| After init, during AllReduce  | Straggler node (slow NIC)                                    | Run nccl-tests, drain slow node                                                                                        |
| On large cluster (128+ nodes) | PyTorch collective timeout too low (default 10 min for NCCL) | Raise via `init_process_group(timeout=timedelta(seconds=<N>))`; `nodes*5+600` is a starting heuristic, not a guarantee |

**Slurm MASTER_ADDR setup** (no headless service needed — Slurm resolves hostnames natively):

```bash
# In your sbatch script:
export MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -1)
export MASTER_PORT=29500
# Verify DNS works from all nodes:
srun --overlap bash -c "nslookup $MASTER_ADDR"
```

**For 100+ node clusters — prioritized fix order:**

1. Extend the PyTorch collective timeout (default: 10 min for NCCL, per the PyTorch distributed docs). Example starting value: `init_process_group(timeout=timedelta(seconds=<N>))` where `N` is tuned from your observed step time. `nodes*5+600` is a starting heuristic only.
2. Check `memlock` — see Section 17 (field-observed workaround for topology-search hangs on 256+ node clusters).
3. Run straggler detection — see `references/performance-testing.md` pairwise bandwidth test.
4. Check for NCCL version drift after rolling node replacements — see Section 10

---

## 2. Security Group Self-Reference Rules

Commands and verification are in [operations.md § 8](operations.md#8-nccl-specific-remediations). Without inbound + outbound self-reference on the cluster SG, NCCL rendezvous and EFA RDMA traffic are dropped.

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
export NCCL_PROTO=Simple            # large-message protocol (valid: LL, LL128, Simple)
# Collective timeout is a PyTorch arg — set via init_process_group(timeout=timedelta(seconds=1800))
```

**K8s pod spec for EFA:**

```yaml
resources:
  limits:
    vpc.amazonaws.com/efa: <N>   # match EFA device count for the instance type
  requests:
    vpc.amazonaws.com/efa: <N>
```

### Suggested command — install EFA K8s device plugin (run this yourself)

**Preconditions:** EKS orchestrator with GPU nodes (p4d / p5 / p5e / p5en / p6); node AMI already has EFA kernel modules (verify `fi_info -p efa` returns endpoints on one node); cluster admin has approved installing a daemonset into `kube-system`. If EFA is already allocated to pods (pod `limits.vpc.amazonaws.com/efa > 0`), the plugin is already installed — skip.

**Command:**

```bash
helm repo add eks <aws-eks-charts-helm-repo>
helm install aws-efa-k8s-device-plugin --namespace kube-system \
  eks/aws-efa-k8s-device-plugin
```

**Blast radius:** installs a daemonset on every node in `kube-system` (one pod per node) that advertises `vpc.amazonaws.com/efa` as a schedulable resource. Cannot be removed by a single command — requires `helm uninstall`. Interacts with every GPU-scheduling pod; misconfiguration can starve pods of EFA resources.

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

NCCL errors caused by GPU / EFA hardware faults (Xid errors, ECC, NVLink, off-bus) are diagnosed and remediated in the node-debugger skill: [hyperpod-node-debugger § G (GPU/Accelerator)](../../hyperpod-node-debugger/references/node-diagnostics-detail.md#g-gpuaccelerator) and [§ F (Hardware / Auto-Repair)](../../hyperpod-node-debugger/references/node-diagnostics-detail.md#f-hardware--auto-repair).

Get the instance ID from a K8s node name:

```bash
kubectl get node <NODE_NAME> -o jsonpath='{.spec.providerID}' | cut -d'/' -f5
```

### Suggested command — drain before reboot/replace (EKS) (run this yourself)

**Preconditions:** hardware fault confirmed on `<NODE_NAME>` (XID/ECC/NVLink/off-bus — see `hyperpod-node-debugger § G`); customer accepts that pods using `emptyDir` volumes on this node will lose that data when evicted; drain is preparation for `batch-reboot-cluster-nodes` (try first) or `batch-replace-cluster-nodes` — not a fix on its own. See [hyperpod-cluster-debugger § G.2](../../hyperpod-cluster-debugger/references/cluster-diagnostics-detail.md#g2-manual-replacement).

**Command:**

```bash
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data
```

**Blast radius:** `--delete-emptydir-data` discards `emptyDir` scratch on this node (training caches, ephemeral checkpoints not persisted to PVC/`/opt/sagemaker`); pods are rescheduled elsewhere if capacity exists, otherwise stay Pending. Drain is reversible (`kubectl uncordon`) only if you decide not to proceed with reboot/replace.

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
export NCCL_DEBUG=WARN
# Set the PyTorch collective timeout in training code, not via env:
#   dist.init_process_group("nccl", timeout=timedelta(seconds=1800))

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

Slurm node management and the `RemoveIPC=no` requirement are in [operations.md § 7](operations.md#7-slurm--nccl-specific-operations).

---

## 9. NCCL RAS — Live Job Health

NCCL's RAS (Reliability, Availability, Serviceability) subsystem lets you query the state of a running NCCL job without attaching a debugger. Per the NCCL env-var reference, RAS is available since NCCL 2.24 and is enabled by default (`NCCL_RAS_ENABLE=1`); the listen address is configured via `NCCL_RAS_ADDR`. Confirm the actual port your build uses (it can be overridden by env or NCCL config) before assuming the example port number below.

```bash
# Find the RAS port for the running NCCL process (configurable via NCCL_RAS_ADDR):
#   - Check the env of the training process:
#       cat /proc/$(pgrep -f python | head -1)/environ | tr '\0' '\n' | grep NCCL_RAS_ADDR
#   - Or check what's listening locally:
#       ss -ltnp | grep -i nccl

# Example (replace <PORT> with the actual RAS port for your build):
echo "verbose status" | nc -w 3 localhost <PORT>

# With the ncclras binary :
ncclras -v
ncclras -f json | python3 -m json.tool   
ncclras -m                              

# Inside a K8s pod:
kubectl exec -n <NS> <POD> -- sh -c "echo 'verbose status' | nc -w 3 localhost <PORT>"
```

**Interpret status:**

- `RUNNING OK` — all ranks alive, progressing normally
- `MISMATCH` — some ranks behind → possible straggler
- `INCOMPLETE` — missing rank data → one rank unresponsive
- `DEAD` / `PEER_DEAD` — a rank process is confirmed dead → this is the rank that hung the collective

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

# If different, update your job spec to pin every replica to the same image:
# spec.template.spec.containers[0].image: <AWS DLC image URI from your region's DLC account>
# e.g. an AWS Deep Learning Container pytorch-training image tagged for your CUDA + Python + OS combo
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
**Cause:** MASTER_ADDR hostname cannot be resolved. Common on EKS when no headless Service is in place to give pods a stable DNS name.

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

1. Install the EFA K8s device plugin — see the Suggested-command block earlier in this file (§ EFA device plugin).
2. Request EFA in pod spec:

   ```yaml
   resources:
     limits:
       vpc.amazonaws.com/efa: <N>   # match EFA device count for the instance type
   ```

3. Set EFA env vars in the pod:

   ```bash
   export FI_PROVIDER=efa
   export FI_EFA_USE_DEVICE_RDMA=1
   export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth
   ```

4. Ensure the `aws-ofi-nccl` plugin is in the container image (`find /opt/amazon -name "libnccl-net.so" 2>/dev/null`).

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

### Suggested command — disable ACS on NVIDIA GPU bridges (last resort; run this yourself)

**Preconditions:** P2P GPU traffic confirmed to fall back to CPU hops via `nvidia-smi topo -m`; GPU peer-to-peer blocked by PCIe ACS (`ACSCtl: SrcValid+` observed via `lspci -vvv`); confirmed the node is single-tenant (training workload only); you have reviewed that this weakens IOMMU isolation for the affected PCI bridges. Do NOT apply to multi-tenant or security-sensitive hosts.

**Command:**

```bash
# Disable ACS on NVIDIA GPU upstream bridges only — scoping to 10de: avoids
# weakening IOMMU isolation on unrelated PCI devices.
for BDF in $(lspci -D -d 10de: | awk '{print $1}'); do
  sudo setpci -s "$BDF" ECAP_ACS+0x6.w=0000 2>/dev/null
done

# For persistence, add the same NVIDIA-only scope to the lifecycle script:
echo 'for BDF in $(lspci -D -d 10de: | awk "{print \$1}"); do setpci -s $BDF ECAP_ACS+0x6.w=0000 2>/dev/null; done' \
  >> /opt/ml/scripts/on_create.sh
```

**Blast radius:** host-wide PCIe change for every NVIDIA GPU bridge on the node — takes effect immediately and persists for the life of the OS (or until the lifecycle script is re-run after a reboot). IOMMU isolation for those bridges is reduced, which is acceptable on a dedicated training host but NOT acceptable on multi-tenant hosts. If applied incorrectly, reboot restores the default ACS state unless the lifecycle-script change was made.

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

### Suggested command — clean stale shm and disable RemoveIPC (run this yourself)

**Preconditions:** no NCCL training job is currently running on this node (`ps aux | grep -E 'python.*torchrun|mpirun'` returns empty); `RemoveIPC=yes` confirmed in `/etc/systemd/logind.conf`; brief `systemd-logind` restart is acceptable on this node.

**Command:**

```bash
# 1. Clean up stale files
rm -f /dev/shm/nccl-*

# 2. Prevent systemd from deleting shm mid-training
echo "RemoveIPC=no" >> /etc/systemd/logind.conf
sudo systemctl restart systemd-logind

# 3. For persistence across replacements, add to the lifecycle script:
echo 'echo "RemoveIPC=no" >> /etc/systemd/logind.conf && systemctl restart systemd-logind' \
  >> /opt/ml/scripts/on_create.sh
```

**Blast radius:** `rm -f /dev/shm/nccl-*` silently destroys any active NCCL shared-memory segments — running a collective at the same time will fail. `RemoveIPC=no` is a persistent systemd change; the `systemctl restart` logs out anyone in a systemd user session. Lifecycle-script edit persists across node replacements.

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

### Suggested command — adjust host firewall to allow NCCL traffic (run this yourself)

**Preconditions:** identified a specific iptables/nftables rule blocking NCCL traffic via `iptables -L -n --line-numbers`; confirmed the rule is **not** managed by `kube-proxy` (those typically appear in the `KUBE-*` chains — never delete those) or the VPC CNI; customer has approved either deleting the specific rule or adding an explicit ACCEPT rule for NCCL ports.

**Command (preferred — add explicit allow rather than touch existing rules):**

```bash
# Allow NCCL rendezvous port range:
iptables -I INPUT -p tcp --dport 29400:29500 -j ACCEPT
# Allow the NCCL RAS port if RAS is enabled and used (read your NCCL_RAS_ADDR setting):
# iptables -I INPUT -p tcp --dport <NCCL_RAS_PORT> -j ACCEPT
```

**Command (alternative — delete a specific custom rule by line number):**

```bash
iptables -L -n --line-numbers   # confirm the line number first
iptables -D INPUT <rule_number>
```

**Blast radius:** `iptables -I INPUT ... -j ACCEPT` adds a rule at the top of the INPUT chain — host-wide effect, cleared on reboot unless persisted via `iptables-save`. Deleting a rule by line number is precise but irreversible without the original rule definition; capture `iptables-save` first if you may need to roll back. Never run `iptables -F` on an EKS worker — it flushes `kube-proxy`'s service rules and VPC CNI NetworkPolicy enforcement, breaking pod networking cluster-wide.

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

### Suggested command — raise memlock for EFA RDMA (run this yourself)

**Preconditions:** `ulimit -l` confirmed at 0 / 64 / very low on the affected node; `Call to ibv_reg_mr failed` confirmed in NCCL/EFA logs; customer accepts a session/login change (immediate path) or a persistent change to `/etc/security/limits.conf` (permanent path); for K8s pods the change must be applied in the pod spec, not on the node.

**Command — immediate (session only, lost on logout):**

```bash
ulimit -l 8388608       # 8 GB in KB
```

**Command — permanent (system-wide):**

```bash
echo "* soft memlock 8388608" >> /etc/security/limits.conf
echo "* hard memlock 8388608" >> /etc/security/limits.conf
# Requires re-login to take effect.

# For Slurm:
echo "ulimit -l 8388608" >> /etc/slurm/prolog.sh
```

**Pod spec (K8s) — required for containerized training:**

```yaml
securityContext:
  capabilities:
    add: ["IPC_LOCK"]
# A high memlock limit on the host is not visible inside the container without
# IPC_LOCK; without this capability, the pod still hits memlock=0 / very low.
```

**Blast radius:** session ulimit affects only the current login shell. `/etc/security/limits.conf` change persists across reboots and applies to **every** user who logs in afterwards. Slurm prolog change applies to every job step launched after the edit. K8s pod-spec change is per-pod. For HyperPod, replication across replacement nodes requires baking the limits.conf change into the lifecycle script.

**Note — field observation on large clusters (not NCCL- or AWS-documented):** HyperPod support has seen NCCL topology-graph-search failures on 256+ node clusters when `memlock` is set to `unlimited`. Using a large fixed value (e.g. `8388608`) instead of `unlimited` has cleared these in field cases. If you hit this, engage AWS Support with the NCCL topology-search failure output.

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
export NCCL_PROTO=Simple        # Simple protocol for large-message FSDP comms
# FSDP checkpoint can be slow at scale — extend the PyTorch collective timeout:
#   dist.init_process_group("nccl", timeout=timedelta(seconds=1800))
```

### DeepSpeed

**Common NCCL issues with DeepSpeed:**

| Symptom                                       | Cause                                 | Fix                                                                                                                                                                                                                                        |
| --------------------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `RuntimeError: NCCL communicator was aborted` | Timeout during ZeRO all-gather        | Extend PyTorch collective timeout via `init_process_group(timeout=...)`; check for straggler nodes                                                                                                                                         |
| OOM with ZeRO Stage 3                         | Parameter partitioning + NCCL buffers | Reduce `stage3_max_live_parameters`, enable `offload_optimizer`                                                                                                                                                                            |
| Slow DeepSpeed init on 100+ nodes             | Sequential NCCL group creation        | Set `TORCH_NCCL_ASYNC_ERROR_HANDLING=1` (the older `NCCL_ASYNC_ERROR_HANDLING` was renamed to the `TORCH_NCCL_*` namespace in recent PyTorch; check your PyTorch's `torch.distributed` env-var docs); increase `init_timeout` in ds_config |
| `ncclInternalError` with pipeline parallelism | Cross-node P2P fails                  | Ensure `NCCL_P2P_LEVEL=NVL` for intra-node, check EFA for inter-node                                                                                                                                                                       |

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

| Symptom                                     | Cause                                           | Fix                                                                                                                                             |
| ------------------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Hang at `initialize_model_parallel`         | NCCL group creation fails across nodes          | Verify world size = TP \* PP \* DP, check network connectivity                                                                                  |
| Slow tensor-parallel matmul                 | NCCL all-reduce on small tensors is inefficient | Increase TP group size to stay intra-node (TP ≤ GPUs/node)                                                                                      |
| Pipeline bubble > 40%                       | PP schedule inefficiency                        | Reduce PP stages, increase micro-batches, try interleaved schedule                                                                              |
| `ncclGroupEnd failed` during 3D parallelism | Too many simultaneous NCCL groups               | Cap NCCL channel count for memory-constrained setups — use `NCCL_MAX_CTAS=2` (replaces the older `NCCL_MAX_NCHANNELS`, deprecated in NCCL 2.17) |

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

NVLS is NVIDIA's in-network aggregation over NVLink. Per the NCCL env-var reference, `NCCL_NVLS_ENABLE` defaults to `2` (since NCCL 2.17), meaning NVLS is enabled when supported. It speeds up small-message AllReduce on H100/H200 nodes but **requires matching driver and container versions** — driver/container mismatch is a common cause of NVLS-related hangs in field cases.

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

PXN lets NCCL route inter-node traffic via an intermediary GPU on a different NUMA node to maximize NIC utilization. The documented PXN env var is `NCCL_P2P_PXN_LEVEL` (since NCCL 2.12), which controls PXN usage for send/receive — default is `2` (always use PXN); set `0` to disable. There are also `NCCL_PXN_DISABLE` and `NCCL_PXN_C2C` knobs; consult the NCCL env-var reference for the version in use.

`NCCL_CROSS_NIC` defaults to `2` (per the NCCL docs: "Try to use the same NIC for the same ring/tree, but still allow for the use of different NICs if it would result in a better performance") — leave at default unless you've measured a regression.

```bash
# Tuning knobs — measure before/after with nccl-tests:
export NCCL_P2P_PXN_LEVEL=2     # default; 0 disables PXN

# Channel count: NCCL_MIN_NCHANNELS / NCCL_MAX_NCHANNELS were deprecated in
# NCCL 2.17 in favor of NCCL_MIN_CTAS / NCCL_MAX_CTAS (per NCCL env-var docs).
# Both names still work on recent versions.
export NCCL_MIN_CTAS=4
```

If these cause regressions on smaller jobs (< 16 nodes), unset and re-measure with the defaults.

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

### Mixed instance families

Mixing different P-family generations in a single NCCL communicator (e.g. p4d + p5) is risky — the topology and EFA adapter counts differ, which can cause NCCL algorithm-selection issues. If you need to do this, measure carefully with nccl-tests first; otherwise launch separate jobs per instance family.

### NCCL_COLLNET_ENABLE on EFA

`NCCL_COLLNET_ENABLE=1` enables NVIDIA's Collective Network (CollNet) protocol, used with SHARP on InfiniBand fabrics. EFA is not InfiniBand and does not provide a SHARP-compatible CollNet provider, so leaving CollNet enabled on EFA can lead to wasted init time or fallback. If a job script sets `NCCL_COLLNET_ENABLE=1`, set it to `0` for HyperPod EFA clusters:

```bash
export NCCL_COLLNET_ENABLE=0
```

### Instance family EFA counts (reference)

Counts from authoritative AWS sources where available. Always confirm live with `ls /dev/infiniband/uverbs* | wc -l` on the node — instance counts vary across firmware revisions.

| Instance type | Expected EFA count |
| ------------- | ------------------ |
| p5.48xlarge   | 32                 |
| p5e.48xlarge  | 32                 |
| p5en.48xlarge | 16                 |
| p4d.24xlarge  | 4                  |

For other EFA-supported types (p4de, p5.4xlarge, trn1, trn1n, trn2, etc.), check the current EC2 instance-types doc rather than hard-coding a value here. Mismatch with the live count → EFA driver not loaded, or a subset of NICs didn't attach at boot. Reboot via `batch-reboot-cluster-nodes` first; replace if reboot doesn't recover.

---

## 20. Pending / CrashLoopBackOff / Init-Container Failures

Pod lifecycle failures surface as `Pending`, `CrashLoopBackOff`, or stuck in an init container. These are NOT NCCL bugs per se — they block the NCCL job from starting. Diagnose in this order:

### Pending pods

```bash
# Why is it pending?
kubectl describe pod <POD> -n <NS> | sed -n '/Events:/,$p' | head -40
```

Common reasons and where to fix:

| Event message                                                                  | Root cause                                                                           | Where to fix                                                                                                    |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| `0/N nodes are available: N Insufficient <resource>`                           | Not enough CPU/mem/GPU free                                                          | Wait for other jobs, or scale the cluster                                                                       |
| `0/N nodes are available: N node(s) didn't match Pod's node affinity/selector` | Affinity/selector too strict                                                         | Fix `nodeSelector` / `nodeAffinity` in the pod spec                                                             |
| `0/N nodes are available: N node(s) had untolerated taint`                     | Taints on HyperPod nodes (check `kubectl describe node <N>` for the exact taint key) | Add matching `tolerations` to the pod spec                                                                      |
| `failed to create pod sandbox: ... CNI`                                        | VPC CNI problem                                                                      | Delegate to `hyperpod-node-debugger` § O                                                                        |
| `MountVolume.SetUp failed for volume`                                          | PVC binding issue                                                                    | Check PVC status, StorageClass, EBS/FSx availability                                                            |
| `ImagePullBackOff` / `ErrImagePull`                                            | Container image pull failed                                                          | Check ECR pull permissions on the node role; check image URI; confirm VPC endpoint for ECR if in private subnet |
| (no events; just stuck)                                                        | Scheduler starved or no matching pool                                                | `kubectl get events -A --sort-by=.lastTimestamp \| tail -50` for cluster-wide scheduler state                   |

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

When NCCL aborts or training accuracy regresses without matching Xid/ECC counts — sporadic NaNs, intermittent AllReduce hangs, DCGM default `medium,memtest` passes but a GPU is silently returning bad data — the cause is usually a pending row-remap or a marginal GPU that DCGM's combined-run is masking.

Diagnosis procedure, remap state table, DCGM split-run workaround, and escalation bundle (`nvidia-bug-report.sh` + `/var/log/nvidia-dcgm/`) are in the node-debugger skill: [hyperpod-node-debugger § G.1.a/b](../../hyperpod-node-debugger/references/node-diagnostics-detail.md#g1-nvidia-p4dp5g5g6).
