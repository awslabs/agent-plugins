---
name: hyperpod-slurm-debugger
description: Diagnostic-only skill for Slurm scheduler and node-daemon issues on Amazon SageMaker HyperPod Slurm clusters. Scope mirrors the HyperPod troubleshooting guide. Invoke when the user reports a Slurm node stuck in down/drain, "Node unexpectedly rebooted" after auto-repair, slurmd not running, jobs stuck PENDING with REASON=Resources while sinfo shows idle nodes, jobs stuck COMPLETING after node replacement, GRES/GPU counts wrong, scontrol ping failing, slurmctld unresponsive, an Action:Reboot/Replace request that did not trigger HyperPod auto-recovery, or auto-resume not restarting a job. Also triggers on "drain before reboot", "diagnose a Slurm node", "investigate stuck jobs."
metadata:
  version: "0.0.1"
---

# HyperPod Slurm Debugger

Diagnostic-only. Identify and classify Slurm scheduler and node-daemon issues on
HyperPod Slurm clusters. Do not run, recommend, or print any state-mutating command.
For remediation, link to the official AWS or Slurm documentation.

## When to invoke

Invoke when the user reports any of the symptoms in the [decision table](#decision-table).

## When NOT to invoke

- Cluster has `Orchestrator.Eks` — invoke `hyperpod-node-debugger` or `hyperpod-nccl`.
- Single-node hardware fault with healthy Slurm scheduler — invoke `hyperpod-node-debugger`.
- NCCL training-hang investigation — invoke `hyperpod-nccl`.
- Node unreachable via SSM — invoke `hyperpod-ssm`.

## Constraints

- Read-only. Do not run, recommend, or print state-mutating commands.
- For any remediation, link to AWS or Slurm docs. The user authorizes and executes.
- IaC-managed cluster (Terraform / CloudFormation / CDK): warn that direct mutation
  drifts the live state from the IaC plan.

Canonical recovery URLs:
[references/slurm-details.md → Authoritative recovery documentation](references/slurm-details.md).

## Prerequisites

- AWS CLI v2, authenticated for the target account and region with permissions:
  - `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`
  - `ssm:StartSession` on the HyperPod-created SSM document
- [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  installed locally.
- `jq` ≥ 1.6.
- `unbuffer` (from the `expect` package). Required — without it `aws ssm start-session`
  returns empty stdout intermittently with `Cannot perform start session: EOF` and every
  check silently misreports. Install: `expect` package on Amazon Linux / RHEL / Debian /
  Ubuntu / macOS. Script exits at prerequisite check if missing.

## Procedure

### Step 1 — Collect inputs

Ask the user for:

1. HyperPod cluster name (not Slurm partition name).
2. AWS region.
3. Optional: a specific Slurm node name.

### Step 2 — Confirm orchestrator

```bash
aws sagemaker describe-cluster --cluster-name <NAME/ARN> --region <REGION> \
  --query 'Orchestrator' --output json
```

If `Orchestrator.Eks` is present, stop. Route per [When NOT to invoke](#when-not-to-invoke).

### Step 3 — Run the diagnostic script

```bash
bash scripts/slurm-diagnose.sh --cluster <NAME> --region <REGION>
# Scope to a node:
bash scripts/slurm-diagnose.sh --cluster <NAME> --region <REGION> --node <SLURM_NODE>
```

Relay the script output to the user verbatim.

### Step 4 — Map findings → docs

For each finding, look up the section in the [decision table](#decision-table) and link
the user to the corresponding AWS / Slurm doc. Do not type out remediation commands.

## Decision table

| Symptom (`sinfo -o "%N %T %30E"` or script finding)         | Section                                                |
| ----------------------------------------------------------- | ------------------------------------------------------ |
| Node state = `down` or `down*`, reason other than below     | [A: Node Down](#a-node-down)                           |
| Node state = `down*`, Reason = `Node unexpectedly rebooted` | [B: Unexpected Reboot](#b-unexpected-reboot)           |
| Jobs `PENDING` with `REASON=Resources` while nodes are idle | [C: Controller State](#c-controller-state)             |
| Jobs stuck `COMPLETING` after node replacement              | [C: Controller State](#c-controller-state)             |
| `scontrol ping` returns `DOWN` for the controller           | [C: Controller State](#c-controller-state)             |
| GRES (GPU) counts incorrect or not released                 | [C: Controller State](#c-controller-state)             |
| `state=fail` issued but no recovery occurred                | [D: Action Reason Mismatch](#d-action-reason-mismatch) |
| Accounting errors or RPC errors mentioning `dbd`            | [C: Controller State](#c-controller-state) (slurmdbd)  |
| `slurm.conf` edited; new partitions or nodes not visible    | [C: Controller State](#c-controller-state) (config)    |
| Job exited on a hardware failure but did not restart        | [E: Auto-resume](#e-auto-resume)                       |

## Defaults

| Behavior             | Default                                                                                            | Override                   |
| -------------------- | -------------------------------------------------------------------------------------------------- | -------------------------- |
| Mode                 | read-only — always; no remediation flag exists                                                     | n/a                        |
| Region               | `$AWS_DEFAULT_REGION`, falling back to `us-east-1`                                                 | `--region <R>`             |
| Scope                | all nodes in `down` / `drain` / `fail` / "unexpectedly rebooted"                                   | `--node <SLURM_NODE_NAME>` |
| Output               | colorized terminal                                                                                 | `--no-color`               |
| SSM target format    | `sagemaker-cluster:<clusterId>_<instanceGroupName>-<instanceId>` (derived)                         | n/a                        |
| Controller discovery | `--controller-group` (if set) → `SlurmConfig.NodeType=Controller` → `provisioning_parameters.json` | `--controller-group <N>`   |

## Error handling

| Failure                                            | Skill behavior                         | Required user action                            |
| -------------------------------------------------- | -------------------------------------- | ----------------------------------------------- |
| `describe-cluster` fails                           | Print AWS error; exit 1                | Fix credentials/region; verify cluster name     |
| Cluster has `Orchestrator.Eks`                     | Exit 1 with pointer to EKS-side skills | Use `hyperpod-node-debugger` or `hyperpod-nccl` |
| `session-manager-plugin` missing / SSM unreachable | `sinfo` returns empty; exit 1          | Install plugin; verify node `InService`         |
| Disk ≥ 95 % full on a `down` node                  | Report finding `disk-full-<node>`      | Refer to AWS troubleshooting docs               |
| Missing `jq` or `aws`                              | Exit 1 at prerequisite check           | Install per [Prerequisites](#prerequisites)     |

---

## A: Node Down

Node is `down` because `slurmd` stopped responding. Causes: `slurmd` crash, disk full,
OOM, network partition, hardware fault.

Script checks: `systemctl is-active slurmd`, `srun -w <NODE> hostname` (RPC layer), disk,
memory.

Link: <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>

If node returns to `down` after a manual resume → escalate to `hyperpod-node-debugger`.

Context: [references/slurm-details.md § A](references/slurm-details.md#-a-node-down--diagnostic-context).

---

## B: Unexpected Reboot

Node is `down*` with Reason `"Node unexpectedly rebooted"` because `slurmd`
re-registered after an out-of-band reboot. Upstream Slurm behavior, not HyperPod.
Node is typically healthy.

Links:

- <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>
- <https://slurm.schedmd.com/scontrol.html> (`state=resume` semantics)

If node reboots again within minutes → escalate to `hyperpod-node-debugger`.

Context: [references/slurm-details.md § B](references/slurm-details.md#-b-unexpected-reboot--diagnostic-context).

---

## C: Controller State

`slurmctld` in-memory state can desync from the on-disk state. A controller restart reloads from `StateSaveLocation` and clears bad caches. User decides and executes.

Restart may help:

| Symptom                                            | Why                                         |
| -------------------------------------------------- | ------------------------------------------- |
| `PENDING` with `REASON=Resources`, idle nodes      | Re-evaluates the queue                      |
| Jobs stuck `COMPLETING` after node replacement     | Controller held a reference to the old node |
| GRES (GPU, EFA) not released after a job ends      | Resource accounting de-synced               |
| Nodes stuck `Unknown` after reboot, `slurmd` is up | Re-registration was not processed           |
| `scontrol ping` times out                          | Controller event loop is hung               |
| Lost connection to `slurmdbd` / RPC errors         | DBD connection wedged                       |

Do NOT restart when:

- HyperPod replacement (`Action:Replace`) in progress on any node — concurrent changes
  fail the replacement.
- Only one compute node is bad — restart `slurmd` on that node.
- `sinfo` and `squeue` are responsive — problem is elsewhere.
- `journalctl -u slurmctld` not reviewed yet — panic / OOM will reproduce.
- `slurm.conf` was just edited — try `scontrol reconfigure` first.

### Folded triggers

- **slurmdbd disconnected** — `sacct` fails, accounting fields show `Unknown`,
  controller log spams `Unable to contact slurmdbd`. Restore `slurmdbd` before
  considering controller restart.
  <https://slurm.schedmd.com/accounting.html> ·
  [details](references/slurm-details.md#slurmdbd-connectivity).
- **Stale config** — `slurm.conf` / `topology.conf` mtime > slurmctld start.
  `scontrol reconfigure` first; restart is fallback.
  <https://slurm.schedmd.com/scontrol.html> ·
  [details](references/slurm-details.md#scontrol-reconfigure-vs-restart).

Restart procedure / what's preserved:

- <https://slurm.schedmd.com/slurmctld.html>
- <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>

Context: [references/slurm-details.md § C](references/slurm-details.md#-c-controller-state--diagnostic-context).

---

## D: Action Reason Mismatch

`scontrol update state=fail reason=...` was issued with a `reason` that does not match
`Action:Reboot` or `Action:Replace` exactly. HyperPod silently ignores anything else.
Script detects near-misses on nodes in `fail` state.

Required strings (case-sensitive, no whitespace, no punctuation):

- `Action:Reboot`
- `Action:Replace`

Link: <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-replace-faulty-instance.html>

Context: [references/slurm-details.md § Action reason-string validation](references/slurm-details.md#action-reason-string-validation).

---

## E: Auto-resume

`--auto-resume=1` is an `srun` step option. It re-runs the step after HMA (the Health
Monitoring Agent) flags a node and Automatic node recovery replaces it.

Why it didn't restart the job:

- Flag on `sbatch` not `srun` — per-step; `sbatch` directives are silently ignored.
- HMA did not flag the node — failure was application/transient, not hardware. Step
  exits as a normal Slurm failure.
- Cluster `NodeRecovery` is `None` — faulty nodes are labeled but not replaced.
- No checkpointing — step restarts from process zero each iteration.
- AMI predates HMA support (released 2025-09-11) — needs AMI / cluster-software update.

Link: <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-auto-resume.html>

Context: [references/slurm-details.md § HyperPod auto-resume](references/slurm-details.md#hyperpod-auto-resume).

---

## Escalation

| Condition                                                       | Next skill                            |
| --------------------------------------------------------------- | ------------------------------------- |
| Node returns to `down` shortly after a manual resume            | `hyperpod-node-debugger` (hardware)   |
| `slurmd` logs contain CUDA / NVIDIA / XID errors                | `hyperpod-node-debugger` § G          |
| Disk full or `/dev/shm` exhausted                               | `hyperpod-node-debugger` § I          |
| Node unreachable via SSM                                        | `hyperpod-ssm`                        |
| Controller restart does not clear `COMPLETING` after 2 attempts | `hyperpod-issue-report` + AWS Support |
