# Step 2D: Gradual Decline

MFU is declining slowly over hours or days.

## Thermal Throttling

```bash
# Run on multiple nodes via SSM and compare.
nvidia-smi --query-gpu=index,temperature.gpu,clocks.current.sm,\
clocks_event_reasons.hw_thermal_slowdown --format=csv
```

GPUs throttle in software at their Max Operating Temperature (88 °C on
H100 SXM5) and in hardware at their Slowdown Temperature (92 °C). A
node that consistently runs hotter than its peers is the straggler.

**Short-term remediation — approval required.** Applying a lower
power cap with `nvidia-smi -pl <watts>` changes runtime state and
will reduce throughput on that node until reverted. The default power
limit is shown by `nvidia-smi -q -d POWER` and can be restored with
`nvidia-smi -pl <default_watts>`. In synchronized training, the cap
will pace the rest of the job at the capped node's new throughput, so
plan the change accordingly.

**Long-term remediation.** Investigate rack cooling or drain and
replace the node. Refer to `../node-diagnostics.md` §2 for the full
threshold table and its source.

## Memory Pressure

```bash
free -h              # Any swap usage is a problem.
vmstat 1 5           # The si/so columns reveal active swapping.
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv
```

## Data Pipeline

GPUs are starved of data. The signature is periodic idle gaps in GPU
utilization that lengthen over time.

```bash
iostat -x 1 5        # Inspect await above 10 ms and high %util.
df -h                # Full disk.
# For FSx for Lustre:
lctl get_param llite.*.stats 2>/dev/null
```

## Further Reading

`../node-diagnostics.md` contains the detailed memory, thermal, and
data-pipeline diagnostic procedures.

---

## If this was not the root cause

If the decline is not thermal, memory, or data-related:

- `2e-periodic.md` — when the "decline" is actually regular dips
  (saw-tooth pattern).
- `2c-straggler.md` — when one node consistently runs hotter than
  peers.
- `2a-regression.md` — when a code or configuration change predates
  the decline.
