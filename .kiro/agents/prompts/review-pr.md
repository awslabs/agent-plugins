# Comprehensive PR Review

Run a comprehensive pull request review using multiple specialized subagents, each focusing on a different dimension of code quality.

## Review Workflow

### 1. Determine Review Scope

- Check git status to identify changed files
- Check if a PR already exists: `gh pr view`
- Parse any user arguments to see if specific review aspects were requested
- Default: Run all applicable reviews

### 2. Available Review Aspects

| Aspect       | Description                                       | Skill                    |
| ------------ | ------------------------------------------------- | ------------------------ |
| **code**     | General code review for project guidelines        | code-reviewer            |
| **simplify** | Simplify code for clarity and maintainability     | code-simplifier          |
| **comments** | Analyze code comment accuracy and maintainability | comment-analyzer         |
| **tests**    | Review test coverage quality and completeness     | pr-test-analyzer         |
| **errors**   | Check error handling for silent failures          | silent-failure-hunter    |
| **types**    | Analyze type design and invariants                | type-design-analyzer     |
| **all**      | Run all applicable reviews (default)              | -                        |

### 3. Identify Changed Files

Run `git diff --name-only` to see modified files and determine which reviews apply:

- **Always applicable**: code-reviewer (general quality)
- **If test files changed**: pr-test-analyzer
- **If comments/docs added**: comment-analyzer
- **If error handling changed**: silent-failure-hunter
- **If types added/modified**: type-design-analyzer
- **After passing review**: code-simplifier (polish and refine)

### 4. Execute Reviews

For each applicable review aspect, spawn a subagent with the task. Each subagent has access to the corresponding skill via its resources.

Spawn subagents in parallel for efficiency. Each subagent should:

1. Read the changed files relevant to its review aspect
2. Apply the methodology from its skill
3. Apply confidence scoring from the code-review-standards steering file
4. Return findings with file paths and line numbers

Use the `code-review` agent as a subagent for the 5-pass automated code review.

### 5. Aggregate Results

After all subagents complete, produce a unified summary:

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

## Tips

- Run early, before creating PR, not after
- Focus on changes: reviews analyze git diff by default
- Address critical issues first
- Re-run after fixes to verify resolution
- Use specific reviews when you know the concern
