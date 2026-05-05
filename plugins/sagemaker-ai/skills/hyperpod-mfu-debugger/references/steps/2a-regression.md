# Step 2A: Code or Configuration Regression

A recent change correlates with an MFU drop.

## Procedure

1. Identify what changed (`git log`, configuration diff).
2. Roll back to the last known-good state.
3. Run a short benchmark of 50–100 steps and compare MFU before and
   after.
4. If MFU recovers, bisect the change.

## Common Causes

- Accidental FP32 operations introduced by type promotion in custom code.
- Flash Attention disabled or removed after a dependency update.
- Changes to micro-batch size, sequence length, or parallelism
  dimensions.
- NCCL or EFA plugin version change after node replacement.
- A new custom kernel with a performance regression.

## Version Drift Across Nodes

A replaced node may ship with a different CUDA, NCCL, or EFA version
than the rest of the cluster. Run the `hyperpod-version-checker` skill
across all nodes to detect mismatches.

## After Bisecting

Once the offending change is identified:

- **Code change**: review for type promotions, missing fused operators,
  or changed parallelism dimensions.
- **Dependency change**: pin the affected package versions; confirm
  Flash Attention and the NCCL plugin are still present.
- **Node replacement**: ensure the lifecycle scripts install an
  identical software stack. Compare the replaced node against healthy
  nodes.

---

## If this was not the root cause

If no recent change is apparent or the rollback did not recover MFU:

- `2g-tuning.md` — when MFU was low before the perceived degradation.
- `2c-straggler.md` — when one node's metrics differ from its peers.
- `2f-network.md` — when step-time variance is high.
