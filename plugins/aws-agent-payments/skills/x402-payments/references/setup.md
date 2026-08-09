# Setup Reference

## Prerequisites

### AWS Account Setup

1. **Enable AgentCore Payments** in your AWS account — see [region availability](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agentcore-regions.html)
2. **Create IAM roles** — see [AgentCore Payments IAM roles best practices](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/payments-iam-roles.html)

**Recommended: Separate IAM roles for setup vs runtime.** This follows the principle of least privilege:

- **Setup role** (used once): `CreatePaymentManager`, `CreatePaymentCredentialProvider`, `CreatePaymentConnector`, `CreatePaymentInstrument`
- **Agent runtime role** (used in production): `ProcessPayment`, `GetPaymentSession`, `CreatePaymentSession`

This separation ensures that the running agent cannot modify its own payment infrastructure.

**Setup role trust policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

1. **Attach permissions** to the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:CreatePaymentCredentialProvider",
        "bedrock-agentcore:CreatePaymentManager",
        "bedrock-agentcore:GetPaymentManager",
        "bedrock-agentcore:CreatePaymentConnector",
        "bedrock-agentcore:CreatePaymentInstrument",
        "bedrock-agentcore:CreatePaymentSession",
        "bedrock-agentcore:ProcessPayment",
        "bedrock-agentcore:GetPaymentSession",
        "bedrock-agentcore:GetPaymentInstrument"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:agentcore-payments-*"
    }
  ]
}
```

### Coinbase CDP Setup

1. Create account at [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com)
2. Create a project
3. Generate an API key → note the **Key ID** (UUID) and **Key Secret** (Ed25519 base64)
4. Generate a **Wallet Secret** (for signing)
5. Under Wallet > Embedded Wallets > Policies, **enable Delegated signing**

**Important: Credentials must NEVER be passed as tool parameters to the LLM.** Store all credentials in environment variables or a `.env` file local to your machine:

```bash
# .env (add to .gitignore!)
CDP_API_KEY_ID=your-key-id
CDP_API_KEY_SECRET=your-key-secret
CDP_WALLET_SECRET=your-wallet-secret
```

The plugin reads these from the environment at execution time. The LLM never sees or processes the raw credential values — only the agent host process has access. Never include wallet secrets in conversation transcripts, tool invocations, or config files checked into source control.

### Stripe/Privy Setup

1. Create account at [dashboard.privy.io](https://dashboard.privy.io)
2. Create an app → note the **App ID** and **App Secret**
3. Generate authorization credentials → **Auth ID** and **Auth Private Key**

## Resource Naming Rules

- **Credential Provider names**: lowercase alphanumeric + hyphens only (`[a-z0-9-]+`). NO underscores.
- **Connector names**: start with letter, alphanumeric + underscores (`[a-zA-Z][a-zA-Z0-9_]*`)
- **Payment Manager names**: alphanumeric + hyphens, start with letter

## Post-Setup Steps

After infrastructure creation:

1. **Authorize delegated signing** — open the redirect URL provided by the setup tool
2. **Fund the wallet** — send USDC to the wallet address on the target network
   - Base Sepolia: use [faucet.circle.com](https://faucet.circle.com/) (select Base Sepolia)
   - Base Mainnet: send USDC via any exchange or bridge
3. **Create a payment session** — the agent handles this automatically on first use

## Scoping Down Agent Permissions

For production, the running agent only needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agentcore:ProcessPayment",
        "bedrock-agentcore:GetPaymentSession",
        "bedrock-agentcore:CreatePaymentSession",
        "bedrock-agentcore:GetPaymentInstrument"
      ],
      "Resource": [
        "arn:aws:bedrock-agentcore:REGION:ACCOUNT:payment-manager/PM_ID",
        "arn:aws:bedrock-agentcore:REGION:ACCOUNT:payment-manager/PM_ID/*"
      ]
    }
  ]
}
```
