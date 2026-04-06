# Typical End-to-End Model Customization Plan

A typical model customization workflow follows these steps in order:

1. **Define Use Case** — Capture the business problem, users, and success criteria. _(Skill: use-case-specification)_
2. **Finetuning Setup** — Choose a fine-tuning technique (SFT, DPO, or RLVR) and base model. _(Skill: finetuning-setup)_
3. **Evaluate Dataset** — Assess data quality, completeness, and format. _(Skill: dataset-evaluation)_
4. **Transform Dataset** — Convert the dataset to the required format for the selected fine-tuning technique and base model. _(Skill: dataset-transformation)_
5. **Fine-Tune Model** — Train a custom model using SageMaker. _(Skill: finetuning)_
6. **Evaluate Model** — Measure model performance against success criteria. _(Skill: model-evaluation)_
7. **Deploy Model** — Create an endpoint for inference. _(Skill: model-deployment)_

Not every plan needs every step. Users may skip steps if they already have the required artifacts (e.g., skip steps 3–4 if they have validated data, or skip to deployment if they have a trained model).

**Note:** This skills package does not support data generation. Do not suggest, offer, or imply that you have the ability to generate data. If the user asks about this, make it clear that the skills do not support this ability.

**Note:** Evaluation datasets require a different format than training datasets (e.g., SageMaker Eval `query`/`response` vs SFT `prompt`/`completion`). If the user has a separate eval dataset, it may need its own validation and transformation pass before model evaluation.
