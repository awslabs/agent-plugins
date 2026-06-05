---
name: iterative-training
description: Multi-stage fine-tuning by progressively training on checkpoints using ForgeTrainer. Use when building on previous training results.
triggers:
  keywords: [iterative, checkpoint, multi-stage, continue, chain, previous, stage, curriculum, model_s3_path]
  task_types: [training]
  error_patterns: ["Cannot continue training from LoRA checkpoint with Full-Rank"]
  methods: [CPT, SFT, RFT]
prerequisites: [training-workflow]
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

# Iterative Training

## Key Rules

### Method Consistency

You must use the same rank type (LoRA vs Full-Rank) across all stages:

- ✅ SFT_LORA → SFT_LORA → RFT_LORA
- ✅ SFT_FULL → SFT_FULL → RFT_FULL
- ❌ SFT_LORA → SFT_FULL (incompatible)
- ❌ SFT_FULL → RFT_LORA (incompatible)

### Hyperparameter Adjustment

Reduce learning rate and epochs in later stages to avoid overfitting:

- Stage 1: `lr=1e-5`, `max_epochs=3`
- Stage 2: `lr=5e-6`, `max_epochs=2`
- Stage 3: `lr=2e-6`, `max_epochs=1`

## Step-by-Step Guide

### Stage 1: Initial Training

```python
from amzn_nova_forge import ForgeTrainer
from amzn_nova_forge import ForgeConfig
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge import SMTJRuntimeManager

infra = SMTJRuntimeManager(
    execution_role='arn:aws:iam::123456789012:role/NovaCustomizationSdkExecutionRole',
    instance_count=4,
    instance_type='ml.p5.48xlarge'
)

stage1_trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/general_domain_data.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/stage1_output/')
)

stage1_result = stage1_trainer.train(
    job_name='stage1-general-domain',
    overrides={'max_epochs': 3, 'lr': 1e-5}
)
stage1_result.dump(file_path=".", file_name="stage1_result.json")
```

### Stage 2: Continue from Checkpoint

```python
from amzn_nova_forge import TrainingResult

stage1_result = TrainingResult.load("stage1_result.json")

stage2_trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.SFT_LORA,
    infra=infra,
    training_data_s3_path='s3://my-bucket/task_specific_data.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/stage2_output/'),
    model_s3_path=stage1_result.model_artifacts.checkpoint_s3_path
)

stage2_result = stage2_trainer.train(
    job_name='stage2-task-specific',
    overrides={'max_epochs': 2, 'lr': 5e-6}
)
stage2_result.dump(file_path=".", file_name="stage2_result.json")
```

### Stage 3: Switch to RFT (Optional)

```python
stage2_result = TrainingResult.load("stage2_result.json")

stage3_trainer = ForgeTrainer(
    model=Model.NOVA_LITE_2,
    method=TrainingMethod.RFT_LORA,  # Switch method, keep LoRA
    infra=infra,
    training_data_s3_path='s3://my-bucket/rft_data.jsonl',
    config=ForgeConfig(output_s3_path='s3://my-bucket/stage3_output/'),
    model_s3_path=stage2_result.model_artifacts.checkpoint_s3_path
)

stage3_result = stage3_trainer.train(
    job_name='stage3-rft',
    overrides={'max_epochs': 1, 'lr': 2e-6, 'kl_coef': 0.1}
)
stage3_result.dump(file_path=".", file_name="stage3_result.json")
```

### Evaluate Between Stages

```python
from amzn_nova_forge import ForgeEvaluator
from amzn_nova_forge import EvaluationTask

evaluator = ForgeEvaluator(
    model=Model.NOVA_LITE_2,
    infra=infra,
    config=ForgeConfig(output_s3_path='s3://my-bucket/eval_output/')
)

stage1_result = TrainingResult.load("stage1_result.json")
eval_result = evaluator.evaluate(
    job_name='stage1-eval',
    eval_task=EvaluationTask.GEN_QA,
    model_path=stage1_result.model_artifacts.checkpoint_s3_path
)
eval_result.show()
```

## Common Pitfalls

| Problem                                    | Solution                                                                             |
| ------------------------------------------ | ------------------------------------------------------------------------------------ |
| `Cannot continue from LoRA with Full-Rank` | Keep same rank type across all stages                                                |
| Training starts from base model            | Use `model_s3_path=result.model_artifacts.checkpoint_s3_path` (not `output_s3_path`) |
| Starting Stage 2 before Stage 1 completes  | Check `result.get_job_status()` first                                                |
| Same hyperparameters all stages            | Reduce `lr` and `max_epochs` in later stages                                         |
| No evaluation between stages               | Always evaluate before continuing to verify improvement                              |

## Common Patterns

| Pattern       | Stage 1                     | Stage 2                | Stage 3       |
| ------------- | --------------------------- | ---------------------- | ------------- |
| Domain → Task | General domain SFT          | Task-specific SFT      | —             |
| SFT → RFT     | SFT to establish capability | RFT to optimize reward | —             |
| Curriculum    | Easy examples               | Medium examples        | Hard examples |
| Incremental   | Initial data                | New data batch         | —             |

## Best Practices

1. **Evaluate between stages** — only continue if performance improved
2. **Reduce learning rate** — smaller `lr` in later stages
3. **Keep method consistent** — don't mix LoRA and Full-Rank
4. **Save all checkpoints** — keep intermediate results for rollback
5. **Use dry run** — test each stage config before running

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
