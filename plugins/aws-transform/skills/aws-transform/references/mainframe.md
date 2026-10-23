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

| # | Capability                            | Description                                                                                                                                   | Eligible Files  | Requires                                          |
| - | ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | --------------- | ------------------------------------------------- |
| 1 | Analyze code                          | Parse and analyze your files, collect statistics, analyze structure and dependencies, generate dependency graphs, and identify missing assets | All             | —                                                 |
| 2 | Analyze data                          | Analyze data flow and lineage relationships in your codebase                                                                                  | All             | Code analysis                                     |
| 3 | Analyze activity metrics              | Analyze mainframe SMF records for job runs and metrics                                                                                        | SMF records     | Recommend code analysis first                     |
| 4 | Generate technical documentation      | Create comprehensive technical documentation for your mainframe code                                                                          | COBOL, JCL      | Code analysis + dependency analysis               |
| 5 | Extract business logic                | Extract and document business rules from your mainframe applications                                                                          | COBOL, JCL      | Code analysis + dependency + entry point analysis |
| 6 | Decompose code                        | Break down your codebase into functional or logical domains based on seed programs                                                            | All             | Code analysis. Recommend BRE first                |
| 7 | Plan test cases                       | Create test plans from mainframe code and schedulers                                                                                          | JCL, schedulers | Code analysis. Benefits from BRE                  |
| 8 | Generate test data collection scripts | Create JCL scripts for data collection                                                                                                        | Test plan       | Test planning                                     |
| 9 | Generate test automation scripts      | Generate execution scripts for modern environments                                                                                            | Test plan       | Test planning + test data collection              |

## Starting Workflow

When the user mentions mainframe modernization, COBOL, JCL, or any mainframe-related topic, present the options directly:

**Question:** "Here are your mainframe modernization options. You can write out an objective or select from options below:"

**Options:**

- **"Assess and reimagine"** — "Identify modernization boundaries to identify business functions, and generate requirements to reimagine the business functions. This will analyze code and data to discover discrete data paths and produce a catalog of business functions, then generate modernization requirements to reimagine your selected business functions."
- **"Reimagine"** — "If you already have a scoped application, generate requirements and reimagine this application. This will analyze your programs and data sources, extract business rules, and generate modernization requirements to reimagine your application."
- **"See list of all capabilities"** — "Create a custom job plan by selecting from all available capabilities."
- **"Connect to an existing job"** — "Resume or check progress on a mainframe modernization job you've already started."

**Based on selection:**

- **Assess and reimagine:** Create a job with the full end-to-end workflow. The generated plan will include: Kick off modernization → Discover business functions (Analyze code, Analyze data, Discover data paths, Discover business functions). After the "Discover business functions" phase completes, the user will select one or more business functions to reimagine. Then proceed to: Reimagine (Extract business logic, Generate requirements) for the selected business functions. Confirm the plan with the user before executing.

- **Reimagine:** Create a job scoped to reimagining an already-analyzed application. The generated plan will include: Kick off modernization → Analyze code → Analyze data → Extract business logic → Generate requirements. Confirm the plan with the user before executing.

- **See list of all capabilities:** Present the capabilities from the Capabilities Overview table above and let the user select which to include (they can select by name or number, and choose multiple). Then generate a custom job plan from their selections. Confirm the plan with the user before executing.

- **Connect to an existing job:** List the user's workspaces and jobs to find mainframe jobs. Present the job(s) with their current status (phase, progress, pending tasks). Once connected, show the job status and ask what they'd like to do next (e.g., check status, trigger reimagine, handle pending requests, download artifacts). If the user then asks to "reimagine" or "forward engineer" from a connected job, follow [mainframe-reimagine](mainframe-reimagine.md).

All new job options require a "Kick off modernization" step first (connector setup and source code location) before any analysis begins. Additional steps may be added due to dependencies between capabilities.

## Agents & Transforms

| Agent           | How to Discover                            | Purpose                                                    |
| --------------- | ------------------------------------------ | ---------------------------------------------------------- |
| Mainframe agent | `list_resources` with `resource: "agents"` | End-to-end COBOL → Modern microservices application on AWS |

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

### Reimagine (Forward Engineering)

See [mainframe-reimagine](mainframe-reimagine.md) for the complete workflow to download specs and source code, organize a workspace, and begin reimagining.

### Business Logic Extraction (BRE) Configuration

When the "Configure settings" task appears for BRE (`MainframeBreInputComponent`), you MUST always populate the `userSelectedFiles` array — regardless of `reportScope`.

- `applicationLevel` — produces a single application-wide business rules summary
- `fileLevel` — produces per-file business rules reports

Both scopes require the file list. The webapp auto-selects all files for `applicationLevel`, but the API does not — you must explicitly list them.

## Known Limitations

- Assembler programs (ASM) are not handled by AWS Transform agents — the IDE can analyze but not convert
- PL/I is supported for Business Logic Extraction, Technical Documentation and Data Analysis only — not for refactoring
- CICS BMS screen conversion may need manual UI design decisions
- Complex SORT/MERGE JCL steps may need manual review
- Performance tuning of converted Java code is not automated
