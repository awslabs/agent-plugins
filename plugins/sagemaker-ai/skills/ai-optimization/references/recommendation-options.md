# Recommendation Configuration Options

## Instance Types (optional)

For **latency** and **throughput** targets, the user can specify which instance types to evaluate:

> "Would you like to specify which instance types to evaluate, or let the service choose automatically?
>
> Examples: `ml.g5.xlarge`, `ml.g6.12xlarge`, `ml.p5.48xlarge`"

Note: **Cost** target does not support customer-specified instance types.

## Optimization (optional)

> "Should the service try to optimize the model?
>
> - **Kernel tuning** — Up to 30% improved TTFT and throughput
> - **Speculative decoding** — Up to 10x improved throughput
>
> **Heads up:** Without optimizations: 30–60 min. With: 2–10 hours.
>
> Default is yes (`OptimizeModel=True`). Set `OptimizeModel=False` to skip."

### Dataset Requirement for Throughput + Optimization

If **throughput** target AND `OptimizeModel=True`, a dataset is **required** for speculative decoding. Without it, the job fails with `ValidationError`.

Ask:

> "Since you chose throughput with optimizations, I need a dataset. Format:
>
> - **ShareGPT** — JSONL with `conversations` column: `[{"from": "human", "value": "..."}, ...]`
> - **OpenAI Chat** — JSONL with `messages` column: `[{"role": "user", "content": "..."}, ...]`
> - **OpenAI Completions** — JSONL with `prompt` column (optionally `completion`/`response`)
> - **File type:** `.jsonl`
> - **Location:** S3 prefix containing dataset files
>
> What's the S3 URI? (e.g., `s3://my-bucket/datasets/prompts/`)"

⏸ Wait for user.

Provide `DatasetConfig` on the **workload config** (not the recommendation job):

```python
sm.create_ai_workload_config(
    AIWorkloadConfigName=config_name,
    AIWorkloadConfigs={"WorkloadSpec": {"Inline": json.dumps(workload_spec)}},
    DatasetConfig={
        "InputDataConfig": [{
            "ChannelName": "datasets",
            "DataSource": {
                "S3DataSource": {
                    "S3DataType": "S3Prefix",
                    "S3Uri": "<DATASET_S3_URI>",
                }
            },
            "ContentType": "application/jsonl",
        }],
    },
)
```

## Workload Config

Required. If one doesn't exist, create it per `benchmark-workflow.md` Step 2.

## Inference Framework (optional)

> "Which inference framework?
>
> - **VLLM** — High-performance serving with PagedAttention
> - **LMI** — SageMaker Large Model Inference container
>
> Default: auto-selected based on the model."
