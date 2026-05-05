# MFU Optimization Guide

How to improve MFU when the root cause is configuration, not hardware.
Organized by expected impact; start from the top.

## Contents

1. [High-Impact Checklist](#1-high-impact-checklist)
2. [Profiling](#2-profiling)
3. [Parallelism Tuning](#3-parallelism-tuning)
4. [Computation-Communication Overlap](#4-computation-communication-overlap)
5. [Kernel and Precision](#5-kernel-and-precision)
6. [Memory for Larger Batches](#6-memory-for-larger-batches)
7. [NCCL Tuning](#7-nccl-tuning)
8. [Infrastructure Placement](#8-infrastructure-placement)

---

## 1. High-Impact Checklist

| # | Check                                  | Expected gain | Verify                                                 |
| - | -------------------------------------- | ------------- | ------------------------------------------------------ |
| 1 | Flash Attention enabled                | 15–30%        | Profiler shows `flash_attn` kernels                    |
| 2 | Gradient all-reduce overlaps backward  | 10–25%        | All-reduce interleaved with backward in trace          |
| 3 | TP within a node (≤ 8)                 | 5–20%         | Parallelism config                                     |
| 4 | Sequence parallelism when TP > 1       | 3–8%          | Config                                                 |
| 5 | BF16 actually in use                   | 10–50%        | No FP32 matmuls in forward/backward                    |
| 6 | Full parameter sharding only if needed | 10–30%        | Optimizer-state sharding + checkpointing may be enough |
| 7 | Asynchronous checkpointing             | 1–60%         | Step time stable during save                           |

---

## 2. Profiling

Profile before optimizing.

### Single-step capture

```python
from torch.profiler import profile, ProfilerActivity

with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    record_shapes=True,
    with_stack=True,
) as prof:
    train_step()

print(prof.key_averages().table(sort_by="cuda_time_total", row_limit=20))
prof.export_chrome_trace("trace.json")   # open in chrome://tracing or Perfetto
```

### Multi-step capture with warmup

```python
from torch.profiler import profile, ProfilerActivity, schedule

with profile(
    activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
    schedule=schedule(wait=5, warmup=2, active=3, repeat=1),
    on_trace_ready=torch.profiler.tensorboard_trace_handler('./profiler_logs'),
    record_shapes=True,
    profile_memory=True,
    with_stack=True,
) as prof:
    for step, batch in enumerate(dataloader):
        train_step(batch)
        prof.step()
        if step >= 10:
            break
```

### Breakdown buckets

| Category      | Includes                                           | Healthy range |
| ------------- | -------------------------------------------------- | ------------- |
| Compute       | matmul, attention, FFN, activations                | 60–75%        |
| Communication | all_reduce, reduce_scatter, all_gather, send, recv | 25–40%        |
| Idle/overhead | gaps, sync, data loading, GC, checkpointing        | < 10%         |

- Compute < 50% → communication-bound: reduce TP, enable overlap, check EFA.
- Compute > 85% → near hardware ceiling: optimize kernels/precision.
- Overhead > 15% → data pipeline, GC, or checkpoint stalls.

---

## 3. Parallelism Tuning

### Tensor Parallelism (TP)

Keep TP within a single instance. TP all-reduces on every transformer
layer; NVLink is 900 GB/s per GPU on H100/H200 while EFA at 3,200 Gbps
is shared across the 8 GPUs. Cross-instance TP consumes enormous
bandwidth on every layer and rarely pays off.

If TP > 8 (cross-node), that is typically the single largest MFU
problem. Reduce TP to ≤ 8 and compensate with DP or PP.

### Pipeline Parallelism (PP)

1F1B bubble ratio (Narayanan et al. 2021):
`(P − 1) / (P − 1 + M)` where `P` = pipeline stages, `M` =
microbatches per step.

| PP stages | Microbatches | Bubble |
| --------- | ------------ | ------ |
| 4         | 4            | 43%    |
| 4         | 8            | 27%    |
| 4         | 16           | 16%    |
| 4         | 32           | 9%     |

Reduce bubbles: more microbatches per flush, interleaved 1F1B, balance
layers by compute cost (embeddings are lighter than transformer
blocks), virtual pipeline stages.

### Data Parallelism and Sharding

| Strategy                     | Shards                | Overhead                   | Use when           |
| ---------------------------- | --------------------- | -------------------------- | ------------------ |
| Optimizer states only        | Optimizer             | Minimal                    | Default            |
| + gradients                  | Optimizer + gradients | Moderate                   | More memory needed |
| + parameters (full sharding) | Full                  | Heavy (all-gather / layer) | Last resort        |

Full parameter sharding adds an all-gather per forward layer, costing
10–30% MFU. Prefer optimizer-state sharding plus gradient checkpointing
if the model fits.

### Sequence Parallelism

Distributes LayerNorm/Dropout activations across the TP group,
replacing an all-reduce with reduce-scatter + all-gather. Net cost
≈ 0. Enable whenever TP > 1.

---

## 4. Computation-Communication Overlap

### Gradient all-reduce overlap

Gradients become available layer by layer in backward. Communicating
each layer's gradient during the next layer's backward compute delivers
10–25% MFU.

Without overlap: `[backward all layers] → [all-reduce all grads]`.
With overlap: `[backward layer N] + [all-reduce layer N+1 grads]`
simultaneously.

**Verify**: all-reduce interleaved with backward kernels in the trace.
A single all-reduce block after backward = no overlap.

Most frameworks overlap by default (DDP bucketing). Usual culprit is
custom training code calling `all_reduce` after the full backward.

### Pipeline prefetch

Overlap next microbatch's forward with current microbatch's backward.
Costs memory for two microbatches.

### Parameter prefetch (full sharding)

With full parameter sharding, prefetch next layer's parameters during
current layer's compute. Without prefetch, all-gather latency is fully
exposed per layer.

---

## 5. Kernel and Precision

### Flash Attention

Fused kernel; avoids the O(n²) attention matrix. Memory O(n²) → O(n);
throughput up.

**Verify**: `flash_attn` or `flash_fwd` kernels in the trace. An
`sdpa_attention` op or manual QKV matmul + softmax pattern = not
active.

Install: `pip install flash-attn --no-build-isolation`.

### BF16

H100/A100 deliver ~2× BF16 vs FP32. Accidental FP32 is a common silent
MFU killer. Causes: `.float()` in custom code, loss functions that
upcast, third-party layers without BF16. Check the trace for `float32`
matmuls in the main forward/backward — there should be none.

### FP8 (H100/H200)

Up to 2× additional throughput over BF16. Requires per-tensor
quantization and loss scaling. Not all workloads benefit — profile
first.

### Fused kernels

Fusing small ops (LayerNorm + bias + activation; optimizer step)
reduces launch overhead and memory bandwidth pressure. Most frameworks
provide them; verify enabled. New fused kernels are a common regression
source — compare MFU and loss before and after.

---

## 6. Memory for Larger Batches

More free GPU memory → larger micro-batch → better utilization per
kernel launch → higher MFU.

### Gradient checkpointing

| Strategy                                | Memory savings | Compute overhead |
| --------------------------------------- | -------------- | ---------------- |
| Full recomputation                      | 30–40%         | ~33%             |
| Selective (LayerNorm, activations only) | 20–30%         | ~10–15%          |

Selective is almost always better: recompute cheap ops, keep attention
and MLP activations.

### Micro-batch sizing

1. Profile current GPU memory.
2. Headroom = total − peak active − 10% margin.
3. Increase micro-batch to fill headroom.
4. Verify stability and loss at the new size.

### CPU offloading

Offload optimizer states to CPU. Transfers must overlap with compute,
otherwise offload is a regression.

---

## 7. NCCL Tuning

### Buffer size

```bash
export NCCL_BUFFSIZE=8388608   # 8 MB. Modern NCCL (≥ 2.19) often auto-tunes; measure before overriding.
```

### Protocol

```bash
export NCCL_PROTO=Simple       # Best for EFA on p4d/p5/p5e/p5en
# LL and LL128 are low-latency small-message paths (usually auto)
```

### Algorithm benchmarking

```bash
NCCL_ALGO=Ring ./all_reduce_perf -b 1M -e 4G -f 2 -g 1
NCCL_ALGO=Tree ./all_reduce_perf -b 1M -e 4G -f 2 -g 1
```

Pick the algorithm with highest `busbw` for the target message-size
range.

### GPU Direct RDMA

```bash
export NCCL_NET_GDR_LEVEL=SYS
export NCCL_NET_GDR_READ=1
export FI_EFA_USE_DEVICE_RDMA=1
```

Direct GPU-to-NIC transfer; bypasses CPU memory.

---

## 8. Infrastructure Placement

### Topology-aware placement

| Parallelism | Place on                | Rationale                                 |
| ----------- | ----------------------- | ----------------------------------------- |
| TP group    | Same node (NVLink)      | All-reduce / layer; maximum bandwidth     |
| PP group    | Same rack / leaf switch | P2P between stages; moderate bandwidth    |
| DP group    | Across racks            | Less-frequent all-reduce; fault isolation |

### GPU-NIC affinity

`nvidia-smi topo -m` shows which GPUs are closest to which NICs.
Assign ranks so each GPU's cross-node traffic takes the nearest NIC.
Some frameworks handle this automatically — verify in the launcher.

---

## References

**Checklist / baselines (§1):**

- PyTorch FSDP 57% MFU at 7B / 512 GPUs:
  https://pytorch.org/blog/maximizing-training/
- MegaScale 55.2% MFU at 175B / 12,288 GPUs (NSDI 2024):
  https://www.usenix.org/conference/nsdi24/presentation/jiang-ziheng
- Transformer FLOPs and `6N`:
  https://www.adamcasson.com/posts/transformer-flops

**Profiler (§2):**

- PyTorch Profiler: https://docs.pytorch.org/docs/stable/profiler.html
- TensorBoard profiler tutorial:
  https://docs.pytorch.org/tutorials/intermediate/tensorboard_profiler_tutorial.html
- Perfetto: https://ui.perfetto.dev

**Parallelism (§3):**

- Megatron-LM 1F1B and bubble formula (Narayanan et al., SC 2021):
  https://arxiv.org/abs/2104.04473
- GPipe (Huang et al., NeurIPS 2019): https://arxiv.org/abs/1811.06965
- ZeRO-1/2/3 (Rajbhandari et al., SC 2020):
  https://arxiv.org/abs/1910.02054
- PyTorch FSDP: https://docs.pytorch.org/docs/stable/fsdp.html
- Megatron tensor parallelism (Shoeybi et al. 2019):
  https://arxiv.org/abs/1909.08053
- Megatron sequence parallelism (Korthikanti et al. 2022):
  https://arxiv.org/abs/2205.05198

**Overlap (§4):**

- PyTorch DDP bucketed all-reduce:
  https://docs.pytorch.org/docs/stable/notes/ddp.html
- Zero Bubble Pipeline Parallelism (Qi et al. 2023):
  https://arxiv.org/abs/2401.10241

**Kernels / precision (§5):**

- Flash Attention 1 (Dao et al., NeurIPS 2022):
  https://arxiv.org/abs/2205.14135
- Flash Attention 2 (Dao 2023): https://arxiv.org/abs/2307.08691
- Flash Attention 3 (Shah et al. 2024): https://arxiv.org/abs/2407.08608
- `flash-attn`: https://pypi.org/project/flash-attn/
- NVIDIA Transformer Engine (FP8):
  https://github.com/NVIDIA/TransformerEngine
- Hopper architecture deep dive:
  https://developer.nvidia.com/blog/nvidia-hopper-architecture-in-depth/

**Memory (§6):**

- PyTorch activation checkpointing:
  https://docs.pytorch.org/docs/stable/checkpoint.html
- Selective recomputation trade-off:
  https://mbrenndoerfer.com/writing/activation-checkpointing-gradient-memory-selective-recomputation
- Selective activation recomputation (Korthikanti et al. 2022):
  https://arxiv.org/abs/2205.05198
- DeepSpeed ZeRO-Offload:
  https://www.deepspeed.ai/tutorials/zero-offload/

**NCCL (§7):**

- NCCL environment variables:
  https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html
- nccl-tests: https://github.com/NVIDIA/nccl-tests
- AWS libfabric EFA variables:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/efa-start-nccl.html

**Placement (§8):**

- EC2 cluster placement groups:
  https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html
- HyperPod EC2 UltraCluster topology:
  https://aws.amazon.com/ec2/instance-types/p5/
- `nvidia-smi topo`:
  https://docs.nvidia.com/deploy/nvidia-smi/index.html
