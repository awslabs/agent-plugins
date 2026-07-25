# x402 Protocol Reference

## How x402 Works

x402 is a standard HTTP payment protocol that extends HTTP 402 (Payment Required) with machine-readable payment challenges. When a server protects content behind a paywall:

1. Client makes a normal HTTP request
2. Server returns HTTP 402 with payment challenge headers
3. Client processes payment (signs a blockchain transaction)
4. Client replays the request with a payment proof header
5. Server verifies the proof and returns the content

## x402 Version 2 (Current)

This skill targets x402 v2, which is the actively deployed protocol version.

- **Challenge delivery:** `Payment-Required` header (base64 JSON) OR JSON response body with `x402Version: "2"`
- **Payment header:** `X-PAYMENT` with base64-encoded PaymentPayload envelope
- **Multiple accepted payment schemes** per challenge via structured `accepts` array

### Payment Flow (v2)

**1. Server sends 402 with challenge:**

```json
{
  "x402Version": 2,
  "resource": { "url": "...", "description": "...", "mimeType": "..." },
  "accepts": [
    {
      "scheme": "exact",
      "network": "eip155:84532",
      "amount": "100000",
      "asset": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      "payTo": "0x...",
      "maxTimeoutSeconds": 60
    }
  ]
}
```

**2. Agent calls AgentCore ProcessPayment:**

```json
{
  "paymentManagerArn": "arn:aws:bedrock-agentcore:...:payment-manager/...",
  "paymentSessionId": "...",
  "paymentInstrumentId": "...",
  "userId": "...",
  "clientToken": "<stable hash for idempotency>",
  "paymentType": "CRYPTO_X402",
  "paymentInput": {
    "cryptoX402": {
      "version": "2",
      "payload": {/* accepts[0] object from challenge */}
    }
  }
}
```

**3. AgentCore returns signed payload:**

```json
{
  "paymentOutput": {
    "cryptoX402": {
      "payload": {
        "signature": "0x...",
        "authorization": {
          "from": "<wallet address>",
          "to": "<asset contract>",
          "value": "<transfer amount>",
          "validAfter": "<unix timestamp>",
          "validBefore": "<unix timestamp>",
          "nonce": "<unique nonce>"
        }
      }
    }
  }
}
```

**4. Agent replays request with X-PAYMENT header:**

```
X-PAYMENT: <base64-encode(paymentOutput.cryptoX402.payload)>
```

### Challenge `accepts` Array

Each entry in `accepts` describes one payment option the server will accept:

| Field               | Description                                                |
| ------------------- | ---------------------------------------------------------- |
| `scheme`            | Payment scheme (e.g., `"exact"`)                           |
| `network`           | Chain identifier (e.g., `"eip155:84532"` for Base Sepolia) |
| `amount`            | Amount in base units (e.g., `"100000"` for $0.10 USDC)     |
| `asset`             | Token contract address                                     |
| `payTo`             | Recipient address                                          |
| `maxTimeoutSeconds` | Maximum time for payment validity                          |
| `extra`             | Optional additional parameters                             |

## AgentCore ProcessPayment

The AgentCore Payments API handles the cryptographic signing:

**Input (`paymentInput.cryptoX402`):**

- `version` — protocol version ("2")
- `payload` — the `accepts[0]` object from the x402 challenge

**Output (`paymentOutput.cryptoX402`):**

- `payload` — signed payment object containing `authorization` + `signature` fields

The output payload is base64-encoded and sent as the `X-PAYMENT` header value.

## Supported Asset Addresses

| Network      | Asset | Address                                      |
| ------------ | ----- | -------------------------------------------- |
| Base Sepolia | USDC  | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |
| Base Mainnet | USDC  | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |

## Security Considerations

- **Redirect safety:** Payment proof headers should NOT follow cross-origin redirects. The replay request should use `redirect: "manual"` and only re-attach the payment header if the redirect target's origin matches the original challenge origin.
- **Credential handling:** Wallet signing keys must never be passed as tool parameters or stored in conversation transcripts. Use environment variables or secure credential files.
- **Idempotency:** ProcessPayment supports a `clientToken` for idempotent retries. Implementations should derive a stable token from the challenge (e.g., hash of resource URL + amount + nonce) rather than relying on SDK auto-generation.

## Error Codes

| Error                   | Meaning                    | Resolution                              |
| ----------------------- | -------------------------- | --------------------------------------- |
| `PaymentSessionExpired` | Session TTL exceeded       | Create new session                      |
| `InsufficientBalance`   | Session spend cap reached  | Create new session with higher cap      |
| `InvalidSignature`      | Wallet signing failed      | Check instrument/connector setup        |
| `NetworkMismatch`       | Wrong network for endpoint | Verify wallet network matches challenge |
