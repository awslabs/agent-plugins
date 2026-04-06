---
name: mlops
description: End-to-end MLOps guidance on AWS — platform selection, training, inference, pipelines, monitoring, and cost optimization. This skill should be used when the user asks to "build an ML pipeline", "deploy a model on SageMaker", "set up MLOps", "configure SageMaker Pipelines", "choose between SageMaker and Bedrock", "deploy ML models to production", "set up model monitoring", "use MLflow on AWS", "train a model with Spot instances", "configure inference endpoints", "set up distributed training", or mentions SageMaker, MLflow, Kubeflow, ML pipelines, model registry, model monitoring, hyperparameter tuning, inference endpoints, or MLOps on AWS.
---

Specialist guidance for MLOps on AWS. Covers platform selection, training job configuration, inference deployment patterns, CI/CD for ML, experiment tracking, model monitoring, and cost optimization.

## Process

1. Identify the ML workload characteristics: model type (classical ML, deep learning, foundation model), training data volume, inference latency requirements, traffic pattern, team expertise
2. Use the `aws-docs` MCP tools to verify current SageMaker instance types, limits, pricing, and feature availability
3. Select the appropriate MLOps platform using the decision matrix below
4. Design the training infrastructure (instance selection, distributed strategy, Spot configuration)
5. Design the inference topology (real-time, serverless, batch, async)
6. Configure the ML pipeline (SageMaker Pipelines, Step Functions, or CI/CD integration)
7. Set up experiment tracking (MLflow on SageMaker or SageMaker Experiments)
8. Configure model monitoring (data quality, model quality, bias drift, feature attribution drift)
9. Recommend cost optimization strategies (Spot training, Savings Plans, Inferentia/Trainium, right-sizing)

## Platform Selection Decision Matrix

| Requirement | Recommendation | Why |
|---|---|---|
| End-to-end ML platform, team wants managed infrastructure | SageMaker (full) | Integrated training, tuning, deployment, monitoring, and model registry in one service; eliminates infrastructure management |
| CI/CD for ML with automated retraining and approval workflows | SageMaker Pipelines | Native step types for Processing, Training, Tuning, Transform, Model, Condition, and Callback; integrates with Model Registry for approval gates |
| Team already uses MLflow, needs portability across clouds | MLflow on SageMaker (managed) | Zero-infrastructure MLflow tracking server with automatic SageMaker Model Registry sync; preserves existing MLflow workflows |
| Customizing a foundation model without managing training infra | Bedrock fine-tuning / continued pre-training | No instance selection, no distributed training config, no checkpointing — AWS manages all training infrastructure; pay per training token |
| Kubernetes-native teams with existing EKS clusters | Kubeflow on EKS | Leverages existing K8s expertise and cluster; full control over scheduling, GPU sharing, and custom operators; but significant operational overhead |
| Simple orchestration for inference-only or lightweight training | Step Functions + Lambda | Event-driven, serverless, pay-per-execution; appropriate when training is infrequent and models are small enough for Lambda memory limits |
| Large-scale foundation model training (billions of parameters) | SageMaker HyperPod | Persistent managed clusters with automatic fault detection and repair; checkpointless recovery; supports Slurm and EKS orchestration |

## Training Instance Selection

### Training Instances

| Instance Family | Accelerator | Use Case | Price-Performance Notes |
|---|---|---|---|
| **ml.trn1 / ml.trn1n** | AWS Trainium | Large model training (LLMs, diffusion) | Up to 50% cheaper than comparable GPU instances for supported architectures; requires Neuron SDK |
| **ml.p5.48xlarge** | 8x NVIDIA H100 | Largest models, highest performance | Most powerful GPU option; use when Trainium does not support the model architecture |
| **ml.p4d.24xlarge** | 8x NVIDIA A100 | Large model training | Previous-gen flagship; still strong for most distributed training |
| **ml.g5.xlarge-48xlarge** | NVIDIA A10G | Medium models, fine-tuning | Good balance of cost and capability for fine-tuning and smaller training jobs |
| **ml.m5.large-24xlarge** | CPU only | Classical ML (XGBoost, sklearn) | No GPU overhead; appropriate for tree-based models and tabular data |

### Inference Instances

| Instance Family | Accelerator | Use Case | Price-Performance Notes |
|---|---|---|---|
| **ml.inf2** | AWS Inferentia2 | LLM and generative AI inference | Up to 4x higher throughput and 10x lower latency vs Inf1; 50%+ cheaper than GPU for supported models |
| **ml.g5** | NVIDIA A10G | General-purpose GPU inference | Broad framework support; use when Inferentia does not support the model |
| **ml.g4dn** | NVIDIA T4 | Cost-effective GPU inference | Previous-gen but still the cheapest GPU option for small-medium models |
| **ml.c7g / ml.c6g** | Graviton (CPU) | CPU inference for classical ML | Best price-performance for models that do not need GPU (XGBoost, sklearn, small NLP) |
| **Serverless** | Auto-managed | Sporadic or unpredictable traffic | No idle cost; 1-6 GB memory; cold start latency of seconds; max 60s processing time |

### Default to Trainium/Inferentia When Possible

Always evaluate ml.trn1 for training and ml.inf2 for inference before selecting GPU instances. Trainium offers up to 50% cost savings for training and Inferentia2 offers 50%+ cost savings for inference on supported model architectures. The AWS Neuron SDK supports PyTorch and TensorFlow natively. Only fall back to GPU instances when the model architecture is not supported by the Neuron compiler (check the Neuron model support matrix) or when the team needs CUDA-specific libraries.

## Inference Deployment Decision Matrix

| Pattern | Latency | Max Payload | Timeout | Cost Model | When to Use |
|---|---|---|---|---|---|
| **Real-time endpoint** | Low (ms) | 25 MB | 60s (8 min streaming) | Per-instance-hour (always running) | Consistent traffic with latency SLAs; use auto-scaling to match demand |
| **Serverless inference** | Medium (cold start) | 4 MB | 60s | Per-request + per-ms compute | Sporadic traffic with idle periods; eliminates idle instance cost entirely |
| **Batch transform** | High (minutes-hours) | 100 MB/record | Days | Per-instance-hour (job duration) | Offline scoring of large datasets; no persistent endpoint needed |
| **Async inference** | Medium-high | 1 GB | 1 hour | Per-instance-hour (scale to 0) | Large payloads or long processing; queue-based with SNS notifications |

### Real-time Endpoint Patterns

- **Single-model endpoint**: One model per endpoint. Simplest. Use for most production deployments.
- **Multi-model endpoint (MME)**: Thousands of models behind one endpoint, loaded on demand from S3. Use when you have many similar models (per-customer, per-region) and cannot justify an endpoint per model. Trade-off: first-request latency while loading a model.
- **Multi-container endpoint**: Up to 15 containers per endpoint, invoked individually or as a serial pipeline. Use for A/B testing different model versions or combining pre/post-processing with inference.
- **Shadow testing**: Route production traffic to both current and candidate models simultaneously. Compare metrics before promoting. Always use shadow testing before replacing a production model because it reveals performance differences under real traffic that offline evaluation cannot capture.

### Auto-Scaling

Default to target-tracking scaling on `SageMakerVariantInvocationsPerInstance` because it automatically adjusts instance count based on actual request load without requiring manual threshold tuning.

```
Target value: start at 70% of the max RPS the instance can handle (benchmark first)
Scale-in cooldown: 300 seconds (prevent flapping)
Scale-out cooldown: 60 seconds (respond quickly to load spikes)
```

Use Inference Recommender before production deployment to benchmark instance types and find the optimal instance/model combination. It runs load tests and reports latency, throughput, and cost per inference, replacing guesswork with data.

## SageMaker Pipelines

### Pipeline Step Types

| Step | Purpose | Notes |
|---|---|---|
| **Processing** | Data prep, feature engineering, evaluation | Runs a processing container (sklearn, Spark, custom) |
| **Training** | Model training | Supports all SageMaker training job features including Spot |
| **Tuning** | Hyperparameter optimization | Bayesian, Random, Grid, or Hyperband strategies |
| **Transform** | Batch inference | Run batch predictions as a pipeline step |
| **Model** | Create/register model | Register in Model Registry with metadata |
| **Condition** | Branching logic | Route pipeline based on metrics (e.g., accuracy threshold) |
| **Callback** | External integration | Wait for external approval or process completion |
| **Lambda** | Run a Lambda function | Lightweight compute for custom logic |
| **QualityCheck** | Data/model quality check | Integrates with Model Monitor baselines |
| **ClarifyCheck** | Bias and explainability | Integrates with SageMaker Clarify |
| **Fail** | Terminate with error | Explicit failure with message for debugging |

### Model Registry

The Model Registry is the central artifact store for production ML. Always register models through the registry because it provides:
- **Version tracking**: Every model gets an immutable version number with metadata (metrics, parameters, data lineage)
- **Approval workflows**: Models must be explicitly approved (manual or automated) before deployment, preventing untested models from reaching production
- **Lineage**: Links model versions to the training job, dataset, pipeline execution, and code commit that produced them
- **Cross-account deployment**: Approved models can be deployed to staging/production accounts via resource policies

### Pipeline Best Practices

- **Parameterize everything**: Instance types, data paths, hyperparameters, and thresholds should be pipeline parameters, not hardcoded values. This enables reuse across environments (dev/staging/prod) without code changes.
- **Use Condition steps for quality gates**: After training, compare the candidate model metric against a threshold. Only register and deploy if the metric passes. This prevents model regressions from reaching production.
- **Cache pipeline steps**: Enable step caching to skip unchanged steps on re-execution, reducing pipeline run time and cost.
- **Trigger pipelines from CI/CD**: Use CodePipeline or GitHub Actions to trigger SageMaker Pipelines on code merge, creating a full ML CI/CD loop.

## MLflow on AWS

### Managed MLflow on SageMaker (Recommended Default)

Use managed MLflow on SageMaker as the default experiment tracking solution because it requires zero infrastructure management, scales automatically, and synchronizes with SageMaker Model Registry automatically.

- **MLflow Apps**: Latest offering with faster startup, cross-account sharing, and automatic model registration
- **MLflow Tracking Servers**: Traditional MLflow with configurable compute and storage; each project can have its own server
- Artifacts stored in S3 (durable, shareable, versioned)
- Native integration with SageMaker training jobs — metrics logged automatically
- Models registered in MLflow automatically appear in SageMaker Model Registry
- Deploy MLflow models directly to SageMaker endpoints without custom containers

### Self-Hosted MLflow on EKS

Only choose self-hosted MLflow when you need custom plugins, specific MLflow versions not yet supported by the managed service, or multi-cloud portability with a single MLflow backend.

- Deploy MLflow server as a Kubernetes Deployment on EKS
- Use Amazon RDS (PostgreSQL) as the metadata/backend store for durability and query performance
- Use S3 as the artifact store with a dedicated bucket and lifecycle policies
- Front with an ALB + Cognito or IAM for authentication
- Operational overhead: you own patching, scaling, backups, and availability

### When to Choose MLflow over Native SageMaker Experiments

- Team has existing MLflow workflows and muscle memory
- Multi-cloud or hybrid-cloud requirement where portability matters
- Need for MLflow-specific features (Prompt Registry, advanced tracing for agentic workflows)
- Want a single UI for experiment comparison across SageMaker and non-SageMaker training runs

## Model Monitoring

### Four Monitoring Dimensions

| Monitor Type | What It Detects | Baseline Source | When to Use |
|---|---|---|---|
| **Data Quality** | Schema violations, missing values, statistical drift in input features | Training dataset statistics | Always — this is the earliest signal that something changed |
| **Model Quality** | Accuracy/precision/recall/RMSE degradation | Baseline predictions + ground truth | When ground truth labels are available (even delayed) |
| **Bias Drift** | Changes in model fairness across demographic groups | Pre-deployment bias metrics from Clarify | When the model makes decisions affecting people (lending, hiring, content) |
| **Feature Attribution Drift** | Shifts in which features drive predictions | SHAP values from Clarify baseline | When you need to explain why predictions changed, not just that they changed |

### Monitoring Setup

1. **Enable Data Capture** on the endpoint to log inputs and outputs to S3 (asynchronous, no performance impact on inference)
2. **Create baselines** from the training dataset using `DefaultModelMonitor` for data quality or `ModelQualityMonitor` for model quality
3. **Schedule monitoring jobs** — hourly for high-traffic endpoints, daily for moderate traffic
4. **Configure CloudWatch alarms** on monitoring violations to trigger SNS notifications
5. **Automate retraining**: Use EventBridge to trigger a SageMaker Pipeline re-execution when monitoring detects sustained drift

### When to Retrain vs When to Investigate

- **Retrain** when data quality monitoring shows gradual statistical drift (feature distributions shifting over time) and the model's accuracy metrics are declining — this is expected model staleness
- **Investigate first** when monitoring shows sudden, sharp changes — this typically indicates an upstream data pipeline issue, a schema change, or a bug, not genuine drift; retraining on bad data makes things worse

## Distributed Training

### Data Parallel

Use data parallel training when the model fits in a single GPU's memory but training is slow due to dataset size. Each GPU processes a different data batch, gradients are synchronized across GPUs. SageMaker's distributed data parallelism (SMDDP) library optimizes AllReduce/AllGather operations for better inter-node communication.

### Model Parallel

Use model parallel training when the model does not fit in a single GPU's memory (large language models, large vision transformers). SageMaker's model parallelism (SMP) library supports tensor parallelism, pipeline parallelism, and expert parallelism. Use EFA-enabled instances (ml.p4d, ml.p5, ml.trn1) for model parallel training because inter-node communication is the bottleneck and EFA provides 400-3200 Gbps networking.

### Hyperparameter Tuning Strategies

| Strategy | When to Use | Notes |
|---|---|---|
| **Bayesian** (default) | Most cases | Uses prior results to choose next trials; converges faster with fewer trials |
| **Random** | Large search spaces with many parameters | Good baseline; easy to parallelize |
| **Grid** | Small discrete search spaces | Exhaustive; only practical with few parameters and few values each |
| **Hyperband** | Need results fast on a budget | Early-stops poor configurations; allocates more resources to promising ones |

Always use Bayesian optimization as the default because it typically finds better hyperparameters in fewer trials than random search, directly reducing training cost.

## Cost Optimization

### Managed Spot Training

Always use Managed Spot Training for training jobs because training is inherently fault-tolerant (checkpointing lets you resume from the last saved state) and Spot provides 60-90% savings over On-Demand. The only exception is ultra-time-sensitive training where any interruption is unacceptable (rare in practice).

- Enable with `use_spot_instances=True` in the Estimator
- Set `max_wait` to 2x the expected training time to allow for interruptions
- Enable checkpointing to S3 so training resumes from the last checkpoint, not from scratch
- SageMaker automatically handles Spot interruption, checkpoint save, and job restart

### SageMaker Savings Plans

Commit to consistent SageMaker usage (measured in $/hour) for 1 or 3 years. Savings Plans cover Studio Notebooks, Processing, Training, Real-Time Inference, and Batch Transform. Up to 64% savings over On-Demand. Use for production inference endpoints that run continuously.

### Serverless Inference for Sporadic Traffic

Use Serverless Inference instead of real-time endpoints when traffic is sporadic or unpredictable. Real-time endpoints charge per instance-hour even when idle; Serverless charges per request and per millisecond of compute. A real-time ml.m5.large endpoint costs ~$100/month idle. Serverless at 100 requests/day costs under $5/month.

### Instance Right-Sizing with Inference Recommender

Run SageMaker Inference Recommender before deploying to production. It benchmarks your model across instance types and reports latency percentiles, throughput, and cost per inference. Teams that skip this step typically overprovision by 2-3x because they guess conservatively.

### Trainium and Inferentia

Evaluate Trainium (ml.trn1) for training and Inferentia2 (ml.inf2) for inference on every ML project. For supported model architectures (most PyTorch and TensorFlow models), these custom silicon instances deliver 50%+ cost savings compared to GPU instances. The Neuron SDK compiles models for these chips with minimal code changes. Only skip when the model uses CUDA-specific operations that Neuron does not support.

## Anti-Patterns

- **Training on notebooks instead of training jobs.** Notebook training is not reproducible, cannot use Spot instances (60-90% savings lost), cannot distribute across multiple instances, and produces no training job metadata for lineage tracking. Always convert notebook experiments to SageMaker Training Jobs for anything beyond initial prototyping.

- **Skipping Model Registry.** Without a registry, there is no version history, no approval workflow, no lineage from model to training data, and no clean rollback path. A bad model deployed without registry tracking requires manual forensics to identify what changed.

- **Real-time endpoints for batch workloads.** A real-time endpoint running 24/7 to process a nightly batch job wastes money on 23 hours of idle compute. Batch Transform provisions instances only for the job duration and terminates them automatically.

- **Single large instance instead of distributed training.** A single ml.p5.48xlarge costs more per hour than multiple smaller instances delivering equivalent total compute. Distributed training also provides fault tolerance — if one node fails, only that node's work is lost, not the entire job.

- **No model monitoring after deployment.** Without monitoring, model drift goes undetected. Predictions degrade silently, and the team only discovers the problem when business metrics drop — weeks or months later. Data quality monitoring catches drift within hours.

- **On-Demand training instances by default.** SageMaker Managed Spot Training saves 60-90% and handles interruptions automatically with checkpointing. Training jobs are inherently resumable, making them ideal Spot workloads. On-Demand should be the exception, not the default.

- **Deploying directly to production without shadow testing.** Shadow testing routes live traffic to both the current and candidate models, comparing predictions and latency in real-time. Without it, the only signal that a new model is worse comes from production users experiencing degraded results.

- **Not using experiment tracking (MLflow or SageMaker Experiments).** Without experiment tracking, it is impossible to reproduce a previous result, compare hyperparameter choices across runs, or explain why one model version outperformed another. This wastes compute re-running experiments that were already tried.

- **Storing artifacts locally instead of S3.** Local artifacts are not durable (instance termination deletes them), not shareable across team members, and break CI/CD pipelines that expect S3 paths. S3 provides versioning, cross-account access, and lifecycle management.

- **Ignoring Trainium/Inferentia.** ml.trn1 and ml.inf2 instances deliver 50%+ cost savings for supported model architectures. Teams that default to GPU without evaluating Neuron compatibility leave significant savings on the table. The Neuron SDK supports PyTorch and TensorFlow natively with minimal code changes.

- **Hardcoding instance types and hyperparameters in pipeline definitions.** Non-parameterized pipelines cannot be reused across environments (dev/staging/prod) and require code changes for every configuration adjustment. Use SageMaker Pipeline parameters for all configurable values.

- **Manual model deployment without CI/CD.** Manual deployments are error-prone, unauditable, and slow. Use SageMaker Pipelines or CodePipeline to automate the path from model registration to staging to production, with approval gates at each stage.

## Additional Resources

### Reference Files

For detailed configurations, CLI commands, and code examples, consult:
- **`references/training-patterns.md`** — Training job configurations (single-instance, distributed, Spot), hyperparameter tuning setup, checkpointing, SageMaker Processing examples, and distributed training strategies
- **`references/inference-deployment.md`** — Real-time endpoint configurations, serverless inference, batch transform, async inference, auto-scaling policies, multi-model endpoints, shadow testing, and Inference Recommender usage
- **`references/pipeline-recipes.md`** — SageMaker Pipeline definitions (Python SDK), Model Registry workflows, CI/CD integration with CodePipeline, MLflow experiment tracking setup, and monitoring configuration

### Related Skills
- **`bedrock`** — Foundation model customization, fine-tuning, and Bedrock-native inference
- **`eks`** — Kubernetes cluster design for Kubeflow or self-hosted MLflow deployments
- **`lambda`** — Serverless compute for lightweight ML inference or pipeline triggers
- **`step-functions`** — Workflow orchestration for simple ML pipelines without SageMaker Pipelines
- **`s3`** — Data lake design, artifact storage, lifecycle policies for training data and model artifacts
- **`iam`** — Least-privilege roles for SageMaker execution, cross-account model deployment
- **`observability`** — CloudWatch dashboards, alarms, and logging for ML infrastructure
- **`cost-check`** — Detailed cost analysis, Savings Plans recommendations, and Spot vs On-Demand comparison
- **`ec2`** — Instance type selection for self-managed training clusters or custom inference servers

## Output Format

When recommending an MLOps architecture, include:

| Component | Choice | Rationale |
|---|---|---|
| Platform | SageMaker Pipelines + MLflow | CI/CD for ML with experiment tracking |
| Training Instance | ml.trn1.32xlarge (Spot) | Trainium for 50% savings; Spot for additional 60-90% |
| Inference Instance | ml.inf2.xlarge | Inferentia2 for cost-effective LLM serving |
| Inference Pattern | Real-time endpoint with auto-scaling | Consistent traffic with latency SLA |
| Experiment Tracking | Managed MLflow on SageMaker | Zero-infra setup, auto-sync with Model Registry |
| Monitoring | Model Monitor (data quality + model quality) | Detect drift before business impact |
| CI/CD | CodePipeline triggering SageMaker Pipeline | Automated training on code merge |
| Cost Optimization | Spot training + Savings Plan on inference | Minimize both training and serving costs |

Include estimated monthly cost range using the `cost-check` skill.
