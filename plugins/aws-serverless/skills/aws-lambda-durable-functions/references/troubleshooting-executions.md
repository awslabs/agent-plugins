# Troubleshooting Executions

**PROACTIVE AGENT**: When users report issues with durable function executions, spawn a specialized troubleshooting agent.

## When to Spawn Troubleshooting Agent

Spawn the agent when users mention:

- "My execution is stuck"
- "Execution failed with ID xyz"
- "Debug execution abc123"
- "Troubleshoot execution"
- "Why is my durable function not completing"
- Provide an execution ID and need diagnosis

## Agent Instructions

When spawning the troubleshooting agent, provide:

```
Diagnose durable function execution issue:
- Function: <function-name>:<alias> (must be qualified ARN)
- Execution ID: <execution-id>

CRITICAL SAFETY RULES:
- This is READ-ONLY diagnosis
- NEVER call StopDurableExecution or any termination APIs
- NEVER modify execution state
- Only suggest manual remediation if user explicitly requests it

Steps:
1. Run: aws lambda get-durable-execution-history --function-name <function> --execution-id <id>
2. Analyze execution status (RUNNING/SUCCEEDED/FAILED/TIMED_OUT)
3. Check for stuck operations (PENDING/RUNNING status)
4. Identify failed operations and error messages
5. Calculate operation durations and timeline
6. Diagnose specific issue:
   - Stuck in WAIT_FOR_CALLBACK: Extract callback ID, suggest manual callback
   - Failed operations: Show error and retry attempts
   - Timeout: Calculate total duration, identify slow operations
   - Unexpected behavior: Compare operation order with expected flow
7. Provide specific recommendations and next steps

Use jq for JSON parsing and analysis.
```

## Example Usage

```
User: "My durable function execution abc-123 is stuck on my-function:prod"

Claude: [Spawns Task agent with troubleshooting instructions]
Agent: [Runs get-durable-execution-history command]
Agent: [Analyzes with jq queries]
Agent: [Returns: "Execution stuck in WAIT_FOR_CALLBACK operation 'wait-for-approval'.
         Callback ID: xyz789. Waiting since 2026-02-14. Timeout in 12 hours.
         Recommendation: Check if approval email was sent, or manually send callback."]
Claude: [Presents findings and offers to send manual callback if needed]
```
