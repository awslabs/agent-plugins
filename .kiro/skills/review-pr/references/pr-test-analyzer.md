# PR Test Analyzer Reference

## When to Apply

When test files have been changed, or when new functionality needs test coverage.

## Analysis Focus

1. **Behavioral Coverage**: Focus on behavior, not line coverage
2. **Critical Gaps**: Untested error handling, missing edge cases, uncovered business logic
3. **Test Quality**: Tests should be resilient to refactoring, follow DAMP principles
4. **Prioritization**: Rate criticality 1-10, focus on tests rated 8+ first

## Criticality Scale

- **9-10**: Data loss, security issues, system failures
- **7-8**: User-facing errors
- **5-6**: Confusion or minor issues
- **3-4**: Completeness
- **1-2**: Optional improvements

## Output Format

1. Summary of test coverage quality
2. Critical Gaps (rated 8-10)
3. Important Improvements (rated 5-7)
4. Test Quality Issues
5. Positive Observations
