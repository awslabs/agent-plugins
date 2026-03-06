# AWS Step Functions Testing

## TestState API

TestState API enables unit and integration testing of Step Functions without deployment. Key capabilities:

- **Mock service integrations** — Test without invoking real services
- **Advanced states** — Map, Parallel, Activity, `.sync`, `.waitForTaskToken` (require mocks)
- **Control execution** — Simulate retries, Map iterations, error scenarios
- **Chain tests** — Use output→input to test execution paths
- **Optional IAM** — When mocking, `roleArn` optional

```bash
aws stepfunctions test-state \
  --definition '{"Type":"Task","Resource":"arn:aws:states:::lambda:invoke","Arguments":{...},"End":true}' \
  --input '{"data":"value"}' \
  --mock '{"result":"{\"StatusCode\":200,\"Payload\":{\"body\":\"success\"}}"}' \
  --inspection-level DEBUG
```

## Inspection Levels

| Level     | Returns                                                                         | Use Case            |
| --------- | ------------------------------------------------------------------------------- | ------------------- |
| **INFO**  | `output`, `status`, `nextState`                                                 | Quick validation    |
| **DEBUG** | + `afterInputPath`, `afterParameters`, `afterResultSelector`, `afterResultPath` | Data flow debugging |
| **TRACE** | + HTTP `request`/`response` (use `--reveal-secrets` for auth)                   | HTTP Task debugging |

## Critical: Service-Specific Mock Structure

**⚠️ Mocks MUST match AWS service API response schema exactly** — field names (case-sensitive), types, required fields.

### Finding Mock Structure

1. Identify service from `Resource` ARN: `arn:aws:states:::lambda:invoke` → Lambda `Invoke` API
2. Consult AWS SDK docs for that API's Response Syntax
3. Structure mock to match

### Common Service Mocks

| Service         | API              | Mock Structure                          | Example                                                                       |
| --------------- | ---------------- | --------------------------------------- | ----------------------------------------------------------------------------- |
| Lambda          | `Invoke`         | `{StatusCode, Payload, FunctionError?}` | `'{"result":"{\"StatusCode\":200,\"Payload\":{\"body\":\"ok\"}}\"}'`          |
| DynamoDB        | `PutItem`        | `{Attributes?}`                         | `'{"result":"{\"Attributes\":{\"id\":{\"S\":\"123\"}}}"}'`                    |
| DynamoDB        | `GetItem`        | `{Item?}`                               | `'{"result":"{\"Item\":{\"id\":{\"S\":\"123\"}}}"}'`                          |
| SNS             | `Publish`        | `{MessageId}`                           | `'{"result":"{\"MessageId\":\"abc-123\"}"}'`                                  |
| SQS             | `SendMessage`    | `{MessageId, MD5OfMessageBody}`         | `'{"result":"{\"MessageId\":\"xyz\",\"MD5OfMessageBody\":\"...\"}"}'`         |
| EventBridge     | `PutEvents`      | `{FailedEntryCount, Entries[]}`         | `'{"result":"{\"FailedEntryCount\":0,\"Entries\":[{\"EventId\":\"123\"}]}"}'` |
| S3              | `PutObject`      | `{ETag, VersionId?}`                    | `'{"result":"{\"ETag\":\"\\\"abc123\\\"\"}"}'`                                |
| Step Functions  | `StartExecution` | `{ExecutionArn, StartDate}`             | `'{"result":"{\"ExecutionArn\":\"arn:...\",\"StartDate\":\"...\"}"}'`         |
| Secrets Manager | `GetSecretValue` | `{ARN, Name, SecretString?}`            | `'{"result":"{\"Name\":\"MySecret\",\"SecretString\":\"...\"}"}'`             |

**For `.sync` patterns:** Mock the **polling API** (e.g., `startExecution.sync:2` → mock `DescribeExecution`, NOT `StartExecution`)

### Mock Syntax

**Success:** `--mock '{"result":"<service API response JSON>"}'`\
**Error:** `--mock '{"errorOutput":{"error":"ErrorCode","cause":"description"}}'`\
**Validation:** `--mock '{"fieldValidationMode":"STRICT|PRESENT|NONE","result":"..."}'`

**Validation modes:**

- `STRICT` (default): All required fields, correct types — use in CI/CD
- `PRESENT`: Only validate fields present — flexible testing
- `NONE`: No validation — quick prototyping only

## Testing Map States

Tests Map's **input/output processing**, not iterations inside. Mock = entire Map output.

```bash
aws stepfunctions test-state \
  --definition '{
    "Type":"Map",
    "ItemsPath":"$.items",
    "ItemSelector":{"value.$":"$$.Map.Item.Value"},
    "ItemProcessor":{"ProcessorConfig":{"Mode":"INLINE"},...},
    "End":true
  }' \
  --input '{"items":[1,2,3]}' \
  --mock '{"result":"[10,20,30]"}' \
  --inspection-level DEBUG
```

**DEBUG returns:** `afterItemsPath`, `afterItemSelector`, `afterItemBatcher`, `toleratedFailureCount`, `maxConcurrency`

**Distributed Map:** Provide data in input (as if read from S3)\
**Failure threshold testing:** Use `--state-configuration '{"mapIterationFailureCount":N}'`\
**Testing state within Map:** `--state-name` auto-populates `$$.Map.Item.Index`, `$$.Map.Item.Value`

## Testing Parallel States

Mock = JSON array, one element per branch (in definition order):

```bash
--mock '{"result":"[{\"branch1\":\"result1\"},{\"branch2\":\"result2\"}]"}'
```

## Testing Error Handling

### Retry Logic

```bash
--state-configuration '{"retrierRetryCount":1}' \
--mock '{"errorOutput":{"error":"Lambda.ServiceException","cause":"..."}}' \
--inspection-level DEBUG
```

Response includes: `status:"RETRIABLE"`, `retryBackoffIntervalSeconds`, `retryIndex`

### Catch Handlers

```bash
--mock '{"errorOutput":{"error":"Lambda.TooManyRequestsException","cause":"..."}}' \
--inspection-level DEBUG
```

Response includes: `status:"CAUGHT_ERROR"`, `nextState`, `catchIndex`, error in `output` via `ResultPath`

### Error Propagation in Map/Parallel

```bash
--state-name "ChildState" \
--state-configuration '{"errorCausedByState":"ChildState"}' \
--mock '{"errorOutput":{"error":"States.TaskFailed","cause":"..."}}'
```

## Testing .sync and .waitForTaskToken

**Required:** Must provide mock (validation exception otherwise)

### .sync Patterns

Mock the **polling API**, not initial call:

```bash
# startExecution.sync:2 → mock DescribeExecution
--mock '{"result":"{\"Status\":\"SUCCEEDED\",\"Output\":\"{...}\"}"}'
```

Common patterns: `startExecution.sync:2`→`DescribeExecution`, `batch:submitJob.sync`→`DescribeJobs`, `glue:startJobRun.sync`→`GetJobRun`

### .waitForTaskToken

```bash
--context '{"Task":{"Token":"test-token-123"}}' \
--mock '{"result":"{\"StatusCode\":200,\"Payload\":{\"status\":\"approved\"}}"}'
```

## Activity States

Require mock:

```bash
--definition '{"Type":"Task","Resource":"arn:aws:states:...:activity:MyActivity",...}' \
--mock '{"result":"{\"result\":\"completed\"}"}'
```

## Chaining Tests (Integration Testing)

```bash
RESULT_1=$(aws stepfunctions test-state --state-name "State1" ... | jq -r '.output')
NEXT_1=$(... | jq -r '.nextState')
RESULT_2=$(aws stepfunctions test-state --state-name "$NEXT_1" --input "$RESULT_1" ...)
```

Validates: data transformations, state transitions, end-to-end paths

## Context Fields

Test states referencing execution context:

```bash
--context '{
  "Execution":{"Id":"arn:...","Name":"test-123","StartTime":"2024-01-01T10:00:00.000Z"},
  "State":{"Name":"ProcessData","EnteredTime":"2024-01-01T10:00:05.000Z"},
  "Task":{"Token":"test-token-abc123"}
}'
```

## HTTP Tasks (TRACE)

```bash
--resource "arn:aws:states:::http:invoke" \
--inspection-level TRACE \
--reveal-secrets  # Requires states:RevealSecrets permission
```

Returns: `inspectionData.request` (method, URL, headers, body), `inspectionData.response` (status, headers, body)

## Troubleshooting

| Error                   | Fix                                            |
| ----------------------- | ---------------------------------------------- |
| Invalid field type      | Check AWS SDK docs for correct types           |
| Required field missing  | Add field OR use `fieldValidationMode:PRESENT` |
| .sync validation failed | Mock polling API, not initial call             |

**Debug workflow:**

1. Start `fieldValidationMode:NONE` for logic testing
2. Switch to `PRESENT` for partial validation
3. Use `STRICT` in CI/CD

## Test Automation Pattern

```bash
#!/bin/bash
test_state() {
  local state_name=$1
  local input=$2
  local mock=$3
  
  aws stepfunctions test-state \
    --definition "$(cat statemachine.asl.json)" \
    --state-name "$state_name" \
    --input "$input" \
    --mock "$mock" \
    --inspection-level DEBUG
}

# Test chain
RESULT=$(test_state "State1" '{"id":"123"}' '{"result":"..."}' | jq -r '.output')
test_state "State2" "$RESULT" '{"result":"..."}'
```

## Best Practices

1. **Always verify mock structure** against AWS SDK docs for the specific service
2. **For .sync, mock polling API** (DescribeX/GetX), not initial call
3. **Use STRICT validation in CI/CD** to catch mismatches early
4. **Test all error paths** with appropriate error codes
5. **Chain tests** to validate multi-state execution paths
6. **Start with NONE→PRESENT→STRICT** when developing mocks
7. **Use DEBUG for data flow**, TRACE for HTTP debugging
8. **Mock external dependencies** to isolate state machine logic
9. **Test Map failure thresholds** with `mapIterationFailureCount`
10. **Never commit `--reveal-secrets` output** to version control

## Quick Reference

```bash
# Basic test
aws stepfunctions test-state --definition '{...}' --input '{...}' --mock '{...}'

# Test specific state in state machine
aws stepfunctions test-state --definition "$(cat sm.json)" --state-name "MyState" --input '{...}' --mock '{...}'

# Test retry (2nd attempt)
--state-configuration '{"retrierRetryCount":1}' --mock '{"errorOutput":{...}}'

# Test Map failure threshold
--state-configuration '{"mapIterationFailureCount":5}' --mock '{"errorOutput":{...}}'

# Test with context
--context '{"Execution":{"Id":"..."}, "Task":{"Token":"..."}}'

# HTTP Task with secrets
--inspection-level TRACE --reveal-secrets

# Mock validation modes
--mock '{"fieldValidationMode":"STRICT|PRESENT|NONE","result":"..."}'
```

## Step Functions Local (Docker)

Run a local emulator for integration testing. Note it is unsupported and does not have full feature parity with the cloud service:

```bash
docker run -p 8083:8083 amazon/aws-stepfunctions-local

# Run alongside sam local start-lambda for Lambda-integrated tests
sam local start-lambda &
docker run -p 8083:8083 \
  -e LAMBDA_ENDPOINT=http://host.docker.internal:3001 \
  amazon/aws-stepfunctions-local
```

Then use the AWS CLI with `--endpoint-url http://localhost:8083` to create and execute state machines locally.

For most use cases, the TestState API (above) is preferred — it tests against real AWS service behavior without requiring Docker or a local emulator.
