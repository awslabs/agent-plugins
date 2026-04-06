# Bedrock Cost Modeling Reference

## Pricing Model Basics

Bedrock charges per token (input and output separately). Key variables:
- **Input tokens**: Prompt (system + user + context). Controllable via prompt design and context selection.
- **Output tokens**: Model's response. Control via max_tokens and prompt design.
- **Cached input tokens**: Repeated system prompts cached by Bedrock — up to 90% cheaper for supported models.
- **Batch inference**: 50% discount for async, non-real-time workloads.
- **Provisioned throughput**: Committed capacity — only for high, sustained volume. Minimum commitment is 1 month.

## Cost Modeling Template

```
Daily invocations:          ___
Avg input tokens/call:      ___
Avg output tokens/call:     ___
% cacheable input tokens:   ___
% batch-eligible calls:     ___

Model: _______________
Input price per 1K tokens:  $___
Output price per 1K tokens: $___
Cached input price:         $___

Daily cost = (invocations x input_tokens x input_price / 1000)
           + (invocations x output_tokens x output_price / 1000)
           - cache savings - batch savings
```

## Cost Drivers by Component

### Model Inference
- Largest cost driver in most Bedrock architectures
- Output tokens typically cost 3-5x more than input tokens
- Prompt caching reduces input cost by up to 90% for stable system prompts
- Batch inference provides 50% discount for non-real-time workloads

### Knowledge Bases
- **Embedding generation**: One-time cost to embed documents (charged per token at embedding model rate)
- **Vector store**: OpenSearch Serverless minimum ~$700/mo per collection — use a single collection for multiple KBs in dev
- **Retrieval inference**: Each retrieval query invokes the embedding model + the generation model
- Tune retrieved chunk count (default 5) — more chunks = more input tokens = higher cost

### Agents
- Agent invocations compound: each "step" (reasoning + tool call) is a separate model invocation
- A single agent turn can easily be 3-8 model invocations depending on tool count and reasoning steps
- Router + specialist pattern (Nova Micro routing to focused agents) reduces cost vs one large agent reasoning over many tools
- Return Control action groups avoid Lambda invocation costs by executing tools client-side

### Guardrails
- Charged per text unit (1,000 characters) — not per token
- Content filters are cheaper than denied topic policies
- Apply guardrails only to user-facing inputs/outputs — skip for internal agent reasoning steps
- Contextual grounding checks add cost but catch hallucination at inference time

## Cost Optimization Strategies

### Model Right-Sizing
- Start with the smallest model that meets quality requirements — upgrade with evidence
- Use Nova Micro/Haiku for classification, routing, and extraction tasks
- Reserve Opus for genuinely hard problems where Sonnet falls short
- Benchmark on real data, not generic benchmarks — smaller well-prompted models often beat larger general ones

### Prompt Optimization
- Structure prompts: long, stable system prompt + short, variable user prompt (maximizes cache hits)
- Request JSON with explicit schemas to reduce output token waste
- Use the Converse API with tool use for structured extraction — more reliable and token-efficient than freeform JSON
- Minimize few-shot examples in prompts when possible — they inflate input tokens

### Batch vs On-Demand
- Use batch inference for: document processing, bulk classification, dataset enrichment, eval runs
- Not for: real-time user-facing requests (latency is minutes to hours)
- 50% discount makes batch the default choice for any workload that can tolerate async processing

### Intelligent Routing
- Use Bedrock's intelligent prompt routing to auto-route to the cheapest model that can handle each request
- Alternatively, build a custom router: Nova Micro classifies complexity → routes to Nova Pro or Sonnet as needed

### Cross-Region Inference
- Cross-region inference pricing may differ — verify with `aws-docs` MCP tools
- Some models are cheaper in specific regions or have better availability

## Cost Monitoring

### CloudWatch Metrics
- `InvocationCount`: Track total invocations by model
- `InputTokenCount` / `OutputTokenCount`: Monitor token consumption trends
- `InvocationLatency`: Higher latency may indicate throttling (which means hitting capacity limits)

### Cost Explorer
```bash
# Check Bedrock spend (last 30 days) broken down by usage type
aws ce get-cost-and-usage \
  --time-period Start=$(date -v-30d +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Bedrock"]}}' \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=USAGE_TYPE
```

### Budget Alerts
Set up AWS Budgets with alerts at 50%, 80%, and 100% of expected monthly Bedrock spend. Agent-based architectures are especially prone to cost spikes during iteration.

## Cost Estimation Output Format

| Component | Volume | Unit Cost | Monthly Cost | Notes |
|---|---|---|---|---|
| Model inference (input) | ... | ... | ... | ... |
| Model inference (output) | ... | ... | ... | ... |
| Prompt caching savings | ... | ... | -$... | ... |
| Knowledge base (embedding) | ... | ... | ... | ... |
| Knowledge base (retrieval) | ... | ... | ... | ... |
| Vector store (OpenSearch) | ... | ... | ... | ... |
| Guardrails | ... | ... | ... | ... |
| Batch discount | ... | ... | -$... | ... |
| **Total** | | | **$___** | |

Include a sensitivity analysis: what happens if volume doubles? If avg tokens increase 50%?
