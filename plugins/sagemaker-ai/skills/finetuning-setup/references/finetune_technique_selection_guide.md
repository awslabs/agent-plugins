# Finetuning Technique Selection Guide

Not all models support all techniques. Always validate technique availability against the selected model's recipes before recommending. Only SFT, DPO, and RLVR are supported.

## Technique Overview

### SFT (Supervised Fine-Tuning)

**Use when:**

- Task has clear right/wrong answers
- Single optimal output per input
- Output represents exemplary responses
- Classification, extraction, structured generation

### DPO (Direct Preference Optimization)

**Use when:**

- Multiple valid outputs, some better than others
- Subjective quality (tone, style, helpfulness)
- Creative tasks with preference judgments

### RLVR (Reinforcement Learning from Verifiable Rewards)

**Use when:**

- Outputs can be verified programmatically
- Want to reward similarity to gold responses
- Code generation (passes tests = reward)
- Math problems (correct answer = reward)
- Constraint satisfaction (meets criteria = reward)

**Key difference from SFT:**

- SFT: Model learns to imitate gold responses directly
- RLVR: Model learns to maximize rewards (can be gold similarity or verification-based)
