# Nova Data Validation

Validates dataset format for Nova model training using the Forge SDK's `DatasetLoader.validate()`.

## Quick Usage

```python
from amzn_nova_forge import JSONLDatasetLoader
from amzn_nova_forge import Model, TrainingMethod
from amzn_nova_forge.dataset.operations import ValidateMethod

loader = JSONLDatasetLoader()
loader.load("s3://my-bucket/data.jsonl")
loader.show(n=5)  # Preview structure

loader.validate(
    method=ValidateMethod.INVALID_RECORDS,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
)
```

## What Validation Checks

- Required fields are present
- Field types and formats are correct
- Role alternation in conversations (user/assistant)
- Optional field consistency across samples
- Forbidden keywords in content

## For Evaluation Datasets

Pass the `eval_task` parameter:

```python
from amzn_nova_forge import EvaluationTask

loader.validate(
    method=ValidateMethod.INVALID_RECORDS,
    training_method=TrainingMethod.EVALUATION,
    model=Model.NOVA_LITE_2,
    eval_task=EvaluationTask.GEN_QA,
)
```

## Expected Column Names by Training Method

| Training Method    | Required Columns               | Optional Columns                                                   |
| ------------------ | ------------------------------ | ------------------------------------------------------------------ |
| SFT                | `question`, `answer`           | `system`, `image_format`, `video_format`, `s3_uri`, `bucket_owner` |
| SFT 2.0 (Nova 2.0) | `question`, `answer`           | All SFT + `reasoning_text`, `tools`/`toolsConfig`*                 |
| RFT                | `question`, `reference_answer` | `system`, `id`, `tools`*                                           |
| CPT                | `text`                         | —                                                                  |
| Evaluation         | `query`, `response`            | `images`, `metadata`                                               |

> \* `tools`/`toolsConfig` only supported when source is OpenAI Messages format.

If validation fails with "Missing required field", the user's column names don't match the expected names. They need to run the dataset-transformation skill to apply column mappings via `transform()`.

## Supported File Formats

- `JSONLDatasetLoader` — `.jsonl` files (newline-delimited JSON)
- `JSONDatasetLoader` — `.json` files
- `CSVDatasetLoader` — `.csv` files

All loaders support local paths and S3 URIs.
