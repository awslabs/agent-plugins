# Node Issue Catalog

Patterns seen in real customer cases. Each entry: symptoms → root cause → diagnostic → fix. For the full remediation procedures see [node-diagnostics-detail.md](node-diagnostics-detail.md); this catalog is the quick-pattern lookup.

---

## 1. EFA

### 1.1 Primary EFA health-check failure

Covered in [node-diagnostics-detail.md § A](node-diagnostics-detail.md#a-efa--security-group).

### 1.2 EFA not working after node replacement

**Symptoms:** Training hangs at NCCL init after replacing one or more nodes; `fi_info -p efa` returns no providers on the replacement; other nodes work.

**Root cause:** EFA driver not loaded, or version drift after an AMI update.

```bash
# On the affected node (via SSM):
lsmod | grep efa                            # efa module loaded?
fi_info -p efa                              # EFA endpoints visible?
cat /opt/amazon/efa_installed_packages      # version
```

**Fix:** Compare versions across nodes with the `hyperpod-version-checker` skill. If versions differ, the lifecycle script likely needs updating.

### 1.3 EFA intermittent failures

**Symptoms:** Training works sometimes, randomly hangs; NCCL logs show `Using network TCP` on some iterations (EFA fallback).

**Root cause:** EFA interface flapping, NIC errors, or PCIe issues.

```bash
# On the affected node (via SSM):
ip -s link show 2>/dev/null | grep -A5 "RX\|TX"   # errors / drops
dmesg | grep -i "efa\|pcie\|error" | tail -20
bash scripts/check-node-reachability.sh            # full EFA health check
```

---

## 2. GPU / Accelerator

### 2.1 GPU off bus (XID 79)

**Symptoms:** `nvidia-smi` shows fewer GPUs than expected; `dmesg` has `Xid 79: GPU has fallen off the bus`; training fails with CUDA device not found.

**Root cause:** Hardware — GPU disconnected from PCIe bus.

```bash
nvidia-smi -L | wc -l              # visible GPUs
dmesg | grep -i "xid.*79\|off the bus"
lspci | grep -i nvidia | wc -l     # physical GPU count
```

**Fix:** Drain and replace — see the Suggested-command blocks in [node-diagnostics-detail.md § G (drain)](node-diagnostics-detail.md#accelerator-failure--section-f) and [§ F (batch-replace)](node-diagnostics-detail.md#f-hardware--auto-repair) for Preconditions / Blast-radius. Root + secondary volumes are destroyed on replace.

### 2.2 ECC errors

**Symptoms:** `nvidia-smi -q` shows non-zero ECC counts; training produces NaNs or incorrect gradients; throughput degrades on a specific GPU.

```bash
nvidia-smi -q | grep -A 10 "ECC Errors"
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,ecc.errors.uncorrected.volatile.total --format=csv
```

Correctable errors (CE) are a normal background. **Any uncorrectable error (UCE) indicates failing memory — drain and replace.** A persistent growing CE rate is also a warning and worth escalating even without UCE.

### 2.3 Thermal throttling

**Symptoms:** GPU utilization drops periodically; `nvidia-smi dmon` shows rising temperature and clock ramp-down; training throughput varies over time.

```bash
nvidia-smi dmon -s pucvmet -d 5
nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.current.sm --format=csv
```

Persistent throttling on a single GPU when others stay cool typically points at a hardware-level thermal or power-delivery issue — drain and replace, and capture `nvidia-bug-report.sh` for the support case.

### 2.4 NVLink failures

**Symptoms:** Inter-GPU communication slow on the same node; `nvidia-smi nvlink --status` shows inactive links; XID 74 in dmesg.

```bash
nvidia-smi nvlink --status
nvidia-smi topo -m             # should show NVLinks, not PHB-only paths
dmesg | grep -i "xid.*74\|nvlink"
```

**Fix:** Drain and replace.

---

## 3. Slurm

### 3.1 "Node unexpectedly rebooted"

**Symptoms:** `sinfo` shows node `down`; reason `"Node unexpectedly rebooted"`; node is actually running and accessible.

**Root cause:** Node rebooted without notifying Slurm; slurmd may not have restarted.

```bash
scontrol show node <NODE> | grep -E "State|Reason"
# On node via SSM:
sudo systemctl status slurmd
```

**Fix:** restart slurmd on the node and resume on the controller — see [node-diagnostics-detail.md § H (Slurm Node Management)](node-diagnostics-detail.md#h-slurm-node-management) for the framed procedure.

### 3.2 Jobs stuck COMPLETING after node replacement

**Symptoms:** Jobs stay in COMPLETING indefinitely; node was recently replaced.

**Root cause:** slurmctld cached the COMPLETING state and keeps waiting for the replaced node.

**Fix:** restart slurmctld (preserves running jobs, queue, and node states) — see the Suggested-command block in [node-diagnostics-detail.md § H (Jobs stuck PENDING / COMPLETING)](node-diagnostics-detail.md#jobs-stuck-pending--completing--restart-slurmctld).

### 3.3 GRES (GPU) miscalculation

**Symptoms:** Jobs stuck PENDING with `Reason=Resources` despite free GPUs; `scontrol show node` shows the wrong GRES count.

**Root cause:** GRES resources not released after job completion or node replacement.

**Fix:** restart slurmctld — same Suggested-command block as 3.2 above. Verify with `scontrol show node <NODE> | grep Gres`.

---

## 4. Configuration

### 4.1 Wrong vCPU count (e.g. 96 on p5.48xlarge instead of 192)

**Symptoms:** `nproc` shows half the expected vCPU count for the instance family; jobs configured for the full count can't schedule.

**Fix:** See [node-diagnostics-detail.md § J](node-diagnostics-detail.md#j-configuration) for the `update-cluster` fix using `ThreadsPerCore`.

---

## 5. Resource exhaustion

See [node-diagnostics-detail.md § I](node-diagnostics-detail.md#i-resource-exhaustion) — full coverage of root volume exhaustion, `os.fork()` memory error with EFA, OOM kills, inode exhaustion, and time sync.
