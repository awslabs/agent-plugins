# AgentCore Runtime Deployment Reference

## AgentCore CLI (Preferred)

The [AgentCore CLI](https://github.com/aws/agentcore-cli) is the fastest way to create, develop, and deploy agents. It handles container builds, ECR pushes, and runtime configuration automatically.

```bash
pip install agentcore-cli

# Scaffold a new agent
agentcore init my-agent --framework strands

# Run locally with hot-reload
cd my-agent && agentcore dev

# Deploy to AgentCore Runtime
agentcore deploy --region us-east-1

# Test the deployed agent
agentcore invoke --agent-name my-agent --input "Hello"

# Manage aliases
agentcore alias create --agent-name my-agent --alias-name production --version 1
```

For full-stack deployments with auth and frontend, use the [Starter Toolkit](https://github.com/aws/bedrock-agentcore-starter-toolkit) (CDK-based FAST template) instead.

---

## Manual Container Setup

Use this approach when you need full control over the build process or are integrating into existing CI/CD infrastructure.

### Minimal Dockerfile

```dockerfile
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8080
CMD ["python", "agent.py"]
```

### Requirements

```
boto3>=1.35.0
bedrock-agentcore-runtime>=0.1.0
strands-agents>=0.1.0  # or your framework of choice
```

### AgentCore SDK Decorators (Strands Example)

```python
# agent.py — AgentCore Runtime compatible agent
from bedrock_agentcore_runtime import BedrockAgentCoreApp
from strands import Agent
from strands.models import BedrockModel

app = BedrockAgentCoreApp()

model = BedrockModel(
    model_id="anthropic.claude-sonnet-4-20250514",
    region_name="us-east-1"
)

@app.handler
def handle_request(session_id: str, input_text: str):
    agent = Agent(
        model=model,
        system_prompt="You are a helpful assistant.",
        tools=[...]
    )
    return agent(input_text)

if __name__ == "__main__":
    app.run(port=8080)
```

The `BedrockAgentCoreApp` wrapper creates the HTTP server with required health check and invocation endpoints, handles authentication, and integrates with AgentCore's session management.

## Starter Toolkit (FAST Template)

For full-stack deployments with Cognito auth, React frontend, and all AgentCore services:

```bash
git clone https://github.com/aws/bedrock-agentcore-starter-toolkit.git
cd bedrock-agentcore-starter-toolkit
pip install -r requirements.txt
cdk deploy --all
```

The FAST template deploys: Runtime + Gateway + Memory + Code Interpreter + Observability + Cognito + CloudFront frontend. See the main SKILL.md for the full architecture diagram.

## CI/CD with GitHub Actions

```yaml
# .github/workflows/deploy-agent.yml
name: Deploy Agent to AgentCore

on:
  push:
    branches: [main]
    paths: ['agents/**']

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/agentcore-deploy
          aws-region: us-east-1

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push container
        run: |
          docker build -t $ECR_REPO:$GITHUB_SHA .
          docker push $ECR_REPO:$GITHUB_SHA

      - name: Deploy to AgentCore Runtime
        run: |
          aws bedrock-agentcore create-agent-runtime \
            --agent-runtime-name my-agent \
            --agent-runtime-artifact '{"containerImage": {"uri": "'$ECR_REPO:$GITHUB_SHA'"}}'

      - name: Run agent evaluations
        run: |
          deepeval test run tests/agent_evals.py --report

      - name: Update alias to new version
        run: |
          aws bedrock-agentcore update-agent-runtime-endpoint \
            --agent-runtime-endpoint-name production \
            --agent-runtime-id $RUNTIME_ID
```

## Alias Management

Aliases decouple consumers from specific agent versions. Use them for:

| Alias | Purpose | Traffic |
|---|---|---|
| `production` | Stable, tested version | 100% production traffic |
| `canary` | New version under test | 5-10% via traffic splitting |
| `staging` | Pre-production testing | Internal test traffic only |

### Traffic Splitting for Canary Deployments

```bash
# Route 90% to v1, 10% to v2
aws bedrock-agentcore update-agent-runtime-endpoint \
  --agent-runtime-endpoint-name production \
  --routing-configuration '[
    {"agentRuntimeVersion": "1", "weight": 90},
    {"agentRuntimeVersion": "2", "weight": 10}
  ]'
```

### Rollback Pattern

```bash
# Immediate rollback: point alias back to previous version
aws bedrock-agentcore update-agent-runtime-endpoint \
  --agent-runtime-endpoint-name production \
  --agent-runtime-version 1
```

## VPC Configuration

Enable VPC connectivity when agents need to access:
- Private databases (RDS, DynamoDB via VPC endpoint)
- Internal APIs behind an ALB
- On-premises resources via VPN/Direct Connect

```bash
aws bedrock-agentcore update-agent-runtime \
  --agent-runtime-id $RUNTIME_ID \
  --network-configuration '{
    "networkMode": "VPC",
    "vpcConfig": {
      "subnetIds": ["subnet-abc123", "subnet-def456"],
      "securityGroupIds": ["sg-xyz789"]
    }
  }'
```

### VPC Security Group Rules
- **Outbound**: Allow HTTPS (443) to Bedrock endpoints, your APIs, and any external services
- **Inbound**: Not required — AgentCore Runtime initiates all connections
- Place in private subnets with NAT Gateway for internet access (model API calls)

## Scaling Patterns

### Real-Time Conversational Agents
- CPU: 1 vCPU, Memory: 2 GiB
- Session TTL: 300-600s
- Expect sub-second response initiation with streaming

### Long-Running Async Agents (Research, Data Processing)
- CPU: 2-4 vCPU, Memory: 4-8 GiB
- Session TTL: up to 28,800s (8 hours)
- Use async invocation API for fire-and-forget patterns

### High-Concurrency Agents
- AgentCore auto-scales based on concurrent sessions
- Default quota: 1,000 active session workloads per account (us-east-1), 500 in other regions
- Request quota increase for high-traffic agents before launch

## Resource Quotas (Key Limits)

| Resource | Default Limit | Adjustable |
|---|---|---|
| Active session workloads per account | 1,000 (us-east-1) / 500 (other) | Yes |
| Total agents per account | 1,000 | Yes |
| Versions per agent | 1,000 | Yes |
| Docker image size | Check latest docs | Yes |
| Request timeout | Check latest docs | Yes |
| Max payload size | Check latest docs | - |
| Streaming max duration | Check latest docs | - |
| Async job max duration | Check latest docs | - |

Always verify current limits via `aws-docs` MCP tools — quotas are updated frequently.
