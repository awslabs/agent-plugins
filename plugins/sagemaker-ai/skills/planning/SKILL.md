---
name: planning
description: Discovers user intent and generates a structured, step-by-step plan for model customization workflows. This skill must always be activated alongside any other skill when the user's request relates to model customization — including fine-tuning, training, building, customizing, reviewing data, or getting advice on approach, regardless of domain. Do not skip this skill even if the immediate ask is narrow (e.g., reviewing data format or a single workflow step), because planning discovers the full scope of work needed. Also activate when the user wants to resume, continue, or modify an existing plan.
metadata:
  version: "2.0.0"
---

## Principles

- **One question at a time.** Each question should resolve a branching decision in the plan. Avoid generic or out-of-domain questions.
- **Surface constraints early.** If a user decision would constrain downstream options, flag it before the plan is finalized.
- **Keep plans short.** Only include tasks that are necessary for the user's stated goal.
- **Don't ask what you already know.** Check conversation history and project files before asking the user.

---

## Phase 1: Brainstorming

**Goal:** Understand what the user wants to accomplish and identify which skills belong in the plan.

Read `references/input-output-contracts.md`, `references/model-customization-plan.md`, and `references/evaluate-first-plan.md` to:

- Identify which skills could be relevant to the user's stated goal.
- Check whether the user has the necessary input artifacts for each skill. If not, find the skills that generate those inputs and add them first.
- Order skills to allow a smooth transition from one to the next and avoid dead ends.
- Check if a recommended workflow matches the user's needs. If not, assess what modifications are needed and verify they are possible against the contracts table.
- Decide which skills in a matching workflow can be skipped.
- Surface limitations early — if a user decision (model choice, region, evaluation method) would constrain downstream options, mention it proactively, get user feedback, and adapt the plan accordingly.

**During brainstorming:**

- **Workflow choice gate:** Before generating any plan, determine whether the user wants the evaluate-first workflow or the direct fine-tuning workflow. If the user has explicitly chosen (e.g., "evaluate first", "skip evaluation", "already evaluated the base model"), proceed with their choice. Otherwise, present both options with brief pros/cons and ask the user to choose. Saying "fine-tune" or naming a technique alone is NOT an explicit choice to skip evaluation — the user may not know evaluate-first is an option. Do NOT present a plan until the user has chosen a path. After they choose, read ONLY the corresponding reference plan.
- Use the Restrictions column of the contracts table to flag constraints as soon as the relevant decision is made. Examples (non-comprehensive list, check contracts table for the full picture):
  - User picks a Nova model → alert that deployment regions are limited.
  - User picks a region → alert if it conflicts with model availability.
- If a restriction applies, check whether it requires changes to other steps in the plan.
- Do NOT ask the user about base model selection or preferences. Model selection is handled exclusively by the `model-selection` skill.
- Move to Phase 2 as soon as you can determine which skills and tools the plan needs.

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

- Infer ordering from the Prerequisites column in the contracts table — a skill cannot appear before its prerequisites. If unsure, consult `references/skill-routing-constraints.md`.
- Only offer capabilities covered by an available skill. If the user needs something no skill supports, say so.
- Tailor the plan to the user's actual intent. Not every plan needs every skill.
- If the user already has input artifacts (e.g., a trained model), skip the steps that produce them.

When the user approves the plan, write it to `PLAN.md` and save it under the project directory structure defined by the directory-management skill.

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
- If the user approves, begin execution by handing off to the first task's skill.

---

## Execution

Once the plan is approved:

1. Before starting a task, update its status in `PLAN.md` to 🔄 (In Progress).
2. If the task maps to a skill, load that skill's full SKILL.md before doing any work. Do not attempt the task from general knowledge — always defer to the skill's instructions.
3. Execute the task by following the loaded skill's workflow.
4. When the task completes:
   - Update its status in `PLAN.md` to ✅ (Completed). If the task generated output files (scripts, notebooks, manifests), record the file paths under the completed task:

     ```
     - [x] Fine-tune model
       - Output: `scripts/01_sft_finetuning.py`
       - Output: `manifests/sft-llama-20260515.json`
     ```

   - Briefly confirm completion and move to the next task.
5. If the user interrupts with a new request mid-execution:
   - Completed tasks are immutable — do NOT modify them.
   - Regenerate the remaining tasks to incorporate the user's new input.
   - Present the updated remainder for approval before continuing.

---

## Plan Completion

When all tasks in the plan are done:
Present to the user:

> "We've completed everything in the plan. What would you like to do next?"

This re-enters Phase 1 (Brainstorming) for a new goal. There is no terminal state — the conversation continues as long as the user wants.

---

## References

Load the reference plan that matches the customer's intent, then adjust based on their needs.

- `references/evaluate-first-plan.md` — The evaluate-first workflow: evaluate a base model before deciding whether to fine-tune.
- `references/model-customization-plan.md` — The direct fine-tuning plan. Use when the user has explicitly committed to fine-tuning.
- `references/input-output-contracts.md` - A table showing all skills, required inputs, produced outputs, prerequisites, and constraints.
- `references/skill-routing-constraints.md` — Optional supplemental resource about Mandatory inclusion rules, ordering constraints, and skill boundary rules.
