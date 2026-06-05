# Nova Forge SDK — Deployment Enums

Exact enum values for use in generated deployment code.

## DeployPlatform Enum

| Enum Value                  | Description                                                |
| --------------------------- | ---------------------------------------------------------- |
| `DeployPlatform.BEDROCK_OD` | Amazon Bedrock On-Demand (pay per token, base models only) |
| `DeployPlatform.BEDROCK_PT` | Amazon Bedrock Provisioned Throughput (pay per model unit) |
| `DeployPlatform.SAGEMAKER`  | Amazon SageMaker (pay per instance hour)                   |

## DeploymentMode Enum

| Enum Value                        | Description                                              |
| --------------------------------- | -------------------------------------------------------- |
| `DeploymentMode.FAIL_IF_EXISTS`   | Raise error if endpoint already exists (default, safest) |
| `DeploymentMode.UPDATE_IF_EXISTS` | Try in-place update (Bedrock PT only)                    |
