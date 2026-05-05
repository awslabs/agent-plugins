# Slurm Details

Supplementary procedures for `hyperpod-slurm-debugger`. Read this when SKILL.md points here
for deeper context or when you want to run a step manually.

## Table of contents

- [HyperPod-native recovery](#hyperpod-native-recovery)
- [Node down — full diagnostic playbook](#node-down--full-diagnostic-playbook)
- [Disk cleanup before resume](#disk-cleanup-before-resume)
- [Node unexpectedly rebooted — why Slurm protects you](#node-unexpectedly-rebooted--why-slurm-protects-you)
- [Controller restart — what's preserved vs reset](#controller-restart--whats-preserved-vs-reset)
- [When NOT to restart `slurmctld`](#when-not-to-restart-slurmctld)
- [Node name → instance ID](#node-name--instance-id)
- [Prevention checklist](#prevention-checklist)
- [Quick command reference](#quick-command-reference)

---

## HyperPod-native recovery

AWS provides two equivalent paths for rebooting or replacing a HyperPod node: the
`BatchRebootClusterNodes` / `BatchReplaceClusterNodes` APIs, or `scontrol update` with an
`Action:*` reason string that HyperPod recognises. Both trigger the same underlying recovery
workflow.

### Reboot

```bash
# Via scontrol (from the head node — requires Slurm access):
sudo scontrol update node=<NODE> state=fail reason="Action:Reboot"

# Via the API (from anywhere with AWS credentials):
aws sagemaker batch-reboot-cluster-nodes \
  --cluster-name <CLUSTER_NAME_OR_ARN> \
  --region <REGION> \
  --node-ids i-0123456789abcdef0 i-0fedcba9876543210
```

Use reboot for transient or software problems — system hangs, memory leaks, hung processes,
kernel updates, GPU-driver state to clear.

### Replace

```bash
# Via scontrol:
sudo scontrol update node=<NODE> state=fail reason="Action:Replace"

# Via the API:
aws sagemaker batch-replace-cluster-nodes \
  --cluster-name <CLUSTER_NAME_OR_ARN> \
  --region <REGION> \
  --node-ids i-0123456789abcdef0
```

Replace provisions fresh hardware with the same AMI, same configuration, and the same host
name, but **everything on local storage is lost** — instance-store volumes, anything on `/`
that isn't on a shared FSx or persistent EBS volume. A replace can take several minutes
depending on capacity and lifecycle-script runtime.

When you run the `scontrol update … state=fail reason="Action:Replace"` form, Slurm first
waits for running jobs on the node to finish, then HyperPod replaces the instance and Slurm
re-registers it with the same host name. **While the replacement is in progress, do not
change the node state again and do not restart `slurmctld`** — concurrent changes can cause
the replacement to fail.

If `auto-resume` is enabled on a job (`srun --auto-resume=1`), HyperPod always replaces nodes
on hardware failures rather than rebooting.

### Force-down (last resort)

If a node is stuck in `fail` indefinitely and neither reboot nor replace progresses:

```bash
sudo scontrol update node=<NODE> state=down reason="Action:Replace"
```

This is the documented escape hatch. It **force-kills every job on the node** — you lose any
unsaved progress. Use only after AWS Support has advised it, or after exhausting the
non-destructive options.

---

## Node down — full diagnostic playbook

The script automates these steps; use this list if you're debugging manually or want to
understand what's being checked.

1. **Get node state and reason:**

   ```bash
   sinfo -N -l                          # per-node detail
   sinfo -o "%N %T %30E"                # concise state + reason
   scontrol show node <NODE>            # Reason, LastBusyTime, Boot, CfgTRES
   ```

2. **Check the HyperPod-side instance view:**

   ```bash
   aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
     --query 'ClusterNodeSummaries[?contains(PrivateDnsName, `<NODE>`)]'
   ```

3. **Test reachability at each layer — isolates what is broken:**

   ```bash
   ping <NODE>                          # L3 / ICMP
   ssh  <NODE> true                     # SSH (if configured)
   srun -w <NODE> hostname              # Slurm RPC
   ```

   - Ping OK, Slurm fails → `slurmd` down, or munge auth broken.
   - Ping fails → network or security-group issue.

4. **On the node (via SSM):**

   ```bash
   sudo systemctl status slurmd
   sudo journalctl -u slurmd -n 200 --no-pager
   sudo journalctl -xe -n 100 --no-pager   # kernel errors, OOM kills
   free -h
   df -h                                # disk full?
   df -h /dev/shm                       # shared-memory exhaustion?
   ```

5. **Map what you found to a fix:**

   | Finding                                    | Fix                                                          |
   | ------------------------------------------ | ------------------------------------------------------------ |
   | `slurmd` stopped, logs look clean          | `systemctl start slurmd` → `scontrol ... resume`             |
   | `slurmd` keeps dying, munge errors in logs | Restart `munge`, then `slurmd`                               |
   | Disk full                                  | See [Disk cleanup](#disk-cleanup-before-resume)              |
   | OOM in `dmesg`                             | Right-size the workload, or larger instance                  |
   | Kernel panic / recent reboot               | See [Section B in SKILL.md](../SKILL.md#b-unexpected-reboot) |
   | Hardware errors (GPU XID, ECC) in `dmesg`  | `hyperpod-node-debugger` § G                                 |

## Disk cleanup before resume

If `df -h /` shows the root volume full, clean up **before** restarting `slurmd` — otherwise it
refuses to start or dies again immediately.

HyperPod's default root volume is often small relative to container image and checkpoint
workloads. For anything larger than the root volume, write to `/opt/sagemaker` (persistent
EBS) or `/opt/dlami/nvme` (instance-store) instead of `/`, or attach a shared FSx mount.
See `hyperpod-node-debugger` § I.

```bash
# Identify the culprit:
sudo du -h --max-depth=1 / 2>/dev/null | sort -hr | head -20
sudo du -sh /var/log/* 2>/dev/null      | sort -hr | head -10
sudo du -sh /tmp/*     2>/dev/null      | sort -hr | head -10

# Safe cleanups:
sudo rm -f /var/log/*.log.* /var/log/*/*.gz /var/log/*.[0-9] /var/log/*/*.[0-9]
sudo journalctl --vacuum-time=2d

# Only if no active training / runtime has open files in these paths:
sudo rm -rf /tmp/* /var/tmp/*

# Distro-specific:
sudo apt-get clean               # Ubuntu / Debian
docker system prune -af          # only if Docker is idle on this node
```

## Node unexpectedly rebooted — why Slurm protects you

When a node reboots out-of-band (kernel panic, hardware watchdog, manual `reboot`, HyperPod
auto-repair), the controller notices the boot time changed the moment `slurmd` re-registers.
Slurm marks the node `down*` with reason `Node unexpectedly rebooted` and refuses scheduling.
This is **upstream Slurm behaviour, not HyperPod-specific** — it protects pending jobs from
landing on a node whose local state may have been corrupted (partial checkpoints on
`/opt/dlami/nvme`, half-written scratch files).

To acknowledge the node is healthy and resume it:

```bash
# On node: make sure slurmd will stay up across boots
sudo systemctl is-enabled slurmd || sudo systemctl enable slurmd
sudo systemctl is-active  slurmd || sudo systemctl start  slurmd

# On head node:
sudo scontrol update nodename=<NODE> state=resume
```

If the node reboots again shortly after — or loops through reboots — it's hardware or a
kernel panic, not a Slurm issue. Check `dmesg` and `journalctl -b -1` (previous boot) before
resuming again.

## Controller restart — what's preserved vs reset

A standard `systemctl restart slurmctld` reloads the controller from its on-disk state at
`StateSaveLocation` (often `/var/spool/slurm/ctld/` on HyperPod). The `slurmctld(8)` man page
confirms this behaviour: without the `-c` flag, "previously running jobs will be preserved
along with node State of DOWN, DRAINED and DRAINING nodes".

**Preserved:**

- Running jobs — they continue executing on compute nodes and reconnect when the controller
  comes back up.
- Pending job queue — `squeue` returns the same queue.
- Node states for `DOWN`, `DRAINED`, `DRAINING` nodes, including the Reason field.
- Accounting records (via `slurmdbd`).
- Partition definitions (re-read from `slurm.conf`).

**Reset — which is exactly what fixes the bad-cache symptoms:**

- In-memory scheduling decisions and priority calculations.
- GRES / TRES accounting caches.
- Hung RPC connections to compute nodes.
- Stale `REASON=Resources` annotations on pending jobs.
- Stuck `COMPLETING` tracking.

Verify the state directory is intact _before_ a force-kill restart:

```bash
scontrol show config | grep StateSaveLocation
sudo ls -la /var/spool/slurm/ctld/       # should have recent files
```

If the directory is missing or empty, do **not** restart — recover the state file from backup
first. `slurmctld -c` (clean start) purges every job from the controller's view.

## When NOT to restart `slurmctld`

Restart is cheap but not free. Skip it when:

- A HyperPod replacement (`Action:Replace`) is currently in progress on any node. AWS
  documents that concurrent controller restarts can cause the replacement to fail.
- A single compute node is misbehaving — restart `slurmd` on that node. Restarting `slurmctld`
  affects every node.
- `sinfo` / `squeue` respond and show expected state — the problem is elsewhere (network,
  quota, job script).
- You haven't read `journalctl -u slurmctld` yet — if there's a panic or OOM-kill pattern,
  restart will reproduce it.
- The user just edited `slurm.conf` — try `scontrol reconfigure` first; restart is the fallback.

## Node name → instance ID

HyperPod Slurm nodes are named by private IP (`ip-10-1-123-45`), but the `batch-reboot-cluster-nodes`,
`batch-replace-cluster-nodes`, and SSM APIs need the EC2 instance ID.

### Option 1 — from the head node's resource config (fastest, one node)

```bash
NODE="ip-10-1-123-45"
IP=$(echo "$NODE" | sed 's/ip-//; s/-/./g')
sudo python3 - <<'PY'
import json, os
d = json.load(open('/opt/ml/config/resource_config.json'))
ip = os.environ['IP']
for g in d.get('InstanceGroups', []):
    for i in g.get('Instances', []):
        if i.get('CustomerIpAddress') == ip:
            print(i.get('InstanceId'), g.get('Name'))
PY
```

### Option 2 — AWS API (works from anywhere)

```bash
aws sagemaker list-cluster-nodes --cluster-name <C> --region <R> \
  --query "ClusterNodeSummaries[?starts_with(PrivateDnsName, '${NODE}.')].{ID:InstanceId,Group:InstanceGroupName}" \
  --output table
```

The DNS suffix is `<region>.compute.internal` in most regions and `ec2.internal` in
`us-east-1`.

### Option 3 — bulk lookup (large clusters, recurring operations)

Use the [`dump_cluster_nodes_info.py`](https://github.com/aws-samples/awsome-distributed-training/blob/main/1.architectures/5.sagemaker-hyperpod/tools/dump_cluster_nodes_info.py)
helper from `aws-samples/awsome-distributed-training` to dump everything to CSV once, then
grep it:

```bash
python3 dump_cluster_nodes_info.py --cluster-name <C>
grep "10.1.123.45" cluster_nodes_info.csv
```

## Prevention checklist

- **Enable `slurmd` on boot on every node.** This single setting prevents most "unexpected
  reboot" recoveries from ever being needed:

  ```bash
  sudo systemctl enable slurmd
  ```

  The default HyperPod Slurm lifecycle script does this; re-verify if you've customised it.

- **Always drain before an intentional reboot:**

  ```bash
  sudo scontrol update nodename=<N> state=drain reason="Planned reboot"
  sudo scontrol update node=<N>     state=fail  reason="Action:Reboot"
  # After the node comes back and slurmd is running:
  sudo scontrol update nodename=<N> state=resume
  ```

- **Back up `slurm.conf` and `topology.conf`** before edits. The config reload path can be
  fragile around topology changes.

- **Monitor `slurmctld` memory.** Large clusters (> 200 nodes) can drive controller memory
  up over time; restart during maintenance windows before it OOMs during a job.

- **Don't over-automate `state=resume`.** If a hook auto-resumes a flapping node, you'll mask
  a real hardware problem. The script's `--fix` mode only resumes after confirming `slurmd`
  is actually running on the node.

- **Use `--auto-resume=1` on long-running training jobs.** When HyperPod detects a hardware
  failure on a job with auto-resume, it replaces the node and re-runs the job step from the
  last checkpoint.

## Quick command reference

### Inspection (read-only, always safe)

```bash
sinfo                                # cluster summary
sinfo -N -l                          # per-node, long format
sinfo -o "%N %T %30E"                # state + reason (best for triage)
scontrol show node <NODE>            # full node detail
scontrol show job <JOBID>            # why a job is pending / completing
scontrol ping                        # controller health
squeue                               # running + pending jobs
squeue -o "%i %T %r %N"              # job state + reason + node
journalctl -u slurmd    -n 200       # node daemon logs
journalctl -u slurmctld -n 200       # controller logs
```

### State changes (require sudo, change cluster behaviour)

```bash
# Slurm daemons on a compute node (via SSM):
sudo systemctl status  slurmd
sudo systemctl restart slurmd
sudo systemctl enable  slurmd

# Controller on head node — read "When NOT to restart" before running:
sudo systemctl restart slurmctld
sudo pkill -9 slurmctld && sudo systemctl start slurmctld   # only if truly hung

# Node state on head node:
sudo scontrol update nodename=<N> state=drain reason="..."
sudo scontrol update nodename=<N> state=resume
sudo scontrol reconfigure                    # reload slurm.conf without restart

# HyperPod-native recovery (preferred for reboot/replace):
sudo scontrol update node=<N> state=fail reason="Action:Reboot"
sudo scontrol update node=<N> state=fail reason="Action:Replace"

# Or the equivalent APIs:
aws sagemaker batch-reboot-cluster-nodes  --cluster-name <C> --region <R> --node-ids <ID>
aws sagemaker batch-replace-cluster-nodes --cluster-name <C> --region <R> --node-ids <ID>
```

---

## § A: Node Down — recovery procedures

These are the detailed recovery steps referenced from SKILL.md Section A.

**Inspect** (the script does this automatically):

```bash
# On the head node:
sinfo -o "%N %T %30E" | grep -E 'down|drain'
scontrol show node <NODE>           # Reason, LastBusyTime, Boot

# Test each layer — isolates what is broken:
ping <NODE>                          # L3
srun -w <NODE> hostname              # Slurm RPC
ssh <NODE> true                      # SSH (only if keys are configured)

# On the affected node (via SSM):
sudo systemctl status slurmd
sudo journalctl -u slurmd -n 200 --no-pager
free -h && df -h                     # OOM / disk-full
```

**Recover** (in order — the script's `--fix` covers steps 1–3):

1. If `/` is ≥ 95 % full, clean up first — `slurmd` will die again immediately otherwise. See
   [Disk cleanup before resume](#disk-cleanup-before-resume).
2. Start `slurmd` on the node:

   ```bash
   sudo systemctl enable slurmd   # so it auto-starts on future boots
   sudo systemctl start  slurmd
   ```

3. From the head node, return the node to service:

   ```bash
   sudo scontrol update nodename=<NODE> state=resume
   ```

4. If `slurmd` won't stay up or the node flaps back to `down` within a few minutes, use the
   HyperPod-native reboot path:

   ```bash
   sudo scontrol update node=<NODE> state=fail reason="Action:Reboot"
   ```

5. If a reboot doesn't clear it (repeated ECC errors, kernel panics, GPU XID), use the
   HyperPod-native replace path. **This destroys local state on the instance** (instance-store
   volumes, anything on `/`):

   ```bash
   sudo scontrol update node=<NODE> state=fail reason="Action:Replace"
   ```

   After a replace, running jobs on that node are lost unless `--auto-resume=1` was used to
   launch them.

Slurm node names are IP-based (`ip-10-1-123-45`); translate to an EC2 instance ID with
[Node name → instance ID](#node-name--instance-id) when you need to call the `batch-*` APIs
directly.

---

## § B: Unexpected Reboot — recovery procedures

These are the detailed recovery steps referenced from SKILL.md Section B.

Common triggers on HyperPod: kernel panic, hardware watchdog, manual `reboot`, and HyperPod
auto-repair actions.

**The node is usually fine.** Recover with:

```bash
# 1. On the node (via SSM) — make sure slurmd stays up across future boots.
sudo systemctl is-enabled slurmd || sudo systemctl enable slurmd
sudo systemctl is-active  slurmd || sudo systemctl start  slurmd

# 2. On the head node:
sudo scontrol update nodename=<NODE> state=resume

# 3. Verify:
sinfo -N -l | grep <NODE>     # should be idle or alloc, not down
```

If the node reboots _again_ within a short window, stop resuming it — that points to a kernel
loop or a hardware problem. Check `dmesg` and `journalctl -b -1` (previous boot) first, and
route to `hyperpod-node-debugger`.

**Prevent this during intentional reboots** by draining first:

```bash
sudo scontrol update nodename=<NODE> state=drain reason="Planned reboot"
# Reboot via the HyperPod-native path (preferred):
sudo scontrol update node=<NODE> state=fail reason="Action:Reboot"
# After it comes back healthy:
sudo scontrol update nodename=<NODE> state=resume
```

For a bulk auto-repair aftermath, the script's `--fix` mode handles the resume for every node
currently in this specific state.

---

## § C: Controller restart procedures

These are the detailed restart procedures referenced from SKILL.md Section C.

### Standard restart (preserves state)

```bash
sudo systemctl restart slurmctld
sudo systemctl status  slurmctld
sudo journalctl -u slurmctld -n 100 --no-pager

# Verify:
sinfo                                 # all nodes in expected states
squeue                                # running jobs still there
scontrol ping                         # controller responding
scontrol show config | grep StateSaveLocation   # state dir intact
```

### If the daemon is fully hung

Only after a normal stop has timed out, and only when `StateSaveLocation` has been verified
intact:

```bash
scontrol show config | grep StateSaveLocation
sudo ls -la /var/spool/slurm/ctld/     # should have recent state files

sudo systemctl stop slurmctld || true
sudo pkill -9 slurmctld                # last resort
sudo systemctl start slurmctld
```

**Never** invoke `slurmctld -c` unless the state directory is corrupt — the `-c` flag purges
all jobs and node states.
