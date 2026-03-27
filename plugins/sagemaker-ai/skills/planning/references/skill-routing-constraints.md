# Skill Routing Constraints

## Plan Completeness

- Generate the complete plan upfront. The plan presented to the user
  must include all steps needed to reach their goal. Do not generate
  a partial plan with the intent to add steps later.
- Each step must be executed by its designated skill. Do not perform
  a skill's work ad-hoc or inline within another skill.

## Mandatory Inclusion

- use-case-specification: Include by default in every model
  customization plan unless the user explicitly declines or has an
  existing spec.

## Ordering Constraints

- finetuning-setup MUST run before dataset-evaluation and finetuning.
  The base model and technique must be known before data can be
  validated or training can begin. If the user asks to evaluate data
  first, explain that model and technique selection is needed first
  and propose reordering.
- dataset-evaluation should run after finetuning-setup and before
  finetuning, to catch format issues before training.

## Skill Boundaries

- All dataset format changes MUST go through dataset-transformation.
  Do not write inline transformation code in other skills' notebooks.
- All model/technique selection MUST go through finetuning-setup.
  Do not resolve model IDs or select techniques ad-hoc.
