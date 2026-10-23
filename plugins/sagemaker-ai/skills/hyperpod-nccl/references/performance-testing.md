# NCCL Performance Testing & Straggler Detection

Measure NCCL bandwidth and identify slow nodes.

---

## Install nccl-tests (once per cluster)

```bash
# On each compute node (add to lifecycle script for persistence). Source: NVIDIA nccl-tests.
cd /opt && git clone <nccl-tests-source> nccl-tests
cd /opt/nccl-tests
make MPI=1 MPI_HOME=/usr/local/mpi NCCL_HOME=/usr/local/nccl CUDA_HOME=/usr/local/cuda
# Binary: /opt/nccl-tests/build/all_reduce_perf
```

---

## Single-Node Baseline Test

Run first to confirm the node itself is healthy before multi-node tests.

```bash
# Single-GPU test (quick sanity check):
/opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 1

# All-GPU test (p4d: 8 GPUs, p5: 8 GPUs):
/opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 8

# Expected output column headers:
# size  count  type  redop  root  time  algbw  busbw  error  time  algbw  busbw
```

**How to identify stragglers:** there is no single published GB/s threshold that applies across EFA generations, NCCL versions, and test message sizes. Run `all_reduce_perf` on **every** node against a known-good peer and compare the `busbw` (bus bandwidth) column. The outliers in the bottom quartile at the same message size are the stragglers. For reference workflow and exact test command, see the AWS EC2 EFA + NCCL getting-started doc. Also compare against the results of a recent known-good run on the same instance type and NCCL version — hardware generations differ widely and a static table rots quickly.

---

## Multi-Node AllReduce Test

```bash
# With MPI (from head node):
mpirun -np <TOTAL_RANKS> \
  --hostfile /etc/hosts \
  -N <RANKS_PER_NODE> \
  -x FI_PROVIDER=efa \
  -x FI_EFA_USE_DEVICE_RDMA=1 \
  -x NCCL_SOCKET_IFNAME=^lo,docker,efa,veth \
  -x NCCL_DEBUG=WARN \
  /opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 1

# With Slurm:
srun --nodes=4 --ntasks-per-node=8 \
  /opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 1

# With kubectl (EKS, 2 nodes, 8 GPUs each):
# Deploy as a K8s Job with 2 pods, each requesting 8 GPUs.
# Use mpirun inside the container, or the Kubeflow MPI Operator.
kubectl exec -n <NS> <POD> -- mpirun -np 16 -N 8 \
  --hostfile /etc/hosts \
  -x FI_PROVIDER=efa -x FI_EFA_USE_DEVICE_RDMA=1 \
  /opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 1
```

---

## Pairwise Bandwidth Test (identify slow pairs)

```bash
# Test each node pair individually to find the outlier:
# From node A → node B:
fi_ping -p efa -I 100 <NODE_B_IP>

# From node B → node A:
fi_ping -p efa -I 100 <NODE_A_IP>

# Automate across all pairs (run on head node):
for node in $(scontrol show hostnames $SLURM_JOB_NODELIST); do
    echo -n "Testing $node: "
    fi_ping -p efa -I 10 "$node" 2>/dev/null | tail -1 || echo "FAILED"
done
```

**Interpreting fi_ping output:**

- Normal: < 5 microseconds latency, consistent
- Straggler: > 50 microseconds, or high variance across runs

---

## NCCL_DEBUG_FILE Analysis

```bash
# Enable per-rank debug files:
export NCCL_DEBUG=INFO
export NCCL_DEBUG_FILE=/tmp/nccl_rank${RANK}.log

# After training (or timeout), check which rank was slow:
# Look for the last "AllReduce" timestamp before the timeout:
grep -h "AllReduce\|ring\|timeout" /tmp/nccl_rank*.log | sort -k1,1 | tail -30

# Compare timestamps across ranks — the one furthest behind is the straggler:
for f in /tmp/nccl_rank*.log; do
    echo -n "$f: last line timestamp = "
    tail -1 "$f" | awk '{print $1, $2}'
done
```

---

## Collective-op timeout scaling

PyTorch's `init_process_group` default timeout for NCCL is **10 minutes (600 s)**. Too low for large clusters — a slow rank or straggler can blow past 10 min during warm-up or a large all-gather.

Scale up via the `timeout` argument (NOT via a `NCCL_TIMEOUT` env var — that is not a standard NCCL or PyTorch variable):

```python
import datetime
import torch.distributed as dist

# nodes * 5 + 600 is a simple heuristic — tune against your actual step time:
nodes = int(os.environ.get("WORLD_SIZE", "1")) // 8   # GPUs per node
timeout_s = nodes * 5 + 600

dist.init_process_group(
    backend="nccl",
    timeout=datetime.timedelta(seconds=timeout_s),
)
```

Field-observed starting points (not AWS- or PyTorch-prescribed; tune from your actual step time and slowest collective):

| Cluster size  | Starting point                   |
| ------------- | -------------------------------- |
| 2–16 GPUs     | 600 s (PyTorch default for NCCL) |
| 17–64 GPUs    | 1200 s                           |
| 65–256 GPUs   | 1800 s                           |
| 257–1024 GPUs | 3600 s                           |
| 1024+ GPUs    | 7200 s                           |

To surface hangs as Python exceptions instead of silently waiting, also set:

```bash
export TORCH_NCCL_ASYNC_ERROR_HANDLING=1
export TORCH_NCCL_BLOCKING_WAIT=1   # for debugging; has a perf cost at scale
```

---

## NCCL_DEBUG=INFO Performance Impact

**Never leave `NCCL_DEBUG=INFO` in production.** The NCCL env-var reference describes `TRACE` as printing "replayable trace information on every call" but does not publish overhead percentages. Field experience on HyperPod is:

| Setting                     | Notes                                                                   |
| --------------------------- | ----------------------------------------------------------------------- |
| `NCCL_DEBUG=WARN` (default) | Negligible overhead                                                     |
| `NCCL_DEBUG=INFO`           | Measurable runtime overhead and verbose logs — disable in production    |
| `NCCL_DEBUG=TRACE`          | Per-call trace; very large log volume, only for short debugging windows |

Use `INFO` / `TRACE` only for debugging, then set back to `WARN`. Measure your own overhead before and after if it matters for the workload.

---

## EFA Performance Settings

```bash
# Full EFA performance configuration:
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1    # GPU Direct RDMA
export NCCL_PROTO=Simple           # large-message protocol (valid: LL, LL128, Simple)
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth
# Collective timeout goes in training code: init_process_group(timeout=timedelta(seconds=1800))

# Optional tuning for very large jobs:
export FI_EFA_FORK_SAFE=1            # safe for multiprocessing
export FI_EFA_ENABLE_SHM_TRANSFER=1  # intra-node shared memory

# Do NOT set in production:
# NCCL_DEBUG=INFO  (verbose; runtime overhead — disable in production)
# CUDA_LAUNCH_BLOCKING=1  (disables GPU/CPU overlap, very slow)
```

---

## Straggler Node — Detection and Replacement

### Detection workflow

1. **Run nccl-tests** across all nodes — compare algbw values
2. **Check nvidia-smi nvlink -e** for NVLink error counters
3. **Check dmesg** for XID errors, hardware failures
4. **Compare fi_ping latency** pairwise — outlier has degraded EFA port

### Replacement workflow

Diagnose (read-only):

```bash
# Identify the bad node's instance ID:
kubectl get node <NODE_NAME> -o jsonpath='{.spec.providerID}' | cut -d'/' -f5
# OR for Slurm — list-cluster-nodes does NOT return PrivateDnsHostname (only describe-cluster-node does).
# Two-step: list candidate IDs, then describe each one until DNS matches the Slurm name.
SLURM_NODE="<SLURM_NODE_NAME>"
for IID in $(aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
               --query 'ClusterNodeSummaries[?InstanceStatus.Status==`Running`].InstanceId' --output text); do
  DNS=$(aws sagemaker describe-cluster-node --cluster-name <C> --region <R> --node-id "$IID" \
          --query 'NodeDetails.PrivateDnsHostname' --output text 2>/dev/null)
  case "$DNS" in "$SLURM_NODE."*) echo "$SLURM_NODE → $IID"; break ;; esac
done
```

### Suggested command — drain the straggler node before reboot/replace (run this yourself)

**Preconditions:** straggler behavior confirmed across **multiple** nccl-tests runs (single-run outliers can be transient — don't drain on one bad sample); customer accepts that pods using `emptyDir` volumes on this node will lose that data when evicted (EKS path); on Slurm, customer accepts that no new jobs will be scheduled to the node until `state=resume` runs after recovery; drain is preparation for reboot/replace, not a fix on its own.

**Command:**

```bash
# EKS — cordon prevents new pods; drain evicts existing pods (emptyDir data lost).
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data

# Slurm — on the controller via SSM; running jobs continue until they finish.
scontrol update nodename=<NODE> state=drain reason="low-bandwidth-$(date +%Y%m%d)"
```

**Blast radius:** EKS — `--delete-emptydir-data` discards `emptyDir` scratch on this node; pods are rescheduled elsewhere if capacity exists, otherwise stay Pending. Slurm — running jobs finish on the node; pending jobs route around it. Drain is reversible (`kubectl uncordon` / `scontrol update state=resume`) only if you decide not to proceed with reboot/replace.

See [hyperpod-cluster-debugger § G.2](../../hyperpod-cluster-debugger/references/cluster-diagnostics-detail.md#g2-manual-replacement) for the reboot-before-replace ordering.

### Suggested command — replace the node (run this yourself, only after reboot did not clear the fault)

**Preconditions:** reboot was tried first and did not clear the fault (see [hyperpod-cluster-debugger § G.2](../../hyperpod-cluster-debugger/references/cluster-diagnostics-detail.md#g2-manual-replacement)). Data on root + secondary volumes is backed up. Not supported on Slurm controller nodes. `NodeIds` batch: 1-25 per call.

**Command:**

```bash
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["<INSTANCE_ID>"]'

# Monitor replacement completion (read-only):
watch -n 10 "aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,State:InstanceStatus.Status}' \
  --output table"
```

**Blast radius:** destroys root + secondary volumes on the replaced instance — all data permanently lost. New hardware is provisioned with the same AMI.
