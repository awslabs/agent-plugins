# Cluster Operations Reference

Operational deep-dives for the hyperpod-cluster-debugger skill. See SKILL.md for the workflow entry points.

---

## 1. EFA Security Group (multi-SG clusters)

The EFA health check runs during instance provisioning, **before** lifecycle scripts execute. If it fails, lifecycle scripts never run and CloudWatch lifecycle logs are empty — the cluster event will say `"EFA health checks did not run successfully"`.

When a cluster uses multiple security groups, **all** SGs must have the self-referencing rules. Check each:

```bash
for SG in $(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'VpcConfig.SecurityGroupIds[]' --output text); do
  echo "=== $SG ==="
  aws ec2 describe-security-groups --group-ids $SG --region <R> \
    --query 'SecurityGroups[0].{In:IpPermissions,Out:IpPermissionsEgress}'
done
```

Fix commands are in [cluster-diagnostics-detail.md § A](cluster-diagnostics-detail.md#a-efa-health-checks).

---

## 2. Capacity

See [capacity-planning.md](capacity-planning.md).

---

## 3. Lifecycle scripts

See [lifecycle-scripts.md](lifecycle-scripts.md).

---

## 4. EKS access control

### Authentication modes

Access entries require `API` or `API_AND_CONFIG_MAP`. If the cluster is on `CONFIG_MAP` only, `aws eks list-access-entries` returns nothing useful; verify the mode with `describe-cluster --query 'cluster.accessConfig.authenticationMode'` and consult the EKS access-entries documentation for the switching procedure.

### Access policies (EKS-native)

| Policy                        | Scope        | Use case                       |
| ----------------------------- | ------------ | ------------------------------ |
| `AmazonEKSClusterAdminPolicy` | Cluster-wide | Full admin (debugging)         |
| `AmazonEKSAdminPolicy`        | Namespace    | Namespace admin (multi-tenant) |
| `AmazonEKSEditPolicy`         | Namespace    | Read/write workloads           |
| `AmazonEKSViewPolicy`         | Namespace    | Read-only                      |

### Troubleshooting kubectl auth

```bash
aws sts get-caller-identity            # your identity
kubectl config current-context         # which cluster kubeconfig points at
kubectl cluster-info                   # API server reachable?
```

If using an assumed role: **access entries reference the IAM role ARN, not the assumed-role session ARN.**

- Role ARN: `arn:aws:iam::123456789012:role/MyRole`
- Session ARN: `arn:aws:sts::123456789012:assumed-role/MyRole/session-name`

---

## 5. Continuous Provisioning (EKS only)

The cluster transitions to `InService` once the control plane is ready; instances are created asynchronously and failures are reported as events, not cluster failures. Failed instances can be individually replaced.

```bash
# Poll instance creation:
watch -n 30 "aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'InstanceGroups[*].{Name:InstanceGroupName,Current:CurrentCount,Target:InstanceCount}' --output table"

# Poll cluster events:
watch -n 30 "aws sagemaker list-cluster-events --cluster-name <C> --region <R> \
  --query 'ClusterEventSummaries[0:5].{Time:EventTime,Msg:Message}' --output table"
```

### Nodes in `list-cluster-nodes` but not in `kubectl get nodes`

1. Check lifecycle script logs — it registers the node with EKS
2. Verify the EKS endpoint is reachable from worker subnets
3. Check kubelet on the node via SSM
4. Verify the node's IAM role has `AmazonEKSWorkerNodePolicy`

> Cluster events are emitted for HyperPod EKS. For HyperPod Slurm, events are not yet surfaced — use CloudWatch logs and `list-cluster-nodes` instead.

---

## 6. SSM target format

See the `hyperpod-ssm` skill's `SKILL.md` for the target format (`sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>`), prerequisites, and manual-command examples. HyperPod requires `start-session` — not `send-command` against raw instance IDs.

---

## 7. Node replacement (batch APIs)

Full Suggested-command blocks with preconditions + blast radius are in [cluster-diagnostics-detail.md § G.2](cluster-diagnostics-detail.md#g2-manual-replacement). Summary:

- Cluster must be `InService`
- Batch limit: **1-25 node IDs per call** for both APIs
- `batch-replace-cluster-nodes` destroys root + secondary volumes and is not supported on Slurm controller nodes — back up first
- Monitor with `list-cluster-events` after the call
- Prefer batch APIs over legacy paths (Slurm reason fields, K8s labels)

---

## 8. Slurm — controller operations

The per-node Slurm operations (resuming a single node, fixing a single Slurm state) live in the `hyperpod-node-debugger` skill. This section is controller-level only.

### Diagnose controller health (via SSM on the controller)

```bash
scontrol ping                                     # slurmctld responsive?
systemctl status slurmctld                        # service state
systemctl is-active munge && systemctl status munge   # auth daemon (required)
systemctl is-active slurmdbd                      # accounting DB (if used)
```

### slurmctld down

```bash
journalctl -u slurmctld --since "1 hour ago" --no-pager | tail -100
tail -200 /var/log/slurm/slurmctld.log
```

Common causes and fixes:

- **OOM on controller**: restart the service; investigate the job scale that triggered it.
- **Munge auth failure** (`Invalid authentication credential`): munge key mismatch. Re-sync `/etc/munge/munge.key` to every node, restart munge + slurmctld.
- **Accounting DB unreachable** (slurmdbd + MariaDB / RDS): check network path and credentials. slurmctld won't start if accounting is required but unreachable.
- **Config error in `slurm.conf`**: `slurmctld -D -vvv` (foreground) prints the parse error. Roll back to the last known-good config.

### Fix — restart slurmctld

Customer-run on the Slurm controller (via SSM) after the root cause is diagnosed. Running jobs, pending queue, and node states are preserved; caches and resource calculations reset. Brief scheduler pause.

```bash
sudo systemctl restart slurmctld
scontrol ping   # expect "Slurmctld(primary) is UP"
```

If `slurm.conf` is broken the service will not return — roll back the config first.

### munge inactive

Diagnose:

```bash
systemctl status munge
ls -l /etc/munge/munge.key   # expect munge:munge, mode 0400
sudo md5sum /etc/munge/munge.key   # must match on controller + every compute node
```

### Fix — start munge

Customer-run. Safe when `munge` is inactive and the key file is present and matches other nodes.

```bash
sudo systemctl start munge
```

If md5 mismatches another node, jobs will still fail auth — re-distribute the controller's key cluster-wide and restart munge on every node.

### Stuck jobs (PENDING / COMPLETING / CONFIGURING)

```bash
squeue -o "%i %j %T %R %N" --noheader | grep -iE "COMPLETING|CONFIGURING|PENDING"
scontrol show job <JOBID>
scancel <JOBID>               # if safe to cancel
```

Common reason codes:

- `(Resources)` — waiting for free nodes. Check `sinfo -o "%P %a %l %D %T"`.
- `(AssocGrpNodeLimit)` / `(QOSMaxJobsPerUserLimit)` — quota-related. `sacctmgr show assoc`.
- `(NodeDown)` — partition has no healthy nodes. Use the `hyperpod-node-debugger` skill.
- `(BeginTime)` — scheduled for a future start time.

Restarting slurmctld to clear stuck-job symptoms uses the same Suggested-command block as above (§ slurmctld down).

### Verify after remediation

```bash
scontrol ping                                   # "Slurmctld(primary) is UP"
sinfo                                            # no "down*" or "drain" states
systemctl is-active slurmctld munge
scontrol show config | grep StateSaveLocation   # must be persistent + writable
```

---

## 9. Filesystem performance

Symptom: training bottlenecked by data loading, checkpoint save / load, or slow executable / script loading.

### Diagnose on the node

```bash
mount | grep -E "fsx|nfs|lustre|ebs|nvme"
df -hT
iostat -x 1 5                 # per-device throughput / IOPS / utilization

# FSx for Lustre:
lfs df -h                     # per-OST utilization (uneven = hotspot)
lfs getstripe <path>          # striping config; wider = more parallelism

# FSx for OpenZFS / NFS:
nfsstat -m                    # per-mount retransmissions / wait times
nfsiostat 5                   # ops/s, throughput, RTT

# EBS:
lsblk -o NAME,TYPE,SIZE,MOUNTPOINT
```

### CloudWatch (from your workstation)

```bash
# FSx for Lustre throughput saturation:
aws cloudwatch get-metric-statistics \
  --namespace AWS/FSx --metric-name DataReadBytes \
  --dimensions Name=FileSystemId,Value=<FSxId> \
  --statistics Sum --period 300 \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region <REGION>
# Also: DataWriteBytes, FreeDataStorageCapacity, MetadataOperations

# EBS throughput / IOPS:
aws cloudwatch get-metric-statistics \
  --namespace AWS/EBS --metric-name VolumeReadOps \
  --dimensions Name=VolumeId,Value=<vol-id> \
  --statistics Sum --period 60 \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region <REGION>
# Also: VolumeWriteOps, VolumeReadBytes, VolumeWriteBytes, BurstBalance
```

### Interpret

| Signal                                              | Interpretation                         | Action                                                                           |
| --------------------------------------------------- | -------------------------------------- | -------------------------------------------------------------------------------- |
| FSx Lustre `DataReadBytes` sustained at the ceiling | Throughput ceiling hit                 | Increase throughput-per-TiB or grow storage (throughput scales with size)        |
| FSx Lustre metadata ops saturated                   | Small-file workload on Lustre          | Move small-file traffic to FSx for OpenZFS; keep Lustre for large sequential I/O |
| FSx OpenZFS `TotalIOps` near provisioned IOPS       | IOPS ceiling hit                       | Increase provisioned IOPS                                                        |
| EBS `BurstBalance` draining to 0 on `gp2`           | Baseline IOPS insufficient             | Migrate to `gp3` or `io2` with provisioned IOPS / throughput                     |
| `iostat %util` > 90% on a mount device              | Local device saturated                 | If NVMe instance store: at hardware ceiling, change data layout                  |
| Slow only at checkpoint time                        | Write amplification (many small files) | Consolidate checkpoints; rank-0 writer patterns                                  |

### Choose the right filesystem

| Workload                                                         | Best fit                                |
| ---------------------------------------------------------------- | --------------------------------------- |
| Large sequential reads (datasets >> 1 MiB), many-reader training | FSx for Lustre                          |
| Small-file / metadata-heavy / mixed random I/O                   | FSx for OpenZFS                         |
| Single-instance scratch                                          | EBS `gp3` or `io2`                      |
| Highest per-GPU throughput, ephemeral                            | NVMe instance store (`/opt/dlami/nvme`) |

For HyperPod Slurm, the default lifecycle script supports FSx for OpenZFS for `/home` — evaluate it if home is on Lustre and you see metadata-op saturation.

### Verify after remediation

- CloudWatch: throughput / IOPS climbs past the old flat-line
- Training step time drops; data-loading fraction of step time drops
- `iostat %util` stays below 80% under sustained load
