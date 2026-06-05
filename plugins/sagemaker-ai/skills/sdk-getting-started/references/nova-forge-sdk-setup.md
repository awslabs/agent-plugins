# Nova Forge SDK Setup

Guides first-time Nova Forge SDK setup: installation, IAM configuration, HyperPod CLI, and first dry run.

## Step 1: Install the SDK

> "Let's get the Nova Forge SDK installed. Run: `pip install amzn-nova-forge` (requires Python 3.12+). Let me know when it's done."

⏸ Wait for user.

## Step 2: Determine Runtime Platform

> "Which runtime platform do you plan to use?
>
> - **SMTJ Serverless** — Simplest, no instance management
> - **SMTJ** — Full instance control for SFT/RFT/DPO
> - **SMHP (HyperPod)** — Required for CPT, data mixing, RFT Multiturn
> - **Bedrock** — Fully managed service
>
> If you're not sure, SMTJ Serverless is the easiest way to start."
>
> **SMHP prerequisite:** A HyperPod cluster with a Restricted Instance Group (RIG) must already be provisioned and in `InService` state. Nova customization on HyperPod requires RIGs. The Forge SDK connects to an existing cluster — it does not create one. Do NOT offer to create a cluster or RIG. If no cluster exists, advise the user to work with their infrastructure team to provision one first.

⏸ Wait for user.

## Step 3: Resolve Execution Role

Read and follow `execution-role-setup.md` to discover the user's execution role ARN. Store the full ARN (including any IAM path prefix like `/service-role/`) for use in downstream code generation.

⏸ Wait for user to confirm role ARN.

## Step 4: Setup IAM Permissions

Read `iam-setup.md` and guide the user through the IAM permissions relevant to their chosen platform.

⏸ Wait for user to confirm IAM setup.

## Step 5: Install HyperPod CLI (SMHP Only)

**Skip this step** if the user chose SMTJ, SMTJ Serverless, or Bedrock.

Read `getting-started.md` (Step 3: HyperPod CLI section) and guide the user through the Forge-specific HyperPod CLI installation.

⏸ Wait for user.

## Step 6: Verify Installation

> "Let's verify everything works. Run this in Python:
>
> ```python
> from amzn_nova_forge import ForgeTrainer
> from amzn_nova_forge import Model, TrainingMethod
> from amzn_nova_forge import SMTJRuntimeManager
> print('Nova Forge SDK installed successfully!')
> ```
>
> Let me know what you see."

⏸ Wait for user.

## Troubleshooting

### Region Not Supported

**Symptoms:** `ValueError: region is unsupported`

**Solution:** Nova models are only available in `us-east-1` and `us-west-2`. Ensure your AWS configuration uses one of these regions.

### IAM Permission Errors

**Symptoms:** `AccessDeniedException` or `UnauthorizedOperation` immediately after job submission.

**Solutions:**

1. Verify execution role has the permissions listed in `iam-setup.md`
2. Ensure execution role trust policy includes `sagemaker.amazonaws.com`
3. Confirm S3 bucket permissions for data and output paths

## Important Notes

- The Forge SDK installs the SageMaker Python SDK (v3.x) as a dependency
- Nova models are currently available in us-east-1 and us-west-2
