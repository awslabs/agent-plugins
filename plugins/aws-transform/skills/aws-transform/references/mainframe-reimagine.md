# Mainframe Reimagine

> **Last Updated:** 2026-06-10

## Table of Contents

- [When to Use](#when-to-use)
- [Prerequisites](#prerequisites)
- [Phases Overview](#phases-overview)
- [Download and Create Workspace](#download--create-workspace)
- [Gate: After Workspace Setup](#gate-after-workspace-setup)
- [Resume Detection](#resume-detection)
- [Execution: Run All Phases](#execution-run-all-phases)

After a mainframe modernization job completes analysis and generates requirements, use this workflow to download the outputs and reimagine the application — decomposing the legacy system into modern microservices through progressive analysis phases.

## When to Use

- User asks to "download specs", "download source code", "forward engineer", "reimagine", or "set up workspace"
- A mainframe job has completed the "Generate requirements" step
- User wants to start building modernized code from the generated specifications

## Prerequisites

- A completed (or partially completed) mainframe job with spec_gen output
- The job's workspace ID and job ID

## Phases Overview

| Phase                        | Input                                      | Output                                                    | Reference                                                                             |
| ---------------------------- | ------------------------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Download & Workspace Setup   | S3 assets                                  | `reimagine-<ts>/` workspace                               | This file                                                                             |
| Business Function Analysis   | `spec/` folder                             | `ddd-analysis.md`                                         | [mainframe-reimagine-analysis](mainframe-reimagine-analysis.md)                       |
| DDD Bounded Context Design   | `ddd-analysis.md`                          | Domain model with contexts, aggregates, events            | [mainframe-reimagine-ddd](mainframe-reimagine-ddd.md)                                 |
| Microservice Spec Generation | DDD model + `spec/`                        | One `*-specification.md` per service                      | [mainframe-reimagine-specgen](mainframe-reimagine-specgen.md)                         |
| Traceability Verification    | Specs + `spec/`                            | `traceability-dashboard.html` (pass/fail)                 | [mainframe-reimagine-verify](mainframe-reimagine-verify.md)                           |
| Modern Code Traceability     | `outputs/microservices/*-specification.md` | Annotated code + `*-traceability-modern.yaml` per service | [mainframe-reimagine-modern-traceability](mainframe-reimagine-modern-traceability.md) |

**User confirmation is required before starting the pipeline (see Gate below).** Once started, phases run sequentially without additional prompts.

---

## Download & Create Workspace

**When the user asks to download specs, source code, or set up a workspace for forward engineering/reimagine:**

Tell the user: "I'll gather the generated specs and original source code from your job, then set up a workspace for reimagining."

Both files are **connector-backed assets** — use `resource="asset"`. Do NOT use `resource="artifact"`, `list_resources resource="artifacts"`, or browse output folders.

**Required parameters for `get_resource resource="asset"`:**

- `workspaceId` — the workspace ID
- `jobId` — the job ID
- `connectorId` — get from `list_resources resource="connectors" workspaceId="<workspaceId>"`
- `assetKey` — the S3 key (path after bucket name)

### Step 0: Get the connector ID

```
list_resources resource="connectors" workspaceId="<workspaceId>"
# Returns the connectorId needed for all asset downloads
```

### Step 1: Download the generated spec requirements

The spec_gen output path is in the agent's message or task:

> "Modernization requirements are stored in your S3 bucket. s3://…/transform-output/\<jobId\>/spec_gen/spec_gen_specs_\<timestamp\>.zip"

```
# Extract the assetKey (the S3 path after the bucket name) and download
get_resource resource="asset" workspaceId="<workspaceId>" jobId="<jobId>" connectorId="<connectorId>" assetKey="transform-output/<jobId>/spec_gen/spec_gen_specs_<timestamp>.zip"
```

### Step 2: Download the original source code ZIP

The source ZIP is NOT in the job's output folders. The ONLY way to find it:

```
# Find the "Specify resource location" task from "Kick off modernization"
list_resources resource="tasks" workspaceId="<workspaceId>" jobId="<jobId>"

# Get the task — read the HUMAN ARTIFACT (submitted response) for the source ZIP filename
get_resource resource="task" workspaceId="<workspaceId>" jobId="<jobId>" taskId="<specify-resource-location-taskId>"

# Download — use the filename from the human artifact as assetKey
get_resource resource="asset" workspaceId="<workspaceId>" jobId="<jobId>" connectorId="<connectorId>" assetKey="<source-zip-filename>.zip"
```

**Do NOT** browse folders or tell the user the source is unavailable — it IS downloadable via the steps above.

### Step 3: Unzip, organize, and clean up

After both downloads complete, create a workspace folder named `reimagine-<current-timestamp>` using the current date and time (e.g., `reimagine-20260610_143022`):

```
# Create workspace folder using current timestamp (YYYYMMDD_HHMMSS)
mkdir -p reimagine-<current-timestamp>/source

# Unzip source code
unzip <source-zip>.zip -d reimagine-<current-timestamp>/source/

# Unzip generated specs directly into workspace root (ZIP already contains a spec/ folder)
unzip spec_gen_specs_<timestamp>.zip -d reimagine-<current-timestamp>/

# Clean up ZIP files
rm <source-zip>.zip spec_gen_specs_<timestamp>.zip
```

Present the resulting structure to the user:

```
reimagine-20260610_143022/
├── source/    ← original mainframe legacy source code
└── spec/      ← generated modernization requirements
```

---

## Gate: After Workspace Setup

Ask the user:

**Question:** "Workspace is ready. Would you like to start the reimagine analysis?"

**Options:**

- **"Start reimagine" (Recommended)** — "I'll run 5 phases to decompose your legacy system into microservice specifications and generate modern code: business function analysis → domain model design → microservice spec generation → traceability verification → modern code generation with traceability annotations. I'll give you a summary after each phase."
- **"Explore with AWS Transform plugin"** — "Install the AWS Transform VS Code extension to browse specs and source interactively with traceability and AI-powered docs."
- **"Stop here"** — "Workspace is set up. You can come back later to start."

If user selects "Explore workspace with AWS Transform plugin", provide more detail:

> The **AWS Transform** VS Code extension adds these features to your workspace:
>
> - **Forward traceability** — select a line of legacy source and see which business rules trace to it
> - **Reverse traceability** — select a requirement (REQ-\*) and jump to the source code locations it maps to
> - **Generate technical documentation** — right-click a program to generate AI-powered docs
> - **Generate business capability summaries** — right-click a spec folder for a capability overview
> - **Generate requirement summaries** — select a REQ-\* to get a plain-language explanation
>
> Search "AWS Transform" in the VS Code Extensions marketplace to install. Once installed, open the reimagine workspace folder and the plugin will auto-detect the spec/ structure.

Then re-ask whether to start reimagine or stop here.

If user proceeds → continue to the Execution section below.

---

## Resume Detection

Before starting any phase, check what output files already exist in the workspace to determine where to resume:

| File exists                                                                                | Skip to                                                                                                    |
| ------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `ddd-analysis-wip.md` (without `ddd-analysis.md`)                                          | Resume Business Function Analysis mid-way — read the WIP file and continue from the last completed section |
| `ddd-analysis.md`                                                                          | Domain Model Design                                                                                        |
| `ddd-working.md` (without `ddd-bounded-contexts.md`)                                       | Resume Domain Model Design mid-way — read the working file and continue from the last completed step       |
| `ddd-bounded-contexts.md`                                                                  | Microservice Spec Generation                                                                               |
| `outputs/microservices/*.md`                                                               | Traceability Verification                                                                                  |
| `traceability-dashboard.html` (without `outputs/microservices/*-traceability-modern.yaml`) | Modern Code Traceability                                                                                   |
| `outputs/microservices/*-traceability-modern.yaml`                                         | Done — show results                                                                                        |

If a previous phase's output exists, tell the user: "I can see you've already completed [phase]. Continuing from [next phase]."

This allows the user to resume in a new conversation if context runs out.

---

## Execution: Run All Phases

Once the user confirms, tell them:

> "Starting the reimagine process. I'll run 5 phases and give you a summary along the way:"
>
> 1. **Business function analysis** — consolidate all spec artifacts into a single analysis document
> 2. **Domain model design** — identify bounded contexts, aggregates, and domain events
> 3. **Microservice spec generation** — produce one detailed specification per service
> 4. **Traceability verification** — confirm every business rule and requirement is covered in specs
> 5. **Modern code traceability** — generate annotated code with requirement traces linked back to legacy rules
>
> If we run into context limits, you can start a new conversation — I'll detect the progress and resume from where we left off.

Then execute each phase sequentially with a brief summary between them. Do NOT ask for confirmation between phases — just notify progress.

### Business Function Analysis

Tell the user: "Starting business function analysis..."

Read and follow [mainframe-reimagine-analysis](mainframe-reimagine-analysis.md).

**Context management:** Read one source file at a time, extract what's needed, write the chunk immediately, then move to the next file. Do NOT accumulate all files in context before writing.

When complete, summarize to the user: brief stats (number of business functions found, data stores, programs) and confirm `ddd-analysis.md` was created.

### Domain Model Design

Tell the user: "Analysis complete. Moving to domain model design..."

Read and follow [mainframe-reimagine-ddd](mainframe-reimagine-ddd.md).

When complete, summarize: number of bounded contexts identified, key aggregates, notable integration points.

### Microservice Spec Generation

Tell the user: "Domain model ready. Generating microservice specifications..."

Read and follow [mainframe-reimagine-specgen](mainframe-reimagine-specgen.md).

When complete, summarize: number of services generated, list the specification files created.

### Traceability Verification

Tell the user: "Specs generated. Running traceability verification..."

Read and follow [mainframe-reimagine-verify](mainframe-reimagine-verify.md).

When complete, present the coverage results (percentage, any gaps) and the path to the HTML dashboard.

### Modern Code Traceability

Tell the user: "Specs verified. Ready to generate modern code with full traceability annotations."

Read and follow [mainframe-reimagine-modern-traceability](mainframe-reimagine-modern-traceability.md).

Process one microservice specification at a time. For each service: detect the target language, build the REQ-* tracking list from the spec, generate the annotated code, run the completeness gate, then produce `outputs/microservices/<service>-traceability-modern.yaml` before moving to the next service.

When all services are complete, summarize: language detected, total services implemented, total requirements traced across all services, any exclusions, and paths to the generated `*-traceability-modern.yaml` files.
