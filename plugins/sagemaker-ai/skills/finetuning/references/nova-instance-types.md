## Instance Type Specs

This document defines the allowed instances types for each model/method combination and the training platform you're using (SMTJ, SMHP).

### SMTJRuntimeManager (SageMaker Training Jobs)

```python
from amzn_nova_forge import *

runtime = SMTJRuntimeManager(
    instance_type="ml.p5.48xlarge",
    instance_count=4
)
```

#### Supported Instance Types

##### SFT (Supervised Fine-Tuning)

Nova 1.0 Allowed Instance Types can be found via the [AWS public documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/nova-fine-tune-1.html).

| Model    | Run Type        | Allowed Instance Types (Allowed Instance Counts)       |
| -------- | --------------- | ------------------------------------------------------ |
| Lite 2.0 | LoRA, Full-Rank | ml.p5.48xlarge (4, 8, 16), ml.p5en.48xlarge (4, 8, 16) |

##### DPO (Direct Preference Optimization)

All DPO allowed instance type combinations can be found in the [AWS public documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/nova-fine-tune-1.html).

##### RFT (Reinforcement Fine-Tuning)

All RFT allowed instance type combinations can be found in the [AWS public documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/nova-reinforcement-fine-tuning.html#nova-rft-creating-jobs).

##### Evaluation

All allow 1, 2, 4, 8, or 16 instances.

| Model    | Allowed Instance Types                                                                                                                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Micro    | ml.g5.4xlarge, ml.g5.8xlarge, ml.g5.12xlarge, ml.g5.16xlarge, ml.g5.24xlarge, ml.g6.4xlarge, ml.g6.8xlarge, ml.g6.12xlarge, ml.g6.16xlarge, ml.g6.24xlarge, ml.g6.48xlarge, ml.p5.48xlarge |
| Lite     | ml.g5.12xlarge, ml.g5.24xlarge, ml.g6.12xlarge, ml.g6.24xlarge, ml.g6.48xlarge, ml.p5.48xlarge                                                                                             |
| Lite 2.0 | ml.p4d.24xlarge, ml.p5.48xlarge                                                                                                                                                            |
| Pro      | ml.p5.48xlarge                                                                                                                                                                             |

---

### SMHPRuntimeManager (SageMaker HyperPod)

```python
from amzn_nova_forge import *

runtime = SMHPRuntimeManager(
    instance_type="ml.p5.48xlarge",
    instance_count=4,
    cluster_name="my-hyperpod-cluster",
    namespace="kubeflow"
)
```

#### Supported Instance Types

##### CPT (Continous Pre-Training)

| Model    | Allowed Instance Types (Allowed Instance Counts) |
| -------- | ------------------------------------------------ |
| Micro    | ml.p5.48xlarge (2, 4, 8, 16, 32)                 |
| Lite     | ml.p5.48xlarge (4, 8, 16, 32)                    |
| Lite 2.0 | ml.p5.48xlarge (4, 8, 16, 32)                    |
| Pro      | ml.p5.48xlarge (6, 12, 24)                       |

##### SFT (Supervised Fine-Tuning)

| Model    | Run Type        | Allowed Instance Types (Allowed Instance Counts)       |
| -------- | --------------- | ------------------------------------------------------ |
| Micro    | LoRA, Full-Rank | ml.p5.48xlarge (2, 4, 8)                               |
| Lite     | LoRA, Full-Rank | ml.p5.48xlarge (4, 8, 16)                              |
| Lite 2.0 | LoRA, Full-Rank | ml.p5.48xlarge (4, 8, 16), ml.p5en.48xlarge (4, 8, 16) |
| Pro      | LoRA, Full-Rank | ml.p5.48xlarge (6, 12, 48)                             |

##### DPO (Direct Preference Optimization)

| Model | Run Type  | Allowed Instance Types (Allowed Instance Counts) |
| ----- | --------- | ------------------------------------------------ |
| Micro | LoRA      | ml.p5.48xlarge (2, 4, 8)                         |
| Micro | Full-Rank | ml.p5.48xlarge (2, 4, 8)                         |
| Lite  | LoRA      | ml.p5.48xlarge (4, 8, 16)                        |
| Lite  | Full-Rank | ml.p5.48xlarge (4, 8, 16)                        |
| Pro   | LoRA      | ml.p5.48xlarge (6, 12, 24)                       |
| Pro   | Full-Rank | ml.p5.48xlarge (6, 12, 24)                       |

##### RFT (Reinforcement Fine-Tuning)

| Model    | Run Type        | Allowed Instance Types (Allowed Instance Counts) |
| -------- | --------------- | ------------------------------------------------ |
| Lite 2.0 | LoRA, Full-Rank | ml.p5.48xlarge (2, 4, 8, 16)                     |

##### Evaluation

All allow 1, 2, 4, 8, or 16 instances.

| Model    | Allowed Instance Types                                                                                                                                                                     |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Micro    | ml.g5.4xlarge, ml.g5.8xlarge, ml.g5.12xlarge, ml.g5.16xlarge, ml.g5.24xlarge, ml.g6.4xlarge, ml.g6.8xlarge, ml.g6.12xlarge, ml.g6.16xlarge, ml.g6.24xlarge, ml.g6.48xlarge, ml.p5.48xlarge |
| Lite     | ml.g5.12xlarge, ml.g5.24xlarge, ml.g6.12xlarge, ml.g6.24xlarge, ml.g6.48xlarge, ml.p5.48xlarge                                                                                             |
| Lite 2.0 | ml.p4d.24xlarge, ml.p5.48xlarge                                                                                                                                                            |
| Pro      | ml.p5.48xlarge                                                                                                                                                                             |
