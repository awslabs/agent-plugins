# Hardware Failure Patterns

Xid codes, gray failures, failure propagation, silent data corruption.
Used in Phase 2B (explicit errors) and 2C (hardware straggler).

## Contents

1. [Xid Error Catalog](#1-xid-error-catalog)
2. [Gray Failures](#2-gray-failures)
3. [How One Degraded GPU Slows the Job](#3-how-one-degraded-gpu-slows-the-job)
4. [Silent Data Corruption](#4-silent-data-corruption)
5. [Failure Frequency at Scale](#5-failure-frequency-at-scale)

---

## 1. Xid Error Catalog

Xid errors are NVIDIA GPU hardware/driver events in `dmesg`.

```bash
dmesg -T | grep 'NVRM: Xid' | tail -20

# Aggregate by code:
dmesg -T | grep 'NVRM: Xid' | awk -F'Xid.*: ' '{print $2}' | \
  sort | uniq -c | sort -rn
```

Common codes on A100/H100/H200 (source:
[NVIDIA Xid Error Catalog](https://docs.nvidia.com/deploy/xid-errors/analyzing-xid-catalog.html)):

| Xid | Mnemonic                       | Meaning                                                   | Action                                         |
| --- | ------------------------------ | --------------------------------------------------------- | ---------------------------------------------- |
| 13  | Graphics Engine Exception      | Usually application; driver/GSP can also present this way | Restart; treat as HW if it recurs on same node |
| 31  | GPU memory page fault (MMU)    | Usually illegal access; persistent = HW                   | Restart; if persistent, reset GPU or drain     |
| 32  | Invalid/corrupted push buffer  | PBDMA fault, often PCIe quality                           | Restart                                        |
| 43  | GPU stopped processing         | Channel reset verification failure                        | Restart                                        |
| 45  | Preemptive cleanup             | Secondary to another Xid; usually benign                  | Follow primary Xid                             |
| 48  | Double-bit ECC error           | Uncorrectable memory error                                | Reset GPU or evict                             |
| 63  | GPU memory remapping event     | Row remap succeeded; monitor                              | Monitor                                        |
| 64  | GPU memory remapping failure   | Row remap failed; HBM exhausted                           | Reset GPU or evict                             |
| 74  | NVLink error                   | Link-level fault                                          | Reset GPU                                      |
| 79  | GPU has fallen off the bus     | PCIe link down                                            | Restart                                        |
| 92  | High single-bit ECC error rate | Corrected errors trending high                            | Monitor, plan replacement                      |
| 94  | Contained memory error         | Application-level containment                             | Restart                                        |
| 95  | Uncontained memory error       | Multi-application impact                                  | Reset GPU                                      |
| 119 | GSP RPC timeout                | GSP unresponsive                                          | Reset GPU                                      |
| 120 | GSP error                      | GSP firmware fault                                        | Reset GPU                                      |

Immediate eviction warranted: **48, 64, 79, 95**. Xid 31 and 94 are
typically application bugs unless recurring on the same node. Xid 63
alone is informational; escalate if Xid 64 follows.

### ECC counts

```bash
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,\
ecc.errors.uncorrected.volatile.total --format=csv
```

- Uncorrected > 0 → evict.
- Corrected rising fast (minutes/hours) → plan replacement.

### Row-remap state

```bash
nvidia-smi --query-remapped-rows=gpu_bus_id,\
remapped_rows.correctable,remapped_rows.uncorrectable,\
remapped_rows.pending,remapped_rows.failure --format=csv
```

`remapped_rows.failure > 0` → spare-row pool exhausted, retire GPU.

---

## 2. Gray Failures

The GPU appears working but is degraded, silently slowing the job.

### Clock mismatch

```bash
nvidia-smi --query-gpu=index,clocks.current.sm,clocks.max.sm --format=csv
```

One GPU at 1,200 MHz while peers report 1,800 MHz → throttled or
clock-locked. Common causes:

- Thermal throttle — check temperature.
- Power cap hit — compare `power.draw` vs `power.limit`.
- Stale frequency lock from a previous diagnostic (e.g. NVIDIA EUD).
- Driver bug.

**Approval required** before a clock-lock workaround:
`nvidia-smi -lgc <min>,<max>` changes runtime state and reduces
throughput until reverted. Revert: `nvidia-smi -rgc`. Address the
underlying cause rather than leaving a lock in place.

### PCIe link degradation

```bash
nvidia-smi --query-gpu=index,pcie.link.width.current,\
pcie.link.width.max,pcie.link.gen.current,pcie.link.gen.max \
  --format=csv
```

Gen x8 when x16 is expected → half the NIC/host bandwidth; throttles
data transfers and can cascade as network congestion.

### Rising correctable ECC

Correction adds latency. A GPU with rapidly rising correctable counts
is slower than peers and will eventually fail uncorrectably.

```bash
watch -n 10 'nvidia-smi --query-gpu=index,\
ecc.errors.corrected.volatile.total --format=csv'
```

---

## 3. How One Degraded GPU Slows the Job

Synchronized collectives (all-reduce, all-gather, reduce-scatter)
require every rank to finish before any rank proceeds.

```
Healthy:
  GPU 0: compute 10 ms → all-reduce 5 ms → next step = 15 ms
  GPU 1: compute 10 ms → all-reduce 5 ms → next step = 15 ms

One degraded GPU (3.6× slower):
  GPU 0: compute 10 ms → WAIT 40 ms  → all-reduce 5 ms = 55 ms
  GPU 1: compute 50 ms ─────────────→ all-reduce 5 ms = 55 ms
```

Straggler detection is the highest-leverage MFU debugging skill.

---

## 4. Silent Data Corruption

A faulty GPU produces incorrect results without raising an error.
Corrupted values propagate through collectives to every rank.

### Spread

1. Faulty GPU computes an incorrect gradient.
2. All-reduce mixes the corrupted gradient into every rank.
3. All ranks apply a wrong update.
4. Error compounds across steps.
5. Eventually manifests as NaN loss or divergent training.
6. The source GPU is usually unidentifiable from training metrics
   alone by the time corruption is noticed.

### Signals

- NaN/Inf loss with no logged errors.
- Loss diverging from expected trajectory.
- Gradient-norm spikes without obvious cause.
- Bitwise mismatch between replicated computations.

### Proactive detection

```bash
# DCGM level 4 (most thorough; 8+ hours). Drain first:
#   Slurm: scontrol update nodename=<node> state=drain
#   EKS:   kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets
# Revert: state=resume or kubectl uncordon.
dcgmi diag -r 4

nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total --format=csv
```

### Isolation when source is unknown

1. Split the job across disjoint node subsets.
2. Run each for several hundred steps.
3. The subset producing incorrect results contains the faulty node.
4. Binary-search within the subset.
5. Drain the node and run DCGM -r 4 offline.

### Recovery

- Roll back before corruption started. Corruption may predate the
  first NaN; inspect the loss trajectory for the first divergence.

---

## 5. Failure Frequency at Scale

At thousands of GPUs, hardware failures are continuous rather than
rare.

The public reference is Meta's Llama 3 paper: a 54-day pre-training
snapshot on 16,384 H100 GPUs, 466 interruptions, 419 unexpected
(Table 5, Grattafiori et al. 2024). ~78% of unexpected interruptions
were confirmed or suspected hardware:

| Category                   | Share of unexpected interruptions |
| -------------------------- | --------------------------------- |
| Faulty GPUs                | 30.1%                             |
| GPU HBM3 memory            | 17.2%                             |
| Software bugs              | 12.9%                             |
| Network switch/cable       | 8.4%                              |
| Unplanned host maintenance | 7.6%                              |

These are Meta's cluster and software stack — illustrative, not a
HyperPod expectation. Real rates vary by instance family, cluster
size, job duration, and operational tooling.

Averaged to ~1 unexpected interruption every 3 hours on 16K GPUs.
Meta reported > 90% effective training time despite this.

Operator implications at similar scale:

- Automate detection; manual diagnosis costs tens of minutes to hours.
- Checkpoint frequently; every minute of recompute is lost MFU.
- Keep pre-validated spare nodes ready for fast replacement.
- Simple automated responses (restart, evict-and-replace) resolve
  most failures faster than human investigation.
- A single throttled or slow GPU can reduce throughput several-fold
  (§3).

---

## References

**Xid (§1):**

- NVIDIA Xid Error Catalog:
  https://docs.nvidia.com/deploy/xid-errors/analyzing-xid-catalog.html
- A100 Memory Error Management (Xid 63/64 details):
  https://docs.nvidia.com/deploy/a100-gpu-mem-error-mgmt/index.html
- `nvidia-smi` reference (ECC, remapped-rows fields):
  https://docs.nvidia.com/deploy/nvidia-smi/index.html
- AWS re:Post on Xid troubleshooting:
  https://repost.aws/knowledge-center/ec2-linux-troubleshoot-xid-errors

**Gray failures / stragglers (§2, §3):**

- "Impact of GPU Thermal Throttling on LLM Training" (one throttled
  GPU can reduce throughput ~5×):
  https://jingchaozhang.github.io/Thermal-Throttling-Impact-on-Multi-Node-Training/
- Llama 3 §5.1 on stragglers (Grattafiori et al. 2024):
  https://ai.meta.com/research/publications/the-llama-3-herd-of-models/

**SDC (§4):**

- "Silent Data Corruptions at Scale" (Meta, SIGMETRICS 2021):
  https://arxiv.org/abs/2102.11245
- Google SDC research: https://research.google/pubs/pub50906/
- DCGM diagnostic levels:
  https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/dcgm-diagnostics.html

**Failure rates (§5):**

- Grattafiori et al., "The Llama 3 Herd of Models" (Meta 2024),
  Table 5:
  https://ai.meta.com/research/publications/the-llama-3-herd-of-models/
- ByteDance ByteRobust (200K-GPU reliability):
  https://arxiv.org/abs/2509.16293
- MegaScale 10K+ GPU reliability (Jiang et al., NSDI 2024):
  https://www.usenix.org/conference/nsdi24/presentation/jiang-ziheng
