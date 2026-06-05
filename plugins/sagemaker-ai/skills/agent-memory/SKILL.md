---
name: agent-memory
description: File-based local memory system that persists session context across conversations. Tracks progress during execution and saves session notes for resumption. Activate at the beginning of any model customization conversation to load prior context, or when the user references prior work ("where did we leave off?", "continue", "resume").
metadata:
  version: "2.0.0"
---

# Agent Memory

Persists session context across conversations using local memory files in the user's workspace.

## Principles

1. **Read before you act.** Always load best practices references at session start before brainstorming.
2. **Never claim no prior context if memory files exist.** The memory files ARE your prior context.
3. **Keep session notes current.** Update local memory as you progress through tasks.

## Workflow

### Step 1: Load Best Practices

Always read `references/common-best-practices.md` at session start.

After the model path is determined (Nova vs OSS):

- Nova → read `references/nova-best-practices.md`
- OSS → read `references/oss-best-practices.md`

### Step 2: Load Prior Context (Conditional)

If the user references prior work ("where did we leave off?", "continue", "resume", or references a project/config not in the current conversation), check for local memory files:

- Read `<project-dir>/agent_memory/session-notes.md` — session history, progress, next steps

The `<project-dir>` is the project directory established by the directory-management skill.

### Step 3: Track Progress During Execution

Write progress to `<project-dir>/agent_memory/session-notes.md` during execution. Create the directory if it doesn't exist.

Track:

- Current task and plan step
- Configurations used (model, technique, instance type, hyperparameters)
- Outcomes (success/failure, job IDs, checkpoint paths)
- Issues encountered and resolutions
- Next steps for the following session

### Step 4: Update on Completion

When a task completes (training finishes, deployment succeeds, evaluation done), update session notes with:

- Final outcome and key results
- Artifact locations (checkpoint paths, endpoint names, result files)
- Recommended next steps

## Local Memory Schema

```
<project-dir>/agent_memory/
└── session-notes.md
```

### session-notes.md format

```markdown
# Session: [YYYY-MM-DD]

## Current Task

[What the user is working on]

## Progress

- ✓ [completed step]
- ⏳ [in-progress step]
- ⬜ [upcoming step]

## Configurations Used

- Model: [name]
- Technique: [type]
- Job name: [name]
- Key settings: [details]

## Artifacts

- Training result: [file path]
- Checkpoint: [S3 path]
- Endpoint: [name, if deployed]

## Issues Encountered

[Any problems and how they were resolved]

## Next Steps

[What to do next session]
```

## Important Notes

- Local memory is git-ignored and private to the current user
- Best practices are read-only skill references — they ship with the plugin
- Create the `agent_memory/` directory on first write if it doesn't exist

## References

- `references/common-best-practices.md` — Cross-model best practices (loaded at session start)
- `references/nova-best-practices.md` — Nova Forge SDK best practices (loaded for Nova path)
- `references/oss-best-practices.md` — OSS model best practices (loaded for OSS path)
