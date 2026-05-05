# Step 2F: Network Variance

Step times fluctuate. Different ranks are slow at different times.

## EFA Health

```bash
# Run on each node via SSM.
fi_info -p efa | head -10
cat /sys/class/infiniband/*/ports/1/state   # Should report "4: ACTIVE"

# EFA error counters
for dev in /sys/class/infiniband/*/; do
  echo "=== $(basename $dev) ==="
  cat "$dev/ports/1/counters/port_rcv_errors" 2>/dev/null
  cat "$dev/ports/1/counters/port_xmit_discards" 2>/dev/null
done

# Confirm NCCL is using EFA rather than falling back to TCP.
# Inspect training logs for: "NET/OFI Using provider: efa"
# A "NET/Socket" line indicates EFA is not in use.
```

## NCCL Cross-Node Bandwidth

```bash
# Run nccl-tests between two nodes to measure collective bandwidth.
# Must be launched as a training job or via MPI.
all_reduce_perf -b 1M -e 4G -f 2 -g 1
# Compare the busbw column against expected values:
#   p5, p5e, p5en (2 nodes): ~380–420 GB/s
#   p4d, p4de   (2 nodes):  ~35–45 GB/s
```

## Common EFA Issues on HyperPod

- **Security group missing self-referencing rule**. EFA requires all
  traffic between nodes in the same group.
- **NCCL not using EFA**. Confirm `FI_PROVIDER=efa` is set and the AWS
  OFI NCCL plugin is installed at `/opt/amazon/ofi-nccl/lib/` (or
  `/opt/aws-ofi-nccl/lib/` on older AMIs).
- **Missing placement group**. All training nodes must be in an EC2
  cluster placement group.
- **Version mismatch**. Run the `hyperpod-version-checker` skill across
  all nodes.

## Further Reading

`../network-and-comms.md` contains NCCL environment tuning, recommended
variables per instance type, and topology diagnosis.

---

## If this was not the root cause

If EFA and NCCL appear healthy but variance persists:

- `2c-straggler.md` — variance may originate from a single drifting
  node rather than the network as a whole.
- `2e-periodic.md` — when the apparent variance is actually regular
  dips.
- `2g-tuning.md` — cross-node tensor parallelism causes heavy variance
  on its own.
