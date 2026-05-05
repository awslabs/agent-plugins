# Performance Details

Supplementary detail for `hyperpod-performance-debugger`. Each section corresponds to one of the three top-level categories.

---

## Uneven NCCL

### Pairwise NCCL all-reduce test

Use the `nccl-tests` container from [aws-samples/awsome-distributed-training](https://github.com/aws-samples/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests). The repo ships `slurm/nccl-tests-container.sbatch` and `slurm/topology-aware-nccl-tests/` with pairwise sweeps pre-wired. For an N-node cluster, run all-reduce across every pair and record `busbw` for each pair. Any pair more than ~20% below the cluster median points to the node(s) common to the slow pairs.

The topology-aware submit script in that repo uses `sbatch --array` to fan out pairwise jobs and the `process_nccl_results.sh` helper to flag outliers (default threshold 5% deviation from the run median).

Manual single-pair run (Slurm):

```bash
sbatch -N 2 -w <NODE_A>,<NODE_B> nccl-tests-container.sbatch
```

Aggregate run across all N nodes (from the DLAMI-preinstalled NCCL tests path):

```bash
# Path varies by DLAMI version; prefer the repo's sbatch file over hardcoded paths.
srun -N <N> --mpi=pmix /opt/nccl-tests/build/all_reduce_perf -b 8 -e 8G -f 2 -g 8
```

### Expected bandwidth (8-GPU all-reduce, message sizes ≥ 1 GiB)

Per the [AWS AI-on-HyperPod NCCL guide](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests#performance-benchmarks):

| Instance      | Network bandwidth  | Expected busbw | Warning threshold | Failure threshold |
| ------------- | ------------------ | -------------- | ----------------- | ----------------- |
| p4d.24xlarge  | 400 Gbps           | ~300 GB/s      | < 270 GB/s        | < 240 GB/s        |
| p4de.24xlarge | 400 Gbps           | ~300 GB/s      | < 270 GB/s        | < 240 GB/s        |
| p5.48xlarge   | 3,200 Gbps (EFAv2) | ~400+ GB/s     | < 360 GB/s        | < 320 GB/s        |
| p5e.48xlarge  | 3,200 Gbps (EFAv2) | ~400+ GB/s     | < 360 GB/s        | < 320 GB/s        |
| p5en.48xlarge | 3,200 Gbps (EFAv3) | ~400+ GB/s     | < 360 GB/s        | < 320 GB/s        |
| p6e.48xlarge  | 3,200 Gbps         | ~400+ GB/s     | < 360 GB/s        | < 320 GB/s        |

> **Trainium**: `trn1.32xlarge` and `trn2.48xlarge` do **not** run NCCL — they run `NCCOM` tests via the Neuron SDK. See the [NCCOM testing guide](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccom-tests). The "expected busbw" column above does not apply; use the `nccom-test` binaries and compare against Neuron SDK docs.

The AWS pairwise-validation script (`validate_performance.sh` in the NCCL guide) flags any pair deviating more than 5% from the run mean — that's the tight threshold for production validation. The 20% number here is the coarser "drain-and-replace" threshold: if a pair is 20%+ below median, the node common to slow pairs is the prime suspect.

### UltraCluster / placement group check

```bash
for id in $(aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
             --query 'ClusterNodeSummaries[*].InstanceId' --output text); do
  aws ec2 describe-instances --instance-ids $id --region <R> \
    --query 'Reservations[0].Instances[0].{ID:InstanceId,AZ:Placement.AvailabilityZone,PG:Placement.GroupName,Subnet:SubnetId}' \
    --output text
done
```

All nodes that need fast all-reduce together must share the same `PG` and `AZ`. If they don't, the cluster was provisioned without placement constraints — you cannot fix this in place. Use Flexible Training Plans or reserved capacity to force co-location (see [hyperpod-cluster-debugger → capacity-planning.md](../../hyperpod-cluster-debugger/references/capacity-planning.md)).

### EFA version consistency

All nodes in the training group must run identical EFA and OFI-NCCL versions. Use `hyperpod-version-checker` to compare. Any mismatch is sufficient to degrade pairwise bandwidth 10–30%.

---

## Filesystem

### CloudWatch metrics per filesystem type

All metrics live in the `AWS/FSx` namespace (not `AWS/EBS`). Dimension: `FileSystemId`.

#### FSx for Lustre (`FileSystemType: LUSTRE`)

| Metric                    | What it means                                | Statistic |
| ------------------------- | -------------------------------------------- | --------- |
| `DataReadBytes`           | Aggregate read throughput (Bytes)            | Sum       |
| `DataWriteBytes`          | Aggregate write throughput (Bytes)           | Sum       |
| `MetadataOperations`      | File-open, stat, readdir rate (Count)        | Sum       |
| `FreeDataStorageCapacity` | Remaining bytes — low values throttle writes | Minimum   |
| `DiskIopsUtilization`     | % of provisioned IOPS in use (Percent)       | Maximum   |

Lustre throughput scales as `StorageCapacity_TiB × PerUnitStorageThroughput_MBps`. To scale up, grow capacity or upgrade per-unit throughput (`PERSISTENT_2` only). Capacity changes are non-disruptive.

#### FSx for OpenZFS (`FileSystemType: OPENZFS`)

| Metric                                       | What it means                              | Statistic        |
| -------------------------------------------- | ------------------------------------------ | ---------------- |
| `DataReadBytes` / `DataWriteBytes`           | Aggregate throughput (Bytes)               | Sum              |
| `DataReadOperations` / `DataWriteOperations` | Client IOPS (Count)                        | Sum              |
| `NetworkThroughputUtilization`               | % of provisioned network throughput in use | Average, Maximum |
| `FileServerDiskIopsUtilization`              | % of disk IOPS in use                      | Average, Maximum |
| `FileServerDiskThroughputUtilization`        | % of disk throughput in use                | Average, Maximum |
| `CPUUtilization`                             | File server CPU %                          | Average, Maximum |

The utilization metrics (percent) are the authoritative saturation signals. There is **no** `ReadIOPS` metric in `AWS/FSx` — that's an EBS metric. Source: [FSx for OpenZFS metrics](https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/fsx-openzfs-metrics.html).

#### EBS (`AWS/EBS` namespace — separate from FSx)

Use `VolumeReadOps`, `VolumeWriteOps`, `VolumeQueueLength`. A sustained `VolumeQueueLength > 1` means the volume is the bottleneck. For gp3, also compare against the provisioned IOPS/throughput (set when creating the volume, not scaled automatically).

### NVMe sizes per instance

Source: [EC2 P5 product page](https://aws.amazon.com/ec2/instance-types/p5/), [EC2 P4 product page](https://aws.amazon.com/ec2/instance-types/p4/).

| Instance      | NVMe devices | Mount             | Total raw |
| ------------- | ------------ | ----------------- | --------- |
| p4d.24xlarge  | 8 × 1 TB     | `/opt/dlami/nvme` | ~8 TB     |
| p4de.24xlarge | 8 × 1 TB     | `/opt/dlami/nvme` | ~8 TB     |
| p5.48xlarge   | 8 × 3.84 TB  | `/opt/dlami/nvme` | ~30.7 TB  |
| p5e.48xlarge  | 8 × 3.84 TB  | `/opt/dlami/nvme` | ~30.7 TB  |
| p5en.48xlarge | 8 × 3.84 TB  | `/opt/dlami/nvme` | ~30.7 TB  |
| p6e.48xlarge  | 8 × 3.84 TB  | `/opt/dlami/nvme` | ~30.7 TB  |

NVMe is **ephemeral** — data is lost on stop, replace, or hardware failure. Use for scratch, not persistent state.

### Async checkpoint pattern (PyTorch)

Requires PyTorch ≥ 2.4. The `torch.distributed.checkpoint.async_save` API stages the state dict to CPU (default), starts the save in a background thread, and returns a future the training loop can continue past. See the [PyTorch DCP documentation](https://docs.pytorch.org/docs/stable/distributed.checkpoint.html).

```python
import torch.distributed.checkpoint as dcp
from torch.distributed.checkpoint import FileSystemWriter

# FSDP users: use SHARDED_STATE_DICT, not FULL_STATE_DICT.
# FULL_STATE_DICT gathers to rank 0 and serializes every write through one node.

state = {"model": model.state_dict(), "optimizer": optim.state_dict()}
storage_writer = FileSystemWriter(f"{ckpt_dir}/step_{step}")

# Non-blocking: training continues immediately.
fut = dcp.async_save(
    state,
    checkpoint_id=f"{ckpt_dir}/step_{step}",
    storage_writer=storage_writer,
)

# Block only when you must — e.g. before job exit or before the next save.
fut.result()
```

Notes:

- `async_save` returns either a bare future or an `AsyncSaveResponse` (two-future form: `.staging_completion` + `.upload_completion`) depending on the staging configuration. The one-future form above works for the default `BlockingAsyncStager`.
- On shared FSx Lustre, stripe your checkpoint directory across multiple OSTs with `lfs setstripe` before the first save; this alone often doubles checkpoint throughput.
- For very large models (tens of billions of params), set the writer's `thread_count` based on the rank count per node.

### Filesystem selection by pattern

| Pattern                       | Best fit                               | Why                                     |
| ----------------------------- | -------------------------------------- | --------------------------------------- |
| Large sequential I/O          | FSx for Lustre                         | Striping scales with OSTs               |
| Small random I/O, mixed reads | FSx for OpenZFS                        | POSIX + better small-file performance   |
| Temporary high-perf scratch   | NVMe (`/opt/dlami/nvme`)               | 30+ GB/s aggregate, zero network        |
| Single-node persistent        | EBS gp3 / io2 (`/opt/sagemaker`)       | 100 GB root is too small; EBS is sized  |
| Datasets (cold + warm)        | S3 + Mountpoint-S3 for streaming reads | Scales infinitely, no provisioned limit |

---

## GPU

### Xid error catalog (common codes)

Source: [NVIDIA Xid errors](https://docs.nvidia.com/deploy/xid-errors/). When in doubt, treat Xid ≥ 48 as hardware until proven otherwise by DCGM `-r 3` passing.

| Xid    | Meaning                           | Severity     | Action                                              |
| ------ | --------------------------------- | ------------ | --------------------------------------------------- |
| 13     | GR: SW notify / user app fault    | App          | Usually a CUDA kernel bug; inspect training code    |
| 31     | MMU fault (bad memory access)     | App          | Usually user bug; monitor                           |
| 43     | GPU stopped processing            | App → HW     | Restart job; if recurring on the same node, replace |
| 45     | Preemptive cleanup                | Info         | Benign                                              |
| 48     | Double-bit ECC error              | **Hardware** | Drain + replace                                     |
| 62     | Internal micro-controller halt    | **Hardware** | Drain + replace                                     |
| 63, 64 | ECC page retirement               | **Hardware** | Drain + replace if rate climbing                    |
| 74     | NVLink error                      | **Hardware** | Drain + replace                                     |
| 79     | GPU fell off the bus              | **Hardware** | Drain immediately                                   |
| 92     | GPU exhausted                     | **Hardware** | Drain + replace                                     |
| 94, 95 | Contained / uncontained ECC error | **Hardware** | Drain + replace                                     |

### ECC error-rate thresholds

Track both `volatile` (since driver load) and `aggregate` (lifetime). The `aggregate.total` field survives reboots; rely on it for long-lived clusters.

```bash
nvidia-smi --query-gpu=index,ecc.errors.uncorrected.volatile.total,ecc.errors.uncorrected.aggregate.total,ecc.errors.corrected.volatile.total \
  --format=csv,noheader
```

| Rate                                      | Interpretation                                |
| ----------------------------------------- | --------------------------------------------- |
| Corrected < 100/day (volatile)            | Normal background                             |
| Corrected 100–1000/day (volatile)         | Watch — may be environmental or early failure |
| Corrected > 1000/day (volatile)           | Pre-failure; schedule replacement             |
| Uncorrectable (volatile or aggregate) > 0 | **Failed** — drain and replace now            |

### DCGM diag levels

| Level  | Command              | Duration | Scope                               | Safe during training? |
| ------ | -------------------- | -------- | ----------------------------------- | --------------------- |
| `-r 1` | Short                | ~30 sec  | Sanity — device present, responsive | Yes                   |
| `-r 2` | Medium               | ~2 min   | Adds memory & PCIe tests            | No — moderate load    |
| `-r 3` | Long (comprehensive) | ~15 min  | Full stress including SM & memory   | No — 100% load        |
| `-r 4` | Extended             | ~1 hour  | Long-duration stress                | No — 100% load        |

Use `-r 3` for replacement decisions. Record the output — AWS Support will want it. **Must be run on a drained node.**

### GPU stress / burn test

`gpu-burn` is a third-party CUDA stress test that sustains ~100% GPU utilization for a fixed duration and reports errors. Use it only as a final post-replacement verification step, and only on a drained node.

Prefer `dcgmi diag -r 3` whenever DCGM is available on the node — it returns structured pass/fail per sub-test and is the output AWS Support requires. Fall back to `gpu-burn` only when DCGM is unavailable, or when the user explicitly asks for a second signal.

**Supply-chain posture.** `gpu-burn` is not preinstalled on HyperPod DLAMIs and is not an AWS-signed artifact. Do not auto-clone and build it at runtime. Before invoking `gpu-burn`, confirm one of the following, in this order of preference:

1. **`gpu_burn` is already present on the node** at a known path (e.g. baked into the cluster's operator image). Use the existing binary. Do not rebuild.
2. **The user's account has a pinned, trusted artifact** — an S3 object, internal package-repo entry, or OCI image tag they have approved for this workflow. Fetch from there.
3. **The user explicitly asks to build `gpu-burn` from source for a one-off diagnostic.** In that case:
   - Ask for a specific commit SHA or release tag from <https://github.com/wilicc/gpu-burn>. Refuse to build from `HEAD` or an unpinned branch.
   - Show the commit diff against the previous known-good tag and the Makefile contents, and wait for the user to approve before building.
   - Build in an isolated working directory on the target node. Record the resulting binary's SHA-256 and report it back.
   - Do not persist the binary outside that directory unless the user approves mirroring it to their trusted store.

If none of (1), (2), or (3) apply, skip `gpu-burn` and rely on `dcgmi diag -r 3` alone. Never silently install or compile third-party binaries on a production node.

Once a trusted binary is present on the drained node, the invocation is `./gpu_burn 600` for a 10-minute burn. A healthy GPU completes without errors and without clock dips beyond brief transients. Any failure → drain and replace.

### Pre-return validation for a replaced node

Before returning a replaced node to the scheduling pool, confirm it is healthy. Execute the following on the drained replacement via SSM and report results back to the user:

```bash
# Required checks:
nvidia-smi                                                   # all 8 GPUs visible
nvidia-smi -q | grep -A2 "ECC Errors"                        # zero uncorrectable
sudo dcgmi diag -r 3                                         # all tests pass
fi_info -p efa | head -20                                    # EFA devices present; compare to healthy peer
```

Optional additional signal: `./gpu_burn 300` (5-minute burn). Only run this if a trusted `gpu_burn` binary is already available on the node per the supply-chain posture above. If no trusted binary is present, skip it — do not clone, download, or compile `gpu-burn` to satisfy pre-return validation.

If everything passes, return to the pool:

```bash
# Slurm:
scontrol update NodeName=<N> State=resume
# EKS:
kubectl uncordon <NODE>
```

### Complete replacement playbook

See `hyperpod-node-debugger` § F for the authoritative flow, and the AI-on-HyperPod GPU stress-testing guide:
<https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/validation-and-testing/performance-testing/gpu-stress-testing>
