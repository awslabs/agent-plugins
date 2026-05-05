---
name: hyperpod-performance-debugger
description: Diagnoses three performance issues on SageMaker HyperPod — uneven NCCL bandwidth across nodes, poor filesystem throughput, and suspected GPU failure. Triggers on uneven NCCL, straggler node, FSx slow, checkpoint slow, dataloader slow, GPU failure, ECC, Xid, thermal throttling, UltraCluster placement, DCGM diagnostics, hardware replacement.
metadata:
  version: "1.0.0"
---

# HyperPod Performance Debugger

Narrow-scope triage for three performance symptoms on HyperPod:

1. **Uneven NCCL performance** across nodes — topology variance or degraded EFA on one or more nodes
2. **Poor filesystem performance** — FSx / EBS throughput saturation, I/O bottleneck
3. **Suspected GPU failure** — ECC, thermal throttling, Xid errors, hardware replacement

The scope here is deliberately **narrow**: identify which of the three categories applies, run the category-specific diagnostic pass, then delegate to the right deep-dive skill for the fix.

| Category                    | After triage, delegate to                                   |
| --------------------------- | ----------------------------------------------------------- |
| Uneven NCCL performance     | `hyperpod-nccl`; also `hyperpod-mfu-debugger` if MFU-driven |
| Poor filesystem performance | `hyperpod-mfu-debugger` (see its `optimization-guide.md`)   |
| Suspected GPU failure       | `hyperpod-node-debugger` § G (GPU) → § F (replacement)      |

All on-node commands run via the `hyperpod-ssm` skill.

> **Destructive-action policy**
> Operate in read-only mode by default. Several remediation commands referenced below are destructive (drain, reboot, replace, GPU stress). Each is flagged `WARNING — destructive`. Before executing any flagged command, get the user's explicit confirmation in the session. Approval for one destructive step does **not** carry over to the next — confirm each one separately.

---

## Step 1: Classify the Symptom

Ask the user what they're actually seeing, then match to one of the three categories:

| What the user reports                                                          | Go to                                   |
| ------------------------------------------------------------------------------ | --------------------------------------- |
| Training is faster on some node sets than others / variance across allocations | **[A](#a-uneven-nccl-performance)**     |
| One specific node is slow (straggler) at AllReduce                             | **[A](#a-uneven-nccl-performance)**     |
| Placement-group concerns, cross-AZ latency suspicions                          | **[A](#a-uneven-nccl-performance)**     |
| DataLoader stalls, epoch time bloats, checkpoint saves very slow               | **[B](#b-poor-filesystem-performance)** |
| `iostat`/`dstat` shows disk wait high, FSx dashboards red                      | **[B](#b-poor-filesystem-performance)** |
| `nvidia-smi` shows errors, CUDA errors in logs, NaN loss, Xid in dmesg         | **[C](#c-suspected-gpu-failure)**       |
| Thermal throttling (temp > 85°C), ECC error counts climbing                    | **[C](#c-suspected-gpu-failure)**       |

If the user can't classify, run the one-shot snapshot — it prints all three signals and tells you which section to jump to:

```bash
bash scripts/perf-snapshot.sh --cluster <NAME> --region <REGION>
# Scope to one suspect node:
bash scripts/perf-snapshot.sh --cluster <NAME> --region <REGION> --node <INSTANCE_ID>
```

The script is read-only. It may emit color codes; pass `--no-color` or pipe to a file to disable.

---

## A: Uneven NCCL Performance

**Signals:** Identical training job has different step times on different node sets. Bandwidth varies across node pairs. Some jobs consistently slower than others despite same code.

**Root causes (in order of frequency):**

1. Network topology differences — nodes not in the same placement group / UltraCluster, or spread across AZs
2. Degraded EFA on one or more nodes — driver, OFI-NCCL version, or hardware
3. Instance-type mix within an instance group (e.g., `p5.48xlarge` and `p5e.48xlarge` together)
4. CPU frequency scaling / GPU-EFA affinity differences

### Diagnostic pass (on each suspect node, via SSM)

```bash
# Topology — GPU↔EFA mapping. Look for NODE/SYS/PIX inconsistencies across nodes:
nvidia-smi topo -m

# EFA device count and versions. All nodes must match:
fi_info -p efa | grep -E 'provider|version|fabric' | sort -u
lsmod | grep -iE 'efa|ib_'
cat /opt/amazon/efa/share/VERSION 2>/dev/null

# Instance type (IMDSv2 required on HyperPod DLAMIs):
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-type

# CPU governor (should be 'performance' for training):
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

### Pairwise NCCL bandwidth test

Use `nccl-tests` from [aws-samples/awsome-distributed-training](https://github.com/aws-samples/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests). For an N-node cluster, run all-reduce across every pair and record `busbw` for each pair. Any pair more than ~10% below the cluster median points to the node(s) common to the slow pairs.

Expected `busbw` (8-GPU node, message sizes ≥ 1 GiB) per the [AWS AI-on-HyperPod NCCL guide](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests):

| Instance      | Expected busbw | Warning (< 10% below) | Failure (> 20% below) |
| ------------- | -------------- | --------------------- | --------------------- |
| p4d.24xlarge  | ~300 GB/s      | < 270 GB/s            | < 240 GB/s            |
| p4de.24xlarge | ~300 GB/s      | < 270 GB/s            | < 240 GB/s            |
| p5.48xlarge   | ~400+ GB/s     | < 360 GB/s            | < 320 GB/s            |
| p5e.48xlarge  | ~400+ GB/s     | < 360 GB/s            | < 320 GB/s            |
| p5en.48xlarge | ~400+ GB/s     | < 360 GB/s            | < 320 GB/s            |
| p6e.48xlarge  | ~400+ GB/s     | < 360 GB/s            | < 320 GB/s            |

Trainium (`trn1.32xlarge`, `trn2.48xlarge`) does **not** run NCCL — use NCCOM via the Neuron SDK instead. See the [NCCOM testing guide](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccom-tests).

### Fix path

Once the outlier node is isolated:

- **Replace the bad node.** See the destructive-action warning below.
  Delegate the full replacement flow to `hyperpod-node-debugger` § F (Hardware / Auto-Repair). It covers `batch-reboot-cluster-nodes` (try first — non-destructive) and `batch-replace-cluster-nodes` (destructive — terminates the instance and wipes all local volumes).

- **Systemic topology issues** (no single bad node, but spread-out placement):
  - Verify all nodes are in the same placement group — check `Placement.GroupName` via `describe-instances`.
  - Confirm all nodes share the same AZ — check `Placement.AvailabilityZone`.
  - If they don't, the cluster was provisioned without placement constraints; you cannot fix this in place. Recreate using Flexible Training Plans or reserved capacity to force co-location. See [hyperpod-cluster-debugger → capacity-planning.md](../hyperpod-cluster-debugger/references/capacity-planning.md).

### Delegate

| Situation                                           | Use                                               |
| --------------------------------------------------- | ------------------------------------------------- |
| NCCL timeout / hang / AllReduce stuck               | `hyperpod-nccl` skill                             |
| EFA/NCCL/CUDA version drift across nodes            | `hyperpod-version-checker` skill                  |
| Training-wide MFU degradation is the actual symptom | `hyperpod-mfu-debugger` skill (Phase 2F: network) |
| Node replacement required                           | `hyperpod-node-debugger` § F                      |

See [references/perf-details.md → Uneven NCCL](references/perf-details.md#uneven-nccl) for the pairwise-test scripts, busbw thresholds, and the UltraCluster placement-group check.

---

## B: Poor Filesystem Performance

**Signals:** Training bottlenecked on data loading, checkpoint save/load dominates step time, executables/scripts load slowly, `iowait` high in `top`/`dstat`.

### Diagnostic pass

**1. CloudWatch metrics** — the authoritative signal for FSx. Compare actual throughput against provisioned.

For each filesystem, list and pull recent throughput. Scope to filesystems actually attached to the cluster by inspecting on-node mounts first, not `describe-file-systems` unfiltered (which enumerates every FSx in the region):

```bash
# On a cluster node, via SSM — list actually-mounted FSx filesystems:
mount | grep -E 'lustre|zfs' | awk '{print $3}'
```

Then describe just those IDs:

```bash
aws fsx describe-file-systems --region <REGION> --file-system-ids <FSID1> <FSID2> \
  --query 'FileSystems[*].{Id:FileSystemId,Type:FileSystemType,CapacityGiB:StorageCapacity}'
```

Lustre and OpenZFS both emit `DataReadBytes` / `DataWriteBytes` (Bytes, Sum) in the `AWS/FSx` namespace:

```bash
aws cloudwatch get-metric-statistics --region <REGION> \
  --namespace AWS/FSx --metric-name DataReadBytes \
  --dimensions Name=FileSystemId,Value=<FSID> \
  --start-time "$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 60 --statistics Sum Maximum
```

For saturation (%), OpenZFS exposes `FileServerDiskThroughputUtilization` and `FileServerDiskIopsUtilization` directly; Lustre exposes `DiskIopsUtilization`. See [references/perf-details.md → Filesystem](references/perf-details.md#filesystem) for the full per-filesystem catalog.

**2. On-node I/O inspection** (via `hyperpod-ssm`):

```bash
iostat -xz 1 30                       # per-device I/O over 30s (unprivileged, DLAMI default)
sudo iotop -ao -b -n 30 -d 1          # per-process I/O over 30s (requires sudo)
df -h /fsx /opt/dlami/nvme /opt/sagemaker 2>/dev/null
for mnt in $(mount | awk '/lustre/ {print $3}'); do lfs df -h "$mnt"; done
```

### Fix path

Ask: **is the workload legitimately demanding more, or is the I/O pattern inefficient?**

**Provisioned capacity saturated → scale up:**

- FSx for Lustre: throughput scales with `StorageCapacity × PerUnitStorageThroughput`. Grow the filesystem (online, rebalances automatically) or upgrade `PerUnitStorageThroughput` for `PERSISTENT_2` deployments.
- FSx for OpenZFS: increase provisioned IOPS and/or throughput capacity.
- EBS: upgrade volume type (gp3 → io2) or bump provisioned IOPS/throughput.

**I/O pattern inefficient → fix the app** (most common):

- **Dataloader:** raise `num_workers`, `pin_memory=True`, `persistent_workers=True`, preload to RAM when it fits. Detailed tuning → [hyperpod-mfu-debugger → optimization-guide.md (data pipeline)](../hyperpod-mfu-debugger/references/optimization-guide.md).
- **Checkpointing:** use async + sharded checkpoints with `torch.distributed.checkpoint.async_save` + FSDP `SHARDED_STATE_DICT`. Canonical pattern in [references/perf-details.md → async checkpoint](references/perf-details.md#async-checkpoint-pattern-pytorch). Requires PyTorch ≥ 2.4.
- **Small-file workloads:** Lustre is optimized for large sequential I/O. For millions of small files, use WebDataset / tar shards, FSx for OpenZFS, or NVMe scratch.

**Choose the right filesystem for the pattern** — see [references/perf-details.md → filesystem selection](references/perf-details.md#filesystem-selection-by-pattern).

### Delegate

| Situation                                                | Use                                                                           |
| -------------------------------------------------------- | ----------------------------------------------------------------------------- |
| Data pipeline tuning (dataloader, prefetch, shuffling)   | `hyperpod-mfu-debugger` → its `optimization-guide.md` (data pipeline section) |
| Periodic dips tied to checkpoint cadence                 | `hyperpod-mfu-debugger` → its `steps/2e-periodic.md`                          |
| Shell access on nodes (`iotop`, `lfs df`)                | `hyperpod-ssm` skill                                                          |
| Diagnostic bundle for AWS Support (FSx metrics included) | `hyperpod-issue-report` skill                                                 |

---

## C: Suspected GPU Failure

**Signals:** CUDA errors, training produces NaN, GPU memory allocation failures, Xid in `dmesg`, temperature sustained > 85°C, ECC error counters climbing, crashes during GPU-intensive phases.

> **Warning — `dcgmi diag -r 3` and `gpu_burn` are destructive during training.**
> Both sustain 100% GPU load for minutes-to-hours and will disrupt any co-resident training job. Run only on a node that has been drained from the scheduler. If you haven't drained yet, skip these and start with the read-only queries below.

### Diagnostic pass (suspect node, via SSM)

Read-only checks — safe to run while training continues:

```bash
nvidia-smi                                                              # all GPUs visible?
nvidia-smi -q | grep -E 'ECC|Uncorrectable|Volatile|Aggregate' -A 2
dmesg -T 2>/dev/null | grep -iE 'xid|nvrm|pcie|ecc' | tail -30
nvidia-smi dmon -s pucvmet -c 30                                        # 30s live metrics
```

Stress diagnostics — require a drained node (see Fix path step 1):

```bash
sudo dcgmi diag -r 3                                                    # ~15 min, definitive
```

### What each finding means

| Signal                                            | Severity      | Action                                                         |
| ------------------------------------------------- | ------------- | -------------------------------------------------------------- |
| Xid 13, 31, 43, 45                                | Info / app    | Often app-side; investigate training code before replacing     |
| Xid 48, 62, 74, 79, 92, 94, 95                    | **Hardware**  | Drain + replace                                                |
| Xid 63, 64 (ECC page retirement)                  | **Hardware**  | Drain + replace if rate climbing; monitor otherwise            |
| ECC **uncorrectable** > 0 (volatile or aggregate) | **Hardware**  | Drain + replace                                                |
| ECC corrected > 1000/day and climbing             | Watch         | Schedule replacement before it escalates                       |
| GPU temp sustained > 85°C with throttling         | Environmental | Check airflow; replace if persistent                           |
| `nvidia-smi` missing a GPU                        | **Hardware**  | Drain + replace                                                |
| DCGM `-r 3` fails any test                        | **Hardware**  | Drain + replace; attach DCGM output to support case            |
| NaN loss but diagnostics clean                    | Software      | Not GPU — check mixed-precision / dtype config / learning rate |

Full Xid catalog, ECC thresholds, and DCGM level details in [references/perf-details.md → GPU](references/perf-details.md#gpu).

Trainium/Inferentia: use `neuron-ls`, `neuron-top`, `neuron-monitor` instead of `nvidia-smi`; delegate to `hyperpod-node-debugger` § G (Trainium section).

### Fix path (hardware confirmed)

**1. Drain so no new jobs land** (non-destructive — the node keeps existing state):

```bash
# Slurm — delegate to hyperpod-slurm-debugger for full drain/reboot/resume workflow
scontrol update NodeName=<N> State=drain Reason="GPU hardware failure - DCGM -r 3 failed"

# EKS — NOTE: --delete-emptydir-data permanently deletes emptyDir volumes on evicted pods
kubectl cordon <NODE>
kubectl drain <NODE> --ignore-daemonsets --delete-emptydir-data
```

**Warning:** `kubectl drain --delete-emptydir-data` destroys any scratch data in pod `emptyDir` volumes on that node. Confirm the user has no unpersisted results before running.

**2. Collect evidence for AWS Support** (read-only) — GPU serial, ECC counts, DCGM output, dmesg Xid lines. Use `hyperpod-issue-report` to bundle.

**3. Validate it's really hardware with `dcgmi diag -r 3`** (now safe because the node is drained). If all tests pass, the fault is unlikely to be GPU — re-check with `hyperpod-node-debugger` before paying for a replacement.

**4. Replace the node — destructive.** All data on instance volumes is permanently lost:

Delegate the replacement to `hyperpod-node-debugger` § F. That section covers:

- The `UpdateClusterSoftware` prerequisite that must run first on any pre-patch cluster, or `BatchReplaceClusterNodes` will fail.
- The exact `batch-reboot-cluster-nodes` → `batch-replace-cluster-nodes` ordering (reboot first; replace only if reboot doesn't clear).
- The data-loss warning: `BatchReplaceClusterNodes` **terminates the instance and destroys all EBS root and secondary volumes**. Back up `/opt/sagemaker` to S3 or FSx before calling. `/opt/dlami/nvme` is instance-store and ephemeral anyway.
- The CLI syntax: `--node-ids` takes **space-separated** instance IDs (`i-0abc... i-0def...`), not a JSON array.

**5. Validate the replacement before returning to the pool** — `dcgmi diag -r 3` + a short `gpu_burn` run on the drained replacement. See [references/perf-details.md → pre-return validation](references/perf-details.md#pre-return-validation-for-a-replaced-node).

### Delegate

| Situation                                            | Use                              |
| ---------------------------------------------------- | -------------------------------- |
| Broader node triage (lifecycle, VPC, not just GPU)   | `hyperpod-node-debugger` skill   |
| Full replacement flow + auto-repair debugging        | `hyperpod-node-debugger` § F     |
| Slurm drain / reboot / resume workflow               | `hyperpod-slurm-debugger` skill  |
| Trainium (trn1/trn2) — `neuron-ls`, not `nvidia-smi` | `hyperpod-node-debugger` § G     |
| Evidence bundle for AWS Support                      | `hyperpod-issue-report` skill    |
| Version mismatch (driver/CUDA/NCCL) suspected        | `hyperpod-version-checker` skill |

## Escalate to AWS Support When

1. Pairwise NCCL tests isolate a node, replacement passes DCGM, but bandwidth is still uneven — likely an UltraCluster-level network issue.
2. FSx for Lustre shows sustained throughput saturation despite being at the highest per-TiB throughput tier — may need a service quota increase or architecture change.
3. DCGM `-r 3` passes but training still NaNs or crashes on that GPU — silent-data-corruption case; collect evidence with `hyperpod-issue-report`.

## References

- [references/perf-details.md](references/perf-details.md) — pairwise NCCL test scripts with busbw thresholds; CloudWatch metric catalog per filesystem type with async-checkpoint patterns; Xid code catalog, ECC thresholds, DCGM test suites, and the full GPU replacement playbook.
- [AWS AI-on-HyperPod NCCL tests](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests) — canonical busbw expectations and topology-aware test scripts.
- [BatchReplaceClusterNodes API](https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_BatchReplaceClusterNodes.html) — data-loss warning and `UpdateClusterSoftware` prerequisite.
- [NVIDIA Xid errors](https://docs.nvidia.com/deploy/xid-errors/) — upstream severity guidance.
