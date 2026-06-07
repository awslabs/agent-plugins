# Agent Memory Schema

Local memory files live in the user's workspace under `<project-dir>/agent_memory/`. This directory is created on first write.

## Workspace Memory Structure

```
<project-dir>/agent_memory/
└── session-notes.md                # Current session tracking (git-ignored)
```

## Local Memory Schema

### session-notes.md

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

## Notes

- Local memory is git-ignored and private to the current user
- Create the directory on first write: `mkdir -p <project-dir>/agent_memory/`
- Session notes are overwritten each session (not appended) — keep only the latest state
