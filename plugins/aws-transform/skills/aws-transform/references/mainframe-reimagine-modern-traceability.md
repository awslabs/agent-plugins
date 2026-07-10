# Phase 5: Modern Code Traceability

## Table of Contents

- [When to Use](#when-to-use)
- [Prerequisites](#prerequisites)
- [Step 1: Target Stack Discovery](#step-1-target-stack-discovery)
- [Step 2: Inline Tracing During Code Generation](#step-2-inline-tracing-during-code-generation-write-time)
- [Step 3: Generate traceability-modern.yaml](#step-3-generate-traceability-modernyaml)
- [Step 4: Completeness Validation](#step-4-completeness-validation)
- [Key Principles](#key-principles)
- [Example Workflow](#example-workflow)

> **Last Updated:** 2026-06-30

This reference file guides the generation of annotated modern code and traceability artifacts that link functional requirements (from the reimagine pipeline) to their implementing code locations in a modernized codebase. It is the fifth and final phase of the mainframe reimagine pipeline, following Phase 4 (Traceability Verification).

It is language-agnostic and architecture-agnostic — it auto-detects the customer's target stack and adapts accordingly.

## When to Use

- After Phase 4 has completed with a `traceability-dashboard.html`
- User asks to "implement from specs", "forward engineer", "build from requirements", or "generate code"
- User asks to start implementing a specific microservice specification from `outputs/microservices/`

**Key principle:** Traceability annotations are inserted AT WRITE TIME — as code is being generated. This ensures 100% coverage by default.

**Relationship to Phase 4:** Phase 4 (`traceability-dashboard.html`) verifies that all requirements appear in microservice specifications. Phase 5 (`traceability-modern.yaml`) verifies that all requirements appear in the actual generated source code. They are separate artifacts at different levels of the chain:

```
Legacy COBOL rules (traceability.yaml)
    → Requirements (requirements.md)
        → Microservice Specs (*-specification.md)     ← Phase 4 verifies this link
            → Modern Source Code (*.java, *.cs, etc.) ← Phase 5 verifies this link
```

The REQ-* ID is the join key across all levels. A compliance reviewer can trace any `@TracesRequirement("REQ-F-044")` annotation in modern code back through the spec → `requirements.md` → `traceability.yaml` → original COBOL rule.

## Prerequisites

- Phase 1–4 of the reimagine pipeline completed
- `outputs/microservices/*-specification.md` files exist (Phase 3 output)
- `traceability-dashboard.html` exists (Phase 4 output)
- `spec/<FunctionName>/requirements.md` and `spec/<FunctionName>/traceability.yaml` present for all business functions
- The target modern source code project is set up (or will be created during generation)

---

## Step 1: Target Stack Discovery

Before generating any code, determine the customer's target environment. The detection order is:

1. **Customer reference files** — check for target language, framework, project structure, and naming conventions in any provided steering or configuration docs. These are the authoritative source.
1. **Build/project files** — if no reference files specify the stack, inspect the workspace:

| Indicator File                          | Language   | Framework Hints                 |
| --------------------------------------- | ---------- | ------------------------------- |
| `pom.xml`, `build.gradle`, `*.java`     | Java       | Spring Boot, Quarkus, Micronaut |
| `*.csproj`, `*.sln`, `*.cs`             | C#         | .NET, ASP.NET Core              |
| `package.json`, `tsconfig.json`, `*.ts` | TypeScript | Node.js, NestJS, Express        |
| `package.json`, `*.js`                  | JavaScript | Node.js, Express                |
| `pyproject.toml`, `setup.py`, `*.py`    | Python     | FastAPI, Django, Flask          |
| `go.mod`, `*.go`                        | Go         | Standard library, Gin, Echo     |
| `Cargo.toml`, `*.rs`                    | Rust       | Actix, Axum, Tokio              |

1. **Ask the user** — if neither provides clarity, ask: "I couldn't determine your target language from project structure. What language/framework are you targeting?"

---

## Step 2: Inline Tracing During Code Generation (Write-Time)

**This is the primary traceability mechanism.** When generating modern code from a microservice specification, traceability annotations MUST be inserted as the code is being written.

### Pre-Generation: Load the Requirement Checklist

Before writing any code for a service, extract every `REQ-*` identifier from the service's specification file in `outputs/microservices/<service-name>-specification.md`. These IDs were distributed to each service during Phase 3 (specgen) and appear throughout sections 1–8 of the spec.

The agent MUST:

1. **Build a tracking list** of all REQ-* IDs from the specification — this is the punch list for this service
2. **Keep this list in working memory** throughout code generation, marking each REQ-* as "traced" when a corresponding annotation is written

Each specification's header shows which business functions it covers, for example:

```
> **Source Functions**: BatchDataProcessing-AccountProcessing, OnlineTransactionProcessing-AccountManagement
```

This determines which `spec/<FunctionName>/traceability.yaml` files contain the legacy rule hashes that back-fill the `legacy_rule_ids` field in `traceability-modern.yaml`.

**This list is the source of truth.** Code generation is not complete for a service until every REQ-* on the list has been annotated in at least one code location.

### Write-Time Rules

When writing any method, function, or handler that implements a requirement:

1. **Before writing the code element**, determine which REQ-* ID(s) it satisfies
2. **Insert the appropriate annotation** immediately above the method/function signature
3. **Mark the requirement as traced** on the tracking list
4. **Track the mapping** for later inclusion in `traceability-modern.yaml`

This is NOT optional. Every method that implements a traced requirement gets an annotation at write time.

### Post-Generation Gate: Completeness Check

After all code for a service has been written, the agent MUST:

1. **Review the tracking list** — identify any REQ-* IDs still unmarked
2. **If gaps exist**, the agent SHALL NOT consider code generation complete. Instead:
   - List the untraced requirements to the user
   - Ask: "These requirements don't have implementing code yet. Should I implement them now, or are they handled elsewhere?"
   - If the user confirms they are out of scope, mark them as `excluded` with a reason
   - Otherwise, implement the missing requirements before proceeding
3. **Only after all requirements are traced or explicitly excluded** may the agent proceed to generate `traceability-modern.yaml`

### Exclusion Guardrails

1. **Every exclusion requires a reason.** Acceptable reasons:
   - "Handled by service X" (cross-service boundary)
   - "Infrastructure concern, not application code" (e.g., deployment, monitoring)
   - "Deferred to phase 2" (with user acknowledgment)
   - Free-text from the user

2. **Exclusions are always visible** in `traceability-modern.yaml` and the validation report with their reason. They are NEVER silently omitted.

3. **Threshold warning.** If more than 20% of requirements are excluded, the agent MUST warn:
   > "X out of Y requirements (Z%) are marked as excluded. This is a high exclusion rate — are you sure these are all handled elsewhere? Would you like to review the list?"

### Context Persistence Across Sessions

For large services spanning multiple sessions, write tracking state to `outputs/microservices/<service>-traceability-progress.yaml` after each session:

```yaml
service: account-service
source_functions:
  - BatchDataProcessing-AccountProcessing
  - OnlineTransactionProcessing-AccountManagement
total_requirements: 49
traced: [REQ-F-001, REQ-F-002, ...]
excluded: []
remaining: [REQ-F-044, REQ-F-048]
last_updated: '2026-06-30T15:30:00Z'
```

On resume, check for `outputs/microservices/*-traceability-progress.yaml`. If a file exists:

- Load the tracked/excluded/remaining lists
- Tell the user: "Resuming traceability — X/Y requirements already traced. Continuing with the remaining Z."

On completion (gate passes), delete `<service>-traceability-progress.yaml` — the final `traceability-modern.yaml` supersedes it.

### Annotation Granularity

Annotate at the **lowest-level method that meaningfully implements business logic**, not the orchestrator that calls it.

| Scenario                                   | Where to Annotate                           |
| ------------------------------------------ | ------------------------------------------- |
| One requirement → one method               | That method                                 |
| One requirement → multiple methods         | Each method that contributes distinct logic |
| Orchestrator calls sub-methods             | The sub-methods, NOT the orchestrator       |
| Helper/utility shared across requirements  | Do NOT annotate the helper                  |
| One method satisfies multiple requirements | Stack annotations on that method            |

**Rule of thumb:** If you removed the annotated method, would the requirement no longer be satisfied? If yes, the annotation is correctly placed.

### Annotation Format (by detected language)

| Language      | Format                             | Placement                                                    |
| ------------- | ---------------------------------- | ------------------------------------------------------------ |
| Java          | `@TracesRequirement("REQ-F-XXX")`  | Above method, after other annotations                        |
| C#            | `[TracesRequirement("REQ-F-XXX")]` | Above method, after other attributes                         |
| TypeScript/JS | `/** @traces REQ-F-XXX */`         | Above function/method, merged into existing JSDoc if present |
| Python        | `@traces_requirement("REQ-F-XXX")` | Below other decorators, above `def`                          |
| Go            | `// traces: REQ-F-XXX`             | Line above function signature                                |
| Rust          | `/// traces: REQ-F-XXX`            | In doc comment block above function                          |
| Other/Unknown | `// traces: REQ-F-XXX`             | Line above function/method                                   |

### Multiple Requirements Per Method

Stack annotations when a single method implements multiple requirements:

```java
@TracesRequirement("REQ-F-044")
@TracesRequirement("REQ-F-048")
public void postTransaction(Transaction txn) { ... }
```

```python
@traces_requirement("REQ-F-044")
@traces_requirement("REQ-F-048")
def post_transaction(self, txn: Transaction) -> None: ...
```

```typescript
/** @traces REQ-F-044 @traces REQ-F-048 */
async postTransaction(txn: Transaction): Promise<void> { ... }
```

### Annotation Type Definition

Include the annotation type definition in the project when generating the first annotated file:

**Java** — Create `TracesRequirement.java`:

```java
package com.example.traceability;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.METHOD, ElementType.TYPE})
@Repeatable(TracesRequirements.class)
public @interface TracesRequirement {
    String value();
}
```

And the container annotation for `@Repeatable`:

```java
package com.example.traceability;

import java.lang.annotation.*;

@Retention(RetentionPolicy.SOURCE)
@Target({ElementType.METHOD, ElementType.TYPE})
public @interface TracesRequirements {
    TracesRequirement[] value();
}
```

**C#** — Create `TracesRequirementAttribute.cs`:

```csharp
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class TracesRequirementAttribute : Attribute
{
    public string RequirementId { get; }
    public TracesRequirementAttribute(string requirementId) => RequirementId = requirementId;
}
```

**Python** — Create `traceability.py`:

```python
def traces_requirement(*req_ids: str):
    """Decorator marking a function as implementing the given requirement(s). No runtime effect."""
    def decorator(func):
        func._traces_requirements = getattr(func, '_traces_requirements', []) + list(req_ids)
        return func
    return decorator
```

**Go/Rust/Other** — No type definition needed (comment-based annotations).

---

## Step 3: Generate `traceability-modern.yaml`

After the completeness gate passes for a service, produce this artifact. Write one file per service into `outputs/microservices/`:

```yaml
service: <service-name>                 # e.g., account-service
generated_at: '<ISO 8601 timestamp>'
source_commit: '<git SHA or "unknown">'
target_language: '<detected language>'
architecture: '<monolith|microservices|serverless|modular>'
project_root: '<relative path to source root>'

# The source functions this service was built from (from the spec header)
# Read the **Source Functions** comma-separated list, e.g.:
# > **Source**: BC-1 ... | **Source Functions**: FunctionA, FunctionB
source_functions:
  - <FunctionName>   # e.g., OnlineTransactionProcessing-AccountManagement
  - <FunctionName>   # e.g., BatchDataProcessing-AccountProcessing

summary:
  total_requirements: <int>
  covered: <int>      # requirements with at least one trace in code
  excluded: <int>     # user-confirmed out-of-scope (with reasons)
  gaps: <int>         # neither implemented nor excluded (should be 0 after gate)

traces:
- req_id: REQ-F-XXX
  legacy_rule_ids:
    # Populated from spec/<FunctionName>/traceability.yaml.
    # Find all captured rules where this REQ-* ID appears in either:
    #   req_id: REQ-F-XXX        (singular — rule maps to one requirement)
    #   req_ids: [REQ-F-XXX, ...]  (plural — rule maps to multiple requirements)
    # Both forms exist in the real data. List every matching rule_id here.
    # Use the exact underscore-separated UUID format, e.g.:
    - 139833a6_6bfd_4ba1_ade8_4f6380850ac4
  locations:
    - target_file: <relative path from project_root>
      element_type: <class|method|function|field|constructor|module|interface>
      element_name: <QualifiedName.methodName>
      start_line: <int>
      end_line: <int>
  annotations:
    - '<actual annotation text>'

# For excluded requirements:
- req_id: REQ-F-YYY
  status: excluded
  reason: '<user-provided reason>'
  locations: []
```

### Writing Rules

- One file per microservice (e.g., `outputs/microservices/account-service-traceability-modern.yaml`)
- One entry per REQ-* ID
- `legacy_rule_ids` is always populated in the mainframe reimagine context. For each REQ-* ID, scan all `spec/<FunctionName>/traceability.yaml` files for the source functions covered by this service. Match rules where:
  - `req_id: <this REQ-*>` (singular field — rule maps to exactly one requirement), OR
  - `req_ids: [<this REQ-*>, ...]` (plural field — rule maps to multiple requirements)
  - Both forms appear in the real data; check for both
- If a service covers multiple source functions, search all their `traceability.yaml` files
- Multiple locations per requirement are normal (one requirement implemented across several methods)
- Use dot-notation for qualified names regardless of language (e.g., `AccountService.getBalance`)
- File paths use forward slashes, relative to `project_root`
- If `source_commit` cannot be determined, use `"unknown"`

---

## Step 4: Completeness Validation

This step produces a persistent, auditable report that can be run in CI/CD pipelines independently of the agent.

### Process

1. Load all `spec/<FunctionName>/traceability.yaml` files for functions covered by this service — extract every `req_id`/`req_ids` entry where `disposition: captured`
2. Load `outputs/microservices/<service>-traceability-modern.yaml` — extract all entries with their locations and status
3. Classify each requirement:
   - **covered** — at least one trace location exists in code
   - **excluded** — user-confirmed out-of-scope with a recorded reason
   - **gap** — neither implemented nor excluded (should be zero if the gate passed)

4. Produce two outputs per service:
   - `outputs/microservices/<service>-traceability-validation.md` — human-readable
   - `outputs/microservices/<service>-traceability-validation.yaml` — machine-readable for CI/CD

### Validation Report Template

```markdown
# Traceability Validation — <ServiceName>

**Generated:** <timestamp>
**Target language:** <language> (<detection method>)
**Source functions:** <FunctionName>, <FunctionName>
**Spec artifact:** outputs/microservices/<service>-specification.md
**Modern artifact:** outputs/microservices/<service>-traceability-modern.yaml

| Status                  | Count | Percentage |
| ----------------------- | ----- | ---------- |
| Covered (implemented)   | N     | X%         |
| Excluded (out of scope) | N     | X%         |
| Gap (unresolved)        | N     | X%         |

### Excluded Requirements

| Req ID    | Reason                                                          |
| --------- | --------------------------------------------------------------- |
| REQ-F-013 | Handled by shared DateUtils library in platform-commons service |

### Gaps (Unresolved)

<table of requirements with no implementation and no exclusion — should be empty if gate passed>
```

---

## Key Principles

- **Requirements-driven** — The REQ-* list is loaded from `outputs/microservices/<service>-specification.md` BEFORE code generation begins. Code generation is not complete until every requirement is traced or explicitly excluded.
- **Write-time only** — Annotations are inserted AS code is being generated. No post-hoc scanning.
- **Gated completion** — The agent cannot declare code generation done until the completeness check passes.
- **Language-agnostic by default** — Never assume a target language. Always detect first.
- **One service at a time** — Process one microservice specification completely (including its traceability gate and YAML output) before moving to the next. This mirrors the "one service at a time" principle from Phase 3 (specgen).
- **Deterministic** — All traces are inserted by the agent at generation time with full knowledge of which requirement is being implemented.

---

## Example Workflow

```
User: "Implement the account-service from the spec"

Agent:
1. Reads outputs/microservices/account-service-specification.md
   → Extracts 49 REQ-* IDs into tracking checklist
   → Reads spec header: `> **Source**: BC-1 ... | **Source Functions**: BatchDataProcessing-AccountProcessing, OnlineTransactionProcessing-AccountManagement`
   → Collects all source functions from the comma-separated list
2. Detects target: Java (found pom.xml)
3. Generates TracesRequirement.java annotation type (first time only)
4. Writes AccountService.java with @TracesRequirement annotations on each
   method — marks REQ-F-001, REQ-F-002, etc. as traced
5. Continues generating remaining service classes...
6. Post-generation gate: checks tracking list
   → 48/49 traced, REQ-F-013 has no implementation
   → Asks user: "REQ-F-013 (timestamp formatting) isn't implemented yet.
     Should I implement it, or is it handled elsewhere?"
7. User says "implement it" → agent writes DateUtils with annotation
8. 49/49 traced — gate passes
9. Generates outputs/microservices/account-service-traceability-modern.yaml
   → For each REQ-*, scans spec/OnlineTransactionProcessing-AccountManagement/traceability.yaml
     and spec/BatchDataProcessing-AccountProcessing/traceability.yaml
   → Matches rules with req_id: <REQ-*> (singular) OR req_ids: [<REQ-*>, ...] (plural)
   → Populates legacy_rule_ids with all matching rule_id values
10. Generates account-service-traceability-validation.md (100% coverage)
```
