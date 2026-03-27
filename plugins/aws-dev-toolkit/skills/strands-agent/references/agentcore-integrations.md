# AgentCore Integrations: Observability, Evals, Tracing, Memory

## Observability & Distributed Tracing

Strands has OpenTelemetry (OTel) baked in. Traces are emitted automatically for every agent invocation, model call, and tool execution. You just need to tell it where to send them.

### Enable Tracing (Python)

Set the OTLP endpoint and Strands starts exporting traces:

```bash
# Send to any OTLP-compatible collector (Jaeger, Grafana, etc.)
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317

# For AgentCore deployed agents, OTEL is enabled by default
# Disable with: agentcore configure --disable-otel
```

Strands automatically creates spans for:
- Agent invocations (full request lifecycle)
- Model calls (input/output tokens, latency, model ID)
- Tool executions (tool name, input, output, duration)
- Error states and retries

### Enable Tracing (TypeScript)

```typescript
// TypeScript uses the same OTel environment variables
// Set OTEL_EXPORTER_OTLP_ENDPOINT before starting your agent
// Strands TS SDK emits spans automatically
```

### AgentCore Native Observability

When deployed to AgentCore, you get observability out of the box:

- **CloudWatch Logs**: Agent session transcripts at `/aws/bedrock-agentcore/runtimes/<agent-name>`
- **X-Ray Traces**: Distributed traces across agent → model → tool calls
- **CloudWatch Metrics**: Invocation count, latency, errors (namespace: `bedrock-agentcore`)
- **GenAI Observability Dashboard**: Token usage, model latency, cost — linked from `agentcore status`

```bash
# Tail agent logs
aws logs tail /aws/bedrock-agentcore/runtimes/<agent-name>-DEFAULT \
  --region us-east-1 --since 5m --follow

# Check agent metrics
aws cloudwatch get-metric-statistics \
  --namespace bedrock-agentcore \
  --metric-name Invocations \
  --start-time $(date -v-1d +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date +%Y-%m-%dT%H:%M:%S) \
  --period 3600 --statistics Sum
```

### Third-Party Observability Backends

Strands OTel traces are vendor-neutral. Route them to any backend:

| Backend | How | Notes |
|---|---|---|
| CloudWatch + X-Ray | Default on AgentCore | Zero config, GenAI dashboard included |
| Langfuse | Set OTLP endpoint to Langfuse collector | LLM-native: cost per trace, prompt versioning |
| Grafana | OTel collector → Grafana Cloud | Rich dashboards, alerting |
| Datadog | OTel collector → Datadog | APM integration, anomaly detection |
| Elastic | OTel collector → Elastic APM | Full-stack correlation |
| Arize Phoenix | `openinference-instrumentation-strands-agents` | OpenInference format, trace visualization |

### Trace Attributes

Strands enriches spans with GenAI semantic conventions. Opt in to experimental attributes:

```bash
# Enable experimental GenAI attributes
export OTEL_SEMCONV_STABILITY_OPT_IN=gen_ai_latest_experimental,gen_ai_tool_definitions
```

This adds:
- `gen_ai.system`: Model provider
- `gen_ai.request.model`: Model ID
- `gen_ai.usage.input_tokens` / `gen_ai.usage.output_tokens`: Token counts
- `gen_ai.conversation.id`: Session correlation
- Tool definition schemas in spans

---

## Evaluation with Strands Evals

Strands Evals is a dedicated evaluation framework with LLM-as-a-Judge built in. Install separately:

```bash
pip install strands-agents-evals
```

> **Note**: Strands Evals is Python-only as of now. Even if your agent is TypeScript, write your evals in Python.

### Built-in Evaluators

| Evaluator | Level | What It Measures |
|---|---|---|
| `OutputEvaluator` | Response | Custom rubric-based quality scoring |
| `TrajectoryEvaluator` | Trajectory | Tool selection sequence and efficiency |
| `HelpfulnessEvaluator` | Response | 7-point helpfulness scale |
| `FaithfulnessEvaluator` | Response | Grounded in context (anti-hallucination) |
| `HarmfulnessEvaluator` | Response | Safety check (binary) |
| `ToolSelectionAccuracyEvaluator` | Tool | Was the right tool chosen? |
| `ToolParameterAccuracyEvaluator` | Tool | Were tool parameters correct? |
| `GoalSuccessRateEvaluator` | Session | Did the user achieve their goal? |
| `InteractionsEvaluator` | Multi-agent | Quality of agent-to-agent interactions |

### Quick Eval Example

```python
from strands import Agent
from strands_evals import Case, Experiment
from strands_evals.evaluators import OutputEvaluator, TrajectoryEvaluator
from strands_evals.extractors import tools_use_extractor

# Define test cases
cases = [
    Case(
        name="order-lookup",
        input="Where is my order #ORD-789?",
        expected_output="Should include order status and tracking info",
        expected_trajectory=["lookup_order"],
    ),
]

# Define evaluators
output_eval = OutputEvaluator(
    rubric="""
    Score 1.0 if the response includes order status and tracking number.
    Score 0.5 if it includes status but no tracking.
    Score 0.0 if it doesn't address the order.
    """,
    include_inputs=True,
)

trajectory_eval = TrajectoryEvaluator(
    rubric="Verify the agent used the lookup_order tool with the correct order ID.",
    include_inputs=True,
)

# Task function — connects your agent to the eval framework
def my_task(case):
    agent = Agent(tools=[lookup_order], callback_handler=None)
    result = agent(case.input)
    trajectory = tools_use_extractor.extract_agent_tools_used_from_messages(agent.messages)
    return {"output": str(result), "trajectory": trajectory}

# Run
experiment = Experiment(cases=cases, evaluators=[output_eval, trajectory_eval])
reports = experiment.run_evaluations(my_task)
reports[0].run_display()
```

### Trace-Based Evaluation (Using OTel Spans)

For deeper analysis, evaluate using captured OTel traces:

```python
from strands_evals.telemetry import StrandsEvalsTelemetry
from strands_evals.mappers import StrandsInMemorySessionMapper
from strands_evals.evaluators import HelpfulnessEvaluator

telemetry = StrandsEvalsTelemetry().setup_in_memory_exporter()

def task_with_traces(case):
    telemetry.in_memory_exporter.clear()
    agent = Agent(
        tools=[lookup_order],
        trace_attributes={
            "gen_ai.conversation.id": case.session_id,
            "session.id": case.session_id,
        },
        callback_handler=None,
    )
    response = agent(case.input)
    spans = telemetry.in_memory_exporter.get_finished_spans()
    session = StrandsInMemorySessionMapper().map_to_session(spans, session_id=case.session_id)
    return {"output": str(response), "trajectory": session}

experiment = Experiment(cases=cases, evaluators=[HelpfulnessEvaluator()])
reports = experiment.run_evaluations(task_with_traces)
```

### Multi-Turn Simulation

Test multi-turn conversations with simulated users:

```python
from strands_evals import Case, ActorSimulator

case = Case(
    input="I need to return a damaged item",
    metadata={"task_description": "Successfully initiate a return"},
)

user_sim = ActorSimulator.from_case_for_user_simulator(case=case, max_turns=10)
agent = Agent(tools=[lookup_order, initiate_return])

user_message = case.input
while user_sim.has_next():
    agent_response = agent(user_message)
    user_result = user_sim.act(str(agent_response))
    user_message = str(user_result.structured_output.message)

# Then evaluate the full session with GoalSuccessRateEvaluator
```

### Auto-Generate Test Cases

```python
from strands_evals.generators import ExperimentGenerator
from strands_evals.evaluators import OutputEvaluator

generator = ExperimentGenerator(input_type=str, output_type=str, include_expected_output=True)
experiment = await generator.from_context_async(
    context="A customer service agent for an e-commerce platform",
    task_description="Handle order inquiries, returns, and product questions",
    num_cases=20,
    evaluator=OutputEvaluator,
    num_topics=4,
)
experiment.to_file("generated_evals")
```

### Eval Strategy

| Phase | What to Eval | Evaluators | Frequency |
|---|---|---|---|
| Dev | Output quality, tool usage | OutputEvaluator, TrajectoryEvaluator | Every prompt change |
| Pre-prod | Full suite + faithfulness + safety | All + HarmfulnessEvaluator | Every PR / deploy |
| Production | Offline traces + goal success | GoalSuccessRateEvaluator, HelpfulnessEvaluator | Daily / on model updates |

---

## Memory Integration

See [python-patterns.md](python-patterns.md) for the code patterns. Key decisions:

### Memory Modes

| Mode | What It Stores | Use Case |
|---|---|---|
| `NO_MEMORY` | Nothing | Stateless tool agents |
| `STM_ONLY` | Conversation history within sessions (30-day retention) | Multi-turn chat |
| `STM_AND_LTM` | STM + extracted preferences, facts, summaries across sessions | Personalization |

### LTM Strategies

When using `STM_AND_LTM`, configure strategies for what to extract:

```python
strategies = [
    {"summaryMemoryStrategy": {"name": "SessionSummarizer", "namespaceTemplates": ["/summaries/{actorId}/{sessionId}/"]}},
    {"userPreferenceMemoryStrategy": {"name": "PreferenceLearner", "namespaceTemplates": ["/preferences/{actorId}/"]}},
    {"semanticMemoryStrategy": {"name": "FactExtractor", "namespaceTemplates": ["/facts/{actorId}/"]}},
]
```

- **summaryMemoryStrategy**: Summarizes sessions for quick recall
- **userPreferenceMemoryStrategy**: Extracts user preferences (likes sushi, prefers TypeScript)
- **semanticMemoryStrategy**: Extracts factual information (user's name, company, role)

### Memory with AgentCore CLI

```bash
# Interactive — prompts for memory setup
agentcore configure --entrypoint agent.py

# Create memory manually
agentcore memory create my_memory --strategies '[{"semanticMemoryStrategy": {"name": "Facts"}}]' --wait

# Check memory status (must be ACTIVE before use)
agentcore memory status <memory-id>
```

### Memory with Batching (High-Throughput)

For agents with many messages per session, batch memory writes:

```python
from bedrock_agentcore.memory.integrations.strands.config import AgentCoreMemoryConfig
from bedrock_agentcore.memory.integrations.strands.session_manager import AgentCoreMemorySessionManager

config = AgentCoreMemoryConfig(
    memory_id=MEMORY_ID,
    session_id=SESSION_ID,
    actor_id=ACTOR_ID,
    batch_size=10,  # Buffer 10 messages before flushing
)

# MUST use context manager or call close() to flush remaining buffer
with AgentCoreMemorySessionManager(config, region_name="us-east-1") as session_manager:
    agent = Agent(session_manager=session_manager)
    agent("Hello!")
    agent("Tell me about AWS")
# Buffered messages auto-flushed on exit
```
