# Nova Forge SDK — Training Enums

Exact enum values for use in generated training code. This is the canonical reference for training-related enums — other skills that need these values should cross-reference this file.

## Model Enum

| Enum Value          | Model Type String              | Version | Context Length |
| ------------------- | ------------------------------ | ------- | -------------- |
| `Model.NOVA_MICRO`  | `amazon.nova-micro-v1:0:128k`  | 1.0     | 128k           |
| `Model.NOVA_LITE`   | `amazon.nova-lite-v1:0:300k`   | 1.0     | 300k           |
| `Model.NOVA_LITE_2` | `amazon.nova-2-lite-v1:0:256k` | 2.0     | 256k           |
| `Model.NOVA_PRO`    | `amazon.nova-pro-v1:0:300k`    | 1.0     | 300k           |

Lookup by model_type string:

```python
from amzn_nova_forge import Model
model = Model.from_model_type("amazon.nova-micro-v1:0:128k")
```

## TrainingMethod Enum

| Enum Value                          | Description                                |
| ----------------------------------- | ------------------------------------------ |
| `TrainingMethod.CPT`                | Continued Pre-Training                     |
| `TrainingMethod.SFT_LORA`           | Supervised Fine-Tuning with LoRA           |
| `TrainingMethod.SFT_FULL`           | Supervised Fine-Tuning (full rank)         |
| `TrainingMethod.DPO_LORA`           | Direct Preference Optimization with LoRA   |
| `TrainingMethod.DPO_FULL`           | Direct Preference Optimization (full rank) |
| `TrainingMethod.RFT_LORA`           | Reinforcement Fine-Tuning with LoRA        |
| `TrainingMethod.RFT_FULL`           | Reinforcement Fine-Tuning (full rank)      |
| `TrainingMethod.RFT_MULTITURN_LORA` | RFT Multiturn with LoRA                    |
| `TrainingMethod.RFT_MULTITURN_FULL` | RFT Multiturn (full rank)                  |
| `TrainingMethod.EVALUATION`         | Evaluation only                            |

## Platform Enum (for CloudWatchLogMonitor)

| Enum Value         | Description             |
| ------------------ | ----------------------- |
| `Platform.SMTJ`    | SageMaker Training Jobs |
| `Platform.SMHP`    | SageMaker HyperPod      |
| `Platform.BEDROCK` | Amazon Bedrock          |

## JobStatus Enum

| Enum Value              | Description                |
| ----------------------- | -------------------------- |
| `JobStatus.IN_PROGRESS` | Job is running             |
| `JobStatus.COMPLETED`   | Job completed successfully |
| `JobStatus.FAILED`      | Job failed                 |
