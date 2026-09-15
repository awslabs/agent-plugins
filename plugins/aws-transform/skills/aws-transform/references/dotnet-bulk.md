# .NET Bulk Modernization (multi-repo / portfolio)

> Last Updated: 2026-08-28

Multi-repository, portfolio-scale .NET modernization driven by the **bulk modernization
orchestrator** (AWS Transform Managed Agents). Use this file when the customer wants to discover and
modernize a **fleet of .NET repositories** behind a source connector — not a single local solution.

**Single local solution instead?** Use [dotnet](dotnet.md) (the single-job flow: one uploaded
`source.zip`, local diff-apply). Route by scope — see [workflow](workflow.md).

## When to use this (vs. single-solution)

| Signal                                                                       | This file (bulk) | [dotnet](dotnet.md) (single)         |
| ---------------------------------------------------------------------------- | ---------------- | ------------------------------------ |
| "Modernize my **portfolio / all my repos**"                                  | ✅               |                                      |
| Source is a **connector** (git repos via CodeConnections, or S3), many repos | ✅               |                                      |
| One solution the user already has locally, wants diffs written back          |                  | ✅                                   |
| Distinct **assessment → plan → transform** phases with review panels         | ✅               | (single job, no separate assessment) |

## Capabilities

Same source→target matrix as single-solution .NET (see [dotnet](dotnet.md) "Capabilities"): .NET
Framework 2.0–4.8 / .NET Core / .NET 5–7 → .NET 8/9/10, VB.NET, WPF, ASP.NET MVC→Core, Web
Forms→Blazor, EF6→EF Core, etc. The difference is **scale and flow**, not the per-repo capability.

## Agent — discover, do NOT hardcode

Per [tools](tools.md), only orchestrator agents create jobs, and they MUST be discovered — never
hardcode an agent id:

```python
list_resources(resource="agents", agentType="ORCHESTRATOR_AGENT")
```

The two .NET orchestrators are easy to confuse — disambiguate on the fields `list_resources`
actually returns, not on chat prose (both are described as ".NET modernization agent"):

| Field (from `list_resources`)                     | Bulk (this flow)                                            | Single-job ([dotnet](dotnet.md))                                 |
| ------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- |
| `name` (agent id)                                 | **`dotnet-bulk-modernization-agent`**                       | `dotnet-chatty-agent`                                            |
| `jobOrchestratorMetadata.chatUILabel`             | ".NET Modernization Agent"                                  | — (none: `jobOrchestrator=false` ⇒ no `jobOrchestratorMetadata`) |
| `jobOrchestrator` (web-app chat entry-point flag) | `true`                                                      | `false`                                                          |
| `description`                                     | "bulk modernization of multi-repository .NET applications…" | single-repo assessment + transformation                          |

Disambiguate on the agent **`name` (id)** — it is the only unambiguous discriminator. Select the
agent whose `name` is **`dotnet-bulk-modernization-agent`** and pass that `name` to
`create_job(orchestratorAgent=...)`. Do **not** filter on `jobOrchestrator` or `chatUILabel`: the
`jobOrchestrator` flag marks the web-app **chat entry-point** (per the agent registry schema), not
"can create jobs," so it is not a reliable selector; `chatUILabel` exists only for `jobOrchestrator=true`
agents (the single-job agent has none), and in chat both simply read as ".NET modernization agent". The
values in the table above are descriptive context,
not filter criteria. In chat prose refer to the agent as ".NET modernization agent" — never the
internal id.

## Authentication

See [auth](auth.md) — the MCP `get_status` message is authoritative for the supported sign-in
options; present all of them. The bulk agent works with any of them, including **AWS Credentials
(IAM)** for accounts whose AWS Transform web app has IAM sign-in enabled (`AWS_PROFILE` +
`ATX_REGION`), in addition to session cookie and SSO. Do not demand a specific mode — follow
`get_status`.

## Decision points

Ask in order: **target version → mode → source (connector vs upload) → scope**. Reuse the exact
question **wording** from [dotnet](dotnet.md), but reuse its **value mapping only for target version**.
Do NOT reuse dotnet.md's Mode value mapping (see the Mode bullet below), and source is connector-based
here (see "Connect the source" below), not the upload-only block from that file:

- **Target version** → `target_framework` (`net10.0` recommended / `net9.0` / `net8.0`).
- **Mode** → this is a **job/orchestrator-level** choice, NOT a per-repo-agent setting. `auto` runs the
  whole portfolio end-to-end without stopping; `interactive` makes the **orchestrator** pause for your
  review at each repo checkpoint. Either way the per-repo transform runs straight through — see the box
  under "Create and start the job". **Reuse only the question wording, not dotnet.md's value mapping:**
  an `interactive` selection here is realized via the orchestrator mode gate, NOT by writing
  `interactive_mode` in the objective — that MUST stay `"auto"`, or the whole job wedges.
- **Scope** (bulk-specific): after discovery, which repos to assess; after assessment, which repos to
  transform (optionally filter by complexity). These are answered through the selection review panels
  below, not up front.

## Workflow

### Verify auth

`get_status()` — if unconfigured, guide sign-in per [auth](auth.md). Do not proceed until confirmed.

### Create or reuse workspace

`create_workspace(name="dotnet-bulk-modernization", description="Modernize .NET portfolio to <target>")`.

### Connect the source (multi-repo)

For a fleet, connect a source rather than uploading one zip:

```python
create_connector(...)   # connectorType per the tool schema (see below)
```

**Supported source categories** — at the platform level the `ConnectorType` is **`CODE_CONNECTION`**
(git repositories via AWS CodeConnections: GitHub, GitLab, Bitbucket, Azure DevOps) or **`S3`**; a
direct **ZIP upload** (`upload_artifact`, `fileType="ZIP"`, `categoryType="CUSTOMER_INPUT"`) is the
one-off alternative (fine for a single case, not the portfolio path).

> **Pass the exact `connectorType` the `create_connector` tool schema specifies — do NOT hardcode the
> raw enum.** The underlying Connector Control Plane accepts only `CODE_CONNECTION`/`S3`, but the tool
> may expect a qualified Agent-Registry connector id (e.g. `dotnet_modernization|code_repository|1`)
> that it maps to that enum. Read the tool schema for the accepted value and required fields before
> calling rather than assuming either form.

`create_connector` creates the connector in `PENDING` and returns a **verification link**. Activate
it one of two ways (per the `create_connector` tool description):

1. **Console approval** — the AWS admin opens the verification link and approves it (they can create
   the IAM role during approval). This is the flow [tools](tools.md) › Connectors documents.
2. **`accept_connector(roleArn=...)`** — the alternative when an IAM role ARN already exists. It
   associates the role with the connector. Call it with `workspaceId`, `connectorId`, and `roleArn`,
   using AWS Credentials for the connector's target account (in addition to the sign-in session).

Either path transitions `PENDING → ACTIVE` — or `REJECTED` if the approver declines, in which case
create a fresh connector (and delete the rejected one to free the workspace connector quota) rather
than polling. Do NOT proceed to discovery until the connector is `ACTIVE`; poll
`get_resource(resource="connector")` (see [tools](tools.md) › Connectors).

### Create and start the job

```python
objective_json = '{"target_framework": "net10.0", "interactive_mode": "auto"}'
create_job(
  workspaceId="<id>", jobName="DotNet Bulk Modernization",  # must start with a letter/digit — no leading "."
  objective=objective_json,           # MUST be valid JSON, not prose
  intent="LANGUAGE_UPGRADE",             # agent-specific value (not a platform-enforced enum)
  orchestratorAgent="<discovered .NET modernization orchestrator>",
)
load_instructions(workspaceId="<id>", jobId="<id>")   # gates job-scoped tools; once per job
```

> **`interactive_mode` in the objective MUST be `"auto"` — always, regardless of the user's Mode
> choice.** In the bulk/orchestrated flow this field controls only the **per-repo transform sub-agent**,
> and each sub-agent has no reviewer of its own: if it is `interactive`, the sub-agent raises a review
> panel after its first project and then idles out, wedging that repo (and, across the wave, the whole
> job) with zero completions. Per-repo review belongs to the **orchestrator**, not the sub-agent. The
> user's `interactive` choice is realized at the orchestrator level (next section) — do NOT encode it here.

Keep `objective` to the confirmed keys (`target_framework`, `interactive_mode="auto"`); the exact
accepted fields come from the job's runtime schema — do not assume others. Drive **repo scope and
complexity filtering through the selection panels** ("Select repos to assess" / "Select repos to
transform"), not the objective.

### If the user chose interactive: set the orchestrator review mode

Only after the job is created — and only if the user picked **interactive** — put the _orchestrator_
into interactive review mode with a mode message (this is how the web app does it; it maps to the
orchestrator's `set_execution_mode`):

```python
send_message(workspaceId="<id>", jobId="<id>", text="interactive")   # orchestrator-level review gate
```

This makes the orchestrator pause for your approval at each repo checkpoint while every sub-agent still
transforms in `auto`. For **auto** portfolios, skip this — the orchestrator default runs the fleet
end-to-end. The user can switch modes at any time by sending `"interactive"` / `"auto"`; it takes
effect at the next checkpoint (switching to auto releases any repo paused for review).

### Discovery

The orchestrator scans the connected source and discovers repositories. Monitor with
`get_resource(resource="job")`; discovered repos surface via the selection panel next.

### Select repos to assess — review panel `DotnetDiscoveredRepoSelector` (tag `batch-assess-selection`)

Present the discovered repos; the user picks which to assess. Follow the generic review-panel pattern
in [tools](tools.md) (read `_outputSchema`/`_responseHint`, present `agentArtifactContent`, then
`complete_task` sending only changed fields).

### Assessment + review — review panel `DotnetAssessmentSummary` (BLOCKING)

Distributed assessment runs across the selected repos, then raises a results panel (complexity, LOC,
Linux-readiness, per-repo tiers) plus a downloadable **Assessment report** artifact. Present it; the
user reviews before proceeding. This is a real review gate — unlike the single-solution flow, there
**is** an assessment results panel here. **Offer to download the report** (see "Downloading reports &
plans" below) — pull the real artifact from the store; do NOT re-serialize panel text.

### Select repos to transform — review panel `DotnetCrossRepoSelector` (tag `transform-selection`)

From the assessed set, the user selects which repos to transform (optionally scoped by complexity).

### Approve the modernization plan — review panel `DotnetUberTransformationPlan` (BLOCKING)

The orchestrator generates a dependency-aware, cross-repo **modernization plan**. Present a summary
and offer the user three actions: **Approve** (start transformation), **Edit** (change before
approving), or **Download the full plan**. (In `auto` mode the plan may be auto-approved — follow the
task's `blockingType`/`_responseHint`.)

**Download the plan = fetch the real artifact, don't re-serialize.** The full plan is a durable job
artifact (`Modernization_Plan.md`; the plan panel payload also carries `uberReportMarkdown` /
`editedPlanMarkdown`). When the user asks to download/save the plan, locate it with
`list_resources(resource="artifacts")` and save it with
`get_resource(resource="artifact", artifactId="<plan artifact>", savePath=...)`. Do NOT reconstruct
the markdown from the panel text you fetched — that produces a lossy, hand-rebuilt copy instead of the
authoritative artifact. Only fall back to writing the panel payload's
`uberReportMarkdown`/`editedPlanMarkdown` if no plan artifact is present in the store.

### Transformation (per-repo waves)

The orchestrator dispatches per-repo transform sub-agents in dependency-aware waves. Monitor via
`get_resource(resource="job")` + `list_resources(resource="tasks")`; use `_pollingGuidance`
(`hasPendingTasks`, `isTerminal`). Do not trust a chat line over the task/job resources.

### Missing private packages — review panel `DotnetMissingPackages` (BLOCKING)

Same handling as single-solution (see [dotnet](dotnet.md) › "Handle Missing Packages"): present the
missing packages, upload `.nupkg` files via `complete_task`/`upload_artifact`, or remove them.
Transformation is blocked until resolved.

### Results & download

Bulk outputs (assessment report, modernization plan, per-repo transformed source, summaries) are
delivered as job **artifacts** and in the web app — see "Downloading reports & plans" below. **Do NOT
apply diffs to a local filesystem** — that IDE-side step from [dotnet](dotnet.md) does not apply to
the portfolio/web flow.

## Downloading reports & plans

Whenever the user asks to download/save a report or plan (at ANY gate — assessment results, plan
approval, or final results), pull the **real artifact from the store**, never a hand-rebuilt copy:

1. `list_resources(resource="artifacts")` (paginate; use the "Generated Outputs/" `pathPrefix` on the
   second call if the first returns folders). Identify by `fileName` / `categoryType`.
2. `get_resource(resource="artifact", artifactId="<id>", savePath=".atx/<fileName>")` to save it.
3. Tell the user the local path.

| Artifact                                | fileName (typical)                          | Gate it's available   |
| --------------------------------------- | ------------------------------------------- | --------------------- |
| Assessment report                       | `Assessment_Report.*` (md/html)             | after assessment      |
| Modernization plan                      | `Modernization_Plan.md`                     | after plan generation |
| Per-repo transformed source / summaries | `*_Transformed_*.zip`, report/summary files | after transformation  |

**Anti-pattern:** do NOT reconstruct a report/plan by re-serializing the markdown you fetched for a
review panel (e.g. writing the plan's `uberReportMarkdown` to a file from memory). That yields a
lossy, agent-rebuilt copy. Fetch the authoritative artifact via `get_resource`; only use the panel
payload's `uberReportMarkdown`/`editedPlanMarkdown` as a fallback when no corresponding artifact
exists yet.

## Review panel reference (bulk)

| Panel                     | Component ID                   | Tag                      | Blocking   | Role                                     |
| ------------------------- | ------------------------------ | ------------------------ | ---------- | ---------------------------------------- |
| Select repos to assess    | `DotnetDiscoveredRepoSelector` | `batch-assess-selection` | per schema | Pick discovered repos to assess          |
| Assessment results        | `DotnetAssessmentSummary`      | —                        | BLOCKING   | Review complexity/LOC/readiness + report |
| Select repos to transform | `DotnetCrossRepoSelector`      | `transform-selection`    | per schema | Pick assessed repos to transform         |
| Modernization plan        | `DotnetUberTransformationPlan` | —                        | BLOCKING   | Approve/edit cross-repo plan             |
| Missing packages          | `DotnetMissingPackages`        | `missing-packages`       | BLOCKING   | Provide/remove private NuGet packages    |

Always drive these through the generic review-panel flow in [tools](tools.md) — the submission shape
comes from each task's `_outputSchema`/`_responseHint` at runtime, not from hardcoded payloads here.

## Status check

Same procedure as [dotnet](dotnet.md) › "Status Check": `get_resource(resource="job")` +
`list_resources(resource="tasks")`, read `_pollingGuidance`, and surface any pending review panel or
an agent message awaiting a `send_message`. Note the extra phases (discovery, assessment, plan) each
have their own pending-task shape — always fetch the tasks resource; never infer readiness from job
status alone.

## Known limitations

Per-repo limitations are the same as single-solution ([dotnet](dotnet.md) › "Known Limitations").
Additionally, at portfolio scale: discovery/assessment across many repos can be long-running (monitor,
don't block); and a job parked after assessment awaiting the user's selection is expected — surface
the pending selection/plan review panel rather than reporting the phase as stuck.
