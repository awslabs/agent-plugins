---
name: hyperpod-mfu-debugger
description: >
  Diagnose MFU (Model FLOPs Utilization) degradation in distributed GPU
  and Trainium training on Amazon SageMaker HyperPod (Slurm and EKS).
  Walks through Phase 0 context, Phase 1 decision-tree triage, and
  Phase 2 deep dive into one of seven root causes: code regression,
  CUDA or NCCL or OOM errors, hardware straggler, thermal or memory or
  data-pipeline issues, periodic checkpoint dips, network variance, or
  configuration tuning. Runs diagnostic commands via Systems Manager
  and interprets the output with the user. Use when someone reports
  MFU drops, training slowdowns, GPU underutilization, step-time
  increases, stragglers, or throughput regressions on HyperPod, even
  if "MFU" is not said explicitly. Do not use for cluster-creation
  failures (hyperpod-cluster-debugger),
  single-node faults without MFU symptoms (hyperpod-node-debugger),
  NCCL hangs (hyperpod-nccl), Slurm node-state management
  (hyperpod-slurm-debugger), or uneven-NCCL, FSx, or GPU-failure
  triage (hyperpod-performance-debugger).
metadata:
  version: "1.0.0"
---

# Debug MFU Degradation on Amazon SageMaker HyperPod

Structured workflow for diagnosing MFU degradation. Walk each phase
with the user: run, interpret, decide. Do not skip phases. Do not take
state-changing actions without explicit confirmation.

## Prerequisites

| Requirement                                          | Purpose                                                                      |
| ---------------------------------------------------- | ---------------------------------------------------------------------------- |
| `hyperpod-ssm` skill                                 | All on-node commands (`get-cluster-info.sh`, `list-nodes.sh`, `ssm-exec.sh`) |
| `hyperpod-version-checker` skill                     | Detect driver/CUDA/NCCL/EFA/OFI drift across nodes                           |
| `hyperpod-issue-report` skill                        | Bulk diagnostic collection (recommended)                                     |
| AWS CLI v2, authenticated for target account/Region  | SSM, EKS access                                                              |
| `kubectl`                                            | EKS clusters only                                                            |
| `nvidia-smi`                                         | Preinstalled on HyperPod GPU DLAMIs                                          |
| `py-spy`                                             | Python stack capture. `pip install py-spy` if missing                        |
| [`nccl-tests`](https://github.com/NVIDIA/nccl-tests) | Cross-node bandwidth benchmarks                                              |
| [NVIDIA DCGM](https://github.com/NVIDIA/DCGM)        | `dcgmi` diagnostics, `dcgm-exporter` for monitoring                          |
| `neuron-top`, `neuron-monitor`                       | Trainium instances (trn1, trn2) in place of `nvidia-smi`                     |

## Defaults

Apply these when the user does not specify:

- **Triage sampling**: 2–3 nodes (suspected slow + healthy baseline).
- **Fail-slow stack capture**: 5 snapshots at 10-second intervals.
- **Post-fix benchmark**: ≥100 training steps.
- **Anomaly threshold**: metric must deviate for several consecutive
  minutes; 1–2-second spikes are jitter.
- **State-changing actions**: diagnose only. Never drain, cordon,
  evict, reboot, or restart without explicit approval. Quote the
  command and wait.
- **MFU baseline**: Phase 0 table. Flag < 25% as "seriously wrong."
- **Region/cluster**: ask, or fall back to `aws configure get region`
  and state the value used.

## Error Handling

- **SSM access denied / node unreachable**: report the failing target,
  continue on reachable nodes.
- **`hyperpod-ssm` not installed**: tell the user. Do not substitute
  raw `aws ssm send-command` unless asked.
- **Tool missing on node** (`py-spy`, `dcgmi`, `nccl-tests`): report,
  offer the install command, wait for approval. Do not auto-install.
- **Ambiguous orchestrator**: ask. `sinfo` and `kubectl describe node`
  are not interchangeable.
- **No MFU baseline**: ask once, then use the Phase 0 table and state
  which value was applied.
- **Trainium vs GPU mismatch**: on trn1/trn2 use `neuron-top` and
  `neuron-monitor`; skip `nvidia-smi`. Flag if context implied GPUs.
- **Multiple failure modes**: rank by likely impact, work the top
  item first with approval.

## Examples

**1. Sudden drop.** "Our p5 cluster was at 48% MFU, overnight it fell
to 22%. Nothing redeployed. Cluster `llama3-70b-prod`, us-west-2."
→ Phase 0 confirms p5 (H100, 45–55% baseline) and "no code change."
Phase 1 routes to **2C** (step-function drop). Phase 2 compares
per-rank step times, sweeps 2–3 nodes, identifies the outlier,
recommends drain-and-replace after approval.

**2. Consistently low.** "MFU has been ~18% since day one on our p4d
cluster. Normal?" → Phase 0 flags 18% as below the 40–55% multi-node
dense baseline. Phase 1 routes to **2G**. Phase 2 captures a
single-step PyTorch Profiler trace, walks the high-impact checklist
(Flash Attention, all-reduce overlap, TP placement, BF16).

## Safety and Execution Model

Commands run on a live training cluster via the `hyperpod-ssm` skill,
which invokes AWS Systems Manager `AWS-RunShellScript` under the
node's SSM instance profile as root. Every call is logged to
CloudTrail.

Three command categories:

| Category           | Safe during training | Examples                                                                                     |
| ------------------ | -------------------- | -------------------------------------------------------------------------------------------- |
| Read-only          | Yes                  | `nvidia-smi --query-gpu=…`, `dmesg -T`, `fi_info -p efa`, `df -h`, `iostat`, `free -h`       |
| Process inspection | With care            | `py-spy dump`, `gdb -p` — brief `ptrace` pause; may trip the NCCL watchdog                   |
| State changing     | No                   | `nvidia-smi -pl`, `-lgc`; `scontrol update state=drain`; `kubectl cordon`; `dcgmi diag -r 4` |

Every state-changing command in the reference files is marked
**Approval required** with a paired revert. Present and wait for
explicit confirmation; approval for one step does not carry over.

Sensitive data: training logs can contain dataset paths and
identifiers — share only relevant lines. Process command lines in
`nvidia-smi` / `dmesg` can reveal model details; trim before sharing.

Input validation: quote paths, targets, and cluster names when
interpolating into SSM payloads — they execute as a remote shell.

---

## Accessing Nodes

All on-node work goes through `hyperpod-ssm`. Resolve cluster metadata
once per session, then use `ssm-exec.sh`:

```bash
scripts/get-cluster-info.sh <CLUSTER_NAME> --region <REGION>
scripts/list-nodes.sh        <CLUSTER_NAME> --region <REGION>

scripts/ssm-exec.sh --target "sagemaker-cluster:<CLUSTER_ID>_<GROUP>-<INSTANCE_ID>" \
  '<command>' --region <REGION>
```

EKS also needs `kubectl`:

```bash
aws eks update-kubeconfig --name <EKS_CLUSTER_NAME> --region <REGION>
kubectl get pods -A -o wide
kubectl describe node <NODE_NAME>
```

Use `hyperpod-issue-report` for cluster-wide snapshots to S3, and
`hyperpod-version-checker` to detect driver/CUDA/NCCL/EFA/OFI drift.

---

## Phase 0: Gather Context

Ask only for what is not already in the conversation:

1. **Cluster name/ARN and Region** — required for SSM.
2. **Orchestrator** — Slurm or EKS.
3. **Recent changes** — code, config, node replacement, AMI, deps,
   or none.
4. **Current and expected MFU**. If none provided, use:

   | Setup                         | Expected MFU    |
   | ----------------------------- | --------------- |
   | Single-node dense, well tuned | 55–65%          |
   | Multi-node dense, well tuned  | 40–55%          |
   | Multi-node MoE                | 30–45%          |
   | Trainium (any topology)       | 35–50%          |
   | Below 25%                     | Seriously wrong |

5. **Pattern** — sudden drop, gradual decline, periodic dips, high
   variance, or consistently low.
6. **Instance type** — p4d/p4de (A100), p5 (H100, EFAv2),
   p5e (H200, EFAv2), p5en (H200, EFAv3/Nitro v5), trn1/trn2.
7. **Parallelism** — TP, PP, DP sizes; sharding (ZeRO-1/2/3, FSDP).
8. **Errors** — CUDA, NCCL timeouts, OOM, Xid in logs/`dmesg`.

Then resolve SSM:

```bash
scripts/get-cluster-info.sh <CLUSTER_NAME> --region <REGION>
scripts/list-nodes.sh        <CLUSTER_NAME> --region <REGION>
```

---

## Phase 1: Triage

```
MFU degradation
├─ Recent code/config change?              YES → 2A
├─ Explicit errors (CUDA/NCCL/OOM/Xid)?    YES → 2B
├─ Pattern?
│  ├─ Sudden step-function drop            → 2C
│  ├─ Gradual decline (hours)              → 2D
│  ├─ Periodic dips                        → 2E
│  ├─ High step-time variance              → 2F
│  └─ Consistently low from start          → 2G
└─ Persists across job restarts?
   YES → hardware or persistent misconfig
   NO  → transient; restart with monitoring
```

Initial sweep on 2–3 nodes (one suspect, one healthy):

```bash
nvidia-smi
nvidia-smi --query-gpu=index,temperature.gpu,clocks.current.sm,clocks.max.sm,\
power.draw,power.limit,pcie.link.width.current,pcie.link.width.max,\
ecc.errors.uncorrected.volatile.total,ecc.errors.corrected.volatile.total,\
memory.used,memory.total --format=csv
dmesg -T | grep -iE 'xid|error|fault|nccl|efa|pcie|ecc' | tail -30
free -h
df -h
fi_info -p efa 2>/dev/null | head -5
```

Route based on findings:

| Finding                            | Meaning                         | Route |
| ---------------------------------- | ------------------------------- | ----- |
| GPU temperature > 88 °C (one node) | Thermal throttle (H100 SW)      | 2D    |
| SM clock < max (one node)          | Frequency throttle / clock lock | 2C    |
| Uncorrected ECC > 0                | Memory corruption               | 2B    |
| PCIe width x8 (max x16)            | PCIe link degradation           | 2C    |
| Xid in `dmesg`                     | GPU hardware fault              | 2B    |
| Host swap > 0                      | Host memory pressure            | 2D    |
| Disk > 90% full                    | Storage bottleneck              | 2E    |
| EFA absent or wrong count          | Network misconfiguration        | 2F    |
| All output healthy and identical   | Likely configuration            | 2G    |

Multiple matches: take the higher-severity row first.

---

## Phase 2: Deep Dive

Load only the step file matching the triage result. Each is
self-contained and footer-links to adjacent paths.

| Route | Problem                          | File                                |
| ----- | -------------------------------- | ----------------------------------- |
| 2A    | Code or configuration regression | `references/steps/2a-regression.md` |
| 2B    | CUDA, NCCL, or OOM errors        | `references/steps/2b-errors.md`     |
| 2C    | Hardware failure or straggler    | `references/steps/2c-straggler.md`  |
| 2D    | Thermal, memory, or data         | `references/steps/2d-gradual.md`    |
| 2E    | Periodic dips                    | `references/steps/2e-periodic.md`   |
| 2F    | Network variance                 | `references/steps/2f-network.md`    |
| 2G    | Configuration tuning             | `references/steps/2g-tuning.md`     |

---

## Phase 3: Validate and Monitor

After a fix:

1. **Benchmark** ≥ 100 steps; fewer is noise.
2. **Verify correctness** — loss trajectory unchanged. A faster
   divergent run is a regression.
3. **Monitor** — DCGM Exporter + Prometheus + Grafana for GPU metrics
   (temperature, clocks, ECC, utilization, power); per-rank step-time
   logging for stragglers; alert on > 3 σ from a 100-step rolling
   mean, sustained for several minutes.
4. **Snapshot** — `hyperpod-issue-report` periodically and after every
   incident.

---

## MFU Quick Reference

See [references/mfu-quick-ref.md](references/mfu-quick-ref.md) for the MFU formula, instance specs (TFLOPS, EFA bandwidth, NVLink), baseline expectations, and source references.

---

## Reference Files

Load only the file matching the current phase — see the Phase 2 table above.
