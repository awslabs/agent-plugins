# Node Diagnostics Detail

Full diagnostic procedures, commands, and fixes for each section referenced from [SKILL.md](../SKILL.md).

---

## A: EFA / Security Group

**Signals:** `"EFA health checks did not run successfully"`, EFA send/recv timeouts, NCCL connectivity fails.

```bash
bash scripts/check-efa-sg.sh --cluster <CLUSTER> --region <REGION>
```

Required rules on every cluster SG (per the HyperPod prerequisites doc — "configure the security group to allow all inbound and outbound traffic to and from the security group itself"):

1. **Outbound self-ref (all protocols, source = SG)** — required for EFA.
2. **Inbound self-ref (all protocols, source = SG)** — required for node-to-node communication.

**Do not add `0.0.0.0/0` outbound to the EFA security group.** Per the HyperPod prerequisites doc: "avoid using `0.0.0.0/0` for outbound rules, as this may cause EFA health check failures." Outbound internet traffic for AWS API calls, package downloads, and image pulls must be routed at the **subnet** level — via a NAT gateway in private subnets, or via VPC interface/gateway endpoints in air-gapped VPCs (see § B.4).

The script prints `[PASS]` / `[FAIL]` per rule.

### Suggested command — add EFA SG self-referencing rules (run this yourself)

**Preconditions:** the rule check above (`scripts/check-efa-sg.sh`) reports `[FAIL]` on inbound or outbound self-ref for `<SG_ID>`; `<SG_ID>` is one of the security groups attached to the HyperPod cluster (`describe-cluster → VpcConfig.SecurityGroupIds`); apply once **per SG** if multiple are attached; for IaC-managed SGs, see the operating-policy IaC note in SKILL.md before running directly.

**Command:**

```bash
aws ec2 authorize-security-group-egress --group-id <SG_ID> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG_ID>","Description":"HyperPod EFA intra-SG"}]}]'

aws ec2 authorize-security-group-ingress --group-id <SG_ID> --region <REGION> \
  --ip-permissions '[{"IpProtocol":"-1","UserIdGroupPairs":[{"GroupId":"<SG_ID>","Description":"HyperPod intra-SG"}]}]'
```

**Blast radius:** opens all protocols between instances that share this SG (intended scope for intra-cluster EFA traffic) — does not open anything to the internet or to other SGs. Idempotent: `InvalidPermission.Duplicate` = the rule already exists. Reversible with `revoke-security-group-ingress`/`revoke-security-group-egress` using the same `--ip-permissions` payload. For outbound internet access, route at the subnet level (NAT gateway or VPC endpoints) — not via a `0.0.0.0/0` rule on this SG (per HyperPod prerequisites).

**For provisioned nodes with EFA problems**, use the `hyperpod-ssm` skill to upload and run `check-node-reachability.sh`, or spot-check:

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> 'fi_info -p efa'
```

---

## B: VPC / Routing

**Signals:** `"bootstrap failed...network misconfiguration"`, S3 timeout, subnet/VPC mismatch, DNS resolution failure, node unreachable despite correct SG.

```bash
bash scripts/check-vpc-config.sh --cluster <CLUSTER> --region <REGION>
```

### B.1 Common errors

| Error                                                 | Fix (each is a mutation — see Suggested-command blocks below or in the referenced section)                                                                                                                                                                                    |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SG and subnet in different VPCs                       | Move SG to same VPC as subnet                                                                                                                                                                                                                                                 |
| S3 timeout (endpoint unreachable from private subnet) | Add an S3 Gateway VPC endpoint — see [hyperpod-cluster-debugger § lifecycle-scripts](../../hyperpod-cluster-debugger/references/lifecycle-scripts.md) for the Suggested-command block                                                                                         |
| EKS auth mode is `CONFIG_MAP` only                    | Access entries require `API` or `API_AND_CONFIG_MAP`; switching the auth mode is a cluster-level change — see the EKS access-entries docs and [hyperpod-cluster-debugger § D](../../hyperpod-cluster-debugger/references/cluster-diagnostics-detail.md#d-eks-access--kubectl) |
| `aws-hyperpod` namespace missing                      | `kubectl create namespace aws-hyperpod` — customer-run. **Preconditions:** namespace is genuinely missing (not just RBAC denial). **Blast radius:** creates a new namespace; low risk, but confirm which namespace HyperPod expects on this cluster version                   |
| Workers can't reach EKS controller                    | Add route to EKS VPC CIDR in worker subnet; check VPC flow logs                                                                                                                                                                                                               |

### B.2 VPC DNS

HyperPod requires both `enableDnsSupport` and `enableDnsHostnames` on the VPC. Without these, EKS internal DNS, internal hostnames, and `ip-x-x-x-x` Slurm nodenames fail to resolve.

Diagnose (read-only):

```bash
aws ec2 describe-vpc-attribute --vpc-id <VPC> --attribute enableDnsSupport   --region <R> --query 'EnableDnsSupport.Value'
aws ec2 describe-vpc-attribute --vpc-id <VPC> --attribute enableDnsHostnames --region <R> --query 'EnableDnsHostnames.Value'
```

### Suggested command — enable VPC DNS attributes (run this yourself)

**Preconditions:** VPC is customer-owned in this account (cannot modify attributes on a VPC shared from another account via RAM); current values are `false` (verify with the read-only `describe-vpc-attribute` calls above — calling modify on already-enabled attributes is a harmless no-op but wastes a call); change is acceptable cluster-wide (every instance in the VPC gains Amazon DNS resolution and internal hostnames).

**Command:**

```bash
aws ec2 modify-vpc-attribute --vpc-id <VPC> --region <R> --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id <VPC> --region <R> --enable-dns-hostnames '{"Value":true}'
```

**Blast radius:** additive — enables Amazon-provided DNS resolution and `ip-x-x-x-x` internal hostnames for every existing and future instance in this VPC. Does not affect existing IPs, routes, or SGs. Reversible by setting the values to `false`, but disabling on a live HyperPod cluster will break EKS internal DNS and Slurm nodename resolution.

### B.3 Private subnets

HyperPod subnets should be private — route tables should not have a direct default route to an IGW. If outbound internet is needed, route `0.0.0.0/0` via a NAT Gateway in a separate public subnet. In air-gapped VPCs, the default route can be absent and outbound goes through VPC endpoints (§ B.4).

```bash
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=<subnet-1>,<subnet-2>" \
  --region <R> \
  --query "RouteTables[*].{Assoc:Associations[?SubnetId!=\`null\`].SubnetId,Routes:Routes[?DestinationCidrBlock==\`0.0.0.0/0\`]}" \
  --output json
```

| Route target for `0.0.0.0/0` | Subnet type                  | Action                                         |
| ---------------------------- | ---------------------------- | ---------------------------------------------- |
| `igw-*`                      | Public — not supported       | Remove IGW route; use a NAT Gateway            |
| `nat-*`                      | Private with internet egress | OK                                             |
| Absent                       | Fully private / air-gapped   | OK if VPC endpoints are configured — see § B.4 |
| `vpce-*`                     | Endpoint-only routing        | OK                                             |

### B.4 VPC endpoints (internet-disabled VPCs)

When there is no NAT Gateway, nodes need private interface endpoints for every AWS service they call. Interface endpoints listen on TCP/443 — the endpoint's SG must allow inbound 443 from the HyperPod subnet CIDR.

| Endpoint                                   | Type      | Required     | Purpose                                                                                                                                             |
| ------------------------------------------ | --------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `com.amazonaws.<region>.s3`                | Gateway   | **Yes**      | Lifecycle scripts, DLC image layers                                                                                                                 |
| `com.amazonaws.<region>.ecr.api`           | Interface | **Yes**      | ECR authentication                                                                                                                                  |
| `com.amazonaws.<region>.ecr.dkr`           | Interface | **Yes**      | Pull container images                                                                                                                               |
| `com.amazonaws.<region>.sts`               | Interface | **Yes**      | STS calls (AssumeRole, GetCallerIdentity)                                                                                                           |
| `com.amazonaws.<region>.ssm`               | Interface | **Yes**      | SSM Session Manager                                                                                                                                 |
| `com.amazonaws.<region>.ssmmessages`       | Interface | **Yes**      | SSM session traffic                                                                                                                                 |
| `com.amazonaws.<region>.ec2messages`       | Interface | **Yes**      | SSM heartbeats                                                                                                                                      |
| `com.amazonaws.<region>.ec2`               | Interface | **Yes**      | EC2 control-plane API (DescribeInstances, EBS volume operations) — instance metadata is link-local (169.254.169.254) and does not use this endpoint |
| `com.amazonaws.<region>.sagemaker.api`     | Interface | **Yes**      | HyperPod control plane                                                                                                                              |
| `com.amazonaws.<region>.sagemaker.runtime` | Interface | **Yes**      | Runtime calls                                                                                                                                       |
| `com.amazonaws.<region>.logs`              | Interface | **Yes**      | CloudWatch lifecycle + health-monitoring-agent logs                                                                                                 |
| `com.amazonaws.<region>.eks`               | Interface | EKS only     | Required if EKS endpoint is private-only                                                                                                            |
| `com.amazonaws.<region>.fsx`               | Interface | If using FSx | Required for FSx for Lustre / OpenZFS                                                                                                               |

### B.5 EKS ↔ HyperPod VPC alignment

When orchestrator is EKS, the EKS cluster and the HyperPod cluster must share a VPC. The SG attached to the HyperPod cluster must either be attached to the EKS cluster itself OR the EKS cluster SG must allow inbound from the HyperPod SG.

Diagnose (read-only):

```bash
aws sagemaker describe-cluster --cluster-name <HP>  --region <R> --query 'VpcConfig.{Subnets:Subnets,SGs:SecurityGroupIds}'
aws eks describe-cluster       --name         <EKS> --region <R> --query 'cluster.resourcesVpcConfig.{VPC:vpcId,SGs:securityGroupIds,ClusterSG:clusterSecurityGroupId}'
```

### Suggested command — allow HyperPod SG inbound on the EKS cluster SG (run this yourself)

**Preconditions:** the orchestrator is EKS and the HyperPod cluster is in the same VPC as the EKS cluster (verify with the read-only `describe-cluster` calls above); `<EKS_CLUSTER_SG>` is the **EKS-managed cluster SG** (`clusterSecurityGroupId` from `eks describe-cluster`), **not** a worker SG; `<HP_SG>` is one of the security groups attached to the HyperPod cluster (`VpcConfig.SecurityGroupIds`); the customer prefers the SG-allow approach over re-attaching the HyperPod SG directly to the EKS cluster (both are valid; this rule is needed only when they're not attached).

**Command:**

```bash
aws ec2 authorize-security-group-ingress --group-id <EKS_CLUSTER_SG> --region <R> \
  --ip-permissions "[{\"IpProtocol\":\"-1\",\"UserIdGroupPairs\":[{\"GroupId\":\"<HP_SG>\",\"Description\":\"HyperPod worker traffic\"}]}]"
```

**Blast radius:** opens all protocols from every ENI using `<HP_SG>` to the EKS control-plane SG — scoped to two SGs, not the world. Idempotent: returns `InvalidPermission.Duplicate` if the rule already exists. Reversible with `revoke-security-group-ingress` and the same `--ip-permissions` payload.

---

## C: Capacity / AZ

**Signals:** insufficient-capacity or AZ-mismatch failure at creation or replacement time.

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
CLUSTER_NAME="<C>"
REGION="<R>"
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'ClusterArn' --output text | cut -d/ -f2)
LOG_GROUP="/aws/sagemaker/Clusters/${CLUSTER_NAME}/${CLUSTER_ID}"
aws logs describe-log-streams --log-group-name "$LOG_GROUP" --region "$REGION" \
  --query 'logStreams[?starts_with(logStreamName,`LifecycleConfig`)].logStreamName' --output table
```

On-node:

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'cat /var/log/provision/provisioning.log'
```

| Log error                                | Fix                                                        |
| ---------------------------------------- | ---------------------------------------------------------- |
| `Connect timeout on endpoint URL: s3://` | Add S3 VPC Gateway endpoint                                |
| `AccessDenied` on S3                     | Add `s3:GetObject` + `s3:ListBucket` to execution role     |
| Script never exits                       | Add proper exit; check infinite loops; test script locally |
| `CRLF line terminators`                  | `dos2unix script.sh` before uploading                      |
| `provisioning_parameters.json` mismatch  | Instance group names must match between script and API     |

---

## E: Software Versions

**Signals:** NCCL hangs after node replacement, training fails after AMI update, version drift across nodes.

**Delegate to `hyperpod-version-checker`** — compares NVIDIA driver, CUDA, NCCL, EFA installer, OFI NCCL, PyTorch across all nodes.

### Quick spot-check on a node (via `hyperpod-ssm`)

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'nvidia-smi --query-gpu=driver_version --format=csv,noheader && \
   nvcc --version | grep "release" && \
   head -3 /opt/amazon/efa_installed_packages && \
   python3 -c "import torch; print(torch.__version__, torch.version.cuda)"'
```

### CUDA driver vs `nvcc` toolkit

The CUDA driver (`nvidia-smi`) and the CUDA toolkit / `nvcc` (`nvcc --version`) must be a supported pair — a newer toolkit cannot target an older driver. Mismatch commonly causes `CUDA error: no kernel image is available for execution on the device` or kernel-launch segfaults.

```bash
nvidia-smi | grep "CUDA Version"         # max CUDA the driver supports
nvcc --version | grep "release"          # installed toolkit
```

Compatibility matrix: see the NVIDIA CUDA Toolkit Release Notes for the toolkit version in use.

### EFA / NCCL / libfabric

EFA installer version and AWS OFI NCCL version must be paired per the EFA changelog:

```bash
cat /opt/amazon/efa_installed_packages | head -10
fi_info -p efa | head -5
```

Compatibility matrix: see the AWS EFA installer changelog for the version in use.

### Container vs host mismatches

If training works on the host but fails in the container (or vice versa), the cause is almost always one of:

1. **EFA libraries not mounted into the container** — container must see `/opt/amazon/efa`, `/opt/amazon/openmpi`, and `/dev/infiniband`. Without these NCCL silently falls back to TCP.
2. **`LD_LIBRARY_PATH` missing EFA / CUDA paths inside the container**:

   ```bash
   export LD_LIBRARY_PATH=/opt/amazon/efa/lib:/opt/amazon/openmpi/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH
   ```

3. **PyTorch / TF built against a different CUDA major than the host driver supports** — rebuild from a base image whose CUDA matches the host (e.g. AWS DLC `pytorch-training:<ver>-gpu-py<ver>-cu<host-major>-ubuntu*`).

After a driver upgrade, CUDA devices may fail to init until the node is rebooted. Use `batch-reboot-cluster-nodes` (§ F) and re-run training.

### Required job-launcher env vars

Per the EC2 EFA-with-NCCL guide: `FI_EFA_USE_DEVICE_RDMA=1` (RDMA-capable instances). For NCCL over EFA, also set `FI_PROVIDER=efa` and `NCCL_SOCKET_IFNAME=^lo,docker` to keep NCCL's bootstrap off the loopback / docker interfaces. `NCCL_TIMEOUT` (seconds) is not AWS-prescribed — tune to your job's longest expected collective if jobs trip the default; otherwise leave unset.

### Validation

For PyTorch environment and EFA / network-stack validation, use the AWS-published validation guides for SageMaker HyperPod (available from the AWS SageMaker HyperPod documentation).

---

## F: Hardware / Auto-Repair

**Signals:** hardware failure event, EKS label `UnschedulablePendingReplacement`, XID errors, auto-repair not triggering.

```bash
# NodeRecovery on each group
aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'InstanceGroups[*].{Group:InstanceGroupName,Recovery:NodeRecovery}'

# EKS: all node repair labels at once
kubectl get nodes -o custom-columns='NODE:.metadata.name,HEALTH:.metadata.labels.sagemaker\.amazonaws\.com/node-health-status,FAULT:.metadata.labels.sagemaker\.amazonaws\.com/fault-types'

# Repair events — ListClusterEvents returns `Events[*]` with field `Description`
aws sagemaker list-cluster-events --cluster-name <C> --region <R> \
  --query 'Events[?contains(Description,`replacement`) || contains(Description,`reboot`) || contains(Description,`hardware`)]' \
  --output table

# Slurm: HMA auto-recovery is triggered by the health-monitoring agent (not the Slurm reason).
# The Slurm "Action:Reboot" / "Action:Replace" reason is the manual-recovery path — a user sets
# it to ask HyperPod to reboot/replace the node. See "Manually mark a node..." below.
sinfo -o "%N %T %30E"
```

### Suggested command — batch-reboot (run this yourself, soft recovery first)

**Preconditions:**

- Fault is plausibly transient (deep-health-check failure, driver hang, stuck process) and reboot may clear it. For confirmed hardware faults (uncorrectable ECC, GPU off-bus, NVLink), skip to batch-replace below.
- Each node ID belongs to this cluster (verify with `list-cluster-nodes`).
- Workload on the node can tolerate a restart — training processes on the node are interrupted.
- On Slurm: rebooting will not disrupt critical cluster operations (per the API doc note); prefer to drain the node first via `scontrol update state=drain` to avoid the "Node unexpectedly rebooted" flag (§ H).
- `NodeIds` batch size: 1–25 per call (API limit).

**Command:**

```bash
aws sagemaker batch-reboot-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
```

**Blast radius:** per the API doc, "performs a graceful reboot… by calling the Amazon EC2 RebootInstances API." Preserves instance identity, root volume, and secondary volumes — **no data loss**. Training processes on the node are interrupted; pods on EKS are evicted by kubelet during the restart and rescheduled by the workload controller after the node returns Ready. Recovery time depends on instance type, AMI boot time, and any post-boot lifecycle work.

### Suggested command — batch-replace (run this yourself, only if reboot did not clear the fault)

**Preconditions:**

- Reboot attempted first and did not clear the fault.
- Hardware fault confirmed (uncorrectable ECC, GPU bus / NVLink errors, EFA hardware failure); not a software or config issue.
- Data on root + secondary volumes is backed up to S3 or FSx — **per the API doc: "Replacing nodes destroys all instance volumes, including both root and secondary volumes. All data stored on these volumes will be permanently lost and cannot be recovered."**
- Target is **NOT** a Slurm controller node — per the API doc: "For SageMaker HyperPod clusters using the Slurm workload manager, you cannot replace instances that are configured as Slurm controller nodes."
- Cluster has been patched via `UpdateClusterSoftware` — per the API doc: "If you want to invoke this API on an existing cluster, you'll first need to patch the cluster by running the UpdateClusterSoftware API."
- `NodeIds` batch size: 1–25 per call (API limit).

**Command:**

```bash
aws sagemaker batch-replace-cluster-nodes --cluster-name <C> --region <R> --node-ids '["<ID>"]'
```

**Blast radius:** destroys root + secondary volumes on the replaced instance (permanent data loss). New hardware is provisioned with the same AMI and instance configuration.

**Karpenter note:** Karpenter's documented design provisions nodes from pending/unschedulable pods (see Karpenter docs on disruption/provisioning), not as a one-for-one node replacement service. So on Karpenter-managed clusters, `BatchReplaceClusterNodes` terminates the node but **does not by itself guarantee a Karpenter-launched replacement** — Karpenter creates a new node only if pods become unschedulable on remaining capacity. If you need a guaranteed replacement, ensure workload configuration (pod anti-affinity, resource requests) forces pods to a new node.

**Common blockers:** `NodeRecovery=None` (enable it), health agent hasn't detected yet (check `SagemakerHealthMonitoringAgent/<group>/<instance>` stream), lifecycle script failing on replacement (check `LifecycleConfig` stream), insufficient capacity, cluster not `InService`.

### HMA detection events

The Health Monitoring Agent emits `HealthMonitoringAgentDetectionEvent` records to CloudWatch. Use these to read fault history before triggering a manual replace.

```bash
CLUSTER_ID=$(aws sagemaker describe-cluster --cluster-name <C> --region <R> \
  --query 'ClusterArn' --output text | cut -d/ -f2)

aws logs filter-log-events \
  --log-group-name "/aws/sagemaker/Clusters/<C>/${CLUSTER_ID}" \
  --log-stream-name-prefix "SagemakerHealthMonitoringAgent/" \
  --filter-pattern 'HealthMonitoringAgentDetectionEvent' \
  --region <R> \
  --query 'events[*].[timestamp,logStreamName,message]' --output table
```

Reference: the SageMaker HyperPod EKS Health Monitoring Agent documentation.

### Repeat-Xid analysis

A hardware-caused Xid will recur after each reboot because reboot does not repair hardware. If you see the same Xid on the same instance more than once, the node almost certainly needs to be replaced rather than rebooted again.

Count Xid occurrences per instance from the HMA detection stream in the customer-visible cluster log group:

```bash
# Log group: /aws/sagemaker/Clusters/<CLUSTER>/<CLUSTER_ID>
# Stream prefix: SagemakerHealthMonitoringAgent/
fields @timestamp, @logStream, @message
| parse @message /Xid.*?:\s*(?<xidCode>\d+)/
| filter @message like /HealthMonitoringAgentDetectionEvent/ and @message like /Xid/
| stats count(*) as errorCount,
        earliest(@timestamp) as firstError,
        latest(@timestamp) as lastError
  by @logStream, xidCode, bin(1h) as hourBin
| sort hourBin desc, errorCount desc
```

A recurring same-Xid + same-instance row is the signal to replace rather than reboot. The exact recurrence threshold is operator choice — many teams use ≥ 2 within a single time window as the trigger.

### Node-level fault details (EKS)

When HMA detects a fault it writes a four-part response onto the node (per the HyperPod HMA documentation):

- **Labels**: `sagemaker.amazonaws.com/node-health-status`, `sagemaker.amazonaws.com/fault-types`, `sagemaker.amazonaws.com/fault-reasons`
- **Taint**: `sagemaker.amazonaws.com/node-health-status=Unschedulable:NoSchedule`
- **Annotation**: `sagemaker.amazonaws.com/fault-details` — JSON array recording recent faults with timestamps; check the HyperPod HMA doc for the current retention limit
- **Condition** (per the HMA doc): `Type` = fault type, `Status` = `True`, `Reason` = fault reason, `LastTransitionTime` = fault occurrence time. After a successful recovery the condition status flips back to `False`.

```bash
kubectl get node <NODE> -o jsonpath='{.metadata.annotations.sagemaker\.amazonaws\.com/fault-details}' | jq
kubectl get node <NODE> -o jsonpath='{.status.conditions}' | jq '.[] | select(.type|contains("GPU"))'
```

### Manually trigger reboot or replace on EKS (kubectl label)

If HMA has not detected a fault but the customer has independent evidence, a label can trigger the existing HyperPod recovery path.

### Suggested command — trigger replace on EKS (run this yourself)

**Preconditions:** `NodeRecovery=Automatic` on the instance group; hardware fault confirmed on `<NODE>` (not a software/config issue); data on root + secondary volumes is backed up; cluster has been patched via `UpdateClusterSoftware` if this is the first replace on an existing cluster. Per the HyperPod EKS manual-recovery doc, the **preferred path is the Reboot/Replace APIs** (`BatchReplaceClusterNodes`); labelling is an alternative that activates the same recovery process.

**Command:**

```bash
kubectl label nodes <NODE> sagemaker.amazonaws.com/node-health-status=UnschedulablePendingReplacement
```

**Blast radius:** marks the node for replacement. Destroys root + secondary volumes on the replaced instance — all data on those volumes is lost. New hardware is provisioned with the same AMI.

### Suggested command — trigger reboot on EKS (run this yourself)

**Preconditions:** `NodeRecovery=Automatic` on the instance group; fault is plausibly transient (deep-health-check failure, driver hang) and reboot may clear it; workload can tolerate restart.

**Command:**

```bash
kubectl label nodes <NODE> sagemaker.amazonaws.com/node-health-status=UnschedulablePendingReboot
```

**Blast radius:** soft recovery — preserves identity, root volume, and secondary volumes. Training processes on the node are interrupted.

### Suggested command — manually trigger recovery on Slurm (run this yourself)

Per the HyperPod Slurm manual-recovery doc, the **preferred path is the batch APIs** (`BatchReboot`/`BatchReplaceClusterNodes`) — the `scontrol` commands below are documented as a legacy alternative that requires direct Slurm-controller access. Both paths activate the same HyperPod recovery processes.

**Preconditions:** Slurm orchestrator; `scontrol` run on the controller via SSM; customer has decided between reboot (transient fault) and replace (confirmed hardware fault); replace target is NOT a Slurm controller node; data backed up for replace; cluster has been patched via `UpdateClusterSoftware` if invoking replace on an existing cluster.

**Command:**

```bash
# Reboot — soft recovery:
scontrol update node=<ip-ipv4> state=fail reason="Action:Reboot"

# Replace — destroys root + secondary volumes:
scontrol update node=<ip-ipv4> state=fail reason="Action:Replace"
```

Per the HyperPod Slurm manual-recovery doc: for `Action:Replace` the node goes into `fail`, waits for running jobs to finish, then is replaced with a fresh instance using the same host name. For either command, do not change the node state or restart `slurmctld` while recovery is in progress — this can leave the node stuck.

**Last-resort force** — if the node is stuck in `fail`, the HyperPod Slurm manual-recovery doc provides `scontrol update node=<ip-ipv4> state=down reason="Action:Replace"` as a last resort. Per the doc: "this requires administrator privileges (sudo permissions)" and (warning) "it forces kill all jobs, and you might lose all unsaved work." Confirm with the customer that lost in-flight work is acceptable before running.

**Blast radius:** drains the named node. `Action:Replace` inherits the same blast radius as `batch-replace-cluster-nodes` (root + secondary volumes destroyed). `state=down` additionally force-kills running jobs.

### Suggested command — force-delete a stuck Terminating pod (last resort; run this yourself)

**Preconditions:** pod has been in `Terminating` state on `<NODE>` for >30 minutes; the node is quarantined (cordoned, fault confirmed); customer has approved the forced deletion; you understand the API server will remove the pod object immediately even if the container is still running on the node.

**Command:**

```bash
kubectl cordon <NODE>
kubectl delete pods <POD> --grace-period=0 --force
```

**Blast radius:** `--grace-period=0 --force` removes the pod from the API without waiting for kubelet to confirm termination — the container may continue running on the node until the node is rebooted or replaced. Only appropriate when the node will be rebooted/replaced afterward. For a healthy node, use the default `kubectl delete pod` and let the grace period elapse.

---

## G: GPU/Accelerator

**Signals:** GPU off bus, `deep-health-check-status: Failed`, XID errors, low utilization, ECC errors, thermal throttling, NeuronCore errors.

### G.1: NVIDIA (p4d/p5/g5/g6)

Run on the affected node via `hyperpod-ssm`:

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'nvidia-smi -L && nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,ecc.errors.uncorrected.volatile.total --format=csv && nvidia-smi -q | grep -E "Xid|Error Type|ECC" && dmesg | grep -i "xid\|nvrm\|pcie\|error" | tail -20'
```

**ECC:** any uncorrectable error (UCE) → drain and replace. Correctable errors are background noise individually but a growing rate across many GPUs is worth escalating. For detailed GPU diagnostics (NVLink, dmon, XID codes), see [node-issue-catalog.md § 2](node-issue-catalog.md#2-gpu--accelerator).

**Xid reference (per NVIDIA Xid error catalog):** common Xid numbers seen in HyperPod dmesg / HMA `fault-details`:

| Xid | NVIDIA name                  | Class | Typical cause                                                                                 |
| --- | ---------------------------- | ----- | --------------------------------------------------------------------------------------------- |
| 13  | Graphics Engine Exception    | App   | User-application fault (out-of-bounds, illegal instruction / register)                        |
| 31  | GPU memory page fault        | App   | Illegal address access by a chip unit (usually an application bug; occasionally driver or HW) |
| 63  | GPU memory remapping event   | HW    | ECC memory event; on Ampere+ provides row-remapper detail (see § G.1.a for row-remap triage)  |
| 71  | CE4 Error                    | HW    | Copy Engine 4 exception (seen in HMA example detection logs on HyperPod p-family instances)   |
| 74  | NVLINK Error                 | HW    | NVLink connectivity issue between GPUs / NVSwitch                                             |
| 79  | GPU has fallen off the bus   | Bus   | Driver cannot reach GPU over PCIe — failing link or GPU (drain + replace)                     |
| 109 | Context Switch Timeout Error | HW    | Timeout during GPU context switch                                                             |

For an App-classified Xid (13, 31), investigate the workload before replacing hardware; HMA will reboot on the fault but a software cause will recur until the workload is fixed.

#### G.1.a Row-remap state (silent memory degradation)

Row-remapping is the mechanism that permanently reassigns physical memory rows around defects on H100 / A100 GPUs. The remap state is the most reliable signal of _silent_ memory degradation — accuracy regressions, sporadic NaNs, and intermittent NCCL hangs that no XID or ECC count explains.

```bash
nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.correctable,remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
  --format=csv
```

| State                               | Meaning                                                    | Action                                                                             |
| ----------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `pending = 0`, `failure = No`       | Healthy                                                    | None                                                                               |
| `pending > 0`                       | Remap staged but needs a GPU reset / reboot to take effect | Reboot via `batch-reboot-cluster-nodes` (§ F); recheck — pending should reach 0    |
| `pending > 0` persists after reboot | Remap stuck "pending" — memory is silently degrading       | Drain and replace via `batch-replace-cluster-nodes` (§ F); escalate to AWS Support |
| `failure = Yes`                     | Remap capacity exceeded                                    | Drain and replace (§ F)                                                            |

`uncorrectable > 0` with `pending = 0` means historical rows that have already been remapped — fine going forward, but a high count is a warning sign for the hardware cohort.

#### G.1.b DCGM health and nvvs logs

HyperPod runs DCGM as part of the deep-health-check. Findings are under `/var/log/nvidia-dcgm/`.

```bash
dcgmi health --check -j

ls -1t /var/log/nvidia-dcgm/ | head
tail -n 200 "$(ls -1t /var/log/nvidia-dcgm/nvvs*.log | head -1)"
```

Treat only **Fail** / **Warn** verdicts as authoritative. For comprehensive data collection before opening a ticket:

```bash
sudo nvidia-bug-report.sh                                    # NVIDIA's authoritative bundle
sudo tar -czf /tmp/nvidia-dcgm-logs.tgz /var/log/nvidia-dcgm/
```

Attach both to the AWS Support case along with the triage script output.

### G.2: AWS Trainium / Inferentia (trn1/trn2/inf2)

These use the **AWS Neuron SDK**, not CUDA. `nvidia-smi` will not work.

**Quick health check (via SSM):**

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'neuron-ls && neuron-top -n 1 2>/dev/null || echo "neuron-top not available" && dmesg | grep -i "neuron\|nrt\|error" | tail -20'
```

| Command                       | Shows                                                        |
| ----------------------------- | ------------------------------------------------------------ |
| `neuron-ls`                   | Lists all NeuronCore devices, count, status                  |
| `neuron-top`                  | Live utilization (NeuronCore %, memory, model loaded)        |
| `neuron-monitor`              | JSON metrics stream                                          |
| `dmesg \| grep -i neuron`     | Kernel-level Neuron errors                                   |
| `systemctl status neuron-rtd` | Neuron Runtime daemon (older AMIs; deprecated in SDK ≥ 2.10) |
| `pip show neuronx-cc`         | Neuron Compiler version                                      |
| `pip show torch-neuronx`      | PyTorch Neuron version                                       |

**Per-chip counts** (AWS Neuron architecture docs):

| Chip                        | Cores per chip |
| --------------------------- | -------------- |
| Trainium1 (NeuronCore-v2)   | 2              |
| Inferentia2 (NeuronCore-v2) | 2              |

Trainium2 uses **NeuronCore-v3**, with a different per-chip core count and HBM topology than the v2 chips above; check the AWS Neuron Trainium2 architecture doc and `neuron-ls` on the node for the authoritative numbers.

For the chip count per instance type (NeuronDevices × per-chip cores = total), use `neuron-ls` on the node as the source of truth; the AWS EC2 Trn1 / Trn2 / Inf2 instance-types docs are the authoritative reference if you need a number before node-access is available. Per the HyperPod HMA doc: "Neuron Device Count validation — if there's a mismatch between the actual number of neuron device count in a particular instance type and the count returned by `neuron-ls`, then HMA **reboots** the node." Replacement only happens if reboots fail to clear the fault.

**Common issues:**

| Symptom                                    | Likely cause                                      | Action                                                                                                                                                                                                                                                  |
| ------------------------------------------ | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `neuron-ls` shows 0 devices                | Neuron kernel driver not loaded                   | Check `lsmod \| grep neuron`; if the module is absent, the AMI is missing the Neuron driver — use the AWS Neuron DLAMI or rebuild the AMI with Neuron support (loading kernel modules on a running cluster node is a mutation; do not attempt in-place) |
| `neuron-ls: command not found`             | Neuron SDK not installed                          | Install from the AWS Neuron repo, or use the AWS Neuron DLAMI                                                                                                                                                                                           |
| NeuronCore count < expected                | Device failure / driver issue / partial detection | Reboot the node (§ F). If the count is still low, replace.                                                                                                                                                                                              |
| `NRT_UNRECOVERABLE_ERROR` in dmesg or logs | Unrecoverable NeuronDevice fault                  | Drain and replace (§ F). Do not attempt software-only recovery.                                                                                                                                                                                         |
| OOM on NeuronDevice (HBM exhaustion)       | Model + activations + optimizer exceed HBM        | Increase tensor-parallel degree, enable activation checkpointing, or scale up                                                                                                                                                                           |
| Version mismatch across nodes              | AMI drift after partial replacement               | Pin Neuron package versions in the lifecycle script so replacements converge                                                                                                                                                                            |

### Accelerator failure → Section F

Drain the node, then follow the reboot / replace Suggested-command blocks in § F.

### Suggested command — drain the node before reboot/replace (run this yourself)

**Preconditions:** accelerator failure confirmed on `<node-name>` (GPU off-bus, uncorrectable ECC, NeuronDevice `NRT_UNRECOVERABLE_ERROR`); customer accepts that pods using `emptyDir` volumes on this node will lose that data when evicted (EKS path); on Slurm, customer accepts that no new jobs will be scheduled to the node until `state=resume` runs after recovery; you understand drain is preparation for reboot/replace, not a fix on its own.

**Command:**

```bash
# EKS — cordon prevents new pods; drain evicts existing pods (emptyDir data lost).
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Slurm — on the controller via SSM. Running jobs continue until they finish; no new jobs are scheduled.
scontrol update nodename=<node-name> state=drain reason="Accelerator failure -- replacing"
```

**Blast radius:** EKS — `--delete-emptydir-data` discards any in-pod scratch in `emptyDir` volumes (training caches, ephemeral checkpoints not persisted to PVC/`/opt/sagemaker`); pods are rescheduled elsewhere if capacity exists, otherwise stay Pending. Slurm — running jobs finish on the node; pending jobs route around it. Drain is reversible (`kubectl uncordon` / `scontrol update state=resume`) only if you decide not to proceed with reboot/replace.

---

## H: Slurm Node Management

**Signals:** Node `down`, `"Node unexpectedly rebooted"`, jobs stuck PENDING/COMPLETING, `scontrol ping` fails.

### Node down / unresponsive

```bash
sinfo -o "%N %T %30E"          # state + reason
scontrol show node <NODE>      # full details

# Connectivity checks
ping <node-ip>
ssh <node-name>
srun -w <node-name> hostname
```

Diagnose (read-only):

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'sudo systemctl status slurmd && free -h && df -h'
```

### Suggested command — bring the node back in Slurm (run this yourself)

**Preconditions:** root cause of the original `slurmd` failure has been **identified and resolved** (disk full, OOM, config parse error) — running `start` on a node whose underlying issue is unfixed will stop again immediately; node passes a basic health probe (`free -h`, `df -h /`, `df -h /opt/sagemaker`); customer accepts that pending jobs may schedule onto this node immediately after `state=resume`; do not run `systemctl enable slurmd` if the unit was _deliberately_ disabled by an admin (verify it was an unexpected reboot, not a config choice).

**Command:**

```bash
# 1. On the affected node — start (and enable, if an unexpected reboot just
#    knocked the unit out of auto-start):
sudo systemctl start slurmd
sudo systemctl enable slurmd   # only if it was not enabled before

# 2. On the Slurm controller — return the node to the idle pool:
scontrol update nodename=<N> state=resume
```

**Blast radius:** node returns to `idle` and pending jobs may schedule immediately. `enable` makes the unit auto-start on boot — if the unit was previously disabled by lifecycle script or admin, this changes that policy on this node only. Reversible: `scontrol update state=drain` to take it back out of scheduling, `systemctl disable slurmd` to revert auto-start. If start+resume does not hold (slurmd dies or node rejoins as `down`), escalate to batch-reboot then batch-replace (§ F).

Before any intentional reboot of a Slurm compute node, set `scontrol update state=drain` first and `state=resume` after — this avoids Slurm flagging the node as unexpectedly rebooted.

### Jobs stuck PENDING / COMPLETING → restart slurmctld

**When:** PENDING with `Reason=Resources` despite free nodes, GRES miscalculation, COMPLETING after replacement, `scontrol ping` fails.

### Suggested command — restart slurmctld (run this yourself)

**Preconditions:** restart is targeting a **specific known cause** that an in-memory restart fixes (cached COMPLETING state after replacement, GRES miscalculation, scheduler not recomputing after node moves); the underlying cluster config is intact — `slurm.conf` parses cleanly (`scontrol show config >/dev/null` succeeds), `StateSaveLocation` is reachable and not full; the customer is OK with a brief scheduler pause during which no new jobs schedule and `scontrol`/`squeue`/`sbatch` calls return transient errors; no node recovery operation (`Action:Reboot`/`Action:Replace`) is in progress — restarting the controller mid-recovery can leave the affected node stuck.

**Command:**

```bash
sudo systemctl restart slurmctld && sinfo && squeue
```

**Blast radius:** brief scheduler pause; running jobs are not interrupted (slurmd keeps them going); pending queue and node states are preserved on disk via `StateSaveLocation`. New job submissions during the restart window receive a transient error and must be retried by the user. If `systemctl restart` does not return, the daemon is hung — investigate a stuck `StateSaveLocation` (full disk, NFS hang) before any forcible kill, since killing slurmctld with corrupt state files can lose the queue.

### Slurm node name → instance ID

`list-cluster-nodes` does **not** return `PrivateDnsHostname` — that field is only populated by `describe-cluster-node`. So the mapping is a two-step call: list the instance IDs in the cluster, then describe each one to get the DNS hostname.

```bash
# 1. List candidate instance IDs (running nodes only, skip utility groups)
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query 'ClusterNodeSummaries[?InstanceStatus.Status==`Running`].[InstanceId,InstanceGroupName,InstanceType]' \
  --output text

# 2. For each candidate, fetch the DNS hostname and match against the Slurm name
NODE="ip-10-1-2-3"   # Slurm node name
for IID in $(aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
               --query 'ClusterNodeSummaries[?InstanceStatus.Status==`Running`].InstanceId' --output text); do
  DNS=$(aws sagemaker describe-cluster-node --cluster-name <C> --region <R> --node-id "$IID" \
          --query 'NodeDetails.PrivateDnsHostname' --output text 2>/dev/null)
  case "$DNS" in
    "$NODE."*) echo "$NODE → $IID"; break ;;
  esac
done
```

**Scale note:** the for-loop above issues one `describe-cluster-node` API call per Running instance until it finds a match. On clusters with thousands of running nodes that's a lot of API calls; SageMaker has a default rate limit on the `Describe*` family (~10 TPS) so this can take minutes and incur throttling. For large clusters, use `dump_cluster_nodes_info.py` (AWS samples repo `awsome-distributed-training`) once to generate a CSV of IP ↔ instance-ID mappings, then look up locally.

---

## I: Resource Exhaustion

**Signals:** Disk full, OOM kills, `"Cannot allocate memory"` at `os.fork()`, inode exhaustion, `/dev/shm` full.

### Diagnose (via `hyperpod-ssm` on the node)

```bash
df -h && df -i                             # disk + inodes
free -h                                    # RAM
df -h /dev/shm                             # shared memory
dmesg | grep -i oom | tail -10             # OOM kills
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -15
cat /proc/meminfo | grep Huge              # huge pages
```

### I.1: "Cannot allocate memory" at os.fork()

**Symptoms:** `OSError: [Errno 12] Cannot allocate memory` during `os.fork()`, DataLoader crashes, `Failed to register memory` during EFA init, segfaults during NCCL.

**Fix (in order):**

1. `export FI_EFA_USE_HUGE_PAGE=0` — try this first; add to job script, container entrypoint, or `/etc/environment`. Disabling EFA huge pages avoids the fork-time memory-registration path that fails when huge pages aren't pre-allocated.
2. Increase shared memory:
   - Docker: `docker run --shm-size=8g ...`
   - Kubernetes:

     ```yaml
     volumes:
     - name: dshm
       emptyDir: { medium: Memory, sizeLimit: 8Gi }
     volumeMounts:
     - { name: dshm, mountPath: /dev/shm }
     ```

3. Tune PyTorch DataLoader: `num_workers=4` (lower), `persistent_workers=True`, `pin_memory=False` if not bottlenecked on host→GPU copy.
4. Reduce batch size to lower parent-process memory before fork.

**If you need `FI_EFA_USE_HUGE_PAGE=1`**, pre-allocate huge pages first.

### Suggested command — pre-allocate huge pages on a node (run this yourself)

**Preconditions:** the workload requires `FI_EFA_USE_HUGE_PAGE=1` (most jobs do **not** — `=0` is the simpler fix and resolves the fork-time error on its own); free RAM on the node can absorb the reservation (1024 × 2 MiB = 2 GiB; check with `free -h` first); no existing process on the node already depends on a different `nr_hugepages` value; customer accepts that the persistent file (`/etc/sysctl.d/99-hugepages.conf`) survives reboots — on a node that may later be replaced, the file is destroyed with the volumes (replacement will recreate from the AMI/lifecycle script).

**Command:**

```bash
cat /proc/sys/vm/nr_hugepages                             # current
echo 1024 | sudo tee /proc/sys/vm/nr_hugepages            # 1024 × 2 MiB = 2 GiB, runtime-only
echo 'vm.nr_hugepages=1024' | sudo tee -a /etc/sysctl.d/99-hugepages.conf   # persist across reboots
```

**Blast radius:** reduces RAM available to other processes on the node by ~2 GiB immediately. Persistent file change applies on every boot of _this_ node — bake the same value into the lifecycle script so replacement nodes match. Setting `FI_EFA_USE_HUGE_PAGE=1` without pre-allocation is the root cause of the fork-time failure; setting it after pre-allocation fixes that path.

### I.2: Root Volume Exhausted

The default HyperPod root volume is **100 GB EBS**. **Do not plan to grow it post-creation** — redirect heavy data to `/opt/sagemaker` (secondary EBS, sized at instance-group creation) or `/opt/dlami/nvme` (NVMe instance store on P/G families). For shared persistence use FSx for Lustre / OpenZFS or S3.

| Mount             | Type                                                        | Persistence              | Best for                                      |
| ----------------- | ----------------------------------------------------------- | ------------------------ | --------------------------------------------- |
| `/opt/sagemaker`  | Secondary EBS (configurable per group)                      | Persistent               | Checkpoints, app data, logs, container images |
| `/opt/dlami/nvme` | NVMe instance store (on instance types that ship with NVMe) | **Lost on stop/replace** | Scratch, caches, temp files                   |
| FSx for Lustre    | Shared                                                      | Persistent               | Large datasets, shared models                 |
| FSx for OpenZFS   | Shared                                                      | Persistent               | Mixed workloads, snapshots                    |
| Amazon S3         | Object storage                                              | Persistent               | Large datasets, archives                      |

### Suggested command — reclaim disk space (run this yourself)

**Preconditions:** root-volume exhaustion confirmed (`df -h /` shows near-100%); customer has identified what is consuming space (`du -sh /var/* /opt/* 2>/dev/null | sort -h`); no training job is currently writing to the affected paths; you have **inspected** `/var/log/` and decided which files are safe to remove (never run a blanket wipe — target specific files identified by `du`); no running containers will be surprised by `docker system prune`.

**Command:**

```bash
# 1. Shrink journald — capped size, reversible by running again
sudo journalctl --vacuum-size=500M

# 2. Remove rotated logs YOU HAVE IDENTIFIED as safe to delete. Example
#    commands — review the file list first and adapt the globs:
ls -lah /var/log/*.log.* /var/log/*/*.gz 2>/dev/null   # inspect
# Then, targeted deletes for the specific logs you chose:
sudo rm -f /var/log/<specific-file>.log.N

# 3. Package-manager caches (safe):
sudo apt-get clean 2>/dev/null || sudo yum clean all 2>/dev/null

# 4. Docker prune — removes stopped containers, unused networks, dangling
#    images. Add --volumes only if you know no named volume holds training data.
docker system prune -a -f 2>/dev/null
```

**Blast radius:** `journalctl --vacuum-size` and package-manager `clean` are low-risk. Targeted `rm` in `/var/log/` is safe for rotated-and-gzipped files (`*.gz`) but a blanket `rm -f /var/log/*.log.*` can delete logs an incident team needs — always inspect first. `docker system prune -a` without `--volumes` leaves named volumes intact; adding `--volumes` will delete any unattached named volumes (including ones holding model checkpoints if not mounted at prune time).

**Redirect data:**

```bash
# Environment variables
export TORCH_HOME=/opt/sagemaker/torch_cache
export HF_HOME=/opt/sagemaker/huggingface_cache
export TRANSFORMERS_CACHE=/opt/sagemaker/transformers_cache
export TMPDIR=/opt/dlami/nvme/tmp && mkdir -p $TMPDIR

# Training scripts
checkpoint_dir = "/opt/sagemaker/checkpoints"
cache_dir = "/opt/dlami/nvme/cache"
```

For K8s pods, mount `/opt/sagemaker` and `/opt/dlami/nvme` as `hostPath` volumes. Check the customer's lifecycle script — the awsome-distributed-training samples typically point container runtimes at these paths, but custom scripts may not. **Prevention:** size secondary EBS generously at instance-group creation; growing it later is more disruptive than over-provisioning up front.

### I.3: OOM events

Triage signal: `[P1] OOM events on node <i-xxx>`.

```bash
sudo dmesg -T | grep -i -B2 -A30 "Out of memory" | tail -80
ps auxf --sort=-%mem | head -20
```

The fix is in the workload spec (pod `resources.limits.memory`, batch size, DataLoader workers) — no remediation command on the node changes state.

### I.4: Inode exhaustion

Triage signal: `[P1] Inode exhaustion <N>% on /`. Small files (pip caches, HF caches, container image layers) can exhaust inodes before disk space.

Diagnose (read-only):

```bash
df -i /
# Top inode hoarders (by top-level directory):
sudo find / -xdev -type f 2>/dev/null | awk -F/ '{print $1"/"$2"/"$3}' | sort | uniq -c | sort -rn | head -20
```

### Suggested command — reclaim inodes (run this yourself)

**Preconditions:** inode exhaustion confirmed on `/` (`df -i /` near 100%); top hoarders identified via `find` above; no training job is currently writing to or reading from `~/.cache/huggingface` or `~/.cache/pip` (these caches may hold model weights that would need to be re-downloaded — check with the customer before deleting); `docker system prune --volumes` is acceptable (customer has confirmed no unattached named volume holds data they need).

**Command:**

```bash
# 1. pip cache — fast to rebuild; safe.
rm -rf ~/.cache/pip/*

# 2. Hugging Face cache — CONTAINS DOWNLOADED MODEL WEIGHTS. Delete only
#    if the customer accepts re-download cost (can be many GB and minutes).
#    Preferably: `du -sh ~/.cache/huggingface/*` and remove only the specific
#    entries they are not using.
du -sh ~/.cache/huggingface/* 2>/dev/null   # inspect first
# Then, targeted:
rm -rf ~/.cache/huggingface/<specific-model-dir>

# 3. journald (safe):
sudo journalctl --vacuum-size=200M

# 4. Docker prune — see blast-radius note in I.2. Only add --volumes if
#    the customer has confirmed no named volume holds training data.
docker system prune -a -f 2>/dev/null || true
```

**Blast radius:** `rm -rf ~/.cache/huggingface/*` can destroy large model weights requiring slow re-downloads (potentially interrupting training on adjacent jobs that share the cache). `docker system prune -a --volumes -f` without care can delete named volumes holding checkpoints. Always inspect (`du`) and delete targeted paths rather than using wildcards across the whole cache. Redirect caches to `/opt/sagemaker` or `/opt/dlami/nvme` (see I.2) as a long-term fix — separate filesystems with their own inode tables.

---

## J: Configuration

**Signals:** p5.48xlarge shows 96 vCPU instead of 192 (half the expected vCPU count).

### Suggested command — enable SMT via ThreadsPerCore (run this yourself)

**Preconditions:** instance-type confirmed as one where SMT is disabled by default and the workload wants both threads (e.g., p5.48xlarge 96→192); **every field for every instance group is derived from the current `describe-cluster` output** (`update-cluster` replaces the whole `InstanceGroups` list — any mistyped field silently changes cluster config); you understand that changing `ThreadsPerCore` rolls the instance group through replacement.

**Command:**

```bash
aws sagemaker update-cluster --cluster-name <C> --region <R> \
  --instance-groups '[{"InstanceGroupName":"<G>","InstanceType":"ml.p5.48xlarge",
    "InstanceCount":<N>,"ThreadsPerCore":2,
    "LifeCycleConfig":{"SourceS3Uri":"<URI>","OnCreate":"<SCRIPT>"},
    "ExecutionRole":"<ROLE>"}]'
```

**Blast radius:** any instance group omitted from the list is deleted; any field drift (instance type, count, lifecycle config, execution role) is applied as-is. Rolls nodes through replacement — which destroys root + secondary volumes per instance. Coordinate with the workload owner before running.

---

## K: Node Access via SSM

Direct SSH is not available on HyperPod — SSM is the primary node access method. The target format and connection procedure is identical for EKS and Slurm.

### Quick-start: connect in 4 commands

```bash
CLUSTER_NAME="my-hyperpod-cluster"
REGION="us-east-1"

# 1. Cluster ID is the ARN suffix — NOT the cluster name
CLUSTER_ID=$(aws sagemaker describe-cluster \
  --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'ClusterArn' --output text | cut -d/ -f2)

# 2. List nodes
aws sagemaker list-cluster-nodes --cluster-name "$CLUSTER_NAME" --region "$REGION" \
  --query 'ClusterNodeSummaries[*].[InstanceGroupName,InstanceId,InstanceStatus.Status]' --output table

# 3. Build the target
TARGET="sagemaker-cluster:${CLUSTER_ID}_<GROUP>-<INSTANCE_ID>"

# 4. Connect
aws ssm start-session --target "$TARGET" --region "$REGION"
```

### From a Slurm node name (e.g. ip-10-1-2-3)

`PrivateDnsHostname` is only returned by `describe-cluster-node` (not by `list-cluster-nodes`), so map via the two-step procedure in § H "Slurm node name → instance ID" — then build the SSM target with the resolved instance ID.

### Non-interactive command execution

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target "$TARGET" --region "$REGION" \
  'nvidia-smi && free -h && df -h'
```

### Essential on-node checks

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

### Prerequisites

```bash
session-manager-plugin --version
# If missing, install session-manager-plugin for your OS — see the
# AWS Systems Manager Session Manager documentation for current packages.
```

IAM:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "sagemaker:DescribeCluster",
      "sagemaker:DescribeClusterNode",
      "sagemaker:ListClusterNodes",
      "ssm:StartSession",
      "ssm:TerminateSession"
    ],
    "Resource": "*"
  }]
}
```

### SSM not working?

| Error                                   | Fix                                                                                    |
| --------------------------------------- | -------------------------------------------------------------------------------------- |
| `SessionManagerPlugin is not found`     | Install plugin; restart terminal                                                       |
| `Target is not connected`               | Use `sagemaker-cluster:` prefix (not bare `i-xxx`); verify region; verify node Running |
| `InvalidTarget` / `ValidationException` | Format must be exactly `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>`          |
| `Access denied`                         | Need `ssm:StartSession`, `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`     |
| Connection timeout                      | Check VPC endpoints (SSM, SSMMessages, EC2Messages); verify node Running               |

---

## L: Log Collection

**Delegate to `hyperpod-issue-report`** for comprehensive S3-stored diagnostics.

| Log               | Group                                 | Stream                                                 |
| ----------------- | ------------------------------------- | ------------------------------------------------------ |
| Lifecycle scripts | `/aws/sagemaker/Clusters/<name>/<id>` | `LifecycleConfig/<group>/<instance-id>`                |
| Health monitoring | `/aws/sagemaker/Clusters/<name>/<id>` | `SagemakerHealthMonitoringAgent/<group>/<instance-id>` |

---

## M: Container Runtime

**Signals:** CrashLoopBackOff, ImagePullBackOff, RunContainerError, container OOM kills (EKS clusters).

```bash
# Pod-level (from workstation)
kubectl describe pod <POD> -n <NAMESPACE>
kubectl logs <POD> -n <NAMESPACE> --previous       # logs from last crash

# On-node (via SSM)
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'sudo crictl ps -a | head -20 && sudo crictl logs --tail 30 <CONTAINER_ID> && journalctl -u containerd --no-pager -n 50'
```

| Symptom                   | Cause                               | Fix                                                               |
| ------------------------- | ----------------------------------- | ----------------------------------------------------------------- |
| `CrashLoopBackOff`        | Training process crashes repeatedly | `kubectl logs --previous`; likely OOM, missing lib, or NCCL error |
| `OOMKilled`               | Container exceeded memory limit     | Raise `resources.limits.memory` or reduce batch size              |
| `ImagePullBackOff`        | Image not found or auth failure     | Verify ECR URI; ECR access via VPC endpoint or internet           |
| `RunContainerError`       | Runtime can't start container       | `journalctl -u containerd`; may be disk full or GPU device issue  |
| `ContainerCreating` stuck | Volume mount or device plugin issue | Check EFA device plugin DaemonSet, volume mounts, CSI drivers     |

If containerd is crashing or OOM-ing, check disk on `/var/lib/containerd` (lives on the root 100 GB volume). Move container storage to `/opt/sagemaker` if needed.

---

## N: Kernel & System

**Signals:** Kernel panic, watchdog timeout, NMI, system hang, unexpected reboot not explained by HyperPod health monitoring.

```bash
bash skills/hyperpod-ssm/scripts/ssm-exec.sh --target <TARGET> --region <REGION> \
  'dmesg | grep -iE "panic|watchdog|hung_task|NMI|nvrm|Call Trace|BUG:" | tail -30 && journalctl -b -1 --no-pager -n 50 2>/dev/null || echo "No previous boot journal"'
```

| Signal                       | Likely cause                               | Action                                                                                     |
| ---------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `Kernel panic - not syncing` | Critical kernel error                      | Full `dmesg`; nvrm-related signatures suggest NVIDIA driver — reboot, replace if recurring |
| `watchdog: BUG: soft lockup` | CPU stuck in kernel code                   | Often NVLink/PCIe issues on GPU instances; reboot, replace if recurring                    |
| `hung_task_timeout`          | Process stuck in uninterruptible sleep     | Check disk I/O (`iostat`), NFS hangs, deadlocked GPU ops                                   |
| `NMI received`               | Hardware interrupt                         | Drain and replace (§ F)                                                                    |
| `mce: [Hardware Error]`      | Machine check exception                    | CPU/memory hardware failure — replace                                                      |
| Repeated unexpected reboots  | Health agent triggered reboot for HW fault | Check `SagemakerHealthMonitoringAgent` logs; expected if auto-repair is working            |

Previous boot logs:

```bash
journalctl -b -1 --no-pager | tail -100
last reboot | head -5
who -b
```

Recurring panics on the same node after reboot → hardware is likely bad; drain and replace (§ F).

---

## O: CNI / Pod Networking

VPC CNI plugin (`aws-node`) failures prevent pods from getting IP addresses — breaks all pod networking on affected nodes. Pattern seen in customer cases: HyperPod GPU node is `Ready` but `aws-node` is in `CrashLoopBackOff`, pod sandbox creation fails with `gRPC 127.0.0.1:50051 refused`.

### Diagnose

```bash
kubectl get ds -n kube-system aws-node                     # DESIRED vs READY mismatch
kubectl get pods -n kube-system -l k8s-app=aws-node -o wide  # CrashLoopBackOff / Error / high RESTARTS

# Pod logs
kubectl logs -n kube-system <aws-node-pod> -c aws-node --tail=100
kubectl logs -n kube-system <aws-node-pod> -c aws-eks-nodeagent --tail=50

# IPAMD-specific
kubectl logs -n kube-system <aws-node-pod> -c aws-node --tail=100 | grep -iE "ipamd|eni|ip pool|failed"

# Related DaemonSets
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

| Log pattern                                         | Root cause                                        | Fix                                                           |
| --------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------- |
| `gRPC connection refused 127.0.0.1:50051`           | IPAMD not running; aws-node init container failed | Restart aws-node pod; check node IAM role                     |
| `Failed to create ENI` / `ENI limit reached`        | Instance-type ENI limit reached                   | Reduce pod density or enable prefix delegation                |
| `UnauthorizedOperation: ec2:CreateNetworkInterface` | Node IAM role missing EC2 permissions             | Add `AmazonEKS_CNI_Policy` to the node role                   |
| `Failed to pull image` on aws-node                  | ECR unreachable in private VPC                    | Add `com.amazonaws.<region>.ecr.api` and `.dkr` VPC endpoints |
| `Insufficient IP addresses`                         | Subnet exhausted                                  | Larger subnet or enable prefix delegation                     |
| `ipamd: failed to increase IP pool`                 | Cannot allocate warm-pool IPs                     | Check ENI limits, subnet capacity, SG rules                   |

Diagnose (read-only):

```bash
aws ec2 describe-subnets --subnet-ids <SUBNET_ID> --region <REGION> \
  --query 'Subnets[0].{SubnetId:SubnetId,AvailableIPs:AvailableIpAddressCount,CIDR:CidrBlock}'
```

### Suggested command — restart a crashing aws-node pod (run this yourself)

**Preconditions:** root cause has been investigated and is plausibly transient (e.g., a stuck IPAMD process). For persistent crashes from IAM, VPC, or subnet exhaustion, fix the underlying issue first — restarting the pod will only loop. The customer accepts brief CNI unavailability on this node (a few seconds while the daemonset respawns).

**Command:**

```bash
kubectl delete pod -n kube-system <aws-node-pod-name>
```

**Blast radius:** the daemonset respawns the pod within seconds; during the gap, pods being scheduled or deleted on this node may briefly fail IP assignment. Already-running pods with assigned IPs are unaffected. Reversible by definition (replacement pod is identical).

### Suggested command — enable prefix delegation for higher pod density (run this yourself)

**Preconditions:** cluster admin has approved the operational change; you understand that prefix delegation changes ENI allocation behavior for every node managed by this daemonset; no existing workload relies on the previous per-IP allocation pattern.

**Command:**

```bash
kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
```

**Blast radius:** cluster-wide change to the VPC CNI configuration. New pods scheduled after the rollout get IPs from ENI prefixes rather than individual secondary IPs. Existing pods keep their IPs. Reverting requires `kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION-` (note the trailing `-`) and may leave ENIs in an unexpected state until nodes cycle.

The node role needs `AmazonEKS_CNI_Policy` or equivalent: `ec2:CreateNetworkInterface`, `DeleteNetworkInterface`, `DescribeNetworkInterfaces`, `AssignPrivateIpAddresses`, `UnassignPrivateIpAddresses`, `AttachNetworkInterface`, `DetachNetworkInterface`.

### Escalate

If `aws-node` keeps crashing after restart with no clear error, and IAM + VPC + subnet are all correct, escalate with:

```bash
kubectl describe ds -n kube-system aws-node
kubectl logs -n kube-system -l k8s-app=aws-node --tail=200
kubectl get nodes -o wide
```
