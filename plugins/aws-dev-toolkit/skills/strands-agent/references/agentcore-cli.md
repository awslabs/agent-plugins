# AgentCore CLI Quick Reference

Install: `pip install bedrock-agentcore-starter-toolkit`

## Core Workflow

```bash
# 1. Configure
agentcore configure --entrypoint agent.py --name my-agent

# 2. Deploy
agentcore deploy                    # Cloud (CodeBuild, no Docker)
agentcore deploy --local            # Local (needs Docker/Finch/Podman)
agentcore deploy --local-build      # Build local, deploy to cloud

# 3. Invoke
agentcore invoke '{"prompt": "Hello!"}'
agentcore invoke '{"prompt": "Continue"}' --session-id abc123

# 4. Check status
agentcore status
agentcore status --verbose

# 5. Stop session (save costs)
agentcore stop-session

# 6. Tear down
agentcore destroy --dry-run         # Preview
agentcore destroy --force           # No confirmation
```

## Configure Options

| Flag | Description |
|---|---|
| `--entrypoint, -e` | Python file of agent (required) |
| `--name, -n` | Agent name |
| `--deployment-type, -dt` | `direct_code_deploy` (default) or `container` |
| `--runtime, -rt` | Python version: PYTHON_3_10 through PYTHON_3_13 |
| `--disable-memory, -dm` | Skip memory setup |
| `--disable-otel, -do` | Disable OpenTelemetry |
| `--idle-timeout, -it` | Seconds before idle termination (60-28800, default 900) |
| `--max-lifetime, -ml` | Max instance lifetime seconds (60-28800, default 28800) |
| `--region, -r` | AWS region |
| `--non-interactive, -ni` | Skip prompts, use defaults |
| `--vpc` | Enable VPC networking (requires --subnets and --security-groups) |

## Memory Configuration

Memory is opt-in. Three modes:

| Mode | Description |
|---|---|
| `NO_MEMORY` | Default. No memory resources. |
| `STM_ONLY` | Short-term memory. 30-day retention. Conversations within sessions. |
| `STM_AND_LTM` | Short-term + Long-term. Extracts preferences, facts, summaries across sessions. |

```bash
# Interactive — prompts for memory setup
agentcore configure --entrypoint agent.py

# Explicitly disable
agentcore configure --entrypoint agent.py --disable-memory

# Non-interactive (STM only by default)
agentcore configure --entrypoint agent.py --non-interactive
```

## Memory Management

```bash
agentcore memory create my_memory                    # Create STM
agentcore memory create my_memory --strategies '[{"semanticMemoryStrategy": {"name": "Facts"}}]' --wait  # With LTM
agentcore memory list                                # List all
agentcore memory status <memory-id>                  # Check status
agentcore memory delete <memory-id> --wait           # Delete
```

## Deploy Options

| Flag | Description |
|---|---|
| `--local, -l` | Build and run locally (needs Docker) |
| `--local-build, -lb` | Build locally, deploy to cloud |
| `--image-tag, -t` | Custom image tag for versioning |
| `--auto-update-on-conflict, -auc` | Update existing agent instead of failing |
| `--env, -env` | Environment variables (KEY=VALUE) |

## Gateway (MCP Gateway)

```bash
agentcore gateway create-mcp-gateway --name MyGateway
agentcore gateway create-mcp-gateway-target --gateway-arn <arn> --gateway-url <url> --role-arn <role>
agentcore gateway list-mcp-gateways
agentcore gateway delete-mcp-gateway --name MyGateway --force
```

## Identity (OAuth / JWT)

```bash
# AWS JWT (secretless M2M auth)
agentcore identity setup-aws-jwt --audience https://api.example.com

# Cognito (user auth)
agentcore identity setup-cognito
agentcore identity setup-cognito --auth-flow m2m

# Credential providers
agentcore identity create-credential-provider --name MyProvider --type github --client-id <id> --client-secret <secret>

# Cleanup
agentcore identity cleanup --agent my-agent --force
```

## Useful Patterns

```bash
# List configured agents
agentcore configure list

# Set default agent
agentcore configure set-default my-agent

# Deploy with semantic versioning
agentcore deploy --image-tag $(git describe --tags --always)

# Deploy with env vars
agentcore deploy --env API_KEY=abc123 --env DEBUG=true

# Import existing Bedrock Agent to AgentCore
agentcore import-agent
```
