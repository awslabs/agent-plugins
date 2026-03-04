---
inclusion: auto
name: development-workflow
description: Development workflow, build commands, and contribution boundaries for the agent-plugins repository. Use when writing code, making changes, committing, or running builds.
---

# Development Workflow

## Build System

This project uses [mise](https://mise.jdx.dev) for tool versions and tasks. Always use mise commands.

```bash
mise install              # Install tools (first time)
mise run fmt              # Format with dprint
mise run fmt:check        # Check formatting (CI)
mise run lint:md          # Lint Markdown (incl. SKILL.md)
mise run lint:md:fix      # Lint Markdown with auto-fix
mise run lint:manifests   # Validate JSON manifests
mise run lint:cross-refs  # Validate cross-references between manifests
mise run lint             # All linters
mise run security         # All security scans
mise run build            # Full build: lint + fmt:check + security
```

## Boundaries

- ALWAYS use `git worktree add .tmp/<name>` for new work. NEVER switch branches in the main worktree.
- ALWAYS use mise commands to interact with the codebase. If a command is not available, add it.
- NEVER add new dependencies without asking first.
- ALWAYS run a full build (`mise run build`) when done with a task before committing.
- ALWAYS ask first before modifying existing files in a major way.

## Git Worktree Workflow

```bash
git worktree add .tmp/<short-name> -b <branch-name>   # New work
git worktree add .tmp/<short-name> <branch-name>       # Existing branch
git worktree list                                       # List worktrees
git worktree remove .tmp/<short-name>                   # Clean up after merge
```

All worktrees live under `.tmp/` (already in `.gitignore`).
