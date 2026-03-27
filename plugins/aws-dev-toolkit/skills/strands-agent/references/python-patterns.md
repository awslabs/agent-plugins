# Strands Agent — Python Patterns

## Minimal Agent

```python
from strands import Agent

agent = Agent(
    system_prompt="You are a helpful assistant."
)

response = agent("What can you help me with?")
print(response)
```

## Agent with Custom Tools

```python
from strands import Agent, tool

@tool
def lookup_order(order_id: str) -> str:
    """Look up an order by ID. Returns order status, items, and shipping info."""
    # Replace with your actual data source
    return f"Order {order_id}: shipped, tracking TRK-12345"

agent = Agent(
    system_prompt="You are a customer service agent. Help users check their orders.",
    tools=[lookup_order],
)

response = agent("Where is my order #ORD-789?")
print(response)
```

## AgentCore Deployment Entrypoint

```python
# agent.py — AgentCore-compatible entrypoint
import os
from strands import Agent, tool
from bedrock_agentcore.runtime import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

@tool
def lookup_order(order_id: str) -> str:
    """Look up an order by ID."""
    return f"Order {order_id}: shipped, tracking TRK-12345"

@app.entrypoint
async def invoke(payload, context):
    agent = Agent(
        model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        tools=[lookup_order],
    )
    response = await agent.invoke_async(payload.get("prompt", ""))
    return {"response": str(response.message)}
```

## AgentCore with Memory

```python
# agent.py — with AgentCore memory integration
import os
from strands import Agent, tool
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager

app = BedrockAgentCoreApp()
MEMORY_ID = os.getenv("BEDROCK_AGENTCORE_MEMORY_ID")
REGION = os.getenv("AWS_REGION", "us-east-1")

@app.entrypoint
async def invoke(payload, context):
    session_manager = None
    if MEMORY_ID:
        memory_config = AgentCoreMemoryConfig(
            memory_id=MEMORY_ID,
            session_id=context.session_id,
            actor_id=context.actor_id,
        )
        session_manager = AgentCoreMemorySessionManager(memory_config, REGION)

    agent = Agent(
        model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        system_prompt="You are a helpful assistant. Use what you know about the user.",
        session_manager=session_manager,
    )
    response = await agent.invoke_async(payload.get("prompt", ""))
    return {"response": str(response.message)}
```

## Project Structure

```
my-agent/
├── agent.py              # Agent entrypoint
├── tools/                # Custom tool definitions
│   ├── __init__.py
│   └── lookup_order.py
├── requirements.txt
├── .gitignore
└── README.md
```

## requirements.txt

```
strands-agents
bedrock-agentcore
```
