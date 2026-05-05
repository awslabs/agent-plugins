---
name: hyperpod-slurm-debugger
description: Diagnoses and safely recovers Slurm node-management issues on Amazon SageMaker HyperPod Slurm clusters. Use when a user reports — a Slurm node stuck in down/drain, "Node unexpectedly rebooted" after auto-repair, slurmd not running, jobs stuck PENDING with REASON=Resources while sinfo shows idle nodes, jobs stuck COMPLETING after node replacement, GRES/GPU counts wrong, scontrol ping failing, or slurmctld unresponsive. Also triggers on "drain before reboot", "resume a Slurm node", "recover Slurm after auto-repair", or "replace a faulty Slurm node". Do NOT use for EKS/Kubernetes-orchestrated HyperPod (use hyperpod-node-debugger or hyperpod-nccl), single-node GPU/hardware faults where Slurm is healthy (use hyperpod-node-debugger), or NCCL-specific training hangs (use hyperpod-nccl).
metadata:
  version: "1.0.0"
---

# HyperPod Slurm Debugger

Triage and safely recover Slurm scheduler and node-daemon issues on Amazon SageMaker HyperPod
Slurm clusters. Focused on the three common failure modes:

1. **Node `down` / not responding** — `slurmd` stopped, resource exhaustion, or network.
2. **Node `down*` with reason "Node unexpectedly rebooted"** — `slurmd` didn't re-register after
   an out-of-band reboot (panic, manual reboot, HyperPod auto-repair).
3. **Jobs stuck `PENDING` / `COMPLETING`** — `slurmctld` in-memory state out of sync.

Access runs over **AWS Systems Manager (SSM)** — HyperPod does not expose SSH by default. The
default mode is **read-only inspection**. Every state change requires the explicit `--fix` flag,
and the highest-risk changes (Slurm controller restart, node reboot/replace) are additionally
gated and always announced before execution.

## Important — read before using `--fix`

The AWS documentation recommends using the HyperPod-native recovery path whenever possible:

```bash
# HyperPod-orchestrated reboot (preferred)
scontrol update node=<NODE> state=fail reason="Action:Reboot"

# HyperPod-orchestrated replace (preferred for hardware issues)
scontrol update node=<NODE> state=fail reason="Action:Replace"
```

When you set `reason="Action:Reboot"` or `reason="Action:Replace"` via `scontrol`, HyperPod
detects the annotation and orchestrates the recovery. **While a replacement is in progress, do
not change the node state again or restart `slurmctld`** — concurrent changes can cause
replacement failures. See
[references/slurm-details.md → HyperPod-native recovery](references/slurm-details.md#hyperpod-native-recovery).

The `--fix` mode in this skill handles only the safe, routine cases (re-enable `slurmd`, resume
a node that's already healthy, restart `slurmctld` when it is truly wedged). For anything
beyond that, the skill prints the recommended command and waits for you to run it manually.

## Prerequisites

- AWS CLI v2, authenticated for the target account and region with:
  - `sagemaker:DescribeCluster`, `sagemaker:ListClusterNodes`
  - `ssm:StartSession` on the HyperPod-created SSM document
- [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  installed locally (required for `aws ssm start-session`).
- `jq` ≥ 1.6. The diagnostic script builds SSM payloads with `jq` to avoid shell-injection on
  node names / reasons.
- Ability to execute `scripts/slurm-diagnose-fix.sh` (the file ships with the `+x` bit set).

## Defaults

| Behavior             | Default                                                                    | Override                   |
| -------------------- | -------------------------------------------------------------------------- | -------------------------- |
| Mode                 | **inspect-only** — no state changes                                        | `--fix`                    |
| Region               | `$AWS_DEFAULT_REGION`, falling back to `us-east-1`                         | `--region <R>`             |
| Scope                | all nodes currently `down` / `drain` / marked "unexpectedly rebooted"      | `--node <SLURM_NODE_NAME>` |
| Controller restart   | **never** automatic; announced, requires user to type `yes` at prompt      | n/a                        |
| Output               | colorized terminal                                                         | `--no-color`               |
| SSM target format    | `sagemaker-cluster:<clusterId>_<instanceGroupName>-<instanceId>` (derived) | n/a                        |
| Controller discovery | first `InstanceGroup` whose name matches `/controller\|head/i`, else `[0]` | n/a                        |

## Error Handling

| Failure                                                | Skill behavior                                          | User action                                           |
| ------------------------------------------------------ | ------------------------------------------------------- | ----------------------------------------------------- |
| `describe-cluster` fails                               | Prints AWS error, exits 1                               | Fix credentials/region; verify cluster name           |
| Cluster has `Orchestrator.Eks`                         | Exits 1 with pointer to EKS-side skills                 | Use `hyperpod-node-debugger` or `hyperpod-nccl`       |
| `session-manager-plugin` missing / SSM unreachable     | `sinfo` returns empty → exits 1, prints the raw command | Install plugin; verify node `InService`               |
| Disk ≥ 95 % full on a `down` node                      | Skipped by `--fix`, reported as `disk-full-<node>`      | Clean up per references/slurm-details.md, then re-run |
| `slurmd` restart succeeds but Slurm still shows `down` | Warns, no further auto-fix                              | Hardware suspected — use `hyperpod-node-debugger`     |
| Controller restart prompt declined                     | Prints the exact command and escalation path            | Run manually when confident the cluster is idle       |
| Missing `jq` or `aws`                                  | Script exits 1 at prereq check                          | Install per Prerequisites                             |

## Examples

**Example 1 — two nodes stuck `down*` after auto-repair**

> "My HyperPod Slurm cluster `ml-research` in `us-west-2` just did an auto-repair and two
> nodes are stuck `down*` with reason `Node unexpectedly rebooted`. Can you check and fix
> them?"

The skill runs the script in inspect mode, identifies both nodes under Section B, confirms
`slurmd` is running on each via SSM, then re-runs with `--fix` to `systemctl enable slurmd` +
`scontrol update state=resume` on each.

### Example 2 — pending queue with idle nodes

> "Eight jobs are stuck `PENDING` with `REASON=Resources` on my Slurm HyperPod cluster
> `llm-train`, but `sinfo` shows the partition idle."

The skill classifies this as `stuck-pending-with-idle-nodes` (Section C), prints the
recommended `slurmctld` restart command and the expected preservation behavior, and — if the
user confirms at the prompt — runs `systemctl restart slurmctld` on the controller. Running
jobs, the pending queue, and node states are recovered from `StateSaveLocation`.

---

## Step 1: Collect information

Ask the user for:

- **HyperPod cluster name** (not the Slurm partition name).
- **AWS region**.
- **A specific Slurm node name**, if one is known-bad (optional — the script auto-detects).
- Whether the user has confirmed this is a HyperPod _Slurm_ cluster:

  ```bash
  aws sagemaker describe-cluster --cluster-name <NAME> --region <REGION> \
    --query 'Orchestrator' --output json
  ```

  If `Orchestrator.Eks` is set, stop — route to `hyperpod-nccl` or `hyperpod-node-debugger`.

The script auto-discovers the controller node from `DescribeCluster.InstanceGroups`.

## Step 2: Run diagnostics

```bash
# Inspect only — safe, no state changes.
# Collects sinfo, scontrol show nodes, squeue, and per-node slurmd status for
# any node currently down / drain / unknown.
bash scripts/slurm-diagnose-fix.sh --cluster <NAME> --region <REGION>

# Scope to a specific Slurm node:
bash scripts/slurm-diagnose-fix.sh --cluster <NAME> --region <REGION> --node <SLURM_NODE>

# Apply safe auto-fixes (see "What gets auto-fixed" below). For slurmctld restart,
# the script always prompts before acting.
bash scripts/slurm-diagnose-fix.sh --cluster <NAME> --region <REGION> --fix
```

The script prints a decision tree mapping the detected symptom to one of the three sections
below.

## Step 3: Match symptom → section

| Symptom from `sinfo -o "%N %T %30E"`                        | Section                                      |
| ----------------------------------------------------------- | -------------------------------------------- |
| Node state = `down` / `down*`, any reason other than below  | [A: Node Down](#a-node-down)                 |
| Node state = `down*`, Reason = `Node unexpectedly rebooted` | [B: Unexpected Reboot](#b-unexpected-reboot) |
| Jobs `PENDING` with `REASON=Resources` despite idle nodes   | [C: Controller State](#c-controller-state)   |
| Jobs stuck `COMPLETING` after node replacement              | [C: Controller State](#c-controller-state)   |
| `scontrol ping` returns `DOWN` for the controller           | [C: Controller State](#c-controller-state)   |
| GRES (GPU) counts wrong or not released after a job ends    | [C: Controller State](#c-controller-state)   |

---

## A: Node Down

Slurm marks a node `down` when `slurmd` stops responding to the controller. Root causes (in
order of frequency): `slurmd` crashed/stopped, disk full or OOM, network partition, or hardware
failure (route to `hyperpod-node-debugger` Section G).

The script inspects reachability and daemon status, then `--fix` restarts `slurmd` and resumes
the node. If the node flaps, use HyperPod-native reboot/replace.

Full diagnostic and recovery procedures:
[references/slurm-details.md § A](references/slurm-details.md#-a-node-down--recovery-procedures).

---

## B: Unexpected Reboot

Slurm marks a node `down*` with Reason `"Node unexpectedly rebooted"` when it re-registers
after an out-of-band reboot (kernel panic, watchdog, manual reboot, HyperPod auto-repair).
This is standard upstream Slurm protection — the controller refuses to schedule until an admin
confirms the node is healthy.

**The node is usually fine.** The script's `--fix` mode ensures `slurmd` is enabled/running,
then resumes the node. If the node reboots again shortly after, route to
`hyperpod-node-debugger` (hardware).

Full recovery and prevention procedures:
[references/slurm-details.md § B](references/slurm-details.md#-b-unexpected-reboot--recovery-procedures).

---

## C: Controller State

`slurmctld` can get into a bad in-memory state whose symptoms look like scheduler bugs —
PENDING jobs with idle nodes, stuck COMPLETING, wrong GRES counts. A **controller restart
preserves the cluster's important state** (running jobs, pending queue, node state) because
those are re-read from `StateSaveLocation` on disk, and only the in-memory caches are cleared.

### When a restart helps

| Symptom                                                       | Why restart helps                                  |
| ------------------------------------------------------------- | -------------------------------------------------- |
| `PENDING` with `REASON=Resources`, `sinfo` shows idle nodes   | Re-evaluates the queue                             |
| Jobs stuck `COMPLETING` after node replacement                | Controller was holding a reference to the old node |
| GRES (GPU, EFA) not released after a job ends                 | Resource accounting de-synced                      |
| Nodes stuck `Unknown` after reboot even though `slurmd` is up | Re-registration wasn't processed                   |
| `scontrol ping` times out                                     | Controller event loop is hung                      |
| Lost connection to `slurmdbd` / RPC errors in controller logs | Database connection wedged                         |

### When NOT to restart

- While a HyperPod replacement (`Action:Replace`) is in progress on any node. AWS docs: _"Avoid
  changing the node state or restarting the Slurm controller during the operation."_
- When only one compute node is misbehaving — restart `slurmd` on that node instead.
- When `sinfo` / `squeue` are responsive and show expected state — the problem is elsewhere.
- Before checking `journalctl -u slurmctld` for panics or OOM patterns — restart will just
  reproduce them.
- Right after editing `slurm.conf` — try `scontrol reconfigure` first; restart is the fallback.

Full restart procedures (standard and force-kill):
[references/slurm-details.md § C](references/slurm-details.md#-c-controller-restart-procedures).

---

## What gets auto-fixed by `--fix`

Safe, narrowly-scoped actions only. Anything higher-risk is announced and requires an
interactive confirmation.

| Detected condition                                              | Automatic action                                            |
| --------------------------------------------------------------- | ----------------------------------------------------------- |
| `slurmd` inactive on a `down` node                              | `systemctl enable slurmd && systemctl start slurmd` via SSM |
| Node in `down*` with Reason `Node unexpectedly rebooted`        | `scontrol update nodename=<N> state=resume`                 |
| `slurmd` was restarted and is now active                        | `scontrol update nodename=<N> state=resume`                 |
| `scontrol ping` fails **and** logs show a hang or RPC timeout   | Prompts; on `yes` runs `systemctl restart slurmctld`        |
| Jobs stuck `COMPLETING` > 10 min after a known node replacement | Prompts; on `yes` runs `systemctl restart slurmctld`        |

## What requires escalation (script prints the next skill)

| Condition                                                      | Next skill                            |
| -------------------------------------------------------------- | ------------------------------------- |
| Node flaps back to `down` within 5 min of resume               | `hyperpod-node-debugger` (hardware)   |
| `slurmd` logs show CUDA / NVIDIA / XID errors                  | `hyperpod-node-debugger` § G          |
| Disk full or `/dev/shm` exhausted                              | `hyperpod-node-debugger` § I          |
| Node unreachable via SSM                                       | `hyperpod-ssm`                        |
| Controller restart doesn't clear `COMPLETING` after 2 attempts | `hyperpod-issue-report` + AWS Support |
