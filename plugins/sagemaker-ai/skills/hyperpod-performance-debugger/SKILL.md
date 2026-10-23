---
name: hyperpod-performance-debugger
description: Diagnose performance issues on Amazon SageMaker HyperPod clusters — uneven NCCL bandwidth across nodes and poor filesystem throughput. Read-only. Surfaces host-side signals (Xid, ECC, NVLink, EFA reachability, FSx saturation) and routes to the appropriate sibling skill (hyperpod-node-debugger, hyperpod-nccl, hyperpod-version-checker, hyperpod-issue-report) for any remediation. Triggers on uneven NCCL across nodes, straggler node, FSx slow, checkpoint slow, dataloader slow, filesystem bottleneck, FSx throughput, cross-AZ latency, topology mismatch.
metadata:
  version: "0.0.1"
---

# HyperPod Performance Debugger

1. **Uneven NCCL performance across nodes** — workload faster on some node sets than others, pairwise bandwidth variance, suspected straggler.
2. **Poor filesystem performance** — training stalled on data loading, checkpoint save/load dominating step time, FSx throughput saturated.

## Scope and delegation

Route findings outside the two in-scope scenarios to the owner skill below.

| Concern observed                                                       | Route to                                                     |
| ---------------------------------------------------------------------- | ------------------------------------------------------------ |
| GPU hardware fault, ECC, NVLink, Xid, DCGM diagnostics, drain/replace  | `hyperpod-node-debugger` (§ F Hardware/Auto-Repair, § G GPU) |
| `Cannot allocate memory` at `os.fork()`, root volume exhausted         | `hyperpod-node-debugger` (§ I Resource Exhaustion)           |
| NCCL timeouts, hangs, AllReduce stalls, EFA TCP fallback, RDMA memlock | `hyperpod-nccl`                                              |
| EFA / NCCL / CUDA / NVIDIA driver version drift across nodes           | `hyperpod-version-checker`                                   |
| EFA self-referencing security-group rule missing — single node         | `hyperpod-node-debugger` § A (EFA / Security Group)          |
| EFA self-referencing security-group rule missing — cluster-wide        | `hyperpod-cluster-debugger` § A (EFA Health Checks)          |
| Slurm node state changes (drain / resume / reboot)                     | `hyperpod-slurm-debugger`                                    |
| Diagnostic bundle for AWS Support                                      | `hyperpod-issue-report`                                      |
| Shell access on a node                                                 | `hyperpod-ssm`                                               |

## Operating policy

- Read-only. Print commands the customer runs; do not execute commands that modify state.
- Container vs host version comparisons go through `hyperpod-version-checker`.
- Xid lines, ECC counts, NVLink lane state, and thermal readings get surfaced; the catalog and verdict live in `hyperpod-node-debugger` § G.

## Workflow

1. Confirm the symptom is **uneven NCCL** or **poor filesystem performance**. If neither, route to the matching sibling skill above.
2. Run `scripts/perf-snapshot.sh` (read-only) to gather host-side signals for the suspect node and FSx filesystems mounted on it.
3. For each `[CONCERN]` line in the script output, open the matching section below and read the supporting reference.
4. After the per-incident diagnosis, recommend the HyperPod platform health features in [§ Continuous health coverage](#continuous-health-coverage) so the customer gets ongoing protection.

## Step 1: Run the snapshot

```bash
bash scripts/perf-snapshot.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION>

# Scope to one suspect node:
bash scripts/perf-snapshot.sh --cluster <C> --region <R> --node <INSTANCE_ID>
```

The script samples one node by default. It collects host-side data via `hyperpod-ssm`: `nvidia-smi` output (temperature, SM clocks, PCIe link width, ECC, NVLink, `topo -m`), recent `dmesg` Xid lines, EFA port state and `fi_info` provider visibility, EFA installer + kernel module versions, CPU governor, NVL72 Fabric Manager state, FSx CloudWatch utilization, `df -h` / `lfs df -h` per mount, host iowait, `/dev/shm` size, and root-volume usage. All read-only.

Tags: `[OK]` healthy · `[CONCERN]` signal worth investigating (carries a `→` pointer to the owner skill) · `[INFO]` informational.

**Host vs container scope.** The script runs on the host via SSM and reports host-scope values. Many setups ship the EFA / libfabric / OFI-NCCL / CUDA stack inside the training container by design — a host value of `unknown` is not by itself a defect. What matters for performance is the stack the workload actually uses. Verify versions inside the container (and across nodes) via `hyperpod-version-checker` before drawing conclusions.

## Step 2: Match signal → section

| Observation                                                                   | Section                                                                                                                                |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Pairwise NCCL bandwidth varies across node pairs / suspected straggler        | **[A: Uneven NCCL Performance](#a-uneven-nccl-performance)**                                                                           |
| Nodes spread across AZs / network-node-layer labels / UltraServer boundaries  | **[A](#a-uneven-nccl-performance)**                                                                                                    |
| EFA port not ACTIVE on a node, missing OFI plugin, or FI provider not visible | **[A](#a-uneven-nccl-performance)** + route to `hyperpod-node-debugger` § A; `hyperpod-version-checker` for cross-node version compare |
| `iostat` shows high iowait, FSx CloudWatch utilization sustained near 100%    | **[B: Poor Filesystem Performance](#b-poor-filesystem-performance)**                                                                   |
| DataLoader stalls, checkpoint dominates step time                             | **[B](#b-poor-filesystem-performance)**                                                                                                |
| Xid line in `dmesg`, uncorrectable ECC, inactive NVLink lane, GPU ≥ 88°C      | Route to `hyperpod-node-debugger` § G                                                                                                  |
| Container vs host version drift suspected                                     | Route to `hyperpod-version-checker`                                                                                                    |
| `Cannot allocate memory` at `os.fork()`, root volume full, OOM events         | Route to `hyperpod-node-debugger` § I                                                                                                  |
| NCCL timeout, hang, TCP fallback (`NET/OFI Using TCP`), RDMA memlock          | Route to `hyperpod-nccl`                                                                                                               |

---

## A: Uneven NCCL Performance

The customer reports identical training jobs running with different step times on different node sets, pairwise bandwidth variance, or some allocations consistently slower than others despite identical code.

Per the official troubleshooting guide, the common contributing factors are network topology differences between nodes (cross-AZ, cross-rack, cross-UltraServer), degraded EFA performance on some nodes, mixed instance types or generations within an instance group, and CPU frequency scaling differences.

### Diagnostic pass (read-only)

The host-side data points — GPU thermal/ECC/PCIe/clocks, Xid, NVLink lanes, EFA port state and provider visibility, CPU governor, EFA/OFI/driver versions, `nvidia-smi topo -m` — are all collected by `scripts/perf-snapshot.sh` (Step 1 above). The script tags `[CONCERN]` with thresholds and emits routing pointers; rerun it per suspect node via `--node <INSTANCE_ID>`.

For driver / CUDA / NCCL / EFA / OFI version drift across nodes, run `hyperpod-version-checker` skill.

### Pairwise NCCL bandwidth test

Run the standard `nccl-tests` recipes from [awslabs/awsome-distributed-training](https://github.com/awslabs/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests). For an N-node cluster, run all-reduce across every pair and record `busbw` for each pair. Pairs more than ~5% below the run mean (the threshold the AWS validation script flags) are problematic candidates.

Expected `busbw` per SKU is published in the [AI-on-HyperPod NCCL test guide](https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests). Benchmark the specific instance type before relying on a number.

Pairwise scripts, HyperPod topology surfaces (HyperPod API, EKS labels, Slurm `topology.conf`), and GB200 NVL72 specifics are in [references/perf-details.md § Uneven NCCL](references/perf-details.md#uneven-nccl).

### Topology verification

HyperPod exposes topology through three operator-visible surfaces:

- **HyperPod API**: `aws sagemaker describe-cluster-node` returns `NodeDetails.Placement.AvailabilityZone` / `AvailabilityZoneId` and `NodeDetails.UltraServerInfo.Id` (UltraServer SKUs only).
- **EKS labels**: `topology.kubernetes.io/zone`, `topology.k8s.aws/network-node-layer-{1,2,3}` (highest-numbered = closest to instance), `topology.k8s.aws/ultraserver-id`.
- **Slurm**: HyperPod auto-generates `topology.conf`. Inspect via `scontrol show topology`.

Tightly coupled work shares the same AZ, the same highest-numbered network-node-layer label (EKS) or the same Slurm topology block, and — for NVL72 jobs — the same `UltraServerInfo.Id` / `topology.k8s.aws/ultraserver-id`. If the cluster is spread across AZs or layers, topology must be re-established at provisioning time. Route provisioning changes to `hyperpod-cluster-debugger` § B (Capacity & AZ).

---

## B: Poor Filesystem Performance

The customer reports training bottlenecked on data loading, checkpoint save/load dominating step time, executables/scripts loading slowly, or `iowait` high.

Per the official troubleshooting guide, the resolution path follows this order:

1. Check CloudWatch metrics on the filesystem.
2. Check the provisioned performance configuration against workload requirements.
3. Investigate which operations are causing the I/O — workload demand vs inefficient pattern.
4. Consider upgrading provisioned performance.
5. Choose the filesystem type that matches the I/O pattern.

This skill covers steps 1–3. Steps 4–5 are customer decisions; surface the data and let the customer pick.

### Diagnostic pass (read-only)

`scripts/perf-snapshot.sh` (Step 1 above) covers the on-node side of this pass: it discovers FSx mounts, calls `aws cloudwatch get-metric-statistics` on `DataReadBytes` and (for OpenZFS) `FileServerDiskIopsUtilization`, prints `df -h` for `/fsx /opt/dlami/nvme /opt/sagemaker`, runs `lfs df -h` per Lustre mount, and reports `iostat` iowait. It tags `[CONCERN]` when OpenZFS IOPS utilization sustains ≥ 80% or iowait > 20%.

For longer windows or additional metrics (`DataWriteBytes`, Lustre `DiskIopsUtilization`, OpenZFS `FileServerDiskThroughputUtilization`), drive the query directly:

```bash
aws cloudwatch get-metric-statistics --region <REGION> \
  --namespace AWS/FSx --metric-name DataReadBytes \
  --dimensions Name=FileSystemId,Value=<FSID> \
  --start-time "$(date -u -d '3 hours ago' +%Y-%m-%dT%H:%M:%S)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%S)" \
  --period 60 --statistics Sum Maximum
```

The full per-filesystem-type metric catalog is in [references/perf-details.md § Filesystem](references/perf-details.md#filesystem).

### Branches

**Provisioned capacity is saturated.** CloudWatch utilization sustained near 100% across the workload window. Customer decision: scale up the filesystem.

- FSx for Lustre throughput scales with `StorageCapacity × PerUnitStorageThroughput`; capacity changes are non-disruptive.
- FSx for OpenZFS — increase provisioned IOPS or throughput.

**I/O pattern is inefficient.** CloudWatch shows headroom but the workload is still I/O-bound. Customer decision: change the application.

- DataLoader: raise `num_workers`, set `pin_memory=True`, `persistent_workers=True`.
- Checkpointing: use async + sharded (`torch.distributed.checkpoint.async_save` plus FSDP `SHARDED_STATE_DICT`). `FULL_STATE_DICT` serializes through rank 0 and is a frequent root cause.
- Small-file workloads: Lustre is optimized for large sequential I/O. For millions of small files, use WebDataset / tar shards, FSx for OpenZFS, or NVMe scratch.

Filesystem-selection guidance and the async-checkpoint pattern are in [references/perf-details.md § Filesystem](references/perf-details.md#filesystem).

---

## Continuous health coverage

Once the immediate incident is diagnosed, recommend HyperPod's built-in health features so problems are caught before the next training run rather than after another customer-reported regression.

- **Enable `NodeRecovery=Automatic`** on the cluster. The Health Monitoring Agent (HMA) continuously monitors GPU- and Trainium-based instances and marks instances unhealthy on detected failure. With auto-recovery enabled, HyperPod reboots or replaces the node — no operator intervention.
- **Enable `OnStartDeepHealthChecks` on every GPU instance group** with both check categories:
  - `InstanceStress` — `stress-ng` on CPU/memory/disk, GPU and PCI device count verification, DCGM level-4 diagnostics (memory test included), and EFA loopback bandwidth/latency.
  - `InstanceConnectivity` — multi-node NCCL all-reduce.

  Every newly provisioned or auto-replaced node passes the same hardware bar before accepting jobs.

- **Run on-demand deep health checks** when this skill or any sibling surfaces a hardware concern but the cluster is mid-workload. `aws sagemaker start-cluster-health-check` runs the same checks against a specific instance group; nodes are placed in a Slurm maintenance reservation and the check is queued until any running job completes (not preempted). Console: **HyperPod → Clusters → Instances → Run deep health checks**.

  Not supported when `NodeProvisioningMode=Continuous`; one on-demand request per cluster at a time. Requires the latest AMI — run `UpdateClusterSoftware` first.

Logs land in CloudWatch at `/aws/sagemaker/Clusters/<cluster_name>/<cluster_id>` under `DeepHealthCheckResults/<log_stream_id>`, and on each node at `/var/log/aws/clusters/sagemaker-deep-health-check.log`.

## References

- [references/perf-details.md](references/perf-details.md) — pairwise NCCL test recipes, HyperPod topology check, GB200 NVL72 placement; CloudWatch metric catalog per filesystem type, async-checkpoint pattern, filesystem selection guide.

External:

- Amazon SageMaker HyperPod troubleshooting guide (official): <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>
- AI-on-HyperPod NCCL performance tests (expected `busbw` per SKU): <https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests>
- Amazon SageMaker HyperPod resiliency (NodeRecovery, HMA, auto-resume): <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency.html>
- Amazon SageMaker HyperPod deep health checks: <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-deep-health-checks.html>
- StartClusterHealthCheck API: <https://docs.aws.amazon.com/sagemaker/latest/APIReference/API_StartClusterHealthCheck.html>
- Amazon EC2 instance topology / network-node-layer labels: <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-topology-works.html>
- Amazon FSx for Lustre performance: <https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html>
- Amazon FSx for OpenZFS metrics: <https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/fsx-openzfs-metrics.html>
- AWS Elastic Fabric Adapter and NCCL: <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl.html>
- awslabs/awsome-distributed-training NCCL tests: <https://github.com/awslabs/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests>
