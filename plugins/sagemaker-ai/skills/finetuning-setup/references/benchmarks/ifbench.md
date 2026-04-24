# IF-Bench

Precise instruction-following generalization — 58 novel verifiable output constraints.

**Use this for:** Tasks requiring tight control over model output.

**Source:** Artificial Analysis (artificialanalysis.ai), April 2026.
"—" = no data — infer from similar models in the same family, but tell the user you're inferring.

| #  | Model                               | Family      | Score |
| -- | ----------------------------------- | ----------- | ----- |
| 1  | Nova 2.0 Lite (mode: high)          | Amazon Nova | 70.7% |
| 2  | GPT-OSS 120B (mode: high)           | OpenAI      | 69.0% |
| 3  | Nova 2.0 Lite (mode: medium)        | Amazon Nova | 68.5% |
| 4  | GPT-OSS 20B (mode: high)            | OpenAI      | 65.1% |
| 5  | Nova 2.0 Lite (mode: low)           | Amazon Nova | 61.2% |
| 6  | GPT-OSS 120B (mode: low)            | OpenAI      | 58.3% |
| 7  | GPT-OSS 20B (mode: low)             | OpenAI      | 57.8% |
| 8  | Llama 3.3 70B Instruct              | Meta Llama  | 47.1% |
| 9  | Qwen3 14B (mode: reasoning)         | Qwen        | 40.5% |
| 10 | Nova 2.0 Lite (mode: non-reasoning) | Amazon Nova | 40.5% |
| 11 | Llama 4 Scout 17B                   | Meta Llama  | 39.5% |
| 12 | Nova Pro                            | Amazon Nova | 38.1% |
| 13 | Qwen2.5 72B Instruct                | Qwen        | 36.9% |
| 14 | Qwen3 32B (mode: reasoning)         | Qwen        | 36.3% |
| 15 | Nova Lite                           | Amazon Nova | 34.1% |
| 16 | Qwen3 8B (mode: reasoning)          | Qwen        | 33.5% |
| 17 | Qwen3 4B (mode: reasoning)          | Qwen        | 32.5% |
| 18 | Qwen3 32B (mode: non-reasoning)     | Qwen        | 31.5% |
| 19 | Nova Micro                          | Amazon Nova | 29.4% |
| 20 | Llama 3.1 8B Instruct               | Meta Llama  | 28.6% |
| 21 | Qwen3 8B (mode: non-reasoning)      | Qwen        | 28.6% |
| 22 | DeepSeek R1 Distill Llama 70B       | DeepSeek    | 27.6% |
| 23 | Qwen3 1.7B (mode: reasoning)        | Qwen        | 26.9% |
| 24 | Llama 3.2 3B Instruct               | Meta Llama  | 26.2% |
| 25 | Qwen3 14B (mode: non-reasoning)     | Qwen        | 23.9% |
| 26 | Qwen3 0.6B (mode: reasoning)        | Qwen        | 23.3% |
| 27 | DeepSeek R1 Distill Qwen 32B        | DeepSeek    | 22.9% |
| 28 | Llama 3.2 1B Instruct               | Meta Llama  | 22.8% |
| 29 | DeepSeek R1 Distill Qwen 14B        | DeepSeek    | 22.1% |
| 30 | Qwen3 0.6B (mode: non-reasoning)    | Qwen        | 21.9% |
| 31 | Qwen3 1.7B (mode: non-reasoning)    | Qwen        | 21.1% |
| 32 | DeepSeek R1 Distill Llama 8B        | DeepSeek    | 17.6% |
| 33 | DeepSeek R1 Distill Qwen 1.5B       | DeepSeek    | 13.2% |
| —  | Qwen3 4B (mode: non-reasoning)      | Qwen        | —     |
| —  | Qwen2.5 32B Instruct                | Qwen        | —     |
| —  | Qwen2.5 14B Instruct                | Qwen        | —     |
| —  | Qwen2.5 7B Instruct                 | Qwen        | —     |
| —  | DeepSeek R1 Distill Qwen 7B         | DeepSeek    | —     |
