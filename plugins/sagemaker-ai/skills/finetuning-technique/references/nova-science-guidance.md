# Nova Model Customization — Science Guidance

Practical guidance on choosing the right technique, preparing data effectively, and setting hyperparameters for Nova 2.0 model customization.

Sources: [RFT blog](https://aws.amazon.com/blogs/machine-learning/reinforcement-fine-tuning-for-amazon-nova-teaching-ai-through-feedback/), [SFT Nova 2.0 docs](https://docs.aws.amazon.com/nova/latest/nova2-userguide/nova-sft-2-fine-tune.html), [RFT Nova 2.0 docs](https://docs.aws.amazon.com/nova/latest/nova2-userguide/nova-hp-rft-nova2.html), [CPT Nova 2.0 docs](https://docs.aws.amazon.com/nova/latest/nova2-userguide/nova-cpt-2.html)

---

## Step 0: Always Evaluate Baseline First

Before choosing any technique, run an evaluation of the base model on your task. This single step determines everything else.

| Baseline performance                             | What it means                        | What to do                               |
| ------------------------------------------------ | ------------------------------------ | ---------------------------------------- |
| > 95% reward / accuracy                          | Model already handles your task well | Customization may not be needed          |
| 0% reward consistently                           | Model lacks basic task capability    | Start with SFT to establish fundamentals |
| Moderate (some successes, some failures)         | Model has potential to improve       | RFT is likely the right choice           |
| Knowledge gap (wrong facts, not wrong reasoning) | Model doesn't know your domain       | CPT first, then SFT or RFT               |

---

## Choosing the Right Technique

### Decision Tree

```
Does the model need domain knowledge it doesn't have?
├── Yes → Start with CPT (then follow with SFT or RFT)
└── No → Do you have labeled prompt-response pairs?
    ├── Yes, high quality pairs with clear correct outputs → SFT
    └── No / Can you define what "correct" looks like programmatically?
        ├── Yes (verifiable outcomes) → RFT
        └── No → Build labeled data first, then SFT
```

### SFT — Supervised Fine-Tuning

**Use when:**

- You have high-quality prompt-response pairs (hundreds to thousands)
- The task has clear, well-defined correct outputs ("given X, the answer is Y")
- You want to teach specific formatting, style, or output structure
- You need to inject factual knowledge (e.g. "Paris is the capital of France")
- Baseline model performance is 0% — SFT establishes the foundation before RFT

**Not ideal when:**

- You can't easily create labeled examples at scale
- Multiple valid solution paths exist and you can't enumerate them all
- The task requires complex multi-step reasoning optimization

**Data requirements:**

- Format: JSONL with `question`/`answer` fields (or use column mappings)
- Nova 2.0 also supports: reasoning traces (`reasoningContent`), tool calling, document/video understanding
- Minimum: a few hundred examples; more is better for generalization

### RFT — Reinforcement Fine-Tuning

**Use when:**

- You can define what "correct" looks like but can't easily demonstrate the reasoning path
- Outcomes are verifiable programmatically (code execution, math, structured outputs)
- You have limited labeled data but can write a reward function
- You want to optimize competing objectives (accuracy + efficiency + style)
- Baseline model gets at least some correct answers (needs diversity across rollouts)

**Not ideal when:**

- Model consistently fails at 0% — it needs at least one success among 4-8 attempts to learn
- The task is purely knowledge-based (RFT optimizes reasoning, not knowledge injection)
- You can't define a reliable, fast reward function

**Key requirement:** RFT uses Group Relative Policy Optimization (GRPO), which needs outcome diversity across multiple rollouts (4-8 generations per prompt). The model must produce at least one correct and one incorrect answer to learn the distinction.

**Real-world use cases:** Code generation, math reasoning, financial analysis, customer service tone, content moderation, tool/API usage, multi-step logical deduction.

### CPT — Continued Pre-Training

**Use when:**

- The model lacks domain-specific knowledge entirely (specialized terminology, proprietary data, industry-specific facts)
- You have large volumes of unlabeled domain text (product catalogs, documentation, transaction logs, research papers)
- You want to extend the model's knowledge base before task-specific fine-tuning

**Not ideal when:**

- You have a small dataset — CPT needs substantial data to be effective
- The problem is reasoning quality, not knowledge gaps
- You need quick results — CPT is the most compute-intensive option

**Always follow CPT with SFT or RFT** to teach the model how to apply its new knowledge to specific tasks.

### LoRA vs Full-Rank

|                            | LoRA                                       | Full-Rank                                    |
| -------------------------- | ------------------------------------------ | -------------------------------------------- |
| Resource cost              | Lower                                      | Higher                                       |
| Model artifact size        | Smaller                                    | Larger                                       |
| Deployment                 | Bedrock On-Demand (pay per token)          | Requires Provisioned Throughput              |
| Best for                   | Iteration, validation, cost-sensitive      | Maximum performance, high-traffic production |
| Recommended starting point | Yes — iterate fast, then upgrade if needed | After LoRA validates the approach            |

**Recommendation:** Start with LoRA. Validate your approach. Move to Full-Rank when traffic or performance requirements justify the cost.

### Reasoning Mode (Nova 2.0 Only)

Nova 2.0 supports explicit reasoning traces — the model thinks step-by-step before answering.

|               | Reasoning enabled                                      | Reasoning disabled                    |
| ------------- | ------------------------------------------------------ | ------------------------------------- |
| Best for      | Complex analytical tasks, math, multi-step logic, code | Chat-style Q&A, speed-sensitive tasks |
| Training data | Must contain `reasoningContent` fields                 | Standard prompt-response pairs        |
| Inference     | Enable reasoning at inference too                      | Keep consistent with training         |

**Critical rule:** Match reasoning mode between training and inference. Training on non-reasoning data with `reasoning_enabled: true` will cause the model to lose reasoning capability. If you train without reasoning but want it at inference, it's possible but not guaranteed to improve performance.

---

_For hyperparameter guidance (starting points, tuning, debugging), see `../../finetuning/references/nova-hyperparameter-guidance.md` — that content is applied at training time._

---

Sources: AWS ML Blog (Feb 2026), Nova 2.0 User Guide — SFT, RFT, CPT documentation
