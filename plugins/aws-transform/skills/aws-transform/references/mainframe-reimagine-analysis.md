# Phase 1: Business Function Comprehensive Analysis

## Table of Contents

- [Purpose](#purpose)
- [Goal](#goal)
- [Execution Model: Chunked Output](#execution-model-chunked-output)
- [Input Sources](#input-sources)
- [Analysis Process](#analysis-process)
- [Output Document Structure](#output-document-structure)
- [Traceability Rules](#traceability-rules)
- [Key Principles](#key-principles)

## Purpose

This reference file guides the comprehensive analysis of all business function inputs — requirements, rule dispositions, and discovery artifacts — to produce a single consolidated markdown document (`ddd-analysis.md`). That document serves as the sole input for Phase 2 (DDD bounded context analysis).

## Goal

Read, cross-reference, and synthesize every artifact in the `spec/` folder into a structured, self-contained analysis document that preserves full traceability to the original sources. The output must be rich enough that the DDD bounded context analysis can proceed without re-reading the raw inputs.

## Execution Model: Chunked Output

**CRITICAL**: Do NOT attempt to produce the entire `ddd-analysis.md` document in a single pass. The volume of data across all business functions (typically 40–60 source files, 1000+ rules, 1000+ requirements) will exceed context limits and produce incomplete or shallow output.

**Instead, produce the document in small, incremental chunks. Each file-write or file-append must be small enough to succeed without hitting network timeouts or token limits.**

### Chunk 1: Section 1 (Inventory Only)

1. Read `_index.yaml` and all `capability.yaml` files to build the inventory
2. Read each function's `discovery/data-stores.yaml` for owned/consumed stores
3. Read each function's `traceability.yaml` summary section for disposition counts
4. **Write** (create) `ddd-analysis-wip.md` with the document header and Section 1 (Business Functions Inventory table)

### Chunk 2+: Section 2 (One Business Function Per Chunk)

For EACH business function, produce a SEPARATE append:

1. Read that function's `requirements.md` completely
2. Read that function's `traceability.yaml` completely (captured rules, dispositions)
3. Read that function's `capability.yaml` for shared dependencies
4. **Append** one subsection to `ddd-analysis-wip.md`: "### 2.N \<FunctionName\>" with Requirements Summary, Traceability Summary, and Shared Dependencies Summary

**Repeat for each business function.** Do NOT combine multiple functions in a single write — one function per append operation.

### Next Chunk: Section 2 Shared Capabilities

1. Read all files under `_shared/` (capability.yaml, requirements.md for each shared program)
2. **Append** a "### 2.X Shared Capabilities" subsection summarizing all shared programs

### Next Chunk: Section 3 (Data Store Analysis)

1. Read all `data-stores.yaml` files completely for field-level detail
2. Cross-reference `data-model.md` for the system-wide data store access map
3. Cross-reference the `.function-list.yaml` shared subroutine relationships
4. **Append** Section 3 to `ddd-analysis-wip.md` (Core Business Data Stores with full field dictionaries, Data Ownership Matrix, Entity Relationships, Shared Data Hotspots)

If Section 3 is too large (many data stores with full field dictionaries), split further:

- Append 3.1 and 3.2 (Core Business Data Stores + Data Ownership Matrix)
- Append 3.3 and 3.4 (Entity Relationships + Shared Data Hotspots)

### Next Chunk: Section 4 (Programs and Batch Jobs)

1. Read all `programs.yaml` and `batch-jobs.yaml` files
2. Read all `screens.yaml` files
3. **Append** Section 4 to `ddd-analysis-wip.md` (Program-to-Data-Store Map, Batch Job Data Flows, Program Dependency Graph)

### Final Chunk: Section 5 (Cross-Function Synthesis + Appendix)

1. Synthesize cross-function interactions from data already gathered
2. **Append** Section 5 to `ddd-analysis-wip.md` (Function Interaction Map, Business Rule Distribution, Screen-to-Program-to-Data Flows, Integration Points Summary)
3. **Append** Appendix A (Source File References)
4. **Rename** `ddd-analysis-wip.md` to `ddd-analysis.md` — this signals Phase 1 is complete

### Why Chunked Execution

- **Prevents network timeouts**: Each write is small enough to complete within API limits
- **Prevents context overflow**: Each chunk reads a focused subset of files and produces a bounded output section
- **Enables incremental verification**: Each chunk can be reviewed before proceeding
- **Preserves depth**: Smaller focused passes produce richer cross-referencing than one shallow pass over everything
- **Handles large systems**: Systems with 10+ business functions and 100+ programs cannot fit in a single context window

### File Operations

- **Chunk 1**: Use file-write to CREATE `ddd-analysis-wip.md` with Section 1 only
- **All subsequent chunks**: Use file-APPEND to add content to `ddd-analysis-wip.md`
- **One business function per append** in Section 2 — never combine multiple functions
- If any single append fails with a network error, reduce the content size and retry with a smaller portion
- Each chunk should read its required source files, produce the output, then move to the next chunk
- **After the final chunk** (Section 5 + Appendix): Rename `ddd-analysis-wip.md` to `ddd-analysis.md`. This signals Phase 1 is complete for resume detection.

## Input Sources

### 1. System-Level Files

| Source           | Path                          | Content                                                                                                                              |
| ---------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Function List    | `spec/.function-list.yaml`    | System name, all business functions with program counts, subroutines (classified as dedicated/shared), and shared_with relationships |
| Capability Index | `spec/_index.yaml`            | Generated index listing all business capabilities with their IDs and paths                                                           |
| Data Model       | `spec/data-model.md`          | System-wide data model listing all data stores (type, accessing capabilities)                                                        |
| Glossary         | `spec/.glossary.yaml`         | Domain glossary terms                                                                                                                |
| Term Preferences | `spec/.term-preferences.yaml` | Preferred terminology conventions                                                                                                    |

### 2. Business Function Specifications

Located under `spec/`. Each subdirectory (excluding `_shared/` and files) is a business function:

| Source       | Path Pattern                            | Content                                                                                                                                                                      |
| ------------ | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Capability   | `spec/<FunctionName>/capability.yaml`   | Function metadata: id, kind (business_capability), capability_name, program_count, summary, depends_on (shared programs), and outputs list                                   |
| Requirements | `spec/<FunctionName>/requirements.md`   | User workflows, functional requirements (REQ-*), preconditions, cross-boundary constraints                                                                                   |
| Traceability | `spec/<FunctionName>/traceability.yaml` | Business rules extracted from legacy programs with disposition (captured, not_applicable, unreachable, not_accounted_for), rule_id, program, req_ids, and traceability_lines |

### 3. Discovery Artifacts

Each business function has a `discovery/` subfolder containing structured analysis of the legacy system:

| Source      | Path Pattern                                     | Content                                                                                                                                                       |
| ----------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data Stores | `spec/<FunctionName>/discovery/data-stores.yaml` | Owned and consumed data stores with copybook views, field definitions (name, PIC type, offset, length), record lengths, internal/external readers and writers |
| Programs    | `spec/<FunctionName>/discovery/programs.yaml`    | Programs (COBOL, JCL) with execution type (online/batch/subroutine), transaction IDs, data stores read/written, screen references, calls, and includes        |
| Batch Jobs  | `spec/<FunctionName>/discovery/batch-jobs.yaml`  | Batch jobs classified by type (migrate, interface, setup, skip) with descriptions, programs invoked, and data stores accessed                                 |
| Screens     | `spec/<FunctionName>/discovery/screens.yaml`     | Screen definitions (BMS maps) with field lists (name, type, length) and available actions                                                                     |

### 4. Shared Capabilities

Located under `spec/_shared/`. Each subdirectory is a shared subroutine/program used across multiple business functions:

| Source       | Path Pattern                                 | Content                                                                                                        |
| ------------ | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Capability   | `spec/_shared/<ProgramName>/capability.yaml` | Shared program metadata: id, kind (shared_capability), capability_name, directory, source_programs, rule_count |
| Requirements | `spec/_shared/<ProgramName>/requirements.md` | Functional requirements for the shared program (REQ-* identifiers), open questions                             |

## Analysis Process

Execute the following steps sequentially. Each step builds on the previous one.

### Step 1: Discover and Inventory All Business Functions

1. Read `spec/_index.yaml` to get the system-level list of all business capabilities
2. Read `spec/.function-list.yaml` to get program counts, subroutine dependencies, and shared_with relationships
3. List all subdirectories under `spec/` (excluding `_shared/` and dot-files) to confirm the function list
4. For each subdirectory, read `capability.yaml` for metadata (id, program_count, summary, depends_on)
5. For each subdirectory, verify the presence of `requirements.md`, `traceability.yaml`, and the `discovery/` folder
6. Read each function's `discovery/data-stores.yaml` to extract owned and consumed data stores
7. Inventory shared capabilities from `spec/_shared/` — read each shared program's `capability.yaml`
8. Build a complete inventory

**Output section:** "Business Functions Inventory"

For each function, record:

- Function name (directory name / capability id)
- Capability summary (from capability.yaml)
- Program count (from capability.yaml)
- Whether requirements.md exists
- Whether traceability.yaml exists
- Discovery artifacts present (data-stores, programs, batch-jobs, screens)
- Dependencies on shared capabilities (from capability.yaml `depends_on` field)
- Primary data stores owned (from data-stores.yaml `owned` section)
- Data stores consumed (from data-stores.yaml `consumed` section)
- Internal readers and writers (from data-stores.yaml)
- External readers and writers (from data-stores.yaml — these indicate cross-function dependencies)
- Total rules count and disposition breakdown (from traceability.yaml `summary` section: captured, not_applicable, unreachable, not_accounted_for)

### Step 2: Analyze Each Business Function

For each discovered business function, read its `requirements.md` and `traceability.yaml` in full. Produce a structured summary that captures:

#### 2a. Requirements Summary

For each function's `requirements.md`:

- **Function purpose**: One-paragraph description of what this function does (also available from `capability.yaml` summary field)
- **Actors**: Who uses this function (user roles)
- **Preconditions**: Global preconditions listed at the top
- **User workflows**: List each numbered section with its title and a brief description
- **Key requirements inventory**: Table of all REQ-* identifiers grouped by workflow, with a one-line summary of each
- **Cross-boundary requirements**: Any `REQ-XBND-*`, `REQ-INTEG-*`, `REQ-LOCK-*` or similar cross-cutting requirements that indicate integration points with other functions
- **Validation rules**: Any REQ-VALID-* requirements that define input validation
- **Error handling patterns**: Key error conditions and their handling
- **Open questions**: Any OQ-* items listed at the end of the requirements document

**IMPORTANT**: Preserve all REQ-* identifiers exactly as they appear. These are traceability anchors.

#### 2b. Traceability Summary

For each function's `traceability.yaml`:

- **Total rules** and **disposition breakdown** (captured, not_applicable, unreachable, not_accounted_for) from the `summary` section
- **Captured rules**: List each with rule_id, program, and req_ids — these are the canonical business rules linked to requirements
- **Not applicable rules**: Count only with a brief note on why (typically platform mechanics, working storage, file I/O verb mechanics)
- **Unreachable rules**: Count only — dead code paths
- **Not accounted for rules**: Count only — rules not yet mapped to requirements

**IMPORTANT**: Preserve all rule_id values exactly. These are traceability anchors.

#### 2c. Shared Dependencies Summary

For each function's `capability.yaml` `depends_on` field:

- List each shared capability dependency with its source_programs
- Cross-reference with `_shared/<ProgramName>/requirements.md` for the shared program's functional requirements
- Note which shared programs are used and what they provide

### Step 3: Analyze Discovery Artifacts — Data Stores (Data Model & Field Dictionary)

Read each function's `discovery/data-stores.yaml` in full and produce:

**NOTE**: The data-stores.yaml files serve as both the data model and the field dictionary. Each file contains complete field definitions with PIC types, offsets, and lengths — no separate data dictionary enrichment step is needed.

#### 3a. Core Business Data Stores

For each data store across all functions (both owned and consumed):

- Store name (full DSN)
- Type (VSAM KSDS, VSAM PATH, etc.)
- Record length
- Owning function (the function whose `owned` section lists it)
- Copybook views with program associations
- Complete field listing with PIC types, offsets, and lengths (this is the field dictionary)
- Internal readers and writers (programs within the owning function)
- External readers and writers (programs from other functions)

#### 3b. Data Ownership Matrix

Build a matrix showing which functions own, read, or write each data store. Use the `owned` vs `consumed` classification from each function's data-stores.yaml, supplemented by the system-level `data-model.md` which shows the `Accessed By` relationships for all data stores:

| Data Store | Owner Function | Internal Readers | Internal Writers | External Readers | External Writers |
| ---------- | -------------- | ---------------- | ---------------- | ---------------- | ---------------- |

#### 3c. Entity Relationships

Identify relationships between data stores by analyzing shared key fields:

- Match fields that appear across multiple data stores (e.g., ACCT-ID appearing in both account and transaction stores)
- Note which shared key fields connect entities across functions
- Identify foreign key patterns from field naming conventions

#### 3d. Shared Data Hotspots

Identify data stores accessed by 3+ functions — these are integration hotspots that will drive bounded context boundaries:

- List each hotspot store
- List all functions that own or consume it
- List all external readers and writers
- Note the contention pattern (read-heavy, write-heavy, mixed)

### Step 4: Analyze Discovery Artifacts — Programs and Batch Jobs

Read each function's `discovery/programs.yaml` and `discovery/batch-jobs.yaml` and produce:

#### 4a. Program-to-Data-Store Map

From each function's `programs.yaml`, build a map of which programs access which data stores and how:

- Group by function, then by program
- For each program, list: type (COBOL/JCL), execution mode (online/batch/subroutine), transaction ID
- List data stores read and written
- Note screen associations and program calls
- Note included copybooks

#### 4b. Batch Job Data Flows

From each function's `discovery/batch-jobs.yaml`, identify batch processing chains:

- Group by function
- For each batch job, list: classification (migrate/interface/setup/skip), programs invoked, data stores read/written
- Identify input → processing → output patterns
- Note the classification rationale

#### 4c. Program Dependency Graph

From the `calls` and `includes` fields in programs.yaml, build a dependency view:

- For each program, list what it calls and what calls it
- Classify as online (CICS transaction) vs batch (JCL invoked) vs subroutine
- Identify cross-function program dependencies (programs called by other functions)

### Step 5: Cross-Reference and Synthesize

Produce cross-cutting analysis sections:

#### 5a. Function Interaction Map

Using the data ownership matrix, external readers/writers, and cross-boundary requirements, build a function interaction map:

- Which functions depend on which other functions' data (via external readers/writers in data-stores.yaml)
- What the nature of each dependency is (read-only lookup, shared write, event-driven)
- Which requirements drive each interaction (cite REQ-* identifiers)

#### 5b. Business Rule Distribution

Map captured business rules to the data stores they operate on:

- Which rules validate or transform data in which stores
- Which rules span multiple stores (cross-aggregate candidates)
- Which rules are function-local vs cross-function

#### 5c. Screen-to-Program-to-Data Flows

Read each function's `discovery/screens.yaml` and map the full user interaction chains:

- For each screen: ID, name, associated program, field inventory with types and lengths, available actions
- Map the end-to-end flow: Screen → Program → Data Stores (read/write)
- This reveals the online transaction flows from user input to data persistence and is most valuable when cross-referenced with the function interaction map and program dependency graph

#### 5d. Integration Points Summary

Consolidate all evidence of cross-function integration:

- Cross-boundary requirements (`REQ-XBND-*`, `REQ-INTEG-*`)
- Data stores with external writers (from data-stores.yaml) — these indicate cross-function write dependencies
- Data stores consumed by multiple functions
- Programs that access data stores owned by different functions (external readers/writers)
- Batch jobs that read from one function's output and write to another's input

## Output Document Structure

The output file `ddd-analysis.md` must follow this exact structure. Replace `<SystemName>` with the system name derived from `spec/` content (e.g., folder names, `capability.yaml`, or the job description):

```markdown
# <SystemName> — Comprehensive Business Function Analysis

## Document Purpose

<Brief statement that this document consolidates all business function analysis
 and serves as the input for DDD bounded context identification>

## 1. Business Functions Inventory

<Step 1 output>

## 2. Business Function Detailed Analysis

### 2.1 <FunctionName>

#### 2.1.1 Requirements Summary

#### 2.1.2 Traceability Summary

#### 2.1.3 Shared Dependencies Summary

### 2.2 <FunctionName>

...
<Repeat for all functions>

## 3. Data Store Analysis (Data Model & Field Dictionary)

### 3.1 Core Business Data Stores

### 3.2 Data Ownership Matrix

### 3.3 Entity Relationships

### 3.4 Shared Data Hotspots

## 4. Program and Batch Job Analysis

### 4.1 Program-to-Data-Store Map

### 4.2 Batch Job Data Flows

### 4.3 Program Dependency Graph

## 5. Cross-Function Synthesis

### 5.1 Function Interaction Map

### 5.2 Business Rule Distribution

### 5.3 Screen-to-Program-to-Data Flows

### 5.4 Integration Points Summary

## Appendix A: Source File References

<Complete listing of all input files read during this analysis,
with their relative paths, for full traceability>
```

## Traceability Rules

Throughout the output document, maintain these traceability conventions:

1. **Requirement references**: Always cite as `REQ-XXX-NNN` exactly as they appear in the source requirements.md
2. **Rule references**: Always cite as `rule_id: <uuid>` exactly as they appear in the source traceability.yaml (underscore-separated UUID segments)
3. **Data store references**: Always cite using the full DSN name as it appears in data-stores.yaml (e.g., `%%CICV.MU.MUTB00.TAB.KLALI`)
4. **Program references**: Always cite the program name (e.g., MUBGVEIN) as it appears in programs.yaml
5. **Shared capability references**: Always cite the shared program ID (e.g., MUIALXXB) as it appears in capability.yaml `depends_on`
6. **Source file references**: When citing a specific fact, note the source file path in parentheses

## Key Principles

- **Completeness over brevity**: Include all requirements, all captured rules, all data stores. The DDD analysis cannot go back to re-read inputs.
- **Preserve identifiers**: Every REQ-*, rule_id, program name, and data store identifier must be preserved verbatim for traceability.
- **Cross-reference aggressively**: The value of this document is in connecting requirements to rules to data stores to programs. Make these connections explicit.
- **Include shared capabilities**: The `_shared/` programs represent cross-cutting logic used by multiple business functions — their requirements must be attributed to the consuming functions.
- **Flag ambiguities**: If ownership is unclear, if rules conflict, or if discovery data shows unexpected patterns, call them out explicitly as items for the DDD analysis to resolve.
- **Separate facts from inference**: Clearly mark any inferred relationships or assumptions with [INFERRED] tags.
- **Use discovery data as ground truth**: The discovery artifacts (data-stores.yaml, programs.yaml, batch-jobs.yaml) represent the actual system structure. Use them to validate and enrich the requirements and traceability data.
- **Disposition mapping**: Rules with disposition `captured` are the canonical business rules to model (equivalent to the old "consolidated" disposition). Rules with `not_applicable` are platform mechanics to exclude. Rules with `not_accounted_for` indicate gaps requiring investigation.
