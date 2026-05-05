# Step 2G: Configuration Tuning

MFU was low from the start. This path is optimization, not failure
diagnosis.

## Step 1: Profile One Training Step

Use PyTorch Profiler (or the framework's equivalent) to capture a
single-step breakdown of compute, communication, and idle time.

```python
import torch.profiler

with torch.profiler.profile(
    activities=[torch.profiler.ProfilerActivity.CPU,
                torch.profiler.ProfilerActivity.CUDA],
    record_shapes=True,
    with_stack=True,
) as prof:
    train_step()

print(prof.key_averages().table(sort_by="cuda_time_total", row_limit=20))
```

## Step 2: Interpret the Breakdown

| Compute % | Communication % | Diagnosis                                               |
| --------- | --------------- | ------------------------------------------------------- |
| 60–75%    | 25–40%          | Healthy balance                                         |
| Below 50% | Above 50%       | Communication-bound. Reduce TP, enable overlap.         |
| Above 85% | Below 15%       | Compute-bound. Optimize kernels or precision.           |
| —         | —               | Idle above 15%: data loading, GC, or checkpoint stalls. |

## Step 3: Apply Fixes in Order of Typical Impact

1. **Enable Flash Attention** if not already active (15–30% gain for
   long sequences).
2. **Enable gradient all-reduce overlap**. The backward pass and
   communication should be interleaved, not sequential (10–25% gain).
3. **Right-size tensor parallelism**. Keep TP within a single node
   (TP ≤ 8). Cross-node TP incurs a significant communication tax.
4. **Enable sequence parallelism** when TP > 1 (near-zero cost).
5. **Avoid full parameter sharding when unnecessary**. Optimizer-state
   sharding plus gradient checkpointing is usually sufficient and
   costs 10–30% less.
6. **Maximize micro-batch size**. Use the largest value that fits in
   memory.
7. **Verify BF16 precision**. Accidental FP32 from type promotion in
   custom code is a common silent performance killer.
8. **Topology-aware placement**. TP groups on NVLink; PP groups within
   a rack.

## Further Reading

`../optimization-guide.md` contains the full playbook, including the
profiling workflow, NCCL tuning, and infrastructure-level optimizations.

---

## If this was not the root cause

If the configuration already looks reasonable and MFU is still low:

- `2f-network.md` — suboptimal EFA or NCCL setup appears identical to
  "bad configuration" from the training-loop perspective.
- `2c-straggler.md` — a hidden straggler caps MFU regardless of
  configuration.
- `../failure-patterns.md` §2 — for gray-failure signatures that
  present as "it is just slow".
