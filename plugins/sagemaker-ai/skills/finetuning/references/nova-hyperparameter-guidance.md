---
name: nova-hyperparameter-guidance
description: Hyperparameter starting points, tuning advice, and debugging guidance for Nova SFT, RFT, and CPT training jobs.
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

# Nova Hyperparameter Guidance

## SFT Hyperparameter Guidance

### Recommended Starting Points

| Parameter                    | Full-Rank         | LoRA              |
| ---------------------------- | ----------------- | ----------------- |
| Epochs                       | 1                 | 2                 |
| Learning rate (`lr`)         | 1e-5              | 5e-5              |
| Min learning rate (`min_lr`) | 1e-6              | 1e-6              |
| Warmup steps                 | ~15% of max_steps | ~15% of max_steps |
| Global batch size            | 32, 64, or 128    | 32, 64, or 128    |
| Max sequence length          | 32768 (default)   | 32768 (default)   |

### Key Parameters Explained

**`max_length`** — Match this to your actual data distribution. Longer sequences improve training efficiency but increase memory. Options: 8192, 16384, 32768, 65536. Don't set higher than your data needs.

**`global_batch_size`** — Affects training stability and throughput. Start with what fits in memory. For domain-specific data, larger batches can over-smooth gradients — prefer smaller batches if your dataset is narrow.

**`warmup_steps`** — Set to ~15% of `max_steps`. Prevents instability at the start of training.

**`weight_decay`** — Default 0.0. Increase to 0.01–0.1 if you see overfitting.

**LoRA `alpha`** — Controls the magnitude of adaptation. Typical range: 8–128. Higher alpha = stronger adaptation.

**LoRA `lora_plus_lr_ratio`** — Multiplier on the learning rate for LoRA parameters specifically. Tune if LoRA adaptation is too slow or too aggressive.

### SFT Recipe Snippet (Nova 2.0 Full-Rank)

```yaml
training_config:
  max_steps: 100
  max_length: 32768
  global_batch_size: 32
  reasoning_enabled: false   # set true only if data has reasoningContent

  lr_scheduler:
    warmup_steps: 15          # ~15% of max_steps
    min_lr: 1e-6

  optim_config:
    lr: 1e-5
    weight_decay: 0.0
    adam_beta1: 0.9
    adam_beta2: 0.95

  peft:
    peft_scheme: "null"       # "lora" for LoRA training
```

---

## RFT Hyperparameter Guidance

### Recommended Starting Points

| Parameter                        | Recommended value           |
| -------------------------------- | --------------------------- |
| Learning rate (`lr`)             | 1e-7                        |
| Number of generations per prompt | 2 (SMTJ)/8 (SMHP)           |
| Max new tokens                   | 8192                        |
| Batch size                       | 128 (SMTJ max) / 256 (SMHP) |
| LoRA rank (if using LoRA)        | 32                          |

### Dataset Size

- **Minimum to start:** 100 training examples + 100 evaluation examples
- **Practical scale:** Start small (100–200 examples), validate reward function, then expand
- **Quality over quantity:** A reliable reward function and diverse prompts matter more than raw dataset size

### Reward Function Design

The reward function is the most critical component of RFT. It must:

- **Execute in seconds** — Lambda has a 15-minute limit, but fast functions enable rapid iteration
- **Return consistent scores** — Inconsistent rewards confuse training
- **Handle all model output formats gracefully** — Models will produce unexpected outputs
- **Directly measure what you care about in production** — Don't proxy; measure the real thing

**RLVR (rule-based, objective tasks):** Implement as an AWS Lambda function. Best for code execution, math verification, structured output checking.

**RLAIF (AI judge, subjective tasks):** Use an AI model to evaluate responses against criteria. Best for tone, helpfulness, brand voice adherence.

**Common reward function additions:**

- Format penalty: penalize malformed outputs
- Length reward: reward appropriate response lengths
- Language consistency: penalize unwanted language switches

### RFT Data Format

```jsonl
{
  "id": "example-001",
  "messages": [
    {"role": "system", "content": "You are a math tutor"},
    {"role": "user", "content": "Solve: 2x + 5 = 13"}
  ],
  "reference_answer": {
    "solution": "x = 4",
    "steps": ["2x = 13 - 5", "2x = 8", "x = 4"]
  },
  "difficulty_level": "easy",
  "domain": "algebra"
}
```

Custom metadata fields (e.g. `difficulty_level`, `domain`, `task_id`) are passed through to your reward function — use them for richer scoring logic.

### Debugging RFT Training

**Watch these metrics:**

- Reward trend over time — should generally increase
- KL divergence from base model — high KL means the model is drifting too far
- Generation length over time — sudden changes indicate reward hacking

**If reward is stuck at 0%:** Switch to SFT first. The model needs at least one correct answer among its rollouts to learn.

**If reward plateaus early:** Expand prompt diversity, add harder examples, or refine the reward function to capture more nuance.

**If generation length explodes:** Add a length penalty to your reward function.

---

## CPT Hyperparameter Guidance

### Recommended Starting Points

| Parameter                    | Value                   |
| ---------------------------- | ----------------------- |
| Learning rate (`lr`)         | 1e-5                    |
| Min learning rate (`min_lr`) | 1e-6                    |
| Warmup steps                 | ~10% of max_steps       |
| Global batch size            | 256                     |
| Max sequence length          | 8192                    |
| Replicas                     | 8 (minimum recommended) |

### Data Preparation for CPT

CPT data quality is the single biggest determinant of success. Raw structured data dumped into training rarely works well.

**Data format:** Simple JSONL with a `text` field per line:

```jsonl
{"text": "AWS SageMaker is a fully managed machine learning service that..."}
{"text": "Amazon Bedrock provides access to foundation models via API..."}
```

**For structured/semi-structured business data (product catalogs, transaction logs, etc.):**

1. **Shuffle field order** — Forces the model to learn relationships between fields rather than memorizing positional patterns.
2. **Randomly drop fields** — Acts like feature dropout. Forces the model to infer missing information from context.
3. **Mix instruction-style examples into CPT data** — Pure CPT can memorize facts in brittle ways. Interleaving instruction-style tasks improves retrievability.
4. **Validate Arrow format compatibility** before training:

```python
from datasets import load_dataset
dataset = load_dataset("json", data_files="your_data.jsonl", split="train")
dataset.save_to_disk("output_dir", max_shard_size="1GB")
```

**When using data mixing:** Run a first job with `max_steps=2` to validate cluster data access and confirm all data mixes are available before committing to a full run.

### CPT → SFT/RFT Pipeline

CPT alone is not enough. Always follow with task-specific fine-tuning:

```
CPT (domain knowledge injection)
  → SFT (teach task format and behavior)
  → RFT (optimize reasoning quality)  ← optional, if task benefits from it
  → Evaluate at each stage
```

---

## Common Pitfalls

| Pitfall                                         | What happens                                 | Fix                                            |
| ----------------------------------------------- | -------------------------------------------- | ---------------------------------------------- |
| Starting RFT with 0% baseline                   | No positive signal, model doesn't learn      | Run SFT first to establish basic capability    |
| `reasoning_enabled: true` on non-reasoning data | Model loses reasoning capability             | Match reasoning mode to your data              |
| Reward function too slow                        | Training bottlenecked on Lambda              | Optimize for seconds-level execution           |
| Inconsistent reward scores                      | Model learns noise, not signal               | Audit reward function for edge cases           |
| Dumping raw structured data into CPT            | Model memorizes positions, not relationships | Shuffle fields, drop keys randomly             |
| LoRA alpha too high                             | Overfitting, unstable training               | Start at 32, tune carefully                    |
| Skipping baseline evaluation                    | Wasted compute on wrong technique            | Always evaluate baseline first                 |
| Not validating data format before training      | Job fails mid-run                            | Run `loader.validate()` and Arrow format check |

---

## Recommended Experimentation Order

1. Evaluate baseline model on your task
2. If knowledge gap → CPT on domain data
3. Start with LoRA (faster iteration, lower cost)
4. If labeled data available → SFT first
5. If SFT plateaus or labeled data is scarce → add RFT
6. Monitor with MLflow (SMHP only) or CloudWatch logs
7. Upgrade to Full-Rank only when LoRA results justify the cost

---

Sources: AWS ML Blog (Feb 2026), Nova 2.0 User Guide — SFT, RFT, CPT documentation
