# τ²-bench

Multi-turn customer service simulation with dual-control (agent + user modify shared state). Telecom domain.

**Use this for:** Multi-turn tool use with policy following, accurate state management through API calls.

**Source:** Artificial Analysis (artificialanalysis.ai), April 2026.
"—" = no data — infer from similar models in the same family, but tell the user you're inferring.

| #  | Model                               | Family      | Score |
| -- | ----------------------------------- | ----------- | ----- |
| 1  | Nova 2.0 Lite (mode: medium)        | Amazon Nova | 75.7% |
| 2  | Nova 2.0 Lite (mode: high)          | Amazon Nova | 72.8% |
| 3  | Nova 2.0 Lite (mode: low)           | Amazon Nova | 71.9% |
| 4  | GPT-OSS 120B (mode: high)           | OpenAI      | 65.8% |
| 5  | Nova 2.0 Lite (mode: non-reasoning) | Amazon Nova | 62.0% |
| 6  | GPT-OSS 20B (mode: high)            | OpenAI      | 60.2% |
| 7  | GPT-OSS 20B (mode: low)             | OpenAI      | 50.3% |
| 8  | GPT-OSS 120B (mode: low)            | OpenAI      | 45.0% |
| 9  | Qwen3 14B (mode: reasoning)         | Qwen        | 34.5% |
| 10 | Qwen2.5 72B Instruct                | Qwen        | 34.5% |
| 11 | Qwen3 14B (mode: non-reasoning)     | Qwen        | 32.2% |
| 12 | Qwen3 32B (mode: reasoning)         | Qwen        | 29.8% |
| 13 | Qwen3 8B (mode: reasoning)          | Qwen        | 27.8% |
| 14 | Llama 3.3 70B Instruct              | Meta Llama  | 26.6% |
| 15 | Qwen3 1.7B (mode: reasoning)        | Qwen        | 26.0% |
| 16 | Qwen3 8B (mode: non-reasoning)      | Qwen        | 24.9% |
| 17 | DeepSeek R1 Distill Llama 70B       | DeepSeek    | 21.9% |
| 18 | Qwen3 1.7B (mode: non-reasoning)    | Qwen        | 21.6% |
| 19 | Llama 3.2 3B Instruct               | Meta Llama  | 21.1% |
| 20 | Qwen3 0.6B (mode: reasoning)        | Qwen        | 21.1% |
| 21 | Qwen3 4B (mode: reasoning)          | Qwen        | 19.0% |
| 22 | Nova Lite                           | Amazon Nova | 17.5% |
| 23 | Llama 3.1 8B Instruct               | Meta Llama  | 16.4% |
| 24 | Llama 4 Scout 17B                   | Meta Llama  | 15.5% |
| 25 | Qwen3 0.6B (mode: non-reasoning)    | Qwen        | 14.6% |
| 26 | Nova Pro                            | Amazon Nova | 14.0% |
| 27 | Nova Micro                          | Amazon Nova | 14.0% |
| 28 | Llama 3.2 1B Instruct               | Meta Llama  | 0.0%  |
| —  | Qwen3 32B (mode: non-reasoning)     | Qwen        | —     |
| —  | Qwen3 4B (mode: non-reasoning)      | Qwen        | —     |
| —  | Qwen2.5 32B Instruct                | Qwen        | —     |
| —  | DeepSeek R1 Distill Llama 8B        | DeepSeek    | —     |
| —  | DeepSeek R1 Distill Qwen 32B        | DeepSeek    | —     |
| —  | DeepSeek R1 Distill Qwen 14B        | DeepSeek    | —     |
| —  | DeepSeek R1 Distill Qwen 1.5B       | DeepSeek    | —     |
| —  | Qwen2.5 14B Instruct                | Qwen        | —     |
| —  | Qwen2.5 7B Instruct                 | Qwen        | —     |
| —  | DeepSeek R1 Distill Qwen 7B         | DeepSeek    | —     |
