---
name: hyperpod-node-debugger
description: Diagnose and remediate per-node issues on a HyperPod cluster (EKS or Slurm) — a specific node is unhealthy, unresponsive, stuck, or needs replacing. Covers on-node EFA, GPU / accelerator hardware (XID, ECC, NVLink, row-remap, DCGM), Slurm node down/drained, disk and memory pressure, per-node lifecycle-script failures, SSM agent, container runtime, kernel panics, pod networking. Read-only. Not for cluster-wide provisioning (→ hyperpod-cluster-debugger), NCCL (→ hyperpod-nccl), or MFU (→ hyperpod-mfu-debugger).
metadata:
  version: "0.0.1"
---

# HyperPod Node Debugger

**Operating policy.** Run read-only diagnostics yourself. Never run a command that changes cluster, node, or workload state — present each one as a **Suggested command (run this yourself)** block and wait for the customer. Destructive order: **investigate → reboot → replace** (replace destroys root + secondary volumes; not supported on Slurm controller nodes). Never discard training state, logs, or caches on speculation.

**IaC note (always include with mutation commands).** When you suggest any command that changes cluster, VPC, SG, subnet, or EKS configuration (e.g. `authorize-security-group-*`, `modify-vpc-attribute`, `update-cluster`, `kubectl label/cordon/drain`, `create namespace`, `set env daemonset`), ask the customer first whether the cluster / VPC / SG is managed by Infrastructure-as-Code (CloudFormation, CDK, Terraform, Pulumi). If yes, tell them: "Apply this change in your IaC source first, then deploy through the pipeline — running the command directly will drift from your template and the next stack update may overwrite it." If they need to fix the issue immediately and the IaC change will follow, flag the drift explicitly so they remember to reconcile.

Read-only triage. `scripts/triage-cluster.sh` (and helpers `check-efa-sg.sh`, `check-node-reachability.sh`, `check-vpc-config.sh`) read state and print each issue as `[FAIL] ... → references/node-diagnostics-detail.md § <section>`. Catalog of customer-ticket patterns: [references/node-issue-catalog.md](references/node-issue-catalog.md).

---

## Workflow

1. Collect cluster name, region, suspect instance ID, exact error string from logs.
2. Run `scripts/triage-cluster.sh` (add `--node <INSTANCE-ID>` to focus one node).
3. For every `[FAIL]` / issue entry, `Read` the referenced section.
4. Present: what script detected (copy the line verbatim), root cause, exact command(s) with instance/SG IDs filled in, blast radius (e.g. "reboots i-xxx", "wipes volumes on replacement"). For any command that mutates cluster/VPC/SG/EKS state, ask whether the affected resource is IaC-managed and surface the drift warning from the operating-policy note above.
5. Wait for explicit customer approval. Destructive order: investigate → reboot → replace.
6. Re-run triage to confirm. Iterate if not cleared.

## Step 1: Triage

```bash
bash scripts/triage-cluster.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION>

# Focus on one node:
bash scripts/triage-cluster.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION> --node <INSTANCE_ID>
```

One pass collects: cluster status + NodeRecovery, events, per-node health (HyperPod + EKS labels, Slurm states), VPC/SG snapshot, CloudWatch availability, SSM readiness, on-node resource checks (disk, memory, /dev/shm, OOM, NVMe, time sync, SSM agent), Slurm node→instance mapping.

Tags: `[PASS]` passed · `[FAIL]` issue with a `→ references/...` pointer · `[WARN]` advisory · `[INFO]` informational. Priorities: **P0** blocks operation · **P1** degraded · **P2** informational.

## Step 2: Match signal → section

**Events (`list-cluster-events`) — provisioning-time:**

| Event                                                                       | Section                                                         |
| --------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `"EFA health checks did not run successfully"` (public-doc verbatim signal) | **[A: EFA/SG](#a-efa--security-group)**                         |
| Instance bootstrap or network-misconfiguration event                        | **[A](#a-efa--security-group)** + **[B: VPC](#b-vpc--routing)** |
| Lifecycle-script failure or timeout                                         | **[D: Lifecycle](#d-lifecycle-scripts)**                        |
| Insufficient-capacity or AZ-mismatch failure at creation                    | **[C: Capacity](#c-capacity--az)**                              |
| Hardware failure / `UnschedulablePendingReplacement`                        | **[F: Hardware](#f-hardware--auto-repair)**                     |

**EKS labels:**

| Label                                                 | Section                                                          |
| ----------------------------------------------------- | ---------------------------------------------------------------- |
| `node-health-status: UnschedulablePendingReplacement` | **[F](#f-hardware--auto-repair)**                                |
| `node-health-status: UnschedulablePendingReboot`      | **[F](#f-hardware--auto-repair)**                                |
| `deep-health-check-status: Failed`                    | **[G](#g-gpu--accelerator)** → **[F](#f-hardware--auto-repair)** |

**Symptoms:**

| Symptom                                                  | Section                                                         |
| -------------------------------------------------------- | --------------------------------------------------------------- |
| Training hangs at NCCL init / AllReduce                  | **[A](#a-efa--security-group)** → **[E](#e-software-versions)** |
| Slurm node `down` / `"Node unexpectedly rebooted"`       | **[H: Slurm](#h-slurm-node-management)**                        |
| Jobs stuck PENDING / COMPLETING                          | **[H](#h-slurm-node-management)**                               |
| Auto-repair not triggering                               | **[F](#f-hardware--auto-repair)**                               |
| GPU not visible / XID / ECC errors                       | **[G](#g-gpu--accelerator)**                                    |
| GPU row-remap pending/failed / silent NaNs / DCGM Fail   | **[G § G.1.a/b](#g-gpu--accelerator)**                          |
| Disk full / OOM / `"Cannot allocate memory"`             | **[I: Resources](#i-resource-exhaustion)**                      |
| Wrong vCPU count (e.g. 96 instead of 192 on p5.48xlarge) | **[J: Config](#j-configuration)**                               |
| Container CrashLoopBackOff / runtime crash               | **[M: Container Runtime](#m-container-runtime)**                |
| `aws-node` CrashLoopBackOff / gRPC 50051 refused         | **[O: CNI / Pod Networking](#o-cni--pod-networking)**           |
| Pods stuck Pending with no IP / CNI error                | **[O](#o-cni--pod-networking)**                                 |
| DNS resolution / `enableDnsSupport`                      | **[B § B.2](#b-vpc--routing)**                                  |
| Public subnet / IGW misconfigured                        | **[B § B.3](#b-vpc--routing)**                                  |
| Missing VPC endpoints (ECR / STS / FSx)                  | **[B § B.4](#b-vpc--routing)**                                  |
| EKS VPC / SG mismatch with HyperPod                      | **[B § B.5](#b-vpc--routing)**                                  |
| Kernel panic / watchdog / hung task                      | **[N: Kernel](#n-kernel--system)**                              |
| Need shell on a node                                     | **[K: SSM](#k-node-access-via-ssm)**                            |
| Collect logs for AWS Support                             | **[L: Log Collection](#l-log-collection)**                      |

---

## A: EFA / Security Group

Per the HyperPod prerequisites doc, the SG must allow all inbound and outbound to itself. `scripts/check-efa-sg.sh` validates self-ref rules on every cluster SG. On-node EFA check via `scripts/check-node-reachability.sh` over SSM. Full: [§ A](references/node-diagnostics-detail.md#a-efa--security-group).

## B: VPC / Routing

SG/subnet VPC mismatch, missing S3 Gateway endpoint, EKS auth mode, worker→controller routing, VPC DNS support, private-subnet + NAT / VPC endpoints, EKS↔HyperPod VPC alignment. `scripts/check-vpc-config.sh`. Full: [§ B](references/node-diagnostics-detail.md#b-vpc--routing).

## C: Capacity / AZ

Insufficient-capacity failure at creation, or no subnets in the AZ where capacity is available. Check AZ offerings via `describe-instance-type-offerings`, then change subnet AZ or use Flexible Training Plans / ODCR. Full: [§ C](references/node-diagnostics-detail.md#c-capacity--az).

## D: Lifecycle Scripts

Surfaced in cluster events + CloudWatch under `LifecycleConfig/<group>/<instance-id>`. Common: S3 connectivity, IAM gaps, CRLF line endings, infinite loops, parameter-name mismatch. Full: [§ D](references/node-diagnostics-detail.md#d-lifecycle-scripts).

## E: Software Versions

Delegate to `hyperpod-version-checker` to compare NVIDIA driver, CUDA, NCCL, EFA installer, OFI NCCL, PyTorch across nodes. Ensure job env has `FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1`, `NCCL_SOCKET_IFNAME=^lo,docker`. Full: [§ E](references/node-diagnostics-detail.md#e-software-versions).

## F: Hardware / Auto-Repair

Confirm `NodeRecovery=Automatic`, inspect the EKS health labels + `sagemaker.amazonaws.com/fault-details` annotation, and read the `SagemakerHealthMonitoringAgent/<group>/<instance>` CloudWatch stream. HMA runs passive background checks on GPU and Neuron state and **reboots** the node on count mismatch (per the HMA doc: "if there's a mismatch between the expected number of GPUs … and the count returned by `nvidia-smi`, then HMA reboots the node"; same for `neuron-ls`). Manual recovery order: reboot first, replace only if reboot fails; the preferred path is the batch APIs (`BatchReboot`/`BatchReplaceClusterNodes`). Full: [§ F](references/node-diagnostics-detail.md#f-hardware--auto-repair) · patterns: [node-issue-catalog.md](references/node-issue-catalog.md).

## G: GPU / Accelerator

**NVIDIA (p4d/p5/g5/g6):** `nvidia-smi` + `dmesg` over SSM for Xid, ECC, thermal throttling. Xid classification per NVIDIA's catalog: 13 Graphics Engine Exception (application-level), 31 GPU memory page fault (application, can be driver/HW), 63 GPU memory remapping event (HW/ECC), 71 CE4 Error (HW copy engine), 74 NVLink Error (HW), 79 GPU has fallen off the bus (PCIe bus), 109 Context Switch Timeout Error (HW). Any uncorrectable ECC → drain and replace. Row-remap state is the authoritative silent-degradation signal (§ G.1.a).

**Trainium / Inferentia (trn1/trn2/inf2):** Neuron SDK — `neuron-ls`, `neuron-top`, `neuron-monitor`. `nvidia-smi` does not apply.

GPU / accelerator failures flow into § F for reboot / replace. Full: [§ G](references/node-diagnostics-detail.md#g-gpuaccelerator).

## H: Slurm Node Management

Node down/unresponsive, unexpected reboots, stuck PENDING/COMPLETING jobs, Slurm-to-instance-ID translation. Primary access is SSM; diagnose `slurmd` first, fix the root cause, then start/resume the node per § H. Full: [§ H](references/node-diagnostics-detail.md#h-slurm-node-management).

## I: Resource Exhaustion

Disk full (HyperPod root volume defaults to 100 GB and is not intended to grow post-creation), OOM, `os.fork()` memory error, `/dev/shm` exhaustion, inode exhaustion. Fork-memory fix: `export FI_EFA_USE_HUGE_PAGE=0`. Redirect bulk data to `/opt/sagemaker` (secondary EBS) or `/opt/dlami/nvme` (instance store). Full: [§ I](references/node-diagnostics-detail.md#i-resource-exhaustion).

## J: Configuration

p5.48xlarge reports 96 vCPU instead of 192 → set `ThreadsPerCore=2` via `update-cluster`. Full: [§ J](references/node-diagnostics-detail.md#j-configuration).

## K: Node Access via SSM

No direct SSH on HyperPod. Target format `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>`. Failures: plugin missing, wrong prefix, IAM, VPC endpoints. Full: [§ K](references/node-diagnostics-detail.md#k-node-access-via-ssm).

## L: Log Collection

Delegate to `hyperpod-issue-report` for S3-stored bundles. Key CloudWatch streams: `LifecycleConfig/<group>/<instance-id>`, `SagemakerHealthMonitoringAgent/<group>/<instance-id>`. Full: [§ L](references/node-diagnostics-detail.md#l-log-collection).

## M: Container Runtime

CrashLoopBackOff, OOMKilled, ImagePullBackOff, RunContainerError on EKS. `kubectl describe pod` + on-node `crictl ps -a`, `journalctl -u containerd`. Full: [§ M](references/node-diagnostics-detail.md#m-container-runtime).

## N: Kernel & System

Kernel panic, watchdog timeout, soft lockup, unexpected reboots not explained by HyperPod health monitoring. `dmesg | grep -iE 'panic|watchdog|hung_task|NMI'` + `journalctl -b -1`. nvrm-related signatures point at NVIDIA driver crashes. Full: [§ N](references/node-diagnostics-detail.md#n-kernel--system).

## O: CNI / Pod Networking

VPC CNI (`aws-node`) failures, IPAMD errors, gRPC 127.0.0.1:50051 refused, pods stuck `Pending` with `FailedCreatePodSandBox`. Script auto-checks `aws-node`, `kube-proxy`, CoreDNS. Full: [§ O](references/node-diagnostics-detail.md#o-cni--pod-networking).

---

## Prerequisites

- `aws` CLI v2, recent enough to support the HyperPod cluster commands (`describe-cluster`, `list-cluster-nodes`, `batch-reboot-cluster-nodes`, `batch-replace-cluster-nodes`)
- `python3`, `bash` 4+ (associative arrays are required by the scripts)
- `kubectl` authenticated to the EKS cluster (K8s checks skipped if absent)
- `session-manager-plugin` for on-node hardware checks
- `unbuffer` (from the `expect` package) — optional; if missing, SSM on-node probes are skipped while the rest of the triage still runs. Install via `yum install expect` / `apt install expect`.

## Defaults

- **Region** — required: pass `--region` or set `$AWS_DEFAULT_REGION`.
- **Target scope** — all nodes; `--node <ID>` focuses one.
- **Event window** — up to 500 most recent events (5 × 100, paginated).
- **Node list cap** — up to 20,000 nodes (200 × 100); warns on cap.
- **SSM probes** — 180 s per node with retry-on-throttle.
- **Colors** — auto-disabled on non-TTY; `--no-color` to force off.

## Error handling

| Failure                                         | Script                                                 | Tell the customer                                                    |
| ----------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- |
| `aws sts get-caller-identity` fails             | Exit 1                                                 | "Fix AWS credentials and rerun."                                     |
| `describe-cluster` fails                        | Exit 1 after listing region's clusters                 | "Confirm cluster name and region."                                   |
| `sagemaker:*` / `ec2:*` / `logs:*` AccessDenied | Warn, add `Missing IAM permission for <API>`, continue | "Grant the listed IAM action and rerun."                             |
| `kubectl` absent or unauthenticated             | Skip K8s checks                                        | "Install/authenticate kubectl (see § K)."                            |
| `session-manager-plugin` absent                 | Skip on-node probes                                    | "Install session-manager-plugin (see § K)."                          |
| SSM `start-session` fails or times out (180s)   | Mark node unreachable with `→ § K` pointer             | "Rerun with `--node <ID>` to isolate; verify SSM agent on the node." |
| Cluster > 20,000 nodes                          | First 20,000 paginated; warn                           | "Use `--node` to target specific nodes."                             |

Exit codes: `0` triage complete · `1` cluster not found or fatal prerequisite missing.

## IAM permissions

Read-only diagnostic — covers `triage-cluster.sh`, `check-efa-sg.sh`, `check-vpc-config.sh`, and `check-node-reachability.sh`:

```json
{
  "Action": [
    "sagemaker:DescribeCluster",
    "sagemaker:DescribeClusterNode",
    "sagemaker:ListClusterNodes",
    "sagemaker:ListClusterEvents",
    "sagemaker:ListClusters",
    "eks:DescribeCluster",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeVpcs",
    "ec2:DescribeVpcAttribute",
    "ec2:DescribeVpcEndpoints",
    "ec2:DescribeRouteTables",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeInstances",
    "ec2:DescribeInstanceTypeOfferings",
    "ec2:DescribeInstanceTypes",
    "logs:DescribeLogGroups",
    "logs:DescribeLogStreams",
    "logs:FilterLogEvents",
    "ssm:StartSession",
    "ssm:TerminateSession",
    "service-quotas:GetServiceQuota"
  ]
}
```

`sts:GetCallerIdentity` is implicit — it requires no IAM action. SSM on HyperPod uses `start-session` against `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets — not `send-command` against bare instance IDs. For remediation commands, grant the matching write permission (e.g. `ec2:AuthorizeSecurityGroupIngress` / `Egress`, `ec2:RevokeSecurityGroupIngress` / `Egress`, `ec2:ModifyVpcAttribute`, `sagemaker:UpdateCluster`, `sagemaker:BatchRebootClusterNodes`, `sagemaker:BatchReplaceClusterNodes`). Not needed for the diagnostic itself.

## Skill delegation

| Need                                                   | Use                                                          |
| ------------------------------------------------------ | ------------------------------------------------------------ |
| Cluster creation / deployment failures                 | `hyperpod-cluster-debugger` (§ A / B / C / H + `--validate`) |
| Cluster-wide SSM outage                                | `hyperpod-cluster-debugger` § F                              |
| Single-node SSM failure                                | stay here — § K                                              |
| Cluster-wide EFA health-check failure at creation time | `hyperpod-cluster-debugger` § A                              |
| Single-node EFA failure post-provisioning              | stay here — § A                                              |
| NCCL AllReduce / collective-op timeouts (distributed)  | `hyperpod-nccl`                                              |
| Silent GPU NaNs on a specific node (row-remap / DCGM)  | stay here — § G.1 (even if discovered by NCCL)               |
| Post-deployment cluster-wide management                | `hyperpod-cluster-debugger`                                  |
| Shell / commands on nodes                              | `hyperpod-ssm`                                               |
| CUDA / NCCL / EFA version comparison                   | `hyperpod-version-checker`                                   |
| Diagnostic bundle for AWS Support                      | `hyperpod-issue-report`                                      |
| Training performance / MFU degradation                 | `hyperpod-mfu-debugger`                                      |

## Escalate to AWS Support

Escalate when:

1. SG rules correct and reachability passes but EFA still fails.
2. VPC correct but K8s bootstrap fails — check VPC flow logs for REJECT.
3. Hardware failure where replacement keeps failing (bad physical host).
4. Node replacement fails with an insufficient-capacity signal despite a valid ODCR.

### Before opening the case

```bash
# 1. Cluster identity + affected node status
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION>
aws sagemaker list-cluster-nodes --cluster-name <CLUSTER> --region <REGION> \
  --query "ClusterNodeSummaries[?InstanceId=='<INSTANCE_ID>']"

# 2. Triage bundle (scoped to the affected node where possible)
bash scripts/triage-cluster.sh --cluster <CLUSTER> --region <REGION> --node <INSTANCE_ID> > triage.txt

# 3. Per-node log/config bundle to S3 (delegates to hyperpod-issue-report)
#    See skills/hyperpod-issue-report/SKILL.md for the exact invocation.
```

### Include in the case

- Cluster name + ARN and AWS region
- Orchestrator (EKS or Slurm)
- Affected instance IDs / node names / instance-group names
- Timestamp window (UTC start / end) of the failure
- Exact error strings observed (copy verbatim from pod logs, CloudWatch, dmesg, events)
- XID numbers / ECC counts / DCGM output where hardware is implicated
- `triage.txt` from step 2 above
- S3 URI of the `hyperpod-issue-report` bundle from step 3

Patterns from real customer tickets: [node-issue-catalog.md](references/node-issue-catalog.md).
