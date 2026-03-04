---
name: maintainers-guide
description: Repository reviewer, maintainer, and admin workflows including PR review criteria, merge rules, CI/CD overview, labels, and release process. Use when reviewing PRs, triaging issues, managing releases, or understanding CI workflows. Triggers on "review criteria", "merge rules", "how to merge", "CI workflow", "release process", or "maintainers guide".
---

# Maintainers Guide

For the full maintainers guide, read `docs/MAINTAINERS_GUIDE.md` in the repository root.

## PR Review Criteria

1. CI is green (all required checks pass)
2. PR title follows conventional commits (`fix:`, `feat:`, `chore:`, etc.)
3. Contributor statement present in PR body
4. Design quality per review checklist in `docs/DESIGN_GUIDELINES.md`
5. Versioning follows semver
6. New plugins must include: CODEOWNERS entry, marketplace manifest entry, README table entry, `new-plugin` label
7. No secrets or sensitive data in diff

## Merge Rules

- Passing status checks required
- `do-not-merge` label blocks merging
- `HALT_MERGES` repo variable: `0` = allowed, `-1` = all blocked, `<PR#>` = only that PR

## Labels

| Label          | Purpose                              |
| -------------- | ------------------------------------ |
| `do-not-merge` | Blocks PR from merging (CI-enforced) |
| `new-plugin`   | PR adds a new plugin                 |
| `backlog`      | Exempts from stale automation        |
| `stale`        | Auto-applied to inactive PRs/issues  |

## Stale Automation

- PRs: stale after 14 days, closed 2 days later
- Issues: stale after 60 days, closed 7 days later
- Add `backlog` label to exempt
