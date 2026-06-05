---
name: inference-recommendation
description: Guide customers to the optimal inference configuration through structured conversation, benchmark data, and cheap probes. Use when customers need help choosing instance types, context lengths, or optimization settings.
triggers:
  keywords: [inference, instance, deploy, endpoint, latency, throughput, cost, recommend, which instance, how much will it cost, TTFT, TPOT, concurrency]
  task_types: [inference-recommendation, deployment-planning, cost-estimation]
  error_patterns: []
  methods: [SFT, RFT, DPO, CPT]
prerequisites: []
last_verified: 2026-03-27
sdk_version: ">=1.0.0"
---

# Inference Recommendation Skill

## When to Use This Skill

- Customer asks "which instance should I use?"
- Customer asks about inference cost or latency
- Customer wants to deploy a model and needs guidance
- Customer asks about speculative decoding, RAI, or other optimizations
- Before any deployment decision

## When NOT to Use This Skill

- Customer already knows their instance and just wants to deploy → use `deployment-inference.md`
- Customer is asking about training, not inference → use `training-workflow.md`

## The 5-Step Inference Recommendation Flow

### Step 1: Intent Extraction (MANDATORY — do this FIRST)

Ask these questions in natural conversation, not as a form:

- What does your application do? (chatbot, summarization, classification, code gen, etc.)
- What's the user-facing latency expectation? (sub-200ms TTFT? sub-500ms? doesn't matter?)
- What's your monthly budget ceiling? (or $/hr)
- Is traffic steady or bursty? (steady = optimize for cost, bursty = need headroom)
- What's the expected input/output token length? (this determines context length setting)
- How many concurrent users/requests?
- Is RAI (content safety) required?

Map answers to constraints internally:

| Customer says                     | Constraint                                                  |
| --------------------------------- | ----------------------------------------------------------- |
| "sub-200ms first token"           | TTFT < 200ms → eliminates g5/g6 at high concurrency         |
| "under $10/hr"                    | Eliminates p5.48xlarge ($63.30/hr) unless multi-tenant      |
| "chatbot, 500 token responses"    | Long output → consider speculative decoding                 |
| "classification, 10 token output" | Short output → skip speculative decoding, optimize for TTFT |
| "bursty, 10x spikes"              | Need concurrency headroom, don't run at max                 |
| "internal tool, no public users"  | RAI likely optional → use "without RAI" benchmarks          |

### Step 2: Constraint Propagation — Eliminate Bad Options

Read `docs/reference/inference-benchmark-data.md` for benchmark data.
Read `docs/reference/inference-optimizations.md` for optimization guidance.

Apply constraints to narrow the search space. Show the customer what was eliminated and why:

> "I looked at 6 instance types across 3 Nova models. Your $10/hr budget eliminates p5.48xlarge ($63.30/hr). Your sub-300ms TTFT requirement eliminates g5.12xlarge at concurrency > 8. Here are the survivors:"

The elimination narrative builds trust — the customer sees you're not guessing.

### Step 3: Benchmark Table Presentation

Present a filtered table showing ONLY configurations that survive the constraint envelope:

| Instance | Context | Concurrency | TTFT (ms) | TPOT (ms) | Throughput | $/hr | $/1M tokens |
| -------- | ------- | ----------- | --------- | --------- | ---------- | ---- | ----------- |

For configs not in the benchmark table, use the coefficient formulas to estimate:

- **TPOT** = a_tpot + b_tpot × ln(concurrency)
- **Throughput** = exp(a_thr + b_thr × ln(concurrency))
- **TTFT** = a_ttft + b_ttft × ln(concurrency)

Mark estimated values clearly: `~150ms (estimated, R²=0.92)` vs `150ms (measured)`

### Step 4: Optimization Recommendations

Based on the conversation, proactively recommend:

- **RAI on/off** — based on use case
- **Context length reduction** — if actual input << model max
- **Speculative decoding** — if long outputs
- **Concurrency sweet spot** — from benchmark stability data

Reference `docs/reference/inference-optimizations.md` for details.

### Step 5: Decision Support — Present Tradeoffs

Present 2-3 surviving configurations side-by-side with clear tradeoffs:

> "Config A (g6.48xlarge): $16.69/hr, TTFT ~280ms, handles 8 concurrent. Best cost.
> Config B (g5.24xlarge): $10.18/hr, TTFT ~270ms, handles 8 concurrent. Cheaper but lower throughput.
> Config C (p5.48xlarge): $63.30/hr, TTFT ~80ms, handles 32+ concurrent. Only if you need massive throughput."

Let the customer decide. Do NOT pick for them.

After they choose, proceed to the deployment workflow in the model-deployment skill.

## Cheap Inference Probe (Advanced)

For customers who want measured data instead of estimates:

1. Deploy a temporary endpoint with the chosen config
2. Run 50-100 requests from their actual prompt distribution
3. Measure actual TTFT, TPS, cost-per-query
4. Compare against estimates
5. Tear down the temporary endpoint

Total cost: < $5. Total time: ~10 minutes.
This replaces estimates with real data on the customer's workload.

## Important: Nova SageMaker Inference Container

All benchmark data in this skill is from the **Nova SageMaker Inference container**:

- us-east-1: `708977205387.dkr.ecr.us-east-1.amazonaws.com/nova-inference-repo:SM-Inference-latest`
- us-west-2: `176779409107.dkr.ecr.us-west-2.amazonaws.com/nova-inference-repo:SM-Inference-latest`
- eu-west-2: `470633809225.dkr.ecr.eu-west-2.amazonaws.com/nova-inference-repo:SM-Inference-latest`

When deploying, the agent must ensure the customer uses this container image. The SDK's `deploy(deploy_platform=DeployPlatform.SAGEMAKER)` selects it automatically. For raw boto3 deploys, the image URI must be set explicitly in `create_model()`.

The deploy call must set these environment variables to match the chosen benchmark config:

- `CONTEXT_LENGTH` — e.g., `"8192"` for 8k
- `MAX_CONCURRENCY` — e.g., `"16"`

## Key Reference Files

- `docs/reference/inference-benchmark-data.md` — benchmark data + coefficients
- `docs/reference/inference-optimizations.md` — RAI, speculative decoding, quantization
- `docs/reference/instance_type_spec.md` — instance constraints for training (different from inference)
- `references/nova-deployment-inference.md` — actual deployment steps after decision is made
