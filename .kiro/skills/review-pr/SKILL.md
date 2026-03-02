---
name: review-pr
description: Comprehensive PR review using multiple specialized review aspects including code quality, test coverage, error handling, type design, comment accuracy, and code simplification. Use when the user wants a thorough PR review, says "review my PR", "check this PR", or wants to run multiple review aspects at once.
---

# Comprehensive PR Review

Run a comprehensive pull request review using multiple specialized review aspects, each focusing on a different dimension of code quality.

## Review Workflow

### 1. Determine Review Scope

- Check git status to identify changed files
- Check if a PR already exists: `gh pr view`
- Parse any user arguments to see if specific review aspects were requested
- Default: Run all applicable reviews

### 2. Available Review Aspects

| Aspect       | Description                                       | Skill                                                      |
| ------------ | ------------------------------------------------- | ---------------------------------------------------------- |
| **code**     | General code review for project guidelines        | [code-reviewer](../code-reviewer/SKILL.md)                 |
| **simplify** | Simplify code for clarity and maintainability     | [code-simplifier](../code-simplifier/SKILL.md)             |
| **comments** | Analyze code comment accuracy and maintainability | [comment-analyzer](../comment-analyzer/SKILL.md)           |
| **tests**    | Review test coverage quality and completeness     | [pr-test-analyzer](../pr-test-analyzer/SKILL.md)           |
| **errors**   | Check error handling for silent failures          | [silent-failure-hunter](../silent-failure-hunter/SKILL.md) |
| **types**    | Analyze type design and invariants                | [type-design-analyzer](../type-design-analyzer/SKILL.md)   |
| **all**      | Run all applicable reviews (default)              | -                                                          |

### 3. Identify Changed Files

Run `git diff --name-only` to see modified files and determine which reviews apply:

- **Always applicable**: code-reviewer (general quality)
- **If test files changed**: pr-test-analyzer
- **If comments/docs added**: comment-analyzer
- **If error handling changed**: silent-failure-hunter
- **If types added/modified**: type-design-analyzer
- **After passing review**: code-simplifier (polish and refine)

### 4. Execute Reviews

For each applicable review aspect, follow the instructions from the corresponding skill's reference documentation.

Run reviews sequentially by default (easier to understand and act on). If the user requests parallel or "all at once", run them simultaneously.

### 5. Aggregate Results

After all reviews complete, produce a unified summary:

```markdown
# PR Review Summary

## Critical Issues (X found)

- [aspect-name]: Issue description [file:line]

## Important Issues (X found)

- [aspect-name]: Issue description [file:line]

## Suggestions (X found)

- [aspect-name]: Suggestion [file:line]

## Strengths

- What's well-done in this PR

## Recommended Action

1. Fix critical issues first
2. Address important issues
3. Consider suggestions
4. Re-run review after fixes
```

## Usage Examples

**Full review (default):**

```
/review-pr
```

**Specific aspects:**

```
/review-pr tests errors
/review-pr comments
/review-pr simplify
```

## Tips

- Run early, before creating PR, not after
- Focus on changes: reviews analyze git diff by default
- Address critical issues first
- Re-run after fixes to verify resolution
- Use specific reviews when you know the concern

## Reference Documentation

See [references/](references/) for detailed instructions for each review aspect.
