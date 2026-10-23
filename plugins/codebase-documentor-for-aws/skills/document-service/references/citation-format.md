# Source-of-Truth Citation Format

Every finding in generated documentation must cite the source code that produced it.

## Why Citations Matter

- **Verifiability**: Readers can follow any citation to confirm a finding
- **Maintainability**: When cited code changes, stale documentation is identifiable
- **Trust**: Documentation with citations is trusted over unsourced claims

## Citation Format

All citations use **clickable markdown links** so readers can cmd+click (Mac) or ctrl+click to navigate directly to the source code. The link format uses `#L{line}` anchors which work on GitHub and in most editors.

### Inline Citations (for tables)

Use markdown links in table cells:

| Component     | Type   | Purpose                 | Source                                              |
| ------------- | ------ | ----------------------- | --------------------------------------------------- |
| order-queue   | SQS    | Buffers incoming orders | [`lib/order-stack.ts:23`](./lib/order-stack.ts#L23) |
| process-order | Lambda | Processes queued orders | [`lib/order-stack.ts:31`](./lib/order-stack.ts#L31) |

### Block Citations (for narrative sections)

Use `> Sources:` blocks after narrative paragraphs:

```markdown
The service uses an event-driven architecture with SQS queues
triggering Lambda handlers for asynchronous order processing.

> Sources:
>
> - [`lib/order-stack.ts:45-52`](./lib/order-stack.ts#L45) — SQS queue to Lambda event source mapping
> - [`src/handlers/process-order.ts:12-18`](./src/handlers/process-order.ts#L12) — SQS event handler entry point
> - [`src/handlers/charge-payment.ts:8`](./src/handlers/charge-payment.ts#L8) — SNS trigger for payment processing
```

### Line Ranges

Use `file:start-end` for multi-line references. The link anchors to the start line:

- Single line: [`src/app.ts:42`](./src/app.ts#L42)
- Line range: [`src/app.ts:42-58`](./src/app.ts#L42) — link opens at line 42
- Entire file (avoid unless small): [`config/database.yml`](./config/database.yml)

### Anchoring Citations

When citing a specific function, class, or constant, include its name alongside the line number. This makes citations resilient to line shifts when code changes:

- Good: [`src/auto-reply/tokens.ts:4`](./src/auto-reply/tokens.ts#L4) (`SILENT_REPLY_TOKEN`)
- Good: [`src/app.ts:42-58`](./src/app.ts#L42) (`handleRequest()`)
- Weak: `src/auto-reply/tokens.ts:4` (no link, no anchor — brittle and not navigable)

## Citation Rules

1. **Cite every finding** — No claim without a source
2. **Be specific** — Cite exact lines, not entire files
3. **Verify accuracy** — Read the cited lines to confirm they support the finding
4. **Use relative paths** — Paths relative to the analyzed directory root
5. **Annotate citations** — Include a brief description of what the citation shows
6. **Group related citations** — Multiple sources for one finding go in one `> Sources:` block

## Citation Verification Process

REQUIRED: Before including any citation, verify it is accurate:

1. **Read the cited lines** — Confirm the code at the cited location supports the finding
2. **Use exact line numbers** — Do not estimate; read the file and count lines
3. **Mark unverifiable claims** — Mark unverifiable citations `[UNVERIFIED]` with an explanation

## When Citations Cannot Be Provided

Mark findings that are inferred rather than directly cited:

```markdown
The service likely communicates with a payment gateway.
[INFERRED — based on `PaymentService` import at `src/app.ts:3`,
but no direct API call found]
```

Do not present inferences as facts. Clearly distinguish between:

- **Cited findings**: Directly supported by code
- **Inferences**: Logically deduced but not directly visible
- **Unknowns**: Cannot be determined from code
