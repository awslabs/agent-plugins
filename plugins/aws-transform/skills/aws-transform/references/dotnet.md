# .NET Modernization

> **Last Updated:** 2026-05-13

## Table of Contents

- [Capabilities](#capabilities)
- [Agents & Transforms](#agents--transforms)
- [Decision Points](#decision-points)
  - [Target Version](#target-version)
  - [Transformation Mode](#transformation-mode)
  - [Source Code Upload](#source-code-upload)
  - [Confirm & Launch](#confirm--launch)
  - [Per-Project Review Toggles](#per-project-review-toggles-interactive-mode-only)
- [Status Check](#status-check)
- [Workflow (11 Steps)](#workflow-11-steps)
  - [Verify Authentication](#verify-authentication)
  - [Create or Reuse Workspace](#create-or-reuse-workspace)
  - [Collect User Choices](#collect-user-choices)
  - [Create and Start Job](#create-and-start-job)
  - [Upload Source Code](#upload-source-code)
  - [Monitor Assessment](#monitor-assessment)
  - [Plan Approval](#plan-approval)
  - [Checkpoint Config](#checkpoint-config-interactive-mode-only)
  - [Monitor Transformation](#monitor-transformation)
  - [Local Build Verification (Auto-Skip)](#local-build-verification-auto-skip)
  - [Final Summary & Download](#final-summary--download)
- [Apply Transformation Changes](#apply-transformation-changes)
- [Handle Missing Packages](#handle-missing-packages)
- [Mode Behavior Reference](#mode-behavior-reference)
- [HITL Reference](#hitl-reference)
- [Artifacts Reference](#artifacts-reference)
- [Error Recovery](#error-recovery)
- [Known Limitations](#known-limitations)

---

## Capabilities

Modernize .NET applications to .NET 8, .NET 9, or .NET 10. Supports projects targeting .NET Framework (v2.0–v4.8), .NET Core (1.x–3.x), or .NET 5–7.

| Source                 | Target                               |
| ---------------------- | ------------------------------------ |
| .NET Framework 2.0–4.8 | .NET 8 or .NET 10                    |
| .NET Core 1.x–3.x      | .NET 8 or .NET 10                    |
| .NET 5–7               | .NET 8 or .NET 10                    |
| VB.NET (.vbproj)       | VB.NET on .NET 8 or .NET 10          |
| WPF (.NET Framework)   | WPF on .NET 8 or .NET 10             |
| Xamarin                | .NET MAUI                            |
| ASP.NET MVC 5          | ASP.NET Core                         |
| WCF Services           | gRPC or REST APIs                    |
| Web Forms              | Blazor or Razor Pages                |
| Entity Framework 6     | EF Core                              |
| Web.config             | appsettings.json                     |
| IIS deployment         | ECS Fargate / App Runner             |
| packages.config        | PackageReference (SDK-style .csproj) |

---

## Agents & Transforms

| User-Facing Name         | orchestratorAgent     | Purpose                                         |
| ------------------------ | --------------------- | ----------------------------------------------- |
| .NET Modernization Agent | `dotnet-chatty-agent` | .NET code assessment + transformation (primary) |

The .NET Modernization Agent handles both assessment AND transformation in a single job. There is no separate assessment agent.

In user-facing messages, refer to this as ".NET modernization agent" or "Managed Agent". Use `dotnet-chatty-agent` only in `create_job` tool calls — never in chat prose.

---

## Decision Points

All user-facing questions. Ask in this order: version → mode → source code → per-project toggles.

### Target Version

| Target  | TFM       | Support                   | Notes                                   |
| ------- | --------- | ------------------------- | --------------------------------------- |
| .NET 10 | `net10.0` | LTS (Nov 2025 – Nov 2028) | Latest LTS, newest APIs and performance |
| .NET 9  | `net9.0`  | STS (Nov 2024 – May 2026) | Latest features, shorter support window |
| .NET 8  | `net8.0`  | LTS (Nov 2023 – Nov 2026) | Stable, widely adopted                  |

MUST present all versions as explicit options. Mark .NET 10 as "(Recommended)". Default to .NET 10 if user has no preference.

Present options to the user and wait for their selection:

| Option                | Description                                                   | Value Mapping                  |
| --------------------- | ------------------------------------------------------------- | ------------------------------ |
| .NET 10 (Recommended) | LTS until Nov 2028. Latest APIs and performance improvements. | `target_framework = "net10.0"` |
| .NET 9                | STS until May 2026. Latest features, shorter support window.  | `target_framework = "net9.0"`  |
| .NET 8                | LTS until Nov 2026. Stable, widely adopted.                   | `target_framework = "net8.0"`  |

### Transformation Mode

Exactly TWO modes exist. No other modes exist.

| Mode        | Value         | Behavior                                                                                                                                                                                                                                                      | Best For                         |
| ----------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| Auto        | `auto`        | Runs to completion without pausing. Failures logged and skipped. Transformations are applied to your code during status checks. Best for low-complexity projects resolvable mostly by package version upgrades.                                               | Simple projects, small solutions |
| Interactive | `interactive` | Pauses after each project for review. Plan approval required. Approved changes are applied to your code. Users can optionally configure project checkpoints to review the transformation and iterate in chat for addressing feedback and any residual errors. | Medium and complex applications  |

Present options to the user and wait for their selection:

| Option                                 | Description                                                                                                                                     | Value Mapping                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| Auto (Recommended for simple projects) | Runs to completion without pausing. Transformations are applied to your code during status checks. Failures logged and skipped. Fast.           | `interactive_mode = "auto"`        |
| Interactive                            | Pauses after each project for your review. Approved changes are applied to your code. You can inspect diffs, request changes, or skip projects. | `interactive_mode = "interactive"` |

Default to `auto` if user has no preference.

After the user selects a mode, inform them: "You can switch between auto and interactive mode at any time during the transformation — just ask."

### Source Code Upload

Present options to the user and wait for their selection:

| Option                | Description                                            |
| --------------------- | ------------------------------------------------------ |
| Upload from workspace | Zip and upload the solution from the current workspace |
| Specify a path        | User provides the path to the solution                 |

MUST ask before uploading. MUST NOT auto-upload.

### Confirm & Launch

After collecting target version and mode, present a summary of the user's selections and ask for confirmation before creating the job. No backend APIs have been called yet — this is the user's last chance to adjust.

Present options to the user and wait for their selection:

| Option              | Description            |
| ------------------- | ---------------------- |
| Go ahead            | Start the migration    |
| Wait, let me adjust | Change something first |

The plan presented above the question MUST include these steps:

1. Create a new workspace (or reuse existing)
2. Create a job with the .NET modernization agent (target: `<version>`, mode: `<mode>`)
3. Upload your source code
4. Agent assesses your solution, produces an assessment report, and generates a migration plan before starting the transformation
5. Once transformation completes, you receive the migrated source code and a summary of changes

If user selects "Wait, let me adjust" — return to the relevant decision point (version or mode) and re-collect the choice. No backend APIs have been called yet, so this is a local loop with no side effects.

### Per-Project Review Toggles (Interactive Mode Only)

Presented after plan approval. Projects default to "review enabled" — user deselects what they want to skip.

Present a multi-select list of projects from the plan. Each option shows the project name and complexity. All are selected by default — user deselects any they want to skip review for.

| Option Pattern  | Description                          |
| --------------- | ------------------------------------ |
| `<ProjectName>` | `<complexity> — <brief description>` |

---

## Status Check

When the user asks for status, progress, or "what's happening" — use this procedure regardless of which workflow step is active:

1. `get_resource(resource="job", workspaceId=..., jobId=...)` → get job status + `_pollingGuidance` + `recentWorklogs`
2. `list_resources(resource="tasks", workspaceId=..., jobId=...)` → any pending HITL tasks?
3. Check the **latest agent message** in the response — if it asks a question or presents options (continue/retry/skip/approve), the orchestrator is waiting for a `send_message` response. Present those options to the user.

**Present the full picture:**

- Current phase and status
- What the agent last did (from worklogs)
- Any pending actions needed from user (HITL tasks OR agent message asking a question)
- What's coming next

**Rules:**

- **AUTO mode:** Call `list_resources(resource="artifacts", pathPrefix="...Generated Outputs/")` to check for new diff artifacts (`fileType: "ZIP"` with `planStepId != "default"`). If found, trigger the Apply Transformation Changes procedure for each completed project before reporting status.
- If `_pollingGuidance.hasPendingTasks=true` → check tasks, present to user
- If `_pollingGuidance.isTerminal=true` → job done, present final summary
- If latest agent message asks a question → present it to user, orchestrator is waiting
- If no pending tasks AND no questions AND job is EXECUTING → inform user the agent is working, no action needed

---

## Workflow (11 Steps)

The full lifecycle of a .NET modernization job.

### Verify Authentication

```python
get_status()
```

If not authenticated, guide user through `configure()`. Do not proceed until auth is confirmed.

### Create or Reuse Workspace

```python
create_workspace(name="dotnet-modernization", description="Modernize .NET Framework solution to <target>")
```

Save `workspaceId`. If user has a workspace from a previous session (check `.atx/context.json`), offer to reuse it instead of creating a new one. Users can create multiple jobs within the same workspace.

### Collect User Choices

MUST ask version FIRST, mode SECOND. MUST store exact values before calling `create_job`.

1. Ask target version → store `target_framework` ("net10.0", "net9.0", or "net8.0")
2. Ask transformation mode → store `interactive_mode` ("auto" or "interactive")

See [Decision Points](#decision-points) for the exact formats and value mappings.

### Create and Start Job

Build `objective` as a JSON string from collected values:

```python
# Examples:
objective_json = '{"target_framework": "net10.0", "interactive_mode": "interactive"}'
objective_json = '{"target_framework": "net8.0", "interactive_mode": "auto"}'
```

Call `create_job`:

```python
create_job(
  workspaceId="<workspace-id>",
  jobName=".NET Assessment & Modernization",
  objective=objective_json,   # MUST be valid JSON, not prose
  intent="LANGUAGE_UPGRADE",
  orchestratorAgent="dotnet-chatty-agent"
)
```

Save `jobId`. The backend parses `objective` as JSON — if it receives prose, parsing fails silently and defaults to `auto` + `net10.0`.

Immediately after:

```python
load_instructions(workspaceId="<workspace-id>", jobId="<job-id>")

send_message(
  workspaceId="<workspace-id>",
  jobId="<job-id>",
  text="Target: <target> (<tfm>). Mode: <mode>. Source code will be uploaded shortly."
)
```

`load_instructions` gates all job-scoped tools — MUST be called once per job.

### Upload Source Code

Ask user first (see [Decision Points: Source Code Upload](#source-code-upload)). Then:

```python
# Zip (exclude .git, bin, obj, packages)
upload_artifact(
  workspaceId="<workspace-id>", jobId="<job-id>",
  content="/tmp/source.zip", fileType="ZIP",
  categoryType="CUSTOMER_INPUT", fileName="source.zip"
)

# Notify agent
send_message(workspaceId="<workspace-id>", jobId="<job-id>",
  text="Source code uploaded (artifact ID: <id>). Please proceed with assessment.")
```

Save the user's source path to `.atx/context.json` as `source_root`. This is needed later to apply transformation changes to the correct location.

### Monitor Assessment

The agent assesses the solution automatically. On user check-in:

```python
get_resource(resource="job", workspaceId="<workspace-id>", jobId="<job-id>")
```

Report status, any available artifacts (Assessment_Report.md, Modernization_Plan.md), and pending tasks.

Use `_pollingGuidance` from the response:

- `hasPendingTasks=true` → check for BLOCKING tasks
- `isTerminal=true` → job done

If `list_resources(resource="tasks")` returns a task with tag `missing-packages`, follow the Handle Missing Packages procedure. Transformation will not proceed until resolved.

### Plan Approval

**AUTO mode:** Skipped. Agent proceeds directly to transformation.

**INTERACTIVE mode:**

The backend orchestrator WAITS for user approval before starting transformation. It will NOT proceed on its own. You MUST detect the plan and get user approval.

**How to detect "plan ready":** Job status is `PLANNING` AND `Modernization_Plan.md` artifact exists. The status stays `PLANNING` until the user approves — it only moves to `PLANNED` after approval.

**Do NOT trust the chatter's response** — it may say "I'm proceeding" or "preparing to begin" but the orchestrator is actually paused waiting for your `send_message` approval.

Flow:

1. Detect plan is ready (artifact or worklog signal)
2. Present plan summary to user (from the agent's messages or assessment data)
3. Ask user to approve
4. Send approval:

```python
send_message(workspaceId="<workspace-id>", jobId="<job-id>",
  text="User approves the migration plan. Please proceed with transformation.")
```

Only after this `send_message` will the backend start transforming projects.

After confirming approval to the user, also inform them: "You can switch between auto and interactive mode, or select/deselect which projects to review, at any time during the transformation — just ask."

**AUTO mode:** Plan approval is skipped, but still inform the user when first reporting transformation progress that they can switch modes or enable per-project review at any time.

### Checkpoint Config (Interactive Mode Only)

Skip this step entirely in AUTO mode.

After plan approval, extract project step_ids from the plan and present per-project toggles:

**8a. Get plan and find project steps:**

```python
get_resource(resource="plan", workspaceId="<id>", jobId="<id>")
# Find steps where parentStepId matches "Transform Projects" step
# These are per-project steps with stepId and stepName
```

**8b. Find checkpoint config task ID:**

```python
list_resources(resource="tasks", workspaceId="<id>", jobId="<id>")
# Find task where tag ends with "-checkpoint"
```

**8c. Present per-project toggles to user** (see [Decision Points: Per-Project Review Toggles](#per-project-review-toggles-interactive-mode-only))

**8d. Submit user's choices:**

```python
complete_task(
  workspaceId="<workspace-id>", jobId="<job-id>",
  taskId="<checkpoint-task-id>",
  content='{"interactive_mode": "interactive", "<step_id_1>": true, "<step_id_2>": false, ...}',
  action="SAVE_DRAFT"
)
```

Use `SAVE_DRAFT` (not `APPROVE`) for checkpoint config — this keeps the task open so it can be updated again later. The backend reads the humanArtifact regardless of task status.

Rules:

- Step IDs come from plan (`steps[].stepId` where parent is "Transform Projects")
- `true` = pause for review; `false` = skip review
- MUST include ALL project step_ids — omitted ones default to `false`
- MUST include `interactive_mode` in every submission
- The HITL does not close — can be updated anytime

**8e. Save to `.atx/checkpoint-config.json`:**

```json
{
  "checkpointTaskId": "<task-id>",
  "mode": "interactive",
  "projects": {
    "<step_id>": { "label": "<ProjectName>", "review": true }
  },
  "lastUpdated": "<ISO timestamp>"
}
```

On conversation resume, check this file first — reuse stored mapping instead of re-asking.

**Mid-run updates:** When user asks to switch mode or change toggles:

1. Read `.atx/checkpoint-config.json`
2. Update values per user's request
3. Save updated file
4. Call `complete_task` with values from saved file, using `action="SAVE_DRAFT"`

A `send_message` alone does NOT change the mode — only `complete_task` (with `SAVE_DRAFT`) on the checkpoint HITL changes backend behavior.

### Monitor Transformation

The agent transforms each project in dependency order (convert → upgrade packages → fix errors → checkpoint).

Status progression: `PLANNING` → `PLANNED` → `EXECUTING` → `COMPLETED`

Terminal states: `STOPPED`, `FAILED`

**INTERACTIVE mode — when Project Review HITL appears:**

1. Inform user which project completed + summary
2. Present options to the user:

   | Option            | Description                                                           |
   | ----------------- | --------------------------------------------------------------------- |
   | Approve           | Apply transformation to the project and continue to the next project. |
   | Download the diff | Inspect the exact file changes before deciding.                       |
   | Reject            | Skip this project's transformation. Local code is not modified.       |

3. If user approves, state which project you are approving before calling `complete_task`
4. Submit decision:

   ```python
   complete_task(workspaceId="<id>", jobId="<id>", taskId="<review-task-id>",
     content='{}', action="APPROVE")
   ```

5. Immediately send follow-up:

   ```python
   send_message(workspaceId="<id>", jobId="<id>",
     text="Review approved for <project>. Please continue with transformation.")
   ```

6. Apply transformation changes (see [Apply Transformation Changes](#apply-transformation-changes) section).

**AUTO mode:** No review tasks appear. Transformation changes are applied when the user checks status (see [Status Check](#status-check) and [Apply Transformation Changes](#apply-transformation-changes) sections).

### Local Build Verification (Auto-Skip)

After all projects transform, a build verification HITL appears (BLOCKING, tag: `local-build-verification`). This applies to both auto and interactive modes.

Auto-complete this HITL immediately with a skip response. The user does not need to approve — this workflow handles it silently. After auto-completing, inform the user: "Local build verification is optional and has been skipped. You can always run `dotnet build` on the migrated code yourself after downloading. If you encounter build errors, you can ask me to help fix them."

```python
complete_task(workspaceId="<id>", jobId="<id>", taskId="<build-task-id>",
  content='{"status": "SUCCESS", "errorCount": 0, "errors": [], "rawOutput": "Build verification skipped."}',
  action="APPROVE")

send_message(workspaceId="<id>", jobId="<id>",
  text="Build verification skipped. Please proceed with next steps.")
```

**Detection:** When `list_resources(resource="tasks")` returns a task with tag `local-build-verification`, auto-complete it using the pattern above. This includes detection during status checks — if the user asks for status and a `local-build-verification` HITL is pending, auto-complete it first, then report progress.

If the backend creates additional build verification rounds (after agent-side fixes), auto-complete each round the same way.

### Final Summary & Download

After build verification, the agent generates final artifacts (report, next steps, migrated source ZIP) and sends a message asking whether to mark the job as complete. The job remains in EXECUTING until a confirmation is sent via `send_message`.

When the agent's message indicates transformation is complete and artifacts are ready:

1. List output artifacts: `list_resources(resource="artifacts")`
2. Present a summary to the user:
   - Projects transformed (count, names, status)
   - Per-project diff ZIPs — list each with project name and artifact ID. These contain `metadata.json`, `diffs/*.diff`, `before/*`, and `after/*` so the user can review exactly what changed per project. Identify them by label `checkpoint-diff-{project-name}`.
   - Transformation report available (`Transformation_Report.html` — detailed HTML report)
   - Next steps available (`NextSteps.md` — recommended post-migration actions)
   - Final migrated source available (`*_Transformed_*.zip` — complete migrated solution)
3. Present options to the user and wait for their selection:

   | Option           | Description                                  |
   | ---------------- | -------------------------------------------- |
   | Complete the job | Mark the job as done and download artifacts  |
   | Make adjustments | Request additional changes before completing |

4. Based on user's choice:

   ```python
   # User confirms completion:
   send_message(workspaceId="<id>", jobId="<id>",
     text="Looks good, mark the job as complete.")

   # User wants adjustments — relay their request:
   send_message(workspaceId="<id>", jobId="<id>",
     text="<user's adjustment request>")
   # Agent will handle the request, then ask again — repeat this step.
   ```

5. Once job reaches `COMPLETED`, download any artifacts the user requests:

   ```python
   get_resource(resource="artifact", workspaceId="<id>", jobId="<id>",
     artifactId="<id>", savePath=".atx/<filename>")
   ```

6. Update `.atx/context.json` with `phase: "complete"`

---

## Apply Transformation Changes

Apply transformed code from per-project diff artifacts to the user's local filesystem. Triggered when a project's transformation completes and the user interacts.

**Trigger conditions:**

- **AUTO mode:** When the user checks status and projects have completed transformation, trigger the Apply Transformation Changes procedure for each completed project
- **INTERACTIVE mode:** After the user approves the project review HITL
- MUST NOT apply if the user rejected the project in interactive mode

**First-time consent (both modes):** Before applying changes for the first time, inform the user:

"I'll apply the transformed code to your local codebase as each project completes. Any modifications you made since uploading will be overwritten for the affected projects. If you have git initialized, the changes will appear as unstaged modifications you can review or discard."

In AUTO mode, ask for confirmation before proceeding. In INTERACTIVE mode, the user's approval of the project review HITL serves as consent.

### Procedure

**1. Find the latest diff artifact for the project:**

```python
# First call returns folder paths
list_resources(resource="artifacts", workspaceId="<id>", jobId="<id>")
# Response contains folders[] — use the "Generated Outputs/" path as pathPrefix

# Second call with pathPrefix returns actual artifacts
list_resources(resource="artifacts", workspaceId="<id>", jobId="<id>",
  pathPrefix="AWSTransform/Workspaces/<workspaceId>/Jobs/<jobId>/Generated Outputs/")
# Per-project diff artifacts are identified by:
#   - fileType == "ZIP"
#   - planStepId != "default"
# Match artifact.planStepId to plan step.stepId to determine which project it belongs to.
# If multiple artifacts share the same planStepId (retries), pick the one with the latest artifactCreatedTimestamp.
```

**2. Download the diff ZIP:**

```python
get_resource(resource="artifact", workspaceId="<id>", jobId="<id>",
  artifactId="<latest-diff-artifact-id>",
  savePath=".atx/diffs/<jobId>/checkpoint-diff-<project-name>.zip")
```

**3. Extract the ZIP and read `metadata.json`:**

```json
{
  "filesAdded": ["path/to/NewFile.cs"],
  "filesUpdated": ["path/to/Modified.csproj"],
  "filesRemoved": ["path/to/Deleted.cs"]
}
```

**4. Write files to the user's local codebase:**

The `source_root` is the path the user provided during Source Code Upload, stored in `.atx/context.json`.

| Action     | Source                            | Destination                   |
| ---------- | --------------------------------- | ----------------------------- |
| Update/Add | `after/{path}` from extracted ZIP | `{source_root}/{path}`        |
| Remove     | —                                 | Delete `{source_root}/{path}` |

MUST use the agent's native file-write capability. Do NOT use `git apply`, `patch`, or any OS-specific command. This ensures cross-platform compatibility (Windows, macOS, Linux).

MUST create parent directories if they do not exist when writing new files.

MUST preserve file encoding from the `after/` content (write bytes as-is).

**5. Confirm to user:**

```
✅ Applied transformation for <project-name>:
   • <N> files updated
   • <N> files added
   • <N> files removed
```

### Rules

- MUST apply project-by-project as each completes — do NOT wait until all projects finish
- MUST use the latest diff artifact when multiple exist (highest `createdAt`)
- MUST preserve file encoding from the `after/` content (write bytes as-is)
- If a file in `filesUpdated` does not exist locally, treat it as an add
- If a file in `filesRemoved` does not exist locally, skip silently
- If download or extraction fails, inform the user and offer to retry

---

## Handle Missing Packages

When the agent detects private or unavailable NuGet packages during assessment, a BLOCKING HITL task appears. Transformation will not proceed until resolved.

**Detection:** `list_resources(resource="tasks")` returns a task with tag `missing-packages` and `uxComponentId: "DotnetMissingPackages"`.

**Procedure:**

1. Get task details to see which packages are missing:

   ```python
   get_resource(resource="task", workspaceId="<id>", jobId="<id>", taskId="<task-id>")
   ```

2. Present to user: "The following NuGet packages could not be found on public feeds: [list]. Please provide the .nupkg files, or let me know if any can be removed."

3. For each .nupkg file the user provides, upload it:

   ```python
   complete_task(workspaceId="<id>", jobId="<id>", taskId="<task-id>",
     filePath="/path/to/Package.1.0.0.nupkg",
     action="SAVE_DRAFT")
   # Returns uploadedArtifactId — save this for the final submission
   ```

4. After all packages are uploaded, submit the final response with all artifact IDs:

   ```python
   complete_task(workspaceId="<id>", jobId="<id>", taskId="<task-id>",
     content='{"uploadedArtifactIds": [{"artifactId": "<id1>", "name": "Package1.nupkg", "lastModified": 0, "size": 0}, {"artifactId": "<id2>", "name": "Package2.nupkg", "lastModified": 0, "size": 0}]}',
     action="APPROVE")
   ```

5. If user wants to remove a package from the missing list instead of uploading:

   ```python
   complete_task(workspaceId="<id>", jobId="<id>", taskId="<task-id>",
     content='{"removedPackages": [{"name": "PackageName", "version": "1.0.0"}]}',
     action="APPROVE")
   ```

**Rules:**

- MUST collect all `uploadedArtifactId` values from each `SAVE_DRAFT` call for the final `APPROVE` submission
- User uploads are stored under `CUSTOMER_INPUT` category
- If only one package is missing, a single `complete_task` with `filePath` + `action="APPROVE"` is sufficient
- Transformation remains blocked until this HITL is resolved

**Upload packages anytime (outside the HITL):**

If the user wants to upload private packages at any point during the job (e.g., after the HITL closes, or when a build fails due to a missing package):

```python
upload_artifact(workspaceId="<id>", jobId="<id>",
  content="/path/to/Package.nupkg", fileType="ZIP",
  categoryType="CUSTOMER_INPUT", fileName="Package.1.0.0.nupkg")

send_message(workspaceId="<id>", jobId="<id>",
  text="I uploaded the private package Package.1.0.0.nupkg. Please add it to the local feed and retry.")
```

The agent checks CUSTOMER_INPUT artifacts, adds the package to the local feed, and resumes.

---

## Mode Behavior Reference

| Phase                        | AUTO                                        | INTERACTIVE                            |
| ---------------------------- | ------------------------------------------- | -------------------------------------- |
| Plan approval                | Skipped                                     | Required (via send_message)            |
| Checkpoint config            | Ignore                                      | Present per-project toggles — optional |
| Per-project review           | No HITLs created                            | HITL per toggled-on project — optional |
| Apply transformation changes | On status check, for each completed project | After user approves project review     |
| On project failure           | Log + skip + continue                       | Present to user, wait for decision     |
| Build verification           | Auto-skip                                   | Auto-skip                              |
| Missing Packages             | Present to user (BLOCKING)                  | Present to user (BLOCKING)             |
| Final diffs                  | All at end                                  | Per-project during + all at end        |

---

## HITL Reference

| HITL Type                | Component ID             | Tag                        | Blocking     | Behavior                                                |
| ------------------------ | ------------------------ | -------------------------- | ------------ | ------------------------------------------------------- |
| Checkpoint Config        | `FileUploadV2`           | `*-checkpoint`             | NON_BLOCKING | AUTO: ignore. INTERACTIVE: Checkpoint Config step.      |
| Project Review           | `DotnetReviewAndConfirm` | `*-review`                 | NON_BLOCKING | INTERACTIVE only. Present diffs, wait for decision.     |
| Missing Packages         | `DotnetMissingPackages`  | `missing-packages`         | BLOCKING     | Both modes. Always present to user. Severity: CRITICAL. |
| Local Build Verification | `FileUploadV2`           | `local-build-verification` | BLOCKING     | Both modes. Auto-skip with dummy SUCCESS.               |

Processing pattern for any HITL:

1. `list_resources(resource="tasks")` → discover pending tasks
2. `get_resource(resource="task", taskId=...)` → get full details (read `_outputSchema`, `_responseHint`)
3. Present to user
4. Show payload before submitting
5. `complete_task(content=..., action="APPROVE")` → submit

There is NO Assessment Review HITL. Plan approval uses `send_message`.

---

## Artifacts Reference

| Type                                                 | Category          | Contains                                                  |
| ---------------------------------------------------- | ----------------- | --------------------------------------------------------- |
| Source code ZIP                                      | `CUSTOMER_INPUT`  | User's original .NET solution                             |
| Assessment report (`Assessment_Report.md`)           | `CUSTOMER_OUTPUT` | Complexity scores, dependency analysis                    |
| Modernization plan (`Modernization_Plan.md`)         | `CUSTOMER_OUTPUT` | Migration plan with project ordering                      |
| Per-project diff ZIP                                 | `CUSTOMER_OUTPUT` | `metadata.json` + `diffs/*.diff` + `before/*` + `after/*` |
| Final migrated source ZIP (`*_Transformed_*.zip`)    | `CUSTOMER_OUTPUT` | Complete migrated solution after all projects transform   |
| Transformation report (`Transformation_Report.html`) | `CUSTOMER_OUTPUT` | HTML summary of all transformations performed             |
| Next steps (`NextSteps.md`)                          | `CUSTOMER_OUTPUT` | Recommended post-migration actions                        |

Per-project diff ZIPs have `label: "checkpoint-diff-{project-name}"`.

The final migrated source ZIP, Transformation_Report.html, and NextSteps.md appear after build verification completes (job near completion).

Upload rules:

- Use `categoryType: "CUSTOMER_INPUT"` for source code
- Exclude `.git/`, `bin/`, `obj/`, `packages/` from ZIP
- Notify agent via `send_message` after upload with artifact ID

When multiple artifacts of the same type exist (e.g., multiple diff ZIPs from retries or re-runs), always use the most recent one. Sort by creation timestamp and pick the latest.

---

## Error Recovery

```
Job not progressing?
├─ Check tasks → pending HITL? → present to user
├─ Check messages → agent asked something? → respond via send_message
├─ Check job status → FAILED? → offer restart or new job
├─ Send status query → agent responds? → continue
└─ None of above → offer restart
```

Key actions:

- **Job creation fails:** Retry. If repeated, check auth and workspace.
- **Upload fails:** Check file size, verify ZIP, retry.
- **Job stuck:** Send status query via `send_message`. Check for hidden HITL tasks.
- **Task or project fails:** Ask the agent to retry the failed task in chat via `send_message`. The agent can re-attempt the transformation for that project.
- **Restart:** `control_job(action="stop")` then `control_job(action="start")`. Previously uploaded artifacts remain available.
- **Delete and start over:** `delete_job()` then new `create_job()`.

---

## Known Limitations

- COM interop references require manual replacement
- P/Invoke (native Windows DLL calls) need manual porting
- Web Forms → Blazor conversion is partial — complex controls may need redesign
- Windows Services → need manual conversion to BackgroundService
- GAC dependencies must be replaced with NuGet packages manually
