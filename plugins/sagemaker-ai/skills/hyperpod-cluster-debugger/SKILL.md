---
name: hyperpod-cluster-debugger
description: Diagnose and remediate cluster-wide HyperPod (EKS or Slurm) problems — creation / deployment failures (CloudFormation, EFA health check, lifecycle scripts, capacity), EKS access, node replacement, CloudFormation nested-stack errors, post-maintenance rollback state, dangling nodes, autoscaler conflicts. Includes `--validate` pre-flight. Read-only.
metadata:
  version: "0.0.1"
---

# HyperPod Cluster Debugger

**Operating policy.** Run read-only diagnostics yourself. Never run a command that changes cluster, node, or workload state — present each one as a **Suggested command (run this yourself)** block and wait for the customer to run it. Destructive order: **investigate → reboot → replace** (replace destroys root + secondary volumes; not supported on Slurm controller nodes).

**Before any state-changing CLI: ask if it's IaC-managed.** HyperPod clusters, SGs, EKS access entries, and IAM are usually provisioned via CloudFormation / CDK / Terraform. If yes, the fix belongs in IaC — running the CLI will drift and the next deploy reverts it. Use the CLI only when IaC is unavailable (locked out, predates IaC, mid-review).

`scripts/diagnose-cluster.sh` is read-only: it collects state via AWS APIs (and SSM for Slurm controller health) and prints each issue as `[FAIL] ... → references/<file>.md § <section>`.

| Reference                                                                 | Open when                                                           |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| [cluster-diagnostics-detail.md](references/cluster-diagnostics-detail.md) | Per-finding remediation runbook (§ A–L)                             |
| [cluster-operations.md](references/cluster-operations.md)                 | Operational deep-dives (EFA SG, EKS access, SSM, Slurm, filesystem) |
| [cloudformation-errors.md](references/cloudformation-errors.md)           | § H needs the full per-resource CFN error catalog                   |
| [capacity-planning.md](references/capacity-planning.md)                   | § B or `--validate` flags capacity / subnet sizing                  |
| [lifecycle-scripts.md](references/lifecycle-scripts.md)                   | § C points at a specific lifecycle failure                          |
| [iam-permissions.md](references/iam-permissions.md)                       | Full IAM policy for the diagnostic                                  |

---

## Workflow

1. Collect HyperPod cluster name (not EKS name), region, exact error string.
2. Run `scripts/diagnose-cluster.sh` (or `--validate` for pre-create).
3. For every `[FAIL]` line, `Read` the referenced section.
4. Present finding, root cause, and the Suggested-command block verbatim. Wait for customer approval.
5. Re-run the diagnostic to confirm.

---

## Step 1: Run diagnostics

```bash
# Diagnose an existing cluster:
bash scripts/diagnose-cluster.sh --cluster <CLUSTER_NAME_OR_ARN> --region <REGION>

# Pre-flight (no cluster needed) — validates SGs, subnets, IAM, VPC endpoints,
# optionally S3 lifecycle scripts and per-AZ capacity:
bash scripts/diagnose-cluster.sh --validate --region <REGION> \
  --sg-ids <sg-1,sg-2> --subnet-ids <sub-1,sub-2> [--iam-role <role-arn>] \
  [--s3-uri s3://<BUCKET>/path/] [--instance-type ml.p5.48xlarge]
```

Pass `--instance-type` when the target instance type is known — enables the per-AZ capacity check (warns if none of the provided subnets are in an AZ that offers that type, which causes insufficient-capacity failures at creation time).

Tags: `[PASS]` · `[FAIL]` (counted, has `→ references/...` pointer) · `[WARN]` · `[INFO]`. Priorities: **P0** blocks operation · **P1** degraded · **P2** informational.

---

## Step 2: Match signal → section

**Error messages / events:**

| Signal                                                                       | Section                                                        |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `"EFA health checks did not run successfully"` (public-doc verbatim signal)  | **[A: EFA Health Checks](#a-efa-health-checks)**               |
| Insufficient-capacity or AZ-mismatch failure at creation                     | **[B: Capacity & AZ](#b-capacity--az)**                        |
| Lifecycle-script failure or timeout during provisioning                      | **[C: Lifecycle Scripts](#c-lifecycle-scripts)**               |
| kubectl auth error (server asks for credentials / no API group list)         | **[D: EKS Access](#d-eks-access--kubectl)**                    |
| `InService` but not all instances visible                                    | **[E: Cluster Provisioning](#e-cluster-provisioning)**         |
| `"Target is not connected"` / SSM errors                                     | **[F: SSM Connectivity](#f-ssm-connectivity)**                 |
| Node replacement not happening / `batch-replace` not working                 | **[G: Node Replacement](#g-node-replacement)**                 |
| `"Embedded stack failed"` / any CloudFormation error                         | **[H: CloudFormation Errors](#h-cloudformation-errors)**       |
| `UpdateClusterSoftware` failed or cluster in post-maintenance rollback state | **[J: AMI & Cluster Updates](#j-ami--cluster-updates)**        |
| Dangling / orphaned nodes in EKS vs `list-cluster-nodes`                     | **[K: Dangling Nodes & Cleanup](#k-dangling-nodes--cleanup)**  |
| Cluster Autoscaler breaks after HyperPod attached                            | **[L: Autoscaler Compatibility](#l-autoscaler-compatibility)** |
| Slow I/O, FSx throughput saturated                                           | [cluster-operations.md § 9](references/cluster-operations.md)  |
| Slurm node name → instance ID lookup                                         | **[I: Utilities](#i-utilities)**                               |

---

## A: EFA Health Checks

SG missing self-reference. Add inbound + outbound self-ref to every SG on the cluster, plus least-privilege egress for the AWS APIs the node needs (HTTPS 443 to S3 / ECR / SageMaker / SSM / STS / CloudWatch Logs — via VPC-endpoint prefix-lists when possible). Full procedure: [cluster-diagnostics-detail.md § A](references/cluster-diagnostics-detail.md#a-efa-health-checks).

## B: Capacity & AZ

Instance type unavailable in the requested AZ. Verify with `describe-instance-type-offerings`, then change AZ, use Flexible Training Plans, or request ODCR. Full: [§ B](references/cluster-diagnostics-detail.md#b-capacity--az) · strategy: [capacity-planning.md](references/capacity-planning.md).

## C: Lifecycle Scripts

Script failed or timed out during provisioning. Read CloudWatch under `/aws/sagemaker/Clusters/<name>/<id>` — common causes: missing S3 VPC endpoint, IAM gap, CRLF line endings, instance-group name mismatch. Full: [§ C](references/cluster-diagnostics-detail.md#c-lifecycle-scripts) · layout: [lifecycle-scripts.md](references/lifecycle-scripts.md).

## D: EKS Access / kubectl

IAM identity not in EKS access entries. Verify with `sts get-caller-identity`, create an access entry with admin policy, update kubeconfig. Full: [§ D](references/cluster-diagnostics-detail.md#d-eks-access--kubectl).

## E: Cluster Provisioning

`InService` without all instances is expected under Continuous Provisioning — failures surface as events, not cluster errors. For stuck `Creating`/`Updating`/`Deleting`: check CFN nested stacks (§ H), IAM, capacity, events; if stuck `Deleting` check VPC ENI dependencies. Full: [§ E](references/cluster-diagnostics-detail.md#e-cluster-provisioning).

## F: SSM Connectivity

`Target is not connected`: use `sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>` format (not raw EC2 ID), install session-manager-plugin, confirm node `Running`. Check IAM + VPC endpoints on timeouts. Full: [§ F](references/cluster-diagnostics-detail.md#f-ssm-connectivity).

## G: Node Replacement

Auto-repair: confirm `NodeRecovery=Automatic`, check Health Monitoring Agent (HMA) logs + node labels / Slurm reason, confirm capacity. Manual: reboot first, replace only if reboot fails. Replace requires the cluster to have been patched via `UpdateClusterSoftware` at least once and cannot target a Slurm controller node. Full: [§ G](references/cluster-diagnostics-detail.md#g-node-replacement).

## H: CloudFormation Errors

`Embedded stack failed` hides the real error. Drill into nested stacks via Events tab (filter Failed) until you reach a non-stack resource. CLI: `describe-stack-events --query 'StackEvents[?ResourceStatus==\`CREATE_FAILED\`]'`. Also covers SLR creation failures and permission-boundary denials. Full: [§ H](references/cluster-diagnostics-detail.md#h-cloudformation-errors) · catalog: [cloudformation-errors.md](references/cloudformation-errors.md).

## I: Utilities

Map Slurm node names (`ip-10-x-y-z`) to HyperPod instance IDs via `list-cluster-nodes` or on-node `/opt/ml/config/resource_config.json`. Full: [§ I](references/cluster-diagnostics-detail.md#i-utilities).

## J: AMI & Cluster Updates

`UpdateClusterSoftware` fails and rolls back, or the cluster stays in a post-maintenance rollback state. Common causes: lifecycle script incompatible with new AMI, HMA version too old, insufficient rolling-update capacity. If the cluster has active nodes, collect diagnostics and escalate rather than delete-and-recreate. Full: [§ J](references/cluster-diagnostics-detail.md#j-ami--cluster-updates).

## K: Dangling Nodes & Cleanup

Nodes in `kubectl get nodes` but not in `list-cluster-nodes` (ghost EKS nodes), or the inverse (HyperPod nodes that never registered kubelet). Script flags both. Full: [§ K](references/cluster-diagnostics-detail.md#k-dangling-nodes--cleanup).

## L: Autoscaler Compatibility

Cluster Autoscaler errors on HyperPod provider IDs and breaks autoscaling for all node groups. No officially endorsed workaround — escalate to AWS Support. Karpenter does not conflict with HyperPod nodes by default. Full: [§ L](references/cluster-diagnostics-detail.md#l-autoscaler-compatibility).

---

## Prerequisites

- `aws` CLI v2.13+ authenticated to the cluster's account
- `jq`, `python3`, `bash` 4.2+
- `kubectl` authenticated to the EKS cluster (EKS checks skipped if absent)
- `session-manager-plugin` (Slurm controller health checks only)

IAM policy: [references/iam-permissions.md](references/iam-permissions.md).

## Defaults

- **Region** — required: pass `--region` or set `$AWS_DEFAULT_REGION`.
- **Mode** — `--cluster <NAME>` (diagnose) or `--validate` (pre-create).
- **Event window** — up to 500 most recent events (5 × 100, paginated).
- **Colors** — auto-disabled on non-TTY; `--no-color` to force off.

## Error handling

| Failure                                             | Script                                                     | Tell the customer                                     |
| --------------------------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------- |
| `aws sts get-caller-identity` fails                 | Exit 1                                                     | "Fix AWS credentials and rerun."                      |
| Cluster not found                                   | Exit 1 after listing region's clusters                     | "Confirm HyperPod cluster name (not EKS) and region." |
| `sagemaker:*` / `ec2:*` / `eks:*` / `logs:*` denied | Warn, add `Missing IAM permission for <API>`, continue     | "Grant the listed IAM action and rerun."              |
| `kubectl` absent or unauthenticated                 | Skip EKS checks (access entries, add-ons, aws-auth, nodes) | "Install/authenticate kubectl."                       |
| `session-manager-plugin` absent (Slurm)             | Skip Slurm controller probe                                | "Install session-manager-plugin."                     |
| SSM throttled / times out (180s)                    | Retry with backoff; warn and continue if still failing     | "Rerun later — script is idempotent."                 |
| CloudWatch log group not found                      | Skip CloudWatch check                                      | "CloudWatch not configured on this cluster."          |

Exit codes: `0` no critical failures · `1` one or more critical failures (cluster not found, fatal prerequisite missing, or any `[FAIL]` in diagnose or `--validate` mode). `[WARN]` lines do not affect the exit code.

## Skill delegation

| Need                            | Use                        |
| ------------------------------- | -------------------------- |
| Shell on nodes                  | `hyperpod-ssm`             |
| Version comparison across nodes | `hyperpod-version-checker` |

## Escalate to AWS Support

Escalate when:

1. EFA health checks fail despite correct SG rules.
2. Capacity errors persist despite a valid Flexible Training Plan / ODCR.
3. Node replacement fails repeatedly without clear events / log signal.
4. Cluster stuck in a non-terminal state (`Creating`, `Updating`, or a post-maintenance rollback state) for an extended period.
5. CloudFormation root-cause is an internal service error.

### Before opening the case

Run these commands and attach the output. Goal: AWS Support has everything at case open.

```bash
# 1. Cluster identity + status (confirms region, ARN, orchestrator, instance groups)
aws sagemaker describe-cluster --cluster-name <CLUSTER> --region <REGION>

# 2. Full cluster-level diagnostic bundle
bash scripts/diagnose-cluster.sh --cluster <CLUSTER> --region <REGION> > diag.txt

# 3. Per-node log/config bundle to S3 (delegates to hyperpod-issue-report skill)
#    See skills/hyperpod-issue-report/SKILL.md for the exact invocation.
```

### Include in the case

- Cluster name + ARN (or `ClusterId` suffix) and AWS region
- `ClusterStatus` + `FailureMessage` from `describe-cluster`
- Timestamp window (UTC start / end) of the failure
- Exact error strings observed (copy verbatim from events / logs / console)
- Affected instance IDs / `NodeLogicalId`s / instance group names
- `diag.txt` from step 2 above
- S3 URI of the `hyperpod-issue-report` bundle from step 3
