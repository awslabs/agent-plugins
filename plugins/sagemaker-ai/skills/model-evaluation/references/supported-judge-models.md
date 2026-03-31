# Supported Judge Models

Reference: [Amazon Bedrock LLM-as-Judge Evaluation](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation-judge.html)

## Allowed Judge Models

The SageMaker Python SDK validates the judge model against a hardcoded allowlist before submitting the evaluation job. Only these models are accepted:

| Model                          | Model ID                                    | Regions                                         |
| ------------------------------ | ------------------------------------------- | ----------------------------------------------- |
| Amazon Nova Pro                | `amazon.nova-pro-v1:0`                      | us-east-1                                       |
| Anthropic Claude 3.5 Sonnet v1 | `anthropic.claude-3-5-sonnet-20240620-v1:0` | us-west-2, us-east-1, ap-northeast-1            |
| Anthropic Claude 3.5 Sonnet v2 | `anthropic.claude-3-5-sonnet-20241022-v2:0` | us-west-2                                       |
| Anthropic Claude 3 Haiku       | `anthropic.claude-3-haiku-20240307-v1:0`    | us-west-2, us-east-1, ap-northeast-1, eu-west-1 |
| Anthropic Claude 3.5 Haiku     | `anthropic.claude-3-5-haiku-20241022-v1:0`  | us-west-2                                       |
| Meta Llama 3.1 70B Instruct    | `meta.llama3-1-70b-instruct-v1:0`           | us-west-2                                       |
| Mistral Large                  | `mistral.mistral-large-2402-v1:0`           | us-west-2, us-east-1, eu-west-1                 |

This list applies to both built-in and custom metrics — the SDK does not distinguish between them.

Source: `sagemaker.train.constants._ALLOWED_EVALUATOR_MODELS` (sagemaker SDK v3)

## Selection Guidance

Verify each candidate is active in the user's region. Use the AWS MCP tool `get-foundation-model` (Bedrock service) with the model identifier and region. Extract `modelDetails.modelLifecycle.status` from the response.

Only include models that return `ACTIVE`. Models marked `LEGACY` will fail at evaluation time.

Present all active models to the user and let them choose. **NEVER recommend or suggest any particular model.** Only display the list. If the user asks for guidance, you may share these general trade-offs so they can decide:

- Cost vs quality: Smaller models are faster and cheaper; larger models produce higher-quality judgments
- Task complexity: Simple tasks (QA, classification) may not need the most capable model; complex reasoning (math, multi-step) benefits from stronger models
