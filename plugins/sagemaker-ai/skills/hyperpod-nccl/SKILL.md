---
name: hyperpod-nccl
description: Diagnose NCCL failures and adjacent training-pod failures on HyperPod GPU clusters (EKS or Slurm) — training hangs, AllReduce / collective-op timeouts, EFA or libfabric errors, rendezvous failures, EFA TCP fallback, /dev/shm or memlock issues, NCCL version mismatch across pods, container OOM / exit-137 / OOMKilled, GPU OOM (CUDA out of memory), CrashLoopBackOff / Pending pods, MASTER_ADDR DNS, NetworkPolicy blocking. Not for single-node hardware faults (→ hyperpod-node-debugger § G) or cluster-creation EFA / SSM failures (→ hyperpod-cluster-debugger § A / § F).
metadata:
  version: "0.0.1"
---

# HyperPod NCCL Debugger

**Operating policy.** Run read-only diagnostics yourself. Never run a command that changes cluster, node, or workload state — present each one as a **Suggested command (run this yourself)** block and wait for the customer. Destructive order: **investigate → reboot → replace** (replace destroys root + secondary volumes; not supported on Slurm controller nodes). Never discard training state on speculation.

Diagnose NCCL failures on SageMaker HyperPod (EKS and Slurm). `scripts/nccl-diagnose.sh` reads state via AWS APIs, kubectl, and SSM, then prints each issue as `[FAIL] ... → references/<file>.md § <section>`. Read-only.

**Signal sourcing:** `list-cluster-events` carries infrastructure-level state only (lifecycle, bootstrap, EFA health check, capacity, replacement, reboot, AMI rollback). It does **not** carry NCCL timeouts, GPU XID/ECC, or per-pod training signals — those come from pod logs, CloudWatch training streams, on-node SSM probes, and NCCL env audit. "No events" on a training-time NCCL issue is expected, not a clean bill of health.

---

## Workflow

1. Collect cluster name, region, namespace/job (EKS), exact NCCL error string.
2. Run the diagnostic (always — the output drives everything else).
3. For every `[FAIL]` line, `Read` the referenced section.
4. Present finding, root cause, and the Suggested-command block with concrete values (instance IDs, SG IDs, namespaces) filled in from the script output. Wait for customer approval.
5. Re-run the diagnostic to confirm.

If a finding has no matching section, report it as a bug — do not invent a fix.

## Step 1: Authenticate kubectl (EKS)

```bash
EKS_ARN=$(aws sagemaker describe-cluster --cluster-name <HYPERPOD-NAME> --region <REGION> \
  --query 'Orchestrator.Eks.ClusterArn' --output text)
EKS_NAME=$(echo "$EKS_ARN" | awk -F'/' '{print $NF}')
aws eks update-kubeconfig --name "$EKS_NAME" --region <REGION>
kubectl get nodes
```

## Step 2: Run the diagnostic

```bash
# Basic:
bash scripts/nccl-diagnose.sh --cluster <HYPERPOD-NAME> --region <REGION>

# Scope to an EKS job/namespace:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --namespace <NS> --job <JOB>

# Force orchestrator:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --orchestrator slurm

# Larger hardware sample (default 3):
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --sample-nodes 10

# Specific node only:
bash scripts/nccl-diagnose.sh --cluster <NAME> --region <REGION> --node i-0abc123def456
```

Tags: `[PASS]` · `[FAIL]` (counted in `Issues Found`, has reference pointer) · `[WARN]` · `[INFO]`. Priorities: **P0** blocks training · **P1** degraded · **P2** informational.

---

## Remediation index

Each `[FAIL]` line in the script already points directly at the right section. This table is a lookup for manual triage.

| Finding                                    | Section                                                                                             |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| SG missing inbound/outbound self-reference | [operations.md § 8](references/operations.md)                                                       |
| Blocking NetworkPolicy / allow-all missing | [operations.md § 8](references/operations.md)                                                       |
| Slurm node DOWN / DRAINING / RemoveIPC     | [operations.md § 7](references/operations.md)                                                       |
| GPU XID / SYSTEM_ERROR / hardware fault    | [hyperpod-node-debugger § F / § G](../hyperpod-node-debugger/references/node-diagnostics-detail.md) |
| GPU row-remap / DCGM Fail / silent NaNs    | [hyperpod-node-debugger § G.1.a/b](../hyperpod-node-debugger/references/node-diagnostics-detail.md) |
| NCCL timeout / rendezvous / straggler      | [debugging-guide.md § 1](references/debugging-guide.md)                                             |
| EFA configuration / not used               | [debugging-guide.md § 6](references/debugging-guide.md)                                             |
| EFA TCP fallback (`NET/OFI Using TCP`)     | [debugging-guide.md § 13](references/debugging-guide.md)                                            |
| NCCL version mismatch across pods          | [debugging-guide.md § 10](references/debugging-guide.md)                                            |
| Container OOM (pod killed, exit 137)       | [debugging-guide.md § 4](references/debugging-guide.md)                                             |
| GPU OOM (`CUDA out of memory`)             | [debugging-guide.md § 11](references/debugging-guide.md)                                            |
| RDMA memlock / `/dev/shm` too small        | [debugging-guide.md § 17](references/debugging-guide.md)                                            |
| MASTER_ADDR DNS / headless Service         | [debugging-guide.md § 12](references/debugging-guide.md)                                            |
| NVLS / PXN / topology tuning               | [debugging-guide.md § 19](references/debugging-guide.md)                                            |
| Any NCCL / EFA / rendezvous log pattern    | [error-patterns-quick-ref.md](references/error-patterns-quick-ref.md)                               |
| Performance / nccl-tests / bandwidth       | [performance-testing.md](references/performance-testing.md)                                         |

---

## Prerequisites

- `aws` CLI v2.13+ authenticated (`aws sts get-caller-identity`)
- `jq`, `python3`, `bash` 4.2+
- `unbuffer` (from the `expect` package: `yum install expect` / `apt install expect`)
- `kubectl` authenticated to the EKS cluster (K8s checks skipped if absent)
- `session-manager-plugin` for on-node hardware checks

## Defaults

- **Region** — required: pass `--region` or set `$AWS_DEFAULT_REGION`.
- **Orchestrator** — auto-detected; override with `--orchestrator eks|slurm`.
- **Namespace / job (EKS)** — all namespaces; scope with `--namespace <NS> --job <JOB>`.
- **Hardware sampling** — 3 nodes over SSM (capped at 50). `--node <ID>` for a specific node. Node probes run **serially** (180 s per node): `--sample-nodes 10` can take ~30 min.
- **CloudWatch window** — last 2 hours.
- **Colors** — auto-disabled on non-TTY or `TERM=dumb`.

## Error handling

| Failure                             | Script                                                | Tell the customer                                                         |
| ----------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------- |
| `aws sts get-caller-identity` fails | Exit 1 with the AWS error                             | "Fix AWS credentials and rerun."                                          |
| `describe-cluster` AccessDenied     | Warn, add `Missing IAM for sagemaker:DescribeCluster` | "Grant `sagemaker:DescribeCluster` (operations.md § 2)."                  |
| Cluster not found                   | Exit 1 after listing region's clusters                | "Confirm HyperPod cluster name and region."                               |
| `kubectl` absent / unauthenticated  | Warn, skip K8s checks                                 | "`aws eks update-kubeconfig --name <EKS> --region <R>`."                  |
| SSM plugin absent                   | Warn, skip on-node hardware checks                    | "Install session-manager-plugin."                                         |
| SSM times out (180s)                | Partial output, mark node unreachable                 | "Rerun with `--node <ID> --sample-nodes 1`; check SSM agent on the node." |
| CloudWatch log group not found      | Skip CloudWatch scan                                  | "Enable CloudWatch on the cluster (operations.md § 4)."                   |
| Cluster events API throttled        | Warn, continue with partial data                      | "Rerun later — script is idempotent."                                     |

Exit codes: `0` diagnostic complete · `1` fatal prerequisite missing or cluster unreachable.

## IAM permissions

Full policy + RBAC in [operations.md § 2](references/operations.md#2-iam). SSM on HyperPod uses `start-session` against `sagemaker-cluster:<cluster-id>_<group>-<iid>` targets — grant `ssm:StartSession` / `ssm:TerminateSession`, not `ssm:SendCommand`.

## Scale strategy

| Scope           | Method                                   | Coverage                 |
| --------------- | ---------------------------------------- | ------------------------ |
| All nodes       | `sagemaker:ListClusterNodes` (paginated) | 100% nodes               |
| All K8s objects | `kubectl`                                | 100% pods/nodes/policies |
| Hardware        | SSM `--sample-nodes N` (default 3)       | Sampled                  |
| Node logs       | CloudWatch                               | 100% nodes               |

**Large clusters:** the PyTorch NCCL backend defaults to a 10-minute collective-op timeout (per the PyTorch distributed docs). Large clusters routinely exceed that on first rendezvous; raise it via `torch.distributed.init_process_group(timeout=timedelta(seconds=<N>))`. HyperPod support has also observed NCCL topology-graph-search hangs on 256+ node clusters when `memlock` is `unlimited`; using a large fixed memlock (e.g. `8388608`) in pod `securityContext` or `/etc/security/limits.conf` has cleared these in field cases. This memlock pattern is a field observation, not AWS- or NCCL-documented behavior.

For **FSDP**, **DeepSpeed**, or **Megatron-LM** tuning: [debugging-guide.md § 18](references/debugging-guide.md).

## Skill delegation

| Need                                                                   | Use                                                          |
| ---------------------------------------------------------------------- | ------------------------------------------------------------ |
| Cluster creation / deployment failures                                 | `hyperpod-cluster-debugger` (§ A / B / C / H + `--validate`) |
| Post-deployment cluster-wide management                                | `hyperpod-cluster-debugger`                                  |
| Per-node issues (disk, lifecycle, hardware)                            | `hyperpod-node-debugger`                                     |
| Trainium/Inferentia collective-comm (AWS Neuron Collectives, not NCCL) | `hyperpod-node-debugger` § G.2                               |
| Shell on nodes                                                         | `hyperpod-ssm`                                               |
| Version comparison across nodes                                        | `hyperpod-version-checker`                                   |
| Diagnostic bundle for AWS Support                                      | `hyperpod-issue-report`                                      |
| MFU / performance degradation                                          | `hyperpod-mfu-debugger`                                      |

## Escalate to AWS Support

Escalate when:

1. All SG rules correct, EFA verified on-node, but NCCL still times out.
2. Hardware checks pass on all nodes but AllReduce still hangs.
3. `Issues Found: 0` but training still fails.
4. GPU XID errors persist after node replacement.
5. Collective-op timeout raised and memlock workaround applied but large-cluster rendezvous still hangs.

### Before opening the case

```bash
# 1. Cluster identity + status
aws sagemaker describe-cluster --cluster-name <C> --region <R>

# 2. Full NCCL diagnostic (sample more nodes for escalation)
bash scripts/nccl-diagnose.sh --cluster <C> --region <R> --sample-nodes 10 > nccl-diag.txt

# 3. Per-node log/config bundle to S3 (delegates to hyperpod-issue-report)
#    See skills/hyperpod-issue-report/SKILL.md for the exact invocation.
```

### Include in the case

- Cluster name + ARN and AWS region
- Orchestrator (EKS or Slurm) and EKS cluster name / Slurm controller node
- Timestamp window (UTC start / end) of the failure
- Exact NCCL / libfabric error strings (copy verbatim from pod logs or journalctl)
- Affected instance IDs / node names / pod names / namespace / job name
- `nccl-diag.txt` from step 2 above
- S3 URI of the `hyperpod-issue-report` bundle from step 3
- NCCL env vars in effect (`printenv | grep -E '^NCCL|^FI_|^TORCH_'` from one pod)

## References

- [error-patterns-quick-ref.md](references/error-patterns-quick-ref.md) — log pattern → code → fix table
- [debugging-guide.md](references/debugging-guide.md) — per-scenario procedures (21 sections incl. NVLS/PXN/topology)
- [performance-testing.md](references/performance-testing.md) — nccl-tests, bandwidth thresholds, straggler detection
- [operations.md](references/operations.md) — IAM, SSM format, CloudWatch, env-var reference, node labels, Slurm ops, remediations
