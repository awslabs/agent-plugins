---
name: aws-transform
description: Migrate, modernize, and upgrade codebases to AWS. Transforms .NET Framework to .NET 8/10, mainframe COBOL to Java, VMware VMs to EC2, SQL Server to Aurora, and upgrades Java/Python/Node.js versions and AWS SDKs. Use when the user says "migrate .NET to AWS", "upgrade Java to 17/21", "modernize COBOL", "modernize mainframe", "move VMware to EC2", "convert SQL Server to Aurora", "upgrade Python version", "migrate AWS SDK", or "transform this codebase". Don't use for infrastructure provisioning, CI/CD pipelines, or general coding tasks.
---

# AWS Transform

## Overview

Domain expertise for migrating and modernizing workloads using AWS Transform. Covers .NET Framework to .NET 8/10, mainframe COBOL to Java, VMware to EC2, SQL Server to Aurora PostgreSQL, and custom code transformations (Java, Python, Node.js version upgrades, SDK migrations). Orchestrates assessment, planning, and execution through Managed Agents and AWS Transform CLI with human-in-the-loop checkpoints.

## Prerequisites

This skill requires the AWS Transform MCP server (`aws-transform-mcp`). Configure it in your agent's MCP settings:

```json
{
  "mcpServers": {
    "aws-transform-mcp": {
      "command": "uvx",
      "args": [
        "awslabs.aws-transform-mcp-server@latest"
      ]
    }
  }
}
```

The AWS Transform CLI is also required for custom transformations. Install via:

```bash
curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
```

## Mandatory workflow

Follow these phases in order. Do NOT skip ahead. Authentication is handled just-in-time — only when a chosen action actually needs it. Do NOT probe auth before the user has declared an intent.

```
Resume        → Check .atx/context.json
Intent        → Ask user what they want to do
Discovery     → Scan workspace + query available agents
Scope         → User selects what to modernize (GATE 1)
Assessment    → Run workload assessment (NOT optional)
Requirements  → Draft from assessment report
Approval      → User approves requirements (GATE 2)
Tasks         → Generate tasks.md
Execute       → Run transforms, monitor, review diffs
```

**Discovery finds opportunities. Assessment produces detailed findings. Requirements come from the assessment — NOT from discovery.**

You MUST NOT create requirements without an assessment report.
You MUST NOT start execution without requirements.md and tasks.md.

## Resuming a prior session

Check for `.atx/context.json` (workspace-relative). NEVER read `~/.aws/atx/kiro-power-context.json`.

**This check is an internal bookkeeping operation. The user must never see it happen.** Do not announce the check, do not narrate what you are doing. No phrases like "checking for prior sessions", "let me check", "check for a prior session", "context file". On a fresh install, the first visible output must be the intent question — no preamble of any kind.

- **No context found:** Proceed directly to intent. Produce no user-visible output for this step.
- **Context found:** If the context has an active job (`assessment.jobId` or entries in `execution.activeJobIds`), try to refresh live state from the service, but do so invisibly:
  - **Check auth first** (no-auth-required). If sign-in is NOT configured, skip the refresh entirely — do not attempt service calls. Use local context only.
  - **If sign-in is configured**, fetch each resource your resume message depends on — at minimum the job itself and all pending user tasks. Surface every pending task to the user; do not cherry-pick one and omit the others. `BLOCKING` HITL tasks hold up progress even when the job status is active; `NON_BLOCKING` tasks still need attention but don't stall the job. Name every pending task; flag blocking ones. Don't infer one resource from another.
  - **If any call fails** for any reason, silently fall back to local context. **Do NOT reveal your reasoning about the refresh to the user** — no "sign-in isn't configured so I'll skip", no "the service isn't reachable". The user should see only the resume message. Do NOT demand auth or block the flow.

  Then tell the user about their prior session. Frame the offer explicitly as a **continuation** of that same session — not a new one. The message should make clear:
  - This is the specific session they previously worked on. Mention the phase reached, workspace/job identifiers if relevant.
  - **Refresh succeeded** → speak in present tense about live state ("your assessment job is running", "I need your input on X to continue"). If there is a pending HITL task, surface it — don't bury it under "your job is running."
  - **Refresh failed or was skipped** → use prior-session framing: "last time", "when you paused", "previously", "your last session had finished assessment." Do NOT present-tense claims about job state — local context may be stale. Offer sign-in as the path to current status ("sign in to see the latest status"), not as a gate.
  - **Resume** = continue where you left off, reusing the existing assessment report, workspace, and prior progress.
  - **Start fresh** = discard the prior session (local artifacts deleted) and begin a brand-new migration.

  Use language like "continue where you left off" or "pick up from where you stopped" — not ambiguous phrasing like "start a similar session." If user chooses start fresh, delete `.atx/context.json`, `.atx/discovery.json`, `.atx/assessment-report/`, and `.atx/specs/`, then proceed to intent. Otherwise follow the resume logic in [workflow reference](references/workflow.md).

## Determining user intent

Ask the user: "What would you like to focus on?" The first user-visible action in this phase is the question — no auth-probing tool calls precede it, no auth lecture precedes it.

With projects: [Discover This Workspace] [Browse My Jobs] [Start a Specific Transform]
No projects: [Browse My Jobs] [Open a Project Folder] [Start from Scratch]

**Just-in-time auth.** Once the user picks an intent, the next tool that action needs may require auth. If so, prompt for auth then, framed around the action the user just chose ("to browse your jobs, sign in to AWS Transform"). Which auth each MCP tool needs is reported by the MCP server — read it from the tool's description, `get_status`, or the error the tool returns. CLI transforms use AWS credentials only — do NOT prompt for sign-in for CLI-only intents, even when sign-in is unconfigured. If the user picks something that needs no service call (e.g., "Open a Project Folder"), do not probe auth.

See [auth reference](references/auth.md) for the MCP-vs-CLI auth split and how to present sign-in options.

## Discovery

Fast scan (~10 sec). Three things happen in parallel:

1. **Scan the workspace** — detect languages, frameworks, file types, and dependencies present in the project.
2. **Query available agents** — call `list_resources` with `resource: "agents"` (MCP). Skip if sign-in is not configured or the user's intent is CLI-only. This is a paginated API — fetch all pages to get the complete set. The results contain two levels:
   - **Orchestrator agents** — top-level agents you create jobs with. Each orchestrator may have sub-agents that provide deeper workload-specific capabilities.
   - **Sub-agents** — invoked through their orchestrator, not directly. They represent specialized skills within a workload type.
   - Some agents may not belong to a known orchestrator — treat these as standalone capabilities.
3. **List available transformation definitions** — call `atx custom def list` (CLI) to get the current set and what they transform. Skip if CLI is not available or the user's intent is MCP-only.

For the "Discover This Workspace" intent, Discovery is where sign-in is first required (other intents like "Browse My Jobs" need sign-in even earlier, per the just-in-time rule — handle those there). If `list_resources` returns NOT_CONFIGURED, prompt the user to sign in for the auth system needed — do not demand both.

Then **match** workspace signals against orchestrator capabilities and available transformation definitions. Before selecting an orchestratorAgent for any workload, read the matched workload's reference file — it may specify the exact agent to use. Save the matched results to `.atx/discovery.json` — include the orchestrator → sub-agent hierarchy so later steps know what deeper capabilities are available.

See [workflow reference](references/workflow.md) for the workspace scanning framework.

**Discovery is NOT assessment.** Discovery identifies opportunities and matches them to available agents. Assessment produces the detailed findings.

## Scoping (GATE 1)

**For each matched workload type, read ALL reference files with its prefix (e.g., [dotnet](references/dotnet.md)).** These contain the workload's capabilities, workflow, agent details, example requirements, and known limitations. The file prefix comes from the agent match in Discovery — not from a hardcoded list.

Show migration table, then let the user select with multiSelect:

```
| Risk | Why | Component | Current | Target | AWS Target | Recommended Approach |
```

Always explain risk in plain language in the "Why" column — use the user-facing phrases from the Risk Classification table in [workflow reference](references/workflow.md). Never show a bare HIGH/MED/LOW label without explanation.

User selects what to modernize.

## Assessment

**This is NOT optional. Run the workload's assessment BEFORE creating requirements.**

Tell the user: "I'll assess your workload. The assessment report drives the migration plan."

**How assessment runs depends on the workload's reference files.** Each workload type defines its own assessment approach — the agent to use, the objective format, and how to collect results. Consult the matched workload's reference files for specifics.

General pattern for agent-based assessment:

1. **Confirm the plan** — tell the user what you will do (create workspace, create job with which agent, what the objective is). WAIT for approval before calling any tools.
2. Create/select workspace
3. Create job with a **clear objective** — the workload's reference files define what a good objective looks like
4. Start the job (already started by `create_job`; use `control_job` to restart if stopped)
5. Send a **detailed follow-up message** with project specifics
6. **Ask before uploading** — ask how the user wants to share source code. WAIT. Then upload with `categoryType: "CUSTOMER_INPUT"`.
7. Handle agent requests (checkpoints, decisions) — always present to user, WAIT for user response
8. When assessment completes, download the report: `get_resource resource="artifact"`
9. Save report to `.atx/assessment-report/`

**Rule: NEVER batch workspace creation, job creation, and uploads into a single turn without user confirmation at each decision point.**

Use the orchestrator agent or transformation definition identified during Discovery. The match comes from `list_resources` (with `resource: "agents"`) and `atx custom def list`, not a hardcoded mapping. When creating a job, specify the orchestrator — sub-agents are invoked by the orchestrator as needed.

Update `.atx/context.json` with `phase: "assessed"`, workspace ID, job ID.

## Requirements (from assessment report)

Now create `.atx/specs/requirements.md` using the **assessment report** — NOT discovery findings.

- Read `.atx/assessment-report/` for detailed findings
- Load workload reference files for context
- Draft requirements grounded in the assessment (specific blockers, LOC, complexity, migration paths)
- Each requirement says WHO handles it: AWS Transform CLI / Managed Agents / IDE
- Multi-module: group by module with Module Overview table
- See [workflow reference](references/workflow.md) for format

**Do NOT create tasks.md yet.**

Show requirements summary and let the user choose: [Looks Good] [Edit] [Add Component]

## Approval (GATE 2)

Ask the user: "Requirements finalized. Ready to create the execution plan?"
[Create Plan] [Edit More]

## Task generation

Generate `tasks.md` from approved requirements:

- Module Status table + per-module sections
- Sized: max 100 files/task
- Parallel groups verified
- Review-diffs after every code change
- See [workflow reference](references/workflow.md) for format

Present options: [Start Execution] [Review Tasks] [Modify]

## Execution

See [workflow reference](references/workflow.md) for full details.

**How execution runs depends on the workload's reference files.** Each workload type defines its own execution tooling — which agent or CLI command to use, how to parallelize, and how to collect results. Consult the matched workload's reference files.

General pattern for agent-based execution:

When creating new jobs, always:

1. **Clear objective** in `create_job` — what to transform, from what, to what
2. **Detailed follow-up message** via `send_message` — project specifics, discovery findings, blockers
3. **Upload artifacts** if agent needs code — ask user first, `categoryType: "CUSTOMER_INPUT"`

### Every agent request → user decides (NEVER auto-handle)

When the AWS Transform agent asks for input, needs files, or hits a checkpoint:

1. Read the task/message
2. Present to user
3. WAIT for user response
4. Relay user's decision back to agent

### Uploading artifacts to agents

Always use `categoryType: "CUSTOMER_INPUT"` when uploading files to an agent:

```python
upload_artifact(
  workspaceId="...", jobId="...",
  content="/path/to/source.zip",
  fileType="ZIP",
  categoryType="CUSTOMER_INPUT"
)
```

| categoryType      | When to Use                                               |
| ----------------- | --------------------------------------------------------- |
| `CUSTOMER_INPUT`  | Uploading files TO the agent (source code, configs, data) |
| `CUSTOMER_OUTPUT` | Downloading files FROM the agent (reports, migrated code) |
| `HITL_FROM_USER`  | User responses to agent HITL tasks                        |

See [workflow reference](references/workflow.md) for agent request handling patterns.

### Progress

Review diffs after every code change. User must approve.
Update tasks.md checkboxes + `.atx/context.json` after every step.

---

## Context persistence (.atx/context.json)

Save `.atx/context.json` IMMEDIATELY after completing each phase — before presenting results to the user. Every phase transition must have a context save between them. Top-level keys: `phase`, `discovery`, `assessment`, `spec`, `workStyle`, `execution`, `updatedAt`. See [workflow reference](references/workflow.md) for the full schema.

Resume: read `phase`, pick up from that phase.

---

## Constraints

- MUST use product, capability, and step names exactly as defined in this document. Never paraphrase or invent terminology. When describing this skill's capabilities, use: "Migrate, modernize, and upgrade codebases — .NET, mainframe COBOL, VMware, databases, and language/SDK upgrades — using AWS Transform CLI and Managed Agents, directly from your IDE."
- MUST present user choices as an explicit selectable list — never bury options in prose or proceed on an inferred answer
- MUST run CLI commands in background — never block the conversation
- MUST discover agents dynamically via `list_resources` with `resource: "agents"` (paginated) — do not hardcode agent names
- MUST create jobs with orchestrator agents — sub-agents are invoked by the orchestrator, not directly
- MUST refer to resources by name, not ID. When referencing a workspace, job, agent, or artifact in user-facing messages, use its human-readable name. Never surface raw UUIDs in prose. If a resource has no name, use a descriptive phrase ("your .NET modernization job") rather than the ID.
- MUST NOT expose internal mechanics to the user — do not name tools (get_status, list_resources), do not cite step numbers, do not reference files you are reading, and do not narrate what you are about to do. Just do it silently and present the outcome in user terms.
- MUST NOT mix workflow descriptions with actual questions in the same numbered list, and never use count language like "two questions" when some items are informational steps rather than questions. Keep what-I-will-do separate from what-I-need-from-you.
- MUST NOT frame HITL checkpoints, agent questions, or pending decisions as coming from "the web app", "the webapp", "the web UI", or a third-party "the agent is asking / the agent needs / the agent wants". The user is working with you in the IDE — you own the interaction. Present every checkpoint as your own first-person request, not a relayed message from elsewhere. **Wrong:** "The web app is asking how you want to deploy the landing zone." / "The agent is now asking about the replication subnet configuration." **Right:** "The next step is to choose how to deploy the landing zone." / "I need the replication subnet configuration to continue."
- MUST NOT explain what this skill does
- MUST NOT create requirements from discovery — wait for assessment
- MUST NOT skip from discovery to execution
- MUST NOT modify code, upgrade dependencies, or run analysis manually — always use AWS Transform tooling
- MUST NOT make decisions on behalf of the user
- MUST NOT editorialize or use subjective language — no "interesting", "fascinating", "notably", "impressive", "remarkable". State findings as facts.
- MUST NOT prompt for authentication before the user has declared an intent. Auth prompts come from the tool a chosen action needs, framed around that action.
- MUST NOT overclaim freshness. If you did NOT fetch a resource this turn, lead with "last I checked" (past tense throughout) and offer to refresh. Never promise proactive surfacing ("I'll let you know when…") unless actively polling — make the reactive model explicit.
- MUST NOT infer one resource's state from another — each MCP resource (job, tasks, artifacts) is its own source of truth. A job in an active state does NOT imply no pending user tasks. Fetch each resource directly when relevant. See [workflow reference](references/workflow.md).
- MUST NOT mix unrelated transformation goals in the same chat without warning. On every shift to a different goal, suggest the user start a new chat session (they start it themselves). Keep re-offers terse. If the user declines, proceed to answer their question about the other job — do not refuse or redirect back to the original goal. Just avoid mixing cached state (e.g., don't apply VMware findings to the .NET question).
- MUST store state in `.atx/context.json`

---

## Reference

### Core

| Topic                                                                   | File                                             |
| ----------------------------------------------------------------------- | ------------------------------------------------ |
| Authentication (sign-in, AWS credentials, CLI credentials, errors)      | [references/auth.md](references/auth.md)         |
| Tools (MCP tools, CLI commands, connectors, HITL, troubleshooting)      | [references/tools.md](references/tools.md)       |
| Workflow (discovery, transforms, execution, planning, context, display) | [references/workflow.md](references/workflow.md) |

### Workload Types

| Workload     | Files                      |
| ------------ | -------------------------- |
| .NET         | `references/dotnet*.md`    |
| SQL/Database | `references/sql*.md`       |
| Mainframe    | `references/mainframe*.md` |
| VMware       | `references/vmware*.md`    |
| Custom       | `references/custom*.md`    |

Each workload type has a root reference file with its capabilities, workflow, and agent details. Additional files with the same prefix provide deeper guidance (e.g., `custom-cli-reference.md`, `custom-repo-analysis.md`).
