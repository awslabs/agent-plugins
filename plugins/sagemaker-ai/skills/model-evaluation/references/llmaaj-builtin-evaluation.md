# LLM-as-Judge with Built-in Metrics: Alignment Guide

This file guides you through aligning with the user on built-in metric selection.

## Select Metrics

Read `references/builtin-metrics.md` for the full list of metrics with descriptions and common combinations.

Based on the user's task and data, recommend specific metrics with reasoning:

> "Based on your [task], I recommend these metrics:
>
> - [metric1]: [why it matters for this task]
>
> Does this look good, or do you want to consider other metrics?"

⏸ **Wait for user to confirm.**

Tips:

- Start with the common combinations from the metrics file as a baseline
- Adjust based on what you know about the user's task and data
- If the user pushes back, understand why and adjust — don't just agree
