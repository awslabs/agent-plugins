---
name: use-case-specification
description: Creates a reusable use case specification file that defines the business problem, stakeholders, and measurable success criteria for model customization, as recommended by the AWS Responsible AI Lens. Use as the default first step in any model customization plan. Skip only if the user explicitly declines or already has a use case specification to reuse. Captures problem statement, primary users, and LLM-as-a-Judge success tenets.
metadata:
  version: "1.0.0"
---

# Use Case Specification

Multi-turn conversation to gather use case details and produce a use case specification document.

## Principles

1. **One thing at a time.** Each response advances exactly one decision or collects one piece of information.
2. **Confirm before proceeding.** Wait for the user to approve the spec before considering this skill complete.
3. **Infer, don't interrogate.** Use what's already known from the conversation. Only ask when you truly can't infer.
4. **Do NOT ask about base model selection.** Model selection is handled exclusively by the finetuning-setup skill.

## Workflow

### Step 0: Check for Existing Spec

Before starting discovery, check if a `*_use_case_spec.md` file already exists in the project. If it does, present it to the user and ask whether they want to reuse it, modify it, or start fresh.

### Phase 1: Discovery (1–3 turns)

Review what is already known from the conversation so far, then identify what is still missing. You need these three things:

- **What** is the problem the user is trying to solve with model customization
- **Who** will use the finetuned model and in what context
- **Which** success criteria can be used to evaluate how well the custom model performs compared to the base model on a test set. Success criteria must be measurable by an LLM-as-a-Judge (e.g., response accuracy, tone adherence) — not things like latency or throughput.

**Guidelines**:

- Infer as much as possible from what the user has already said
- If the user gave examples, use them to fill gaps rather than asking again
- Only ask clarifying questions when you cannot infer the information needed for Phase 2
- If everything is already clear, say "You've given me a clear picture. I'll put together a use case specification now." and move to Phase 2.

⏸ Wait for user after each clarifying question.

### Phase 2: Producing a Use Case Specification Document

1. Save all generated artifacts under the project directory structure defined by the directory-management skill, if available.
2. Synthesize the information you collected from the user into a Markdown document called [relevant_title]_use_case_spec.md containing the following fields (and only these fields):

```
Use case description
  - Concise problem statement + what the custom model will do
  - Field name: “Business Problem”
  - Type: String

Key stakeholders
  - Who uses the model and in what context
  - Field name: “Primary Users”
  - Type: String, comma separated if there are multiple 

Success criteria
  - A list of 3 criteria (a short name and a description) with which the user measure the success of the custom model. 
  - Field name: “Success Tenets”
  - Type: list of name-description pairs
```

1. Present the use case specification in a human-readable format as follows:

I have put together a use case specification and saved it in [relevant_title]_use_case_spec.md.

A use case specification is a design principle recommended by the [AWS Responsible AI Lens](https://docs.aws.amazon.com/wellarchitected/latest/responsible-ai-lens/design-principles.html).

[use case in human-readable format]

Does this match your intent?

⏸ Wait for user approval.

## use_case_specification Edit Protocol

- If the user requests changes pertaining to any information covered by use_case_spec.md, you must edit it accordingly and ask for confirmation again.
- The user can edit use_case_spec.md directly if they want to. If the user says they've updated the file directly, read it to get the latest in your context.
