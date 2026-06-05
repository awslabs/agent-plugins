# OSS Model Best Practices

Best practices specific to open-source model customization (Llama, Mistral, Qwen, etc.) via SageMaker.

## Model Selection

- Check SageMaker Hub for available models and supported techniques before committing
- Verify the model's license is compatible with your use case
- For Meta/Llama models, the user must explicitly accept the EULA

## Technique Selection

- **SFT** — Best for tasks with clear input-output pairs and well-defined correct answers
- **DPO** — Best for preference alignment when you have chosen/rejected response pairs
- **RLVR** — Best for tasks with verifiable outcomes where you can write a reward function

## Training

- Use SageMaker Serverless Model Customization for simplicity
- The notebook-first workflow lets you review and modify code before execution
- Run cells one by one and monitor progress

## Data Format

- Training data format depends on both the model type and finetuning technique
- Always run dataset evaluation before training to catch format issues
- Evaluation datasets use a different format than training datasets

## Deployment

- Both SageMaker endpoints and Bedrock are supported for OSS models
- Only LoRA fine-tuned models are supported for deployment through this workflow
