## Overview

This plugin brings deep AWS AI/ML expertise directly into your coding assistant, covering the surface area of [Amazon SageMaker AI](https://aws.amazon.com/sagemaker/ai/); currently, skills are provided to assist with the following capability areas:

- **Model Customization** — End-to-end guided workflows for fine-tuning foundation models, from use case definition through data preparation, training, evaluation, and deployment on Amazon SageMaker AI.
- **HyperPod Cluster Operations** — Remote command execution on nodes via SSM, version checking, and diagnostic reporting for SageMaker HyperPod training clusters.

## Agent Skills

| #  | Skill                      | Description                                                                                                              | Documentation                                        |
| -- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| 1  | `planning`                 | Builds a dynamic, step-by-step plan tailored to your intents                                                             | [SKILL.md](skills/planning/SKILL.md)                 |
| 2  | `directory-management`     | Manages project directory setup, artifact organization, and plan association for new or existing projects                | [SKILL.md](skills/directory-management/SKILL.md)     |
| 3  | `use-case-specification`   | Guided, conversational process to define your model customization use case goals, key stakeholders, and success criteria | [SKILL.md](skills/use-case-specification/SKILL.md)   |
| 4  | `dataset-evaluation`       | Dataset quality validation, format detection, and data requirements analysis                                             | [SKILL.md](skills/dataset-evaluation/SKILL.md)       |
| 5  | `dataset-transformation`   | Dataset format conversion and preparation for SageMaker-compatible training formats                                      | [SKILL.md](skills/dataset-transformation/SKILL.md)   |
| 6  | `finetuning-setup`         | Fine-tuning technique selection (SFT, DPO, RLVR, etc.) and base model selection                                          | [SKILL.md](skills/finetuning-setup/SKILL.md)         |
| 7  | `finetuning`               | Hyperparameter configuration and training job execution                                                                  | [SKILL.md](skills/finetuning/SKILL.md)               |
| 8  | `model-evaluation`         | Evaluation design, benchmark selection, LLM-as-a-judge, and model comparison                                             | [SKILL.md](skills/model-evaluation/SKILL.md)         |
| 9  | `model-deployment`         | Deployment configuration and endpoint setup (SageMaker or Bedrock)                                                       | [SKILL.md](skills/model-deployment/SKILL.md)         |
| 10 | `hyperpod-ssm`             | Remote command execution and file transfer on HyperPod cluster nodes via SSM                                             | [SKILL.md](skills/hyperpod-ssm/SKILL.md)             |
| 11 | `hyperpod-version-checker` | Check and compare software component versions across HyperPod cluster nodes                                              | [SKILL.md](skills/hyperpod-version-checker/SKILL.md) |
| 12 | `hyperpod-issue-report`    | Generate diagnostic reports for HyperPod troubleshooting and support cases                                               | [SKILL.md](skills/hyperpod-issue-report/SKILL.md)    |

## MCP Servers

| # | Server    | Description                                                 |
| - | --------- | ----------------------------------------------------------- |
| 1 | `aws-mcp` | AWS documentation and SOP retrieval via `mcp-proxy-for-aws` |

## Installation

Before installing the above skills, install `uv` for your platform: [UV: Installing UV](https://docs.astral.sh/uv/getting-started/installation/)

### Add the MCP Server

Add the contents of `.mcp.json` file to your platform's MCP configuration file:

- Claude code: Run `claude mcp add --transport stdio aws-mcp -- uvx mcp-proxy-for-aws@latest https://aws-mcp.us-east-1.api.aws/mcp` or manually add to `User/Project/Local` location as needed ([Claude Code Docs: What uses scopes](https://code.claude.com/docs/en/settings#what-uses-scopes)).
- Cursor: `.cursor/mcp.json`
- Kiro: `.kiro/settings/mcp.json`

### Install Skills with `npx skills`

You may use the [Skills CLI](https://github.com/vercel-labs/skills) (from Vercel Labs) to install the skills into your platform:

- Claude code: `npx skills add https://github.com/awslabs/agent-plugins/tree/main/plugins/sagemaker-ai/skills --all --agent claude-code --copy`
- Cursor: `npx skills add https://github.com/awslabs/agent-plugins/tree/main/plugins/sagemaker-ai/skills --all --agent cursor --copy`
- Kiro: `npx skills add https://github.com/awslabs/agent-plugins/tree/main/plugins/sagemaker-ai/skills --all --agent kiro-cli --copy`

If you have configured other agents use:

```
npx skills add https://github.com/awslabs/agent-plugins/tree/main/plugins/sagemaker-ai/skills --all --agent <agents...>
```

## Model Customization

The model customization skills cover the jobs-to-be-done for fine-tuning foundation models on Amazon SageMaker AI. They encode AWS best practices into agent-readable instruction packages, guiding you from use case definition through deployment.

### How It Works

- **Build your plan** — Describe what you want to build. The Planning skill discovers your intent, asks targeted clarifying questions, and generates a step-by-step customization plan covering data preparation, fine-tuning, evaluation, and deployment — adapting as your project evolves.
- **Define your use case** — The Use Case Specification skill guides you through a structured process to capture goals, constraints, and success criteria, producing a reusable specification document.
- **Work through each stage** — At each step, the agent generates executable Jupyter notebooks you can review, edit, and run cell by cell. You validate results and iterate before moving on.
- **Deploy your model** — Once evaluation criteria are met, the deployment skill guides you through endpoint configuration and launch on Amazon SageMaker AI or Amazon Bedrock.

For Kiro IDE users who use the chat interface, SageMaker AI model customization skills trigger correctly in ["vibe" mode](https://kiro.dev/docs/chat/vibe/) but not consistently in "spec" mode. Select "Vibe" when prompted by Kiro.

### Examples

- "Hi, help me customize a model"
- "I want to fine-tune a model for customer support classification"
- "Evaluate my dataset for finetuning a base model"
- "Deploy my fine-tuned model"

### Getting Started

You can try it out with the sample datasets [here](https://docs.aws.amazon.com/sagemaker/latest/dg/model-customize-open-weight-samples.html).

## HyperPod Cluster Operations

The HyperPod skills provide operational tooling for Amazon SageMaker HyperPod AI/ML clusters orchestrated via Slurm or Amazon EKS, enabling you to manage, diagnose, and troubleshoot cluster nodes directly from your coding assistant.

- **`hyperpod-ssm`** — Run commands and transfer files on cluster nodes via AWS Systems Manager (SSM), without needing direct SSH access.
- **`hyperpod-version-checker`** — Check and compare software component versions (drivers, libraries, frameworks) across cluster nodes to identify drift or incompatibilities.
- **`hyperpod-issue-report`** — Generate comprehensive issue reports that collect system state, logs, and configuration details for troubleshooting or support case submission.

### Examples

- "Check the GPU memory usage on all nodes in my HyperPod cluster using SSM"
- "Check driver versions on my HyperPod cluster"
- "Generate an issue report for my HyperPod cluster"

## Supported Environments

### Using the plugin through a remote connection to SageMaker Spaces

You may choose to setup a remote connection to your existing SageMaker Spaces, and use the plugin there. If you choose to do this, the environment is pre-configured with AWS credentials and environment variables. You may skip the Authentication and Authorization and Configuration pre-requisite steps, simply install the plugin and start using it with your agent. Learn more about remote connections to SageMaker Spaces [here](https://docs.aws.amazon.com/sagemaker/latest/dg/remote-access.html).

### Using the plugin in your local compute

In your own local compute environment, you need to follow the Authentication and Authorization and Configuration pre-requisite steps outlined below to get your local environment ready for the use of this plugin. Then, you may install the plugin and start using it with your agent of choice.

#### Prerequisites

- An AWS account with access to Amazon SageMaker AI
- Local AWS credentials and config
- Python 3.8+ (for generated notebooks)

#### Authentication and Authorization

In your local environment, configure AWS credentials using one of the following methods, to enable the skills to execute relevant SageMaker AI and AWS API operations as needed:

- **AWS CLI** — Run `aws configure` (IAM Role credentials)
- **Environment variables** — Set `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN`. See [Configuring environment variables](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html) for details. If you're using isolated environments such as conda or venv, make sure to set your environment variables within your environment.

The credentials configured here should be for an IAM Role. This IAM Role:

- Should have the necessary IAM permissions to invoke the various SageMaker AI operations (such as CreateTrainingJob, CreateEndpoint, CreateModel, etc.). The `AmazonSageMakerFullAccess` managed policy covers all SageMaker operations used by the skills.
- Should be configured to be used as an "execution role" for SageMaker AI operations that require an execution role (trusted by [sagemaker.amazonaws.com](http://sagemaker.amazonaws.com))
- For Bedrock deployment and evaluation: must also be trusted by [bedrock.amazonaws.com](http://bedrock.amazonaws.com) (add to the role's trust policy) and have permissions for Bedrock operations (see supplemental policy below)
- For RLVR fine-tuning: must also be trusted by [lambda.amazonaws.com](http://lambda.amazonaws.com) (add to the role's trust policy) to allow the finetuning skill to create an RLVR reward Lambda function

**Supplemental Bedrock permissions:** `AmazonSageMakerFullAccess` does not include the Bedrock permissions required by the model-evaluation and model-deployment (Bedrock pathway) skills. Add the following policy to your role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockModelImportAndDeploy",
      "Effect": "Allow",
      "Action": [
        "bedrock:CreateModelImportJob",
        "bedrock:GetModelImportJob",
        "bedrock:DeleteImportedModel",
        "bedrock:CreateCustomModel",
        "bedrock:GetFoundationModel",
        "bedrock-runtime:Converse"
      ],
      "Resource": "*"
    }
  ]
}
```

**S3 bucket naming caveat:** The default SageMaker execution policy only grants `s3:GetObject` and `s3:PutObject` on S3 buckets with "sagemaker" in the name. If your datasets or model artifacts are stored in buckets without "sagemaker" in the name, you must add a supplemental S3 policy granting access to those buckets.

**RLVR Lambda naming caveat:** For RLVR fine-tuning, `lambda:InvokeFunction` is only granted on Lambda functions with "sagemaker" in the name. Ensure your RLVR reward functions follow this naming convention, or add a broader Lambda invoke policy.

Learn more about AWS Identity and Access Management for Amazon SageMaker AI [here](https://docs.aws.amazon.com/sagemaker/latest/dg/security-iam.html).

#### Configuration

- Set `AWS_DEFAULT_REGION` to your preferred AWS region (e.g., `us-east-1`) for your customization workflow. See [Configuring environment variables](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html) for details. If you're using isolated environments such as conda or venv, make sure to set your environment variables within your environment.

#### Callouts

- SageMaker LLM as a Judge: This feature is powered by Amazon Bedrock Evaluations. Your use of this feature is subject to pricing of Amazon Bedrock Evaluations, see the [Service Terms](https://aws.amazon.com/service-terms/) applicable to Amazon Bedrock, and the terms that apply to your usage of third-party models. Amazon Bedrock Evaluations may securely transmit data across AWS Regions within your geography for processing. For more information, access [Amazon Bedrock Evaluations documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/evaluation-judge.html).
- When deploying a customized model to Bedrock for inference, set your region inference policy to control scale of inference geographically or globally. See [Bedrock documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/cross-region-inference.html).
- Nova models are subject to the following restrictions:
  - Only available for customization in us-east-1
  - Not supported for model evaluation with LLMaaJ.

## Customizing Skills for Your Organization

The skills in this plugin encode AWS best practices, but they are fully customizable. You can fork the repository and modify any `SKILL.md` to reflect your organization's standards, approved techniques, required evaluation benchmarks, or internal tooling. Workspace-level skills take precedence over global skills, so teams can maintain their own versions without affecting other users.

## Related Resources

- [Amazon SageMaker AI Model Customization](https://aws.amazon.com/sagemaker/ai/model-customization/)
- [SageMaker AI Developer Guide](https://docs.aws.amazon.com/sagemaker/latest/dg/customize-model.html)
- [Agent Skills open standard — Anthropic](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
- [AWS Agent Plugins Marketplace](https://github.com/awslabs/agent-plugins)
- [SageMaker AI MCP Server](https://github.com/awslabs/mcp)

## License

This project is licensed under the Apache 2.0 License.
