# Table of Contents

- [Quick Start](#quick-start)
- [CLI vs Managed Agents](#cli-vs-managed-agents)
- [Choosing a Transformation](#choosing-a-transformation)
  - [By Tech Stack](#by-tech-stack)
  - [By Goal](#by-goal)
- [Discovery](#discovery)
  - [How It Works](#how-it-works)
  - [Signal Detection](#signal-detection)
  - [Risk Classification](#risk-classification)
  - [Discovery Output](#discovery-output)
- [Execution Lifecycle](#execution-lifecycle)
  - [Managed Agent Jobs (MCP)](#managed-agent-jobs-mcp)
  - [CLI Transforms](#cli-transforms)
  - [Monitoring](#monitoring)
  - [Parallel Execution](#parallel-execution)
  - [Mandatory Diff Review](#mandatory-diff-review)
  - [Hybrid Workflow](#hybrid-workflow)
- [Plan Building](#plan-building)
  - [Spec Structure](#spec-structure)
  - [Two Gates](#two-gates)
  - [Iterative Planning](#iterative-planning)
- [Context Management](#context-management)
  - [Location](#location)
  - [Schema](#schema)
  - [Resume Logic](#resume-logic)
- [Freshness and Source of Truth](#freshness-and-source-of-truth)
  - [Source of truth: fetch each resource directly](#source-of-truth-fetch-each-resource-directly)
  - [Freshness framing](#freshness-framing)
  - [No false promises of proactive surfacing](#no-false-promises-of-proactive-surfacing)
  - [Transformation goal switching](#transformation-goal-switching)
- [Display Conventions](#display-conventions)
  - [Interactive Choices](#interactive-choices)
  - [Consultant-Style Observations](#consultant-style-observations)
  - [Status Icons](#status-icons)
  - [Progress](#progress)

---

## Workflow

## Quick Start

| Say This                              | What Happens                                                     |
| ------------------------------------- | ---------------------------------------------------------------- |
| "Analyze this codebase"               | Quick local analysis of architecture and dependencies            |
| "Start .NET modernization"            | Launch AWS Transform agents to transform .NET Framework → .NET 8 |
| "Check my job"                        | See job status and progress                                      |
| "Review pending requests"             | Handle collaborator requests the agent needs from you            |
| "Download artifacts"                  | Get transformed code, reports, and build outputs                 |
| "Show my workspaces"                  | List your AWS Transform workspaces                               |
| "What transformations are available?" | See available agents for your account                            |

---

## CLI vs Managed Agents

|                   | **AWS Transform CLI**                                                | **Managed Agents**                               |
| ----------------- | -------------------------------------------------------------------- | ------------------------------------------------ |
| **Runs on**       | Your machine                                                         | AWS infrastructure                               |
| **Auth**          | AWS credentials                                                      | Sign in to AWS Transform                         |
| **Scope**         | Single repo                                                          | Multi-repo, specialized workload types           |
| **Best for**      | Analysis, small upgrades, custom transformations, applying standards | .NET, mainframe, VMware, SQL, full modernization |
| **Offline**       | Yes                                                                  | No                                               |
| **Human-in-loop** | No                                                                   | Yes (collaborator requests)                      |
| **Team features** | No                                                                   | Yes (shared workspaces)                          |

**Decision tree:**

```
What do you want to do?
│
├─ Quick analysis or standards check? → CLI
├─ .NET Framework modernization? → Managed Agents
├─ Mainframe (COBOL/JCL)? → Managed Agents
├─ VMware → EC2? → Managed Agents
├─ Database modernization (SQL Server, Oracle)? → Managed Agents
├─ Java/Python version upgrade? → CLI
├─ Team collaboration needed? → Managed Agents
├─ Not sure? → Start with CLI analysis, escalate to Managed Agents if needed
│
└─ Best results on complex project? → Hybrid (CLI assess → Managed Agents transform → CLI validate)
```

---

## Choosing a Transformation

### By Tech Stack

| Stack                    | Approach       | Agent                                                                        |
| ------------------------ | -------------- | ---------------------------------------------------------------------------- |
| .NET Framework 4.x       | Managed Agents | `dotnet-chatty-agent` (hardcoded)                                            |
| .NET Core 3.1 / .NET 5/6 | Managed Agents | Same .NET agent (simpler upgrade)                                            |
| Java 8/11/17             | CLI            | Find Java transformation definitions via `atx custom def list --json`        |
| Spring Boot 2.x → 3.x    | CLI            | Find Spring Boot transformation definitions via `atx custom def list --json` |
| COBOL / JCL              | Managed Agents | Discover via `list_resources resource="agents"`                              |
| VMware VMs               | Managed Agents | Discover via `list_resources resource="agents"`                              |
| SQL Server / Oracle      | Managed Agents | Discover via `list_resources resource="agents"`                              |
| Already modern           | CLI            | Run analysis or standards transformation definitions                         |

**.NET agent is the only hardcoded name. All others: discover dynamically.**

### By Goal

| Goal                   | Approach                                                        |
| ---------------------- | --------------------------------------------------------------- |
| Understand a codebase  | CLI: run analysis transformation definition                     |
| Modernize legacy app   | Identify stack → CLI assessment → Managed Agents transformation |
| Upgrade a version      | CLI for Java/Python; Managed Agents for .NET                    |
| Apply coding standards | CLI: find standards transformation definition                   |
| Migrate to AWS         | Managed Agents (.NET → dotnet-chatty-agent, mainframe, VMware)  |

---

## Discovery

Discovery is a fast scan (~10 sec) that finds what's in the workspace and maps to agents. It is NOT assessment.

### How It Works

1. Glob for project files (signal detection)
2. Read key files for framework/version
3. Classify risk: HIGH / MED / LOW
4. Map to recommended agent
5. Save to `.atx/discovery.json`

### Signal Detection

| Signal File                            | What to Extract                             | Opportunity             |
| -------------------------------------- | ------------------------------------------- | ----------------------- |
| `pom.xml`                              | `<java.version>`, spring-boot version       | Java upgrade            |
| `build.gradle`                         | `sourceCompatibility`, spring boot plugin   | Java upgrade            |
| `pom.xml` / `build.gradle`             | `com.amazonaws` group                       | AWS SDK v1 → v2         |
| `.csproj`                              | `<TargetFrameworkVersion>v4.x`              | .NET modernization      |
| `.csproj`                              | `<TargetFramework>netcoreapp2.x` / `net5.0` | .NET upgrade            |
| `packages.config`, `Web.config`        | Legacy NuGet, `system.web`                  | .NET modernization      |
| `*.cbl`, `*.cob`                       | COBOL source                                | Mainframe modernization |
| `*.jcl`                                | JCL job cards                               | Mainframe modernization |
| `*.sql` with T-SQL (`GO`, `sp_`)       | SQL Server                                  | SQL migration           |
| `*.sql` with PL/SQL (`BEGIN`, `DBMS_`) | Oracle                                      | Oracle migration        |

### Risk Classification

| Risk     | Criteria            | Examples                                                          | Say This to Users                                            |
| -------- | ------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------ |
| **HIGH** | EOL/deprecated      | Java 8, .NET FW 4.x, COBOL, Spring Boot 1.x, Spring Framework 5.x | No longer receiving security updates — migration recommended |
| **MED**  | Patched or near-EOL | Java 11, .NET 9                                                   | Approaching end of life — plan migration soon                |
| **LOW**  | Minor version lag   | Java 17→21                                                        | Current but not latest — optional upgrade for new features   |

### Discovery Output

Save to `.atx/discovery.json`:

```json
{
  "discoveredAt": "...",
  "components": [
    {
      "path": "order-service/",
      "stack": "Java 8, Spring Boot 1.5.22",
      "risk": "HIGH",
      "reason": "Java 8 EOL Jan 2019",
      "recommendedAgent": "AWS Transform CLI (find Java transformation definition via atx custom def list --json)"
    }
  ]
}
```

Present as migration table:

```
| Risk | Why | Component | Current | Target | AWS Target | Recommended Approach |
|------|-----|-----------|---------|--------|------------|---------------------|
| HIGH | No longer receiving security updates | order-service/ | Java 8 | Java 25 | — | CLI |
| HIGH | No longer receiving security updates | storefront/ | .NET FW 4.7.2 | .NET 8 | — | Managed Agents |
```

---

## Execution Lifecycle

All transformations follow this pattern:

### Managed Agent Jobs (MCP)

```
1. Create/select workspace     create_workspace
2. Set up connectors           create_connector (if agent requires them)
3. Create and start job        create_job
4. Drive conversation          send_message
5. Handle collaborator requests complete_task (see tools.md)
6. Download results            get_resource resource="artifact"
```

**Your IDE is the bridge between user and AWS Transform agent:**

- Agent asks a question → present options and wait for user decision
- User answers → relay via `send_message` or `complete_task`
- Agent needs files → upload via `upload_artifact`
- Agent produces results → download via `get_resource resource="artifact"`

**Rule: Present options to user, user decides, relay decision. Never shortcut this.**

### CLI Transforms

```bash
# Always run in background
AWS_REGION=us-east-1 atx custom def exec -n <name> -p <path> -x -t
```

Use `run_in_background=true` in your IDE.

### Monitoring

For job status and progress, ask the agent directly — it has full job context:

```
send_message                      # Scoped to the job: "What's the current status?"
list_resources resource="worklogs" # Recent activity log
list_resources resource="tasks"   # Pending collaborator requests — always check
```

Fall back to lower-level resources only if the agent's answer is unclear or you need specifics it didn't cover:

```
get_resource resource="job"       # Status: CREATED, STARTING, ASSESSING, PLANNING, PLANNED, EXECUTING, AWAITING_HUMAN_INPUT, COMPLETED, FAILED, STOPPING, STOPPED
list_resources resource="plan"    # Phases and current step
list_resources resource="messages" # Raw messages from agent
```

**Monitoring loop:**

- Ask the agent via `send_message` + check `worklogs`
- Always check `list_resources resource="tasks"` — active job status does not imply no pending user tasks
- Always check `list_resources resource="messages"` — messages with a non-null `interactions` array (selection menus, confirmations) may be awaiting a user response via `send_message`. These interactive prompts do NOT appear as tasks and do NOT change the job status. A job can remain in EXECUTING status with no pending tasks while the agent is waiting on a user reply to an interactive message.
- When a collaborator request appears → present to user, relay decision
- When job completes → download artifacts
- When job fails → show error, offer retry

**Waiting between re-checks.** When a resource is in a transitional state and you need to re-check after a delay, use `adaptive_poll` rather than responding with stale data or silently stalling. Follow the tool's own description for terminal states and approval requirements. During an active, user-approved polling loop, present-tense status framing is fine (see Freshness below); outside that loop, do not promise proactive surfacing.

### Parallel Execution

- CLI and Managed Agents on **different** components → run in parallel
- Two CLI transforms on different projects → both `run_in_background`
- Same component → sequential
- Each workspace can only run **one job at a time**

### Mandatory Diff Review

After ANY transform that changes code, show `git diff` summary then present options and wait for user decision:

- "Accept Changes"
- "Revert"
- "Review File-by-File"

User MUST approve before next task.

### Hybrid Workflow

For best results, combine CLI and Managed Agents:

1. **Assess locally** (CLI) — run analysis transformation definition, understand codebase
2. **Transform with Managed Agents** — use findings to guide agents (pass in `intent` field)
3. **Validate locally** (CLI) — apply org standards to output

---

## Plan Building

### Spec Structure

One spec at `.atx/specs/`:

```
.atx/specs/
  .config           # {"specId":"aws-transform","workflowType":"requirements-first","specType":"feature"}
  requirements.md   # Numbered requirements with user stories and acceptance criteria
  tasks.md          # Hierarchical checkboxes referencing requirements
```

For multi-module projects, use **sections within the same spec** — not separate specs.

### Two Gates

**Gate 1: Scope Confirmation** (after discovery, before requirements)

- Present scope summary: components, risk levels, estimated task count
- User confirms or adjusts

**Gate 2: Plan Approval** (after requirements, before execution)

- Present full plan: task count, phases, parallel groups
- User confirms "Start Execution" or adjusts

Between gates: agent works autonomously. After Gate 2: execution proceeds with diff review as the ongoing control mechanism.

### Iterative Planning

```
while not done:
  1. Read requirements.md + tasks.md + .atx/context.json
  2. Pick the most important incomplete task
  3. Execute ONE task
  4. Review diffs — get user approval if code changed
  5. Mark task [x], update context
  6. If new issues found, add to tasks.md
```

One task per iteration. Fresh analysis each time. State on disk.

---

## Context Management

### Location

```
.atx/context.json       ← workspace-relative, source of truth
.atx/discovery.json     ← discovery findings
.atx/specs/             ← requirements + tasks
```

**NEVER read from `~/.aws/atx/context.json`** — that's the MCP server's internal state, not this skill's. Context is always relative to the workspace directory.

Add `.atx/` to `.gitignore`.

### Schema

```json
{
  "phase": "intent|discovery|scoped|assessed|requirements|planning|executing|complete",
  "discovery": { "completedAt": "...", "components": 3, "discoveryFile": ".atx/discovery.json" },
  "assessment": {
    "completedAt": "...",
    "workspaceId": "...",
    "jobId": "...",
    "reportDir": ".atx/assessment-report/"
  },
  "spec": { "folder": ".atx/specs", "requirementsApproved": false, "tasksGenerated": false },
  "workStyle": null,
  "execution": {
    "currentTask": "1.2",
    "completedTasks": ["1.1"],
    "workspaceId": null,
    "activeJobIds": []
  },
  "updatedAt": "..."
}
```

### Resume Logic

Silently check for `.atx/context.json`.

**No context found:** Proceed directly to the Intent step. Never reference internal step numbers in user-facing text — no "Step 1", "Step 2", or similar. Your first user-facing message must be the intent menu itself, with zero preamble.

**Context found:** Before resuming, silently try to refresh live state from the service:

1. **Check auth first** (no-auth-required). Use the MCP tool that reports auth/sign-in status (discover it from `tools/list`). If sign-in is NOT configured, skip the refresh entirely and use local context only. Do NOT attempt further service calls, do NOT mention auth to the user, do NOT demand sign-in.
2. **If sign-in is configured**, fetch each resource your resume message depends on. Each resource has its own source of truth — do NOT infer one from another (e.g., a job in an active state like `EXECUTING` does not mean no pending user tasks). At minimum:
   - The **job** itself — what phase is it in, has it completed or failed.
   - Any **pending tasks** — HITL tasks requiring user action. Fetch ALL pending tasks, not just one. **Surface every pending task to the user — do NOT cherry-pick the most prominent and omit the rest.** Each task (input-needed, approval-pending, etc.) is something the user needs to know about. `BLOCKING` tasks hold up progress even when the job is in an active state; `NON_BLOCKING` tasks still need attention but don't stall the job. Name every pending task in the resume message; flag which ones are blocking.
3. **If any call fails**, silently fall back to local context. Do NOT mention the failure to the user.

Tool names come from the server's `tools/list` response; read tool descriptions directly rather than hardcoding names in resume logic.

Then tell the user about their prior session, framing the offer as a **continuation of that same session** — not a similar new one:

- Use explicit continuation language: "continue where you left off", "pick up from where you stopped".
- What phase was reached (e.g., "last time, your session finished assessment")
- What key artifacts exist (e.g., workspace ID, assessment report)
- **Refresh succeeded** → speak in present tense about live state ("your assessment job is running", "I need your input on X to continue"). If there is a pending HITL task, surface it — don't bury it under "your job is running."
- **Refresh failed or was skipped** → use prior-session framing ("last time", "when you paused", "previously"). Do NOT present-tense claims about job state; local context may be stale. Offer sign-in as the path to current status — a benefit, not a gate ("sign in to see the latest status").
- Clarify what resume vs. start-fresh means in user terms:
  - **Resume** = continue the same session, reusing the existing assessment report, workspace, and prior progress.
  - **Start fresh** = discard the prior session (local artifacts deleted) and begin a brand-new migration.

If user chooses **start fresh**: delete `.atx/context.json`, `.atx/discovery.json`, `.atx/assessment-report/`, and `.atx/specs/`, then proceed to the Intent step.

If user chooses **resume**, resume based on `phase`:

| Phase          | Resume Action                                           |
| -------------- | ------------------------------------------------------- |
| `intent`       | Present intent options again, continue based on choice  |
| `discovery`    | Show migration table, continue to scope                 |
| `scoped`       | Show selected scope, continue to assessment             |
| `assessed`     | Show assessment summary, draft requirements from report |
| `requirements` | Show current requirements, ask to approve or edit       |
| `planning`     | Show tasks, ask to start execution                      |
| `executing`    | Show progress, pick next task                           |
| `complete`     | Show summary, ask what's next                           |

---

## Freshness and Source of Truth

Resume Logic (above) dictates how you frame status at session start. The same discipline applies to **every in-session turn**.

### Source of truth: fetch each resource directly

Each MCP resource (job, tasks, messages, artifacts, connectors, ...) is its own source of truth on the server. Do NOT infer one resource's state from another's. In particular:

- An active job status (`ASSESSING`, `PLANNING`, `EXECUTING`) ≠ no pending user tasks. The agent may be blocked waiting on a checkpoint decision while the job status still reads as active. The job itself can also enter `AWAITING_HUMAN_INPUT`, but ONLY for `BLOCKING` tasks tied to a plan step — `NON_BLOCKING` tasks never trigger this transition. A job in an active state may still have multiple pending `NON_BLOCKING` tasks. So always fetch the tasks resource; don't rely on job status alone.
- Job status COMPLETED ≠ no artifacts pending review.
- An absence of recent messages ≠ no pending tasks.

When the user-facing message depends on a resource, fetch THAT resource. Don't synthesize. The MCP tool surface is the ground truth — discover the right tool name from the server's `tools/list` response (see [tools](tools.md)), not from memory.

### Freshness framing

A "turn" is one user message → one of your responses. Tool calls made while composing the response count as part of the same turn; calls made for a prior user message do not.

Any user-facing claim about job state, messages, tasks, or artifacts must be either:

- **Just-fetched** — you called the relevant read tool (`get_resource`, `list_resources`) in THIS turn, before answering → present tense is OK ("your job is running").
- **Cached** — no fresh fetch this turn → frame as cached AND offer to refresh.

A fetch from a prior turn, resume, or the initial session refresh does NOT count as fresh. You have no clock — the user may have been away for hours; the job may have changed.

**Cached framing must scope the ENTIRE claim.** Lead with the cached marker; every status verb must be past-tense. A trailing "as of earlier" does not retroactively qualify a present-tense leading clause.

- WRONG: "Your job is handling the assessment phase. As of the last check, it was running."
- RIGHT: "As of my last check, your job was handling the assessment phase and running VM tasks. Want me to pull the latest?"

Exception: during an active polling loop (see workload steering files), present tense is fine — the fetch really is happening on each cycle.

### No false promises of proactive surfacing

When NOT polling, do NOT imply background monitoring. Phrases like "I'll let you know when...", "I'll surface those as they come up", "I'll ping you if..." mislead users into assuming this skill is watching the job.

When not polling, make the reactive model explicit: "You'll need to ask me — I don't watch in the background" / "Say 'check status' and I'll pull the latest."

"I'll update you as the job progresses" is only acceptable during an active polling loop.

### Transformation goal switching

Track the "active goal" — what the user is trying to accomplish (e.g., "modernize this VMware fleet"). Two jobs serving the same goal are ONE goal.

When the user's message shifts to a DIFFERENT goal (different workload, different migration target, or a clearly different body of work), before answering:

1. Recognize the shift. Trigger is a change in what the user is accomplishing, not a field-by-field ID comparison.
2. Ask the user and suggest they start a new chat session with fresh context (they start it themselves — you cannot). Give a brief reason: mixing unrelated goals causes cross-contaminated answers.
3. Wait for their choice. If accepted, stop answering about the new goal in this chat. If declined, **answer the user's question in this chat** — respect their choice. Just do not mix cached state from the prior goal into your answers. Do not re-push the new-chat suggestion until the next goal shift.

**Re-offer on every shift**, because cross-contamination compounds. But keep re-offers terse — "Different goal again — want a new chat session? [Yes] [Stay here]" — don't re-lecture.

Carve-out: historical, past-tense questions about a prior goal ("what did my .NET modernization produce last week?") do NOT trigger the suggestion.

---

## Display Conventions

### Interactive Choices

Always present options and wait for user decision when offering choices.

Example interaction format:

- Question: "How would you like to proceed?"
- Options with descriptions:
  - "Approve (Recommended)" - Start executing
  - "Modify" - Change the plan
  - "Explain" - Deep dive into why this order

**Do NOT use markdown bullets or numbered lists for choices.** Create clickable UI elements.

### Consultant-Style Observations

2-3 sentences max. State what you found, then what's possible. No data dumps. Never narrate tool calls — describe outcomes, not mechanics.

### Status Icons

```
[ ] Pending    [Running] Running    [Done] Done    [Failed] Failed
```

### Progress

```
Steps: 2 of 5 complete
```
