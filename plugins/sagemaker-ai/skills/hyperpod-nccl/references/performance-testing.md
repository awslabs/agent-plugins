# NCCL Performance Testing & Straggler Detection

Reference guide for measuring NCCL bandwidth and identifying slow nodes.

Official awslabs guide:
https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/validation-and-testing/performance-testing/nccl-tests

## Table of Contents

| Section                                                                                  | Use When                                     |
| ---------------------------------------------------------------------------------------- | -------------------------------------------- |
| [Install nccl-tests](#install-nccl-tests-once-per-cluster)                               | First-time setup                             |
| [Single-Node Baseline Test](#single-node-baseline-test)                                  | Verify one node is healthy before multi-node |
| [Multi-Node AllReduce Test](#multi-node-allreduce-test)                                  | Validate cluster-wide NCCL                   |
| [Pairwise Bandwidth Test](#pairwise-bandwidth-test-identify-slow-pairs)                  | Find which node pair is slow                 |
| [NCCL_DEBUG_FILE Analysis](#nccl_debug_file-analysis)                                    | Identify lagging rank from logs              |
| [NCCL_TIMEOUT Scaling](#nccl_timeout-scaling)                                            | Tune timeout for large clusters              |
| [NCCL_DEBUG=INFO Performance Impact](#nccl_debuginfo-performance-impact)                 | Debug logging slowing training               |
| [EFA Performance Settings](#efa-performance-settings)                                    | Optimal EFA env vars                         |
| [Straggler Node — Detection and Replacement](#straggler-node--detection-and-replacement) | Drain and replace slow node                  |

---

## Install nccl-tests (once per cluster)

```bash
# On each compute node (add to lifecycle script for persistence):
git clone https://github.com/NVIDIA/nccl-tests /opt/nccl-tests
cd /opt/nccl-tests
make MPI=1 \
     MPI_HOME=/usr/local/mpi \
     NCCL_HOME=/usr/local/nccl \
     CUDA_HOME=/usr/local/cuda
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

**Expected minimum bandwidth (algbw column):**

| Instance Type | GPUs         | Expected algbw | EFA Bandwidth |
| ------------- | ------------ | -------------- | ------------- |
| p4d.24xlarge  | 8x A100      | ≥ 86 GB/s      | 400 Gbps      |
| p5.48xlarge   | 8x H100      | ≥ 300 GB/s     | 3200 Gbps     |
| p3dn.24xlarge | 8x V100      | ≥ 50 GB/s      | 100 Gbps      |
| trn1.32xlarge | 16x Trainium | ≥ 50 GB/s      | 800 Gbps      |
| g5.48xlarge   | 8x A10G      | ≥ 10 GB/s      | 100 Gbps      |

If below 50% of expected: node is a straggler → drain and replace.

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
# Use mpirun inside the container or the MPI Operator:
# See: https://github.com/kubeflow/mpi-operator
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

## NCCL_TIMEOUT Scaling

Default `NCCL_TIMEOUT=600` (10 minutes). Too low for large clusters.

| Cluster Size  | Recommended NCCL_TIMEOUT |
| ------------- | ------------------------ |
| 2–16 GPUs     | 600s (default)           |
| 17–64 GPUs    | 1200s                    |
| 65–256 GPUs   | 1800s                    |
| 257–1024 GPUs | 3600s                    |
| 1024+ GPUs    | 7200s                    |

**Formula:** `NCCL_TIMEOUT = node_count * 5 + 600`

```bash
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
export NCCL_TIMEOUT=$(( NODE_COUNT * 5 + 600 ))
echo "Setting NCCL_TIMEOUT=$NCCL_TIMEOUT for $NODE_COUNT nodes"
```

---

## NCCL_DEBUG=INFO Performance Impact

**Never leave `NCCL_DEBUG=INFO` in production:**

| Setting                     | Performance Impact                 |
| --------------------------- | ---------------------------------- |
| `NCCL_DEBUG=WARN` (default) | 0% overhead                        |
| `NCCL_DEBUG=INFO`           | 10–30% overhead                    |
| `NCCL_DEBUG=TRACE`          | 50–80% overhead, gigabytes of logs |

Use `INFO` only for debugging, then set back to `WARN`.

---

## EFA Performance Settings

```bash
# Full EFA performance configuration:
export FI_PROVIDER=efa
export FI_EFA_USE_DEVICE_RDMA=1    # GPU Direct RDMA (30-50% faster)
export NCCL_PROTO=simple           # optimal for EFA (vs tree/ring)
export NCCL_SOCKET_IFNAME=^lo,docker,efa,veth
export NCCL_TIMEOUT=1800

# Optional tuning for very large jobs:
export FI_EFA_FORK_SAFE=1          # safe for multiprocessing
export FI_EFA_ENABLE_SHM_TRANSFER=1  # intra-node shared memory

# Do NOT set in production:
# NCCL_DEBUG=INFO  (10-30% overhead)
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

```bash
# 1. Identify the bad node's instance ID:
kubectl get node <NODE_NAME> -o jsonpath='{.spec.providerID}' | cut -d'/' -f5
# OR for Slurm:
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query "ClusterNodeSummaries[?PrivateDnsHostname=='<SLURM_NODE_NAME>'].InstanceId" \
  --output text

# 2. Drain it (EKS):
kubectl cordon <NODE_NAME>
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data

# 3. Drain it (Slurm):
scontrol update nodename=<NODE> state=drain reason="low-bandwidth-$(date +%Y%m%d)"

# 4. Replace via HyperPod:
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["<INSTANCE_ID>"]'

# 5. Monitor replacement completion:
watch -n 10 "aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,State:InstanceStatus.Status}' \
  --output table"
```
