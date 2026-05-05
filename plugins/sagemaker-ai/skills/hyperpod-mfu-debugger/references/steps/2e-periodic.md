# Step 2E: Periodic Dips

MFU drops at regular intervals.

## Correlate Timing

- **Checkpoint saves**. The leading cause of periodic dips.
  Synchronous checkpointing stalls all GPUs while model state is
  written to disk or Amazon S3. Larger models and slower storage make
  the effect worse. Remediation: switch to asynchronous checkpointing
  (supported by most frameworks). Measure the cost by comparing step
  time during a checkpoint step to step time during a normal step.
- **Evaluation steps**. Evaluation that runs on the training GPUs
  interrupts training.
- **Logging**. Synchronous metric uploads stall the training loop. Use
  asynchronous logging.
- **Garbage collection pauses**. Python garbage collection can stall
  the Python process. Some training frameworks replace automatic GC
  with `gc.disable()` plus explicit `gc.collect()` between training
  steps. This is an advanced, framework-level change: it is a
  code modification, not a diagnostic, and if long-lived reference
  cycles accumulate it can lead to gradual host-memory growth.
  Validate on a representative workload (at least one full epoch or
  thousands of steps) before adopting on a production run.

## Measure Directly

```bash
# Locate regular step-time spikes in training logs.
grep -E 'step_time|iteration' "/path/to/train.log" | \
  awk '{print NR, $NF}' | sort -k2 -n -r | head -20
```

If the spike interval matches the checkpoint frequency, the cause is
confirmed.

---

## If this was not the root cause

If the dips do not match any periodic event:

- `2f-network.md` — when the apparent period is actually irregular
  variance.
- `2d-gradual.md` — when the baseline between dips is itself declining.
- `../node-diagnostics.md` §4 — for a deeper data-pipeline
  investigation.
