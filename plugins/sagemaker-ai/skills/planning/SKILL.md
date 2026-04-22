---
name: planning
description: Discovers user intent and generates a structured, step-by-step plan for SageMaker AI model customization workflows (fine-tuning, data preparation, evaluation, deployment). Activate when the user's request relates to these areas or when the user asks to modify the current plan. Handles intent discovery, plan generation, plan iteration, and mid-execution plan alterations.
metadata:
  version: "1.0.0"
---

# Planning

Implements dynamic planning for flexible user journeys. Instead of forcing a rigid workflow, this skill discovers what the user wants, proposes a plan, and adapts as needed.

---

## Phase 1: Brainstorming

**Goal:** Understand what the user wants to accomplish.

**First message rules:**

- If the user describes a goal, ask one clarifying question at most — then move to Phase 2.
- Do NOT list capabilities, pipeline steps, or menus unprompted.
- Do NOT read files or run tools unless the user asks.

**During brainstorming:**

- The goal of this phase is to determine which skills and tools to use to fulfill the user's intent. Every question you ask should help you decide whether a specific skill or tool belongs in the plan.
- Before asking questions, review the name, description, and details of each skill in your context (do not actually load the full SKILL.md files yet), as well as the available MCP tools. Identify what information you'd need from the user to decide if each skill/tool is relevant.
- Ask only questions whose answers would include or exclude a skill or tool from the plan. Do not ask generic or open-ended questions. Each question should map to a planning and skill-selection decision.
- Do NOT ask the user about base model selection or preferences. Model selection is handled exclusively by the finetuning-setup skill.
- When evaluating whether to include a skill, check if ALL of the skill's responsibilities are satisfied, not just the primary one. If a skill handles multiple decisions (e.g., technique selection AND model selection), include it if any of those decisions remain unresolved.
- Move to Phase 2 as soon as you can determine which skills and tools the plan needs. Don't over-ask — 1 to 3 targeted questions should be sufficient in most cases.

---

## Phase 2: Plan Generation

**Goal:** Propose a structured plan for the user to review.

Generate a plan as a numbered list of tasks. Each task has:

- A short name
- A one-sentence description of what happens
- Which skill handles it (if applicable)

**Format:**

```
Based on what you've described, here's what I propose:

1. ⬜ **[Task Name]** — [What happens]. *(Skill: [skill-name])*
2. ⬜ **[Task Name]** — [What happens]. *(Skill: [skill-name])*
3. ⬜ **[Task Name]** — [What happens]. *(Skill: [skill-name])*

Does this plan look right, or would you like to change anything?
```

**Rules for plan generation:**

- Before presenting a plan, always read `references/skill-routing-constraints.md` and validate the plan against it.
- Draw tasks from the skills available in your context. Use each skill's name and description to determine relevance.
- Only offer capabilities that are covered by an available skill. Do not offer, suggest, or imply the ability to help with tasks that no skill supports. If the user needs something outside the available skills, explain that it is not supported.
- Not every plan needs every skill. Tailor the plan to the user's actual intent.
- If the user already has artifacts (e.g., a trained model), skip the steps that produce them.
- Keep plans short. Only include tasks that are necessary.

When the user approves the plan, write it to `PLAN.md` using the following format. Save the file under the project directory structure defined by the directory-management skill, if available.

```markdown
# Plan

1. ⬜ **[Task Name]** — [Description]. _(Skill: [skill-name])_
2. ⬜ **[Task Name]** — [Description]. _(Skill: [skill-name])_
3. ⬜ **[Task Name]** — [Description]. _(Skill: [skill-name])_
```

**Status indicators:**

- ⬜ Not Started
- 🔄 In Progress
- ✅ Completed

Update `PLAN.md` whenever a task's status changes.

---

## Phase 3: Plan Iteration

**Goal:** Refine the plan until the user approves it.

- If the user suggests changes, regenerate the plan incorporating their feedback.
- If the user approves (e.g., "looks good", "let's go", "yes"), begin execution by handing off to the first task's skill.

---

## Execution

Once the plan is approved:

1. Before starting a task, update its status in `PLAN.md` to 🔄 (In Progress).
2. If the task maps to a skill, load that skill's full SKILL.md before doing any work. Do not attempt the task from general knowledge — always defer to the skill's instructions.
3. Execute the task by following the loaded skill's workflow.
4. When the task completes, update its status in `PLAN.md` to ✅ (Completed), then briefly confirm completion and move to the next task.
5. If the user interrupts with a new request mid-execution:
   - Completed tasks are immutable — DO NOT ever modify completed tasks in the plan. You are allowed to only modify tasks that are in progress or not started.
   - Regenerate the remaining tasks to incorporate the user's new input.
   - Present the updated remainder for approval before continuing.

---

## Plan Completion

When all tasks in the plan are done:

> "We've completed everything in the plan. What would you like to do next?"

This re-enters Phase 1 (Brainstorming) for a new goal. There is no terminal state — the conversation continues as long as the user wants.

---

## References

Always load the corresponding reference plan based on the customer intent to learn about what a typical plan looks like, and then adjust based on customer's needs.

- `references/model-customization-plan.md` — A typical end-to-end model customization/finetuning plan for reference when generating plans.
- `references/skill-routing-constraints.md` — Mandatory inclusion rules, ordering constraints, and skill boundary rules. Always consult when generating or modifying a plan.
