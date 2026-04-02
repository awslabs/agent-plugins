# Notebook Structure

Cell order, placeholders, and JSON formatting for the evaluation notebook.

## Cells

| Cell | Label                                                  | Source                             |
| ---- | ------------------------------------------------------ | ---------------------------------- |
| 0    | Markdown header: `# SageMaker LLM-as-Judge Evaluation` | —                                  |
| 1    | Configuration                                          | `scripts/notebook_cells.py` Cell 1 |
| 2    | Start Evaluation                                       | `scripts/notebook_cells.py` Cell 2 |
| 3    | Wait for Completion                                    | `scripts/notebook_cells.py` Cell 3 |
| 4    | Show Results                                           | `scripts/notebook_cells.py` Cell 4 |

## Placeholders (Cell 1 only)

| Placeholder             | Description                                                                        | Example                                                          |
| ----------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `[REGION]`              | AWS region                                                                         | `us-west-2`                                                      |
| `[MODEL_ARN]`           | Model package ARN                                                                  | `arn:aws:sagemaker:us-west-2:123456789:model-package/my-model/1` |
| `[DATASET_S3_URI]`      | Evaluation dataset S3 path                                                         | `s3://bucket/data.jsonl`                                         |
| `[JUDGE_MODEL]`         | Judge model ID                                                                     | `anthropic.claude-3-5-haiku-20241022-v1:0`                       |
| `[METRICS_LIST]`        | Built-in metrics as quoted strings, or empty list                                  | `"Completeness", "Correctness"` or `None`                        |
| `[CUSTOM_METRICS_JSON]` | `json.load(open("custom_metrics.json"))` if custom metrics exist, otherwise `None` | See below                                                        |
| `[S3_OUTPUT_PATH]`      | S3 output path                                                                     | `s3://bucket/eval-output/`                                       |
| `[TRUE_OR_FALSE]`       | Compare to base model                                                              | `True`                                                           |

### Custom Metrics Placeholder

When the user has no custom metrics, substitute `[CUSTOM_METRICS_JSON]` with `None`.

When the user has custom metrics, the validated `custom_metrics.json` file sits next to the notebook. Substitute `[CUSTOM_METRICS_JSON]` with a `json.load` call:

```python
CUSTOM_METRICS = json.load(open("custom_metrics.json"))
```

Do not inline the JSON into the notebook. The validated file is the source of truth.

## JSON Formatting

Each line of code is a separate string in `source`, ending with `\n` (except the last line):

```json
{
  "cell_type": "code",
  "execution_count": null,
  "metadata": {},
  "outputs": [],
  "source": [
    "import os\n",
    "x = 5\n",
    "print(x)"
  ]
}
```

- Escape quotes inside strings: `\"`
- No trailing commas in arrays or objects
- 2-space indentation
- Use `fs_write` with `command: create` to write the complete notebook JSON
- Markdown cell 0: `"cell_type": "markdown"`, no `execution_count` or `outputs`
- Wrap all cells in `{"cells": [...], "metadata": {...}, "nbformat": 4, "nbformat_minor": 4}`
