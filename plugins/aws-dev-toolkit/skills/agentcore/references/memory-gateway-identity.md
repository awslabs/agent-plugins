# AgentCore Memory, Gateway, Identity, and Policy Reference

## Memory

### Short-Term Memory (Session-Scoped)

Short-term memory is enabled by default and maintains conversation history within a session. No additional configuration required.

```python
# Short-term memory is automatic with AgentCore Runtime sessions
# Each session_id maintains its own conversation context
response = bedrock_agentcore_runtime.invoke_agent_runtime(
    agentRuntimeId=agent_id,
    agentRuntimeEndpointName="production",
    sessionId="user-session-123",  # Context persists across calls with same session_id
    payload={"input": "What was my last question?"}
)
```

### Long-Term Memory (Cross-Session)

Long-term memory enables agents to remember information across sessions and build user-specific knowledge.

#### Create a Memory Resource

```bash
aws bedrock-agentcore create-memory \
  --memory-name customer-support-memory \
  --memory-strategies '[
    {
      "strategyName": "user-preferences",
      "description": "Extract and store user preferences from conversations",
      "type": "SEMANTIC",
      "configuration": {
        "semantic": {
          "extractionCriteria": "Extract user preferences, past issues, product ownership, and communication style"
        }
      }
    }
  ]'
```

#### Integrate Memory with Agent (Strands)

```python
from strands import Agent
from strands.tools.agentcore import AgentCoreMemoryTool

memory_tool = AgentCoreMemoryTool(
    memory_id="memory-abc123",
    region="us-east-1"
)

agent = Agent(
    model=model,
    system_prompt="You are a customer support agent. Use memory to provide personalized service.",
    tools=[memory_tool, ...other_tools]
)
```

#### Memory Extraction Jobs

Process past conversation transcripts into retrievable long-term memory:

```bash
aws bedrock-agentcore start-memory-extraction-job \
  --memory-id memory-abc123 \
  --source-session-ids '["session-1", "session-2", "session-3"]'
```

### Memory Strategies

| Strategy Type | Use Case | Example |
|---|---|---|
| **Semantic** | Extract structured insights from conversations | User preferences, past issues, product ownership |
| **Summary** | Compress long conversations into summaries | Meeting notes, support ticket summaries |
| **User profile** | Build evolving user models | Communication style, expertise level, role |

### Memory Quotas

| Resource | Default Limit |
|---|---|
| Memory resources per account | Check latest docs |
| Strategies per memory resource | Check latest docs |
| Strategies per account | Check latest docs |

---

## Gateway

### Creating a Gateway

```bash
aws bedrock-agentcore create-gateway \
  --gateway-name my-tools-gateway \
  --protocol-type MCP
```

### Adding a Lambda Target

```bash
aws bedrock-agentcore create-gateway-target \
  --gateway-id gw-abc123 \
  --name order-lookup \
  --description "Look up customer orders by order ID or customer email" \
  --target-configuration '{
    "lambdaTarget": {
      "functionArn": "arn:aws:lambda:us-east-1:123456789:function:order-lookup",
      "toolSchema": {
        "inputSchema": {
          "type": "object",
          "properties": {
            "orderId": {"type": "string", "description": "The order ID to look up"},
            "customerEmail": {"type": "string", "description": "Customer email for order search"}
          }
        }
      }
    }
  }'
```

### Adding an API Target

```bash
aws bedrock-agentcore create-gateway-target \
  --gateway-id gw-abc123 \
  --name crm-api \
  --description "Query the CRM system for customer information" \
  --target-configuration '{
    "apiTarget": {
      "uri": "https://api.example.com/customers",
      "method": "GET",
      "authConfiguration": {
        "oAuth2": {
          "credentialProviderArn": "arn:aws:bedrock-agentcore:us-east-1:123456789:credential-provider/crm-oauth"
        }
      }
    }
  }'
```

### Connecting Existing MCP Servers

Gateway can federate with existing MCP servers, making their tools available to AgentCore agents:

```bash
aws bedrock-agentcore create-gateway-target \
  --gateway-id gw-abc123 \
  --name external-mcp \
  --target-configuration '{
    "mcpTarget": {
      "uri": "https://mcp.example.com/sse",
      "transportType": "SSE"
    }
  }'
```

### Syncing Gateway Targets

After adding or modifying targets, sync to update the tool index:

```bash
aws bedrock-agentcore sync-gateway-targets \
  --gateway-id gw-abc123
```

### Using Gateway Tools in Agents (Strands)

```python
from strands import Agent
from strands.tools.agentcore import AgentCoreGatewayTool

gateway_tools = AgentCoreGatewayTool(
    gateway_id="gw-abc123",
    region="us-east-1"
)

agent = Agent(
    model=model,
    tools=[gateway_tools]
)
```

### Gateway Quotas

| Resource | Default Limit |
|---|---|
| Gateways per account | Check latest docs |
| Targets per gateway | Check latest docs |
| Tools per target | Check latest docs |

---

## Identity

### Workload Identities

Each agent runtime can be assigned a workload identity that manages authentication to external services.

#### OAuth2 Credential Provider

```bash
# Create an OAuth2 credential provider for Salesforce
aws bedrock-agentcore create-oauth2-credential-provider \
  --name salesforce-oauth \
  --credential-provider-vendor SALESFORCE \
  --oauth2-provider-config '{
    "authorizationServerUrl": "https://login.salesforce.com/services/oauth2/token",
    "clientId": "your-client-id",
    "clientSecretArn": "arn:aws:secretsmanager:us-east-1:123456789:secret:sf-client-secret",
    "scopes": ["api", "refresh_token"]
  }'
```

#### API Key Credential Provider

```bash
# Create an API key provider for a third-party service
aws bedrock-agentcore create-api-key-credential-provider \
  --name weather-api \
  --api-key-secret-arn "arn:aws:secretsmanager:us-east-1:123456789:secret:weather-api-key"
```

#### Token Vault

For services requiring managed token storage and rotation:

```bash
aws bedrock-agentcore create-token-vault \
  --token-vault-name production-tokens
```

### Identity Best Practices

- **One credential provider per external service** — do not share credentials across services
- **Use OAuth2 over API keys** when the service supports it — tokens can be scoped and rotated
- **Store secrets in Secrets Manager** — credential providers reference ARNs, never inline secrets
- **Use custom claims** for enhanced authorization context in resource-based policies

---

## Policy

### Creating a Policy Engine

```bash
aws bedrock-agentcore create-policy-engine \
  --policy-engine-name production-policies \
  --gateway-id gw-abc123
```

### Writing Cedar Policies

#### Natural Language Authoring

AgentCore converts natural language to Cedar:

```bash
aws bedrock-agentcore start-policy-generation \
  --policy-engine-id pe-abc123 \
  --description "Allow refunds under $1000 for customer support agents.
                 Block all delete operations.
                 Only allow engineering team to access the deployment tool."
```

#### Direct Cedar Policies

```cedar
// Limit refund amounts
forbid (
  principal,
  action == Action::"invoke",
  resource == Tool::"process-refund"
) when {
  resource.input.refundAmount > 1000
};

// Restrict tool access by role
permit (
  principal,
  action == Action::"invoke",
  resource == Tool::"deploy-service"
) when {
  principal.department == "engineering"
};

// Block dangerous operations entirely
forbid (
  principal,
  action == Action::"invoke",
  resource == Tool::"delete-customer-data"
);

// Time-based access control
permit (
  principal,
  action == Action::"invoke",
  resource == Tool::"trading-api"
) when {
  context.currentHour >= 9 && context.currentHour <= 16
};
```

### Attaching Policies

```bash
aws bedrock-agentcore create-policy \
  --policy-engine-id pe-abc123 \
  --policy-name refund-limits \
  --policy-document file://policies/refund-limits.cedar
```

### Policy Monitoring

Policy decisions are logged automatically. Query them for audit:

```bash
# Check recent policy denials
aws logs filter-log-events \
  --log-group-name /aws/bedrock-agentcore/policy \
  --filter-pattern "DENY"
```

### Policy vs Other Guardrail Mechanisms

| Mechanism | What It Controls | Enforcement | Use For |
|---|---|---|---|
| **AgentCore Policy** | Tool calls and parameters | Deterministic (Cedar) | "Agent X cannot call tool Y with parameter Z" |
| **Bedrock Guardrails** | Content generation | LLM-based | "Agent cannot produce PII or harmful content" |
| **IAM Policies** | AWS API access | Deterministic | "Agent role cannot access S3 bucket X" |
| **SCPs** | Account-wide AWS actions | Deterministic | "No one in this account can create public S3 buckets" |

Use all four layers together for defense in depth.
