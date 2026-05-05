# Node-Level Diagnostics

Per-node health via `hyperpod-ssm` `ssm-exec.sh`. Each section lists
the command, expected output, and problem conditions.

## Contents

1. [GPU Health](#1-gpu-health)
2. [Thermal](#2-thermal)
3. [Memory Pressure](#3-memory-pressure)
4. [Data Pipeline and Storage](#4-data-pipeline-and-storage)
5. [System Checks](#5-system-checks)

---

## Running Across Multiple Nodes

Most diagnoses require cross-node comparison. Use
`hyperpod-issue-report` for automated collection, or loop manually:

```bash
scripts/list-nodes.sh <CLUSTER_NAME> --region <REGION>

for target in <TARGET_1> <TARGET_2> <TARGET_3>; do
  echo "=== $target ==="
  scripts/ssm-exec.sh --target "$target" \
    'nvidia-smi --query-gpu=index,clocks.current.sm,temperature.gpu --format=csv' \
    --region <REGION>
done
```

The node whose output differs from the majority is the suspect.

---

## 1. GPU Health

### Status

```bash
nvidia-smi
```

Inspect utilization, memory, temperature, and processes.

### Per-GPU metrics

```bash
nvidia-smi --query-gpu=index,name,temperature.gpu,\
clocks.current.sm,clocks.max.sm,power.draw,power.limit,\
pcie.link.width.current,pcie.link.width.max,\
ecc.errors.uncorrected.volatile.total,ecc.errors.corrected.volatile.total,\
memory.used,memory.total --format=csv
```

| Condition                              | Meaning                                       |
| -------------------------------------- | --------------------------------------------- |
| `clocks.current.sm` ≪ `clocks.max.sm`  | Throttled (thermal, power cap, or clock lock) |
| `ecc.errors.uncorrected > 0`           | Memory corruption — evict                     |
| `ecc.errors.corrected` rising fast     | HBM degrading; failure imminent               |
| `pcie.link.width.current = 8` (max 16) | Halved PCIe bandwidth                         |

### Throttle reasons

```bash
nvidia-smi --query-gpu=index,\
clocks_event_reasons.hw_slowdown,\
clocks_event_reasons.hw_thermal_slowdown,\
clocks_event_reasons.sw_thermal_slowdown,\
clocks_event_reasons.sw_power_cap --format=csv
```

Any `Active` value = active throttling.

### HBM row remapping

```bash
nvidia-smi --query-remapped-rows=gpu_bus_id,\
remapped_rows.correctable,remapped_rows.uncorrectable,\
remapped_rows.pending,remapped_rows.failure --format=csv
```

`remapped_rows.failure > 0`: remap pool exhausted — retire the GPU.

### NVLink

```bash
nvidia-smi nvlink -s   # throughput
nvidia-smi nvlink -e   # errors (non-zero = degraded link)
```

### DCGM (when installed)

```bash
dcgmi discovery -l
dcgmi health -c        # safe during training
dcgmi diag -r 3        # ~10 minutes
# dcgmi diag -r 4      # 8+ hours, SDC detection
```

**Prerequisite for `-r 3` and `-r 4`**: drain first. These levels hold
the GPU and conflict with training.

- Slurm: `scontrol update nodename=<node> state=drain` — revert with
  `state=resume`.
- EKS: `kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets`
  — revert with `kubectl uncordon`.

For monitoring, deploy
[dcgm-exporter](https://github.com/NVIDIA/dcgm-exporter) into
Prometheus/Grafana.

### Topology

```bash
nvidia-smi topo -m
```

Verify TP groups are placed on NVLink-connected GPUs.

---

## 2. Thermal

### Collect across nodes

```bash
nvidia-smi --query-gpu=index,temperature.gpu,clocks.current.sm \
  --format=csv,noheader
```

### Thresholds (H100 SXM5, from NVIDIA DGX H100 User Guide)

| Threshold                     | H100 SXM5 | Behavior                           |
| ----------------------------- | --------- | ---------------------------------- |
| GPU Target Temperature        | 83 °C     | Fan target; no clock impact        |
| GPU Max Operating Temperature | 88 °C     | Software throttle (reduced clocks) |
| GPU Slowdown Temperature      | 92 °C     | Hardware throttle                  |
| GPU Shutdown Temperature      | ~105 °C   | GPU shuts down                     |

Operational ranges:

| Temperature | Status     | Impact                                 |
| ----------- | ---------- | -------------------------------------- |
| < 75 °C     | Normal     | None                                   |
| 75–83 °C    | Warm       | Monitor                                |
| 83–88 °C    | Hot        | Inspect for cooling drift              |
| 88–92 °C    | Throttling | Software throttle; node is a straggler |
| > 92 °C     | Critical   | Hardware throttle; shutdown risk       |

Confirm thermal throttling is causing MFU loss by correlating the hot
node's per-rank step time against healthy peers.

### Remediation

The first two options change runtime state and reduce throughput on
the affected node until reverted. Present and wait for approval.

| Timeframe  | Action                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Short-term | **Approval required.** `nvidia-smi -pl <watts>` caps power. Default from `nvidia-smi -q -d POWER`; revert with `nvidia-smi -pl <default_watts>`. |
| Short-term | **Approval required.** `nvidia-smi -lgc <min>,<max>` locks SM clocks. Revert: `nvidia-smi -rgc`.                                                 |
| Short-term | Investigate rack cooling at the node's location.                                                                                                 |
| Long-term  | Drain and replace chronically hot nodes.                                                                                                         |

In synchronized training, a capped GPU paces the job — overall
throughput tracks the capped node until reverted.

---

## 3. Memory Pressure

### GPU memory

```bash
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv
```

Usage > 95% of total → fragmentation and OOM risk.

### Fragmentation (in training code)

```python
stats = torch.cuda.memory_stats()
active = stats['active_bytes.all.peak']
reserved = stats['reserved_bytes.all.peak']
print(f"Active: {active/1e9:.1f} GB, Reserved: {reserved/1e9:.1f} GB")
print(f"Fragmentation: {1 - active/reserved:.1%}")
# > 20% is significant.
```

### Host memory

```bash
free -h             # any swap during training is a problem
vmstat 1 5          # si/so > 0 = active swapping
```

### Remediation

| Problem                 | Action                                                      |
| ----------------------- | ----------------------------------------------------------- |
| GPU near capacity       | Reduce micro-batch; enable selective gradient checkpointing |
| GPU fragmentation > 20% | See note below                                              |
| Host swap active        | Reduce DataLoader workers; check preprocessing for leaks    |
| Host OOM                | Verify optimizer-state sharding is active                   |

`torch.cuda.empty_cache()` is a code change, not a diagnostic. It
releases cached memory to the driver; in some allocator configurations
this increases pressure and triggers an OOM on the next step. For
fragmentation, prefer `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`
and reduce peak allocation patterns. Validate any change off a
production workload.

---

## 4. Data Pipeline and Storage

GPUs idle waiting for data → periodic dips or consistently low MFU.

### Disk and filesystem

```bash
df -h                                     # check root and data volumes
lfs df -h /fsx 2>/dev/null                # FSx for Lustre
lctl get_param llite.*.stats 2>/dev/null | head -30
```

> 90% full: checkpoint writes fail; loading may stall.

### Disk I/O

```bash
iostat -x 1 5
# Indicators: await > 10 ms, %util > 80, r/s or w/s flat at device max
```

### DataLoader throughput

Temporary in the training script:

```python
import time
for i, batch in enumerate(dataloader):
    if i == 0:
        start = time.time()
    if i == 100:
        print(f"DataLoader: {100/(time.time()-start):.1f} batches/sec")
        break
```

Throughput < 1.5× the training step rate → data loading is the
bottleneck.

### Remediation

| Problem                 | Action                                                                              |
| ----------------------- | ----------------------------------------------------------------------------------- |
| Slow shared filesystem  | Stage data to local NVMe                                                            |
| Disk full               | Remove old checkpoints; grow the volume                                             |
| DataLoader too slow     | Raise `num_workers` (4–8 per GPU); set `pin_memory=True`, `persistent_workers=True` |
| Tokenization bottleneck | Pre-tokenize offline                                                                |

---

## 5. System Checks

### Processes

```bash
ps aux --sort=-%cpu | head -20
```

### Kernel messages

```bash
dmesg -T | tail -50
dmesg -T | grep -ciE 'error|fault|xid|efa|pcie|nvlink|ecc'
```

Non-zero count warrants investigation.

### Slurm node state

```bash
sinfo -N -l | grep <node>
scontrol show node <node>
# Inspect State, Reason, RealMemory, AllocTRES
```

### EKS node state

```bash
kubectl describe node <node-name>
# Conditions: MemoryPressure, DiskPressure, PIDPressure; compare Allocated vs Capacity
kubectl get pods -A --field-selector spec.nodeName=<node-name>
```

---

## References

**`nvidia-smi` and NVML (§1, §2, §3):**

- `nvidia-smi` user guide: https://docs.nvidia.com/deploy/nvidia-smi/index.html
- NVML throttle-reasons enumeration:
  https://docs.nvidia.com/deploy/nvml-api/group__nvmlClocksThrottleReasons.html

**DCGM (§1):**

- DCGM: https://github.com/NVIDIA/DCGM
- Diagnostic levels:
  https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/dcgm-diagnostics.html
- dcgm-exporter: https://github.com/NVIDIA/dcgm-exporter

**Thermal thresholds (§2):**

- NVIDIA DGX H100/H200 power-capping and thresholds:
  https://docs.nvidia.com/dgx/dgxh100-user-guide/power-capping.html
- NVIDIA developer forum on `GPU Target / Max Operating / Slowdown`:
  https://forums.developer.nvidia.com/t/nvidia-smi-gpu-target-temperature-maximum-operating-temperature/229325
- Hopper architecture deep dive:
  https://developer.nvidia.com/blog/nvidia-hopper-architecture-in-depth/

**HBM row remapping (§1):**

- A100 GPU Memory Error Management Guide:
  https://docs.nvidia.com/deploy/a100-gpu-mem-error-mgmt/index.html

**PyTorch memory (§3):**

- `torch.cuda.memory_stats()`:
  https://docs.pytorch.org/docs/stable/generated/torch.cuda.memory.memory_stats.html
- CUDA semantics and allocator:
  https://docs.pytorch.org/docs/stable/notes/cuda.html

**FSx for Lustre (§4):**

- FSx mount on HyperPod:
  https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-lifecycle-best-practices-slurm-slurm-setup-with-fsx.html
- FSx for Lustre best practices:
  https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/common/tips/Fsx%20for%20Lustre%20best%20practices
- Lustre client statistics:
  https://doc.lustre.org/lustre_manual.xhtml

**System tools (§5):**

- `iostat(1)`: https://man7.org/linux/man-pages/man1/iostat.1.html
- `mpstat(1)`, `vmstat(8)`: https://man7.org/linux/man-pages/man1/mpstat.1.html
- Slurm `sinfo`, `scontrol`:
  https://slurm.schedmd.com/sinfo.html, https://slurm.schedmd.com/scontrol.html
- Kubernetes node conditions:
  https://kubernetes.io/docs/concepts/architecture/nodes/#condition
