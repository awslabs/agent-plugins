# Finetuning Strategy Data Requirements

**Critical** Nova models have a different set of formats than open weights models. Make sure you refer to the right section based on the user's base model.

## Open Weights Models Data Format by Strategy (Llama, Qwen, GPT-OSS, etc.)

### SFT (Supervised Fine-Tuning)

**Required format:**

```jsonl
{
  "prompt": "",
  "completion": ""
}
```

**What it needs:**

- Input-output pairs
- Single "correct" response per input
- Consistent quality across examples

### DPO (Direct Preference Optimization)

**Required format:**

```jsonl
{
  "prompt": "",
  "chosen": "",
  "rejected": ""
}
```

**What it needs:**

- Input with two responses: preferred (chosen) and dispreferred (rejected)
- Clear preference signal between responses
- Both responses should be plausible but one is better
- Avoiding unintentional length bias

### RLVR (Reinforcement Learning from Verifiable Rewards)

**Required format:**

```jsonl
{
  "data_source": "",
  "prompt": [
    {
      "content": "",
      "role": ""
    }
  ],
  "ability": "",
  "reward_model": {
    "ground_truth": "",
    "style": ""
  }
}
```

**What it needs:**

- user prompt
- Ground truth responses in `reward_model.ground_truth` field (leave empty if user data does not have responses)

**How it works:**

1. Model generates response for input
2. Lambda receives full user prompt + reward model fields
3. Lambda computes reward (uses ground_truth if included in verification logic)
4. Model learns to maximize rewards

## Nova Models Data Format by Strategy

### SFT (Supervised Fine-Tuning)

```jsonl
{
  "schemaVersion": "bedrock-conversation-2024",
  "system": [
    {
      "text": ""
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "text": ""
        }
      ]
    },
    {
      "role": "assistant",
      "content": [
        {
          "text": ""
        }
      ]
    }
  ]
}
```

### DPO (Direct Preference Optimization)

The format is the same as SFT for the first N-1 turns. The final assistant turn uses `candidates` with `preferenceLabel` instead of regular `content`.

```jsonl
{
  "schemaVersion": "bedrock-conversation-2024",
  "system": [
    {
      "text": ""
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "text": ""
        }
      ]
    },
    {
      "role": "assistant",
      "candidates": [
        {
          "content": [
            {
              "text": ""
            }
          ],
          "preferenceLabel": "preferred"
        },
        {
          "content": [
            {
              "text": ""
            }
          ],
          "preferenceLabel": "non-preferred"
        }
      ]
    }
  ]
}
```

### RLVR

```jsonl
{
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Hello!"
    }
  ],
  "reference_answer": {
    "answer": "49"
  }
}
```

## MTRL Data Format

MTRL (Multi-Turn Reinforcement Learning) datasets define the prompts that drive rollouts against your agent environment. The dataset only needs to provide prompts; rewards come from the environment, not the dataset.

### Required column

- A `prompt` column containing string values. The service uses the column literally named `prompt`. If no `prompt` column exists, the first column is treated as the prompt column (per the SageMaker SDK).

### Supported file formats

In order of preference:

1. Parquet (`.parquet`) — preferred
2. JSONL (`.jsonl`)
3. JSON array (`.json`)
4. CSV (`.csv`)

### Format-agnostic prompt content

The service does not parse the prompt string. Whatever you put into the `prompt` column is forwarded verbatim to your agent environment, which is responsible for parsing. For structured or agentic prompts (conversation history, tool configs, environment metadata), JSON-encode the structure into one string per record:

```python
import json

task_data = {"prompt": [...], "env_class": "search", ...}
data = {"prompt": [json.dumps(task_data)]}
```
