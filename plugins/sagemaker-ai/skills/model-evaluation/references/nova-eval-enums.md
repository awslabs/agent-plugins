# Nova Forge SDK — Evaluation Enums

Exact enum values for use in generated evaluation code.

## EvaluationTask Enum

| Enum Value                          | Description                                                            | Use with                    |
| ----------------------------------- | ---------------------------------------------------------------------- | --------------------------- |
| `EvaluationTask.MMLU`               | Massive Multitask Language Understanding                               | Built-in benchmark          |
| `EvaluationTask.MMLU_PRO`           | MMLU Pro (harder variant)                                              | Built-in benchmark          |
| `EvaluationTask.BBH`                | BIG-Bench Hard                                                         | Built-in benchmark          |
| `EvaluationTask.GPQA`               | Graduate-level Physics QA                                              | Built-in benchmark          |
| `EvaluationTask.MATH`               | Mathematical Problem Solving                                           | Built-in benchmark          |
| `EvaluationTask.STRONG_REJECT`      | Safety/refusal evaluation                                              | Built-in benchmark          |
| `EvaluationTask.IFEVAL`             | Instruction Following Evaluation                                       | Built-in benchmark          |
| `EvaluationTask.MMMU`               | Multimodal Understanding                                               | Built-in benchmark          |
| `EvaluationTask.GEN_QA`             | Generative Question Answering                                          | BYOD, Custom Scorer         |
| `EvaluationTask.LLM_JUDGE`          | Pairwise comparison — uses LLM judge recipe for Nova 1.0 models        | Nova Micro, Lite, Pro (1.0) |
| `EvaluationTask.RUBRIC_LLM_JUDGE`   | Pairwise comparison — uses rubric LLM judge recipe for Nova 2.0 models | Nova Lite 2 (2.0)           |
| `EvaluationTask.RFT_EVAL`           | RFT singleturn evaluation                                              | RFT Eval                    |
| `EvaluationTask.RFT_MULTITURN_EVAL` | RFT Multiturn evaluation                                               | RFT Multiturn               |
