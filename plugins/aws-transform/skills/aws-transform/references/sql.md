# SQL Database Migration

> **Last Updated:** 2026-04-13

## Capabilities

This domain handles **SQL database migration via the IDE** using the AWS Transform MCP server. It supports two workflows:

1. **From-Scratch Workflow** — Start a new AWS Transform conversion job entirely from the IDE: authenticate, create a workspace/job, upload source SQL, monitor the conversion, review assessment results, and retrieve converted artifacts.
2. **Handoff Workflow** — Pick up where an AWS Transform conversion job left off: download converted artifacts and the validation report, then interactively fix all critical and high-severity issues the AWS Transform agent could not fully resolve.

Both workflows converge at the fix-application phase once converted artifacts and a validation report are available.

```
From-Scratch Workflow                    Handoff Workflow
┌──────────────────────────┐            ┌──────────────────────────┐
│ 1. Authenticate          │            │ 1. Collect job IDs       │
│ 2. Create workspace/job  │            │ 2. Download artifacts    │
│ 3. Upload source SQL     │            └───────────┬──────────────┘
│ 4. Monitor conversion    │                        │
│ 5. Read assessment       │                        │
│ 6. Trigger schema conv.  │                        │
│ 7. Retrieve artifacts    │                        │
└───────────┬──────────────┘                        │
            │         ┌─────────────────────────────┘
            ▼         ▼
┌──────────────────────────────────────────────────┐
│ Common: Parse report → Fix critical/high issues  │
│         → Validate → Upload → Deploy             │
└──────────────────────────────────────────────────┘
```

## ⚠️ Agent Behavior Rules (READ FIRST)

These rules are MANDATORY. Violating any of them is a failure.

> **Cross-platform note.** Commands below are given in two variants where they differ: **macOS/Linux/Git Bash** (POSIX shell: `cp`, `sed`, `perl`, etc.) and **Windows (PowerShell)**. Detect the OS and pick one variant — do not mix. In all PowerShell examples, paths are written with forward slashes (`/`) for readability; PowerShell accepts `/` and `\` interchangeably, so real Windows paths like `C:\Users\alice\work` can be used verbatim without re-quoting.

1. **Three-file workflow.** Keep the original source MSSQL file, the converted PG file (untouched), and a working copy of the converted PG file. ALL edits go to the working copy. NEVER modify the original source or the converted PG file.
2. **Navigate before AND after every fix. Skipping navigation is a rule violation.**
   - Detect the IDE from the environment: Kiro → `kiro --goto`, VS Code → `code --goto`, DBeaver → manual navigation.
   - **Before showing a fix**, open the file at the exact line that will change:

     ```
     code --goto <working_copy>:<line_number>
     ```

   - **After applying a fix**, navigate back to the changed line so the user sees the result:

     ```
     code --goto <working_copy>:<line_number>
     ```

3. **For every fix, follow this exact sequence:**
   a. **Navigate** to the line (rule 2 above). Do NOT skip this.
   b. **Validate the proposed fix** — Before showing the fix to the user, execute a syntax check (e.g., `EXPLAIN` or parse-only) on the proposed SQL block. If invalid, revise and re-validate. Do NOT propose an invalid fix.
   c. **Show in chat:** object name, line number, problem (from report), proposed before/after fix, and syntax validation result (✅ Passed).
   d. **Ask** `Approve this fix? [Yes / No / Modify]` and **STOP**. Do NOT proceed until the user responds.
   e. **After user approves**, apply the fix using `execute_bash` (NOT `fs_write`). Use `sed -i ''` or `perl -i -pe 's/old/new/g'` on macOS/Linux (Perl works cross-platform when available). On Windows without Git Bash, use PowerShell's literal-string `.Replace()` method (NOT `-replace`, which is a regex operator and will silently mis-match SQL tokens containing regex metacharacters like `[ ] . ( ) $ ^`). Write with `[System.IO.File]::WriteAllLines` and an explicit no-BOM UTF-8 encoding — `Set-Content -Encoding UTF8` on Windows PowerShell 5.1 prepends a UTF-8 BOM (`0xEF 0xBB 0xBF`) that Rule 10's ASCII verification step will flag. Wrap the `-Command` argument in **single quotes** so bash/Git Bash does not expand `$c` / `$false` before PowerShell parses them, and prepend `$ErrorActionPreference='Stop'` so intermediate failures surface instead of silently producing an empty working copy:

   ```
   powershell -Command '$ErrorActionPreference="Stop"; $c = (Get-Content "<working_copy>" -Encoding UTF8).Replace("old","new"); [System.IO.File]::WriteAllLines("<working_copy>", $c, [System.Text.UTF8Encoding]::new($false))'
   ```

   If regex matching is actually required, use `-replace [regex]::Escape("old"),"new"`. Note: `-replace`'s replacement string interprets `$1`, `$2`, `$$`, `$&`, etc. as regex substitution tokens, so if the replacement text contains literal `$` characters (common in PostgreSQL dollar-quoting like `$$`, `$BODY$`), double them: `-replace [regex]::Escape("old"), "new".Replace("$","$$")`.
   f. **Navigate back** to the changed line (rule 2 above). Do NOT skip this.
4. **Diff after every cluster.** After completing all fixes in a cluster, show a three-way diff comparing the original source MSSQL, the converted PG file, and the working copy.

   **Empty-diff guard (used by every IDE branch below):** Before showing the second diff (converted PG vs working copy), check whether the two files are identical. If they are, skip the second diff and tell the user: "No fixes have been applied yet — the converted PG file and working copy are still identical."
   - macOS/Linux/Git Bash: `diff --brief <converted_pg> <working_copy>` (exit 0 = identical)
   - Windows (PowerShell): `powershell -Command "if ((Get-FileHash '<converted_pg>').Hash -eq (Get-FileHash '<working_copy>').Hash) { exit 0 } else { exit 1 }"` (exit 0 = identical)

   - **VS Code:** Open two diffs side by side:
     `code --diff <source_mssql> <converted_pg>`
     Only if the converted PG file and working copy differ (empty-diff guard above):
     `code --diff <converted_pg> <working_copy>`
   - **Kiro:** Open two diffs side by side:
     `kiro --diff <source_mssql> <converted_pg>`
     Only if the converted PG file and working copy differ (empty-diff guard above):
     `kiro --diff <converted_pg> <working_copy>`
   - **DBeaver:** Use the SQL Compare feature or an external diff tool
   - **Fallback:** If the IDE diff commands do not produce visible results, generate text-based diffs in chat.
     - macOS/Linux/Git Bash:
       `diff -u <source_mssql> <converted_pg>`
       Only if the converted PG file and working copy differ (empty-diff guard above):
       `diff -u <converted_pg> <working_copy>`
     - Windows (PowerShell): use `Compare-Object`:
       `powershell -Command "Compare-Object (Get-Content '<source_mssql>' -Encoding UTF8) (Get-Content '<converted_pg>' -Encoding UTF8)"`
       Only if the converted PG file and working copy differ (empty-diff guard above):
       `powershell -Command "Compare-Object (Get-Content '<converted_pg>' -Encoding UTF8) (Get-Content '<working_copy>' -Encoding UTF8)"`
       Note: `Compare-Object` output is a side-indicator list (`<=` for left-only, `=>` for right-only) rather than unified-diff format. Show the output to the user as-is — it conveys the same information in a different layout.
       If two diffs were shown, tell the user:
   > "Two diff views have been opened: one comparing the source MSSQL with the converted PG file (showing what the conversion changed), and one comparing the converted PG file with the working copy (showing what fixes have been applied). You may need to arrange the diff tabs side by side."
   > Then ask the user:
   > "Cluster fixes applied. Would you like to upload the working copy to AWS Transform for re-validation before proceeding to the next cluster? [Yes / No]"
   - If **Yes**: Prepare a ZIP artifact for re-validation:
     1. Create the staging directory:
        - macOS/Linux/Git Bash: `execute_bash: mkdir -p <working_directory>/zip_staging`
        - Windows (PowerShell): `execute_bash: powershell -Command "New-Item -ItemType Directory -Force -Path '<working_directory>/zip_staging'"`
     2. Copy the working copy as `postgres-completed-deployment.sql`:
        - macOS/Linux/Git Bash: `execute_bash: cp <working_copy> <working_directory>/zip_staging/postgres-completed-deployment.sql`
        - Windows (PowerShell): `execute_bash: powershell -Command "Copy-Item '<working_copy>' '<working_directory>/zip_staging/postgres-completed-deployment.sql'"`
     3. Copy the custom rules file(s) from the working directory:
        - macOS/Linux/Git Bash: `execute_bash: cp <working_directory>/<rule_file> <working_directory>/zip_staging/<rule_file>`
        - Windows (PowerShell): `execute_bash: powershell -Command "Copy-Item '<working_directory>/<rule_file>' '<working_directory>/zip_staging/<rule_file>'"`
     4. Create `manifest.json` in `zip_staging/` with database name, execution order (`file: "postgres-completed-deployment.sql"`, `type: "all"`, `object_count: <count of CREATE statements>`), and `"custom_rules"` listing the custom rules filenames
     5. Create ZIP:
        - macOS/Linux: `execute_bash: cd <working_directory>/zip_staging && rm -f ../IDE_CONVERTED_DB_ARTIFACT.zip && zip ../IDE_CONVERTED_DB_ARTIFACT.zip *`
        - Windows: `execute_bash: powershell -Command "Compress-Archive -Path '<working_directory>/zip_staging/*' -DestinationPath '<working_directory>/IDE_CONVERTED_DB_ARTIFACT.zip' -Force"`
     6. Clean up:
        - macOS/Linux/Git Bash: `execute_bash: rm -rf <working_directory>/zip_staging`
        - Windows (PowerShell): `execute_bash: powershell -Command "Remove-Item -Recurse -Force '<working_directory>/zip_staging'"`
     7. Upload via `upload_artifact` with `content="<working_directory>/IDE_CONVERTED_DB_ARTIFACT.zip"`, `fileName="IDE_CONVERTED_DB_ARTIFACT"`, `fileType="ZIP"`, `categoryType="CUSTOMER_INPUT"`.
     8. Send `send_message` with text "IDE agent completed all critical and high-severity fixes. Uploaded corrected file as IDE_CONVERTED_DB_ARTIFACT. Ready for re-validation through invoke_validation_after_ide with new artifact id:`<artifactId>`". Poll messages for "Validation complete", download new report, and present results. If new issues are found in this cluster, fix them before moving on.
   - If **No**: Proceed to the next cluster.
5. **No scripts.** Do NOT write Python, Bash, or any scripts to batch-process fixes.
6. **Use `sed`, `perl`, or PowerShell for file edits, NOT `fs_write`.** Large SQL files (10K+ lines) cause the editor to freeze when using `fs_write`. Use `execute_bash` to edit the working copy directly on disk:
   - macOS/Linux/Git Bash: `sed -i '' 's/old/new/g' <working_copy>` or `perl -i -pe 's/old/new/g' <working_copy>`
   - Windows (PowerShell): use the literal-string `.Replace()` method (NOT `-replace`, which is a regex operator). Read with `Get-Content -Encoding UTF8` to avoid Windows PowerShell 5.1's ANSI code-page corruption, and write with `[System.IO.File]::WriteAllLines` + no-BOM UTF-8 (NOT `Set-Content -Encoding UTF8`, which prepends a UTF-8 BOM on PS 5.1 that Rule 10's ASCII verification will flag). Wrap the `-Command` argument in **single quotes** so bash/Git Bash does not expand `$c` / `$false` before PowerShell parses them, and prepend `$ErrorActionPreference='Stop'` so intermediate failures surface instead of silently producing an empty working copy: `powershell -Command '$ErrorActionPreference="Stop"; $c = (Get-Content "<working_copy>" -Encoding UTF8).Replace("old","new"); [System.IO.File]::WriteAllLines("<working_copy>", $c, [System.Text.UTF8Encoding]::new($false))'`. Use `-replace [regex]::Escape("old"),"new"` only if regex matching is actually required; when using `-replace`, also double any literal `$` in the replacement string (`"new".Replace("$","$$")`) because `-replace` interprets `$1`, `$$`, etc. as regex substitution tokens — which silently corrupts PostgreSQL dollar-quoting like `$$` and `$BODY$`.
7. **No bulk operations.** Fix one object at a time.
8. **No invented fixes.** Only apply fixes described in the validation report.
9. **Report every fix in chat** with: object name, line number in working copy, problem (from report), proposed fix, and updated progress table.
10. **Encoding safety before upload.** Before creating a ZIP for upload, sanitize non-ASCII characters that can corrupt during ZIP packaging and cause the validator to fail with `total_checks: 0`.

**Sanitize and verify (cross-platform, using Perl):**

```
perl -i -CSD -pe "s/\x{2014}/--/g; s/\x{2013}/-/g; s/[\x{2018}\x{2019}]/'/g; s/[\x{201c}\x{201d}]/\"/g; s/\x{2026}/.../g; s/\x{a0}/ /g" <working_copy>
perl -ne 'if(/[^\x00-\x7F]/){print "$ARGV:$.: $_"; $f++} END{exit !$f}' <working_copy> || echo "Clean: ASCII only"
```

Perl is available on macOS and Linux by default, and on Windows via Git Bash.

**Windows alternative (PowerShell):**

```
powershell -Command "
  $text = [IO.File]::ReadAllText('<working_copy>', [Text.Encoding]::UTF8);
  $text = $text -replace '\u2014','--' -replace '\u2013','-' -replace '[\u2018\u2019]',\"'\" -replace '[\u201c\u201d]','\"' -replace '\u2026','...' -replace '\u00a0',' ';
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false;
  [IO.File]::WriteAllText('<working_copy>', $text, $utf8NoBom);
  if ($text -match '[^\x00-\x7F]') { Write-Host 'WARNING: non-ASCII characters remain' } else { Write-Host 'Clean: ASCII only' }
"
```

Common offenders: em-dash (`—`), en-dash (`–`), smart quotes (`""''`). These appear in MSSQL-generated comment headers and corrupt from UTF-8 to Windows-1252 `0x97` during ZIP packaging.

---

## From-Scratch Workflow

Use this workflow when starting a new MSSQL → PostgreSQL conversion entirely from the IDE. If you already have a completed AWS Transform job with artifacts, skip to the **Handoff Workflow** section.

### Step 1: Authentication

- **Cookie auth requires the Transform app URL** — Ask the user for their Transform app URL (e.g., `https://xxxxxxxx.transform.us-east-1.on.aws`).
- Do **not** use the SSO/IdC start URL (`https://d-xxx.awsapps.com/start`).
- If the auth cookie has expired, ask the user for a new one.

### Step 2: Create Workspace and Job

- **Unless the user explicitly says to create a new workspace/job, always ask first:**
  > "Do you have an existing AWS Transform workspace or job you'd like to reuse, or should I create new ones?"
- **If reusing an existing workspace:** List all available workspaces so the user can see names and IDs, then ask which one to use. Then ask if they also have an existing job to reuse or need a new job in that workspace.
- **If reusing an existing job:** List all jobs in the selected workspace so the user can see job names and IDs, then ask which one to use. Use artifact store tools to check what outputs the agent has already produced — the job may already be past the upload or assessment phase.
- **If creating a new workspace:** Names must match `[a-zA-Z0-9]+(?:[-_\.][a-zA-Z0-9]+)*` — no spaces allowed.
- **If creating a new job:** MSSQL to PostgreSQL conversion uses `WINDOWS_DATABASE` (SQL Server modernization) as the job type.
- **Always choose MSSQL file upload (NOT the connect-to-database option) after starting the job.**

### Step 3: SQL File Upload

- The source SQL file can be either a `.sql` file or a `.zip` archive containing SQL files. Both formats are accepted by AWS Transform. **Upload the file as-is — do NOT zip a `.sql` file before uploading.**
- If the ActiveFile is a mssql file, use that.
- If not, ask for user's permission and search locally for files — use `fileSearch` to find `.sql` or `.zip` files on the user's machine instead of asking for the full path.
- Upload the file as an artifact first using `upload_artifact`.
- Then send the artifact reference in chat using the URI format:

  ```
  aws-transform://workspaces/{workspaceId}/jobs/{jobId}/artifacts/{artifactId}
  ```

- **Don't send bare artifact IDs** — the agent won't recognize them. It needs the full `aws-transform://` URI.

### Step 4: Interacting with the Agent

- **Always use `send_message` as the primary form of communication with the job agent.**
- **Messages can have interaction buttons** — Agent messages include `SELECT` interactions with options. Respond by sending the option's `value` as a chat message.

### Step 5: Monitoring Job Progress

- The job is carried out by AWS Transform agents; all communication and updates are wired through them.
- **Always check all three**: messages, worklogs, and HITL tasks.
- **Worklogs** are the most granular progress indicator — they update more frequently than messages and show the agent's internal reasoning/actions step by step.
- **Messages** show user-facing interactions with SELECT options (e.g. "MSSQL to PostgreSQL", "Upload DDL files").
- **HITL tasks** may or may not appear — the agent can request input via chat messages instead.
- **No HITL tasks doesn't mean no input needed** — The job can be in `AWAITING_HUMAN_INPUT` with no HITL tasks; input is expected via chat messages.
- Jobs go through phases: `STARTING` → `PLANNING` → `AWAITING_HUMAN_INPUT` → active processing.
- The `input_setup` step handles file ingestion before moving to `discovery`.
- Planning can take a few minutes — no tasks or messages will appear until it completes.

**Polling loop (mandatory throughout the job lifecycle):**

After any action that triggers agent work (file upload, schema conversion, etc.), enter a polling loop:

1. Use **mcp-sleep** to wait 10 seconds.
2. Check messages, worklogs, and HITL tasks.
3. **Format timestamps** — Worklog and message timestamps may be returned as epoch milliseconds or numeric values (e.g., `140638`). Always convert these to human-readable format (e.g., `2026-04-13 21:06:38 UTC`) before displaying to the user.
4. If the agent sent a message requiring a response (SELECT options, questions, or `AWAITING_HUMAN_INPUT` status), respond or prompt the user.
5. If the agent is still processing (no new actionable messages), go back to step 1.
6. Continue polling until the current phase completes (e.g., assessment report is ready, schema conversion finishes, validation completes).

Do NOT stop polling prematurely — always keep the loop running until there is a clear completion signal or user input is needed.

### Step 6: Reading Assessment Results

- Download the assessment report zip artifact.
- Extract the zip file and review all contents — it typically contains PDF reports and CSV data files.
- **PDF reports:**
  - `assessment_summary.pdf` is a short document with a summary of the assessment.
  - The other report PDF is a longer document with detailed findings of migration issues with the database.
- **CSV files:** Contain structured data such as object inventories, issue lists, and migration action items. Read and present these to the user — they are useful for programmatic analysis and tracking.

### Step 7: Schema Conversion

- When the user is ready to proceed towards schema conversion, send this intent to the agent.
- **Custom transformation rules:** During conversion, the AWS Transform agent may ask about custom transformation rules. **Do NOT assume default rules.** Always ask the user:
  > "The conversion agent is asking about custom transformation rules. Do you have custom rules to upload, or should I proceed with default rules?"
  > Only proceed with defaults if the user explicitly confirms.
- Schema conversion is a long-running process — expect to poll for job progress (see Step 5).
- After the schema conversion report is available, review it with the user. **Do NOT skip ahead to downloading the converted PostgreSQL file** — it is not available yet.
- The converted PostgreSQL SQL file is only produced after the **target DB deployment workflow** completes. After reviewing the conversion report, continue interacting with the AWS Transform agent to proceed through the deployment workflow (see Step 8).

### Step 8: Target DB Deployment

- After schema conversion and report review, the AWS Transform agent will guide the workflow toward deploying the converted schema to the target PostgreSQL database.
- Continue polling and responding to the agent's messages through this phase (see Step 5).
- **Do NOT assume the user already has a target database cluster.** The deployment flow requires setting up a DB connector first.

**DB Connector Setup:**

The AWS Transform agent will issue a HITL task to set up a DB connector. Before creating a new one, check if the workspace already has a connector configured:

1. **List existing connectors** in the workspace first. If connectors exist, present them to the user:
   > "This workspace already has the following DB connector(s) configured:
   >
   > - `<connector name>` — `<connection details>`
   >
   > Would you like to use an existing connector, or set up a new one?"
2. **If the user picks an existing connector**, use that and skip connector creation.
3. **If a new connector is needed**, the HITL task will require details from the user. Ask for:
   - AWS Account ID
   - Any other connection parameters the HITL task requests (e.g., database endpoint, credentials, VPC details)

   Do NOT guess or assume any of these values — always ask the user.

- **The converted PostgreSQL SQL file (`ATX_CONVERTED_DB_ARTIFACT` or `postgres-completed-deployment.sql`) is only available as an artifact after the deployment workflow completes.** Do NOT attempt to download it before this point — it won't exist yet.
- Once deployment finishes, proceed to retrieve the artifacts (see Step 9).

### Step 9: Retrieving Conversion Artifacts

```
# List all artifacts from the completed AWS Transform job
list_resources resource="artifacts" workspaceId="<workspaceId>" jobId="<jobId>"
```

Scan the returned list for matching artifact names/labels. AWS Transform MCP does not support filtering by label — you must list all, then match.

- **Scan for converted database artifacts:** Look for all artifacts with `fileMetadata.path` starting with `ATX_CONVERTED_DB_ARTIFACT`. Each artifact represents a converted database, with the database name as the suffix: `ATX_CONVERTED_DB_ARTIFACT_<dbName>`.

  Extract the database names and present them to the user:
  > "Converted artifacts are available for **N** database(s):
  >
  > 1. `OrdersDB`
  > 2. `InventoryDB`
  > 3. `AuditDB`
  >
  > Which database would you like to work on?"

  Wait for the user to choose. Then download the selected artifact:

  ```
  get_resource resource="artifact" workspaceId="<workspaceId>" jobId="<jobId>" artifactId="<matched-id>" savePath="/local/path/ATX_CONVERTED_DB_ARTIFACT_<dbName>.zip"
  ```

  Extract the ZIP — contains: `sourcesql/`, `targetsql/`, `validationreport/`. Read `targetsql/manifest.json` to discover the converted SQL files and custom rules — file paths in the manifest are relative to `targetsql/`.

- **Fallback (single artifact):** If no `ATX_CONVERTED_DB_ARTIFACT_*` artifacts are found, look for a single `ATX_CONVERTED_DB_ARTIFACT` (no suffix) and use it directly.

- **Fallback (individual artifacts):** If no ZIP artifacts found, look for:
  - `postgres-completed-deployment.sql` → converted PG file
  - `Schema Conversion Report` → validation report
  - Then ask user for the source SQL file path

Once artifacts are retrieved, proceed to the **Common Workflow** section below.

---

## Handoff Workflow

Use this workflow when an AWS Transform conversion job has already completed and you need to pick up the remaining fixes in the IDE.

### Why IDE Handover

The IDE agent complements the AWS Transform agentic flow by providing capabilities that a managed batch pipeline cannot:

- **Interactive fixing** — Apply a fix, show the user the exact change, wait for approval or adjustment, then proceed.
- **Cross-object awareness** — The IDE has the full converted file open and can cross-reference across procedures, views, and tables while editing.
- **Granular human-in-the-loop** — Pause at every individual object for user approval instead of coarse-grained job checkpoints.
- **Local tooling** — Run PostgreSQL syntax validation locally, show diffs, and use language intelligence for SQL editing.
- **Long-tail remediation** — Remaining broken objects each have unique issues requiring case-by-case judgment.
- **Full transparency** — Every fix is reported in chat with what changed and why.

### What AWS Transform Handles vs What the IDE Agent Handles

| Responsibility                     | AWS Transform Transform Agent | IDE Agent (this steering)                     |
| ---------------------------------- | ----------------------------- | --------------------------------------------- |
| Schema conversion (DDL)            | ✅                            | —                                             |
| Bulk stored proc rewrite           | ✅                            | Fix remaining broken procs flagged in report  |
| Data type mapping                  | ✅                            | Fix type mapping violations flagged in report |
| View creation                      | ✅                            | Resolve failed views flagged in report        |
| Index migration                    | ✅                            | Re-create missing indexes flagged in report   |
| Validation report generation       | ✅                            | Parse and act on report                       |
| Critical/high-severity remediation | —                             | ✅                                            |
| Application code changes           | —                             | Out of scope (flag for user)                  |

### Step 1: Collect AWS Transform Job Context

Prompt user for AWS Transform job identifiers:

- `workspaceId` — The AWS Transform workspace where the conversion job ran
- `jobId` — The AWS Transform job that performed the MSSQL → PostgreSQL conversion
- `agentInstanceId` — The agent instance that produced the conversion artifacts

### Step 2: Retrieve Artifacts from AWS Transform

Once the user provides identifiers, list all job artifacts and match by name/label:

```
# List all artifacts
list_resources resource="artifacts" workspaceId="<workspaceId>" jobId="<jobId>"
```

- **Scan for converted database artifacts:** Look for all artifacts with `fileMetadata.path` starting with `ATX_CONVERTED_DB_ARTIFACT`. Each artifact represents a converted database: `ATX_CONVERTED_DB_ARTIFACT_<dbName>`.

  Extract the database names and present them:
  > "This job has converted artifacts for **N** database(s):
  >
  > 1. `OrdersDB`
  > 2. `InventoryDB`
  >
  > Which database would you like to fix?"

  Wait for the user to choose. Then download:

  ```
  get_resource resource="artifact" workspaceId="<workspaceId>" jobId="<jobId>" artifactId="<matched-id>" savePath="/local/path/ATX_CONVERTED_DB_ARTIFACT_<dbName>.zip"
  ```

  Extract the ZIP — contains: `sourcesql/`, `targetsql/`, `validationreport/`. Read `targetsql/manifest.json` to discover the converted SQL files and custom rules — file paths in the manifest are relative to `targetsql/`.

- **Fallback (single artifact):** If no `ATX_CONVERTED_DB_ARTIFACT_*` found, look for a single `ATX_CONVERTED_DB_ARTIFACT` (no suffix) and use it directly.

- **Fallback (individual artifacts):** If no ZIP artifacts found, scan for:
  - `postgres-completed-deployment.sql` → converted PG file
  - `Schema Conversion Report` → validation report
  - Ask user for the source SQL file separately

- **Fallback (no artifacts):** If no artifacts found or AWS Transform job not referenced, ask user for local file paths to:
  - Original source SQL file (T-SQL / SQL Server)
  - Converted PostgreSQL SQL file
  - Conversion validation report (HTML or text)

Once artifacts are retrieved, proceed to the **Common Workflow** section below.

---

## Common Workflow (Both Paths Converge Here)

Once you have the source SQL, converted PostgreSQL SQL, and validation report — regardless of whether you arrived via the from-scratch or handoff path — follow these steps.

### Step 1: Check PostgreSQL Extension

Verify the user has a PostgreSQL extension installed in their IDE. If not installed, ask:

> "A PostgreSQL extension is required to validate fixes before applying them. Please install one:
>
> - **VS Code:** Install `ms-ossdata.vscode-postgresql` or `ckolkman.vscode-postgres` from the Extensions marketplace
> - **Kiro:** Install the PostgreSQL extension from the Extensions panel
> - **DBeaver:** Built-in — no additional install needed
>
> Once installed, configure a connection profile for the target Aurora PostgreSQL cluster and let me know the profile name."

### Step 2: Set Fix Autonomy Mode

Ask the user:

> "How should I handle fix approvals?
>
> - **per-fix** (default) — I propose each fix and wait for your approval before applying it
> - **per-cluster** — I show proposed fixes for the first 2–3 issues in a cluster so you can review the approach, then apply all fixes in the cluster after your approval. A cluster diff is shown after applying.
> - **autonomous** — I apply all critical/high fixes end-to-end and present a full diff and summary at the end
>
> Choose [per-fix / per-cluster / autonomous]:"

Store the chosen mode for the session. The user can switch mid-session by saying e.g. `"Switch to per-cluster mode"`. Mode affects approval behavior:

- `per-fix` — Rule 2d (approval prompt before every fix) is enforced.
- `per-cluster` — Rule 2d is skipped. The agent shows proposed before/after fixes for the first 2–3 issues as a preview, asks for approval, then applies all fixes in the cluster. Rule 3 (cluster diff) is shown after applying.
- `autonomous` — Rules 2d and 3 approval prompts are skipped. Fixes are still logged in chat (Rule 8) and a final summary is shown.

### Step 3: Present Available Commands

Before starting fixes, inform the user:

> "Before we begin, here's what you can ask me to do at any time:
>
> - **Show diff** — Display a diff of all changes made so far (three-way diff of source MSSQL, converted PG, and working copy). The converted PG vs working copy diff is skipped if the files are still identical.
> - **Run validation** — Upload the working copy to AWS Transform for functional re-validation and get a new report
> - **Show progress** — Print the current progress table with cluster statuses
> - **Switch autonomy mode** — Change fix approval mode (per-fix / per-cluster / autonomous)
> - **Skip cluster** — Skip the current cluster and move to the next one
> - **Revert cluster** — Undo all fixes in the current cluster
> - **Fix a medium/low item** — Ask me to fix a specific advisory item
> - **I'm done** — End the session, upload the final file to AWS Transform, and optionally deploy
>
> Let's start."

### Step 4: Parse Report and Prioritize

1. **Parse the Issue Clusters table** — Each row has a severity emoji (🔴🟠🟡🟢), a description, and a score deduction.
2. **Filter to critical and high** — Only 🔴 Critical and 🟠 High clusters are in scope for auto-fixing.
3. **For each in-scope cluster, read "What Needs Immediate Attention"** — Contains affected objects, risk description, and recommended SQL fixes.
4. **For medium/low clusters** — Present as advisory items. Do not auto-fix unless user explicitly requests.
5. **For info/warning items** — Note in summary but take no action.
6. **Separate load failures from conversion defects** — Schema Loading Notes distinguish objects that failed to load due to missing dependencies vs true migration issues.
7. **Read the custom rules file** — Parse the custom rules JSON from `targetsql/` (listed in `manifest.json`'s `custom_rules` array). Understand the current type mappings, extensions, and naming conventions. This context is needed when applying fixes — if a fix contradicts or extends these rules, you'll update the custom rules file in Step 6 (and verify in Step 7).

### Step 5: Set Up Three-File Workflow

1. **Ensure the working directory is trusted** — Ask the user:
   > "Which directory should I use for the working files? It should be a directory already open and trusted in your IDE. This avoids permission prompts that can freeze the chat."

2. Read `targetsql/manifest.json` to identify the converted SQL file(s) from `execution_order` and the custom rules file(s) from `custom_rules`. File paths in the manifest are relative to `targetsql/`.
3. Copy the converted PG file (the first `file` in `execution_order`) to a working copy (e.g., `postgres-deployment-fixing.sql`). Keep the original converted PG file as a read-only reference. All fixes go to the working copy only.
4. Copy the custom rules file(s) to the working directory. All custom rules edits go to this working copy — the original in `targetsql/` stays untouched.
   - macOS/Linux/Git Bash: `cp <targetsql>/<rule_file> <working_directory>/<rule_file>`
   - Windows (PowerShell): `powershell -Command "Copy-Item '<targetsql>/<rule_file>' '<working_directory>/<rule_file>'"`
5. Open the source SQL, converted PG file, and working copy in the editor:
   - **Kiro:** `kiro <sourcesql/source.sql>` then `kiro --reuse-window <targetsql/converted.sql>` then `kiro --reuse-window <working_copy>`
   - **VS Code:** `code <sourcesql/source.sql> <targetsql/converted.sql> <working_copy>`
   - **DBeaver:** Open all files via File → Open
6. Tell the user:
   > "I've opened three files: the source MSSQL, the converted PG file, and the working copy. You can arrange them side by side. The source MSSQL and converted PG files are for reference only — all fixes go to the working copy."

### Step 6: Apply Fixes in Priority Order

Apply fixes in dependency order to avoid cascading failures:

1. **Prerequisites** — Extensions, schemas, and any infrastructure the report identifies as missing
2. **Type/column fixes** — Data type corrections flagged as critical or high
3. **Views** — Resolve dependency issues, then re-create failed views in order
4. **Stored procedures and functions** — Apply each fix pattern described in the report
5. **Indexes** — Re-create missing indexes
6. **Validate** — Confirm syntax validity and that all critical/high items are addressed

**Custom rules — update as you go:** When a fix establishes a reusable conversion pattern (type mapping, extension, naming), update the custom rules file immediately:

- **Overwriting an existing rule** (e.g., changing `BIT → BOOLEAN` to `BIT → NUMERIC`) → **ask the user for confirmation** before modifying. Do NOT overwrite silently.
- **Adding a new rule** → In per-fix mode, ask confirmation. In per-cluster/autonomous mode, just inform the user and add it.

This keeps custom rules in sync with the actual conversion. Validation uses these rules to score — inaccurate rules cause false positives.

### Step 7: Verify Custom Rules

**Why this matters:** The validation sub-agent uses the custom rules file to score the conversion. If the custom rules don't reflect the actual type mappings and patterns used in the converted SQL, validation will flag false positives and lower the score. Keeping custom rules accurate ensures validation results are meaningful.

Before uploading, verify that the custom rules file reflects all conversion patterns applied during this session:

1. **Review changes made** — For each fix that changed a type mapping, added an extension, or established a naming pattern, confirm the custom rules file was updated during Step 6.
2. **Check for missed updates** — If any fixes were applied that should have updated custom rules but didn't (e.g., you changed a `BIT` column to `NUMERIC` but the rules still say `BIT → BOOLEAN`), update them now following the rules below.
3. **Confirm with user if overwriting** — If any rule was modified (not just added), confirm the user approved the change during Step 6. If not, ask now.

**Custom rules file format:**

```json
{
  "extensions": {
    "base_extensions": ["citext", "uuid-ossp", "pgcrypto"],
    "additional_extensions": []
  },
  "type_mappings": [
    {
      "rule-id": "<unique_id>",
      "rule-name": "",
      "source-type": "<MSSQL_TYPE>",
      "target-type": "<POSTGRESQL_TYPE>",
      "precision": null,
      "scale": null
    }
  ],
  "naming": {
    "casing": "lowercase",
    "schema_mappings": {},
    "strip_schema_prefixes": []
  }
}
```

**What to update:**

- **Type mapping fixes** → Add or modify entries in `type_mappings`. Use a descriptive `rule-id` (e.g., "bit", "money").
- **Extension requirements** → Add to `extensions.additional_extensions` if a fix requires a PostgreSQL extension not in `base_extensions`.
- **Naming conventions** → Update `naming.schema_mappings` or `naming.casing` if applicable.

Save the updated custom rules file to the working directory. It will be included in the next upload ZIP (Step 8 uses the updated version).

### Step 8: Upload Fixed File to AWS Transform

#### Copy working copy and upload to artifact store

- macOS/Linux/Git Bash:

  ```
  execute_bash: cp <working_copy> <working_directory>/postgres-completed-deployment.sql
  ```

- Windows (PowerShell):

  ```
  execute_bash: powershell -Command "Copy-Item '<working_copy>' '<working_directory>/postgres-completed-deployment.sql'"
  ```

```
upload_artifact(
  workspaceId="<workspaceId>",
  jobId="<jobId>",
  content="<working_directory>/postgres-completed-deployment.sql",
  fileName="IDE_CONVERTED_DB_ARTIFACT",
  fileType="TXT",
  categoryType="CUSTOMER_INPUT"
)
```

#### Notify the AWS Transform job chat

```
send_message(
  workspaceId="<workspaceId>",
  jobId="<jobId>",
  text="IDE agent completed all critical and high-severity fixes. Uploaded corrected file as IDE_CONVERTED_DB_ARTIFACT. Ready for re-validation through invoke_validation_after_ide with new artifact id:<artifactId>"
)
```

### Step 9: Monitor Validation and Continue

Poll AWS Transform job messages for validation status updates:

```
list_resources(
  resource="messages",
  workspaceId="<workspaceId>",
  jobId="<jobId>"
)
```

Filter for messages containing "validation". Display matching messages to show progress. Re-poll every 10 seconds until a message containing **"Validation complete"** appears. Use the **mcp-sleep** tool between polls.

When "Validation complete" is found, extract the artifact ID from the message and download the new report:

```
get_resource(
  resource="artifact",
  workspaceId="<workspaceId>",
  jobId="<jobId>",
  artifactId="<artifactId from validation complete message>",
  savePath="<working_directory>/validation_report_latest.html"
)
```

Prompt the user:

> "Validation is complete. New report downloaded.
>
> Would you like to:
>
> 1. **Review & fix** — Parse the new report and apply another round of fixes
> 2. **Deploy** — Accept the current state and deploy to the target database
>
> Choose [1] or [2]:"

- **If 1:** Go back to Step 4 (Parse Report and Prioritize).
- **If 2:** Prepare and upload the final converted artifact before deployment:
  1. Prepare a ZIP bundle in a staging directory:
     - Create the staging directory:
       - macOS/Linux/Git Bash: `execute_bash: mkdir -p <working_directory>/zip_staging`
       - Windows (PowerShell): `execute_bash: powershell -Command "New-Item -ItemType Directory -Force -Path '<working_directory>/zip_staging'"`
     - Copy working copy as `postgres-completed-deployment.sql`:
       - macOS/Linux/Git Bash: `execute_bash: cp <working_copy> <working_directory>/zip_staging/postgres-completed-deployment.sql`
       - Windows (PowerShell): `execute_bash: powershell -Command "Copy-Item '<working_copy>' '<working_directory>/zip_staging/postgres-completed-deployment.sql'"`
     - Copy the custom rules file(s) from the working directory:
       - macOS/Linux/Git Bash: `execute_bash: cp <working_directory>/<rule_file> <working_directory>/zip_staging/<rule_file>`
       - Windows (PowerShell): `execute_bash: powershell -Command "Copy-Item '<working_directory>/<rule_file>' '<working_directory>/zip_staging/<rule_file>'"`
     - Create `manifest.json` with database name, execution order (`file: "postgres-completed-deployment.sql"`, `type: "all"`, `object_count: <count of CREATE statements>`), and `"custom_rules"` listing the custom rules filenames
  2. Create ZIP:
     - macOS/Linux: `execute_bash: cd <working_directory>/zip_staging && rm -f ../IDE_CONVERTED_DB_ARTIFACT.zip && zip ../IDE_CONVERTED_DB_ARTIFACT.zip *`
     - Windows: `execute_bash: powershell -Command "Compress-Archive -Path '<working_directory>/zip_staging/*' -DestinationPath '<working_directory>/IDE_CONVERTED_DB_ARTIFACT.zip' -Force"`
  3. Clean up:
     - macOS/Linux/Git Bash: `execute_bash: rm -rf <working_directory>/zip_staging`
     - Windows (PowerShell): `execute_bash: powershell -Command "Remove-Item -Recurse -Force '<working_directory>/zip_staging'"`
  4. Upload via `upload_artifact` with `fileName="IDE_CONVERTED_DB_ARTIFACT"`, `fileType="ZIP"`, `categoryType="CUSTOMER_INPUT"`.
  5. Send a message to the AWS Transform job with the artifact ID:

     ```
     send_message(
       workspaceId="<workspaceId>",
       jobId="<jobId>",
       text="IDE agent completed all fixes. Final converted artifact uploaded as IDE_CONVERTED_DB_ARTIFACT (artifactId: <artifactId>). Ready for deployment."
     )
     ```

  6. Proceed with deployment via AWS Transform job or IDE PostgreSQL extension if the user prefers.

---

## Report Structure

The validation report follows this general structure:

| Section                        | What It Contains                                                                                                             | How to Use                                                            |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Executive Summary              | Quantitative Score, Expert Assessment, production readiness grade                                                            | Determine overall severity — 🔴 NOT READY means critical issues exist |
| Migration Overview table       | Per-category counts (Tables, Views, Procs, Triggers, Columns, Constraints, Indexes, Type Mappings) with Pass/Warn/Fail rates | Identify which categories have failures                               |
| Issue Clusters table           | Severity (🔴🟠🟡🟢), cluster description, score deduction                                                                    | Prioritize fixes — work critical clusters first                       |
| Schema Loading Notes           | Objects that failed to load due to missing dependencies vs true migration issues                                             | Distinguish load failures from conversion defects                     |
| What Needs Immediate Attention | Detailed per-cluster breakdown with affected objects, risk description, and recommended SQL fixes                            | Primary source of fix instructions                                    |
| Recommended Action Plan        | Ordered steps: 🔴 Before testing → 🟡 Before go-live → 🟢 Post-migration                                                     | Follow this sequence when applying fixes                              |
| What We Could Not Verify       | Items not tested (runtime correctness, data accuracy, performance, collation)                                                | Flag as remaining risks after fixes                                   |

---

## Progress Reporting

Maintain a two-tier progress display: a summary table for overall status, plus an active context block.

### Progress Table

```
## Conversion Progress

| # | Severity | Cluster | Status |
|---|----------|---------|--------|
| 1 | 🔴 Crit  | <cluster description> (<N> objects) | ✅ Fixed |
| 2 | 🟠 High  | <cluster description> (<N> objects) | 🔄 M/N |
| 3 | 🟠 High  | <cluster description> (<N> objects) | ⏳ Pending |
| 4 | 🟡 Med   | <cluster description> (<N> objects) | ℹ Advisory |

### Currently fixing:
`<schema.object_name>` — <brief description of the fix being applied>

### Last completed:
`<schema.object_name>` — <brief description of what was fixed>
```

### Status Values

| Status                       | Meaning                                                   |
| ---------------------------- | --------------------------------------------------------- |
| `⏳ Pending`                 | Cluster not yet started                                   |
| `🔄 M/N`                     | In progress — M of N objects fixed so far                 |
| `✅ Fixed`                   | All objects in cluster resolved                           |
| `⚠ Partial (M/N, K skipped)` | Some objects could not be fixed — requires user attention |
| `ℹ Advisory`                 | Medium/low severity — presented to user, not auto-fixed   |

### Per-Fix Chat Response

For every individual fix, the chat response MUST include:

**1. Fix summary with line reference:**

```
✅ Fixed `schema.object_name` (line N in working copy)
Problem: <description from the report>
Fix applied: <one-line summary of what was changed>
Syntax validation: ✅ Passed (validated via PostgreSQL extension)
```

**2. Updated progress table** (as shown above).

**3. Approval prompt — STOP and wait:**

```
Approve this fix? [Yes / No / Modify]
```

Do NOT proceed to the next fix until the user responds.

After all critical/high clusters are done, print a final summary:

```
🔴 Critical: X/X done · 🟠 High: Y/Y done · Overall: Z/Z clusters resolved
```

---

## Known Limitations

- The IDE agent applies fixes based on the report's recommendations — it does not independently discover new issues
- Runtime correctness of fixed procedures cannot be verified without production-equivalent test data
- Application code changes (e.g., cursor-based result sets, connection strings) are outside scope — flag for user
- Collation differences (MSSQL case-insensitive vs PostgreSQL case-sensitive) need separate testing
- Performance validation requires production-equivalent load testing
- CLR stored procedures, linked server queries, and SSIS packages require architectural changes beyond SQL file fixes

---

## Example Requirements

```
## Requirement 1: Fix All Critical Issues

**User Story:** As a DBA, I want all critical-severity issues from the validation report
resolved in the PostgreSQL file so that the schema is safe for production.
**Acceptance Criteria:**

1. WHEN fixes are applied, ALL 🔴 critical clusters from the report SHALL be resolved
2. WHEN fixes are applied, the PostgreSQL file SHALL be syntactically valid
3. WHEN fixes are applied, previously converted logic SHALL NOT be altered

## Requirement 2: Fix All High-Severity Issues

**User Story:** As a developer, I want all high-severity issues from the validation report
resolved so that runtime failures are eliminated.
**Acceptance Criteria:**

1. WHEN fixes are applied, ALL 🟠 high clusters from the report SHALL be resolved
2. WHEN fixes are applied, semantic behavior SHALL match the original source SQL
3. WHEN fixes are applied, the fix SHALL follow the report's recommended approach
```

## Example Tasks

```
### From-Scratch Tasks

- [ ] 1. Authenticate and set up AWS Transform job
  - [ ] 1.1 Authenticate to AWS Transform using cookie auth
  - [ ] 1.2 Create workspace and job (or use existing)
  - [ ] 1.3 Upload source SQL artifact (.sql or .zip as-is)
  - [ ] 1.4 Send artifact URI to agent via chat
- [ ] 2. Monitor conversion and review assessment
  - [ ] 2.1 Poll messages, worklogs, and HITL tasks for progress
  - [ ] 2.2 Download and review assessment report PDFs and CSVs
  - [ ] 2.3 Trigger schema conversion when user is ready
  - [ ] 2.4 Poll for conversion completion
  - [ ] 2.5 Retrieve conversion artifacts (ZIP or individual files)

### Handoff Tasks

- [ ] 1. Collect AWS Transform job context and inputs
  - [ ] 1.1 Prompt user for workspaceId, jobId, and agentInstanceId
  - [ ] 1.2 List all artifacts from AWS Transform job
  - [ ] 1.3 Download ATX_CONVERTED_DB_ARTIFACT ZIP or individual artifacts
  - [ ] 1.4 If no artifacts found, ask user for local file paths

### Common Tasks (both workflows)

- [ ] 3. Check PostgreSQL extension prerequisite
- [ ] 4. Parse report and prioritize
  - [ ] 4.1 Extract all issue clusters by severity
  - [ ] 4.2 Identify critical and high-severity clusters
  - [ ] 4.3 Separate load failures from true migration defects
  - [ ] 4.4 Create working copy of converted PG file
- [ ] 5. Apply critical-severity fixes
  - [ ] 5.1 For each 🔴 critical cluster, validate proposed fix via PostgreSQL extension, then apply
- [ ] 6. Apply high-severity fixes
  - [ ] 6.1 For each 🟠 high cluster, validate proposed fix via PostgreSQL extension, then apply
- [ ] 7. Present advisory items
  - [ ] 7.1 Summarize 🟡 medium and 🟢 low clusters for user review
- [ ] 8. Validate and upload
  - [ ] 8.1 Confirm all critical and high clusters are addressed
  - [ ] 8.2 Present diff of all changes
  - [ ] 8.3 Create ZIP and upload to AWS Transform artifact store
- [ ] 9. Monitor validation and continue
  - [ ] 9.1 Poll AWS Transform job messages for validation progress
  - [ ] 9.2 Download new validation report
  - [ ] 9.3 Ask user: apply another round of fixes or deploy
```
