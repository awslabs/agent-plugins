# Large Codebase Strategy

For codebases too large to analyze in a single pass, use parallel decomposition or tracked sequential analysis. "Step 3" below refers to Step 3 ("Generate Documentation Outline") of the main workflow in [SKILL.md](../SKILL.md).

## When to Use

Apply this strategy when **any** of these conditions is true:

- Multiple top-level modules or packages exist (e.g., monorepo with `packages/`, `apps/`, `services/`)
- Deep directory structure (3+ levels of nesting with source files)
- Hundreds of source files after applying exclusion patterns
- The documentation outline from Step 3 (see [SKILL.md](../SKILL.md)) produces 6+ sections mapped to distinct file sets

For single-module codebases with a flat structure, process outline sections directly without this strategy.

## Approach A: Tracked Sequential Analysis (Primary)

The primary approach works on all platforms (Claude Code, Cursor, Codex, or any coding assistant). Create a progress file to track analysis state:

```markdown
# Analysis Progress

| Section                 | Mapped Files                 | Status      | Key Findings |
| ----------------------- | ---------------------------- | ----------- | ------------ |
| Architecture Overview   | lib/*-stack.ts, src/app.ts   | DONE        | Event-driven |
| Order Processing Module | src/order-api/**, handlers/* | IN_PROGRESS | 3 endpoints  |
| Payment Integration     | src/payment/**               | PENDING     | -            |
```

Save as `.codebase-documentor-progress.md` in the target directory. This enables:

- **Resumability** — A new session reads the progress file and continues from the next PENDING section
- **Visibility** — Users can check progress at any time
- **Completeness tracking** — Clear view of what has been analyzed

## Section Analysis Steps

For each outline section (in either approach):

1. **Read mapped source files on-demand** — Re-read for exact line numbers; do not rely on earlier scan memory
2. **Grep for patterns** — Route definitions, model declarations, error handlers. Faster than reading every file.
3. **Record findings with citations** — Every claim needs a verified `file:line` citation
4. **Note cross-module dependencies** — Track which modules depend on which
5. **Mark section complete** — Update progress (agent result or task board)

## Assembly

After all sections are complete:

1. Resolve cross-module dependencies into a coherent Architecture Overview
2. Generate the architecture diagram
3. Assemble final `CODEBASE_ANALYSIS.md` following the template structure
4. Remove the progress file (if created)

## Principles

- **Outline-driven** — The documentation outline determines analysis structure, not the directory layout
- **On-demand reading** — Read source files when writing each section, not in a bulk scan phase
- **Depth-first** — Complete one section fully before starting the next
- **Bottom-up for dependencies** — Analyze shared/utility modules before their consumers when possible
- **Cross-cutting sections last** — Sections like Failure Modes that span modules are analyzed after all module-specific sections

## Approach B: Parallel Workers (Optional Acceleration)

When the environment supports spawning parallel workers (sub-agents, background tasks, or similar):

1. **Assign outline sections to independent workers** — Each section becomes a task for a parallel worker. Each reads only its mapped source files and produces section content with citations.
2. **Keep architecture and cross-cutting sections in the main session** — Architecture Overview, Failure Modes, and Configuration span multiple modules and require accumulated context.
3. **Collect and assemble** — Gather findings from all workers, resolve cross-module dependencies, and assemble into the final CODEBASE_ANALYSIS.md.

This is an acceleration of Approach A — the same section analysis steps apply. The progress file is still useful for tracking which workers have completed.
