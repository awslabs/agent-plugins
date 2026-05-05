---
name: hyperpod-node-debugger
description: Use for per-node issues on a SageMaker HyperPod cluster (EKS or Slurm) — a specific node is unhealthy, unresponsive, stuck, or needs replacing. Covers EFA on-node failures, GPU / accelerator hardware (XID, ECC, NVLink), Slurm node down/drained, disk full, OOM, /dev/shm, AMI drift, per-node lifecycle-script failures, SSM agent issues, NVMe not mounted, time sync, container runtime crashes, kernel panics. Read-only diagnostic — every detected issue points at a references/node-diagnostics-detail.md section; the skill opens the reference and guides the customer through the fix with explicit approval. Do NOT use for cluster-wide creation / provisioning failures or dangling-node reconciliation (→ hyperpod-cluster-debugger), NCCL or distributed-training-specific failures (→ hyperpod-nccl), MFU / performance degradation (→ hyperpod-mfu-debugger). Always run Step 1 triage first.
metadata:
  version: "1.0.0"
---

# HyperPod Node Debugger

Structured, read-only triage for HyperPod node issues.

**Clear separation of concerns:**

- `scripts/triage-cluster.sh` and its helpers are **read-only signal collectors**. They read cluster + node state and print each detected issue as an entry in the Issues Found list. Every issue message ends with a pointer of the form `→ references/node-diagnostics-detail.md § <section>`. The scripts never print remediation commands and never modify state.
- [references/node-diagnostics-detail.md](references/node-diagnostics-detail.md) contains the full remediation runbook for every issue the scripts can detect — root cause, preconditions, exact commands, verification.
- [references/node-issue-catalog.md](references/node-issue-catalog.md) is a catalog of patterns from real customer tickets, organized by symptom.
- This SKILL.md is the **playbook for Claude**: run the scripts, read each finding's pointer, open the referenced section, walk the customer through the fix.

---

## Workflow (authoritative)

1. **Collect inputs** — cluster name, region, specific instance ID if one node is suspect, exact error message from the customer's logs.
2. **Run `scripts/triage-cluster.sh`** — it covers cluster identity, events, per-node health, VPC/SG, SSM reachability, and on-node resource checks (disk, memory, /dev/shm, OOM, NVMe, time sync, SSM agent). Route specialized checks to `scripts/check-efa-sg.sh`, `scripts/check-node-reachability.sh`, `scripts/check-vpc-config.sh` when relevant.
3. **Read the script output top-to-bottom.** Ignore `[PASS]` lines; for every `[FAIL]` / issue entry, note the trailing `→ references/node-diagnostics-detail.md § <section>` pointer.
4. **Open each referenced section.** Use the `Read` tool on the exact file path. Do not paraphrase remediation from memory.
5. **Present the remediation to the customer.** For each finding, state:
   - What the script detected (copy the failure line verbatim).
   - Root cause (from the referenced section).
   - The exact command(s) to run, with concrete values (instance IDs, SG IDs) interpolated from the script output.
   - Blast radius (e.g. "reboots node i-xxx", "wipes instance volumes on replacement").
6. **Wait for explicit customer approval** before running any state-changing command. Destructive order: investigate → reboot → replace (reboot first, replace only if reboot fails).
7. **Re-run triage** after remediation to confirm the failure is cleared. If not, iterate.

## Step 1: Full cluster triage (always start here)

```bash
# Diagnose (read-only — no changes):
bash scripts/triage-cluster.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION>

# For a specific node:
bash scripts/triage-cluster.sh --cluster <CLUSTER> --region <REGION> --node <INSTANCE_ID>
```

One pass collects: cluster status + NodeRecovery, cluster events, per-node health (HyperPod + EKS labels, Slurm states), VPC/SG snapshot, CloudWatch log availability, SSM readiness, on-node resource checks (disk, memory, /dev/shm, OOM, NVMe, time sync, SSM agent), and Slurm node-to-instance-ID mapping. Issues are categorized:

- **P0** — Fix immediately (blocks operation)
- **P1** — Fix soon (degraded or at-risk)
- **P2** — Informational (review when convenient)

### Output tags

| Tag      | Meaning                                                                     |
| -------- | --------------------------------------------------------------------------- |
| `[PASS]` | Check passed                                                                |
| `[FAIL]` | Problem found — counted in the issue list with a `→ references/...` pointer |
| `[WARN]` | Advisory                                                                    |
| `[INFO]` | Informational                                                               |

The script never prints remediation commands. Each `[FAIL]` / issue entry ends with a pointer of the form `→ references/node-diagnostics-detail.md § <section>`. Open the referenced section with `Read` to find the remediation runbook.

## Step 2: Match signal → section

**From `list-cluster-events` (provisioning-time failures):**

| Event message                                                  | Section                                                         |
| -------------------------------------------------------------- | --------------------------------------------------------------- |
| `"EFA health checks did not run successfully"`                 | **[A: EFA/SG](#a-efa--security-group)**                         |
| `"Instance bootstrap failed…network misconfiguration"`         | **[A](#a-efa--security-group)** + **[B: VPC](#b-vpc--routing)** |
| `"Lifecycle scripts did not run successfully"` / `"timed out"` | **[D: Lifecycle](#d-lifecycle-scripts)**                        |
| `"Insufficient capacity"` / `"No subnets in the capacity AZ"`  | **[C: Capacity](#c-capacity--az)**                              |
| `"Instance likely experienced a hardware failure"`             | **[F: Hardware](#f-hardware--auto-repair)**                     |
| `"Failed to provision EC2 Instance"`                           | **[C](#c-capacity--az)** or **[F](#f-hardware--auto-repair)**   |

**From EKS node labels** (`kubectl get nodes --show-labels`):

| Label                                                 | Go to                                                                 |
| ----------------------------------------------------- | --------------------------------------------------------------------- |
| `node-health-status: UnschedulablePendingReplacement` | **[F: Hardware](#f-hardware--auto-repair)**                           |
| `node-health-status: UnschedulablePendingReboot`      | **[F: Hardware](#f-hardware--auto-repair)**                           |
| `deep-health-check-status: Failed`                    | **[G: GPU](#g-gpu--accelerator)** → **[F](#f-hardware--auto-repair)** |
| `fault-type: NetworkFaultType`                        | **[A: EFA/SG](#a-efa--security-group)**                               |

**From symptoms:**

| Symptom                                                | Section                                                                   |
| ------------------------------------------------------ | ------------------------------------------------------------------------- |
| Training hangs at NCCL init / AllReduce                | **[A](#a-efa--security-group)** → **[E: Versions](#e-software-versions)** |
| Slurm node `down` / `"Node unexpectedly rebooted"`     | **[H: Slurm](#h-slurm-node-management)**                                  |
| Jobs stuck PENDING / COMPLETING                        | **[H: Slurm](#h-slurm-node-management)**                                  |
| Auto-repair not triggering                             | **[F: Hardware](#f-hardware--auto-repair)**                               |
| GPU not visible / XID errors / ECC errors              | **[G: GPU](#g-gpu--accelerator)**                                         |
| GPU row-remap pending/failed / silent NaNs / DCGM Fail | **[G: GPU](#g-gpu--accelerator)** (see § G.1.a/b in references)           |
| Disk full / OOM / `"Cannot allocate memory"`           | **[I: Resources](#i-resource-exhaustion)**                                |
| Wrong vCPU count (96 instead of 192)                   | **[J: Config](#j-configuration)**                                         |
| Container CrashLoopBackOff / runtime crash             | **[M: Container Runtime](#m-container-runtime)**                          |
| aws-node CrashLoopBackOff / gRPC 50051 refused         | **[O: CNI / Pod Networking](#o-cni--pod-networking)**                     |
| Pods stuck Pending with no IP / CNI error              | **[O: CNI / Pod Networking](#o-cni--pod-networking)**                     |
| DNS resolution failing / `enableDnsSupport`            | **[B: VPC / Routing](#b-vpc--routing)** (§ B.2)                           |
| Public subnet misconfigured / IGW on private subnet    | **[B: VPC / Routing](#b-vpc--routing)** (§ B.3)                           |
| Missing VPC endpoints in air-gapped VPC (ECR/STS/FSx)  | **[B: VPC / Routing](#b-vpc--routing)** (§ B.4)                           |
| EKS VPC or SG not matching HyperPod cluster            | **[B: VPC / Routing](#b-vpc--routing)** (§ B.5)                           |
| Kernel panic / watchdog timeout / system hang          | **[N: Kernel & System](#n-kernel--system)**                               |
| Need shell on a node                                   | **[K: SSM Access](#k-node-access-via-ssm)**                               |
| Need logs for AWS Support                              | **[L: Log Collection](#l-log-collection)**                                |

---

## A: EFA / Security Group

EFA failures are the most common provisioning blocker. Run `scripts/check-efa-sg.sh` to auto-discover SGs/subnets and validate required self-referencing rules. For on-node EFA checks, upload and run `scripts/check-node-reachability.sh` via SSM.
Full procedure: [references/node-diagnostics-detail.md § A](references/node-diagnostics-detail.md#a-efa--security-group).

## B: VPC / Routing

Covers SG/subnet VPC mismatch, missing S3 Gateway endpoints, EKS auth-mode issues, worker→controller routing. Run `scripts/check-vpc-config.sh`.
Full procedure: [references/node-diagnostics-detail.md § B](references/node-diagnostics-detail.md#b-vpc--routing).

## C: Capacity / AZ

Triggered by `Insufficient capacity` or `No subnets in the capacity AZ`. Check AZ availability, then add a subnet in the correct AZ or use Flexible Training Plans / ODCR.
Full procedure: [references/node-diagnostics-detail.md § C](references/node-diagnostics-detail.md#c-capacity--az).

## D: Lifecycle Scripts

Lifecycle failures show in cluster events and CloudWatch under `LifecycleConfig/<group>/<instance-id>`. Common causes: S3 connectivity, IAM gaps, CRLF line endings, infinite loops, parameter name mismatches.
Full procedure: [references/node-diagnostics-detail.md § D](references/node-diagnostics-detail.md#d-lifecycle-scripts).

## E: Software Versions

Delegate to `hyperpod-version-checker` skill to compare NVIDIA driver, CUDA, NCCL, EFA installer, PyTorch across nodes. Ensure job env includes `FI_PROVIDER=efa`, `FI_EFA_USE_DEVICE_RDMA=1`, `NCCL_SOCKET_IFNAME=^lo,docker`.
Full procedure: [references/node-diagnostics-detail.md § E](references/node-diagnostics-detail.md#e-software-versions).

## F: Hardware / Auto-Repair

Check `NodeRecovery` is enabled, inspect EKS health labels and repair events. For Slurm, auto-repair triggers only when the node reason is exactly `Action:Reboot` or `Action:Replace`. Manual recovery: try `batch-reboot-cluster-nodes` first, then `batch-replace-cluster-nodes` only if reboot does not clear the fault.
Full procedure: [references/node-diagnostics-detail.md § F](references/node-diagnostics-detail.md#f-hardware--auto-repair) and [references/node-issue-catalog.md](references/node-issue-catalog.md).

## G: GPU / Accelerator

**NVIDIA GPUs (p4d/p5/g5/g6):** Run `nvidia-smi` queries and `dmesg` via SSM to check XID errors, ECC counts, thermal throttling. Thresholds: CE < 100/day normal; any UCE means drain and replace.

**AWS Trainium / Inferentia (trn1/trn2/inf2):** Use Neuron SDK — `neuron-ls`, `neuron-top`, `neuron-monitor`. Common issues: Neuron driver not loaded, `neuron-rtd` not running, NeuronCore count mismatch, OOM on NeuronDevice memory.

GPU/accelerator failure flows into Section F for node replacement.
Full procedure: [references/node-diagnostics-detail.md § G](references/node-diagnostics-detail.md#g-gpuaccelerator).

## H: Slurm Node Management

Covers node down/unresponsive, unexpected reboots, stuck jobs (PENDING/COMPLETING), and Slurm-to-instance-ID translation. Primary access is via SSM; check `slurmd`, restart if needed, then `scontrol update state=resume` **only after** confirming the underlying cause is resolved.
Full procedure: [references/node-diagnostics-detail.md § H](references/node-diagnostics-detail.md#h-slurm-node-management).

## I: Resource Exhaustion

Covers disk full (root volume fixed at 100 GB), OOM, `os.fork()` memory errors, `/dev/shm` exhaustion. Key fix for fork memory errors: `export FI_EFA_USE_HUGE_PAGE=0`. Redirect large data to `/opt/sagemaker` (EBS) or `/opt/dlami/nvme` (instance store).
Full procedure: [references/node-diagnostics-detail.md § I](references/node-diagnostics-detail.md#i-resource-exhaustion).

## J: Configuration

`p5.48xlarge` showing 96 vCPU instead of 192: caused by the console defaulting `ThreadsPerCore=1`. Fix with `update-cluster` setting `ThreadsPerCore=2`. CFN `UpdateCluster` must always include `ThreadsPerCore`.
Full procedure: [references/node-diagnostics-detail.md § J](references/node-diagnostics-detail.md#j-configuration).

## K: Node Access via SSM

Direct SSH is not available on HyperPod. Use the `hyperpod-ssm` skill. Target format: `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>`. If SSM fails, check for Session Manager plugin, the target prefix, IAM permissions, and VPC endpoints.
Full procedure: [references/node-diagnostics-detail.md § K](references/node-diagnostics-detail.md#k-node-access-via-ssm).

## L: Log Collection

Delegate to `hyperpod-issue-report` for comprehensive S3-stored diagnostics. Key CloudWatch groups: `LifecycleConfig/<group>/<instance-id>`, `SagemakerHealthMonitoringAgent/<group>/<instance-id>`.
Full procedure: [references/node-diagnostics-detail.md § L](references/node-diagnostics-detail.md#l-log-collection).

## M: Container Runtime

CrashLoopBackOff, container OOM kills, image pull failures, runtime crashes on EKS-orchestrated clusters. Check `kubectl describe pod` for `OOMKilled`, `ImagePullBackOff`, `RunContainerError`. On-node: `crictl ps -a`, `journalctl -u containerd`, `dmesg | grep -i oom`.
Full procedure: [references/node-diagnostics-detail.md § M](references/node-diagnostics-detail.md#m-container-runtime).

## N: Kernel & System

Kernel panics, watchdog timeouts, system hangs, unexpected reboots not explained by HyperPod health monitoring. Check `dmesg | grep -iE 'panic|watchdog|hung_task|NMI'` and `journalctl -b -1`. Watchdog timeouts often indicate NVLink/PCIe hangs on GPU instances. Panics with `RIP: nvrm` point to NVIDIA driver crashes — reboot, and if recurring, replace the node.
Full procedure: [references/node-diagnostics-detail.md § N](references/node-diagnostics-detail.md#n-kernel--system).

## O: CNI / Pod Networking

VPC CNI (`aws-node` DaemonSet) failures, IPAM errors, and kube-system networking pod crashes on EKS. When `aws-node` crashes, pods cannot get IPs and networking breaks. Typical symptoms: `aws-node` CrashLoopBackOff, `gRPC connection refused 127.0.0.1:50051`, pods stuck `Pending` with `FailedCreatePodSandBox`. The triage script auto-checks `aws-node`, `kube-proxy`, and CoreDNS.
Full procedure: [references/node-diagnostics-detail.md § O](references/node-diagnostics-detail.md#o-cni--pod-networking).

---

## Read-only guarantee & remediation principle

The scripts in this skill never mutate cluster state and never emit remediation commands. Each issue detected points at a `references/<file>.md § <section>`; open that section with `Read` to find the root cause, exact commands, verification, and blast radius. For destructive actions, the referenced runbook explicitly orders the steps (investigate → reboot first → replace only if reboot fails). Never execute a destructive command without the customer's explicit approval in the session.

## Prerequisites

Required on the machine running the skill:

- `aws` CLI v2.13+ — authenticated to the AWS account that owns the HyperPod cluster.
- `jq` — used for JSON parsing in the check-efa-sg/check-vpc-config helper scripts.
- `python3` — used for JSON manipulation, SSM payload building, and cluster-events pagination.
- `bash` 4.2+.

Required for EKS clusters:

- `kubectl` — authenticated to the EKS cluster. If absent or not authenticated, K8s-facing checks are skipped and the script reports it.

Required for on-node hardware/resource checks:

- `session-manager-plugin` (AWS Systems Manager) — required for SSM into compute nodes.

See [references/node-diagnostics-detail.md § K (Node Access via SSM)](references/node-diagnostics-detail.md) for setup.

## Defaults

- **Region**: reads `$AWS_DEFAULT_REGION`; if unset, `us-east-1` is used. Explicitly pass `--region <R>` for clarity.
- **Target node scope**: all nodes. Pass `--node <INSTANCE-ID>` to focus the on-node probe on one node.
- **Event pagination**: up to 5 pages × 100 events = 500 most recent cluster events.
- **Node list pagination**: up to 50 pages × 100 nodes = 5000 nodes (cap prevents runaway on misconfigured clusters).
- **SSM command timeout**: ~90 seconds per on-node probe with exponential backoff polling.
- **Output colors**: ANSI colors on; pass `--no-color` or pipe to a non-TTY to disable.
- **Read-only**: the scripts NEVER modify cluster state and NEVER print remediation commands.

## Error Handling

| Failure mode                                               | Script behavior                                                                | What to tell the customer                                                     |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `aws sts get-caller-identity` fails                        | Exit 1                                                                         | "Fix AWS credentials and rerun."                                              |
| `aws sagemaker describe-cluster` fails                     | Exit 1 after listing clusters in the region                                    | "Confirm cluster name and region."                                            |
| Any `sagemaker:*` / `ec2:*` / `logs:*` AccessDenied        | Warn, add issue `Missing IAM permission for <API>`, continue with partial data | "Grant the listed IAM action and rerun."                                      |
| `kubectl` absent / not authenticated                       | Skip K8s checks, note in summary                                               | "Install/authenticate kubectl (section 4 in node-diagnostics-detail.md § K)." |
| `session-manager-plugin` absent                            | Skip on-node probes, warn                                                      | "Install session-manager-plugin; section K in references."                    |
| SSM `send-command` returns non-terminal or times out (90s) | Return partial output, mark node unreachable with a `→ § K` pointer            | "Rerun with `--node <ID>` to isolate; verify SSM agent on the node."          |
| Cluster has > 5000 nodes                                   | First 5000 paginated; warn about the cap                                       | "Use `--node` to target specific nodes."                                      |

Exit codes: `0` = triage complete (issues may still exist — check output); `1` = cluster not found or fatal prerequisite missing.

## IAM permissions required

Read-only diagnostic:

```json
{
  "Action": [
    "sagemaker:DescribeCluster",
    "sagemaker:DescribeClusterNode",
    "sagemaker:ListClusterNodes",
    "sagemaker:ListClusterEvents",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeVpcs",
    "ec2:DescribeInstances",
    "logs:DescribeLogStreams",
    "logs:FilterLogEvents",
    "ssm:StartSession",
    "ssm:TerminateSession"
  ]
}
```

> SSM on HyperPod uses `start-session` against `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets, not `send-command` against plain instance IDs (HyperPod's managed instance fleet does not expose bare instance IDs to customer `SendCommand` calls). Grant `ssm:StartSession` and `ssm:TerminateSession` — not `ssm:SendCommand` / `ssm:GetCommandInvocation`.

For each remediation the operator may run, the matching write permission is required (for example `ec2:AuthorizeSecurityGroupIngress` / `Egress`, `sagemaker:BatchRebootClusterNodes`, `sagemaker:BatchReplaceClusterNodes`, `eks:DescribeCluster`). These are not needed for the diagnostic itself.

## Skill delegation

| Need                                                   | Use                                                                |
| ------------------------------------------------------ | ------------------------------------------------------------------ |
| Cluster creation / deployment failures                 | `hyperpod-cluster-debugger` skill (§ A / B / C / H + `--validate`) |
| Cluster-wide SSM outage (all nodes unreachable)        | `hyperpod-cluster-debugger` § F                                    |
| SSM failure on a single node                           | stay here — § K                                                    |
| Cluster-wide EFA health-check failure at creation time | `hyperpod-cluster-debugger` § A                                    |
| Single-node EFA failure post-provisioning              | stay here — § A                                                    |
| NCCL AllReduce / collective-op timeouts (distributed)  | `hyperpod-nccl` skill                                              |
| Silent GPU NaNs on a specific node (row-remap / DCGM)  | stay here — § G.1 (even if discovered by NCCL)                     |
| Post-deployment cluster-wide management                | `hyperpod-cluster-debugger` skill                                  |
| Shell access / run commands on nodes                   | `hyperpod-ssm` skill                                               |
| CUDA / NCCL / EFA version comparison                   | `hyperpod-version-checker` skill                                   |
| Diagnostic bundle for AWS Support                      | `hyperpod-issue-report` skill                                      |
| Training performance / MFU degradation                 | `hyperpod-mfu-debugger` skill                                      |
| All-in-one first triage                                | `scripts/triage-cluster.sh`                                        |
| EFA SG rules (cluster-centric)                         | `scripts/check-efa-sg.sh`                                          |
| On-node EFA reachability                               | `scripts/check-node-reachability.sh` (via SSM)                     |
| VPC / subnet / EKS config                              | `scripts/check-vpc-config.sh`                                      |

## Escalate to AWS Support when

1. All SG rules correct + reachability passes but EFA checks still fail.
2. VPC correct but K8s bootstrap keeps failing — check VPC flow logs for REJECT entries.
3. Hardware failure + replacement keeps failing (bad physical host).
4. Node replacement fails with `Insufficient capacity` despite valid ODCR.

Collect diagnostics with `scripts/triage-cluster.sh`, `scripts/check-efa-sg.sh`, and `hyperpod-issue-report` before escalating. See [references/node-issue-catalog.md](references/node-issue-catalog.md) for detailed issue patterns from real customer tickets.
