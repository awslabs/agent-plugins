---
name: maintainers-guide
description: Repository reviewer, maintainer, and admin workflows including PR review criteria, merge rules, CI/CD overview, labels, and release process. Use when reviewing PRs, triaging issues, managing releases, or understanding CI workflows. Triggers on "review criteria", "merge rules", "how to merge", "CI workflow", "release process", or "maintainers guide".
---

# Maintainers Guide

## Workflow

### Reviewing a PR

1. Verify CI is green (build, lint, security, CodeQL)
2. Check PR title follows conventional commits format
3. Confirm contributor statement is present in PR body
4. Review design quality (see design-guidelines skill for checklist)
5. Verify version changes follow semver
6. For new plugins: require CODEOWNERS entry, marketplace manifest entry, README table entry, `new-plugin` label

### Merge Rules

- All status checks must pass
- `do-not-merge` label blocks merging
- `HALT_MERGES` repo variable: `0` = allow all, `-1` = block all, `<PR#>` = only that PR

### Labels

- `do-not-merge` — blocks merge (CI-enforced)
- `new-plugin` — PR adds a new plugin
- `backlog` — exempts from stale automation
- `stale` — auto-applied to inactive PRs/issues

For roles, plugin team onboarding, CI/CD details, release process, and stale automation, see references/full-guide.md.
