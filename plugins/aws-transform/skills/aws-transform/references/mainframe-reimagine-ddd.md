# Phase 2: DDD Bounded Context Analysis

## Table of Contents

- [Purpose](#purpose)
- [Input Sources](#input-sources)
- [Analysis Process](#analysis-process)
- [Output Structure](#output-structure)
- [Key Principles](#key-principles)

## Purpose

This reference file guides the identification of bounded contexts and their associated domain objects from the consolidated business function analysis document produced in Phase 1.

## Input Sources

The **primary input** for this analysis is:

- **`ddd-analysis.md`** — The consolidated analysis document that synthesizes all business function requirements, rule dispositions, discovery artifacts (data stores, programs, batch jobs, screens), and cross-function dependencies into a single reference. This document preserves full traceability to the original sources.

If additional detail is needed beyond what `ddd-analysis.md` provides, the original sources can be consulted:

1. **Business Requirements** — `spec/<FunctionName>/requirements.md`
2. **Traceability** — `spec/<FunctionName>/traceability.yaml`
3. **Discovery Artifacts** — `spec/<FunctionName>/discovery/` (data-stores.yaml, programs.yaml, batch-jobs.yaml, screens.yaml)
4. **Capability Metadata** — `spec/<FunctionName>/capability.yaml`
5. **System Inventory** — `spec/.function-list.yaml`
6. **Capability Index** — `spec/_index.yaml`
7. **System Data Model** — `spec/data-model.md`
8. **Shared Capabilities** — `spec/_shared/<ProgramName>/` (capability.yaml, requirements.md)

## Analysis Process

Follow these steps sequentially. Each step builds on the previous one.

### Step 0: Discover Business Functions

Before starting the DDD analysis, discover all available business functions:

1. List all subdirectories under `spec/` (excluding files like `.function-list.yaml`)
2. Each subdirectory name represents a business function
3. Verify each function has a `requirements.md` and optionally a `traceability.yaml`
4. Check each function's `discovery/` folder for data-stores.yaml to identify owned data stores
5. Read each function's `capability.yaml` for metadata (summary, program_count, depends_on)
6. Build the inventory of functions to analyze

**Output format:**

```markdown
## Business Functions Inventory

| # | Function Name    | Has Requirements | Has Traceability | Primary Data Stores (Owned)           | Data Stores (Consumed)                   |
| - | ---------------- | ---------------- | ---------------- | ------------------------------------- | ---------------------------------------- |
| 1 | <directory name> | Yes/No           | Yes/No           | <from data-stores.yaml owned section> | <from data-stores.yaml consumed section> |
```

### Step 1: Identify Bounded Contexts

For each discovered business function, analyze:

- The key capabilities described in its `requirements.md`
- The data stores owned or consumed (from `discovery/data-stores.yaml`)
- The cross-boundary requirements (`REQ-XBND-*`, `REQ-INTEG-*`) that reveal integration points
- The traceability data to understand which rules are core vs supporting (captured rules are canonical)
- The shared capability dependencies (from capability.yaml `depends_on`) that reveal cross-function program sharing
- The external readers/writers in data-stores.yaml that reveal cross-function data dependencies

**Criteria for grouping into bounded contexts:**

- **Cohesion**: Functions that share data ownership and change together belong in the same context
- **Autonomy**: A context should be independently deployable
- **Data Ownership**: Use the `owned` vs `consumed` classification in data-stores.yaml — entities owned by a single function strongly indicate a context boundary
- **Business Alignment**: Group by business capability, not by technical similarity
- **Language Consistency**: Terms used consistently within a function group define the ubiquitous language

**Classification:**

- **Core Domain**: Business functions that provide competitive advantage
- **Supporting Subdomain**: Functions that support the core but are not differentiating
- **Generic Subdomain**: Cross-cutting infrastructure concerns

**Output format for each bounded context:**

```markdown
### <Context Name>

- **Responsibility**: <one-sentence description>
- **Classification**: Core Domain | Supporting Subdomain | Generic Subdomain
- **Source Functions**: <list of business functions that map to this context>
- **Owned Data Stores**: <from data-stores.yaml owned section>
- **Consumed Data Stores**: <from data-stores.yaml consumed section>
- **Key Concepts** (ubiquitous language preview):
  - <Term 1>: <brief definition>
  - <Term 2>: <brief definition>
```

### Step 2: Define Ubiquitous Language

For each bounded context identified in Step 1:

- Extract domain terms from the requirements (field names, entity names, operation names)
- Review field definitions from data-stores.yaml copybook views
- Identify business concepts vs technical/legacy terms
- Define each term in business language
- Note context-specific meanings (same term may mean different things in different contexts)

**Output format:**

```markdown
| Term | Business Definition | Context-Specific Meaning | Related Terms |
| ---- | ------------------- | ------------------------ | ------------- |
```

### Step 3: Identify Aggregates and Aggregate Roots

For each bounded context:

- Identify candidate entities from the data stores owned by the context (from data-stores.yaml `owned` section)
- Determine transactional boundaries from the requirements (look for `REQ-LOCK-*`, `REQ-INTEG-*` patterns)
- Identify consistency requirements from business rules in traceability.yaml
- Group entities that must change together atomically
- Select the aggregate root (the entity with the primary identity that controls access)

**Aggregate root selection criteria:**

- Has a unique identifier (primary key field from data-stores.yaml)
- Manages lifecycle of contained entities
- Enforces business rules across the aggregate (from captured rules in traceability.yaml)
- All external access goes through it
- Changes are atomic within the aggregate boundary

**Output format:**

```markdown
### <Aggregate Name>

- **Aggregate Root**: <Entity name>
  - Source: <data store DSN from data-stores.yaml>
  - Identity: <primary key field>
- **Contained Entities**: <list>
- **Invariants**:
  - <business rule enforced by this aggregate>
- **Field Mapping**:
  | Domain Attribute | Source Field | PIC Type | Offset | Length |
  | ---------------- | ------------ | -------- | ------ | ------ |
```

### Step 4: Define Entities

For each aggregate, define the entities within it:

- Extract attributes from the data-stores.yaml field definitions (name, PIC type, offset, length)
- Map field names to business-meaningful attribute names
- Identify data types, lengths, and constraints
- Define entity operations from the requirements

**Output format:**

```markdown
### <Entity Name>

- **Source**: <data store DSN / copybook reference from data-stores.yaml>
- **Identity**: <field name> (<PIC type>, <length>)
- **Attributes**:
  | Attribute | Source Field | PIC Type | Offset | Length | Required | Description |
  | --------- | ------------ | -------- | ------ | ------ | -------- | ----------- |
- **Operations**: <list of methods derived from requirements>
- **Lifecycle**: <creation → states → termination>
```

### Step 5: Define Value Objects

Identify attributes that should be modeled as value objects:

- Composite values (e.g., Address = line1 + line2 + line3 + state + country + zip)
- Values with validation rules (from REQ-VALID-* requirements)
- Values with formatting requirements (e.g., phone numbers with area code/prefix/line)
- Domain concepts without identity (e.g., Money, DateRange, CreditScore)

**Output format:**

```markdown
### <Value Object Name>

- **Source Fields**: <from data-stores.yaml>
- **Attributes**:
  | Attribute | PIC Type | Length | Validation |
  | --------- | -------- | ------ | ---------- |
- **Validation Rules**: <from requirements>
- **Operations**: <formatting, comparison, etc.>
- **Immutability**: Guaranteed — new instance created for any change
```

### Step 6: Identify Domain Events

Look for state changes and integration points:

- Aggregate creation/update/deletion patterns in requirements
- Cross-boundary requirements (`REQ-XBND-*`, `REQ-INTEG-*`) that indicate events needed between contexts
- External writers in data-stores.yaml that indicate cross-function state changes
- Audit requirements
- Notification patterns (message queue interactions in programs.yaml — look for MQ calls)

**Output format:**

```markdown
### <EventName> (past tense)

- **Trigger**: <what causes this event>
- **Source Context**: <bounded context that publishes>
- **Payload**:
  - aggregateId: <type>
  - <relevant state change fields>
  - occurredAt: timestamp
- **Subscribers**: <list of consuming contexts>
```

### Step 7: Define Domain Services

Identify operations that span multiple entities or aggregates:

- Operations involving multiple data stores (from programs.yaml data_stores_read/data_stores_write)
- Complex validations across entities (from traceability.yaml captured rules)
- Calculations using multiple data sources
- Coordination logic from requirements

**Output format:**

```markdown
### <Service Name>

- **Responsibility**: <what it does>
- **Operations**:
  - <operation name>(<inputs>) → <output>
- **Dependencies**: <aggregates/entities it works with>
```

### Step 8: Define Application Services (Use Cases)

Map each major workflow from requirements.md to a use case:

- Each numbered section in requirements.md typically maps to one use case
- Include the step-by-step flow with embedded business rules
- Reference the traceability.yaml for detailed business logic
- Use programs.yaml to understand the implementation flow (program → data store access)

**Output format:**

```markdown
### <Use Case Name>

- **Actor**: <who triggers this>
- **Input**: <command/request structure>
- **Output**: <result/response structure>
- **Flow**:
  1. <step with business rule reference>
  2. <step>
- **Error Handling**:
  - <condition> → <error response>
- **Business Rules**: <references to traceability.yaml entries>
- **Legacy Programs**: <programs from programs.yaml that implement this use case>
```

### Step 9: Define Context Mapping

Identify relationships between bounded contexts:

- Use the external readers/writers from data-stores.yaml to identify data sharing across functions
- Use cross-boundary requirements to identify integration patterns
- Determine upstream/downstream relationships based on data ownership (owned vs consumed)
- Use program call graphs from programs.yaml to identify runtime dependencies

**Relationship patterns to look for:**

- Data stores consumed by multiple functions → potential Shared Kernel or Customer-Supplier
- External read-only access to another context's data → Anti-Corruption Layer
- Message queue interactions (MQ calls in programs.yaml) → Published Language / Open Host Service
- No direct data sharing → independent contexts

**Output format:**

```markdown
### Context Map

| Upstream Context | Downstream Context | Pattern | Shared Concept | Integration Mechanism |
| ---------------- | ------------------ | ------- | -------------- | --------------------- |
```

## Output Structure

**Working file**: Write each step's output incrementally to `ddd-working.md` as it completes — do NOT accumulate all steps in context before writing. When all steps are done, copy the completed file to `ddd-bounded-contexts.md` in the workspace root. This final filename is used by the Resume Detection logic to skip Phase 2 on subsequent runs.

The document should follow this structure:

1. **Executive Summary** — Artifact counts, context overview, key decisions
2. **Business Functions Inventory** — Discovered functions and their data store associations
3. **Bounded Contexts** — Each context with responsibility, classification, language, and aggregates
4. **Aggregate Definitions** — Roots, entities, value objects, and field mappings
5. **Domain Events** — Grouped by context with triggers and subscribers
6. **Domain Services** — Stateless operations spanning aggregates
7. **Application Services** — Use cases with flows and business rules
8. **Context Map** — Relationships and integration patterns

## Key Principles

- Start with discovery — never assume which business functions exist; always scan `spec/` first
- Keep aggregates small — prefer multiple small aggregates over one large one
- Reference other aggregates by ID only (use shared key fields from data-stores.yaml as evidence)
- Use eventual consistency between aggregates
- One transaction = one aggregate modification
- Data stores listed as `consumed` (not `owned`) indicate cross-context dependencies
- External readers/writers in data-stores.yaml reveal cross-function integration points
- Rule dispositions marked "not_applicable" (platform mechanics, working storage) should be excluded from domain modeling
- Rule dispositions marked "captured" represent the canonical business rules to model
- Rule dispositions marked "not_accounted_for" indicate rules not yet mapped to requirements that may need further investigation
- Shared capabilities (from `_shared/`) represent cross-cutting logic — consider whether they form a Generic Subdomain or should be distributed across contexts
