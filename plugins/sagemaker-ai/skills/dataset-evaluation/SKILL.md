---
name: dataset-evaluation
description: Validates dataset formatting and quality for SageMaker model fine-tuning (SFT, DPO, or RLVR). Use when the user says "is my dataset okay", "evaluate my data", "check my training data", "I have my own data", or before starting any fine-tuning job. Detects file format, checks schema compliance against the selected model and technique, and reports whether the data is ready for training or evaluation.
metadata:
  version: "1.0.0"
---

# Workflow Instruction

Follow the workflow shown below. Locate the dataset, check the file type, and resolve any issues with missing files or wrong file types. Determine the fine-tuning model and fine-tuning strategy. Run the appropriate validation based on the model family. Summarize the results: is the dataset ready for fine-tuning?

## Prerequisites

- The SDK environment has been verified (SDK version, region, execution role). If not done, activate the `sdk-getting-started` skill first.

---

## Workflow

1. **Locate Dataset**:
   - The full path may be a local file path, or an S3 URI
   - Resolve the full path to the dataset file, make sure read permissions are available, and help the user if the file is not found

2. **Determine strategy and model**:
   - File formatting depends on the currently selected fine-tuning strategy and fine-tuning base model.
   - If the strategy and model are already known from the conversation context (e.g., selected via the model-selection and finetuning-technique skills), use them.
   - If not available in context, activate the model-selection and/or finetuning-technique skills to determine them before proceeding.
   - **Exception:** If the user is validating an evaluation dataset (not a training dataset), neither model nor technique is required — the format detector can validate eval format (query/response structure) independently. Do not block on model-selection or finetuning-technique for eval dataset validation.

3. **Check File Formatting**: Run the tool format_detector.py to make sure the file conforms to formatting requirements.
   - Send the full path directly to the format_detector script as an argument
   - Do not send the model and strategy as arguments
   - Do not download data from S3
   - Do not make local copies of data

4. **Summarize Results**: Tell the user if their data is ready
   - Examine the output of format_detector and compare to the known strategy and model
   - **Important: training datasets and evaluation datasets have different format requirements.**
     - **Training datasets** must match the fine-tuning strategy format per `references/strategy_data_requirements.md`
     - **Evaluation datasets** (for model evaluation) must match one of the [SageMaker evaluation dataset formats](https://docs.aws.amazon.com/sagemaker/latest/dg/model-customize-evaluation-dataset-formats.html).
     - **Custom Scorer evaluation datasets** have scorer-specific requirements. If the dataset is intended for Custom Scorer evaluation (Prime Math, Prime Code, or Custom Lambda), read `references/custom-scorer-evaluation-dataset-formats.md` and validate against the scorer-specific schema. The scorer type should be known from conversation context (determined in the model-evaluation skill).
   - Report back to the user if their current dataset is valid for its intended purpose
   - Warn the user if their dataset is valid, but for a different strategy or model
   - Warn the user if their dataset is not valid for any strategy/model pair
   - If the user plans to finetune a model with the evaluated dataset, it needs to be uploaded to an S3 bucket in the same region as the planned training job (usually the default region). Warn the user if this is NOT the case.
   - If the dataset is NOT in the necessary format, recommend transforming it using the dataset-transformation skill, wait for user confirmation, and update the plan based on their response

## Messages to the User

- Introduction: "This skill checks the structure of your dataset for model fine-tuning."
- File types: This skill applies to files that are formatted according to the [Amazon SageMaker AI Developer Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-llms-finetuning-data-format.html#autopilot-llms-finetuning-dataset-format)

# Resources

- scripts/format_detector.py is self-contained format validation script that can be run independently
- model-selection and finetuning-technique skills should have already determined the base model and fine-tuning strategy
- references/strategy_data_requirements.md contains data format requirements per strategy

## Script Details

- scripts/format_detector.py is self-contained format validation script that can be run independently:

```bash
# With the file path argument identified in workflow step 1
python scripts/format_detector.py local_path/to/dataset
```

## References

- `scripts/format_detector.py` — Self-contained format validation script
- `references/strategy_data_requirements.md` — Data format requirements per strategy
