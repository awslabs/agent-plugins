# Agent Payments (x402)

> 🚧 **Preview:** AWS AgentCore Payments is currently in **preview**. APIs, pricing, and availability may change. See [AgentCore Payments documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/payments.html) for the latest status.

Enable stateful autonomous agents to pay for x402-paywalled APIs, MCP tools, and web content via microtransactions using [AWS AgentCore Payments](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/payments.html).

## Overview

When an AI agent encounters an HTTP 402 (Payment Required) response from an x402-protected endpoint, this skill guides the agent through the payment flow — detecting the challenge, processing payment via AgentCore, and replaying the request with a valid payment header. The agent receives the content without needing to understand the underlying crypto mechanics.

Works with stateful autonomous agents (OpenClaw, custom AgentCore deployments) and AI coding agents that need to access paid APIs or content.

Supports **Coinbase CDP** and **Stripe/Privy** wallet providers on **Base Sepolia** (testnet) and **Base Mainnet** networks.

## Skills

| Skill           | When to use                                                              | References                                                                                                                                                            |
| --------------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `x402-payments` | "pay for this URL", "x402 paywall", HTTP 402 detected, "set up payments" | [protocol](skills/x402-payments/references/protocol.md), [setup](skills/x402-payments/references/setup.md), [debugging](skills/x402-payments/references/debugging.md) |

## How x402 Payment Works

```text
Agent request → HTTP 402 + x402 challenge
    → AgentCore ProcessPayment (signs tx)
    → Replay request with X-PAYMENT header
    → HTTP 200 + paid content returned to agent
```

## Installation

### Claude Code

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install aws-agent-payments@agent-plugins-for-aws
```

### Codex

```bash
codex plugin marketplace add awslabs/agent-plugins
```

Then install **aws-agent-payments** from the Plugins panel.

## Prerequisites

- AWS account with [AgentCore Payments](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/payments.html) access
- AWS CLI with configured credentials (`aws sts get-caller-identity`)
- IAM role with `bedrock-agentcore.amazonaws.com` trust policy
- Wallet provider account:
  - **Coinbase CDP**: API key from [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com)
  - **Stripe/Privy**: App credentials from [dashboard.privy.io](https://dashboard.privy.io)
- USDC funding on the target network (Base Sepolia for testnet)

## Security & Spending Controls

- **Session spend caps** — each session locks a maximum USDC amount (default $5)
- **Session TTL** — sessions auto-expire (default 4 hours, max 8 hours)
- **Per-request limits** — AgentCore enforces per-transaction caps from the x402 challenge
- **IAM policies** — scope agent permissions to only `ProcessPayment`, `GetPaymentSession`
- **Audit trail** — all payments logged via CloudTrail

## Supported Networks

| Network      | Chain ID       | Use Case              |
| ------------ | -------------- | --------------------- |
| Base Sepolia | `eip155:84532` | Testnet / development |
| Base Mainnet | `eip155:8453`  | Production            |

## Examples

- "Pay for this API endpoint: `https://x402-test.example.com/api/weather`"
- "Set up x402 payments with my Coinbase CDP credentials"
- "Check my payment session balance"
- "Create a new payment session with $10 cap"
- "This URL returned a 402, can you pay for it?"

## Runtime Plugin (Future)

A TypeScript reference implementation for stateful agent hosts (OpenClaw, etc.) that registers executable tools directly into the agent's tool system is available at [wirjo/agent-toolkit-for-aws](https://github.com/wirjo/agent-toolkit-for-aws/pull/1). This enables fully autonomous payment flows without human-in-the-loop for each transaction. An RFC for the runtime-plugin pattern will be opened separately.
