# Type Design Analyzer Reference

## When to Apply

When new types have been added or existing types have been modified in the PR.

## Analysis Dimensions (each rated 1-10)

1. **Encapsulation**: Are internals hidden? Can invariants be violated from outside?
2. **Invariant Expression**: How clearly are invariants communicated through structure?
3. **Invariant Usefulness**: Do invariants prevent real bugs and align with requirements?
4. **Invariant Enforcement**: Are invariants checked at construction and mutation?

## Common Anti-patterns

- Anemic domain models with no behavior
- Types exposing mutable internals
- Invariants enforced only through documentation
- Types with too many responsibilities
- Missing validation at construction boundaries
- Types relying on external code to maintain invariants

## Output Per Type

1. Invariants identified
2. Ratings (4 dimensions, each X/10 with justification)
3. Strengths
4. Concerns
5. Recommended improvements
