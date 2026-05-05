---
name: hyperpod-nccl
description: Use for NCCL-specific failure on SageMaker HyperPod GPU clusters (EKS or Slurm, p4d/p4de/p5/p5e/p5en/p6) — training hang, AllReduce timeout, EFA/libfabric error, collective-op abort, distributed training not starting. Covers NCCL timeouts, rendezvous failures, NetworkPolicy blocking NCCL, /dev/shm/memlock issues, aws-ofi-nccl missing, EFA TCP fallback, EFA device-count mismatch, NCCL_SOCKET_IFNAME errors, headless service / DNS resolution, NVLS/PXN/topology tuning, NCCL version mismatch across pods, straggler detection, init-container failures. Do NOT use for single-node hardware faults (GPU XID / ECC / silent NaNs / row-remap) → use hyperpod-node-debugger § G. Do NOT use for cluster-wide SSM or EFA failures at cluster creation time → use hyperpod-cluster-debugger § F / § A.
metadata:
  version: "1.0.0"
---

# NCCL HyperPod Debugger

Diagnose NCCL failures on SageMaker HyperPod (EKS and Slurm).

**Clear separation of concerns:**

- `scripts/nccl-diagnose.sh` is a **read-only signal collector**. It reads cluster state via AWS APIs, kubectl, and on-node SSM, then prints each detected issue as a `[FAIL]` line. Every `[FAIL]` line ends with a pointer of the form `→ references/<file>.md § <section>`. The script never prints remediation commands and never modifies cluster state.
- `references/*.md` contains the full remediation runbook for every issue the script can detect — root cause, preconditions, exact commands, verification, rollback.

---

## Workflow (authoritative)

1. **Collect inputs** — cluster name, region, namespace/job if EKS, exact error message from the customer's logs.
2. **Run the diagnostic** (step 3 below). Do not skip this even if the customer already knows the cause; the script produces a stable list of findings the rest of the workflow depends on.
3. **Read the script output top-to-bottom.** For every `[FAIL]` line, note the trailing `→ references/<file>.md § <section>` pointer. Ignore `[PASS]` lines; treat `[WARN]` as advisory.
4. **Open each referenced section.** Use the `Read` tool on the exact file path. Do not paraphrase remediation from memory — read the current doc.
5. **Present the remediation to the customer.** For each finding, state:
   - What the script detected (copy the `[FAIL]` line verbatim).
   - What the root cause is (from the referenced section).
   - The exact command(s) to run.
   - The blast radius (e.g. "this reboots node i-xxx", "this changes SG on all cluster nodes").
6. **Wait for explicit customer approval** before running any command that modifies state. Prefer the least-destructive action first (investigate → reboot → replace).
7. **Re-run the diagnostic** after remediation to confirm the `[FAIL]` is cleared. If not, iterate.

If a finding has no matching section in references (should not happen — if it does, report it as a bug), say so clearly rather than inventing a fix.

**Signal sourcing note.** HyperPod `list-cluster-events` (Check 3) reports **infrastructure-level state only** — lifecycle, bootstrap, EFA health-check, capacity, replacement, reboot, AMI rollback. It does **not** carry NCCL timeouts, GPU XID/ECC, or per-pod training signals. Those come from pod logs (Check 6), CloudWatch (Check 6b), on-node SSM probes (Check 8), and NCCL env audit (Check 7). If a customer reports a training-time NCCL issue and Check 3 shows "no events" — that is expected, not a clean bill of health.

---

## Prerequisites

Required on the machine running the skill:

- `aws` CLI v2.13+ — authenticated to the AWS account that owns the HyperPod cluster (verify with `aws sts get-caller-identity`).
- `jq` — used for JSON parsing; hard prerequisite.
- `python3` — used for safe JSON manipulation when building SSM payloads and parsing cluster events.
- `bash` 4.2+ (AL2 bash 4.2 works; AL2023/Ubuntu/macOS all work).

Required for EKS clusters:

- `kubectl` — authenticated to the EKS cluster behind the HyperPod cluster. If `kubectl get nodes` fails, K8s checks (2, 2b, 5, 5b, 6, 7, 9) are skipped and the script reports it.

Required for on-node hardware checks:

- `session-manager-plugin` (AWS Systems Manager) — used to run diagnostic commands on compute nodes. If absent, SSM checks are skipped and the script reports it.

See [references/operations.md § 1 Pre-Flight Checklist](references/operations.md) for setup commands.

## Defaults

What the script does when the customer does not specify:

- **Region**: reads `$AWS_DEFAULT_REGION`; if unset, the operator must pass `--region` (the script exits with an error — no implicit region assumption).
- **Orchestrator**: auto-detected from `aws sagemaker describe-cluster`; override with `--orchestrator eks|slurm`.
- **Namespace scoping (EKS)**: all namespaces. Pass `--namespace <NS>` to scope checks to a single training namespace.
- **Job scoping (EKS)**: all jobs. Pass `--job <JOB-NAME>` to scope to one job.
- **Hardware-check node sampling**: 3 compute nodes via SSM. Pass `--sample-nodes N` (capped at 50) or `--node <INSTANCE-ID>` for a specific node. **Node probes run serially** — `--sample-nodes 10` can take up to ~30 minutes in the worst case (10 × 180s). Use `--node <ID>` to isolate a suspect node quickly.
- **SSM command timeout**: 180 seconds per node (hardware diagnostics can take 30-120s on busy p5 nodes).
- **CloudWatch log window**: last 2 hours for pattern scanning.
- **Output colors**: ANSI colors on; set `TERM=dumb` or pipe to a non-TTY to disable.
- **Read-only**: the script NEVER modifies cluster state and NEVER prints remediation commands. Remediation always comes from `references/*.md`.

## Error Handling

How the script responds to common failure modes:

| Failure mode                                            | Script behavior                                                                  | What to tell the customer                                                            |
| ------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `aws sts get-caller-identity` fails                     | Exit 1 with the AWS error message                                                | "Fix your AWS credentials (aws configure / aws sso login / AWS_PROFILE) and rerun."  |
| `aws sagemaker describe-cluster` returns AccessDenied   | Warn, add issue `Missing IAM permission for sagemaker:DescribeCluster`, continue | "Add `sagemaker:DescribeCluster` and retry; see operations.md § 3."                  |
| Cluster not found                                       | Exit 1 after listing available clusters in the region                            | "Confirm the HyperPod cluster name and region."                                      |
| `kubectl` absent / not authenticated / cannot reach API | Warn, skip K8s checks, note in summary                                           | "Run `aws eks update-kubeconfig --name <EKS-NAME> --region <R>`."                    |
| SSM plugin absent                                       | Warn, skip on-node hardware checks                                               | "Install session-manager-plugin; see operations.md § 4."                             |
| SSM command times out (180s)                            | Return partial output, mark node as unreachable                                  | "Rerun with `--node <ID> --sample-nodes 1` to isolate; check SSM agent on the node." |
| CloudWatch log group not found                          | Skip CloudWatch scan, continue                                                   | "Enable CloudWatch on the cluster; see operations.md § 5."                           |
| Cluster events API returns throttling                   | Warn and continue with partial data                                              | "Rerun later; the script is idempotent and safe to rerun."                           |

The script exits `0` when diagnostics complete (issues may still be present — check the summary). It exits `1` only when prerequisites are missing or the cluster cannot be reached at all.

---

## Step 1: Collect information

Ask the customer for:

- **HyperPod cluster name** (not the EKS cluster name):

  ```bash
  aws sagemaker list-clusters --region <REGION> --query 'ClusterSummaries[*].ClusterName'
  ```

- **AWS region** — e.g. `us-east-1`, `us-west-2`
- **Namespace + job name** (optional, EKS) — scopes checks to a specific training job
- **Error message** — copy the exact NCCL error from logs

## Step 2: Authenticate kubectl (EKS only)

```bash
EKS_ARN=$(aws sagemaker describe-cluster --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo "$EKS_ARN" | awk -F'/' '{print $NF}')
aws eks update-kubeconfig --name "$EKS_NAME" --region <REGION>
kubectl get nodes
```

## Step 3: Run the diagnostic (read-only)

```bash
# Basic diagnostic — prints findings and reference pointers:
bash scripts/nccl-diagnose.sh --cluster <HYPERPOD-NAME> --region <REGION>

# Scope to a specific EKS job/namespace:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> \
  --namespace <NS> --job <JOB-NAME>

# Force orchestrator if auto-detect is wrong:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --orchestrator slurm

# Hardware-check more nodes via SSM (default 3):
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --sample-nodes 10

# Check a specific node only:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --node i-0abc123def456
```

The script prints:

| Tag      | Meaning                                                               |
| -------- | --------------------------------------------------------------------- |
| `[PASS]` | Check passed — no action needed                                       |
| `[FAIL]` | Problem found — counted in `Issues Found`, includes reference pointer |
| `[WARN]` | Advisory                                                              |
| `[INFO]` | Informational                                                         |

Priority labels in the summary:

- **P0** — Fix immediately (blocks training)
- **P1** — Fix soon (degraded or at-risk)
- **P2** — Informational (review when convenient)

## Step 4: Look up remediation and guide the customer

Each `[FAIL]` line ends with `→ references/<file>.md § <section>`. For every finding:

1. Open the referenced section with the `Read` tool (do not guess from memory — the doc is the source of truth).
2. Read the full section: root cause, preconditions, exact commands, verification.
3. Present to the customer: the finding, the root cause, the command(s) with concrete values (instance IDs, SG IDs, namespaces interpolated from the script output), and the blast radius.
4. **Wait for explicit approval** before running any state-changing command. Destructive actions (`batch-reboot-cluster-nodes`, `batch-replace-cluster-nodes`, `kubectl delete networkpolicy`, SG rule changes) require extra care — describe exactly what they affect.
5. Prefer the narrowest scope: investigate one node before rebooting, read one NetworkPolicy before deleting it, try reboot before replacement.
6. After the customer runs the command, re-run the diagnostic and confirm the `[FAIL]` is cleared.

---

## Remediation index

Where each class of finding is documented. The script itself points directly at the right section via `→ references/<file>.md § <section>` in each `[FAIL]` line.

| Issue surfaced by script                               | Remediation section                                                                       |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| SG missing inbound/outbound self-reference             | [operations.md § Security Groups](references/operations.md)                               |
| Blocking NetworkPolicy / allow-all policy missing      | [operations.md § NetworkPolicy](references/operations.md)                                 |
| Slurm node DOWN/DRAINING                               | [operations.md § Slurm Node Management](references/operations.md)                         |
| GPU XID / SYSTEM_ERROR / hardware fault                | [operations.md § Node Reboot & Replacement](references/operations.md)                     |
| GPU row-remap pending/failed / DCGM Fail / silent NaNs | [debugging-guide.md § 21 GPU Row-Remap / DCGM Health](references/debugging-guide.md)      |
| NCCL timeout / rendezvous / straggler                  | [debugging-guide.md § 1 NCCL Timeout / Rendezvous Hang](references/debugging-guide.md)    |
| EFA configuration / not used                           | [debugging-guide.md § 6 EFA Configuration](references/debugging-guide.md)                 |
| EFA TCP fallback                                       | [debugging-guide.md § 13 EFA TCP Fallback](references/debugging-guide.md)                 |
| NCCL version mismatch across pods                      | [debugging-guide.md § 10 NCCL Version Mismatch](references/debugging-guide.md)            |
| Container OOM (pod killed)                             | [debugging-guide.md § 4 Container OOM](references/debugging-guide.md)                     |
| GPU OOM (CUDA out of memory)                           | [debugging-guide.md § 11 GPU OOM](references/debugging-guide.md)                          |
| RDMA memlock / `/dev/shm` too small                    | [debugging-guide.md § 17 RDMA Memory Registration Failure](references/debugging-guide.md) |
| MASTER_ADDR DNS / headless Service                     | [debugging-guide.md § 12 DNS Resolution Failure](references/debugging-guide.md)           |
| NVLS / PXN / topology tuning                           | [debugging-guide.md § 19 Advanced NCCL Tuning](references/debugging-guide.md)             |
| NCCL log pattern (any of 38)                           | [error-patterns-quick-ref.md](references/error-patterns-quick-ref.md)                     |
| Performance / nccl-tests / bandwidth                   | [performance-testing.md](references/performance-testing.md)                               |

---

## IAM permissions required

Read-only diagnostic needs:

```json
{
  "Action": [
    "sagemaker:DescribeCluster",
    "sagemaker:ListClusterNodes",
    "sagemaker:ListClusterEvents",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeInstances",
    "logs:DescribeLogStreams",
    "logs:FilterLogEvents",
    "ssm:StartSession",
    "ssm:TerminateSession"
  ]
}
```

> SSM on HyperPod uses `start-session` against `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets, not `send-command` against plain instance IDs (HyperPod's managed instance fleet does not expose bare instance IDs to customer `SendCommand` calls). Grant `ssm:StartSession` and `ssm:TerminateSession` — not `ssm:SendCommand` / `ssm:GetCommandInvocation`.

If the customer plans to apply a remediation, they will additionally need the write permission relevant to that action (for example `ec2:AuthorizeSecurityGroupIngress`, `sagemaker:BatchRebootClusterNodes`, etc.). Point them to the specific action before they apply it.

---

## Scale strategy

| Scope           | Method                                   | Coverage                 |
| --------------- | ---------------------------------------- | ------------------------ |
| All nodes       | `sagemaker:ListClusterNodes` (paginated) | 100% nodes               |
| All K8s objects | `kubectl`                                | 100% pods/nodes/policies |
| Hardware checks | SSM `--sample-nodes N` (default 3)       | Sampled                  |
| All node logs   | CloudWatch                               | 100% nodes               |

For 100+ node clusters use `--sample-nodes 10`, or `--node <ID>` for a specific suspect node.

**256+ node clusters:** NCCL topology graph search can fail or hang when `memlock` is set to `unlimited` (GNU libc then reduces thread stack to 2 MB). Use `memlock=8388608` in pod `securityContext` or `/etc/security/limits.conf`. Also increase `NCCL_TIMEOUT` proportionally: `NCCL_TIMEOUT=$(( nodes * 5 + 600 ))`.

---

## Distributed framework guidance

For NCCL tuning specific to **FSDP**, **DeepSpeed**, or **Megatron-LM**, see [references/debugging-guide.md § 18](references/debugging-guide.md) — framework-specific NCCL env vars, common failure patterns, and parallelism mapping for HyperPod clusters.

---

## Skill delegation

| Issue type                                                                                     | Use                                                                |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Cluster creation / deployment failures                                                         | `hyperpod-cluster-debugger` skill (§ A / B / C / H + `--validate`) |
| Post-deployment cluster-wide management                                                        | `hyperpod-cluster-debugger` skill                                  |
| Node-level issues (not NCCL) — disk, lifecycle, hardware                                       | `hyperpod-node-debugger` skill                                     |
| Trainium/Inferentia collective-comm issues (trn1/trn2/inf2 — AWS Neuron Collectives, not NCCL) | `hyperpod-node-debugger` § G.2                                     |
| Shell access on nodes                                                                          | `hyperpod-ssm` skill                                               |
| Software version comparison across nodes                                                       | `hyperpod-version-checker` skill                                   |
| Diagnostic bundle for AWS Support                                                              | `hyperpod-issue-report` skill                                      |
| Training performance / MFU degradation                                                         | `hyperpod-mfu-debugger` skill                                      |

---

## Escalate to AWS Support when

1. All SG rules correct and EFA verified on-node but NCCL still times out.
2. Hardware checks pass on all nodes but AllReduce hangs persist.
3. `nccl-diagnose.sh` reports `Issues Found: 0` but training still fails.
4. GPU XID errors persist after node replacement.
5. Memlock and timeout tuned for 256+ nodes but topology search still hangs.

Collect before escalating:

```bash
bash scripts/nccl-diagnose.sh --cluster <C> --region <R> --sample-nodes 10
# Then use hyperpod-issue-report skill for comprehensive log collection
```

---

## References

- [references/error-patterns-quick-ref.md](references/error-patterns-quick-ref.md) — 38-pattern error table with root cause + remediation commands
- [references/debugging-guide.md](references/debugging-guide.md) — step-by-step procedures per failure type (19 scenarios incl. NVLS/PXN/topology)
- [references/performance-testing.md](references/performance-testing.md) — nccl-tests, bandwidth thresholds, straggler detection
- [references/operations.md](references/operations.md) — Security Groups, NetworkPolicy, Slurm node management, node reboot/replacement
