---
name: sdk-getting-started
description: Validates the user's environment for SageMaker AI operations — checks SDK version, AWS region, and execution role. Use when the user says "set up", "getting started", "check my environment", "configure SDK", or as the first step in any plan involving SageMaker/Bedrock training, evaluation, or deployment.
---

# SDK Getting Started

Preflight checks to verify the user's environment can run SageMaker AI operations. The agent runs these checks directly (no code generation) and stores results in conversation context for downstream skills.

## Principles

1. **Don't ask for what you can look up.** Resolve region and role programmatically before asking the user.

## Workflow

Read and follow `references/sagemaker-python-sdk-setup.md`.

## References

- `references/sagemaker-python-sdk-setup.md` - SageMaker Python SDK version, region, and execution role checks
- `references/execution-role-setup.md` — Execution role resolution and validation
