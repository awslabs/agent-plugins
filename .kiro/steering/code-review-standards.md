---
inclusion: auto
name: code-review-standards
description: Code review standards and confidence scoring methodology. Use when performing code reviews, reviewing pull requests, or evaluating code changes.
---

# Code Review Standards

## Confidence Scoring

When reviewing code, rate each issue on a scale from 0-100:

- **0**: Not confident at all. False positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25**: Somewhat confident. Might be a real issue, but may also be a false positive. If stylistic, not explicitly called out in project guidelines.
- **50**: Moderately confident. Verified as a real issue, but might be a nitpick or not happen very often in practice.
- **75**: Highly confident. Double-checked and verified as very likely a real issue that will be hit in practice. The existing approach is insufficient.
- **100**: Absolutely certain. Confirmed as definitely a real issue that will happen frequently in practice.

**Only report issues with a score of 80 or higher.**

## False Positives to Filter

- Pre-existing issues not introduced in the PR
- Something that looks like a bug but is not actually a bug
- Pedantic nitpicks that a senior engineer wouldn't call out
- Issues that a linter, typechecker, or compiler would catch
- General code quality issues unless explicitly required in project guidelines
- Issues called out in guidelines but explicitly silenced in code (e.g., lint ignore comments)
- Changes in functionality that are likely intentional or directly related to the broader change
- Real issues on lines that the user did not modify in their pull request

## Review Output Format

When posting review results, follow this format:

```markdown
### Code review

Found N issues:

1. <brief description of issue> (guideline says "<...>")

<link to file and line with full SHA + line range>

2. <brief description of issue> (bug due to <explanation>)

<link to file and line with full SHA + line range>
```

If no issues found:

```markdown
### Code review

No issues found. Checked for bugs and project guideline compliance.
```

## Link Format

When linking to code, use this exact format:

```
https://github.com/OWNER/REPO/blob/FULL_SHA/path/file.ext#L[start]-L[end]
```

- Must use full git SHA (not abbreviated)
- Must use `#L` notation with line range
- Provide at least 1 line of context before and after
