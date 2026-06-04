# Finetuning Technique Selection Guide

Not all models support all techniques. Always validate technique availability against the selected model's recipes before recommending. Only SFT, DPO, RLVR, and MTRL are supported.

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

### MTRL (Multi-Turn Reinforcement Learning)

**Use when:**

- Task involves multi-turn agent interaction (tool use, reasoning chains, autonomous decision-making across multiple steps)
- Reward depends on the outcome of an agent rollout, not on a single response
- An agent environment exists (Bedrock AgentCore runtime or a custom agent reachable through a Lambda forwarder)
- Building agentic workflows where the model must plan, call tools, observe results, and decide next steps

**Key difference from RLVR:**

- RLVR: model produces one response, a Lambda computes a reward on it.
- MTRL: model interacts with an environment over many turns; reward is on the whole trajectory.

**Additional setup**: MTRL training requires an agent environment to be configured. The `finetuning` skill walks you through choosing between Bedrock AgentCore and a custom Lambda-fronted agent during notebook generation.
