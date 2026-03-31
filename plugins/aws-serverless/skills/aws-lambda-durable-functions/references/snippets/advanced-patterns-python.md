# Advanced Patterns - Python

## GenAI Agent with Reasoning

```python
@durable_execution
def handler(event: dict, context: DurableContext) -> str:
    context.logger.info('Starting AI agent', extra={'prompt': event['prompt']})
    messages = [{'role': 'user', 'content': event['prompt']}]

    while True:
        result = context.step(invoke_ai_model(messages))
        response = result['response']
        reasoning = result.get('reasoning')
        tool = result.get('tool')

        if reasoning:
            context.logger.debug('AI reasoning', extra={'reasoning': reasoning})

        if tool is None:
            context.logger.info('AI agent completed')
            return response

        # Dynamic step naming
        tool_result = context.step(
            func=execute_tool(tool, response),
            name=f"execute-tool-{tool['name']}"
        )

        messages.append({'role': 'assistant', 'content': tool_result})
        context.logger.debug('Tool result added', extra={'tool': tool['name']})
```
