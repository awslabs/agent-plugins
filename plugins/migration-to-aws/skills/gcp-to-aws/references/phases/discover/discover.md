# Phase 1: Discover GCP Resources

Lightweight orchestrator that detects available source types and delegates to domain-specific discoverers.
**Execute ALL steps in order. Do not skip or deviate.**

## Step 0: Initialize Migration State

1. Create `.migration/[MMDD-HHMM]/` directory (e.g., `.migration/0226-1430/`) using current timestamp (MMDD = month/day, HHMM = hour/minute)
2. Create `.migration/.gitignore` file (if not already present) with exact content:

   ```
   # Auto-generated migration state (temporary, should not be committed)
   *
   !.gitignore
   ```

   This prevents accidental commits of migration artifacts.

3. Write `.phase-status.json` with exact schema:

   ```json
   {
     "phase": "discover",
     "status": "in-progress",
     "timestamp": "2026-02-26T14:30:00Z",
     "version": "1.0.0"
   }
   ```

4. Confirm both `.migration/.gitignore` and `.phase-status.json` exist before proceeding to Step 1.

## Step 1: Scan for Available Source Types

1. Recursively scan working directory for source files:
   - **Terraform**: `.tf`, `.tfvars`, `.tfstate` files (primary v1.0)
   - **Billing** (v1.2+): GCP billing CSV/JSON exports (skip if not available)
   - **App code** (v1.1+): Python/Node/Go with `google.cloud.*` imports (skip if not available)
2. **IF zero sources found**: STOP and output: "No GCP sources detected (no `.tf` files, billing exports, or app code). Provide at least one source type and try again."
3. Report detected sources to user (e.g., "Found Terraform files in: [list]")

## Step 2: Invoke Terraform Discoverer (v1.0 — REQUIRED)

**This step is MANDATORY for v1.0. Produces final outputs directly.**

1. **IF Terraform files found** (from Step 1):
   - Read `references/phases/discover/discover-iac.md` completely
   - Follow ALL steps in discover-iac.md exactly as written
   - **WAIT for completion**: Confirm BOTH output files exist in `.migration/[MMDD-HHMM]/`:
     - `gcp-resource-inventory.json` (REQUIRED)
     - `gcp-resource-clusters.json` (REQUIRED)
   - **Validate schemas**: Confirm files contain all required fields
   - Proceed to Step 3
2. **IF Terraform files NOT found**:
   - **STOP.** Output: "No Terraform files found. v1.0 requires Terraform-defined infrastructure for discovery. Provide `.tf` files and try again."
   - Note: App code and billing discovery are planned for v1.1/v1.2 but do not yet produce the `gcp-resource-inventory.json` and `gcp-resource-clusters.json` files that downstream phases require.

## Step 3: Update Phase Status

1. Update `.phase-status.json` with exact schema:

   ```json
   {
     "phase": "discover",
     "status": "completed",
     "timestamp": "2026-02-26T14:30:00Z",
     "version": "1.0.0"
   }
   ```

2. Output to user: "✅ Discover phase complete. Discovered X total resources across Y clusters. Proceeding to Phase 2: Clarify."

## Output Files ONLY

**Discover phase produces EXACTLY 2 files in `.migration/[MMDD-HHMM]/`:**

1. `gcp-resource-inventory.json` (REQUIRED)
2. `gcp-resource-clusters.json` (REQUIRED)

**No other files should be created:**

- ❌ README.md
- ❌ discovery-summary.md
- ❌ EXECUTION_REPORT.txt
- ❌ discovery-log.md
- ❌ Any documentation or report files

All user communication via output messages only.

## Error Handling

- **Missing `.migration` directory**: Create it (Step 0)
- **Missing `.migration/.gitignore`**: Create it automatically (Step 0) — prevents accidental commits
- **No Terraform files found**: STOP with error message (Step 1). Terraform is required for v1.0.
- **discover-iac.md fails**: STOP and report exact failure point
- **discover-iac.md completes but output files missing**: STOP with error listing missing files
- **Output file validation fails**: STOP and report schema errors
- **Extra files created (README, reports, etc.)**: Failure. Discover must produce ONLY the two JSON files.

## Future Versions (v1.1+, v1.2+)

**v1.1 (App Code Discovery):**

- Implement `discover-app-code.md` to scan Python/Node/Go imports
- Merge strategy with Terraform results: TBD

**v1.2 (Billing Discovery):**

- Implement `discover-billing.md` to parse GCP billing exports
- Merge strategy with other sources: TBD
