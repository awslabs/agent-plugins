# Node Issue Catalog

Detailed issue patterns for HyperPod node-level problems, organized by signal type.
Each entry includes: symptoms, root cause, diagnostic commands, and resolution steps.

---

## 1. EFA / Security Group Issues

### 1.1 EFA Health Check Failure During Cluster Creation

**Symptoms:**

- Cluster event: `"EFA health checks did not run successfully"`
- Cluster creation fails before lifecycle scripts execute
- CloudWatch lifecycle logs are empty (scripts never ran)

**Root Cause:** Security group missing self-referencing rules for EFA RDMA traffic.

**Diagnostic:**

```bash
bash scripts/check-efa-sg.sh --cluster <CLUSTER> --region <REGION>
```

**Fix:**

```bash
SG=<sg-id>; R=<region>
aws ec2 authorize-security-group-ingress --group-id $SG --region $R \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'
aws ec2 authorize-security-group-egress --group-id $SG --region $R \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"'"$SG"'"}]}]'
```

### 1.2 EFA Not Working After Node Replacement

**Symptoms:**

- Training hangs at NCCL init after replacing one or more nodes
- `fi_info -p efa` returns no providers on replacement node
- Other nodes work fine

**Root Cause:** EFA driver not loaded on replacement node, or version drift after AMI update.

**Diagnostic (on affected node via SSM):**

```bash
lsmod | grep efa                           # Should show efa module
fi_info -p efa                             # Should list EFA endpoints
cat /opt/amazon/efa_installed_packages     # Check EFA version
```

**Fix:** Compare versions with working nodes using `hyperpod-version-checker` skill. If versions differ, the lifecycle script may need updating.

### 1.3 EFA Intermittent Failures

**Symptoms:**

- Training works sometimes but randomly hangs
- NCCL logs show TCP fallback on some iterations
- `Using network TCP` instead of EFA in NCCL debug output

**Root Cause:** EFA interface flapping, network interface errors, or PCIe issues.

**Diagnostic (on affected node via SSM):**

```bash
ip -s link show 2>/dev/null | grep -A5 "RX\|TX"   # Check for errors/drops
dmesg | grep -i "efa\|pcie\|error" | tail -20
bash scripts/check-node-reachability.sh             # Full EFA health check
```

---

## 2. GPU / Accelerator Issues

### 2.1 GPU Off Bus (XID 79)

**Symptoms:**

- `nvidia-smi` shows fewer GPUs than expected
- dmesg: `Xid 79: GPU has fallen off the bus`
- Training fails with CUDA device not found

**Root Cause:** Hardware failure — GPU disconnected from PCIe bus.

**Diagnostic:**

```bash
nvidia-smi -L | wc -l                  # Count visible GPUs
dmesg | grep -i "xid.*79\|off the bus"
lspci | grep -i nvidia | wc -l         # Physical GPU count
```

**Fix:** Drain the node and request replacement:

```bash
# EKS:
kubectl cordon <node>; kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# Then:
aws sagemaker batch-replace-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
```

### 2.2 ECC Errors (Correctable → Uncorrectable)

**Symptoms:**

- `nvidia-smi -q` shows non-zero ECC error counts
- Training produces NaN values or incorrect gradients
- Performance degradation on specific GPU

**Root Cause:** Memory bit errors. Correctable (CE) are normal in small numbers. Uncorrectable (UCE) indicate failing hardware.

**Diagnostic:**

```bash
nvidia-smi -q | grep -A 10 "ECC Errors"
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,ecc.errors.uncorrected.volatile.total --format=csv
```

**Thresholds:**

- CE < 100/day: normal, monitor
- CE > 100/day or any UCE: drain node, request replacement

### 2.3 Thermal Throttling

**Symptoms:**

- GPU utilization drops periodically
- `nvidia-smi dmon` shows temperature > 80C
- Training throughput varies over time

**Diagnostic:**

```bash
nvidia-smi dmon -s pucvmet -d 5    # Live monitoring (5 sec intervals)
nvidia-smi --query-gpu=temperature.gpu,power.draw,clocks.current.sm --format=csv
```

**Fix:** Typically indicates a cooling issue. Drain and replace if persistent.

### 2.4 NVLink Failures

**Symptoms:**

- Inter-GPU communication slow (same node)
- `nvidia-smi nvlink --status` shows inactive links
- XID 74 in dmesg

**Diagnostic:**

```bash
nvidia-smi nvlink --status
nvidia-smi topo -m    # Should show NV links, not PHB
dmesg | grep -i "xid.*74\|nvlink"
```

**Fix:** Drain and replace node if NVLink is down.

---

## 3. Slurm Management Issues

### 3.1 Node Down — "Node Unexpectedly Rebooted"

**Symptoms:**

- `sinfo` shows node as `down`
- Reason: `"Node unexpectedly rebooted"`
- Node is running and accessible

**Root Cause:** Node was rebooted without notifying Slurm. slurmd may not have restarted.

**Diagnostic:**

```bash
scontrol show node <NODE> | grep -E "State|Reason"
# On node via SSM:
sudo systemctl status slurmd
```

**Fix:**

```bash
# On node:
sudo systemctl start slurmd
sudo systemctl enable slurmd    # Prevent recurrence
# On head node:
scontrol update nodename=<N> state=resume
```

### 3.2 Jobs Stuck in COMPLETING After Node Replacement

**Symptoms:**

- Jobs stay in COMPLETING state indefinitely
- `squeue` shows jobs stuck
- Node was recently replaced

**Root Cause:** slurmctld cached the COMPLETING state and keeps waiting for the old node that no longer exists.

**Fix:**

```bash
sudo systemctl restart slurmctld
sinfo && squeue    # Verify recovery
```

### 3.3 GRES (GPU) Miscalculation

**Symptoms:**

- Jobs stuck PENDING with `REASON=RESOURCES` despite free GPUs
- `scontrol show node` shows wrong GRES count

**Root Cause:** GRES resources not released after job completion or node replacement.

**Fix:**

```bash
sudo systemctl restart slurmctld    # Resets resource calculations
scontrol show node <NODE> | grep Gres   # Verify GRES count
```

---

## 4. Resource Exhaustion Issues

### 4.1 Root Volume Full (100 GB Default)

**Symptoms:**

- `df -h /` shows 100% used
- Container pulls fail
- Log writes fail
- Training cannot write checkpoints

**Root Cause:** HyperPod's default root volume is 100 GB EBS (per AWS docs). Container
images, logs, or training artifacts written to the root path fill it quickly. Plan to
redirect data off root rather than try to grow it post-creation.

**Diagnostic:**

```bash
df -h
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -15
```

**Fix:** Redirect to alternative storage:

- `/opt/sagemaker` — secondary EBS (configurable size)
- `/opt/dlami/nvme` — NVMe local storage (p4d/p5/trn1)
- Set: `TORCH_HOME=/opt/sagemaker/torch_cache`, `HF_HOME=/opt/sagemaker/huggingface_cache`

### 4.2 os.fork() Memory Error with EFA

**Symptoms:**

- `OSError: [Errno 12] Cannot allocate memory` at `os.fork()`
- Happens with PyTorch DataLoader + EFA
- Segfaults during NCCL init

**Root Cause:** EFA huge pages interfere with process forking.

**Fix (in order):**

1. `export FI_EFA_USE_HUGE_PAGE=0`
2. Increase container shm: `--shm-size=8g` or K8s `emptyDir.medium=Memory`
3. Reduce `num_workers`; set `persistent_workers=True`

### 4.3 OOM Kills (Exit Code 137)

**Symptoms:**

- Pod/process killed with exit code 137
- dmesg shows `oom-kill` messages
- Container shows `OOMKilled` reason

**Diagnostic:**

```bash
dmesg | grep -i "oom\|killed process" | tail -10
free -h
```

**Fix:**

- Enable gradient checkpointing: `model.gradient_checkpointing_enable()`
- Use FSDP/ZeRO for model sharding
- Reduce batch size
- Increase K8s memory limits

### 4.4 Inode Exhaustion

**Symptoms:**

- `df -i` shows 100% inode usage
- `No space left on device` despite free disk space
- Small files (pip caches, logs) consuming all inodes

**Diagnostic:**

```bash
df -i
sudo find / -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head -20
```

**Fix:** Remove cache directories with many small files:

```bash
pip cache purge
sudo rm -rf /tmp/pip-*
sudo find /var/log -name "*.gz" -delete
```

---

## 5. Configuration Issues

### 5.1 Wrong vCPU Count (96 vs 192 on p5.48xlarge)

**Symptoms:**

- `nproc` shows 96 instead of 192 on p5.48xlarge
- Training uses fewer cores than expected

**Root Cause:** Console "Advanced Configuration" defaults `ThreadsPerCore=1` (hyperthreading disabled).

**Fix:**

```bash
aws sagemaker update-cluster --cluster-name <C> --region <R> \
  --instance-groups '[{"InstanceGroupName":"<G>","InstanceType":"ml.p5.48xlarge",
    "InstanceCount":<N>,"ThreadsPerCore":2,
    "LifeCycleConfig":{"SourceS3Uri":"<URI>","OnCreate":"<SCRIPT>"},
    "ExecutionRole":"<ROLE>"}]'
```

### 5.2 Lifecycle Script Environment Mismatch

**Symptoms:**

- Node joins cluster but software is wrong version
- Environment variables not set after provisioning
- Packages missing that should have been installed

**Diagnostic:**

```bash
cat /var/log/provision/provisioning.log
env | grep -E "FI_|NCCL_|CUDA_|LD_LIBRARY"
```

**Fix:** Review lifecycle scripts in S3, compare with latest upstream versions.

---

## 6. Network / Connectivity Issues

### 6.1 Node Cannot Reach AWS APIs

**Symptoms:**

- `aws sagemaker describe-cluster` times out from node
- SSM agent cannot register
- CloudWatch agent cannot publish logs

**Root Cause:** Missing VPC endpoints or NAT gateway.

**Diagnostic:**

```bash
bash scripts/check-vpc-config.sh --cluster <C> --region <R>
# On node:
curl -s --connect-timeout 5 https://sagemaker.<REGION>.amazonaws.com/ && echo OK || echo FAIL
```

**Fix:** Add required VPC endpoints (S3, SSM, SSM Messages, EC2 Messages, SageMaker API).

### 6.2 Cross-Node SSH Fails

**Symptoms:**

- `ssh <other-node>` fails from within cluster
- Slurm `srun -w <node>` hangs

**Root Cause:** Security group blocks inter-node SSH, or SSH keys not distributed.

**Diagnostic:**

```bash
# On node:
ssh -o ConnectTimeout=5 <other-node-ip> hostname
ping -c 3 <other-node-ip>
```

**Fix:** Ensure SG allows all traffic within itself (self-ref rules). Check `~/.ssh/authorized_keys` on target.
