# Mainframe Modernization

> **Last Updated:** 2026-04-01

## Table of Contents

- [Capabilities Overview](#capabilities-overview)
- [Starting Workflow](#starting-workflow)
- [Agents and Transforms](#agents--transforms)
- [Supported File Types](#supported-file-types)
- [Assessment Signals](#assessment-signals-for-local-discovery)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)
- [Known API Behaviors](#known-api-behaviors)
- [Known Limitations](#known-limitations)

AWS Transform for mainframe accelerates the modernization of legacy zOS mainframe applications (COBOL, JCL, CICS, VSAM, Db2, IMS) into cloud-native services on AWS. It orchestrates analysis, documentation, business logic extraction, decomposition, code transformation, and testing through an AI-driven workflow with human-in-the-loop checkpoints. The agent proposes a plan based on your stated objective, executes each step, and pauses for your input when decisions or approvals are needed.

## Capabilities Overview

| #  | Capability                            | Description                                                                                                          | Eligible Files  | Requires                                                     |
| -- | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------- | --------------- | ------------------------------------------------------------ |
| 1  | Analyze code                          | Classifies files, counts LOC, maps dependencies, identifies missing files and duplicates                             | All             | —                                                            |
| 2  | Data analysis                         | Data lineage (program/JCL → dataset mapping) and data dictionary (field-level metadata for copybooks and Db2)        | All             | Code analysis                                                |
| 3  | Activity metrics analysis             | Analyzes SMF records (type 30 batch, type 110 CICS) for job frequency, resource usage, unused code identification    | SMF records     | Recommend code analysis first                                |
| 4  | Generate technical documentation      | PDF/JSON docs per file — summary or detailed functional specification with logic, flows, dependencies                | COBOL, JCL      | Code analysis + dependency analysis                          |
| 5  | Extract business logic                | Extracts business rules, process flows, and logic — application-level (grouped by transactions/jobs) or file-level   | COBOL, JCL      | Code analysis + dependency + entry point analysis            |
| 6  | Decompose code                        | Breaks codebase into functional domains using seed programs, produces dependency graphs                              | All             | Code analysis. Recommend BRE first                           |
| 7  | Migration wave planning               | Sequenced migration plan based on decomposed domains with recommended modernization order                            | Domains         | Decomposition                                                |
| 8  | Refactor code                         | Transforms COBOL → cloud-optimized Java. Configurable target DB, encoding, engine version                            | COBOL           | Code analysis. Recommend decomposition + wave planning first |
| 9  | Reforge code                          | LLM-powered post-refactor improvement — replaces COBOL-style Java with idiomatic Java patterns                       | Refactored Java | Refactor. Quota: 3M LOC/job, 50M LOC/user/month              |
| 10 | Plan test cases                       | Creates test plans from code analysis and scheduler paths, prioritizes by complexity, maps business rules            | JCL, schedulers | Code analysis. Benefits from BRE                             |
| 11 | Generate test data collection scripts | Produces JCL scripts to collect before/after test data from mainframe (Db2 unloads, VSAM REPRO, sequential datasets) | Test plan       | Test planning                                                |
| 12 | Test automation script generation     | Generates scripts to execute test cases on the modernized Java application with data setup and result comparison     | Test plan       | Test planning + test data collection                         |

## Starting Workflow

1. **Inventory** — Scan for COBOL (.cbl, .cob), JCL (.jcl), copybooks (.cpy), and VSAM definitions
2. **Scope decision** — Ask user: full rewrite, partial modernization, or re-platform?
3. **Complete analysis on AWS Transform** — Based on what the customer wants to do, run relevant agents in AWS Transform. Note: the agent always starts with a "Kick off modernization" step that requires connector setup and source code location before any analysis begins.
4. **Build modernized applications with IDE** — Based on scope, draft modernization requirements based on outputs from agents

**Key question to ask user:** "Can you tell me what you are looking to accomplish today on your mainframe modernization project? Is this a full re-architecture to microservices, or a lift-and-shift to run COBOL on AWS?"

## Agents & Transforms

| Agent                               | How to Discover                            | Purpose                                  |
| ----------------------------------- | ------------------------------------------ | ---------------------------------------- |
| Mainframe agent                     | `list_resources` with `resource: "agents"` | End-to-end COBOL → Java/C# modernization |
| AWS/comprehensive-codebase-analysis | CLI: `atx custom def exec`                 | Static analysis of COBOL programs        |

**Discover the agent dynamically** — do not hardcode the agent name:

```python
# First, discover available agents
list_resources(resource="agents")
# Or ask the chat agent
send_message(workspaceId="...", text="What agents are available for mainframe modernization?")
# Then create job — two approaches work:
# Option A: using jobType enum (e.g. MAINFRAME_V2)
create_job(workspaceId="...", jobName="...", jobType="MAINFRAME_V2", objective="...", intent="...")
# Option B: using orchestratorAgent name
create_job(workspaceId="...", jobName="...", orchestratorAgent="<discovered>", objective="...", intent="...")
```

## Supported File Types

zOS: COBOL + copybooks, JCL + PROC, CSD, BMS, Db2, VSAM, IMS TM, PL/I (BRE and docs only — not refactoring).
Fujitsu GS21: PSAM, ADL, NDB.

## Assessment Signals (for local discovery)

These patterns help identify mainframe assets during local workspace scanning, before the AWS Transform agent runs its own analysis:

| File Pattern          | What to Look For             | Indicates                     |
| --------------------- | ---------------------------- | ----------------------------- |
| `*.cbl`, `*.cob`      | COBOL source                 | Mainframe COBOL programs      |
| `*.jcl`               | JCL job cards, DD statements | Batch processing              |
| `*.cpy`               | COBOL copybooks              | Shared data structures        |
| `*.bms`               | BMS maps                     | CICS screen definitions       |
| `EXEC CICS` in source | CICS API calls               | Online transaction processing |
| `EXEC SQL` in source  | Embedded SQL                 | Database access (DB2/IMS)     |

## Example Requirements

```
## Requirement 1: COBOL to Java Conversion

**User Story:** As a developer, I want COBOL batch programs converted to Java services
so that we can run them on AWS without mainframe infrastructure.
**Acceptance Criteria:**

1. WHEN conversion is applied, ALL COBOL PERFORM logic SHALL be equivalent Java methods
2. WHEN conversion is applied, VSAM file I/O SHALL be replaced with database calls
3. WHEN the Java service runs, output SHALL match COBOL program output for test cases
   **Handled by:** AWS Transform Mainframe Agent
```

## Example Tasks

```
- [ ] 1. Inventory and dependency analysis
  - [ ] 1.1 Scan COBOL sources and JCL
  - [ ] 1.2 Map CALL chains and COPY dependencies
- [ ] 2. Convert COBOL programs to Java (AWS Transform)
  - [ ] 2.1 Start mainframe modernization job
  - [ ] 2.2 Handle Collaborator Requests (data mapping decisions)
  - [ ] 2.3 Review diffs — user approves converted code
- [ ] 3. Migrate data stores
  - [ ] 3.1 Convert VSAM to Aurora PostgreSQL schema
  - [ ] 3.2 Migrate data
- [ ] 4. Validation
  - [ ] 4.1 Run test cases comparing COBOL vs Java output
```

## Known API Behaviors

These are things that work differently through the MCP API vs the AWS Transform webapp.

### Source Code Upload

The agent requires source code as a **single .zip file** in S3. When the "Specify resource location" task appears, `assetLocation` must point to a `.zip` file.

### Business Logic Extraction (BRE) Configuration

When the "Configure settings" task appears for BRE (`MainframeBreInputComponent`), you MUST always populate the `userSelectedFiles` array — regardless of `reportScope`.

- `applicationLevel` — produces a single application-wide business rules summary
- `fileLevel` — produces per-file business rules reports

Both scopes require the file list. The webapp auto-selects all files for `applicationLevel`, but the API does not — you must explicitly list them.

## Known Limitations

- Assembler programs (ASM) are not handled by AWS Transform agents — the IDE can analyze but not convert
- PL/I is supported for BRE and documentation only — not for refactoring
- CICS BMS screen conversion may need manual UI design decisions
- Complex SORT/MERGE JCL steps may need manual review
- Performance tuning of converted Java code is not automated
- Reforge quota: 3M lines of code per job, 50M lines of code per user per month
