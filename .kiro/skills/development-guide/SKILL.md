---
name: development-guide
description: Development environment setup, build commands, and contribution workflow for the agent-plugins repository. Use when setting up the project, running builds, preparing contributions, or troubleshooting the development environment. Triggers on "how to build", "setup development", "run tests", "contribution workflow", or "development guide".
---

# Development Guide

## Workflow

### Step 1: Environment Setup

- Install [mise](https://mise.jdx.dev/) >= 2026.2.4
- Run `mise install` to install all project tools

### Step 2: Development

- Fork the repo and clone locally
- Use `git worktree add .tmp/<name> -b <branch>` for new work
- Use mise commands for all build interactions

### Step 3: Build and Validate

- `mise run fmt` — format code
- `mise run lint` — all linters
- `mise run security` — security scans
- `mise run build` — full build (required before committing)

### Step 4: Contribute

- PR title must follow conventional commits (`fix:`, `feat:`, `chore:`)
- PR body must include license contribution acknowledgment
- All CI checks must pass

For Claude Code setup, gitleaks handling, and detailed steps, see references/full-guide.md.
