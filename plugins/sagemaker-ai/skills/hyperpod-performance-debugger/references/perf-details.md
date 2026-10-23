# Performance Details

Supplementary detail for `hyperpod-performance-debugger`. Two sections, matching the two scenarios the parent SKILL.md covers.

## Contents

1. [Uneven NCCL](#uneven-nccl)
2. [Filesystem](#filesystem)
3. [References](#references)

---

## Uneven NCCL

### Pairwise NCCL all-reduce test

Use the `nccl-tests` recipes from [awslabs/awsome-distributed-training](https://github.com/awslabs/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests). The repo ships `micro-benchmarks/nccl-tests/slurm/nccl-tests-container.sbatch` and a topology-aware pairwise sweep under `micro-benchmarks/nccl-tests/slurm/topology-aware-nccl-tests/`. For an N-node cluster, run all-reduce across every pair and record `busbw` for each pair. Pairs more than ~5% below the run mean (the threshold the AWS validation script flags) are straggler candidates.

The topology-aware submit script uses `sbatch --array` to fan out pairwise jobs. The repo also ships `process_nccl_results.sh` as a CSV post-processor for the raw test output; it does not itself apply an outlier threshold — compare results against the published expected `busbw`.

**Single-pair run on Slurm:**

```bash
sbatch -N 2 -w <NODE_A>,<NODE_B> nccl-tests-container.sbatch
```

**N-node aggregate run from a prebuilt container with NCCL + nccl-tests + aws-ofi-nccl baked in:**

```bash
srun -N <N> --mpi=pmix /path/in/container/all_reduce_perf -b 8 -e 8G -f 2 -g 8
```

### Expected bandwidth

Always benchmark the specific SKU before relying on a number — averages across message sizes are misleading; focus on the message sizes the workload actually uses. AWS publishes expected `busbw` per SKU in the AI-on-HyperPod NCCL test guide.

### EFA error-counter check (host)

Non-zero per-port counters mean packet loss or link issues. The data point names a specific node; route to `hyperpod-node-debugger` § A (EFA / Security Group) for the deeper read.

**Check per-port EFA error counters via SSM:**

```bash
for dev in /sys/class/infiniband/*/; do
  name=$(basename "$dev")
  rcv_err=$(cat "$dev/ports/1/counters/port_rcv_errors" 2>/dev/null)
  xmit_disc=$(cat "$dev/ports/1/counters/port_xmit_discards" 2>/dev/null)
  if [ "$rcv_err" != "0" ] || [ "$xmit_disc" != "0" ]; then
    echo "PROBLEM: $name rcv_errors=$rcv_err xmit_discards=$xmit_disc"
  fi
done
```

EFA firmware should also match across nodes (compare via `hyperpod-version-checker`):

```bash
cat /sys/class/infiniband/*/fw_ver 2>/dev/null
```

### HyperPod topology surfaces

HyperPod models co-location through three operator-visible surfaces — check each one that applies to the cluster.

**Validate per-node AZ and UltraServer assignment via the HyperPod API:**

```bash
for id in $(aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
             --query 'ClusterNodeSummaries[*].InstanceId' --output text); do
  aws sagemaker describe-cluster-node --cluster-name <C> --region <R> \
    --node-id "$id" \
    --query 'NodeDetails.{ID:InstanceId,AZ:Placement.AvailabilityZone,AZID:Placement.AvailabilityZoneId,UltraServer:UltraServerInfo.Id}' \
    --output table
done
```

**Check EKS topology labels:**

```bash
kubectl get nodes -L \
  topology.kubernetes.io/zone,\
  topology.k8s.aws/network-node-layer-1,\
  topology.k8s.aws/network-node-layer-2,\
  topology.k8s.aws/network-node-layer-3,\
  topology.k8s.aws/ultraserver-id
```

**Check Slurm topology:**

```bash
scontrol show topology
grep -E 'TopologyPlugin|BlockSizes' \
  /var/spool/slurm/slurm.conf /var/spool/slurm/topology.conf 2>/dev/null
```

Tightly coupled work should share the same AZ, the same highest-numbered `network-node-layer-*` label (EKS) or the same Slurm topology block, and — for NVL72 jobs — the same `UltraServerInfo.Id` / `topology.k8s.aws/ultraserver-id`. If the cluster is spread across AZs or layers, co-location has to be re-established at provisioning time. Route provisioning changes to `hyperpod-cluster-debugger` § B (Capacity & AZ).

### EFA version consistency

All nodes in the training group must run identical EFA and OFI-NCCL versions. Mismatches can materially degrade pairwise bandwidth. Compare across nodes via `hyperpod-version-checker`.

### GB200 NVL72 UltraServer

`p6e-gb200.36xlarge` is fundamentally different from p5/p6-b200. One UltraServer = 18 instances × 4 Blackwell GPUs = 72 GPUs inside one NVLink domain, stitched across the 18 instances by NVIDIA IMEX.

For uneven-NCCL triage on NVL72:

- If the variance is **inside one UltraServer**, the IMEX / NVLink fabric is a candidate. Surface `nvidia-smi topo -m` and `systemctl status nvidia-fabricmanager` as data points; route to `hyperpod-node-debugger` § G for the deeper read. Fabric failures hard-fail CUDA init with SXid errors rather than silently degrading, so a clean `nvidia-smi` typically rules out the fabric.
- If the variance is **across UltraServers**, the workload placement could be wrong — the NVL72 is meant to contain a single tight-coupled group. Verify the auto-configured `topology/block` (Slurm, `BlockSizes=18`) or the EKS `topology.k8s.aws/ultraserver-id` label.

---

## Filesystem

### CloudWatch metrics per filesystem type

All metrics live in the `AWS/FSx` namespace. Dimension: `FileSystemId`.

#### FSx for Lustre (`FileSystemType: LUSTRE`)

| Metric                    | What it means                                | Statistic |
| ------------------------- | -------------------------------------------- | --------- |
| `DataReadBytes`           | Aggregate read throughput (Bytes)            | Sum       |
| `DataWriteBytes`          | Aggregate write throughput (Bytes)           | Sum       |
| `MetadataOperations`      | File-open, stat, readdir rate (Count)        | Sum       |
| `FreeDataStorageCapacity` | Remaining bytes — low values throttle writes | Minimum   |
| `DiskIopsUtilization`     | % of provisioned IOPS in use (Percent)       | Maximum   |

Lustre throughput scales as `StorageCapacity_TiB × PerUnitStorageThroughput_MBps`. Capacity changes are non-disruptive.

#### FSx for OpenZFS (`FileSystemType: OPENZFS`)

| Metric                                       | What it means                              | Statistic        |
| -------------------------------------------- | ------------------------------------------ | ---------------- |
| `DataReadBytes` / `DataWriteBytes`           | Aggregate throughput (Bytes)               | Sum              |
| `DataReadOperations` / `DataWriteOperations` | Client IOPS (Count)                        | Sum              |
| `NetworkThroughputUtilization`               | % of provisioned network throughput in use | Average, Maximum |
| `FileServerDiskIopsUtilization`              | % of disk IOPS in use                      | Average, Maximum |
| `FileServerDiskThroughputUtilization`        | % of disk throughput in use                | Average, Maximum |
| `CPUUtilization`                             | File server CPU %                          | Average, Maximum |

The utilization metrics (percent) are the authoritative saturation signals. There is no `ReadIOPS` metric in `AWS/FSx` — that is an EBS metric.

#### EBS (`AWS/EBS` namespace)

`VolumeReadOps`, `VolumeWriteOps`, `VolumeQueueLength`. A sustained `VolumeQueueLength > 1` typically indicates the volume is the bottleneck. For `gp3`, also compare against the provisioned IOPS / throughput configured on the volume.

### NVMe (instance-local)

Mounted at `/opt/dlami/nvme`. **Ephemeral** — data is lost on stop, replace, or hardware failure. Use for scratch and caches, not persistent state. Available capacity varies by instance type.

### Secondary EBS volume (`/opt/sagemaker`)

The secondary EBS volume is the persistent per-instance storage HyperPod attaches at `/opt/sagemaker`. It is configured per instance group via `ClusterEbsVolumeConfig` (root volume is fixed; secondary is what you size). When the volume backing it fills up and the customer needs more space, there are two paths.

#### Path 1 — Resize via the instance group (takes effect on replacement)

`ClusterEbsVolumeConfig` carries `VolumeSizeInGB` on each instance group. Update the instance group with a larger value via `UpdateCluster` call or CloudFormation/Terraform.

Important: the new size applies to **newly provisioned or replaced nodes**, not to running nodes. Existing nodes keep their original secondary EBS until they're replaced (auto-recovery, on-demand deep health check that fails, or `BatchReplaceClusterNodes`).

When to use this path:

- The customer wants the new size to be the standard for the instance group going forward.
- A rolling replacement is acceptable (data on `/opt/sagemaker` of the existing nodes does not survive replacement — checkpoints / artifacts on shared storage like FSx are unaffected).

#### Path 2 — Attach an extra EBS volume to a running node (EKS only)

`AttachClusterNodeVolume` attaches an existing EBS volume to a running HyperPod EKS node without replacement. This is the EBS CSI driver path — typically driven by Kubernetes PersistentVolumeClaims rather than called directly, but the API is available for ad-hoc attachment.

Constraints (per the API):

- EKS-orchestrated cluster only; the cluster must be `InService`.
- The target node cannot be in a Restricted Instance Group (RIG).
- The EBS volume must already exist and be in the `available` state, in the same AZ as the node.
- A complementary `DetachClusterNodeVolume` removes the volume.

### Filesystem selection by pattern

| Pattern                       | Best fit                               | Why                                     |
| ----------------------------- | -------------------------------------- | --------------------------------------- |
| Large sequential I/O          | FSx for Lustre                         | Striping scales with OSTs               |
| Small random I/O, mixed reads | FSx for OpenZFS                        | POSIX + better small-file performance   |
| Temporary high-perf scratch   | NVMe (`/opt/dlami/nvme`)               | High aggregate throughput, zero network |
| Single-node persistent        | EBS (`/opt/sagemaker`)                 | 100 GiB root is too small; EBS sized    |
| Datasets (cold + warm)        | S3 + Mountpoint-S3 for streaming reads | Scales infinitely, no provisioned limit |

For HyperPod Slurm, the default lifecycle script offers FSx for OpenZFS as an alternative to Lustre for home directories — useful when the home tree has small-file metadata pressure.

---

## References

- Amazon SageMaker HyperPod troubleshooting guide (official): <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>
- AI-on-HyperPod NCCL performance test guide (expected `busbw` per SKU): <https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/slurm-orchestration/validation-and-testing/performance-testing/nccl-tests>
- AI-on-HyperPod GPU stress testing: <https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/validation-and-testing/performance-testing/gpu-stress-testing>
- Amazon SageMaker HyperPod resiliency (NodeRecovery, Health Monitoring Agent, auto-resume): <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency.html>
- Amazon SageMaker HyperPod deep health checks: <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-deep-health-checks.html>
- AWS Elastic Fabric Adapter and NCCL: <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl.html>
- Amazon FSx for Lustre performance: <https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html>
- Amazon FSx for OpenZFS metrics: <https://docs.aws.amazon.com/fsx/latest/OpenZFSGuide/fsx-openzfs-metrics.html>
- awslabs/awsome-distributed-training NCCL tests: <https://github.com/awslabs/awsome-distributed-training/tree/main/micro-benchmarks/nccl-tests>
- Amazon EC2 instance topology (network-node-layer ordering): <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-topology-works.html>
