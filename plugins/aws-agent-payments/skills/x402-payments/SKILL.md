---
name: x402-payments
description: "Auto-pay x402-paywalled URLs using AWS AgentCore Payments. Handles HTTP 402 challenges, payment signing, and request replay for both v1 and v2 of the x402 protocol."
metadata:
  tags: [x402, payments, paywall, usdc, crypto, web3, agentcore, micropayments]
  version: "1.0.0"
---

# x402 Payments

This skill enables AI agents to auto-pay x402-paywalled URLs using AWS AgentCore Payments. It is agent-host independent — it describes the protocol and tool interactions generically, working the same whether tools are exposed as direct functions, MCP tools, or namespaced actions.

## Tool Inventory

The x402 payment system provides five tools. Match them by role — your runtime may prefix or rename them:

| Role                    | Typical name                 | Purpose                                                   |
| ----------------------- | ---------------------------- | --------------------------------------------------------- |
| Infrastructure setup    | `setup_x402_payments`        | One-shot creation of Payment Manager, Connector, Wallet   |
| Session status check    | `get_payment_session_status` | Check if current session is usable                        |
| Session creation        | `create_payment_session`     | Mint a fresh session with budget (requires user approval) |
| Server-side pay + fetch | `get_paid_content`           | Pay and return content in one call                        |
| Header-only payment     | `pay_and_get_header`         | Mint payment header for browser replay                    |

## When to Use

Activate this skill when **any** of these occur:

- An HTTP request returns 402 with x402 challenge headers (`x402Version`, `Payment-Required`, or `x-payment-required`)
- The user asks to access content from a URL they identify as x402-paywalled
- The user asks to "set up x402 payments" or "configure agent payments"
- A tool call fails with 402 Payment Required

Do NOT use for:

- Login walls, captchas, or non-x402 paywalls
- AWS billing or cost management
- Stripe checkout / e-commerce payments

## Protocol

### Step 1: Check Payment Session

Call the **session-status** tool. The response includes a `usable` boolean.

- **If `usable: true`** → proceed to Step 3
- **If `usable: false`** → the session is expired, drained, or doesn't exist. Go to Step 2.

### Step 2: Request User Approval for New Session

**Never mint a session without explicit user approval.** Each session sets a spending budget that the agent can use.

Tell the user:

> Your payment session is [expired/drained/missing]. I can create a new one with a $5 budget valid for 4 hours. Would you like to approve this?

On approval, call the **create-session** tool with `max_spend_usd="5"` and `expiry_minutes=240` (or user-specified values). Always ask for budget and duration confirmation before proceeding.

### Step 3: Pay for the URL

**Preferred path (server-side):** Call `get_paid_content` with the URL. The tool:

1. Probes the URL → gets 402 + x402 challenge
2. Calls AgentCore ProcessPayment → gets signed payment header
3. Replays the request with the payment header
4. Returns `{status_code, content_type, body, url}`

Read the content from the `body` field. No second request needed.

**Alternative path (browser/header-only):** If you need the page rendered in a live browser:

1. Call `pay_and_get_header` → returns `{header: {"X-PAYMENT": "VALUE"}, valid_seconds: <derived from challenge>}`
2. Set the header on your browser context
3. Navigate to the URL again — replay immediately, header validity is time-limited
4. The paid page renders normally

### Step 4: Handle Errors

- **Session expired mid-request** → go back to Step 2
- **Still 402 after payment** → session may have drained; check session status before retrying, then mint a new session if balance is zero
- **Header expired** → call `pay_and_get_header` again

For detailed error diagnosis, see [references/debugging.md](references/debugging.md).

## First-Time Setup

If no payment infrastructure exists, use the **setup** tool. For detailed prerequisites and IAM configuration, see [references/setup.md](references/setup.md).

Required inputs:

- `role_arn` — IAM role with `bedrock-agentcore.amazonaws.com` trust policy
- Wallet provider credentials (stored securely in AWS Secrets Manager, never in transcripts)
- Optional: `region` (default us-east-1), `network` (default eip155:84532), `user_id`

After setup:

1. Provide the redirect URL for delegated signing authorization
2. Instruct the user to fund the wallet with USDC on the target network

## x402 Protocol Details

For the full protocol specification including v2 envelope format, supported assets, and chain IDs, see [references/protocol.md](references/protocol.md).

## Guidelines

- **Don't surface payment internals** — report the content, not transaction hashes or header bytes
- **Always check session status first** — avoids `ExpiredTokenException` errors
- **Never auto-mint sessions** — get explicit user approval each time (unless user previously authorized auto-creation)
- **Wallet credentials must never appear in tool parameters or transcripts** — read from environment or secure config at execution time
- **Verify session balance before retrying** — a retry after failure should confirm the session still has funds rather than blindly calling ProcessPayment again

## Session Consent Enforcement

`CreatePaymentSession` is the spending-authorization boundary — whoever calls it controls how much the agent can spend. If the agent can create sessions autonomously, it can bypass budget controls by minting new sessions indefinitely.

**Recommended enforcement (strongest → weakest):**

| Tier | Mechanism | Guarantee |
|------|-----------|----------|
| 1 | **Host-native approval gate** — the agent host intercepts `CreatePaymentSession` and surfaces an Approve/Deny prompt to the user. The LLM cannot bypass this. | Hard |
| 2 | **IAM role separation** — the agent's runtime role only has `ProcessPayment` + `GetPaymentSession`. Sessions are created out-of-band by a human or privileged process. | Hard |
| 3 | **Conversational confirmation** — the agent asks the user "Create a $5 session?" and waits for affirmative response. | Soft (LLM-enforceable only) |

**Recommendations:**

- For **unattended/autonomous agents**: use Tier 1 or Tier 2. Tier 3 alone is insufficient — a jailbroken or confused model could self-approve.
- For **interactive chat agents with a human present**: Tier 1 (host approval gate) is ideal. Tier 3 is acceptable as a fallback if the host lacks native approval.
- For **developer/CLI workflows**: session creation should be a human-run script outside the LLM loop entirely (Tier 2).

**Host-specific implementations:**

- **OpenClaw**: `create_payment_session` uses a two-phase confirmation gate. The first call returns `AWAITING_USER_APPROVAL` and the agent must present the budget/duration to the user. Only after explicit approval does the second call (with `confirmed: true`) execute.
- **Strands/LangGraph**: Use IAM role separation (Tier 2). The `setup_payment_user.py` script creates sessions in the terminal; the agent runtime role lacks `CreatePaymentSession`.
- **Custom hosts**: Implement a pre-execution hook on `CreatePaymentSession` that gates on user confirmation via your application's consent mechanism.

## Fallback (No Runtime Plugin)

If runtime tools (`get_paid_content`, `pay_and_get_header`) are not available, use the AWS CLI directly:

### Check/Create Session

```bash
# Check existing session
aws bedrock-agentcore get-payment-session \
  --payment-manager-arn $PM_ARN \
  --payment-session-id $SESSION_ID \
  --user-id $USER_ID \
  --region us-east-1

# Create new session (requires user approval for budget)
aws bedrock-agentcore create-payment-session \
  --payment-manager-arn $PM_ARN \
  --user-id $USER_ID \
  --budget '{"maxSpendUsd": "5.00"}' \
  --ttl-minutes 240 \
  --region us-east-1
```

### Process Payment

```bash
# After receiving a 402 with x402 challenge, extract the accepts[0] object and call:
aws bedrock-agentcore process-payment \
  --payment-manager-arn $PM_ARN \
  --payment-session-id $SESSION_ID \
  --payment-instrument-id $INSTRUMENT_ID \
  --user-id $USER_ID \
  --payment-type CRYPTO_X402 \
  --payment-input '{"cryptoX402": {"version": "2", "payload": <accepts[0] object>}}' \
  --region us-east-1
```

The response contains `paymentOutput.cryptoX402.payload` — base64-encode it and set as the `X-PAYMENT` header on the retry request.

## Verification

The skill succeeded if the agent:

1. Detected the 402
2. Paid transparently
3. Returned the paid content to the user

The user should never see "Payment Required" as a final error.
