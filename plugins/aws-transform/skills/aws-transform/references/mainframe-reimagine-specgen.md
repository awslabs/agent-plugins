# Phase 3: Microservice Specification Generation

## Table of Contents

- [Purpose](#purpose)
- [Input Sources](#input-sources)
- [Output Rules](#output-rules)
- [Execution Model: One Service at a Time](#execution-model-one-service-at-a-time)
- [Mandatory Source Reading Per Service](#mandatory-source-reading-per-service)
- [Generation Process](#generation-process)
- [Final Specification File Structure](#final-specification-file-structure)
- [Key Principles](#key-principles)

## Purpose

This reference file guides the generation of microservice specifications from a completed DDD bounded context analysis produced in Phase 2.

## Input Sources

This process requires two categories of inputs:

### 1. DDD Analysis Output (Primary Input)

**`ddd-bounded-contexts.md`** — The completed DDD bounded context analysis document produced by Phase 2. This provides:

- Bounded contexts with responsibilities and classifications
- Aggregates, entities, and value objects with field mappings
- Domain events with triggers and subscribers
- Domain services and application services (use cases)
- Context map with integration patterns

### 2. Original Business Requirements (Reference Input)

Located under `spec/`:

- **Capability Metadata** — `spec/<FunctionName>/capability.yaml` for function summary, program count, and shared dependencies
- **Requirements** — `spec/<FunctionName>/requirements.md` for detailed use case flows and business rules
- **Traceability** — `spec/<FunctionName>/traceability.yaml` for canonical business rules (disposition `captured`) with rule_id and req_ids mappings
- **Discovery Artifacts** — `spec/<FunctionName>/discovery/` for field-level details, data types, data store ownership, program structures, and screen definitions
- **Shared Capabilities** — `spec/_shared/<ProgramName>/requirements.md` for requirements of shared subroutines
- **System Data Model** — `spec/data-model.md` for cross-capability data store access patterns

## Output Rules

**MANDATORY**: Each identified microservice MUST have its own dedicated specification file.

- Do NOT combine multiple microservice specifications into a single document
- If a bounded context is decomposed into N services, produce N separate files
- File naming convention: `<service-name>-specification.md`
- Output location: a dedicated output folder (e.g., `outputs/microservices/`)

## Execution Model: One Service at a Time

**CRITICAL**: Do NOT generate all microservice specifications in a single pass. Process **one service at a time** to ensure maximum depth and traceability.

**Execution sequence:**

1. Complete Step 1 (identify all microservices from bounded contexts) — this produces the full inventory
2. For EACH service in the inventory, execute Steps 2–10 completely before moving to the next service
3. For each service, read the relevant source artifacts BEFORE generating the specification (see Mandatory Source Reading below)

**Why:** Generating all services at once causes context pressure that leads to shallow specifications, merged services, and missing traceability. Processing one service at a time ensures each specification gets full attention and complete source cross-referencing.

---

## Mandatory Source Reading Per Service

**BEFORE generating each service specification**, you MUST read the following source artifacts for every business function mapped to that service's bounded context:

### Required Reads (Non-Negotiable)

For each `<FunctionName>` mapped to the service:

1. **`spec/<FunctionName>/requirements.md`** — Read completely. Extract ALL REQ-* identifiers relevant to this service's use cases.
2. **`spec/<FunctionName>/traceability.yaml`** — Read completely. Extract ALL rules with disposition `captured` — these are the canonical business rules that MUST appear in the specification. Each rule has a `rule_id` and `req_ids` linking it to requirements.
3. **`spec/<FunctionName>/discovery/data-stores.yaml`** — Read completely. Extract field-level metadata (PIC types, offsets, lengths, source copybook names) for all data stores owned by this service.

### Required Reads (For Completeness)

1. **`spec/<FunctionName>/discovery/programs.yaml`** — Read to identify legacy program names (e.g., COACTUPC, COACCT01) that must be referenced in use cases.
2. **`spec/<FunctionName>/discovery/batch-jobs.yaml`** — Read to identify batch use cases that must be included (store initialization, data extraction, provisioning).

### What to Extract

From each source file, extract and keep available while generating the specification:

- Every `REQ-*` identifier and its description
- Every `captured` rule's `rule_id` hash and its associated `req_ids`
- Every field's PIC type, byte offset, and length from data-stores.yaml
- Every legacy program name and its purpose
- Every batch job and its classification
- Shared capability requirements from `spec/_shared/<ProgramName>/requirements.md` for any shared programs referenced in `capability.yaml` `depends_on`

**FAILURE MODE**: If you skip these reads, the specification will lack legacy traceability (no PIC types, no rule hashes, no program names) and will be too shallow for implementation. This is the #1 quality differentiator.

---

## Generation Process

Follow these steps sequentially for each microservice identified.

### Step 1: Identify Microservices from Bounded Contexts

Analyze each bounded context from the DDD analysis and determine the service decomposition:

**Mapping patterns:**

| Pattern           | When to Use                                                                             |
| ----------------- | --------------------------------------------------------------------------------------- |
| 1 BC → 1 Service  | Small, cohesive domain with a single team owning it                                     |
| 1 BC → N Services | Large bounded context that can be decomposed further based on distinct sub-capabilities |

**Decomposition criteria:**

- **Business Capability**: Each service owns a complete business capability
- **Autonomy**: Can be developed, deployed, and scaled independently
- **Data Ownership**: Clear ownership of data entities within bounded context only
- **Team Size**: Can be owned by a single team (2-pizza rule)
- **Cohesion**: Operations within the service change together

**Classification:**

- **Core Domain**: High business value, competitive advantage
- **Supporting Subdomain**: Necessary but not differentiating
- **Generic Subdomain**: Common functionality, consider off-the-shelf

**Output format:**

```markdown
## Microservice Inventory

| # | Service Name | Bounded Context | Mapping Pattern | Domain Type             | Key Capabilities |
| - | ------------ | --------------- | --------------- | ----------------------- | ---------------- |
| 1 | <name>       | <BC name>       | 1:1 or 1:N      | Core/Supporting/Generic | <capabilities>   |
```

### Step 2: Generate Service Overview

For each microservice, define:

```markdown
## Service Overview

- **Service Name**: <clear, business-oriented name>
- **Bounded Context**: <from DDD analysis>
- **Domain Type**: Core Domain | Supporting Subdomain | Generic Subdomain
- **Purpose**: <2-3 sentence description of what this service does>
- **Business Capabilities**:
  - <capability 1>
  - <capability 2>
- **Team Ownership**: <suggested team>
```

### Step 3: Define Service Boundaries

**MANDATORY rules:**

- List ONLY what the service owns within its specific bounded context
- Explicitly list what the service does NOT own
- Identify dependencies on other microservices

```markdown
## Service Boundaries

### Owns

- <aggregate/entity from this bounded context>

### Does NOT Own (belongs to other contexts)

- <entity> → owned by <other service/context>

### Dependencies

- <other microservice>: <what is needed and why>
```

### Step 4: Define Data Ownership

Map aggregates from the DDD analysis to this service's data model:

**CRITICAL RULES:**

- Only include aggregates, entities, and value objects from this specific bounded context
- No cross-context data — do not include entities belonging to other bounded contexts
- Single database per service — no shared databases
- External data access must be through service calls, not direct database access
- **Value objects MUST be fully specified** — not just listed in a summary table. Each value object requires its own dedicated section with attributes, validation rules (with REQ-* and rule hash references), formatting requirements, and immutability guarantees.

```markdown
## Data Ownership

### Domain Model

#### <Aggregate Name>

- **Aggregate Root**: <entity>
- **Identity**: <field> (<type>)
- **Source**: <data store DSN> / Copybook <name>.cpy
- **Entities**:
  | Entity | Key Field | Source Data Store | Description |
  | ------ | --------- | ----------------- | ----------- |

**<Entity Name> — Field Mapping**:

| Domain Attribute | Source Field | PIC Type | Offset | Length | Required | Description |
| ---------------- | ------------ | -------- | ------ | ------ | -------- | ----------- |

**Value Objects**:

| Value Object     | Attributes       | Validation                                    |
| ---------------- | ---------------- | --------------------------------------------- |
| <VO Name> (VO-N) | <attribute list> | <validation summary with REQ-* and rule hash> |
```

#### Value Object Detailed Specifications

**MANDATORY**: Each value object identified in the aggregate MUST have a fully expanded specification below the summary table. Do NOT just list value objects — specify them completely.

For each value object, provide:

```markdown
#### <Value Object Name> (VO-N)

- **Source Fields**: <field names from data-stores.yaml>
- **Attributes**:
  | Attribute | PIC Type | Length | Description |
  | --------- | -------- | ------ | ----------- |
- **Validation Rules**:
  - <Rule description> (<REQ-* identifier>, rule `<hash>`)
  - <Rule description> (<REQ-* identifier>, rule `<hash>`)
- **Format**: <expected format, e.g., YYYY-MM-DD, (AAA) PPP-LLLL>
- **Immutability**: Guaranteed — new instance created for any change
```

Use the field mappings from the DDD analysis and reference `discovery/data-stores.yaml` for complete field metadata (PIC types, offsets, lengths).

### Step 5: Define API Specification

Design REST API endpoints for each use case in this bounded context:

**MANDATORY requirements:**

- ALL use cases MUST have corresponding API endpoints
- ALL API endpoints MUST have complete detailed specifications

````markdown
## API Specification

### <Endpoint Name>

- **Method**: GET | POST | PUT | PATCH | DELETE
- **Path**: `/api/v1/<resource>/{id}`
- **Description**: <what this endpoint does>
- **Use Case**: <mapped use case from DDD analysis>

#### Request

```json
{
  "<field>": "<type> — <description>"
}
```
````

#### Response (Success — 200/201)

```json
{
  "<field>": "<type> — <description>"
}
```

#### Error Responses

| Status | Code             | Description |
| ------ | ---------------- | ----------- |
| 400    | VALIDATION_ERROR | `<when>`    |
| 404    | NOT_FOUND        | `<when>`    |
| 409    | CONFLICT         | `<when>`    |

### Step 6: Define Event Publishing

Map domain events from the DDD analysis that originate from this bounded context:

**MANDATORY REQUIREMENTS for event-driven design:**

- Identify ALL state changes that other bounded contexts need to know about
- For each aggregate write operation, ask: "Does any other service need to react to this change?" If yes, publish an event.
- Events from MQ-based interactions MUST also be modeled as domain events
- Each event MUST have explicit trigger conditions with REQ-* references
- Each event MUST list ALL known subscribers with their bounded context identifier

**Minimum events per service:** Every service that performs write operations should publish at least:

1. An event for its primary aggregate state change
2. An event for any cross-context operation it receives
3. An event for any async/batch operation completion

````markdown
## Event Publishing

### <EventName>

- **Trigger**: <what causes this event — be specific about the use case and REQ-* references>
- **Topic/Channel**: `<context-name>.<aggregate>.<event-verb>`
- **Schema**:
  ```json
  {
    "eventId": "string (UUID)",
    "eventType": "<EventName>",
    "occurredAt": "ISO-8601 timestamp",
    "aggregateId": "<field name> (<PIC type>)",
    "payload": {
      "<relevant state change fields with types>"
    }
  }
  ```
````

- **Subscribers**: `<list ALL consuming services with their BC identifier>`

### Step 7: Define Service Communication

Document how this service interacts with other bounded contexts:

**Communication patterns to specify:**

- **Synchronous (REST)**: For immediate consistency requirements
- **Asynchronous (Events)**: For eventual consistency and decoupling
- **Resilience patterns**: Circuit breaker, retry, timeout, fallback — **with specific numeric parameters**

#### MANDATORY: Resilience Pattern Specificity

Do NOT use generic descriptions like "Circuit Breaker / Retry / Timeout". Each synchronous dependency MUST specify concrete resilience parameters:

- **Circuit Breaker**: failure threshold, window duration, half-open retry interval
- **Retry**: maximum attempts, backoff strategy, initial delay
- **Timeout**: connection timeout and read timeout in seconds
- **Fallback**: what happens when the circuit is open

```markdown
## Service Communication

### Synchronous Dependencies (Outbound REST Calls)

| Target Service | Endpoint | Purpose | Resilience Pattern                                                                                      |
| -------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------- |
| <service>      | <path>   | <why>   | Circuit Breaker (<N> failures / <M>s window), Retry (<X> attempts, exponential backoff), Timeout (<Y>s) |

### Events Consumed (Inbound)

| Event        | Source Context | Handler              | Action         |
| ------------ | -------------- | -------------------- | -------------- |
| <event name> | <context>      | <handler class name> | <what happens> |

### Anti-Corruption Layer

| External Concept      | Internal Concept       | Translation Logic      |
| --------------------- | ---------------------- | ---------------------- |
| <external model term> | <internal domain term> | <specific translation> |
```

### Step 8: Define Domain Services

Map domain services from the DDD analysis that belong to this bounded context:

**CRITICAL RULES:**

- Only include domain services operating within this specific bounded context
- Cross-context coordination belongs in application services, not domain services
- **Identify ALL domain services** — not just one per bounded context

**MANDATORY:** Full operation signatures with parameter types and return types

```markdown
## Domain Services

### <Service Name>

- **Responsibility**: <single, clear statement>
- **Operations**:
  - `<operationName>(<param1>: <type>, <param2>: <type>)` → `<ReturnType>` — <description with REQ-* and rule references>
- **Dependencies**:
  - Internal: <repositories, entities, value objects within this context>
  - External: <services from other bounded contexts>
- **Used By**: <which use cases invoke this service>
```

### Step 9: Define Application Services (Use Cases)

Map use cases from the DDD analysis to this service:

**CRITICAL RULES:**

- Only include use cases operating within this specific bounded context
- Single transaction boundary within this bounded context
- **Every flow step MUST have a `REQ-*` reference and/or rule hash** — non-negotiable for traceability

```markdown
## Application Services (Use Cases)

### <Use Case Name>

- **Actor**: <who triggers this>
- **API Endpoint**: <mapped endpoint from Step 5>
- **Input Command**:
  - <field>: <type> — <description>
- **Output Result**:
  - <field>: <type> — <description>
- **Flow**:
  1. <action description> (<REQ-* identifier>, rule `<hash>`)
  2. <action description> (<REQ-* identifier>, rule `<hash>`)
     ...
- **Transaction Boundary**: <what is atomic>
- **Error Handling**:
  | Condition            | Error Code | Response                                         |
  | -------------------- | ---------- | ------------------------------------------------ |
  | <specific condition> | <CODE>     | <HTTP status + description> (<REQ-* identifier>) |
- **Legacy Programs**: <program names from programs.yaml>
```

### Step 10: Traceability Verification Checklist

**MANDATORY**: Before finalizing each service specification, complete this checklist. Do NOT move to the next service until all items pass.

#### 10a. Captured Rule Coverage

For each `<FunctionName>` mapped to this service:

1. Open `spec/<FunctionName>/traceability.yaml`
2. List ALL rules with disposition `captured`
3. Verify that EACH captured rule's `rule_id` hash appears verbatim in the specification
4. If any captured rule is missing, add it to the appropriate section

#### 10b. Requirements Coverage

For each `<FunctionName>` mapped to this service:

1. Open `spec/<FunctionName>/requirements.md`
2. List ALL REQ-* identifiers that belong to use cases in this service
3. Verify that EACH REQ-* identifier appears in the specification
4. If any REQ-* identifier is missing, add it to the appropriate section

#### 10c. Legacy Program Traceability

For each use case in the specification:

1. Verify it references the legacy program name(s) it derives from
2. If missing, add a `Legacy Programs` field to the use case

#### 10d. Field-Level Traceability

For each entity in the Data Ownership section:

1. Verify the field mapping table includes: Domain Attribute, Source Field name, PIC Type, Offset, Length
2. Verify the source data store DSN is referenced
3. If missing, read `spec/<FunctionName>/discovery/data-stores.yaml` and add the complete field mapping

#### 10e. Batch Operations Coverage

1. Review `spec/<FunctionName>/discovery/batch-jobs.yaml` for this service's function(s)
2. Verify that ALL batch operations have corresponding use cases and API endpoints
3. If any batch operation is missing, add it as a use case with its own API endpoint

**Only after ALL checklist items pass, write the specification file and proceed to the next service.**

---

## Final Specification File Structure

Each microservice specification file (`<service-name>-specification.md`) must contain these sections in order:

```
# <Service Name> — Microservice Specification

> **Source**: <BC-N Context Name> | **Mapping**: <1:1 or 1:N> | **Source Function**: <FunctionName>
> **Validates**: <summary of requirement ranges covered>

---

## 1. Service Overview
## 2. Service Boundaries
## 3. Data Ownership
   ### Domain Model
   #### <Aggregate Name>
     - Entity field mappings (full PIC type, offset, length tables)
     - Value Object summary table
   #### Value Object Detailed Specifications (one subsection per VO)
     - Attributes with types
     - Validation rules with REQ-* and rule hashes
     - Format specifications
   #### Invariants (with REQ-* and rule hash references)
## 4. API Specification (all endpoints with full request/response/error schemas)
## 5. Event Publishing (all events with trigger conditions, schemas, and subscriber lists)
## 6. Service Communication (with specific resilience parameters per dependency)
## 7. Domain Services (multiple services with full typed operation signatures)
## 8. Application Services (Use Cases) (with REQ-* on every flow step)
```

## Key Principles

- **One service at a time** — generate each specification in isolation with full source reads before moving to the next
- **One file per microservice** — never combine specifications
- **Never merge bounded contexts** — if the DDD model defines separate contexts, they MUST remain separate services
- **Bounded context scope** — each service only owns data and logic from its bounded context
- **No shared databases** — services communicate through APIs and events
- **Complete API coverage** — every use case (online AND batch) has a corresponding API endpoint
- **Explicit boundaries** — always state what the service does NOT own
- **Resilience by default** — all cross-service communication includes resilience patterns WITH SPECIFIC NUMERIC PARAMETERS
- **Event-driven integration** — prefer asynchronous events for cross-context communication
- **Anti-corruption layers** — protect internal models from external context changes
- **Mandatory source reading** — ALWAYS read requirements.md, traceability.yaml, and data-stores.yaml for each function before generating its service spec
- **Full legacy traceability** — every field must include PIC type, offset, length, and source copybook; every use case must reference its legacy program name; every validation must reference its REQ-* ID and rule hash
- **Batch operations are first-class** — store initialization, data extraction, GDG setup, RACF provisioning, and file operations are full use cases with API endpoints
- **Verify before finalizing** — complete the Step 10 traceability checklist for each service before writing the file
- **Value objects are fully specified** — each VO gets its own section with attributes, validation rules, format, and immutability guarantee
- **Multiple domain services per context** — identify ALL distinct service responsibilities
- **`REQ-*` on every flow step** — every step must reference the specific requirement it implements
- **Events are comprehensive** — publish events for primary state changes, cross-context operations, AND async/batch completions
- **Resilience parameters are concrete** — specify failure threshold, window, retry count, backoff strategy, and timeout for each dependency
