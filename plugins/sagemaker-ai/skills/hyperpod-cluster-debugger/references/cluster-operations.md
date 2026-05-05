# Cluster Operations Reference

Detailed operational procedures, decision trees, and background context for each
issue type covered by the hyperpod-cluster-debugger skill. See SKILL.md for
quick-reference workflow.

---

## 1. EFA Security Group Configuration (Deep Dive)

### Why Self-Referencing Rules Are Required

HyperPod uses Elastic Fabric Adapter (EFA) for high-bandwidth, low-latency
inter-node communication during distributed training. EFA requires:

- **Inbound self-ref**: Nodes receive RDMA and TCP traffic from other nodes in the same SG
- **Outbound self-ref**: Nodes send RDMA and TCP traffic to other nodes in the same SG
- **Outbound 0.0.0.0/0**: Nodes reach AWS API endpoints (SageMaker, S3, CloudWatch, SSM)

Without the outbound self-referencing rule, the EFA health check performed during
cluster creation will fail — even if nodes could otherwise communicate via TCP.

### EFA Health Check Timing

The EFA health check runs during instance provisioning, **before** lifecycle scripts
execute. This means:

- If EFA health check fails, lifecycle scripts never run
- CloudWatch logs may be empty (scripts didn't execute)
- The cluster event will explicitly say "EFA health checks did not run successfully"

### Multi-SG Clusters

If a cluster uses multiple security groups, **all** SGs must have self-referencing
rules. AWS applies SGs as a union for inbound and intersection for outbound —
meaning a restrictive SG can block EFA even if another SG allows it.

```bash
# List all SGs for a cluster
aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'VpcConfig.SecurityGroupIds' --output json

# Check each one
for SG in $(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'VpcConfig.SecurityGroupIds[]' --output text); do
  echo "=== $SG ==="
  aws ec2 describe-security-groups --group-ids $SG --region <R> \
    --query 'SecurityGroups[0].{In:IpPermissions,Out:IpPermissionsEgress}'
done
```

---

## 2. Capacity Management

### Instance Type Availability by AZ

Not all instance types are available in all AZs. GPU instances (p4d, p5, trn1)
are particularly constrained. Always verify before creating a cluster:

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=ml.p5.48xlarge" \
  --region us-west-2 \
  --query 'InstanceTypeOfferings[*].Location' --output table
```

### Flexible Training Plans Workflow

1. **Search** for available capacity:

   ```bash
   aws sagemaker search-training-plan-offerings \
     --instance-type ml.p5.48xlarge \
     --instance-count 16 \
     --duration-hours 720 \
     --region <REGION>
   ```

2. **Purchase** the training plan (returns a TrainingPlanArn)

3. **Reference** in cluster config:
   - Set `TrainingPlanArn` in the instance group configuration
   - Ensure the subnet AZ matches the capacity reservation AZ

### Common Capacity Error Patterns

| Error                                  | Meaning                                           | Fix                                           |
| -------------------------------------- | ------------------------------------------------- | --------------------------------------------- |
| `Insufficient capacity`                | No instances available in the AZ                  | Try different AZ; use Flexible Training Plans |
| `No subnets in the capacity AZ`        | Subnet doesn't cover the AZ where capacity exists | Add subnet in correct AZ                      |
| `Cannot provision requested instances` | Instance type not available                       | Check AZ availability; contact account team   |
| Capacity error despite TrainingPlanArn | AZ mismatch between plan and subnet               | Verify subnet AZ matches plan AZ              |

---

## 3. Lifecycle Script Debugging

### Log Locations

| Log Type                   | Location                                                                                 | When Available                |
| -------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------- |
| Lifecycle script output    | CloudWatch: `/aws/sagemaker/Clusters/<name>/<id>` → `LifecycleConfig/<group>/<instance>` | After script starts executing |
| Provisioning log (on node) | `/var/log/provision/provisioning.log` (via SSM)                                          | After node boots              |
| Health monitoring          | CloudWatch: same log group → `SagemakerHealthMonitoringAgent/<group>/<instance>`         | After agent starts            |

### Lifecycle Script Execution Order

1. Node boots and gets base AMI
2. EFA health check runs (if applicable)
3. Node metadata is written to `/opt/ml/config/resource_config.json`
4. Lifecycle script is downloaded from S3
5. Script executes as root
6. If script exits 0, node joins cluster
7. If script exits non-zero or times out, provisioning fails

### Testing Lifecycle Scripts Locally

Before deploying, validate scripts:

```bash
# Check for Windows line endings
file lifecycle_script.sh
# Should say "ASCII text" NOT "ASCII text, with CRLF line terminators"

# Convert if needed
dos2unix lifecycle_script.sh

# Verify shebang
head -1 lifecycle_script.sh
# Should be: #!/bin/bash

# Syntax check
bash -n lifecycle_script.sh

# Check for common issues
shellcheck lifecycle_script.sh 2>/dev/null || true
```

### Default Lifecycle Script Repositories

Always compare against the latest upstream versions:

- **EKS**: `https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/7.sagemaker-hyperpod-eks/LifecycleScripts/base-config`
- **Slurm**: `https://github.com/aws-samples/awsome-distributed-training/tree/main/1.architectures/5.sagemaker-hyperpod/LifecycleScripts/base-config`

---

## 4. EKS Access Control

### Authentication Modes

| Mode                 | Description                    | HyperPod Support        |
| -------------------- | ------------------------------ | ----------------------- |
| `CONFIG_MAP`         | Legacy aws-auth ConfigMap only | **Not supported**       |
| `API`                | IAM access entries only        | Supported               |
| `API_AND_CONFIG_MAP` | Both methods                   | Supported (recommended) |

### Access Entry Types

| Policy                        | Scope        | Use Case                       |
| ----------------------------- | ------------ | ------------------------------ |
| `AmazonEKSClusterAdminPolicy` | Cluster-wide | Full admin access (debugging)  |
| `AmazonEKSAdminPolicy`        | Namespace    | Namespace admin (multi-tenant) |
| `AmazonEKSEditPolicy`         | Namespace    | Read/write workloads           |
| `AmazonEKSViewPolicy`         | Namespace    | Read-only                      |

### Troubleshooting kubectl Auth

```bash
# 1. Verify identity
aws sts get-caller-identity

# 2. Check kubeconfig context
kubectl config current-context
kubectl config view --minify

# 3. Verify EKS API reachability
kubectl cluster-info

# 4. If using assumed role, check the role ARN matches the access entry
# Access entries use the role ARN, not the assumed-role session ARN
# Role ARN:          arn:aws:iam::123456789012:role/MyRole
# Session ARN:       arn:aws:sts::123456789012:assumed-role/MyRole/session-name
# Access entry must reference the IAM role ARN, not the session ARN
```

---

## 5. Continuous Provisioning (EKS)

### How It Works

In traditional provisioning, the cluster waits until all instances are ready
before transitioning to InService. With Continuous Provisioning:

1. Cluster transitions to InService as soon as the control plane is ready
2. Instances are created asynchronously
3. Instance failures are reported as events, not cluster failures
4. Failed instances can be individually replaced

### Monitoring Instance Creation

```bash
# Poll cluster events for provisioning updates
watch -n 30 "aws sagemaker list-cluster-events --cluster-name <C> --region <R> \
  --query 'ClusterEventSummaries[0:5].{Time:EventTime,Msg:Message}' --output table"

# Check instance group fill rate
watch -n 30 "aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'InstanceGroups[*].{Name:InstanceGroupName,Current:CurrentCount,Target:InstanceCount}' --output table"
```

### When Nodes Don't Appear in kubectl

If `list-cluster-nodes` shows nodes but `kubectl get nodes` doesn't:

1. Check lifecycle script logs — the script registers nodes with EKS
2. Verify the EKS cluster endpoint is reachable from worker subnets
3. Check if kubelet is running on the node (via SSM)
4. Verify the node's IAM role has the `AmazonEKSWorkerNodePolicy`

---

## 6. SSM Target Format

### Format Specification

```
sagemaker-cluster:<CLUSTER_ID>_<INSTANCE_GROUP_NAME>-<INSTANCE_ID>
```

- `CLUSTER_ID`: The alphanumeric ID from the cluster ARN (not the cluster name)
- `INSTANCE_GROUP_NAME`: The instance group name as configured
- `INSTANCE_ID`: The EC2 instance ID (e.g., `i-0abc123def456789`)

### Constructing the Target

```bash
# Get cluster ID
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'ClusterArn' --output text | cut -d/ -f2)

# List nodes with group info
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,Group:InstanceGroupName}' --output table

# Construct target
TARGET="sagemaker-cluster:${CLUSTER_ID}_<group-name>-<instance-id>"
```

### Common SSM Mistakes

| Mistake                          | Example                                     | Correct                                 |
| -------------------------------- | ------------------------------------------- | --------------------------------------- |
| Using bare instance ID           | `i-0abc123`                                 | `sagemaker-cluster:xyz_group-i-0abc123` |
| Using cluster name instead of ID | `sagemaker-cluster:my-cluster_...`          | Use cluster ID from ARN                 |
| Wrong region                     | `--region us-east-1` (cluster in us-west-2) | Match cluster region                    |
| Missing SSM plugin               | `SessionManagerPlugin is not found`         | Install plugin first                    |

### SSH over SSM

Add to `~/.ssh/config`:

```
Host hyperpod-<node-name>
  HostName sagemaker-cluster:<cluster-id>_<group>-<instance-id>
  User ubuntu
  IdentityFile ~/keys/my-key.pem
  ProxyCommand aws --profile default --region <REGION> ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p
```

**Important:** Add your SSH public key to `~/.ssh/authorized_keys` on the target node via an SSM session before using SSH over SSM.

---

## 7. Node Replacement Decision Tree

```
Node appears unhealthy
    │
    ├── Is NodeRecovery enabled?
    │   ├── No → Enable via update-cluster, or trigger manual replacement
    │   └── Yes ↓
    │
    ├── Has health agent detected the issue?
    │   ├── Check health monitoring CW logs
    │   ├── EKS: check node-health-status label
    │   ├── Slurm: check sinfo reason (must be "Action:Replace" or "Action:Reboot")
    │   └── If not detected → wait for next cycle or trigger manually
    │
    ├── Was replacement triggered?
    │   ├── Check cluster events for replacement activity
    │   └── If triggered ↓
    │
    ├── Did replacement succeed?
    │   ├── Check lifecycle script logs for new instance
    │   ├── If lifecycle script failed → fix script, retry
    │   ├── If capacity error → check AZ, use reserved capacity
    │   └── If succeeded → verify new node is healthy
    │
    └── Manual fallback
        ├── Try reboot first: batch-reboot-cluster-nodes
        └── If reboot doesn't help: batch-replace-cluster-nodes
```

### Batch API Commands

**Reboot** (less disruptive — preserves node identity):

```bash
aws sagemaker batch-reboot-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["i-0abc123"]'
```

**Replace** (new instance — loses local state):

```bash
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <C> --region <R> \
  --node-ids '["i-0abc123"]'
```

**Notes:**

- Batch commands return success/failure indicating whether the service accepted the request
- Use `list-cluster-events` to monitor progress after the command
- **Limit: 25 node IDs per call.** For larger fleets, split into chunks of 25 and issue multiple calls. Passing more than 25 returns `ValidationException`.
- Cluster must be in `InService` state
- Legacy methods (Slurm node reason, K8s labels) are less reliable than batch commands

---

## 8. Slurm Node Name to Instance ID Mapping

### Background

On HyperPod Slurm clusters, nodes are named using their private IP addresses
in the format `ip-10-1-123-45`. Many AWS operations (SSM, node replacement,
CloudWatch logs) require the EC2 instance ID.

### Methods

**Method 1 — resource_config.json** (fastest, requires head node access):

```bash
NODE="ip-10-1-123-45"
IP=$(echo $NODE | sed 's/ip-//; s/-/./g')
sudo cat /opt/ml/config/resource_config.json | python3 -c "
import sys, json
data = json.load(sys.stdin)
ip = '$IP'
for group in data.get('InstanceGroups', []):
    for instance in group.get('Instances', []):
        if ip in str(instance.get('CustomerIpAddress', '')) or ip in str(instance.get('PrivateDnsName', '')):
            print(f\"InstanceId: {instance.get('InstanceId')}\")
            print(f\"Group: {group.get('Name')}\")
            print(f\"IP: {instance.get('CustomerIpAddress')}\")
"
```

**Method 2 — HyperPod APIs** (works from anywhere):

```bash
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,DNS:PrivateDnsHostname,Group:InstanceGroupName}' \
  --output table | grep "10.1.123.45"
```

**Method 3 — dump_cluster_nodes_info.py** (for recurring lookups on large clusters):

```bash
wget https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/tools/dump_cluster_nodes_info.py
python3 dump_cluster_nodes_info.py --cluster-name <C>
# Produces CSV: instance_id, private_ip, hostname, instance_type, az, status
```

---

## 9. Slurm-Specific Operations

Cluster-level Slurm operations — the per-node operations (resuming nodes, fixing individual Slurm states) live in the `hyperpod-node-debugger` skill.

### Diagnose controller health

```bash
# Via SSM on the controller node:
# 1. slurmctld is responding
scontrol ping

# 2. Controller state
systemctl status slurmctld

# 3. munge (auth) is running — without this, every slurm command fails
systemctl is-active munge
systemctl status munge

# 4. Accounting DB reachable (if slurmdbd is used)
systemctl is-active slurmdbd
```

### slurmctld is down

Check logs for root cause first:

```bash
# Look at the most recent lines for panics, OOM, DB auth failure:
journalctl -u slurmctld --since "1 hour ago" --no-pager | tail -100
tail -200 /var/log/slurm/slurmctld.log
```

Common causes:

- **Out of memory** (controller hit memory limit): restart the service, then investigate job scale that triggered the OOM.
- **Munge auth failure** (`Invalid authentication credential`): munge key mismatch between controller and nodes. Re-sync `/etc/munge/munge.key` via SSM on every node and restart munge + slurmctld.
- **Accounting DB unreachable**: if using slurmdbd + MariaDB/RDS, check network path and credentials. slurmctld will not start if accounting is required but unreachable.
- **Config error in slurm.conf**: `slurmctld -D -vvv` (foreground) prints the parse error. Roll back to the previous good `slurm.conf`.

Restart once the cause is resolved:

```bash
sudo systemctl restart slurmctld
scontrol ping   # must return "Slurmctld(primary) is UP"
```

### munge is inactive

```bash
sudo systemctl start munge
sudo systemctl status munge
# If start fails: check /etc/munge/munge.key ownership (must be munge:munge, mode 0400)
ls -l /etc/munge/munge.key
```

If the key file is present but auth still fails, check it is IDENTICAL across all nodes:

```bash
sudo md5sum /etc/munge/munge.key   # run on controller + a sample compute node
```

Mismatches break auth cluster-wide — re-distribute the controller's key to all nodes and restart munge everywhere.

### Stuck jobs (PENDING / COMPLETING / CONFIGURING)

```bash
# List stuck jobs
squeue -o "%i %j %T %R %N" --noheader | grep -iE "COMPLETING|CONFIGURING|PENDING"

# Inspect a specific job
scontrol show job <JOBID>

# Cancel (if safe to do so)
scancel <JOBID>

# For stuck COMPLETING jobs that won't clear, sometimes the only recovery is
# restarting slurmctld after identifying the stuck node(s).
```

Investigate the reason column — common `(Reason)` values:

- `(Resources)` — waiting for enough free nodes. Normal if cluster is busy; check `sinfo -o "%P %a %l %D %T"` to see why.
- `(AssocGrpNodeLimit)` / `(QOSMaxJobsPerUserLimit)` — quota-related. Check account limits with `sacctmgr show assoc`.
- `(NodeDown)` — partition has no healthy nodes. Fix with the `hyperpod-node-debugger` skill.
- `(BeginTime)` — job scheduled for a future start time.

### State preservation on restart

By default, `sudo systemctl restart slurmctld` preserves cluster state: running jobs keep executing, pending jobs stay in the queue, node states are restored from disk, and job history / accounting is intact. The restart clears only the controller's in-memory caches, stale comm channels, hung internal processes, and resource-allocation computations.

### Clean start (use with caution)

If the saved state is corrupted and a normal restart still loops, validate with `-c` (clean start — ignore saved state). **`slurmctld -c` does not exit on its own; it keeps running like a normal slurmctld but with a clean slate.** Do not run it alongside the systemd unit — they will fight for port 6817.

```bash
# IMPORTANT: drops all running jobs, pending queue, and saved node states.
# Notify users first — every running job will be lost.
sudo systemctl stop slurmctld

# Option A (recommended) — foreground validation, easy to abort:
sudo slurmctld -c -D -vvv 2>&1 | tee /tmp/slurmctld-clean.log
#   • Watch for "Slurmctld(primary) is UP"  (typically <10 s)
#   • Verify with a second shell: scontrol ping
#   • Ctrl-C to stop, then hand control back to systemd:
sudo systemctl start slurmctld
```

> **IMPORTANT:** do not add `-c` to a systemd drop-in unit. Persisting `-c` in
> `/etc/systemd/system/slurmctld.service.d/override.conf` means every future
> slurmctld restart (including automatic restarts after crashes and reboots)
> wipes all job state. If the one-shot above is the right call, use Option A
> only — do not edit the unit file.

Use only when state recovery is impossible and you have explicit user signoff.

### Verify after remediation

```bash
scontrol ping                              # must return "Slurmctld(primary) is UP"
sinfo                                      # nodes idle/alloc/mixed, no "down*" or "drain"
squeue -h | wc -l                          # queue length draining normally
systemctl is-active slurmctld munge
scontrol show config | grep StateSaveLocation   # confirm state dir is writable and populated
```

`StateSaveLocation` should point at a persistent path (typically under `/var/spool/slurmctld`); verify the directory exists and is owned by the `slurm` user. A missing or unwritable `StateSaveLocation` is the #1 cause of repeated restarts losing state.

---

## 10. Filesystem Performance

**Applies to**: Common (Slurm and EKS) — training bottlenecked by data loading, checkpoint save/load, or slow script/executable loading.

### Diagnose

Identify which filesystem is slow, then inspect provisioned performance vs. actual throughput.

```bash
# 1. From the node: what is mounted, and is anything pegged?
mount | grep -E "fsx|nfs|lustre|ebs|nvme"
df -hT
iostat -x 1 5                 # per-device throughput/IOPS/utilization

# 2. For FSx for Lustre — check mount options and per-OST throughput
lfs df -h                     # storage target utilization (uneven = hotspot)
lfs getstripe <path>          # striping config; wider stripe = more parallelism

# 3. For FSx for OpenZFS / NFS — check mount options and active I/O
nfsstat -m                    # per-mount retransmissions and wait times
nfsiostat 5                   # ops/s, throughput, avg RTT

# 4. For EBS — check volume type and I/O burst credits
lsblk -o NAME,TYPE,SIZE,MOUNTPOINT
```

Then in CloudWatch (from your workstation):

```bash
# FSx for Lustre — throughput saturation
aws cloudwatch get-metric-statistics \
  --namespace AWS/FSx \
  --metric-name DataReadBytes \
  --dimensions Name=FileSystemId,Value=<FSxId> \
  --statistics Sum --period 300 \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region <REGION>

# Also check: DataWriteBytes, FreeDataStorageCapacity, MetadataOperations

# EBS — throughput and IOPS ceiling
aws cloudwatch get-metric-statistics \
  --namespace AWS/EBS \
  --metric-name VolumeReadOps \
  --dimensions Name=VolumeId,Value=<vol-id> \
  --statistics Sum --period 60 \
  --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time   "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --region <REGION>

# Also check: VolumeWriteOps, VolumeReadBytes, VolumeWriteBytes, BurstBalance
```

### Interpret

| Signal                                                                 | Interpretation                            | Action                                                                                                |
| ---------------------------------------------------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| FSx Lustre `DataReadBytes` sustained at or near provisioned throughput | Throughput ceiling hit                    | Increase throughput-per-TiB, or grow storage capacity (throughput scales with size)                   |
| FSx Lustre metadata ops saturated                                      | Small-file workload on Lustre             | Switch small-file traffic to FSx for OpenZFS; keep Lustre for large sequential I/O                    |
| FSx OpenZFS `TotalIOps` near provisioned IOPS                          | IOPS ceiling hit                          | Increase provisioned IOPS on the filesystem                                                           |
| EBS `BurstBalance` draining to 0 on `gp2`                              | Baseline IOPS insufficient                | Migrate to `gp3` or `io2` and provision the IOPS and throughput you need                              |
| `iostat %util` > 90% on the mount device                               | Local device saturated                    | If `/dev/shm` → increase size; if NVMe instance store → already at hardware ceiling, move data layout |
| Slow only at checkpoint time                                           | Write amplification from many small files | Consolidate checkpoints; use rank-0 writer patterns (DCP `use_shard_dst`)                             |

### Choose the right filesystem for the workload

| Workload pattern                                                          | Best fit                                                 |
| ------------------------------------------------------------------------- | -------------------------------------------------------- |
| Large sequential reads (datasets >> 1 MiB), many-reader training          | FSx for Lustre                                           |
| Small-file / metadata-heavy / mixed random I/O (home dirs, logs, configs) | FSx for OpenZFS                                          |
| Single-instance scratch / checkpoint staging                              | EBS `gp3` or `io2`                                       |
| Highest per-GPU throughput, ephemeral                                     | NVMe instance store (`/opt/dlami/nvme`) — non-persistent |

HyperPod Slurm: the default lifecycle script lets you use FSx for OpenZFS for `/home`. Evaluate this if your home directory is on Lustre and you see metadata-op saturation.

### Upgrade provisioned performance

```bash
# FSx for Lustre — scale storage up (throughput scales with capacity)
aws fsx update-file-system \
  --file-system-id <FSxId> \
  --storage-capacity <GiB> \
  --region <REGION>

# FSx for OpenZFS — raise provisioned IOPS / throughput
aws fsx update-file-system \
  --file-system-id <FSxId> \
  --open-zfs-configuration '{"ThroughputCapacity":<NEW>, "DiskIopsConfiguration":{"Mode":"USER_PROVISIONED","Iops":<NEW>}}' \
  --region <REGION>

# EBS — migrate gp2 → gp3 and raise IOPS/throughput
aws ec2 modify-volume \
  --volume-id <vol-id> \
  --volume-type gp3 \
  --iops <NEW> \
  --throughput <NEW_MBps> \
  --region <REGION>
```

### Verify after remediation

- CloudWatch metric delta: throughput / IOPS climbs and ceases to flat-line at the old ceiling.
- Training step time decreases; data-loading percentage of step time decreases.
- `iostat %util` on the mount drops below 80% under sustained load.

### When to escalate

- Provisioned capacity is maxed, training still I/O-bound, and the workload cannot be restructured — request a regional capacity increase from AWS Support and attach CloudWatch metric graphs.
