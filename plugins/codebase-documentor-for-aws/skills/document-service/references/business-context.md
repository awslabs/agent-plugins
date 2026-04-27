# Business Context Section Template

Structure for the **Business Context** section at the end of `CODEBASE_ANALYSIS.md`. Include only when sufficient business context is available from code, existing docs, or user input.

## When to Include

Include the Business Context section when:

- Existing README or docs contain business context
- User provides business context during the gather step
- Code clearly reveals business domain (e.g., e-commerce order flow, payment processing)

Skip the Business Context section when:

- Code is purely infrastructure or utility
- No business context is available from any source
- Including would require substantial speculation

## Document Structure

The Business Context section is appended at the end of `CODEBASE_ANALYSIS.md`, so it begins at `##` (H2) to sit under the document's top-level `#` heading:

```markdown
## Business Context

### Service Overview

[One paragraph: what the service does in business terms,
who uses it, and why it exists.]

> Sources:
>
> - `file:line` — [what this source reveals]

### Business Capabilities

| Capability   | Description                     | Source      |
| ------------ | ------------------------------- | ----------- |
| [capability] | [what it does for the business] | `file:line` |

### Data Flows

#### [Flow Name]

1. [Step 1] — `source:line`
2. [Step 2] — `source:line`
3. [Step 3] — `source:line`

[Describe the key business processes and how data moves
through the system.]

### Dependencies

#### Upstream (services this depends on)

| Service | Purpose            | Source      |
| ------- | ------------------ | ----------- |
| [name]  | [what it provides] | `file:line` |

#### Downstream (services that depend on this)

| Service | Purpose            | Source      |
| ------- | ------------------ | ----------- |
| [name]  | [what it consumes] | `file:line` |

### SLAs and Constraints

[Performance requirements, availability targets, rate limits —
only if documented in code or configuration.]

| Constraint   | Value   | Source      |
| ------------ | ------- | ----------- |
| [constraint] | [value] | `file:line` |
```

## Section Guidelines

- **Service Overview**: Derive from README, code comments, API names, domain objects. Keep to one paragraph.
- **Business Capabilities**: Map code functionality to business terms. E.g., `processOrder()` → "Order processing".
- **Data Flows**: Trace key business processes through the code. Cite each step.
- **Dependencies**: Identify from API calls, SDK clients, queue consumers/producers, database connections.
- **SLAs and Constraints**: Only include if found in code (timeout configs, rate limit settings, health check thresholds). Mark missing SLAs as `[UNKNOWN]`.
