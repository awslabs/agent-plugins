# Node Diagnostics Detail

Full diagnostic procedures, commands, and fix instructions for each section referenced from SKILL.md.

---

## A: EFA / Security Group

**Signals:** `"EFA health checks did not run successfully"`, EFA send/recv timeouts, NCCL connectivity fails.

```bash
# Cluster-centric: auto-discovers this cluster's exact SGs/subnets
bash scripts/check-efa-sg.sh --cluster <CLUSTER> --region <REGION>
```

Required rules on every cluster SG:

1. **Outbound self-ref (all protocols, source = the SG itself)** — required for EFA. This is the most commonly missing rule and is the #1 cause of "EFA health checks did not run successfully".
2. **Inbound self-ref (all protocols, source = the SG itself)** — required for node-to-node communication.
3. **Outbound 0.0.0.0/0** — required for AWS API calls, package downloads, and container image pulls.

The script prints `[PASS]` / `[FAIL]` for each rule. Apply the fix with explicit customer approval:

```bash
# Outbound self-ref (EFA)
aws ec2 authorize-security-group-egress --group-id <SG_ID> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG_ID>","Description":"HyperPod EFA intra-SG"}]}]'

# Inbound self-ref
aws ec2 authorize-security-group-ingress --group-id <SG_ID> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG_ID>","Description":"HyperPod intra-SG"}]}]'

# Outbound internet (only if missing)
aws ec2 authorize-security-group-egress --group-id <SG_ID> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","IpRanges":[{"CidrIp":"0.0.0.0/0","Description":"Internet egress"}]}]'
```

**Idempotency:** `authorize-security-group-*` returns `InvalidPermission.Duplicate` if the rule already exists — treat this as success and continue.

**For provisioned nodes with EFA problems** -- run on node via `hyperpod-ssm` skill:

```bash
# Upload and run the reachability check (from your workstation):
# 1. Use hyperpod-ssm skill to get target: sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>
# 2. Upload script to node:
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  --upload scripts/check-node-reachability.sh /tmp/check-node-reachability.sh
# 3. Run it:
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'bash /tmp/check-node-reachability.sh'

# Or quick spot-check (single command via SSM):
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'fi_info -p efa'
```

---

## B: VPC / Routing

**Signals:** `"bootstrap failed...network misconfiguration"`, S3 timeout, subnet/VPC mismatch, DNS resolution failures, node unreachable despite SG rules being correct.

```bash
bash scripts/check-vpc-config.sh --cluster <CLUSTER> --region <REGION>
```

### B.1 Common VPC / routing errors

| Error                                                 | Fix                                                                                                           |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| SG + subnet in different VPCs                         | Move SG to same VPC as subnet                                                                                 |
| S3 timeout `"Connect timeout on endpoint URL: s3://"` | Add S3 Gateway VPC endpoint to subnet route table                                                             |
| EKS auth mode `CONFIG_MAP`                            | `aws eks update-cluster-config --name <N> --region <R> --access-config authenticationMode=API_AND_CONFIG_MAP` |
| `aws-hyperpod` namespace missing                      | `kubectl create namespace aws-hyperpod`                                                                       |
| Workers can't reach EKS controller                    | Add route to EKS VPC CIDR in worker subnet; check VPC flow logs                                               |

### B.2 VPC DNS support / hostnames

HyperPod requires both `enableDnsSupport` and `enableDnsHostnames` on the VPC. Without them, EKS internal service DNS, node internal hostnames, and `ip-x-x-x-x` Slurm nodenames fail to resolve.

```bash
# Diagnose
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsSupport   --region <R> --query 'EnableDnsSupport.Value'
aws ec2 describe-vpc-attribute --vpc-id <VPC_ID> --attribute enableDnsHostnames --region <R> --query 'EnableDnsHostnames.Value'

# Fix (both must be true)
aws ec2 modify-vpc-attribute --vpc-id <VPC_ID> --region <R> --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id <VPC_ID> --region <R> --enable-dns-hostnames '{"Value":true}'
```

### B.3 Private subnets & NAT gateway (only private subnets supported)

HyperPod requires **private subnets only**. A private subnet is one whose route table has no default route to an Internet Gateway. If outbound internet is needed, route `0.0.0.0/0` through a NAT Gateway placed in a separate public subnet. In a fully air-gapped VPC, the default route can be absent and outbound must go through VPC endpoints (see § B.4).

```bash
# Inspect route tables associated with the HyperPod subnets:
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=<subnet-1>,<subnet-2>" \
  --region <R> \
  --query "RouteTables[*].{Assoc:Associations[?SubnetId!=\`null\`].SubnetId,Routes:Routes[?DestinationCidrBlock==\`0.0.0.0/0\`]}" \
  --output json
```

| Route target for `0.0.0.0/0` | Subnet type                    | Action                                                            |
| ---------------------------- | ------------------------------ | ----------------------------------------------------------------- |
| `igw-*` (Internet Gateway)   | **Public — not supported**     | Remove the IGW route; add a NAT Gateway and route to it           |
| `nat-*` (NAT Gateway)        | Private with outbound internet | OK for most customers                                             |
| Absent                       | Fully private / air-gapped     | OK if S3/ECR/STS/SSM/EC2 VPC endpoints are configured — see § B.4 |
| `vpce-*`                     | Endpoint-only routing          | OK                                                                |

### B.4 VPC endpoints for private (internet-disabled) VPCs

When the VPC has no NAT Gateway, the HyperPod nodes need private interface endpoints for every AWS service they call. All interface endpoints listen on TCP/443 — the SG attached to the endpoint must allow inbound 443 from the HyperPod subnet CIDR.

| Endpoint                                   | Type      | Required     | Purpose                                                            |
| ------------------------------------------ | --------- | ------------ | ------------------------------------------------------------------ |
| `com.amazonaws.<region>.s3`                | Gateway   | **Yes**      | Lifecycle scripts, DLC image layers                                |
| `com.amazonaws.<region>.ecr.api`           | Interface | **Yes**      | ECR authentication                                                 |
| `com.amazonaws.<region>.ecr.dkr`           | Interface | **Yes**      | Pull container images                                              |
| `com.amazonaws.<region>.sts`               | Interface | **Yes**      | IMDS-less assume-role                                              |
| `com.amazonaws.<region>.ssm`               | Interface | **Yes**      | SSM Session Manager                                                |
| `com.amazonaws.<region>.ssmmessages`       | Interface | **Yes**      | SSM session traffic                                                |
| `com.amazonaws.<region>.ec2messages`       | Interface | **Yes**      | SSM heartbeats                                                     |
| `com.amazonaws.<region>.ec2`               | Interface | **Yes**      | Instance metadata, EBS volume operations                           |
| `com.amazonaws.<region>.sagemaker.api`     | Interface | **Yes**      | HyperPod control plane                                             |
| `com.amazonaws.<region>.sagemaker.runtime` | Interface | **Yes**      | Runtime calls                                                      |
| `com.amazonaws.<region>.logs`              | Interface | **Yes**      | CloudWatch logs from lifecycle scripts and health-monitoring-agent |
| `com.amazonaws.<region>.eks`               | Interface | EKS only     | Required if EKS endpoint is private-only                           |
| `com.amazonaws.<region>.fsx`               | Interface | If using FSx | Required for FSx for Lustre / OpenZFS                              |

### B.5 EKS VPC / SG alignment with HyperPod

When orchestrator is EKS, the EKS cluster and the HyperPod cluster must share a VPC, and the SG attached to the HyperPod cluster must either be attached to the EKS cluster itself OR the EKS cluster SG must allow inbound from the HyperPod SG. The EKS-default cluster SG works if its outbound rules permit the traffic HyperPod needs.

```bash
# Verify VPC match
aws sagemaker describe-cluster --cluster-name <HP>  --region <R> --query 'VpcConfig.{Subnets:Subnets,SGs:SecurityGroupIds}'
aws eks describe-cluster       --name         <EKS> --region <R> --query 'cluster.resourcesVpcConfig.{VPC:vpcId,SGs:securityGroupIds,ClusterSG:clusterSecurityGroupId}'

# If HyperPod SG is NOT attached to EKS, add an inbound rule on the EKS cluster SG
# that allows traffic from the HyperPod SG:
aws ec2 authorize-security-group-ingress \
  --group-id <EKS_CLUSTER_SG> --region <R> \
  --ip-permissions "[{\"IpProtocol\":\"-1\",\"UserIdGroupPairs\":[{\"GroupId\":\"<HP_SG>\",\"Description\":\"HyperPod worker traffic\"}]}]"
```

---

## C: Capacity / AZ

**Signals:** `"Insufficient capacity"` or `"No subnets in the capacity AZ"` in events.

```bash
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=<INSTANCE_TYPE>" \
  --region <REGION> --query 'InstanceTypeOfferings[*].Location'
```

Fix: add subnet in the AZ where capacity exists, or use Flexible Training Plans / ODCR.

---

## D: Lifecycle Scripts

**Signals:** `"Lifecycle scripts did not run successfully"` or `"timed out"` in events.

```bash
# Get cluster ID then fetch logs
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> --query 'ClusterArn' --output text | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/<CLUSTER_NAME>/${CLUSTER_ID}"
aws logs describe-log-streams --log-group-name "$LOG_GROUP" --region <R> \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].logStreamName' --output table
```

**On-node logs** (via `hyperpod-ssm` skill):

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'cat /var/log/provision/provisioning.log'
```

| Log Error                                | Fix                                                        |
| ---------------------------------------- | ---------------------------------------------------------- |
| `Connect timeout on endpoint URL: s3://` | Add S3 VPC Gateway endpoint                                |
| `AccessDenied` on S3                     | Add `s3:GetObject` + `s3:ListBucket` to execution role     |
| Script never exits                       | Add proper exit; check infinite loops; test script locally |
| `CRLF line terminators`                  | `dos2unix script.sh` before uploading to S3                |
| `provisioning_parameters.json mismatch`  | Match instance group names exactly between script and API  |

---

## E: Software Versions

**Signals:** NCCL hangs after node replacement, training fails after AMI update, version drift across nodes.

**Delegate to `hyperpod-version-checker` skill** -- compares NVIDIA driver, CUDA, NCCL, EFA installer, OFI NCCL, PyTorch across all nodes.

### Quick spot-check on affected node (via `hyperpod-ssm` skill)

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'nvidia-smi --query-gpu=driver_version --format=csv,noheader && \
   nvcc --version | grep "release" && \
   head -3 /opt/amazon/efa_installed_packages && \
   python3 -c "import torch; print(torch.__version__, torch.version.cuda)"'
```

### CUDA driver vs `nvcc` compiler version mismatch

The CUDA _driver_ (reported by `nvidia-smi`) and the CUDA _toolkit_ / `nvcc` (reported by `nvcc --version`) must be a supported pair — a newer toolkit cannot target an older driver. This mismatch commonly causes `CUDA error: no kernel image is available for execution on the device` or segfaults during kernel launch.

```bash
# On the node:
nvidia-smi | grep "CUDA Version"         # the maximum CUDA the driver supports
nvcc --version | grep "release"          # the CUDA toolkit installed

# If driver CUDA < toolkit CUDA: upgrade the driver or downgrade the toolkit.
# Compatibility matrix:
#   https://docs.nvidia.com/cuda/cuda-toolkit-release-notes/
```

### EFA / NCCL / libfabric compatibility

EFA installer version and AWS OFI NCCL version must be paired per the AWS EFA changelog:

```bash
# Installed versions:
cat /opt/amazon/efa_installed_packages | head -10
fi_info -p efa | head -5                 # libfabric + EFA provider

# Official compatibility matrix:
#   https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-changelog.html
```

### Container vs host version mismatches

If training works on the host but fails in the container (or vice versa), the cause is almost always one of:

1. **EFA libraries not mounted into the container.** The container must see `/opt/amazon/efa`, `/opt/amazon/openmpi`, and `/dev/infiniband`. Without these, NCCL falls back to TCP silently.
2. **`LD_LIBRARY_PATH` missing EFA / CUDA paths inside the container.** Export explicitly in the container entrypoint:

   ```bash
   export LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
   ```

3. **PyTorch / TensorFlow built against a different CUDA major than the host driver supports.** Rebuild the container from a base image that matches the host driver's CUDA version (e.g. AWS DLC `pytorch-training:<ver>-gpu-py<ver>-cu<host-major>-ubuntu*`).

After a driver upgrade, CUDA devices may fail to initialize until the node is rebooted — the old kernel module continues to service active processes but new processes see stale state. Reboot via `batch-reboot-cluster-nodes` (see Section F) and re-run training.

### Required job-launcher env vars

`FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1`, `NCCL_SOCKET_IFNAME=^lo,docker`, `NCCL_TIMEOUT=1200`

### Additional validation guides

- PyTorch environment validation — <https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/validation-and-testing/environment-validation/pytorch-environment-validation>
- EFA and network-stack validation — <https://awslabs.github.io/ai-on-sagemaker-hyperpod/docs/validation-and-testing/environment-validation/efa-validation>

---

## F: Hardware / Auto-Repair

**Signals:** `"hardware failure"` event, EKS label `UnschedulablePendingReplacement`, XID errors, auto-repair not triggering.

```bash
# Is NodeRecovery enabled?
aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'InstanceGroups[*].{Group:InstanceGroupName,Recovery:NodeRecovery}'

# EKS: check all node repair labels at once
kubectl get nodes -o custom-columns='NODE:.metadata.name,HEALTH:.metadata.labels.sagemaker\.amazonaws\.com/node-health-status,FAULT:.metadata.labels.sagemaker\.amazonaws\.com/fault-type'

# Check repair events
aws sagemaker list-cluster-events --cluster-name <C> --region <R> \
  --query 'ClusterEventSummaries[?contains(Message,`replacement`) || contains(Message,`reboot`) || contains(Message,`hardware`)]' \
  --output table

# For Slurm: auto-repair triggers only if node reason is exactly "Action:Reboot" or "Action:Replace"
sinfo -o "%N %T %30E"
```

**Manual fix:**

```bash
# Try reboot first (less disruptive)
aws sagemaker batch-reboot-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
# If hardware still bad: replace
aws sagemaker batch-replace-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
```

> **Batch size limit: 25 node IDs per call.** Split larger fleets into multiple calls; >25 returns `ValidationException`.

**Common blockers:** `NodeRecovery=None` (enable it), health agent hasn't detected (check CW logs: `SagemakerHealthMonitoringAgent/<group>/<instance>` stream), lifecycle script failing on replacement instance (check `LifecycleConfig` CW logs), no capacity (see `hyperpod-cluster-debugger`), cluster not InService, Slurm reason not `Action:Reboot`/`Action:Replace`. See [node-issue-catalog.md](node-issue-catalog.md) for detailed patterns.

> Rolling batch replacements (12-15 nodes every ~10 min) = HyperPod health monitoring. **Expected behavior.**

---

## G: GPU/Accelerator

**Signals:** GPU off bus, `deep-health-check-status: Failed`, XID errors, low utilization, ECC errors, thermal throttling, NeuronCore errors.

### G.1: NVIDIA GPUs (p4d/p5/g5/g6)

Run on affected node (via `hyperpod-ssm` skill):

```bash
# Quick GPU health (single command via SSM):
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'nvidia-smi -L && nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,ecc.errors.uncorrected.volatile.total --format=csv && nvidia-smi -q | grep -E "Xid|Error Type|ECC" && dmesg | grep -i "xid\|nvrm\|pcie\|error" | tail -20'
```

**ECC thresholds:** CE < 100/day normal; CE > 100/day or **any** UCE -> drain and replace. For detailed GPU diagnostics (NVLink, dmon, stress testing), see [node-issue-catalog.md](node-issue-catalog.md) section 2.

#### G.1.a: Row-remap state (marginal GPU memory)

Row-remapping is the H100 / A100 mechanism that permanently reassigns physical memory rows around defects. The remap state is the most reliable signal of _silent_ GPU memory degradation — training accuracy regressions, sporadic NaNs, and intermittent NCCL hangs that no Xid or ECC count explains.

Query remap state:

```bash
nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
  --format=csv
```

| State                                | Meaning                                                                                                                                        | Action                                                                                                    |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `pending = 0`, `failure = No`        | Healthy                                                                                                                                        | None                                                                                                      |
| `pending > 0`                        | A remap is staged but needs a GPU reset / reboot to take effect. **Marginal memory** — training can drift silently until the remap is applied. | Reboot the node via `batch-reboot-cluster-nodes` (Section F). Re-check after reboot; pending should be 0. |
| `pending > 0` persists across reboot | Known firmware edge case where the remap is stuck "Pending" and never promotes to "Failure". GPU silently degrades.                            | Escalate to AWS Support. Drain and replace the node via `batch-replace-cluster-nodes` (Section F).        |
| `failure = Yes`                      | GPU has exceeded remap capacity; memory is bad.                                                                                                | Drain and replace the node via `batch-replace-cluster-nodes` (Section F).                                 |

`uncorrectable > 0` with `pending = 0` is historical — those rows have already been remapped successfully and are fine going forward, but a high count is a warning sign for the broader hardware cohort.

#### G.1.b: DCGM health and nvvs logs

SageMaker HyperPod runs DCGM as part of its deep-health-check. DCGM findings sit under `/var/log/nvidia-dcgm/` on the node.

```bash
# Quick health check
dcgmi health --check -j

# Full nvvs (NVIDIA Validation Suite) log — surfaces row-remap / memtest detail
ls -1t /var/log/nvidia-dcgm/ | head
tail -n 200 "$(ls -1t /var/log/nvidia-dcgm/nvvs*.log | head -1)"
```

Treat only **Fail** / **Warn** verdicts as authoritative. A **Pass** result from `dcgmi -r medium,memtest` on DCGM ≤ 3.3.9 is not authoritative — a known bug can make the combined `medium,memtest` invocation pass even when `memtest` alone would fail. If the triage script reports a DCGM Pass but symptoms persist, re-run with split invocations on the node:

```bash
# Run medium and memtest separately to work around the DCGM <= 3.3.9 combined-run bug:
dcgmi diag -r medium
dcgmi diag -r memtest
```

For comprehensive data collection before opening a ticket, capture:

```bash
# NVIDIA's authoritative bug-report bundle (large — collect once, attach to ticket):
sudo nvidia-bug-report.sh
# Output: nvidia-bug-report.log.gz in the current directory

# DCGM nvvs logs from the node:
sudo tar -czf /tmp/nvidia-dcgm-logs.tgz /var/log/nvidia-dcgm/
```

Attach both to the AWS Support case along with the triage script output.

### G.2: AWS Trainium/Inferentia (trn1/trn2/inf2)

These instances use the **AWS Neuron SDK** instead of CUDA. `nvidia-smi` will not work — use Neuron tools instead.

**Quick Neuron health check (via SSM):**

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'neuron-ls && neuron-top -n 1 2>/dev/null || echo "neuron-top not available" && dmesg | grep -i "neuron\|nrt\|error" | tail -20'
```

**Diagnostic commands:**

| Command                       | What It Shows                                               |
| ----------------------------- | ----------------------------------------------------------- |
| `neuron-ls`                   | Lists all NeuronCore devices, shows device count and status |
| `neuron-top`                  | Live utilization (NeuronCore %, memory, model loaded)       |
| `neuron-monitor`              | JSON metrics stream for programmatic monitoring             |
| `dmesg \| grep -i neuron`     | Kernel-level Neuron device errors                           |
| `systemctl status neuron-rtd` | Neuron Runtime daemon status (older AMIs)                   |
| `pip show neuronx-cc`         | Neuron Compiler version                                     |
| `pip show torch-neuronx`      | PyTorch Neuron version                                      |

**Expected NeuronCore / NeuronDevice counts** (authoritative source: [AWS Neuron docs — Architecture](https://awsdocs-neuron.readthedocs-hosted.com/en/latest/general/arch/neuron-hardware/neuron-core-v2.html)):

| Instance      | NeuronDevices | NeuronCores (total) | Notes                                 |
| ------------- | ------------- | ------------------- | ------------------------------------- |
| trn1.2xlarge  | 1             | 2                   | 1x Trainium1 chip, 2 cores per chip   |
| trn1.32xlarge | 16            | 32                  | 16x Trainium1 chips, 2 cores per chip |
| trn2.48xlarge | 16            | 128                 | 16x Trainium2 chips, 8 cores per chip |
| inf2.xlarge   | 1             | 2                   | 1x Inferentia2 chip                   |
| inf2.8xlarge  | 1             | 2                   | 1x Inferentia2 chip                   |
| inf2.24xlarge | 6             | 12                  | 6x Inferentia2 chips                  |
| inf2.48xlarge | 12            | 24                  | 12x Inferentia2 chips                 |

> Verify against `neuron-ls` on the node if the Neuron SDK has been updated — chip-to-core mapping has changed between SDK major versions historically.

**Common Neuron issues:**

| Symptom                                                   | Cause                                                                                                                                                                            | Resolution                                                                                                                                                                                           |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `neuron-ls` shows 0 devices                               | Neuron kernel driver not loaded                                                                                                                                                  | Load driver: `sudo modprobe neuron` then re-run `neuron-ls`. If modprobe fails, the AMI is missing the Neuron driver package — rebuild with the AWS Neuron DLAMI or install `aws-neuronx-dkms`.      |
| `neuron-ls: command not found`                            | Neuron SDK tools not on PATH                                                                                                                                                     | Install the Neuron SDK (`aws-neuronx-tools`) from the AWS Neuron apt/yum repo, or use the AWS Neuron DLAMI which has it pre-installed.                                                               |
| NeuronCore count < expected                               | Device failure, driver issue, or partial chip detection                                                                                                                          | Reboot the node first. If the count is still low after reboot, treat as a hardware failure and replace via `batch-replace-cluster-nodes` → Section F.                                                |
| `NRT_UNRECOVERABLE_ERROR` in dmesg or runtime logs        | Unrecoverable hardware fault on a NeuronDevice                                                                                                                                   | Drain the node, then replace it via `batch-replace-cluster-nodes` → Section F. Do not attempt software-only recovery.                                                                                |
| `neuron-rtd` not running (Neuron SDK < 2.10 / older AMIs) | Neuron runtime daemon crashed. The standalone `neuron-rtd` daemon was deprecated in Neuron SDK 2.10+; newer releases use the `libnrt` runtime linked into the framework process. | Restart the daemon: `sudo systemctl restart neuron-rtd`. If running Neuron SDK ≥ 2.10, this table entry does not apply — restart the training process instead.                                       |
| OOM on NeuronDevice (HBM exhaustion)                      | Model weights + activations + optimizer state exceed NeuronDevice HBM capacity                                                                                                   | Increase tensor-parallel degree, enable activation checkpointing, or scale up to `trn2.48xlarge`. Do NOT use swap.                                                                                   |
| Version mismatch across nodes                             | AMI drift after a partial replacement (`aws-neuronx-*` packages differ node-to-node)                                                                                             | Pin `aws-neuronx-dkms`, `aws-neuronx-tools`, `aws-neuronx-collectives`, `neuronx-cc`, and `torch-neuronx` versions in the cluster lifecycle script so all replacements converge on the same release. |

### Accelerator failure → Section F

For either GPU or Neuron device failure, drain and replace the node:

```bash
# EKS:
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Slurm:
scontrol update nodename=<node-name> state=drain reason="Accelerator failure -- replacing"
```

---

## H: Slurm Node Management

**Signals:** Node `down`, `"Node unexpectedly rebooted"`, jobs stuck in PENDING/COMPLETING, `scontrol ping` fails.

### Node Down / Unresponsive

```bash
sinfo -o "%N %T %30E"          # State + reason
scontrol show node <NODE>      # Full details

# Test connectivity (try all methods to identify which path is broken):
ping <node-ip>                  # Basic network
ssh <node-name>                 # Cross-node SSH
srun -w <node-name> hostname    # Slurm communication

# On the node (via hyperpod-ssm skill -- SSM is the primary access method):
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'sudo systemctl status slurmd && free -h && df -h'
# If slurmd is stopped:
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'sudo systemctl start slurmd'

# Fix (on head node):
scontrol update nodename=<N> state=resume
```

If disk space is full, clean up before resuming -- see **[Section I: Resource Exhaustion](#i-resource-exhaustion)**.

If rebooting/resuming doesn't help:

```bash
# Reboot via HyperPod API
aws sagemaker batch-reboot-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
# If hardware issue: replace
aws sagemaker batch-replace-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
```

### Node Unexpectedly Rebooted

Node is running but Slurm marked it down as a protective measure. Fix:

```bash
# On node (via SSM): enable and start slurmd
sudo systemctl enable slurmd && sudo systemctl start slurmd
# On head node: resume the node
scontrol update nodename=<N> state=resume
```

Prevention: always `scontrol update state=drain` before intentional reboot, then `state=resume` after.

### Jobs Stuck PENDING/COMPLETING -> Restart slurmctld

**When to restart:** PENDING with `REASON=RESOURCES` despite available nodes, GRES miscalculation, COMPLETING after replacement, `scontrol ping` fails.

```bash
sudo systemctl restart slurmctld && sinfo && squeue
# If completely hung: sudo pkill -9 slurmctld && sudo systemctl start slurmctld
```

Restart preserves running jobs, pending queue, and node states. Resets memory cache and resource calculations.

### Translate Slurm node name -> Instance ID (for AWS API)

```bash
NODE="ip-10-1-2-3"
IP=$(echo $NODE | sed 's/ip-//; s/-/./g')
sudo python3 -c "import json; d=json.load(open('/opt/ml/config/resource_config.json')); [print(n) for n in d.get('InstanceGroups',[]) if '$IP' in str(n)]"
# Or:
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,DNS:PrivateDnsHostname}' --output table
```

**For large clusters** (recurring lookups): use `dump_cluster_nodes_info.py` to generate a CSV:

```bash
wget https://raw.githubusercontent.com/aws-samples/awsome-distributed-training/main/1.architectures/5.sagemaker-hyperpod/tools/dump_cluster_nodes_info.py
python3 dump_cluster_nodes_info.py --cluster-name <C>
cat cluster_nodes_info.csv | grep "10.1.2.3"
```

---

## I: Resource Exhaustion

**Signals:** Disk full, OOM kills, `"Cannot allocate memory"` at `os.fork()`, inode exhaustion, `/dev/shm` full.

### Diagnose (via `hyperpod-ssm` skill on the node)

```bash
df -h && df -i                                             # Disk + inodes
free -h                                                    # RAM
df -h /dev/shm                                             # Shared memory
dmesg | grep -i oom | tail -10                             # OOM kills
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -15
sudo du -sh /var/log/* /tmp/* 2>/dev/null | sort -hr | head -10
cat /proc/meminfo | grep Huge                              # Huge pages config
```

### I.1: "Cannot allocate memory" at os.fork()

**Symptoms:** `OSError: [Errno 12] Cannot allocate memory` during `os.fork()`, DataLoader crashes, `Failed to register memory` during EFA init, segmentation faults during NCCL operations.

**Fix (in order):**

1. `export FI_EFA_USE_HUGE_PAGE=0` — most common fix; add to job script, container entrypoint, or `/etc/environment` for persistence. Disabling EFA huge pages avoids the fork-time memory-registration path that fails when huge pages aren't pre-allocated.
2. Increase shared memory:
   - Docker: `docker run --shm-size=8g ...`
   - Kubernetes:

     ```yaml
     volumes:
     - name: dshm
       emptyDir:
         medium: Memory
         sizeLimit: 8Gi
     volumeMounts:
     - { name: dshm, mountPath: /dev/shm }
     ```

3. Tune PyTorch DataLoader:
   - `num_workers=4` (start here; too many workers × forked process = exhausted memory)
   - `persistent_workers=True` — reuse workers instead of recreating every epoch
   - `pin_memory=False` if you are not bottlenecked on host→GPU copy; `pin_memory=True` locks host RAM, which compounds the fork-time pressure
4. Reduce batch size to lower parent-process memory footprint before fork
5. Verify the environment:

   ```bash
   free -h                              # RSS + available memory
   df -h /dev/shm                       # /dev/shm capacity and usage
   cat /proc/meminfo | grep Huge        # huge-page allocation
   ```

**Huge-page configuration (only if you need `FI_EFA_USE_HUGE_PAGE=1`):**

If another workload legitimately needs EFA huge pages, pre-allocate them rather than leaving the default of 0:

```bash
# Current allocation
cat /proc/sys/vm/nr_hugepages

# Allocate 1024 × 2MB = 2 GiB (requires root)
echo 1024 | sudo tee /proc/sys/vm/nr_hugepages

# Persist across reboots
echo 'vm.nr_hugepages=1024' | sudo tee -a /etc/sysctl.d/99-hugepages.conf
```

Only then set `FI_EFA_USE_HUGE_PAGE=1`. Setting it without pre-allocation is the root cause of the fork-time failure in the first place.

See [node-issue-catalog.md](node-issue-catalog.md) section 4 for additional examples and the full K8s YAML template.

### I.2: Root Volume Exhausted

**Important:** The default HyperPod root volume is a **100 GB EBS volume** (per AWS docs:
"the default root volume of any fresh instance is mounted to `/tmp` only with a 100 GB EBS volume"
— [Running Docker containers on a Slurm compute node on HyperPod](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-run-jobs-slurm-docker.html)).
**Do not plan to grow the root volume after cluster creation** — redirect heavy data to
`/opt/sagemaker` (secondary EBS, sized at instance-group creation) or `/opt/dlami/nvme`
(NVMe instance store on P/G families). For persistent shared storage, use FSx for Lustre /
OpenZFS or S3.

**Available storage locations:**

| Mount Point       | Type                                                 | Persistence              | Best For                                      |
| ----------------- | ---------------------------------------------------- | ------------------------ | --------------------------------------------- |
| `/opt/sagemaker`  | Secondary EBS (configurable size per instance group) | Persistent               | Checkpoints, app data, logs, container images |
| `/opt/dlami/nvme` | NVMe instance store (p4d/p5/trn1)                    | **Lost on stop/replace** | Scratch data, caches, temp files              |
| FSx for Lustre    | Shared filesystem                                    | Persistent               | Large datasets, shared models                 |
| FSx for OpenZFS   | Shared filesystem                                    | Persistent               | Mixed workloads, snapshots                    |
| Amazon S3         | Object storage                                       | Persistent               | Large datasets, archives                      |

**Quick cleanup:**

```bash
sudo journalctl --vacuum-size=500M
sudo rm -f /var/log/*.log.* /var/log/*/*.gz
sudo apt-get clean 2>/dev/null || sudo yum clean all 2>/dev/null
docker system prune -a 2>/dev/null
```

**Redirect data to correct storage:**

```bash
# Environment variables (add to job scripts or /etc/environment)
export TORCH_HOME=/opt/sagemaker/torch_cache
export HF_HOME=/opt/sagemaker/huggingface_cache
export TRANSFORMERS_CACHE=/opt/sagemaker/transformers_cache
export TMPDIR=/opt/dlami/nvme/tmp && mkdir -p $TMPDIR

# In training scripts
checkpoint_dir = "/opt/sagemaker/checkpoints"
cache_dir = "/opt/dlami/nvme/cache"
```

For K8s pods, mount `/opt/sagemaker` and `/opt/dlami/nvme` as `hostPath` volumes. Default lifecycle scripts already configure container runtimes to use these paths. **Prevention:** size secondary EBS at 2-3x estimated needs when creating instance groups.

### I.3: OOM Events in dmesg

**Signal from the triage script:** `[P1] OOM events on node <i-xxx>`.

**Diagnose:**

```bash
# Full OOM context (what got killed + who invoked the OOM killer):
sudo dmesg -T | grep -i -B2 -A30 "Out of memory" | tail -80

# Running processes with their memory footprint:
ps auxf --sort=-%mem | head -20

# Systemd-level OOM tracking:
sudo journalctl -k --since "1 hour ago" | grep -i oom
```

**Root causes and remediation:**

| Signal                                        | Root cause                                               | Remediation                                                                                |
| --------------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `Killed process <pid> (python3) total-vm:...` | Training process exceeded cgroup memory limit            | Raise pod `resources.limits.memory`, reduce batch size, or reduce DataLoader workers       |
| `invoked oom-killer` on system-wide memory    | Node as a whole ran out of memory (too many pods)        | Reduce pod density; increase instance size; check for memory leaks in sidecars             |
| Repeated OOM within minutes                   | OOM loop — systemd or orchestrator restarting the victim | Before restarting, capture core: `sudo coredumpctl list`; identify leak via py-spy / pprof |

**Blast radius:** understanding-only. No remediation command on the node itself changes state; the fix is in the workload spec (pod limits, batch size).

### I.4: Inode Exhaustion

**Signal from the triage script:** `[P1] Inode exhaustion <N>% on /`.

Root volume has a fixed inode count. Many small files (pip caches, HF transformers cache, container image layers) can exhaust inodes long before disk space.

**Diagnose:**

```bash
df -i /
# Count files per top-level directory:
for d in /var /opt /root /home /tmp; do
  echo "$d: $(sudo find "$d" -xdev 2>/dev/null | wc -l) entries"
done

# Top 20 inode hoarders:
sudo find / -xdev -type f 2>/dev/null | awk -F/ '{print $1"/"$2"/"$3}' | sort | uniq -c | sort -rn | head -20
```

**Remediation (commands the customer runs on the node via SSM):**

```bash
# Clear pip / HF / transformers caches (safe if no training is mid-flight):
rm -rf ~/.cache/pip/* 2>/dev/null
rm -rf ~/.cache/huggingface/* 2>/dev/null

# Clean rotated journals:
sudo journalctl --vacuum-size=200M

# Clean stopped container images (frees inodes held by layers):
docker system prune -a --volumes -f 2>/dev/null || true

# Recheck:
df -i /
```

**Prevention:** redirect caches to `/opt/sagemaker` or `/opt/dlami/nvme` (see I.2 env-var table), which are separate filesystems with their own inode tables.

### I.5: Time Sync Not Healthy

**Signal from the triage script:** `[P1] Node <i-xxx> time sync not healthy`.

Clock drift > a few seconds breaks TLS / IAM SigV4 (every AWS API call fails with `SignatureDoesNotMatch` or token expiry) and Slurm accounting (job epochs disagree between controller and nodes).

**Diagnose:**

```bash
# chrony (default on Amazon Linux 2023):
chronyc tracking
chronyc sources -v

# systemd-timesyncd / timedatectl (fallback on some images):
timedatectl status

# Actual drift vs a reference:
ntpdate -q pool.ntp.org 2>/dev/null || chronyc makestep
```

**Remediation decisions:**

| Finding                                              | Remediation                                                                                                                                                                 |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Leap status : Not synchronised` + chrony is running | Restart chrony: `sudo systemctl restart chronyd`; then `chronyc sources -v` to confirm it has peers                                                                         |
| `Leap status : Not synchronised` + chrony is stopped | Start it: `sudo systemctl enable --now chronyd`                                                                                                                             |
| Drift > 1s but chrony is "synchronised"              | One-shot correction: `sudo chronyc makestep` (safe; pushes the clock to match its peers)                                                                                    |
| `chronyc sources` shows zero reachable servers       | Network/firewall issue — node cannot reach NTP pool. Check egress on UDP/123; check `/etc/chrony.conf` server list; if in a private subnet, ensure NTP traffic is permitted |

**Blast radius:** `chronyc makestep` and `systemctl restart chronyd` are low-risk on a node that is not running latency-sensitive training. During active training, prefer slewing (gradual correction — the default chrony behavior) over stepping; a step can confuse monotonic-time-based code.

---

## J: Configuration

**Signals:** p5.48xlarge shows 96 vCPU instead of 192, CFN error `"DisableHyperThreading not supported"`.

Console "Advanced Configuration" defaults `ThreadsPerCore=1`. Fix:

```bash
aws sagemaker update-cluster --cluster-name <C> --region <R> \
  --instance-groups '[{"InstanceGroupName":"<G>","InstanceType":"ml.p5.48xlarge",
    "InstanceCount":<N>,"ThreadsPerCore":2,
    "LifeCycleConfig":{"SourceS3Uri":"<URI>","OnCreate":"<SCRIPT>"},
    "ExecutionRole":"<ROLE>"}]'
```

CFN `UpdateCluster` must always include `ThreadsPerCore` even if not set at creation.

---

## K: Node Access via SSM

Direct SSH is not available on HyperPod — SSM is the primary node access method. The SSM target format and connection procedure is **identical for both EKS and Slurm** clusters — same plugin, same IAM permissions, same VPC endpoints. The only difference is what commands you run after connecting (kubectl vs scontrol).

### Quick-Start: Get Connected in 4 Commands

```bash
CLUSTER_NAME="my-hyperpod-cluster"
REGION="us-east-1"

# 1. Get cluster ID (last segment of the ARN — NOT the cluster name)
CLUSTER_ID=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'ClusterArn' --output text | cut -d/ -f2)
echo "Cluster ID: $CLUSTER_ID"

# 2. List all nodes with group name, instance ID, and status
aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'ClusterNodeSummaries[*].[InstanceGroupName,InstanceId,InstanceStatus.Status]' \
  --output table

# 3. Build the SSM target (substitute GROUP and INSTANCE_ID from step 2)
TARGET="sagemaker-cluster:${CLUSTER_ID}_<GROUP>-<INSTANCE_ID>"
echo "SSM Target: $TARGET"

# 4. Connect
aws ssm start-session --target "$TARGET" --region "$REGION"
```

### If You Only Have a Slurm Node Name (e.g., ip-10-1-2-3)

```bash
# Convert Slurm node name to instance ID
NODE_IP=$(echo "ip-10-1-2-3" | sed 's/ip-//; s/-/./g')
aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query 'ClusterNodeSummaries[*].{ID:InstanceId,DNS:PrivateDnsHostname,Group:InstanceGroupName}' \
  --output table | grep "$NODE_IP"
```

### Non-Interactive Command Execution

```bash
# Run a single command on a node (no interactive shell):
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target "$TARGET" --region "$REGION" \
  'nvidia-smi && free -h && df -h'
```

### Essential On-Node Checks

| Check                  | Command                                                 |
| ---------------------- | ------------------------------------------------------- |
| System health          | `uptime && free -h && df -h`                            |
| GPU (NVIDIA)           | `nvidia-smi`                                            |
| Accelerator (Trainium) | `neuron-ls && neuron-top -n 1`                          |
| EFA                    | `fi_info -p efa`                                        |
| NCCL/EFA env           | `env \| grep -E "FI_\|NCCL_"`                           |
| OOM / errors           | `dmesg \| grep -i "oom\|xid\|nvrm\|neuron" \| tail -20` |
| Provisioning           | `cat /var/log/provision/provisioning.log`               |
| Slurmd (Slurm only)    | `sudo systemctl status slurmd`                          |

### SSM Prerequisites

**SessionManagerPlugin installation:**

```bash
# Verify installed:
session-manager-plugin --version
# If not found, install:
#   macOS:  brew install --cask session-manager-plugin
#   Linux (DEB): curl -o session-manager-plugin.deb "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" && sudo dpkg -i session-manager-plugin.deb
#   Linux (RPM): curl -o session-manager-plugin.rpm "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" && sudo yum install -y session-manager-plugin.rpm
# After install, verify:
session-manager-plugin --version
```

**Required IAM permissions:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "sagemaker:DescribeCluster",
      "sagemaker:ListClusterNodes",
      "ssm:StartSession",
      "ssm:TerminateSession"
    ],
    "Resource": "*"
  }]
}
```

### SSM Not Working?

| Error                                                     | Root Cause                                             | Fix                                                                                                                                  |
| --------------------------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `SessionManagerPlugin is not found`                       | SSM plugin not installed                               | See installation steps above; restart terminal after install                                                                         |
| `Target is not connected`                                 | Wrong target format, wrong region, or node not running | Use `sagemaker-cluster:` prefix (not bare `i-xxx`); verify region; check node is `Running`                                           |
| `InvalidTarget` / `ValidationException`                   | Malformed target string                                | Ensure format is exactly `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>` — CLUSTER_ID is the ARN suffix, not the cluster name |
| `Access denied`                                           | Missing IAM permissions                                | Need `ssm:StartSession`, `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`                                                   |
| Connection timeout                                        | SSM agent unreachable                                  | Check VPC endpoints exist (SSM, SSMMessages, EC2Messages); verify node is in `Running` state                                         |
| `session-manager-plugin: command not found` after install | Not in PATH                                            | Re-open terminal; or add install dir to PATH                                                                                         |

---

## L: Log Collection

**Delegate to `hyperpod-issue-report` skill** for comprehensive S3-stored diagnostics.

| Log               | Group                                 | Stream                                                 |
| ----------------- | ------------------------------------- | ------------------------------------------------------ |
| Lifecycle scripts | `/aws/sagemaker/Clusters/<name>/<id>` | `LifecycleConfig/<group>/<instance-id>`                |
| Health monitoring | `/aws/sagemaker/Clusters/<name>/<id>` | `SagemakerHealthMonitoringAgent/<group>/<instance-id>` |

---

## M: Container Runtime

**Signals:** CrashLoopBackOff, ImagePullBackOff, RunContainerError, container OOM kills (EKS clusters).

### Diagnose

```bash
# Pod-level (from workstation):
kubectl describe pod <POD> -n <NAMESPACE>
kubectl logs <POD> -n <NAMESPACE> --previous   # logs from last crash

# On-node (via SSM):
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'sudo crictl ps -a | head -20 && sudo crictl logs --tail 30 <CONTAINER_ID> && journalctl -u containerd --no-pager -n 50'
```

| Symptom                   | Cause                               | Fix                                                                     |
| ------------------------- | ----------------------------------- | ----------------------------------------------------------------------- |
| `CrashLoopBackOff`        | Training process crashes repeatedly | Check `kubectl logs --previous`; likely OOM, missing lib, or NCCL error |
| `OOMKilled`               | Container exceeded memory limit     | Increase `resources.limits.memory` in pod spec or reduce batch size     |
| `ImagePullBackOff`        | Image not found or auth failure     | Verify ECR URI, check node has ECR access via VPC endpoint or internet  |
| `RunContainerError`       | Runtime can't start container       | Check `journalctl -u containerd`; may be disk full or GPU device issue  |
| `ContainerCreating` stuck | Volume mount or device plugin issue | Check EFA device plugin DaemonSet, volume mounts, and CSI drivers       |

### containerd Issues

```bash
# On-node via SSM:
sudo systemctl status containerd
sudo journalctl -u containerd --since "1 hour ago" | grep -i error
sudo crictl info   # runtime config and storage usage
```

If containerd is crashing or OOM, check disk usage on `/var/lib/containerd` (lives on root 100GB volume). Move container storage to `/opt/sagemaker` if needed.

---

## N: Kernel & System

**Signals:** Kernel panic, watchdog timeout, NMI, system hang, unexpected reboot not explained by HyperPod health monitoring.

### Diagnose (via SSM)

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'dmesg | grep -iE "panic|watchdog|hung_task|NMI|nvrm|Call Trace|BUG:" | tail -30 && journalctl -b -1 --no-pager -n 50 2>/dev/null || echo "No previous boot journal"'
```

| Signal                       | Cause                                        | Fix                                                                                        |
| ---------------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `Kernel panic - not syncing` | Critical kernel error                        | Check full dmesg; if `RIP: nvrm` → NVIDIA driver crash → reboot + replace if recurring     |
| `watchdog: BUG: soft lockup` | CPU stuck in kernel code                     | Often NVLink/PCIe issue on GPU instances; reboot, then replace if recurring                |
| `hung_task_timeout`          | Process stuck in uninterruptible sleep       | Check for disk I/O issues (`iostat`), NFS hangs, or dead-locked GPU operations             |
| `NMI received`               | Non-maskable interrupt (hardware)            | Hardware issue — drain and replace node → Section F                                        |
| `nvrm: Xid` + system hang    | NVIDIA driver crash leading to system freeze | Reboot via `batch-reboot-cluster-nodes`; replace if repeating                              |
| `mce: [Hardware Error]`      | Machine check exception                      | CPU/memory hardware failure — replace node                                                 |
| Repeated unexpected reboots  | Health agent triggered reboot for HW fault   | Check CloudWatch `SagemakerHealthMonitoringAgent` logs; expected if auto-repair is working |

### Previous Boot Logs

```bash
# See what happened before the last reboot:
journalctl -b -1 --no-pager | tail -100
# Check reboot reason:
last reboot | head -5
who -b
```

If kernel panics recur on the same node after reboot, the hardware is likely bad — drain and replace via Section F.

---

## O: CNI / Pod Networking

VPC CNI plugin (`aws-node`) failures prevent pods from getting IP addresses, breaking all pod networking on affected nodes.

### Diagnosis

```bash
# 1. Check aws-node DaemonSet status:
kubectl get ds -n kube-system aws-node
# Look for: DESIRED vs READY mismatch = unhealthy nodes

# 2. Find crashing aws-node pods:
kubectl get pods -n kube-system -l k8s-app=aws-node -o wide
# Look for: CrashLoopBackOff, Error, or high RESTARTS count

# 3. Check logs on the failing pod:
kubectl logs -n kube-system <aws-node-pod> -c aws-node --tail=100
kubectl logs -n kube-system <aws-node-pod> -c aws-eks-nodeagent --tail=50

# 4. Check IPAMD (IP Address Management Daemon) specifically:
kubectl logs -n kube-system <aws-node-pod> -c aws-node --tail=100 | grep -iE "ipamd|eni|ip pool|failed"

# 5. Check if kube-proxy and CoreDNS are also affected:
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Common Error Patterns

| Log Pattern                                                       | Root Cause                                        | Fix                                                           |
| ----------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| `gRPC connection refused 127.0.0.1:50051`                         | IPAMD not running, aws-node init container failed | Restart aws-node pod; check node IAM role                     |
| `Failed to create ENI` / `ENI limit reached`                      | Instance type ENI limit exhausted                 | Reduce pod density or enable prefix delegation                |
| `UnauthorizedOperation: ec2:CreateNetworkInterface`               | Node IAM role missing EC2 permissions             | Add `AmazonEKS_CNI_Policy` to the node role                   |
| `Failed to pull image` on aws-node                                | ECR endpoint not reachable in private VPC         | Add `com.amazonaws.<region>.ecr.api` and `.dkr` VPC endpoints |
| `Insufficient IP addresses` / `subnet has no available addresses` | VPC subnet exhausted                              | Add a larger subnet or use prefix delegation                  |
| `ipamd: failed to increase IP pool`                               | Cannot allocate warm pool IPs                     | Check ENI limits, subnet capacity, and SG rules               |

### Fixes

```bash
# Restart a single crashing aws-node pod:
kubectl delete pod -n kube-system <aws-node-pod-name>

# Enable prefix delegation for higher pod density (reduces ENI consumption):
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true

# Check node's ENI capacity:
kubectl get node <NODE> -o json | python3 -c "
import sys, json
n = json.load(sys.stdin)
alloc = n.get('status',{}).get('allocatable',{})
cap = n.get('status',{}).get('capacity',{})
print(f'Pod ENIs: allocatable={alloc.get(\"vpc.amazonaws.com/pod-eni\",\"N/A\")}  capacity={cap.get(\"vpc.amazonaws.com/pod-eni\",\"N/A\")}')
print(f'Pods:     allocatable={alloc.get(\"pods\",\"N/A\")}  capacity={cap.get(\"pods\",\"N/A\")}')
"

# Verify node IAM role has CNI permissions:
# The node role must have AmazonEKS_CNI_Policy or equivalent:
#   ec2:CreateNetworkInterface, ec2:DeleteNetworkInterface,
#   ec2:DescribeNetworkInterfaces, ec2:AssignPrivateIpAddresses,
#   ec2:UnassignPrivateIpAddresses, ec2:AttachNetworkInterface, ec2:DetachNetworkInterface

# Check VPC subnet free IPs:
aws ec2 describe-subnets --subnet-ids <SUBNET_ID> --region <REGION> \
  --query 'Subnets[0].{SubnetId:SubnetId,AvailableIPs:AvailableIpAddressCount,CIDR:CidrBlock}'
```

### When to Escalate

If `aws-node` keeps crashing after restart with no clear error in logs, and IAM + VPC + subnet are all correct, escalate to AWS Support with the output of:

```bash
kubectl describe ds -n kube-system aws-node
kubectl logs -n kube-system -l k8s-app=aws-node --tail=200
kubectl get nodes -o wide
```
