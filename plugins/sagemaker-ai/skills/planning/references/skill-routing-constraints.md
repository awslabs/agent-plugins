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

## Evaluate-First Path

When the user chooses to evaluate the base model before fine-tuning:

- model-selection MUST run before sdk-getting-started and
  dataset-evaluation.
- sdk-getting-started MUST run after model-selection and before
  dataset-evaluation.
- model-selection runs before model-evaluation.
- finetuning-technique is NOT required. It only enters the plan if
  the user decides to fine-tune after the decision gate.

## Direct Fine-Tuning Path

When the user chooses to go straight to fine-tuning:

- model-selection MUST run before sdk-getting-started.
- sdk-getting-started MUST run after model-selection and before
  dataset-evaluation.
- model-selection MUST run before finetuning-technique.
- finetuning-technique MUST run before dataset-evaluation (for
  training data) and finetuning. The technique must be known before
  training data can be validated or training can begin.
- dataset-evaluation should run after finetuning-technique and before
  finetuning, to catch format issues before training.

## Ordering Constraints

- model-selection MUST run before sdk-getting-started.
- sdk-getting-started MUST run after model-selection and before the
  first task that runs scripts or makes AWS API calls requiring an
  execution role (e.g., dataset-evaluation, finetuning,
  model-evaluation, model-deployment). It is not needed before
  conversational-only tasks like use-case-specification or
  model-selection.

## Skill Boundaries

- All dataset format changes MUST go through dataset-transformation.
  Do not write inline transformation code in other skills' notebooks.
- All model selection MUST go through model-selection.
  Do not resolve model IDs ad-hoc.
- All technique selection MUST go through finetuning-technique.
  Do not select techniques ad-hoc.

## Nova-Specific Constraints

- The model family (Nova vs OSS) is determined by model-selection.
  Planning does NOT ask this question — it only notes it if the
  user explicitly states a preference.
- sdk-getting-started MUST run before any Nova training skill if the
  user is new to the Forge SDK (has not installed it yet). Skip if
  the user confirms the SDK is already installed. Since model family
  is determined in model-selection, sdk-getting-started may need to be
  inserted into the plan after model-selection selects Nova.
- Nova and OSS training paths are mutually exclusive within a single
  plan. Do not mix Nova Forge SDK skills with OSS SageMaker SDK
  skills for the same training job.
- RFT Multiturn requires SMHP (HyperPod). If the user wants
  RFT Multiturn, the finetuning skill will handle it via the
  nova-rft-multiturn-setup.md reference — ensure HyperPod setup
  is complete first.
- Both Nova and OSS paths share use-case-specification and
  directory-management — these are model-agnostic.

## Memory Integration

- Load agent-memory silently before the first response (this is an
  internal bootstrapping step, not a user-facing action).
- After model path is determined (by model-selection), load
  model-specific best practices (nova or oss) from agent memory.
- During execution, track progress in local memory.
