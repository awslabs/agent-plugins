# End-to-End Model Customization Plan

**Recommended for:** users who are certain they want to finetune a model, and users who clearly communicate that they want to finetune a model

1. **Define Use Case** — Capture the business problem, users, and success criteria. _(Skill: use-case-specification)_
2. **Select Base Model** — Choose a base model from SageMaker Hub based on benchmarks and use case fit. _(Skill: model-selection)_
3. **Verify Environment** — Check SDK version, region, and execution role are configured. _(Skill: sdk-getting-started)_
4. **Select Finetuning Technique** — Choose a fine-tuning technique and validate compatibility with the selected model. _(Skill: finetuning-technique)_
5. **Evaluate Dataset** — Assess data quality, completeness, and format. _(Skill: dataset-evaluation)_
6. **Transform Dataset** — Convert the dataset to the required format for the selected fine-tuning technique and base model. _(Skill: dataset-transformation)_
7. **Fine-Tune Model** — Train a custom model using SageMaker. _(Skill: finetuning)_
8. **Evaluate Model** — Measure model performance against success criteria. _(Skill: model-evaluation)_
9. **Deploy Model** — Create an endpoint for inference. _(Skill: model-deployment)_

**Note:** This skills package does not support data generation. Do not suggest, offer, or imply that you have the ability to generate data. If the user asks about this, make it clear that the skills do not support this ability.
