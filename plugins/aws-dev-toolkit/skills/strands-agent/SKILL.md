---
name: strands-agent
description: Scaffold and build AI agents using the Strands Agents SDK with Bedrock AgentCore. Use when creating new agent projects, building greenfield AgentCore applications, prototyping agents with Strands, or when asked about the Strands framework. Covers both TypeScript and Python.
disable-model-invocation: true
argument-hint: [description of the agent to build]
---

You are building an AI agent using the **Strands Agents SDK** deployed on **Amazon Bedrock AgentCore**.

## First: Clarify Language

Before writing any code, ask the user:

> **TypeScript or Python?** (TypeScript is recommended for new projects — it has strong typing, good DX, and first-class Strands support. Python is fully supported too.)

Default to TypeScript if the user doesn't have a preference.

## Process

1. Clarify the agent's purpose — one sentence. If it needs "and", consider multiple agents.
2. Clarify language preference (TS preferred, Python supported)
3. Identify the tools the agent needs (keep to 3-5 for a PoC)
4. Decide on memory needs: no memory, STM only, or STM+LTM
5. Scaffold the project using the patterns in [references/](references/)
6. Include observability setup (OTel tracing is built in — just configure the endpoint)
7. Include an eval scaffold using Strands Evals (even for TS agents, evals are Python)
8. Include deployment instructions using the AgentCore CLI

## Quick PoC Path: AgentCore CLI

For the fastest path to a working deployed agent, use the **AgentCore Starter Toolkit CLI**. It handles configuration, deployment, memory provisioning, and invocation.

```bash
# Install the toolkit
pip install bedrock-agentcore-starter-toolkit

# Configure your agent
agentcore configure --entrypoint agent.py --name my-agent

# Deploy to AWS (uses CodeBuild, no Docker needed)
agentcore deploy

# Invoke it
agentcore invoke '{"prompt": "Hello!"}'

# Check status
agentcore status

# Tear down when done
agentcore destroy --force
```

See [references/agentcore-cli.md](references/agentcore-cli.md) for the full CLI reference.

## TypeScript Project Setup

```bash
mkdir my-agent && cd my-agent
npm init -y
npm pkg set type=module
npm install @strands-agents/sdk
npm install --save-dev @types/node typescript
```

See [references/typescript-patterns.md](references/typescript-patterns.md) for complete TypeScript agent patterns.

## Python Project Setup

```bash
mkdir my-agent && cd my-agent
python -m venv .venv && source .venv/bin/activate
pip install strands-agents bedrock-agentcore
```

See [references/python-patterns.md](references/python-patterns.md) for complete Python agent patterns.

## Observability & Tracing

Strands has OpenTelemetry built in. Every agent invocation, model call, and tool execution emits OTel spans automatically. You just configure where to send them.

- **AgentCore deployed agents**: OTel is enabled by default → CloudWatch Logs, X-Ray traces, GenAI dashboard
- **Local development**: Set `OTEL_EXPORTER_OTLP_ENDPOINT` to route to Jaeger, Grafana, Langfuse, etc.
- **Disable**: `agentcore configure --disable-otel`

See [references/agentcore-integrations.md](references/agentcore-integrations.md) for full setup, third-party backends, and trace attribute configuration.

## Evaluation with Strands Evals

Ship evals from day one. Strands Evals provides LLM-as-a-Judge evaluation with 9+ built-in evaluators:

- **OutputEvaluator**: Custom rubric-based quality scoring
- **TrajectoryEvaluator**: Did the agent use the right tools in the right order?
- **HelpfulnessEvaluator**: 7-point helpfulness scale
- **FaithfulnessEvaluator**: Is the response grounded in context? (anti-hallucination)
- **HarmfulnessEvaluator**: Safety check
- **ToolSelectionAccuracyEvaluator** / **ToolParameterAccuracyEvaluator**: Tool-level correctness
- **GoalSuccessRateEvaluator**: Did the user achieve their goal across a full session?
- **ActorSimulator**: Simulates realistic multi-turn users for conversation testing

```bash
pip install strands-agents-evals
```

> Evals are Python-only. Even for TypeScript agents, write your eval suite in Python.

See [references/agentcore-integrations.md](references/agentcore-integrations.md) for eval code patterns, trace-based evaluation, multi-turn simulation, and auto-generated test cases.

## Memory Decision Guide

| Scenario | Memory Mode | Notes |
|---|---|---|
| Stateless tool-calling agent | NO_MEMORY | Simplest, cheapest |
| Multi-turn conversation within a session | STM_ONLY | 30-day retention, stores conversation history |
| Personalization across sessions | STM_AND_LTM | Extracts preferences, facts, summaries across sessions |

Memory is opt-in. Start without it, add when you need it.

## Gotchas

- **AgentCore CLI is Python-only for deployment** — even if your agent is TypeScript, the `agentcore` CLI itself is a Python tool. Your TS agent runs in a container.
- **TypeScript agents need containerized deployment** — use `--deployment-type container` when configuring TS agents with the AgentCore CLI
- **Default model is Claude Sonnet** — Strands defaults to `global.anthropic.claude-sonnet-4-5-20250929-v1:0` via Bedrock. You need model access enabled in your AWS account.
- **AWS credentials required** — Strands uses Bedrock by default. Ensure `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` are set, or use IAM roles.
- **Tool count matters** — more tools = more reasoning steps = slower + more expensive. Keep PoCs to 3-5 tools.
- **Zod is included** — `@strands-agents/sdk` bundles Zod for TypeScript tool input validation. No separate install needed.
- **Memory provisioning takes time** — STM: ~30-90s, LTM: ~120-180s. The CLI waits for ACTIVE status.
- **`agentcore destroy` deletes everything** — including memory resources. Use `--dry-run` first.
- **Session lifecycle** — idle timeout defaults to 900s (15min). Set `--idle-timeout` and `--max-lifetime` during configure if you need longer sessions.
- **VPC config is immutable** — once deployed with VPC settings, you can't change them. Create a new agent config instead.
- **OTel is on by default in AgentCore** — traces go to CloudWatch/X-Ray. Disable with `--disable-otel` if you don't want it.
- **Strands Evals is Python-only** — even for TypeScript agents, write evals in Python. The eval framework uses the same Bedrock models as your agent.
- **Evals cost money** — each LLM-as-a-Judge evaluation invokes a model. Use `callback_handler=None` in eval task functions to suppress console output.
- **Memory batching requires close()** — if using `batch_size > 1`, you MUST use a `with` block or call `close()` or buffered messages are lost.

## Output

When scaffolding a new agent project, generate:
1. Complete project structure with all files
2. Agent entrypoint with at least one custom tool
3. Observability setup (OTel endpoint config, env vars)
4. Eval scaffold (`evals/` directory with at least one test case using Strands Evals — Python, even for TS agents)
5. README with setup, deployment, observability, and eval instructions
6. `.gitignore` appropriate for the language
7. Deployment commands (local dev + AgentCore cloud)
