# Code Reviewer Reference

## When to Apply

Always applicable for any PR review. This is the general-purpose code quality check.

## Review Focus

1. **Project Guidelines Compliance**: Check adherence to explicit project rules in CLAUDE.md, AGENTS.md, or `.kiro/steering/` files
2. **Bug Detection**: Logic errors, null/undefined handling, race conditions, memory leaks, security vulnerabilities, performance problems
3. **Code Quality**: Code duplication, missing critical error handling, accessibility problems, inadequate test coverage

## Confidence Scoring

Rate each issue 0-100. Only report issues with confidence >= 80.

- **0-25**: Likely false positive or pre-existing issue
- **26-50**: Minor nitpick not explicitly in guidelines
- **51-75**: Valid but low-impact
- **76-90**: Important, requires attention
- **91-100**: Critical bug or explicit guideline violation

## Output

Group issues by severity (Critical: 90-100, Important: 80-89). Include file path, line number, specific rule or bug explanation, and concrete fix suggestion.
