# Step 2B: Error-Driven Diagnosis

Explicit errors are visible in training logs or `dmesg`.

## CUDA or Xid Errors

```bash
# Run on the failing node via ssm-exec.sh:
dmesg -T | grep 'NVRM: Xid' | tail -20
nvidia-smi --query-gpu=index,ecc.errors.corrected.volatile.total,\
ecc.errors.uncorrected.volatile.total --format=csv
nvidia-smi --query-remapped-rows=gpu_bus_id,remapped_rows.correctable,\
remapped_rows.uncorrectable,remapped_rows.pending,remapped_rows.failure \
--format=csv
```

Xid codes 48, 64, 79, and 95 are critical and warrant immediate node
eviction. Refer to `../failure-patterns.md` §1 for the full catalog.

## NCCL Timeout or Hang

The job is stuck in a collective operation because one rank is not
participating.

1. Capture stack traces on every node to identify the outlier:

   ```bash
   # Run on each node via ssm-exec.sh:
   for pid in $(pgrep -f 'python.*train'); do
     echo "=== PID $pid ==="
     py-spy dump --pid "$pid"
   done
   ```

   Note: `py-spy dump` briefly pauses the target process via `ptrace`.
   On a running distributed job this can trigger the PyTorch NCCL
   watchdog and abort the job. Coordinate with the job owner before
   running, and see `../network-and-comms.md` §4 for the full
   capture procedure and interpretation.

2. Group the stacks by similarity. The majority pattern represents
   healthy ranks; a minority pattern indicates the problem.
3. The outlier rank's node is the likely root cause.
4. Inspect that node's GPU health, NIC status, and `dmesg` for errors.
5. If the outlier is part of a pipeline-parallel group, evict the
   entire pipeline group. A stuck PP stage blocks every stage in that
   group.

Refer to `../network-and-comms.md` §4 for the full stack-trace
aggregation procedure.

## Out-of-Memory (OOM)

- **GPU OOM**: reduce micro-batch size, enable gradient checkpointing,
  and inspect custom code for memory leaks.
- **Host OOM** (`free -h` shows swap use or killed processes): reduce
  DataLoader workers, inspect preprocessing for memory leaks, and
  verify optimizer-state sharding is active.

Refer to `../node-diagnostics.md` §3 for memory-pressure diagnostics.

---

## If this was not the root cause

If no clear error surfaces, or errors are secondary to another
condition:

- `2c-straggler.md` — when only one node reports errors.
- `2d-gradual.md` — when errors correlate with temperature or memory
  pressure trending over time.
- `../failure-patterns.md` — for the full Xid catalog and gray-failure
  signatures.
