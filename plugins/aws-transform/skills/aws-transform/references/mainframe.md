# Mainframe Modernization

> **Last Updated:** 2026-11-20

## Table of Contents

- [Capabilities Overview](#capabilities-overview)
- [Starting Workflow](#starting-workflow)
- [Agents and Transforms](#agents--transforms)
- [Connectors](#connectors)
- [Supported File Types](#supported-file-types)
- [Assessment Signals](#assessment-signals-for-local-discovery)
- [Example Requirements](#example-requirements)
- [Example Tasks](#example-tasks)
- [Known API Behaviors](#known-api-behaviors)
- [Known Limitations](#known-limitations)

AWS Transform for mainframe accelerates the modernization of legacy zOS mainframe applications (COBOL, JCL, CICS, VSAM, Db2, IMS) into cloud-native services on AWS. It orchestrates analysis, documentation, business logic extraction, decomposition, code transformation, and testing through an AI-driven workflow with human-in-the-loop checkpoints. The agent proposes a plan based on your stated objective, executes each step, and pauses for your input when decisions or approvals are needed.

## Capabilities Overview

Reference only. When building a custom plan, present the list the orchestrator returns; it is authoritative.

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

The mainframe orchestrator owns objective negotiation and plan generation. Your job is to get the user's choice into the job chat in the exact form the orchestrator expects, then relay every question it asks. Do not build or describe the plan yourself; show the plan the orchestrator generates.

**Read the job chat before every job reply.** Before any reply about a job (status, next step, task guidance, or a check after relaying an answer), read `list_resources resource="messages"` for that job with `maxResults` (for example 20). The orchestrator asks some questions only in the chat, without creating a task or changing the job status. If its newest message asks a question and no later message has `messageOrigin` `USER`, present that question first and wait for the user's answer. For the Build question after Generate requirements, follow After Generate requirements instead of presenting the question as written.

When the user mentions mainframe modernization, COBOL, JCL, or any mainframe-related topic, present the options:

**Question:** "Here are your mainframe modernization options. You can write out an objective or select from options below:"

**Options:**

- **"Assess and reimagine"** — "Identify modernization boundaries to identify business functions, and generate requirements to reimagine the business functions."
- **"Reimagine"** — "If you already have a scoped application, generate requirements and reimagine this application."
- **"See list of all capabilities"** — "Create a custom job plan by selecting from the available capabilities."
- **"Connect to an existing job"** — "Resume or check progress on a mainframe modernization job you've already started."

Both reimagine options need an Amazon Neptune cluster in the user's account and a reimagine connector (see Connectors below). When the user picks one, say so in one sentence. Do not collect connector details before the job exists; do that when the "Connect to AWS account" task appears.

**Connect to an existing job:** list the user's workspaces and jobs, present the mainframe job(s) with phase, step status and pending tasks, then ask what to do next. If the chosen job is still running, offer automatic tracking ([mainframe-job-tracking](mainframe-job-tracking.md)).

**New job — follow this order:**

1. Confirm workspace and job name with the user in one short message, then wait. This replaces the generic plan confirmation for mainframe jobs: do not list the job's plan steps or a numbered list of what you will do; the orchestrator proposes the plan after the job starts. Do not ask for the source code location.
   > I'll create the job **\<job name\>** in **\<workspace\>** with the mainframe modernization agent. The agent will propose the objective and plan for you to review. OK to create it?
2. `create_job` with `orchestratorAgent` (discovered, see below), a short `objective` naming the application, and `intent`. The orchestrator does not plan from these fields. Then call `load_instructions` with the workspace and job IDs; job-scoped reads and `send_message` are rejected until you do.
3. Read the job messages. The orchestrator posts its own job-plan menu ("To begin, let me know what you are looking to accomplish today..."). The menu's numbering varies by tenant, so never assume an option number.
4. Reply with `send_message` containing **only** the menu line that matches the user's choice, copied verbatim including its number, for example `<N>. Reimagine: If you already have a scoped application, generate requirements and reimagine this application`, where `<N>` is the number that option has in this job's menu. Adding any other words (application name, step list, S3 location) makes the orchestrator treat the reply as a custom objective and offer the capability list instead.
   - For "See list of all capabilities", send that menu line, then present the capability list the orchestrator returns and send the user's selections using the orchestrator's capability names verbatim.
5. Relay each orchestrator question to the user and send the answer back unchanged. Expect, in order:
   - Objective confirmation ("Does this objective match your goals?"), including the Neptune note for reimagine paths.
   - Output language: English is always produced; the user may add one translated language. Present the full list the orchestrator sends.
   - Plan review: fetch the plan with `list_resources resource="plan"` and present every step, then relay approval.
6. After approval the plan executes asynchronously and starts with Kick off modernization (see Connectors, Source Code Upload and Add Collaborators below).
7. Offer automatic tracking, following [mainframe-job-tracking](mainframe-job-tracking.md).

### After Generate requirements

Reimagine and Assess-and-reimagine plans end at **Generate requirements**. Build (code transformation into a target language) is not a plan step at job creation, so do not list it in the plan or say the job will run it.

When Generate requirements succeeds, the orchestrator asks in the job chat whether to continue to Build ("Requirements generation is complete. Do you want to continue to Build, which transforms the code to a target language using the generated requirements? Please reply yes or no."). It is a chat message, not a HITL task, and the job status does not change.

Build is the only step left. The only decision is **yes** (add the Build step and proceed) or **no** (do not add it; the job ends after Generate requirements). Follow Steps 1–3 exactly:

- Ask only Question 1 and Question 2, word for word, with only their options. Post no other text with them: no summary of the requirements, no advice, no other options.
- Never offer or mention anything else at this point: no local reimagine workspace, no reimagine analysis, no comparison with local work, no "check again later". Do not use [mainframe-reimagine](mainframe-reimagine.md) in this flow.
- Send nothing to the job chat except the answer in Step 3.

**Step 1 — Question 1.** Start when the Build question has no later message with `messageOrigin` `USER`. Ask the user (if you cannot present selectable options, post the same question and options as a numbered list). Do not call any download tool before the user answers.

- **Question:** "Requirements generation is complete. How do you want to proceed?"
- **Options:**
  1. **"Review requirements first"** — "Download and review the requirements files first, then decide whether to proceed to the Build step." → Step 2.
  2. **"Skip review and proceed"** — "Skip the requirements download and review, add the Build step to the job plan and proceed immediately." → Step 3 with `yes`.

**Step 2 — Download the requirements, then Question 2.**

1. Take the requirements zip's S3 URI, `s3://<bucket>/transform-output/<jobId>/spec_gen/spec_gen_specs_<timestamp>.zip`, from the description of the task "Review generated modernization requirements" (`list_resources resource="tasks"` without `taskStatus`) or from the job messages. Do not ask the job chat for it.
2. Get the connector ID with `list_resources resource="connectors" workspaceId="<workspaceId>"`.
3. Download only this zip. Do not download the source code.

   ```
   get_resource resource="asset" workspaceId="<workspaceId>" jobId="<jobId>" connectorId="<connectorId>" assetKey="transform-output/<jobId>/spec_gen/spec_gen_specs_<timestamp>.zip" savePath="<workspace root>/spec_gen_specs_<timestamp>.zip"
   ```

   Do not use `resource="artifact"`, the AWS CLI or the user's AWS credentials.
4. Unzip it into `<workspace root>/` as Download Locations below describes (the zip already contains a `spec/` folder), then delete the zip.
5. If any call in 1–4 fails, tell the user "I couldn't download the requirements files.", followed by the error message, then ask Question 1 again.
6. Ask Question 2. `<file path>` is `<workspace root>/spec/`. Show the path only inside the question; do not add a separate path line before or after it.
   - **Question:** "Requirements files downloaded to your workspace successfully (`<file path>`). After you review the requirements, do you want to add the Build step to the job plan and proceed?"
   - **Options:**
     1. **"Yes"** — "Add the Build step to the job plan and proceed." → Step 3 with `yes`.
     2. **"No"** — "Do not add the Build step. The job ends after Generate requirements." → Step 3 with `no`.

**Step 3 — Answer the job.** Read the job messages and take the orchestrator's newest Build question. If it is not in the chat yet, read the messages again until it appears; never send the answer before it. Reply with `send_message` containing **only** `yes` or **only** `no`, as chosen in Step 1 or Step 2; any other words can stop the orchestrator from recognizing the answer. If the orchestrator asks again ("Just to confirm: ..."), send the same answer again; do not ask the user again.

- **yes:** Build is added to the plan and starts (see After Build below). Build first prepares the requirements (`IN_PROGRESS`), then waits in `PENDING_HUMAN_INPUT` for its scope ("Specify build inputs" task, the architecture style questions), then transforms the code (`IN_PROGRESS` again). As soon as Build is `IN_PROGRESS` or `PENDING_HUMAN_INPUT`, start the Build progress dashboard and post its link ([mainframe-build-progress](mainframe-build-progress.md)), before anything else Build needs; it then runs on its own in the background until Build ends. When Build reaches `IN_PROGRESS` while preparing the requirements, job tracking ends: offer Build tracking ([mainframe-job-tracking](mainframe-job-tracking.md) → Build Tracking), and never resume job tracking on your own. Complete the scope task with the scope Q&A in [mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md), never by presenting the task's input box. If Build asks for its scope before preparing anything (`PENDING_HUMAN_INPUT` first), job tracking keeps running and runs the scope Q&A as usual.
- **no:** post exactly "The Build step was not added. The job ends after Generate requirements." and stop. Offer nothing else.

### After Build

When the Build step reaches SUCCEEDED, or a plan read shows it `SUCCEEDED` (for example in a status check of a finished job), first check that the Build progress dashboard is running and start it if it is not ([mainframe-build-progress](mainframe-build-progress.md) → Start the Script), and begin your reply with its "Build has finished" message. Its completion message in the job chat gives the output location (`s3://…/transform-output/<jobId>/build/aws_transform_output_<timestamp>.zip`). Tell the user the build finished and ask whether to download the generated code. Do not call any download tools until they say yes.

- **yes:** download it the same way as the requirements (After Generate requirements → Step 2): get the connector ID with `list_resources resource="connectors"`, then `get_resource resource="asset"` with that `connectorId` and the S3 key after the bucket name as `assetKey`. Do not use `resource="artifact"`, and do not use the AWS CLI or the user's AWS credentials.
  - Unzip into `<workspace root>/build/` (see Download Locations below). Delete the zip after unzipping.
  - Show the resulting folder and point the user to any `README.md` or `DECISIONS.md` files in the output.
- **no:** skip it. The user can ask for the code later.

### Download Locations

Whenever you download a job's outputs, whether in the flows above or because the user asks, put them directly in the workspace root. The AWS Transform plugin reads business rules only from `<workspace root>/spec/`; in any other folder, requirements, business rules and legacy source do not link.

| Download                                                                  | Unzip into                                           |
| ------------------------------------------------------------------------- | ---------------------------------------------------- |
| Requirements (`spec_gen_specs_<timestamp>.zip`, already contains `spec/`) | `<workspace root>/`, giving `<workspace root>/spec/` |
| Original source code                                                      | `<workspace root>/source/`                           |
| Generated code from Build (`aws_transform_output_<timestamp>.zip`)        | `<workspace root>/build/`                            |

- Never unzip the requirements into a subfolder or rename `spec/`.
- Source code: take the zip's S3 URI from the submitted response of Kick off modernization's "Specify resource location" task (`assetLocation`), then download it with `get_resource resource="asset"` and the connector ID, as for the requirements.
- If the target folder already exists and is not empty, ask the user before unzipping: **"Replace"** (delete the folder, then unzip) or **"Cancel"** (download nothing). Requirements and generated code must come from the same job, or business rule links resolve to nothing.
- After unzipping the requirements, tell the user: "If business rule links don't appear in the AWS Transform plugin, run **AWS Transform: Refresh Spec Index** from the Command Palette."
- In After Generate requirements Steps 1–3, skip the Replace question and the Refresh Spec Index tip: replace an existing `spec/` without asking and post only Question 2.

## Agents & Transforms

| Agent           | How to Discover                                                   | Purpose                                                    |
| --------------- | ----------------------------------------------------------------- | ---------------------------------------------------------- |
| Mainframe agent | `list_resources resource="agents" agentType="ORCHESTRATOR_AGENT"` | End-to-end COBOL → Modern microservices application on AWS |

Discover the orchestrator dynamically and pass the name `list_resources` returns as `orchestratorAgent`; do not hardcode it. `jobType` is no longer accepted by `create_job`.

```python
list_resources(resource="agents", agentType="ORCHESTRATOR_AGENT")
create_job(workspaceId="...", jobName="...", orchestratorAgent="<discovered>",
           objective="Reimagine the <application> mainframe application", intent="...")
```

## Connectors

The "Connect to AWS account" task in Kick off modernization needs a connector of type `mainframe_modernization|reimagine|1` for both reimagine paths. A plain S3 connector is not enough: the reimagine connector carries the source bucket plus the Neptune and VPC settings the analysis steps use.

1. `list_resources resource="connectors"` in the job's workspace. If an ACTIVE reimagine connector exists, offer it.
2. Otherwise create one with `create_connector` and `connectorType="mainframe_modernization|reimagine|1"`. Collect the target AWS account ID (`awsAccountId`, a top-level `create_connector` parameter) and **all** of these `configuration` values from the user before calling it. Do not create a partial connector and ask for the rest afterwards.

   | `configuration` key        | Value                                       |
   | -------------------------- | ------------------------------------------- |
   | `s3BucketArn`              | ARN of the bucket holding the source zip    |
   | `neptuneClusterArn`        | Neptune cluster ARN                         |
   | `neptuneClusterResourceId` | Neptune cluster resource ID (`cluster-...`) |
   | `neptuneBulkUploadRoleArn` | IAM role Neptune uses to bulk-load from S3  |
   | `vpcSubnetIds`             | Comma-separated subnet IDs                  |
   | `vpcSecurityGroupId`       | Security group ID                           |

   Show the account ID and full configuration and get the user's confirmation, then create. If another workspace has a reimagine connector, you may offer its values as a starting point, under the same show-and-confirm rule.
3. Approval: give the user the verification link returned by `create_connector`, verbatim. Never construct a console URL yourself. If the link fails, ask the user to open the job's "Connect to AWS account" task in the web app and use the link shown there.
4. After the user confirms approval and `get_resource resource="connector"` shows ACTIVE, submit the task with `{"connectorId": "<id>", "connectorType": "mainframe_modernization|reimagine|1"}` — show the payload first.

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

The agent requires source code as a **single .zip file** in S3, in the connector's bucket. Ask for its location only when Kick off modernization's "Specify resource location" task is waiting for input, never before, and at most once:

1. Take `<bucket>` from the connector submitted in the "Connect to AWS account" task: `get_resource resource="connector"` with that `connectorId` → `configuration.s3BucketArn` (for example `arn:aws:s3:::<bucket>` → `<bucket>`).
2. If the user already gave an S3 URI for the source zip in this chat, use it and go to step 4.
3. Ask, word for word: "Kick off modernization needs your source code. Enter the S3 URI of the source code .zip file in the bucket `<bucket>`, for example `s3://<bucket>/<file>.zip`."
   - If the answer is not `s3://<bucket>/...` ending in `.zip`, say "The source code must be a single .zip file in the bucket `<bucket>`." and ask again.
4. Ask the user, word for word, with only these options:
   - **Question:** "Submit `<S3 URI>` to the Kick off modernization task "Specify resource location"? Task payload: `{"assetLocation": "<S3 URI>"}`"
   - **Options:**
     - **"Submit"** — `complete_task` with `{"assetLocation": "<S3 URI>"}`.
     - **"Not now"** — leave the task open and stop.

### Add Collaborators

Kick off modernization (in some plans, Kickoff) also raises an optional "Add collaborators" task (`InviteCollaboratorsContent`, `NON_BLOCKING`). It does not block the job: Kick off finishes and the later steps run while it stays open.

- Mention it at most once per job, when it first appears, in one line, for example: "Optional: you can add collaborators to this job. Send me their usernames or emails if you want to." Do not wait for an answer before handling the other Kick off tasks.
- If the user names collaborators, submit them as [tools](tools.md) → HITL Tasks describes.
- In every other case it is skipped: the user says skip, answers something else (for example with the source code S3 URI), or does not answer it. Leave the task open and do not submit it.
- Once skipped, never mention it again for this job: never ask for it, never list it as input needed in a status update or during job tracking, and never say Kick off or the job waits for it.

### Checking Progress

Check progress with `list_resources resource="plan"` (step status) and `list_resources resource="tasks"` (pending HITL tasks). Do not call `get_job_status` without `detailed=true`: its default posts a status question to the job chat. Also read the job messages, as Starting Workflow requires for every job reply; the Build question appears there (see After Generate requirements above). Do not ask the job chat for status: a chat message is a user turn for the orchestrator, and its chat answers can lag HITL submissions (for example, asking again for a source location that was already submitted through the task).

Never present the optional "Add collaborators" task as pending input (see Add Collaborators above). Whenever you find Build's scope task ("Specify build inputs") pending, whether in a status check, when connecting to an existing job, or during job tracking, run the scope Q&A in [mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md). Do not present the task as [tools](tools.md) → HITL Tasks describes.

Several steps end with a **blocking, display-only** results task (for example "View code analysis results"). The job does not continue until it is approved, so surface it as soon as you see it. Other display-only tasks may close on their own.

Unless job tracking or Build tracking ([mainframe-job-tracking](mainframe-job-tracking.md)) is on, you do not see job changes between turns. Whenever the user asks about Build or its progress, or a plan read shows Build in any status other than `NOT_STARTED` (`IN_PROGRESS`, `PENDING_HUMAN_INPUT`, `SUCCEEDED`, `FAILED` or `STOPPED`), check that this job's Build progress dashboard ([mainframe-build-progress](mainframe-build-progress.md)) is running: the background process you started, or else a running process whose command line contains `ataa_progress_dashboard.py` and this job's ID. If it is not running, start it ([mainframe-build-progress](mainframe-build-progress.md) → Start the Script) and begin your reply with its dashboard message, before the step table or any other status text. Then, when Build is preparing the requirements ([mainframe-job-tracking](mainframe-job-tracking.md) → Build Tracking), tell the user, for example "Build is still preparing your requirements. No input is needed yet.", and offer Build tracking if you have not offered it for this job; when its scope task is waiting for input, run the scope Q&A; otherwise end your turn. Job tracking ends once Build is `IN_PROGRESS`. Do not tell the user you will notice input requests or step completion on your own; tell them to ask for status, watch the web app, or turn on tracking.

### Local Forward Engineering

[mainframe-reimagine](mainframe-reimagine.md) runs a local reimagine analysis in this workspace. Use it only when the user explicitly asks for that local workflow. Never offer it, and never start it from a job's Generate requirements or Build steps.

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
