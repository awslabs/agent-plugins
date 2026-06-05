---
description: >
  Reference for inference optimization toggles — RAI guardrails, speculative decoding,
  KV cache, quantization, context length, and concurrency tuning. Use when advising
  customers on latency/throughput/cost trade-offs during inference deployment.
related:
  - docs/sdk/skills/deployment-inference.md
  - docs/reference/instance_type_spec.md
---

# Inference Optimization Reference

This document covers the key optimization toggles that affect inference latency, throughput, and cost. Use it to guide customers toward the right configuration for their workload.

> **Key principle:** Always start by understanding the customer's actual workload — input/output lengths, concurrency needs, quality requirements, and whether RAI is required. Don't optimize in the abstract.

---

## 1. RAI (Responsible AI) Guardrails

**What:** Content safety filtering applied to model inputs and outputs.

**Impact on performance:**

- TPOT (time per output token) is generally similar with and without RAI
- TTFT (time to first token) can be higher with RAI enabled
- Overall throughput is generally lower with RAI due to the filtering overhead

**When required:**

- Customer-facing applications
- Regulated industries (healthcare, finance, etc.)
- Any deployment where harmful or inappropriate content is a risk

**When optional:**

- Internal tools with trusted users
- Batch processing pipelines
- Evaluation and benchmarking runs

**How to toggle:** RAI is controlled by the SMI image version — v1.1 includes RAI guardrails, v1.0 does not.

**Agent guidance:** Always ask the customer if RAI is required for their use case. If yes, use "with RAI" benchmark numbers. If no, "without RAI" numbers apply and will show better throughput.

---

## 2. Speculative Decoding

**What:** Uses a smaller draft model to predict multiple tokens ahead, which the main model then verifies in parallel. Accepted tokens skip individual generation steps.

**Impact on performance:**

- Can improve tokens per second (TPS) by 30–60% for long outputs
- Minimal impact on TTFT
- Most effective when the draft model has a high acceptance rate (i.e., its predictions frequently match the main model)

**When helpful:**

- Long-form generation (>200 tokens output)
- Chatbot / conversational use cases
- Summarization tasks

**When NOT helpful:**

- Short outputs (<50 tokens) — overhead outweighs benefit
- Classification tasks — output is too short to benefit
- High-concurrency scenarios — the draft model consumes GPU memory, reducing headroom for concurrent requests

**Trade-off:** The draft model requires additional GPU memory. On memory-constrained instances, enabling speculative decoding may reduce max concurrency.

**How to enable:** Set in `sagemaker_environment` when deploying:

- `SPECULATIVE_DECODING_METHOD`: `"eagle3"` or `"suffix"`
- `NUM_SPECULATIVE_TOKENS`: 1–10 (default varies by method)
- `DISABLE_SPECULATIVE_DECODING`: `"true"` to explicitly disable
- Suffix-specific: `SUFFIX_DECODING_MAX_TREE_DEPTH`, `SUFFIX_DECODING_MAX_CACHED_REQUESTS`, `SUFFIX_DECODING_MAX_SPEC_FACTOR`, `SUFFIX_DECODING_MIN_TOKEN_PROB`

**Agent guidance:** Recommend for long-output use cases on instances with memory headroom. Not available on all instance types. If the customer's outputs are short, skip this optimization.

---

## 3. KV Cache Optimization

**What:** Caches key-value pairs from transformer attention layers so they don't need to be recomputed for previously seen tokens.

**Impact on performance:**

- Critical for multi-turn conversations and long contexts
- Without KV cache, latency scales quadratically with context length
- KV cache is always enabled by default — the optimization decision is about how much memory to allocate to it

**Memory considerations:**
KV cache size scales with: `context_length × num_layers × hidden_dim × concurrency`. Larger models, longer contexts, and higher concurrency all increase KV cache memory consumption.

**Agent guidance:** The KV cache itself is not a toggle — it's always on. The real decision is context length (see below). Ask customers what their actual max input length is. Don't default to the model's maximum context window if they don't need it.

---

## 4. Quantization

**What:** Reduces model weight precision from full precision to lower bit representations (FP16/BF16 → INT8 → INT4).

**Impact on performance:**

- Reduces GPU memory usage by 2–4x, enabling deployment on smaller/cheaper instances
- May slightly reduce output quality, especially on precision-sensitive tasks

**When helpful:**

- Budget-constrained deployments where instance cost matters
- Models too large to fit on the target instance at full precision

**When NOT helpful:**

- Tasks requiring maximum precision (math reasoning, code generation)
- When any quality degradation is unacceptable

**Progression path:**

| Precision | Memory savings | Quality impact           |
| --------- | -------------- | ------------------------ |
| FP16/BF16 | Baseline       | None                     |
| INT8      | ~2x reduction  | Minimal on most tasks    |
| INT4      | ~4x reduction  | Noticeable on some tasks |

**How to enable:** Set in `sagemaker_environment` when deploying:

- `QUANTIZATION_DTYPE`: `"fp8"` — enables FP8 weight quantization
- `KV_CACHE_DTYPE`: `"fp8"` — enables FP8 KV cache (reduces memory for long contexts)

**Agent guidance:** Start with FP16/BF16. If the model doesn't fit the budget instance, suggest INT8 first (minimal quality loss). Only move to INT4 if INT8 is still too large, and warn the customer about potential quality impact on precision-sensitive tasks.

---

## 5. Context Length Tuning

**What:** Setting `max_model_len` below the model's maximum supported context window.

**Impact on performance:**

- Directly reduces KV cache memory consumption
- Allows more concurrent requests on the same GPU
- Benchmark data shows significant throughput differences between 4k, 8k, 16k, 32k, and higher context settings
- Very long context settings (e.g., 45k+) can show substantial throughput drops compared to moderate settings

**How to set:** Use `CONTEXT_LENGTH` in `sagemaker_environment` when deploying (default: 4000).

**Agent guidance:** Always ask what the customer's actual input and output lengths are. If they say "500 tokens input, 200 tokens output," there is no reason to deploy with 32k context. Setting `CONTEXT_LENGTH=4096` would dramatically improve throughput and reduce cost.

**Rule of thumb:** Set `CONTEXT_LENGTH` to roughly 2× the customer's actual max input+output length. This provides safety headroom without wasting GPU memory on unused context capacity.

---

## 6. Concurrency Tuning

**What:** The maximum number of simultaneous requests the inference endpoint handles.

**Impact on performance:**

- Higher concurrency = higher aggregate throughput but higher per-request latency (both TPOT and TTFT increase)
- There is a sweet spot where throughput is maximized without degrading individual request quality

**Warning signs of over-provisioned concurrency:**

- Success rate drops below 100%
- OOM (out of memory) errors
- "Instance replaced" notes in benchmark data
- Latency spikes beyond acceptable thresholds

**How to set:** Use `MAX_CONCURRENCY` in `sagemaker_environment` when deploying (default: 1).

**Agent guidance:** Use benchmark data to find the concurrency level where throughput plateaus or success rate starts dropping. The "likely most balanced" annotations in benchmark data mark good operating points. When in doubt, start with lower concurrency and scale up while monitoring success rate.

---

## Decision Flowchart

Use this sequence when advising on inference configuration:

```
1. Is RAI required?
   → Yes: use "with RAI" benchmarks
   → No:  use "without RAI" benchmarks (better throughput)

2. Output length > 200 tokens typically?
   → Yes: consider speculative decoding (if instance has memory headroom)
   → No:  skip speculative decoding

3. Does the model fit on the target GPU at FP16/BF16?
   → No:  try quantization — INT8 first, then INT4 if needed
   → Yes: use FP16/BF16

4. What is the actual max context needed?
   → Set max_model_len to ~2× actual max input+output length
     (don't waste memory on unused context capacity)

5. What concurrency is needed?
   → Start at the "likely most balanced" point from benchmarks
   → Scale up only if throughput is insufficient and success rate stays at 100%
```

---

## Quick Reference Table

| Optimization          | Primary benefit                         | Primary cost                                 | Default state                  |
| --------------------- | --------------------------------------- | -------------------------------------------- | ------------------------------ |
| RAI Guardrails        | Content safety                          | Higher TTFT, lower throughput                | Depends on SMI image version   |
| Speculative Decoding  | 30–60% TPS improvement for long outputs | Extra GPU memory for draft model             | Off (opt-in)                   |
| KV Cache              | Avoids quadratic latency scaling        | Memory proportional to context × concurrency | Always on                      |
| Quantization (INT8)   | ~2× memory reduction                    | Minimal quality impact                       | Off (FP16/BF16 default)        |
| Quantization (INT4)   | ~4× memory reduction                    | Noticeable quality impact on some tasks      | Off                            |
| Context Length Tuning | More concurrency headroom               | Limits max input size                        | Model maximum (often too high) |
| Concurrency Tuning    | Higher aggregate throughput             | Higher per-request latency                   | Varies by deployment           |
