---
name: data-preparation
description: Data loading, validation, transformation, and filtering for Nova model training using the Forge SDK dataset pipeline.
triggers:
  keywords: [data, dataset, load, csv, jsonl, json, parquet, arrow, huggingface, transform, validate, filter, split, column, format, prepare, dedup]
  task_types: [data-prep]
  error_patterns: ["DataPrepError", "Missing required field", "ValidationError"]
  methods: [SFT, RFT, CPT, DPO, EVALUATION]
prerequisites: []
last_verified: 2026-05-15
sdk_version: ">=1.4.0"
---

> Ensure you've loaded best practices from the agent-memory skill before guiding the customer.

# Data Preparation

## Key Concepts

### Dataset Loaders

The SDK provides 7 loaders with identical chainable APIs:

| Loader                     | File Types                   | Notes                                                            |
| -------------------------- | ---------------------------- | ---------------------------------------------------------------- |
| `JSONLDatasetLoader`       | `.jsonl`                     | Newline-delimited JSON                                           |
| `JSONDatasetLoader`        | `.json`                      | Standard JSON arrays                                             |
| `CSVDatasetLoader`         | `.csv`                       | Comma-separated values                                           |
| `ParquetDatasetLoader`     | `.parquet`, `.pq`            | Lazy batch-based iteration via PyArrow (one row group at a time) |
| `ArrowDatasetLoader`       | `.arrow`, `.feather`, `.ipc` | IPC Stream/File format with auto-fallback                        |
| `HuggingFaceDatasetLoader` | HuggingFace Hub              | Lazy loading with split/name/revision/data_files/data_dir params |
| `CloudWatchDatasetLoader`  | CloudWatch Logs              | Insights queries, JSON/text log parsing                          |

### Standard Workflow

```
load() → filter() → transform() → validate() → split() → save()
```

Each method returns the loader instance for chaining:

```python
loader.load("data.jsonl").filter(
    method=FilterMethod.INVALID_RECORDS,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
).transform(
    method=TransformMethod.SCHEMA,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2,
    column_mappings={"question": "q", "answer": "a"}
).validate(
    method=ValidateMethod.INVALID_RECORDS,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
).save("output.jsonl")
```

### Filter Methods

| Method                             | Description                         |
| ---------------------------------- | ----------------------------------- |
| `FilterMethod.DEFAULT_TEXT_FILTER` | Basic text quality filtering        |
| `FilterMethod.EXACT_DEDUP`         | Remove exact duplicate records      |
| `FilterMethod.FUZZY_DEDUP`         | Remove near-duplicate records       |
| `FilterMethod.LANGUAGE_DETECTION`  | Filter by language                  |
| `FilterMethod.INVALID_RECORDS`     | Remove records that fail validation |

### Validate Methods

| Method                           | Description                                                      |
| -------------------------------- | ---------------------------------------------------------------- |
| `ValidateMethod.INVALID_RECORDS` | **Default.** Validates records against training method and model |
| `ValidateMethod.SCHEMA`          | Legacy schema-only validation (deprecated but supported)         |

### Data Prep Runtime (for server-side operations)

| Runtime              | Status                 | Notes                                        |
| -------------------- | ---------------------- | -------------------------------------------- |
| `SMTJRuntimeManager` | **Default, strategic** | Standard SageMaker runtime for data prep     |
| `GlueRuntimeManager` | Legacy                 | Closed to new customers after April 30, 2026 |

### Column Mappings

| Training Method    | Required Columns               | Optional Columns                                                   |
| ------------------ | ------------------------------ | ------------------------------------------------------------------ |
| SFT                | `question`, `answer`           | `system`, `image_format`, `video_format`, `s3_uri`, `bucket_owner` |
| SFT 2.0 (Nova 2.0) | `question`, `answer`           | All SFT + `reasoning_text`, `tools`/`toolsConfig`*                 |
| RFT                | `question`, `reference_answer` | `system`, `id`, `tools`*                                           |
| CPT                | `text`                         | —                                                                  |
| Evaluation         | `query`, `response`            | `images`, `metadata`                                               |

> \* `tools`/`toolsConfig` only supported when transforming from **OpenAI Messages format**.

### Path Resolution

Loaders accept:

- Absolute/relative local paths (tilde `~` and `..` segments resolved)
- S3 URIs (`s3://bucket/path`)
- Directory paths (all matching files loaded as a single stream)

## Step-by-Step Guide

### 1. Load Data

```python
from amzn_nova_forge import JSONLDatasetLoader

loader = JSONLDatasetLoader()
loader.load("data.jsonl")  # or S3: "s3://bucket/data.jsonl"
```

**From Parquet:**

```python
from amzn_nova_forge import ParquetDatasetLoader

loader = ParquetDatasetLoader()
loader.load("s3://bucket/data.parquet")
```

**From HuggingFace Hub:**

```python
from amzn_nova_forge import HuggingFaceDatasetLoader

loader = HuggingFaceDatasetLoader()
loader.load("org/dataset-name", split="train", revision="main")
```

**From CloudWatch Logs:**

```python
from amzn_nova_forge import CloudWatchDatasetLoader

loader = CloudWatchDatasetLoader()
loader.load(
    log_group="/aws/lambda/my-function",
    query="fields @message | filter @message like /ERROR/",
    start_time="2026-01-01T00:00:00Z",
    end_time="2026-01-02T00:00:00Z"
)
```

### 2. Inspect Data

```python
loader.show(n=5)
```

### 3. Filter (Optional)

```python
from amzn_nova_forge.dataset.operations import FilterMethod

# Remove invalid records
loader.filter(
    method=FilterMethod.INVALID_RECORDS,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
)

# Remove exact duplicates
loader.filter(method=FilterMethod.EXACT_DEDUP)

# Remove near-duplicates
loader.filter(method=FilterMethod.FUZZY_DEDUP)

# Filter by language
loader.filter(method=FilterMethod.LANGUAGE_DETECTION, language="en")
```

### 4. Transform to Training Format

```python
from amzn_nova_forge.dataset.operations import TransformMethod
from amzn_nova_forge import Model, TrainingMethod

loader.transform(
    method=TransformMethod.SCHEMA,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2,
    column_mappings={"question": "input", "answer": "output"}
)
```

**SFT 2.0 with Reasoning (Nova 2.0):**

```python
loader.transform(
    method=TransformMethod.SCHEMA,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2,
    column_mappings={
        "question": "prompt",
        "answer": "completion",
        "reasoning_text": "chain_of_thought"
    }
)
```

**OpenAI Messages format (auto-detected, no column mappings needed):**

```python
loader.load("openai_format.jsonl")
loader.transform(
    method=TransformMethod.SCHEMA,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
)
```

**Multimodal data:**

```python
loader.transform(
    method=TransformMethod.SCHEMA,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2,
    column_mappings={
        "question": "caption_prompt",
        "answer": "caption",
        "image_format": "image_format",
        "s3_uri": "s3_uri",
        "bucket_owner": "bucket_owner"
    }
)
```

### 5. Validate

```python
from amzn_nova_forge.dataset.operations import ValidateMethod

loader.validate(
    method=ValidateMethod.INVALID_RECORDS,
    training_method=TrainingMethod.SFT_LORA,
    model=Model.NOVA_LITE_2
)
```

For evaluation datasets:

```python
from amzn_nova_forge import EvaluationTask

loader.validate(
    method=ValidateMethod.INVALID_RECORDS,
    training_method=TrainingMethod.EVALUATION,
    model=Model.NOVA_LITE_2,
    eval_task=EvaluationTask.GEN_QA
)
```

### 6. Split (Optional)

```python
train, val, test = loader.split(
    train_ratio=0.8,
    val_ratio=0.1,
    test_ratio=0.1,
    seed=42
)
```

### 7. Save

```python
train.save("s3://bucket/train.jsonl")
val.save("s3://bucket/val.jsonl")
test.save("s3://bucket/test.jsonl")
```

## Troubleshooting

### Data Validation Errors

**Symptoms:** `DataPrepError`, `ValidationError`, job fails during data loading phase.

**Solutions:**

1. **Missing fields** — use `column_mappings`:

   ```python
   loader.transform(
       method=TransformMethod.SCHEMA,
       training_method=TrainingMethod.SFT_LORA,
       model=Model.NOVA_LITE_2,
       column_mappings={"question": "prompt", "answer": "completion"}
   )
   ```

2. **Wrong format** — inspect with `loader.show(n=1)` to see actual column names
3. **Validate early** — always call `.validate()` before `.save()`
4. **Use INVALID_RECORDS filter** — removes non-conforming records rather than failing

### Incomplete Multimodal Mappings

**Problem:** Providing only `image_format` without `s3_uri` and `bucket_owner`.

**Solution:** All three must be provided together for multimodal data.

### Tools/ToolsConfig from Generic Format

**Problem:** Providing `tools` column mappings when transforming from generic Q/A format.

**Solution:** `tools`/`toolsConfig` only supported from OpenAI Messages format. Convert to OpenAI format first if tool use is needed.

## Supported Transformations

| Source Format                              | Target                                      | Supported Features                            |
| ------------------------------------------ | ------------------------------------------- | --------------------------------------------- |
| Generic Q/A (CSV/JSON/JSONL/Parquet/Arrow) | SFT 1.0, SFT 2.0 (no tools), RFT, Eval, CPT | Column mappings, multimodal, `reasoning_text` |
| OpenAI Messages                            | SFT 1.0, SFT 2.0 (with tools)               | All above + `tools`, `toolsConfig`            |
| HuggingFace Hub                            | Any above                                   | Lazy loading, auto-detect format              |
| CloudWatch Logs                            | Any above                                   | Insights queries, JSON/text parsing           |

## Best Practices

1. **Always validate before saving** — catches format errors early
2. **Use `.show()` liberally** — preview data at each step
3. **Use INVALID_RECORDS filter** — remove bad records instead of failing the whole dataset
4. **Set a seed for splits** — ensures reproducible train/val/test splits
5. **Save to S3 directly** — avoids local disk space issues
6. **Check column names first** — `loader.show(n=1)` before mapping
7. **Use Parquet/Arrow for large datasets** — lazy loading avoids memory issues

---

_Last verified against amzn-nova-forge SDK v1.4.0+ on 2026-05-15._
