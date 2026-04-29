---
name: document-service
description: "This skill should be used when the user asks to \"analyze this codebase\", \"document this service\", \"generate technical docs\", \"I inherited this code\", \"help me understand this system\", \"create docs for this project\", \"what does this system look like\", \"onboard me to this codebase\", \"this codebase has no docs\", \"visualize the architecture from code\", or any explicit request to produce structured documentation or architecture diagrams from an existing codebase. Specifically optimized for AWS workloads (CDK, CloudFormation, Terraform) with source-of-truth citations. Do NOT activate for code reviews, single-function explanations, generating new code, or general coding tasks."
license: Apache-2.0
---

# Document Service

Analyze codebases to produce structured technical documentation and architecture diagrams with source-of-truth citations. Every finding links back to the exact file and line it was derived from. Optimized for AWS workloads but works with any codebase.

## Core Principles

- **Explain WHY, not just WHAT.** The reader inherited this codebase and has zero context. Listing components is not enough — explain why the architecture is shaped this way. Search for code comments, TODOs, and commit messages that reveal design rationale. When no rationale exists, mark it `[RATIONALE UNKNOWN]`.
- **Trace end-to-end flows.** For every API endpoint or message handler, trace the complete request path from entry to response. Note every intermediate step, transformation, timeout, and failure point. This is the "if it breaks at 3am, where do I look?" analysis.
- **Deep-dive complex logic.** Identify the most complex or domain-specific code paths (ML pipelines, business rule engines, state machines, custom algorithms). Document HOW they work at the implementation level — the algorithm, key parameters, edge cases, and where production bugs will occur. Surface-level summaries of complex code provide no value over a naive AI prompt.
- **Surface implicit knowledge.** Look for hardcoded values, magic numbers, environment-dependent behavior, and undocumented assumptions. These are the tribal knowledge items that disappear when teams leave.
- **Every claim must be traceable.** Include `file:line` citations for every finding. See [citation-format.md](references/citation-format.md). Verify citations precisely — re-read the cited file and confirm the line number is within ±3 lines. Anchor with function/variable names.
- **Code is the source of truth.** Document what actually exists in code, not what READMEs or wikis claim. Flag every discrepancy between documentation and reality.
- **Mark unknowns and risks explicitly.** Use `[UNKNOWN]` for items not inferable from code, `[RISK]` for unhandled failure modes, `[INFERRED]` for educated guesses, `[RATIONALE UNKNOWN]` for unexplained architecture choices. Omitting markers undermines trust.
- **Verify quantitative claims.** List directory entries programmatically and use exact counts.

## Workflow

The workflow runs autonomously from Step 2 onward. Step 1 is the only interactive step.

### Step 1: Gather Context

Gather from the user:

- Target directory or service to analyze
- Any existing documentation, design docs, or business context (accept "nothing" — this skill is designed for undocumented codebases)

If existing docs are provided, read them first to establish baseline context. If the target directory and context are already known (e.g., provided via automation or a pre-configured prompt), skip the interactive step and proceed directly to Step 2.

Check whether `CODEBASE_ANALYSIS.md` already exists at the output path. If so, ask the user: "Overwrite or write to a different filename?" Resolve this before proceeding — the rest of the workflow runs autonomously.

### Step 2: Build File Tree and Detect Project Type

1. List all files recursively in the target directory
2. Apply exclusion patterns from [exclusion-patterns.md](references/exclusion-patterns.md). Also respect `.gitignore`.
3. Detect project type and framework from characteristic files. See [discovery-patterns.md](references/discovery-patterns.md).
4. Identify entry points based on detected project type. See [discovery-patterns.md](references/discovery-patterns.md).
5. Read the README, CLAUDE.md, or AGENTS.md if present — these contain project context.
6. Check git branch names (`git branch -a`) for strategic context (e.g., a `dev/rust` branch signals a language migration in progress). Note active branches in the Architecture Overview.

### Step 3: Generate Documentation Outline

Produce a hierarchical outline mapping each documentation section to specific source files:

```markdown
## Documentation Outline

1. Architecture Overview → [entry points, IaC stack files] — explain WHY, not just WHAT
2. [Module A: detected name] → [source files for module A]
3. [Module B: detected name] → [source files for module B]
4. Shared Utilities → [shared/common source files]
5. Request Lifecycle → [trace end-to-end flows through the system]
6. Domain Logic Deep-Dive → [core services at implementation level: algorithms, parameters, edge cases]
7. Startup and Initialization → [boot sequence, model loading, cache warmup, dependency checks]
8. API Contracts → [route definitions, OpenAPI specs]
9. Data Models → [schema files, ORM models]
10. Deployment → [IaC files, Dockerfiles]
11. Configuration → [config files, .env.example, prompt templates, YAML configs, secrets refs]
12. Monitoring and Observability → [log groups, metrics, tracing, alarms, dashboards]
13. Security → [auth, encryption, IAM, network isolation]
14. Local Development → [how to run/test locally, CPU fallback, dev environment setup]
15. Discrepancies → (cross-reference README/metadata vs actual code)
16. Failure Modes → (cross-cutting — include detection + recovery)
17. Timeout and Dependency Chain → (map cascading timeouts across layers)
```

Follow the section structure in [technical-doc-template.md](references/technical-doc-template.md) but adapt to the actual codebase — add sections for significant modules, skip sections that don't apply. Aim for balance: each section should map to a meaningful subset of files. If a module maps to more than ~30 files, consider splitting it into sub-sections.

**Do NOT pause for user review.** Proceed immediately to analysis.

### Step 4: Analyze

Two core analysis paths:

#### Path A: Application Code

For each outline section, read mapped source files and extract:

1. API and service definitions — route handlers, controllers, gRPC services, GraphQL resolvers
2. Data model definitions — database schemas, ORM models, type definitions
3. Internal dependencies — imports between modules, shared utilities, event handlers
4. External integrations — SDK clients, HTTP calls, queue producers/consumers
5. Configuration — environment variables, feature flags, secrets references

Consult [framework-patterns.md](references/framework-patterns.md) for framework-specific extraction patterns.

#### Path B: Infrastructure-as-Code

When IaC files are detected (CDK, CloudFormation, Terraform, Serverless Framework):

1. Parse resource definitions. Identify AWS resource types, relationships, and networking topology.
2. Map infrastructure to application components that use them.
3. Extract networking topology — VPCs, subnets, security groups.
4. Consult MCP servers — use `awsiac` to confirm resource interpretations, `awsknowledge` for service descriptions.

When no IaC is found, infer infrastructure from application code (SDK clients, connection strings, environment variables) and mark components as `[INFERRED]`.

**Note on CDK projects:** In CDK codebases, the IaC IS application code (TypeScript/Python constructs). Process CDK files in a single pass covering both Path A and Path B rather than treating them as separate analyses. Extract both the resource definitions (Path B) and the application logic interleaved with them (Lambda bundling, environment wiring, IAM grants — Path A) simultaneously.

#### Writing Sections

For each outline section:

1. Re-read mapped source files for exact line numbers — do not rely on memory from earlier steps.
2. Use grep for patterns — route definitions, model declarations, error handlers.
3. Write content with inline citations. See [citation-format.md](references/citation-format.md).
4. **Document every source file.** Enumerate ALL non-generated source files. Every file should appear somewhere in the documentation — in a module table, component table, or at minimum a file inventory. Files that define symbols never imported by any execution path should be flagged as `[UNUSED]` potential dead code.
5. **Analyze the test suite.** Document what tests verify, what coverage gaps exist, and how to interpret test failures. Tests reveal expected behavior and edge cases.

Process cross-cutting sections (Failure Modes, Configuration, Security, Discrepancies) last, drawing on accumulated knowledge.

**Discrepancy detection**: After analyzing the codebase, re-read the README, CLAUDE.md, package.json description, and any project metadata. Flag every claim that does not match the actual code — features referenced but not implemented, resource types that differ, architecture components that don't exist. For legacy codebases, this "trust but verify" pass is the single most valuable output.

**Actionable failure modes**: For each failure mode, include the detection method (CloudWatch metric, log pattern, symptom) and recovery steps (actual commands), not just a description. The reader is an on-call engineer at 3am.

#### Deep Analysis Approach

Do not attempt a single-pass skim. For each module or service, use iterative deepening:

1. **First pass** — scan file structure and entry points to understand scope
2. **Second pass** — read core files, identify questions (what calls this? where is this configured? what happens on error?)
3. **Third pass** — search for answers to those questions across the codebase, trace cross-module dependencies
4. **Write** — only write the section after all three passes. Re-read cited files to verify exact line numbers.

#### Large Codebase Strategy

For codebases with multiple top-level modules, deep nesting, or hundreds of source files:

- **Primary: tracked sequential analysis.** Create a `.codebase-documentor-progress.md` task board to track progress through sections, enabling resumability if interrupted. This works on all platforms (Claude Code, Cursor, Codex, or any coding assistant).
- **Acceleration: parallel workers.** If the environment supports spawning parallel agents, assign outline sections to independent workers. Each worker reads its mapped files and produces section content with citations. Keep Architecture Overview and cross-cutting sections in the main session for assembly.

See [recursive-analysis.md](references/recursive-analysis.md) for detailed instructions on both approaches.

### Step 5: Generate Diagrams

Two types of diagrams serve different purposes:

**Sequence/flow diagrams — inline Mermaid.** For request lifecycle traces and data pipeline flows identified in Step 4, generate Mermaid `sequenceDiagram` or `flowchart` blocks inline in the relevant CODEBASE_ANALYSIS.md sections. Mermaid is the community standard for simple flow diagrams and renders natively on GitHub. Keep these focused — one diagram per major request path or data flow.

**Architecture diagram — always attempt the `aws-architecture-diagram` skill first.** For the system-level architecture diagram (services, infrastructure, boundaries): invoke the `aws-architecture-diagram` skill (part of the `deploy-on-aws` plugin) with "analyze [target-directory]" to trigger Mode A. It produces a validated draw.io diagram (`docs/*.drawio`) with official AWS4 icons and professional styling. **Only if** the skill is genuinely unavailable (not installed, invocation fails), fall back to a Mermaid `flowchart TD` architecture overview directly in the Architecture Overview section. Include all major services, data stores, external dependencies, and infrastructure boundaries (VPC/subnets as subgraphs when IaC is present).

After diagram generation, try to export to PNG for embedding in the report. Run `drawio -x -f png -b 10 -o docs/<name>.drawio.png docs/<name>.drawio`. If `drawio` is not on PATH, skip the PNG export — the report will link to the `.drawio` file directly instead of embedding an image.

Cross-reference the diagram against the Architecture Overview text. Update documentation or diagram if they diverge.

### Step 6: Assemble and Deliver

1. Assemble all sections into `CODEBASE_ANALYSIS.md` following [technical-doc-template.md](references/technical-doc-template.md)
2. Embed the architecture diagram as an image with a link to the editable source:

   ```markdown
   ![Architecture](./docs/<name>.drawio.png)

   > Editable source: [`docs/<name>.drawio`](./docs/<name>.drawio)
   ```

   If PNG export was not possible, link to the `.drawio` file directly. Mermaid flow diagrams go inline in relevant sections.
3. When the codebase reveals clear business capabilities (API contracts, domain models, data flows, SLA configs), include a **Business Context** section at the end of `CODEBASE_ANALYSIS.md` following [business-context.md](references/business-context.md). Skip only for pure libraries or infrastructure-only code. Do NOT include speculative content — but a README describing the product IS sufficient business context.
4. Tag items not inferable from code with `[UNKNOWN]`
5. Write `CODEBASE_ANALYSIS.md` to the target directory
6. Remove `.codebase-documentor-progress.md` if it was created during analysis
7. Present summary: components documented, APIs found, unknowns tagged, citations included

## Output Files

| File                   | Purpose                                                                        |
| ---------------------- | ------------------------------------------------------------------------------ |
| `CODEBASE_ANALYSIS.md` | Single output — technical docs, business context, citations, and flow diagrams |
| `docs/*.drawio`        | Architecture diagram source (editable in draw.io)                              |
| `docs/*.drawio.png`    | Architecture diagram image (embedded in report, if CLI export available)       |

## Defaults

| Setting              | Default                                                                  | Override        |
| -------------------- | ------------------------------------------------------------------------ | --------------- |
| Primary output       | CODEBASE_ANALYSIS.md                                                     | -               |
| Flow diagrams        | Mermaid inline (sequenceDiagram / flowchart)                             | "skip diagrams" |
| Architecture diagram | draw.io via aws-architecture-diagram skill (Mermaid fallback if missing) | "skip diagrams" |
| IaC reading          | Read-only (never modify)                                                 | -               |
| AWS enrichment       | Enabled when AWS services detected                                       | "skip AWS"      |
| Scope                | User-specified directory                                                 | -               |

## Error Handling

See [error-scenarios.md](references/error-scenarios.md) for handling of empty directories, missing entry points, missing IaC, existing output files, and MCP server failures.

## MCP Servers

### awsknowledge

Consult when AWS services are detected. Use for enrichment (adding official service descriptions and documentation links to CODEBASE_ANALYSIS.md) and validation (confirming the analysis interpretation is correct). When the codebase is self-explanatory, validation is more valuable than enrichment — do not add MCP content just because the server is available.

Example queries: search for "Amazon ECS on EC2 GPU instances" to confirm GPU support patterns, or read the official service page for an unfamiliar AWS service to get a one-line description.

### awsiac

Consult when CDK or CloudFormation files are detected. Use primarily for validation — confirm that the interpretation of a construct or resource type matches its actual behavior. Particularly useful for complex constructs with non-obvious defaults.

Example queries: confirm properties of `ecs.FargateService` vs `ecs.Ec2Service` or verify CloudFormation resource relationships. Terraform files are still analyzed by the skill itself (see [discovery-patterns.md](references/discovery-patterns.md) IaC Detection), just without this MCP server's schema validation.

## References

- [Output template](references/technical-doc-template.md) — CODEBASE_ANALYSIS.md section structure
- [Business context](references/business-context.md) — Business Context section guidance (when to include, what to cover)
- [Citation format](references/citation-format.md) — Clickable citation rules and anchoring
- [Error scenarios](references/error-scenarios.md) — Handling common failure conditions
- [Exclusion patterns](references/exclusion-patterns.md) — Files and directories to skip during scanning
- [Project detection](references/discovery-patterns.md) — Project type detection and entry point identification
- [Code extraction](references/framework-patterns.md) — Framework-specific data extraction patterns
- [Large codebase strategy](references/recursive-analysis.md) — Tracked sequential analysis and parallel workers
