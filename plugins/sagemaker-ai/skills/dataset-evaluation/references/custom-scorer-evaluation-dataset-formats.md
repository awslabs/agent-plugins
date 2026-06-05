# Custom Scorer Evaluation Dataset Formats

Dataset format requirements for evaluation datasets used with the Custom Scorer pathway. These are NOT training dataset formats — they are specifically for datasets scored by Prime Math, Prime Code, or a Custom Lambda during model evaluation.

## Format by scorer type

### Prime Math

Evaluates mathematical reasoning by comparing model output to a ground truth answer using symbolic equality.

| Field      | Type   | Required | Description                                                             |
| ---------- | ------ | -------- | ----------------------------------------------------------------------- |
| `query`    | string | yes      | The math problem                                                        |
| `response` | string | yes      | The ground truth answer (concise — just the answer, not an explanation) |

**Example:**

```jsonl
{"query": "What is 15 + 27?", "response": "42"}
{"query": "What is the square root of 81?", "response": "9"}
{"query": "Solve for x: 2x + 6 = 20", "response": "7"}
```

**Notes:**

- The scorer uses sympy for symbolic comparison and extracts answers from `\boxed{}`, text after "is", "=", "answer:", etc.
- `response` should be just the answer value (e.g., "42"), not a full explanation. The scorer compares this against what it extracts from the model's output.

---

### Prime Code

Evaluates code generation by executing the model's output against test cases (stdin → stdout).

| Field      | Type   | Required | Description                                                     |
| ---------- | ------ | -------- | --------------------------------------------------------------- |
| `query`    | string | yes      | The coding problem description                                  |
| `response` | string | yes      | Reference solution code (used for text metrics like ROUGE/BLEU) |
| `metadata` | object | yes      | Test cases: `{"inputs": [...], "outputs": [...]}`               |

**Example:**

```jsonl
{"query": "Write a program that reads an integer and prints its double.", "response": "n = int(input())\nprint(n * 2)", "metadata": {"inputs": ["5", "3", "10"], "outputs": ["10", "6", "20"]}}
```

**Notes:**

- `metadata.inputs` and `metadata.outputs` must be string arrays of equal length.
- The scorer extracts code from `` ```python ``` `` blocks in the model's output, then executes it with each input piped to stdin and compares stdout to the expected output.
- The model must produce code that reads from stdin and prints to stdout.

---

### Custom Lambda

Uses your own Lambda function to score model outputs. The dataset format is the flat genqa format.

| Field      | Type   | Required | Description                                 |
| ---------- | ------ | -------- | ------------------------------------------- |
| `query`    | string | yes      | The prompt/input                            |
| `response` | string | yes      | The ground truth / expected output          |
| `system`   | string | no       | System prompt (passed through to the model) |

**Example:**

```jsonl
{"query": "Redact PII from: John Smith lives at 123 Main St.", "response": "[PERSON: John Smith] lives at [ADDRESS: 123 Main St].", "system": "You are a PII redaction assistant."}
```

**Notes:**

- `response` becomes `reference_answer.text` in the Lambda payload.
- The evaluator parameter must be a registered Hub Content ARN (via `Evaluator.create()`), NOT a raw Lambda ARN.

---

## Lambda payload format

The Lambda receives each sample as:

```json
[{
  "id": "hash",
  "model_response": "model's generated text",
  "query": "the prompt",
  "response": "the gold answer from dataset",
  "reference_answer": { "text": "the gold answer from dataset" },
  "metadata": {},
  "processor_config": {}
}]
```

---

## Common mistakes

| Symptom                              | Cause                                                   | Fix                                                           |
| ------------------------------------ | ------------------------------------------------------- | ------------------------------------------------------------- |
| All scores return 0.0                | `reference_answer` field used instead of `response`     | Use flat `response` field                                     |
| `Invalid HubContentArn format` error | Raw Lambda ARN used instead of registered evaluator ARN | Register via `Evaluator.create()` and use the Hub Content ARN |
| `metadata` not passed to scorer      | `metadata` is a JSON string instead of an object        | Ensure `metadata` is a parsed dict in the JSONL               |
