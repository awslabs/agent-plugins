# Step 2C: Hardware Failure or Straggler

A single degraded node in synchronized training drags all nodes to its
speed. One node at 20% performance produces a whole-job MFU of 20%.

## Step 1: Identify the straggler

Extract per-rank step times from training logs. Most frameworks emit a
line per iteration containing, for example, `step_time=0.45s`.

```bash
# Pull step times from a log and identify outlier ranks.
grep -oP 'rank[=: ]*\K\d+|step_time[=: ]*\K[0-9.]+' "/path/to/train.log"
```

If the framework does not emit per-rank step times, add lightweight
logging:

```python
import time
import os

rank = int(os.environ.get('RANK', 0))
elapsed = time.time() - step_start
if step % 10 == 0:
    print(f"rank={rank} step={step} step_time={elapsed:.4f}")
```

Ranks whose step time exceeds `mean + 2 × stddev` are outliers.

## Step 2: Map rank to node

`node_id = rank // gpus_per_node` (typically 8).

## Step 3: Inspect the suspect node

Run the following via SSM:

```bash
# GPU clocks: compare against a healthy node.
nvidia-smi --query-gpu=index,clocks.current.sm,clocks.max.sm,\
clocks_event_reasons.hw_slowdown,clocks_event_reasons.hw_thermal_slowdown,\
clocks_event_reasons.sw_power_cap --format=csv

# NVLink errors
nvidia-smi nvlink -e

# Intra-node GPU bandwidth (when nccl-tests is installed)
/path/to/nccl-tests/build/all_reduce_perf -b 8 -e 128M -f 2 -g 8

# EFA device count and port state
fi_info -p efa | grep -c 'provider: efa'
cat /sys/class/infiniband/*/ports/1/state
```

## Step 4: Compare metrics across nodes

Run the same commands on a healthy node. The faulty node diverges.
Inspect in this order, most-sensitive first:

| # | Metric          | Command (via SSM)                                              | Problem indicator                      |
| - | --------------- | -------------------------------------------------------------- | -------------------------------------- |
| 1 | CPU usage       | `mpstat 1 3`                                                   | One node near 0% while others are busy |
| 2 | GPU SM clock    | `nvidia-smi --query-gpu=index,clocks.current.sm --format=csv`  | Lower than peers                       |
| 3 | GPU power draw  | `nvidia-smi --query-gpu=index,power.draw --format=csv`         | Significantly lower or higher          |
| 4 | GPU duty cycle  | `nvidia-smi dmon -s u -c 5`                                    | Lower utilization than peers           |
| 5 | NVLink errors   | `nvidia-smi nvlink -e`                                         | Non-zero counters                      |
| 6 | EFA port errors | `cat /sys/class/infiniband/*/ports/1/counters/port_rcv_errors` | Non-zero                               |

A single anomalous metric that persists for several minutes confirms
the faulty node. Transient 1-to-2-second spikes are jitter and should
be ignored.

## Step 5: Evict and replace

**Approval required.** The commands below change cluster state and
will terminate any workload running on the affected node. Present
them to the user and wait for explicit confirmation before running.
Approval for earlier diagnostic steps does not carry over to this
step.

### Slurm

```bash
# Drain the node (new jobs will not be scheduled; existing jobs continue
# until they complete or are cancelled):
scontrol update nodename=<node> state=drain reason="MFU straggler"

# After replacement, return the node to service:
scontrol update nodename=<node> state=resume
```

### EKS

```bash
# Mark the node unschedulable:
kubectl cordon <node-name>

# Evict pods safely. --ignore-daemonsets leaves node-level DaemonSets
# in place; --delete-emptydir-data acknowledges that emptyDir volumes
# (including /dev/shm) on this node will be lost; increase
# --grace-period for pods that need time to checkpoint cleanly.
kubectl drain <node-name> \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# After replacement, return the node to service:
kubectl uncordon <node-name>
```

Once the node is drained, restart training from the latest checkpoint.

## Further Reading

- `../network-and-comms.md` — EFA diagnosis and NCCL debugging.
- `../failure-patterns.md` — gray-failure signatures and Xid catalog.
- `../node-diagnostics.md` — detailed GPU health checks.

---

## If this was not the root cause

If no single node stands out on any metric:

- `2f-network.md` — when variance is high but no single node is
  consistently slow.
- `2d-gradual.md` — when the drop is actually gradual rather than a
  step function.
- `2b-errors.md` — when errors appeared on any node during the sweep.
