---
name: hyperpod-cluster-debugger
description: Use for cluster-wide SageMaker HyperPod issues (EKS or Slurm) across the full cluster lifecycle — pre-create validation and creation/deployment failures (CloudFormation CREATE_FAILED / ROLLBACK_COMPLETE / "Embedded stack failed", stuck in Creating/Updating/Failed, "EFA health checks did not run successfully", "Lifecycle scripts did not run" / timed out, "Insufficient capacity" / "No subnets in the capacity AZ", "Instance bootstrap failed...network misconfiguration", service-linked role missing, S3 lifecycle / CRLF / on_create.sh); plus post-deployment ops (EKS access entries / kubectl auth, EKS add-ons, AMI / UpdateClusterSoftware rollback, ClusterMaintenanceRollbackFailed, dangling nodes, autoscaler/Karpenter conflicts, service quotas, permission-boundary denials, Slurm controller). Read-only. `--validate` pre-flight checks SGs / subnets / IAM / VPC endpoints / S3 lifecycle / per-AZ capacity. Not for per-node issues (hyperpod-node-debugger), NCCL (hyperpod-nccl), or MFU (hyperpod-mfu-debugger).
metadata:
  version: "1.0.0"
---

# HyperPod Cluster Debugger

Read-only diagnostic for cluster-level HyperPod issues across the full cluster lifecycle: **pre-create validation**, **deployment/creation failures**, and **post-deployment operations** (cluster-wide health, AMI upgrades, dangling nodes, autoscaler conflicts, Slurm controller, node replacement). Supports **EKS** and **Slurm**.

**Clear separation of concerns:**

- `scripts/diagnose-cluster.sh` is a **read-only signal collector**. It reads cluster state via AWS APIs and (for Slurm controller health) SSM, then prints each detected issue as a `[FAIL]` line. Every `[FAIL]` line ends with a pointer of the form `→ references/cluster-diagnostics-detail.md § <section>` or `→ references/cluster-operations.md § <N>`. The script never prints remediation commands and never modifies cluster state.
- [references/cluster-diagnostics-detail.md](references/cluster-diagnostics-detail.md) contains the full remediation runbook per section (A–L).
- [references/cluster-operations.md](references/cluster-operations.md) contains operational deep-dives (EFA SG, capacity, lifecycle, EKS access, SSM, node replacement, Slurm operations).
- [references/cloudformation-errors.md](references/cloudformation-errors.md) is the full CloudFormation resource-by-resource error catalog (nested-stack navigation, `AWS::SageMaker::Cluster`/`AWS::IAM::Role`/`AWS::FSx::FileSystem`/`Custom::Resource`/etc.) — open this when § H points you into deep CFN debugging.
- [references/capacity-planning.md](references/capacity-planning.md) is the in-depth capacity strategy guide (on-demand vs. Flexible Training Plans vs. ODCR, AZ/AZ-ID selection, subnet IP sizing per instance type, service quotas) — open this when § B or pre-create validation flags capacity/subnet sizing.
- [references/lifecycle-scripts.md](references/lifecycle-scripts.md) is the in-depth lifecycle-script reference (S3 layout for Slurm/EKS, execution order, `config.py` toggles, on-node debug under `/var/log/provision/`) — open this when § C points you at a specific lifecycle failure.
- This SKILL.md is the **playbook for Claude**: run the script, read each finding's pointer, open the referenced section, walk the customer through the fix with explicit approval.

**Always run Step 1 first** — it collects all cluster signals and produces a prioritized issue list with reference pointers.

---

## Workflow (authoritative)

1. **Collect inputs** — HyperPod cluster name (not EKS name), region, exact error message from console/CLI/CloudFormation.
2. **Run `scripts/diagnose-cluster.sh`** (or `--validate` for pre-create checks).
3. **Read the script output top-to-bottom.** For every `[FAIL]` line, note the trailing `→ references/<file>.md § <section>` pointer.
4. **Open each referenced section.** Use the `Read` tool on the exact file path.
5. **Present the remediation to the customer** with the finding, root cause, exact command(s), and blast radius. Cluster-level remediations (SG changes, AMI upgrade, kubeconfig overwrite, node replacement, service-linked role creation) have wider blast radius than node-level — describe the impact clearly.
6. **Wait for explicit customer approval** before running any state-changing command.
7. **Re-run the diagnostic** after remediation to confirm.

---

## Step 1: Collect information & run diagnostics

Ask the customer for:

- **HyperPod cluster name** (not the EKS cluster name):

  ```bash
  aws sagemaker list-clusters --region <REGION> --query 'ClusterSummaries[*].ClusterName'
  ```

- **AWS region** — e.g. `us-east-1`, `us-west-2`
- **Error message** — the exact error from console, CLI, or CloudFormation

Then run the diagnostic script:

```bash
# Diagnose an existing cluster (read-only; prints findings with references/... pointers):
bash scripts/diagnose-cluster.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION>

# Pre-flight validation (no cluster needed — validates SGs, subnets, IAM, VPC endpoints,
# optionally S3 lifecycle scripts and per-AZ instance-type capacity):
bash scripts/diagnose-cluster.sh --validate --region <REGION> \
  --sg-ids <sg-1,sg-2> --subnet-ids <sub-1,sub-2> [--iam-role <role-arn>] \
  [--s3-uri s3://<BUCKET>/path/] [--instance-type ml.p5.48xlarge]
```

The script collects in one pass: cluster status, orchestrator type, provisioning mode, instance-group health, cluster events, VPC/SG configuration, EKS access + add-ons + aws-auth, SSM readiness, CloudWatch log availability, Slurm controller health (when applicable), dangling/orphaned node reconciliation. Issues are categorized:

- **P0** — Fix immediately (blocks cluster operation)
- **P1** — Fix soon (degraded or at-risk)
- **P2** — Informational (review when convenient)

### Output tags

| Tag      | Meaning                                                                          |
| -------- | -------------------------------------------------------------------------------- |
| `[PASS]` | Check passed                                                                     |
| `[FAIL]` | Problem found — counted in `CRITICAL_FAILURES` with a `→ references/...` pointer |
| `[WARN]` | Advisory                                                                         |
| `[INFO]` | Informational                                                                    |

The script never prints remediation commands. Each `[FAIL]` entry ends with a pointer of the form `→ references/cluster-diagnostics-detail.md § <section>` (or `→ references/cluster-operations.md § <N>`). Open the referenced section with `Read` to find the remediation runbook.

---

## Step 2: Match signal → section

**From `list-cluster-events` / error messages:**

| Event / Error Message                                                               | Section                                                        |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `"EFA health checks did not run successfully"`                                      | **[A: EFA Health Checks](#a-efa-health-checks)**               |
| `"Insufficient capacity"` / `"No subnets in the capacity AZ"`                       | **[B: Capacity & AZ](#b-capacity--az)**                        |
| `"Lifecycle scripts did not run successfully"` / `"timed out"`                      | **[C: Lifecycle Scripts](#c-lifecycle-scripts)**               |
| `"the server has asked for the client to provide credentials"` / kubectl auth error | **[D: EKS Access](#d-eks-access--kubectl)**                    |
| Cluster InService but no instances visible / nodes not showing                      | **[E: Cluster Provisioning](#e-cluster-provisioning)**         |
| `"Target is not connected"` / SSM errors                                            | **[F: SSM Connectivity](#f-ssm-connectivity)**                 |
| Node replacement not happening / `batch-replace` not working                        | **[G: Node Replacement](#g-node-replacement)**                 |
| `"Embedded stack failed"` / CloudFormation error                                    | **[H: CloudFormation Errors](#h-cloudformation-errors)**       |
| `"ENI limit exceeded"` / `"vCPU limit"` / service quota error                       | **[B: Capacity & AZ](#b-capacity--az)**                        |
| `"UpdateClusterSoftware"` failed / AMI upgrade error                                | **[J: AMI & Cluster Updates](#j-ami--cluster-updates)**        |
| Cluster stuck in `ClusterMaintenanceRollbackFailed`                                 | **[J: AMI & Cluster Updates](#j-ami--cluster-updates)**        |
| Dangling nodes on EKS after scale-up rollback                                       | **[K: Dangling Nodes & Cleanup](#k-dangling-nodes--cleanup)**  |
| Cluster Autoscaler stops working after HyperPod attached                            | **[L: Autoscaler Compatibility](#l-autoscaler-compatibility)** |

**From symptoms:**

| Symptom                                                     | Section                                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Cluster creation failed                                     | Run script → follow section pointer                                                              |
| Cluster stuck in Creating/Updating/Deleting > 1 hour        | **[E: Cluster Provisioning](#e-cluster-provisioning)**                                           |
| Cluster stuck in RollbackFailed / MaintenanceFailed         | **[J: AMI & Cluster Updates](#j-ami--cluster-updates)**                                          |
| AMI upgrade silently fails and rolls back                   | **[J: AMI & Cluster Updates](#j-ami--cluster-updates)**                                          |
| Cluster InService, `kubectl get nodes` returns nothing      | **[D](#d-eks-access--kubectl)** then **[E](#e-cluster-provisioning)**                            |
| Auto-repair enabled but nodes not being replaced            | **[G: Node Replacement](#g-node-replacement)**                                                   |
| Ran `batch-replace-cluster-nodes` but nothing happened      | **[G: Node Replacement](#g-node-replacement)**                                                   |
| Can't SSM into nodes                                        | **[F: SSM Connectivity](#f-ssm-connectivity)**                                                   |
| Ghost/dangling nodes visible in EKS after rollback          | **[K: Dangling Nodes & Cleanup](#k-dangling-nodes--cleanup)**                                    |
| Cluster Autoscaler broken after HyperPod attachment         | **[L: Autoscaler Compatibility](#l-autoscaler-compatibility)**                                   |
| Node stuck in Failed after reboot                           | **[G: Node Replacement](#g-node-replacement)**                                                   |
| Topology labels missing on new nodes                        | **[K: Dangling Nodes & Cleanup](#k-dangling-nodes--cleanup)**                                    |
| Need to find instance ID from Slurm node name               | **[I: Utilities](#i-utilities)**                                                                 |
| Slow I/O, data-loading bottleneck, FSx throughput saturated | [references/cluster-operations.md § 10 Filesystem Performance](references/cluster-operations.md) |

---

## A: EFA Health Checks

Security group missing self-referencing rules for inter-node EFA — the #1 cluster creation failure. Diagnose with the cluster script or `describe-security-groups`, then add inbound/outbound self-referencing rules plus outbound internet access to every SG used by the cluster.
Full procedure: [references/cluster-diagnostics-detail.md § A](references/cluster-diagnostics-detail.md#a-efa-health-checks).

## B: Capacity & AZ

Instance type unavailable in the requested Availability Zone. Check AZ offerings with `describe-instance-type-offerings`, then try a different AZ, use Flexible Training Plans, or request reserved capacity.
Full procedure: [references/cluster-diagnostics-detail.md § B](references/cluster-diagnostics-detail.md#b-capacity--az).

## C: Lifecycle Scripts

Lifecycle scripts failed or timed out during provisioning. Check CloudWatch logs under `/aws/sagemaker/Clusters/<name>/<id>` for the specific error — common causes: missing S3 VPC endpoints, IAM permission gaps, Windows line endings, instance-group name mismatches.
Full procedure: [references/cluster-diagnostics-detail.md § C](references/cluster-diagnostics-detail.md#c-lifecycle-scripts).

## D: EKS Access / kubectl

IAM identity not in EKS access entries or kubeconfig not set up. Verify with `sts get-caller-identity`, check access entries and auth mode on the EKS cluster, then create an access entry with admin policy and update kubeconfig.
Full procedure: [references/cluster-diagnostics-detail.md § D](references/cluster-diagnostics-detail.md#d-eks-access--kubectl).

## E: Cluster Provisioning

Cluster shows InService but instances are missing — often expected with Continuous Provisioning (EKS only), where the cluster goes InService before all nodes are created. Check cluster events and node status; failures surface as events, not cluster-level errors.

**Cluster stuck in Creating/Updating/Deleting > 1 hour:** Check CloudFormation nested stacks for the real error (§ H), verify the IAM execution role has required permissions, check for capacity issues (§ B), and look at cluster events. If stuck in Deleting, check for VPC ENI dependencies. If no progress after 2 hours with no error events, escalate to AWS Support.
Full procedure: [references/cluster-diagnostics-detail.md § E](references/cluster-diagnostics-detail.md#e-cluster-provisioning).

## F: SSM Connectivity

SSM session fails with `Target is not connected`. Use the `sagemaker-cluster:` target format (not raw EC2 instance ID), verify the SSM plugin is installed, and confirm the node is Running. Check IAM permissions and VPC endpoints if timeouts persist.
Full procedure: [references/cluster-diagnostics-detail.md § F](references/cluster-diagnostics-detail.md#f-ssm-connectivity).

## G: Node Replacement

Auto or manual node replacement not triggering. For auto-replacement, verify `NodeRecovery` is enabled, check health agent logs and node labels/reasons, and confirm capacity. For manual recovery: reboot first, replace only if reboot fails. Cluster must be InService for `batch-replace-cluster-nodes`.
Full procedure: [references/cluster-diagnostics-detail.md § G](references/cluster-diagnostics-detail.md#g-node-replacement).

## H: CloudFormation Errors

Nested stack failures produce vague `Embedded stack failed`. Drill into nested stacks via the Events tab filtered by Failed until you reach the actual non-stack resource failure. CLI alternative: `describe-stack-events --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'`. Includes guidance for service-linked role (SLR) failures and permission boundaries.
Full procedure: [references/cluster-diagnostics-detail.md § H](references/cluster-diagnostics-detail.md#h-cloudformation-errors).

## I: Utilities

Map Slurm node names (`ip-10-1-123-45`) to HyperPod instance IDs using `list-cluster-nodes` or on-node `resource_config.json`. For large clusters, use the dump utility in `references/cluster-operations.md`.
Full procedure: [references/cluster-diagnostics-detail.md § I](references/cluster-diagnostics-detail.md#i-utilities).

## J: AMI & Cluster Updates

`UpdateClusterSoftware` fails silently and rolls back, or the cluster gets stuck in `ClusterMaintenanceRollbackFailed`. Common causes: lifecycle scripts incompatible with the new AMI, insufficient capacity for the rolling update, or IAM gaps. For `RollbackFailed` (non-terminal state), collect diagnostics and escalate — do NOT attempt to delete and recreate.
Full procedure: [references/cluster-diagnostics-detail.md § J](references/cluster-diagnostics-detail.md#j-ami--cluster-updates).

## K: Dangling Nodes & Cleanup

After a failed scale-up or rollback, EKS may show nodes that HyperPod no longer manages — "dangling" nodes appear in `kubectl get nodes` but not in `list-cluster-nodes`. The diagnostic script flags them automatically. Topology-label gaps on new nodes typically resolve on the next reconciliation cycle.
Full procedure: [references/cluster-diagnostics-detail.md § K](references/cluster-diagnostics-detail.md#k-dangling-nodes--cleanup).

## L: Autoscaler Compatibility

Cluster Autoscaler can conflict with HyperPod-managed node groups because HyperPod controls node lifecycle independently. The fix is to exclude HyperPod node groups from CAS via the node-level `cluster-autoscaler.kubernetes.io/scale-down-disabled=true` annotation (not `safe-to-evict`, which is a pod annotation), or via the `--balancing-ignore-label=sagemaker.amazonaws.com/compute-type` CAS arg.
Full procedure: [references/cluster-diagnostics-detail.md § L](references/cluster-diagnostics-detail.md#l-autoscaler-compatibility).

**Karpenter:** HyperPod nodes are not managed by Karpenter NodePools and should not conflict. If you see Karpenter disrupting HyperPod nodes, add `karpenter.sh/do-not-disrupt: "true"` to HyperPod pods, or configure a NodePool `requirements` filter that excludes nodes with `sagemaker.amazonaws.com/compute-type=hyperpod`.

---

## Read-only guarantee & remediation principle

The scripts in this skill never mutate cluster state and never emit remediation commands. Each issue detected points at a `references/<file>.md § <section>`; open that section with `Read` to find the root cause, exact commands, verification, and blast radius. Cluster-level remediations (SG changes, AMI upgrade, kubeconfig overwrite, node replacement) have wide blast radius — always explain the impact and wait for explicit customer approval before running anything.

## Prerequisites

Required on the machine running the skill:

- `aws` CLI v2.13+ — authenticated to the AWS account that owns the HyperPod cluster.
- `jq` — used for JSON parsing in `--validate` mode and add-on parsing.
- `python3` — used for safe JSON manipulation and SSM payload building.
- `bash` 4.2+.

Required for EKS cluster checks:

- `kubectl` — authenticated to the EKS cluster behind the HyperPod cluster. If absent, EKS-specific checks (access entries, add-ons, aws-auth) are skipped.
- `eks:DescribeCluster`, `eks:ListAccessEntries`, `eks:ListAddons`, `eks:DescribeAddon` in the caller's IAM.

Required for Slurm controller health (SSM-based):

- `session-manager-plugin`. The controller's instance role must include `AmazonSSMManagedInstanceCore`.

See [references/cluster-operations.md § 4 EKS Access Control](references/cluster-operations.md) and [§ 6 SSM Target Format](references/cluster-operations.md) for setup.

## Defaults

- **Region**: reads `$AWS_DEFAULT_REGION`; if unset, `us-east-1`.
- **Mode**: diagnose an existing cluster (`--cluster <NAME>`). Use `--validate` for pre-create checks on SGs / subnets / IAM.
- **Output colors**: ANSI colors on; `--no-color` disables.
- **Event window**: `list-cluster-events --max-results 20` (most recent). For long provisioning incidents, cross-check CloudWatch log streams (§ 7 in the script output).
- **Node list pagination**: paginated via `--no-paginate` / `NextToken` up to 5000 nodes.
- **SSM command timeout**: 180 seconds per controller probe with retries for throttling.
- **Read-only**: the script NEVER modifies cluster state and NEVER prints remediation commands.

## Error Handling

| Failure mode                                              | Script behavior                                                                   | What to tell the customer                                              |
| --------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `aws sts get-caller-identity` fails                       | Exit 1                                                                            | "Fix AWS credentials and rerun."                                       |
| Cluster not found                                         | Exit 1 after listing clusters in the region                                       | "Confirm the HyperPod cluster name (not the EKS name) and region."     |
| `sagemaker:*` / `ec2:*` / `eks:*` / `logs:*` AccessDenied | Warn, add `Missing IAM permission for <API>`, continue with partial data          | "Grant the listed IAM action and rerun."                               |
| `kubectl` absent / not authenticated                      | Skip EKS-specific checks (access entries, add-ons, aws-auth, node reconciliation) | "Install/authenticate kubectl; § D in references."                     |
| SSM plugin absent (Slurm cluster)                         | Skip Slurm controller probe                                                       | "Install session-manager-plugin; § F in references."                   |
| SSM `send-command` throttled                              | Retry with backoff; if still throttled, warn and continue                         | "Rerun later — script is idempotent."                                  |
| SSM command times out (180s) on large Slurm fleets        | Return partial output, note in summary                                            | "Rerun during a quiet window or reduce sinfo scope."                   |
| CloudWatch log group not found                            | Skip CloudWatch check, continue                                                   | "CloudWatch not configured on this cluster; see § 5 in operations.md." |

Exit codes: `0` = diagnostic complete (issues may still exist — check output); `1` = cluster not found / fatal prerequisite missing / critical failures present in `--validate` mode.

## IAM permissions required

See [references/iam-permissions.md](references/iam-permissions.md) for the full IAM policy.

## Skill delegation

| Need                                                              | Use                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------ |
| Per-node runtime issues (GPU, disk, OOM, Slurm)                   | `hyperpod-node-debugger` skill                         |
| SSM failure on a single node                                      | `hyperpod-node-debugger` § K                           |
| Cluster-wide SSM outage (all nodes unreachable)                   | stay here — § F                                        |
| Single-node EFA health-check failure post-provisioning            | `hyperpod-node-debugger` § A                           |
| Cluster-wide EFA health-check failure at creation time            | stay here — § A                                        |
| Cluster creation / deployment failures (CFN, capacity, lifecycle) | stay here — run `--validate` first, then `§ H / B / C` |
| NCCL timeout / distributed training errors                        | `hyperpod-nccl` skill                                  |
| Shell access to nodes                                             | `hyperpod-ssm` skill                                   |
| Software version comparison across nodes                          | `hyperpod-version-checker` skill                       |
| Diagnostic bundle for AWS Support                                 | `hyperpod-issue-report` skill                          |
| Training performance / MFU degradation                            | `hyperpod-mfu-debugger` skill                          |

## Escalate to AWS Support when

1. EFA health checks fail despite all SG rules being correct.
2. Capacity errors persist despite a valid Flexible Training Plan / ODCR.
3. Node replacement keeps failing with no clear error in events or logs.
4. Cluster stuck in a non-terminal state (Creating/Updating) for an extended period.
5. CloudFormation root cause error is an internal service error.

Collect diagnostics with `scripts/diagnose-cluster.sh` and `hyperpod-issue-report` before escalating.
