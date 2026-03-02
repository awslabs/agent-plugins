# Silent Failure Hunter Reference

## When to Apply

When error handling code has been changed, or when catch blocks, fallback logic, or error-related code is present in the diff.

## What to Look For

1. **Empty catch blocks** (absolutely forbidden)
2. **Broad exception catching** that hides unrelated errors
3. **Silent fallbacks** without user awareness
4. **Missing error logging** or insufficient context in logs
5. **Catch blocks that only log and continue** without user feedback
6. **Optional chaining** that silently skips operations
7. **Retry logic** that exhausts attempts silently

## Severity Levels

- **CRITICAL**: Silent failure, broad catch block
- **HIGH**: Poor error message, unjustified fallback
- **MEDIUM**: Missing context, could be more specific

## Output Per Issue

1. Location (file:line)
2. Severity
3. Issue Description
4. Hidden Errors (what unexpected errors could be caught)
5. User Impact
6. Recommendation
7. Example of corrected code
