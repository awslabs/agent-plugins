# Slurm Details

Diagnostic context for `hyperpod-slurm-debugger`. Diagnostic-only — do not run,
recommend, or print state-mutating commands. Link to AWS / Slurm docs for remediation.

## Table of contents

- [Authoritative recovery documentation](#authoritative-recovery-documentation)
- [HyperPod auto-resume](#hyperpod-auto-resume)
- [Action reason-string validation](#action-reason-string-validation)
- [§ A: Node down — diagnostic context](#-a-node-down--diagnostic-context)
- [§ B: Unexpected reboot — diagnostic context](#-b-unexpected-reboot--diagnostic-context)
- [§ C: Controller state — diagnostic context](#-c-controller-state--diagnostic-context)
  - [scontrol reconfigure vs restart](#scontrol-reconfigure-vs-restart)
  - [slurmdbd connectivity](#slurmdbd-connectivity)

---

## Authoritative recovery documentation

- HyperPod Slurm troubleshooting:
  <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>
- Replace a faulty Slurm instance:
  <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-replace-faulty-instance.html>
- HyperPod auto-resume:
  <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-auto-resume.html>
- `BatchRebootClusterNodes`:
  <https://docs.aws.amazon.com/cli/latest/reference/sagemaker/batch-reboot-cluster-nodes.html>
- `BatchReplaceClusterNodes`:
  <https://docs.aws.amazon.com/cli/latest/reference/sagemaker/batch-replace-cluster-nodes.html>
- `scontrol(1)`: <https://slurm.schedmd.com/scontrol.html>
- `slurmctld(8)`: <https://slurm.schedmd.com/slurmctld.html>
- `slurm.conf(5)`: <https://slurm.schedmd.com/slurm.conf.html>
- Slurm accounting: <https://slurm.schedmd.com/accounting.html>
- Slurm authentication (munge): <https://slurm.schedmd.com/authentication.html>

---

## HyperPod auto-resume

Three separate features that compose:

- **HMA (Health Monitoring Agent)** — runs hardware checks (NVIDIA SMI, Neuron sysfs,
  EFA) continuously, independent of jobs. Marks faulty nodes for drain.
- **Automatic node recovery** (cluster `NodeRecovery` setting; `Automatic` or `None`) —
  when `Automatic`, replaces drained nodes after their jobs exit.
- **`--auto-resume=1`** (`srun` step option) — re-runs the step after HMA + node
  recovery replace a node in its allocation.

**Auto-resume itself does not run health checks.** HMA does. Auto-resume reacts to
HMA-triggered replacements. The AWS doc's "How auto-resume works" section is misleading
on this point — the authoritative description is in the "How automatic node recovery
and auto-resume work together" section, which states:
_"If the HMA detects a hardware fault, the node is marked for drain regardless of
job-level status. With node automatic recovery enabled, the nodes are automatically
replaced once all the jobs running in the nodes exit. In this scenario, for jobs with
auto-resume enabled, if there is a non-zero exit status in the step, the auto resume
kicks in."_

If HMA does not flag a node, auto-resume does not fire — the step exits as a normal
Slurm failure.

<https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-auto-resume.html>

### Verify auto-resume ran (read-only)

```bash
# Replace events in slurmctld log:
sudo journalctl -u slurmctld --since "2 hours ago" | grep -E 'auto.?resume|Action:Replace|replac'

# Last reason and boot time on the node:
scontrol show node <NODE> | grep -i 'reason\|boot'

# Job-step events from accounting:
sacct -j <JOBID> -o JobID,JobName,State,ExitCode,NodeList,Start,End -X
```

Same `JOBID` after `NodeList` change → auto-resume succeeded.

### Why auto-resume didn't restart

- **Flag on `sbatch` not `srun`** — per-step option; `sbatch` directives ignored.
- **HMA did not flag the node** — auto-resume only reacts to HMA-triggered
  replacements. Inspect `dmesg` and `journalctl -k` for hardware signals (XID, MCE,
  PCIe AER, EFA driver errors). None → not hardware; failure was application or
  transient and auto-resume cannot fire.
- **Cluster `NodeRecovery` is `None`** — HMA labels faulty nodes but nothing replaces
  them. Confirm: `aws sagemaker describe-cluster ... --query NodeRecovery`.
- **AMI predates HMA support** (released 2025-09-11). Script flags this by checking for
  `--auto-resume` in `srun --help`.
- **Concurrent manual `Action:Replace`** racing with the automatic replacement.

---

## Action reason-string validation

HyperPod auto-recovery matches the Slurm node `Reason` field exactly, case-sensitive:

| Intent  | Required reason  |
| ------- | ---------------- |
| Reboot  | `Action:Reboot`  |
| Replace | `Action:Replace` |

Any mismatch is silently ignored. Common near-misses:

- `action:replace` — wrong case
- `Action: Reboot` — extra space after colon
- `Action:Reboot⎵` (where `⎵` is whitespace) — trailing whitespace
- `Action:Reboot.` — trailing punctuation
- `Reboot` / `replace this` — wrong format

Verify (read-only):

```bash
sinfo -o "%N %T %30E" | grep <NODE>
scontrol show node <NODE> | grep -i reason
```

Canonical command form per AWS docs (do not run from this skill — operator-executed):

```bash
scontrol update node=<ip-ipv4> state=fail reason="Action:Reboot"
scontrol update node=<ip-ipv4> state=fail reason="Action:Replace"
```

Re-issue procedure: <https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-hyperpod-resiliency-slurm-replace-faulty-instance.html>

---

## § A: Node down — diagnostic context

`slurmd` stopped responding. Causes: `slurmd` crash/stop, disk full, OOM, network
partition, hardware fault.

### Inspection (read-only)

```bash
# Head node:
sinfo -o "%N %T %30E" | grep -E 'down|drain'
scontrol show node <NODE>           # Reason, LastBusyTime, Boot

# Reachability per layer:
ping <NODE>                          # L3
srun -w <NODE> hostname              # Slurm RPC
ssh <NODE> true                      # SSH (if configured)

# Affected node (via SSM):
systemctl status slurmd
journalctl -u slurmd -n 200 --no-pager
journalctl -xe -n 100 --no-pager     # kernel errors, OOM kills
free -h
df -h
df -h /dev/shm
```

### Findings → docs

| Finding                         | Link                                                                |
| ------------------------------- | ------------------------------------------------------------------- |
| `slurmd` stopped, logs clean    | HyperPod Slurm troubleshooting (Authoritative recovery)             |
| `slurmd` crashing, munge errors | <https://slurm.schedmd.com/authentication.html>                     |
| Disk full                       | HyperPod storage layout (`/opt/sagemaker`, `/opt/dlami/nvme`, FSx)  |
| OOM in `dmesg`                  | Right-size workload — AWS instance-type docs                        |
| Kernel panic / recent reboot    | [§ B: Unexpected reboot](#-b-unexpected-reboot--diagnostic-context) |
| GPU XID / ECC errors in `dmesg` | `hyperpod-node-debugger` § G                                        |

If node returns to `down` after manual recovery → `hyperpod-node-debugger` (hardware).

---

## § B: Unexpected reboot — diagnostic context

`slurmd` re-registered after an out-of-band reboot (kernel panic, watchdog, manual
reboot, HyperPod auto-repair). Slurm marks the node `down*` with reason
`Node unexpectedly rebooted` and refuses scheduling. **Upstream Slurm behavior, not
HyperPod-specific** — protects pending jobs from landing on a node with potentially
corrupt local state (partial checkpoints, half-written scratch).

Node is usually fine. Resume procedure:

- <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>
- <https://slurm.schedmd.com/scontrol.html> (`state=resume` semantics)

If the node loops through reboots → kernel / hardware issue. Inspect `dmesg` and
`journalctl -b -1` (previous boot) before any further action. Route to
`hyperpod-node-debugger`.

---

## § C: Controller state — diagnostic context

`slurmctld` in-memory state desynced from disk-persisted state. Standard restart reloads
from `StateSaveLocation` (typically `/var/spool/slurmctld/` on HyperPod, but
admin-configured — confirm with `scontrol show config | grep StateSaveLocation`).

### What's preserved across a restart

Per [`slurmctld(8)`](https://slurm.schedmd.com/slurmctld.html), without `-c` the restart
preserves running jobs plus node state of `DOWN`, `DRAINED`, and `DRAINING` nodes with
their Reason field.

**Recovered from `StateSaveLocation`:**

- Running jobs (continue executing on compute nodes; reconnect when controller is back).
- Pending queue (`squeue` returns the same queue).
- `DOWN`, `DRAINED`, `DRAINING` node states + Reason field.
- Accounting records (via `slurmdbd`).

**Re-read from `slurm.conf` on startup:**

- Partition definitions, `NodeName` definitions, scheduling parameters.

**Reset (this is what fixes the symptoms):**

- In-memory scheduling decisions and priority calculations.
- GRES / TRES accounting caches.
- Hung RPC connections to compute nodes.
- Stale `REASON=Resources` on pending jobs.
- Stuck `COMPLETING` tracking.

### Pre-restart inspection (read-only)

```bash
scontrol show config | grep StateSaveLocation
STATE=$(scontrol show config | awk -F= '/^StateSaveLocation/ {gsub(/ /,"",$2); print $2; exit}')
sudo ls -la "$STATE"      # should have recent state files
```

If the directory is missing or empty, do NOT restart — recover state file from backup
first. `slurmctld -c` (clean start) purges every job from the controller.

Restart procedure:

- <https://slurm.schedmd.com/slurmctld.html>
- <https://github.com/aws/sagemaker-hyperpod-cluster-setup/blob/troubleshooting-doc-20250917/troubleshoot/index.md>

When-to-restart vs when-not-to: see [SKILL.md § C](../SKILL.md#c-controller-state).

### scontrol reconfigure vs restart

`slurm.conf` / `topology.conf` / `gres.conf` was edited; controller has stale config
in memory. Two reload paths:

**`scontrol reconfigure`** — no downtime. Reloads `slurm.conf` in place. Per
[`scontrol(1)`](https://slurm.schedmd.com/scontrol.html), cannot change daemons'
listening TCP port or `AuthType`; changing `AuthType` requires terminating all Slurm
daemons + commands per [`slurm.conf(5)`](https://slurm.schedmd.com/slurm.conf.html).

**`systemctl restart slurmctld`** — ~5–30s scheduling pause. Required for changes that
`scontrol reconfigure` rejects. In practice operators also restart for structural
changes (adding/removing nodes, `NodeName` changes, topology rewrites) since
reconfigure isn't guaranteed to apply them cleanly.

Pre-reload inspection (read-only):

```bash
# HyperPod installs to /opt/slurm-<version>/etc/, not /etc/slurm/:
CONF=$(scontrol show config | awk -F= '/^SLURM_CONF/ {gsub(/ /,"",$2); print $2; exit}')
ls -la "$CONF"
# After reload, watch for parse errors:
journalctl -u slurmctld -n 50 --no-pager
```

No syntax-check flag exists for `slurmctld` or `slurmdbd`. Errors surface in
`journalctl` after reload.

`scontrol reconfigure` only reloads the controller's view. Compute nodes read their own
copy of `slurm.conf` from disk. If the lifecycle script doesn't push `slurm.conf` to
every node (via shared FSx mount or explicit copy step), node-side `slurmd` runs with
stale config until restarted.

### slurmdbd connectivity

`slurmctld` cannot reach `slurmdbd`. Scheduler keeps running; accounting fails. Symptoms
look like a controller hang but aren't.

**Symptoms:**

- `sacctmgr show stats` returns `Unable to contact slurmdbd` or `Connection refused`.
- `sacct -j <JOBID>` returns `Sockets disabled` or no rows.
- `journalctl -u slurmctld | grep -i dbd` shows repeated reconnect attempts.
- New jobs complete but accounting records never appear in `sacct`.

**Diagnose (read-only):**

```bash
systemctl status slurmdbd
journalctl -u slurmdbd  -n 100 --no-pager
journalctl -u slurmctld -n 100 --no-pager | grep -iE 'dbd|accounting'

# slurmdbd.conf path — HyperPod uses /opt/slurm-<version>/etc/:
SLURMDBD_CONF=$(find /opt/slurm*/etc /etc/slurm -name slurmdbd.conf 2>/dev/null | head -1)
sudo grep -E 'StorageHost|StoragePort|StorageUser' "$SLURMDBD_CONF"

nc -vz <StorageHost> <StoragePort>     # default port 3306
```

**Common causes:**

| Cause                                         | Link                                             |
| --------------------------------------------- | ------------------------------------------------ |
| `slurmdbd` daemon stopped or crashed          | <https://slurm.schedmd.com/accounting.html>      |
| MySQL / MariaDB endpoint unreachable          | Restore SG / VPC route; slurmdbd self-recovers   |
| `slurmdbd.conf` `StoragePass` wrong / rotated | <https://slurm.schedmd.com/slurmdbd.conf.html>   |
| Disk full on slurmdbd host                    | Daemon won't start without log-file write access |
| Schema migration pending after Slurm upgrade  | <https://slurm.schedmd.com/upgrades.html>        |

**Recovery order:**

1. Restore `slurmdbd`. Running jobs are unaffected — no time pressure.
2. Verify with `sacctmgr show stats` (rollup counters, no errors).
3. Only then evaluate whether `slurmctld` itself needs a restart. If `slurmctld`
   recovered the DBD connection on its own, no restart is needed. If the controller log
   still shows stuck DBD-RPC threads, see
   [§ C](#-c-controller-state--diagnostic-context).

If the database is RDS / Aurora / managed, check snapshot windows and maintenance
events — a brief failover can leave `slurmctld` with a wedged connection.
