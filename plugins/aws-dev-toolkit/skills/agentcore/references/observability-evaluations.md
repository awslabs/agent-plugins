# AgentCore Observability and Evaluations Reference

## Observability

AgentCore Observability provides OpenTelemetry-compatible tracing, metrics, and logging for agent workflows. Traces flow to CloudWatch and X-Ray.

### Automatic Instrumentation

Agents deployed on AgentCore Runtime with the AWS OpenTelemetry Distro are automatically instrumented. Traces capture:
- Agent invocation start/end
- Model inference calls (model ID, latency, token usage)
- Tool calls (tool name, parameters, duration, success/failure)
- Memory operations (read/write)
- Session lifecycle events

### Manual Instrumentation (Custom Spans)

```python
from opentelemetry import trace

tracer = trace.get_tracer("my-agent")

@tracer.start_as_current_span("custom-business-logic")
def process_order(order_id: str):
    span = trace.get_current_span()
    span.set_attribute("order.id", order_id)
    span.set_attribute("order.type", "refund")

    # Your business logic here
    result = lookup_order(order_id)

    span.set_attribute("order.found", result is not None)
    return result
```

### CloudWatch Metrics

#### Critical Metrics — Alarm on These

| Metric | Namespace | Alarm Threshold | Action |
|---|---|---|---|
| `InvocationCount` | AWS/BedrockAgentCore | Sudden drop >50% | Agent may be unhealthy or unreachable |
| `InvocationErrors` | AWS/BedrockAgentCore | >5% error rate sustained 5 min | Check agent logs, model availability |
| `InvocationLatency` (p99) | AWS/BedrockAgentCore | >30s for real-time agents | Model overloaded, tool calls slow, or session state bloated |
| `ThrottleCount` | AWS/BedrockAgentCore | Any sustained occurrence | Approaching quota limits — request increase |
| `SessionCount` | AWS/BedrockAgentCore | >80% of active session quota | Scale quota or optimize session TTLs |

#### Important Metrics — Review Weekly

| Metric | What to Look For | Notes |
|---|---|---|
| `TokenUsage` (input/output) | Cost trends, unexpected spikes | Prompt drift or reasoning loops can explode token usage |
| `ToolCallDuration` | Slow tools degrading agent performance | Optimize the slowest tool first |
| `ToolCallErrors` | Failing tool integrations | May indicate upstream service issues |
| `MemoryOperations` | Read/write patterns | High write volume may indicate memory strategy misconfiguration |

### CloudWatch Dashboard Template

```bash
# Create a comprehensive AgentCore monitoring dashboard
aws cloudwatch put-dashboard \
  --dashboard-name AgentCore-Production \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "title": "Invocations & Errors",
          "metrics": [
            ["AWS/BedrockAgentCore", "InvocationCount", "AgentId", "my-agent"],
            ["AWS/BedrockAgentCore", "InvocationErrors", "AgentId", "my-agent"]
          ],
          "period": 300,
          "stat": "Sum"
        }
      },
      {
        "type": "metric",
        "properties": {
          "title": "Latency (p50/p99)",
          "metrics": [
            ["AWS/BedrockAgentCore", "InvocationLatency", "AgentId", "my-agent", {"stat": "p50"}],
            ["AWS/BedrockAgentCore", "InvocationLatency", "AgentId", "my-agent", {"stat": "p99"}]
          ],
          "period": 300
        }
      },
      {
        "type": "metric",
        "properties": {
          "title": "Active Sessions",
          "metrics": [
            ["AWS/BedrockAgentCore", "SessionCount", "AgentId", "my-agent"]
          ],
          "period": 60,
          "stat": "Maximum"
        }
      }
    ]
  }'
```

### X-Ray Tracing

AgentCore traces integrate with X-Ray for distributed tracing across agent → tool → downstream service calls.

```bash
# Query traces for a specific agent
aws xray get-trace-summaries \
  --start-time $(date -v-1H +%s) \
  --end-time $(date +%s) \
  --filter-expression 'service("bedrock-agentcore") AND annotation.agent_id = "my-agent"'
```

### Langfuse Integration (LLM-Specific Analytics)

For deeper LLM-level observability beyond infrastructure metrics, layer Langfuse on top of CloudWatch:

```python
from langfuse import Langfuse
from langfuse.decorators import observe, langfuse_context

langfuse = Langfuse(
    public_key="pk-...",    # Store in Secrets Manager
    secret_key="sk-...",    # Store in Secrets Manager
    host="https://your-langfuse-instance.com"
)

@observe(as_type="generation")
def invoke_model(prompt, model_id):
    """Model invocation with Langfuse tracing."""
    response = bedrock_runtime.invoke_model(
        modelId=model_id,
        body=json.dumps({"messages": [{"role": "user", "content": prompt}]})
    )
    result = json.loads(response['body'].read())

    langfuse_context.update_current_observation(
        model=model_id,
        usage={
            "input_tokens": result['usage']['input_tokens'],
            "output_tokens": result['usage']['output_tokens']
        }
    )
    return result

@observe()
def run_agent(user_input):
    """Full agent execution with nested tracing."""
    classification = invoke_model(f"Classify: {user_input}", "amazon.nova-micro-v1:0")
    response = invoke_model(f"Respond: {user_input}", "anthropic.claude-sonnet-4-20250514")
    return response
```

### Observability Stack Recommendation

| Phase | Stack | Why |
|---|---|---|
| PoC | AgentCore native (CloudWatch + X-Ray) | Zero setup, included with Runtime |
| Pre-production | + Langfuse | Add LLM-specific analytics (cost per trace, prompt management) |
| Production | CloudWatch + X-Ray + Langfuse + custom dashboards | Full stack: infra health + LLM behavior + business metrics |

---

## Evaluations

### Built-In Evaluators (13 Available)

AgentCore provides 13 built-in evaluators covering common quality dimensions:

| Category | Evaluators | What They Measure |
|---|---|---|
| **Relevancy** | Answer relevancy, Context relevancy | Does the response address the question? Is retrieved context relevant? |
| **Faithfulness** | Faithfulness, Groundedness | Is the response grounded in provided context? |
| **Hallucination** | Hallucination detection | Does the response contain fabricated information? |
| **Safety** | Toxicity, Harmfulness | Does the response contain harmful or toxic content? |
| **Quality** | Coherence, Fluency | Is the response well-structured and readable? |
| **Tool use** | Tool selection accuracy, Parameter correctness | Did the agent pick the right tool with right parameters? |

### On-Demand Evaluation

```bash
# Run an on-demand evaluation against test data
aws bedrock-agentcore create-on-demand-evaluation \
  --evaluation-name weekly-quality-check \
  --evaluator-ids '["answer-relevancy", "faithfulness", "hallucination"]' \
  --test-data-source '{
    "s3Uri": "s3://my-evals-bucket/test-cases.jsonl"
  }'
```

### Online Evaluation (Continuous Monitoring)

```bash
# Configure continuous evaluation on sampled live traffic
aws bedrock-agentcore create-online-evaluation-config \
  --config-name production-monitoring \
  --agent-runtime-id $RUNTIME_ID \
  --evaluator-ids '["answer-relevancy", "faithfulness", "tool-selection"]' \
  --sampling-rate 0.1  # Evaluate 10% of live sessions
```

### DeepEval Integration (CI/CD Quality Gate)

For more control and CI/CD integration, use DeepEval alongside AgentCore evaluations:

```python
# tests/agent_evals.py
import pytest
from deepeval import assert_test
from deepeval.test_case import LLMTestCase
from deepeval.metrics import (
    AnswerRelevancyMetric,
    FaithfulnessMetric,
    HallucinationMetric,
    GEval
)

# Answer relevancy — does the agent actually answer the question?
def test_answer_relevancy():
    test_case = LLMTestCase(
        input="What is the refund policy for enterprise customers?",
        actual_output=agent_response,
        retrieval_context=["Enterprise customers can request refunds within 30 days..."]
    )
    metric = AnswerRelevancyMetric(threshold=0.7)
    assert_test(test_case, [metric])

# Faithfulness — is the agent grounded in retrieved context?
def test_faithfulness():
    test_case = LLMTestCase(
        input="What are the SLA terms?",
        actual_output=agent_response,
        retrieval_context=retrieved_docs
    )
    metric = FaithfulnessMetric(threshold=0.8)
    assert_test(test_case, [metric])

# Custom eval — agent-specific quality criteria
def test_tool_use_correctness():
    correctness = GEval(
        name="Tool Use Correctness",
        criteria="The agent selected the appropriate tool and passed correct parameters.",
        evaluation_params=["input", "actual_output"],
        threshold=0.7
    )
    test_case = LLMTestCase(
        input="Look up order #12345",
        actual_output=agent_response
    )
    assert_test(test_case, [correctness])
```

### Running Evals in CI/CD

```yaml
# In your GitHub Actions workflow
- name: Run agent evaluations
  run: |
    pip install deepeval
    deepeval test run tests/agent_evals.py --report

- name: Run AgentCore built-in evals
  run: |
    aws bedrock-agentcore create-on-demand-evaluation \
      --evaluation-name "ci-$GITHUB_SHA" \
      --evaluator-ids '["answer-relevancy", "faithfulness", "tool-selection"]' \
      --test-data-source '{"s3Uri": "s3://evals/test-cases.jsonl"}'
```

### Eval Strategy by Phase

| Phase | What to Eval | Frequency | Tool |
|---|---|---|---|
| PoC | Answer relevancy, basic hallucination | After each prompt change | DeepEval locally |
| Pre-production | Full suite + faithfulness + tool use | Every PR / deploy | DeepEval in CI + AgentCore on-demand |
| Production | Regression suite + sampled live traffic | Daily + on model updates | AgentCore online evals + DeepEval regression |

### Building Your Eval Dataset

1. **Start with 20-30 representative queries** from real users or domain experts
2. **Include edge cases**: ambiguous queries, out-of-scope requests, adversarial inputs
3. **Version your eval dataset** alongside your agent code (in Git)
4. **Expand as you discover failure modes** in production — every production incident should add at least one eval case
5. **Separate eval tiers**: fast smoke tests (5 cases, every commit) vs full regression (50+ cases, nightly)

### Evaluation Quotas

| Resource | Default Limit |
|---|---|
| Input tokens per minute (built-in evaluators) | Check latest docs |
| Evaluations per minute (built-in evaluators) | Check latest docs |
| Spans per on-demand evaluation | Check latest docs |
| Evaluators per on-demand evaluation | Check latest docs |

---

## Production Monitoring Playbook

### Daily Checks
1. Review CloudWatch dashboard for invocation count, error rate, latency trends
2. Check for any Policy DENY spikes (may indicate agent behavior drift)
3. Review Langfuse cost-per-conversation trends

### Weekly Checks
1. Review online evaluation scores — any degradation?
2. Audit token usage trends — any unexpected growth?
3. Check session TTL utilization — are sessions timing out prematurely?
4. Review tool call error rates by tool — any upstream service degradation?

### On Model Update
1. Run full DeepEval regression suite before switching models
2. Deploy new model version behind canary alias (10% traffic)
3. Monitor online eval scores for canary vs production for 24-48 hours
4. Promote or rollback based on eval scores

### Incident Response
1. Check X-Ray traces for the failing session
2. Review Policy decisions — was a tool call incorrectly denied/allowed?
3. Check CloudWatch Logs for agent-level errors
4. Review Langfuse trace for the specific conversation (token usage, tool calls, reasoning steps)
5. Add a new eval case for the failure mode
