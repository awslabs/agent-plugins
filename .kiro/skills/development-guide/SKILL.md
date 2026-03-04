---
name: development-guide
description: Development environment setup, build commands, and contribution workflow for the agent-plugins repository. Use when setting up the project, running builds, preparing contributions, or troubleshooting the development environment. Triggers on "how to build", "setup development", "run tests", "contribution workflow", or "development guide".
---

# Development Guide

For the full development guide, read `docs/DEVELOPMENT_GUIDE.md` in the repository root.

## Prerequisites

- [Mise](https://mise.jdx.dev/) >= 2026.2.4

## Quick Setup

```bash
cd agent-plugins
mise install          # Install all tools
mise run build        # Full build: lint + fmt:check + security
```

## Build Commands

```bash
mise run fmt          # Format with dprint
mise run fmt:check    # Check formatting (CI)
mise run lint         # All linters (markdown, manifests, cross-refs)
mise run security     # All security scans (Bandit, SemGrep, Gitleaks, Checkov, Grype)
mise run build        # Complete build
```

## Contribution Workflow

1. Fork the repository
2. Clone and `cd agent-plugins`
3. `mise install` to set up tools
4. Make changes
5. `mise run build` before committing
6. Create PR back to `main`

## Security Scanning

Gitleaks false positives: regenerate baseline with `gitleaks git --config=.gitleaks.toml --report-format=json . > .gitleaks-baseline.json` and commit the updated file.
