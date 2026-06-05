# Nova Forge Best Practices

Best practices specific to Nova model customization via the Nova Forge SDK.

## Key Recommendations (Always Explain Reasoning)

When guiding customers through Nova workflows, always provide reasoning for these decisions:

### 1. Model Selection (Explain Why)

- **Nova 2.0 models (`NOVA_LITE_2`)** — Required if data contains reasoning traces (`reasoningContent`). Only v2.0 supports `reasoning_enabled: True`.
- **Nova 1.0 models (`NOVA_MICRO`, `NOVA_LITE`, `NOVA_PRO`)** — For tasks without reasoning traces. Choose based on task complexity and context length needs.
- Consider: input length vs context window, task complexity, cost constraints.

### 2. Technique Selection (Explain Why)

- **SFT** — User has labeled prompt-response pairs with clear correct outputs.
- **RFT** — Outcomes are verifiable programmatically; user can write a reward function.
- **CPT** — Model lacks domain knowledge (always follow CPT with SFT or RFT).
- Always evaluate baseline first. If baseline is 0%, start with SFT before RFT.

### 3. LoRA vs Full-Rank (Explain Why)

- **LoRA** — Faster iteration, lower cost, smaller artifacts, Bedrock On-Demand deployment. Start here.
- **Full-Rank** — Maximum performance, requires Provisioned Throughput. Upgrade only after LoRA validates the approach.

### 4. Always Use Dry Run First

Before submitting any training job, use `dry_run=True` to catch configuration errors early.

```python
trainer.train(dry_run=True)   # Validate first
trainer.train(job_name=...)  # Then run
```

## Training Best Practices

- Prefer LoRA for initial experiments — 3-5x faster and cheaper than full-rank
- Always save training results with `result.dump()` after every job
- Validate data before training with `.validate()`
- Match reasoning mode between training and inference

## Common Error Patterns

- **AccessDenied for S3** — Add `s3:GetObject` and `s3:ListBucket` permissions to IAM role
- **Instance Type Not Supported** — Check instance type constraints for the model/method combination
- **Data Validation Failed** — Check column mappings in data preparation workflow
