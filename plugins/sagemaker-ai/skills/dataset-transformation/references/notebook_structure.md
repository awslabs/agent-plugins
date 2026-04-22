# Dataset Transformation Notebook Structure

Cell order, placeholders, and JSON formatting for the dataset transformation notebook.

## Cells

| Cell | Label                                       | Content                                                           |
| ---- | ------------------------------------------- | ----------------------------------------------------------------- |
| 0    | Markdown header: `# Dataset Transformation` | Description of the transformation (source format → target format) |
| 1    | Configuration                               | Input/output paths, region, any user-configurable parameters      |
| 2    | Transformation Function                     | The approved `transform_dataset(df)` function from Step 6         |
| 3    | Load Dataset                                | Load dataset using `load_dataset_from` and read into DataFrame    |
| 4    | Transform                                   | Apply `transform_dataset(df)` and preview transformed records     |
| 5    | Save Output                                 | Write transformed DataFrame and upload using `output_dataset_to`  |

## Placeholders (Cell 1 only)

| Placeholder         | Description                           | Example                                 |
| ------------------- | ------------------------------------- | --------------------------------------- |
| `[INPUT_LOCATION]`  | S3 URI or local path to input dataset | `s3://bucket/data/input.jsonl`          |
| `[OUTPUT_LOCATION]` | S3 URI or local path for output       | `s3://bucket/output/input_openai.jsonl` |

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
- Write notebooks using your standard file write tool to create the `.ipynb` file with the complete notebook JSON, OR use notebook MCP tools (e.g., `create_notebook`, `add_cell`) if available in the current environment
- **DON'T** use bash commands, shell scripts, or `echo`/`cat` piping to generate notebooks
- Markdown cell 0: `"cell_type": "markdown"`, no `execution_count` or `outputs`
- Wrap all cells in `{"cells": [...], "metadata": {...}, "nbformat": 4, "nbformat_minor": 4}`
