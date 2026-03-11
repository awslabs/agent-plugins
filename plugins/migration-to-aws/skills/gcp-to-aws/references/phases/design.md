# Phase 3: Design AWS Architecture

## Step 0: Validate Inputs

1. Read `clarified.json` from `$MIGRATION_DIR`. If missing: **STOP**. Output: "Phase 2 (Clarify) not completed. Run Phase 2 first."
   - If invalid JSON: **STOP**. Output: "clarified.json is corrupted (invalid JSON). Re-run Phase 2."
2. Read `gcp-resource-clusters.json` from `$MIGRATION_DIR`. If missing: **STOP**. Output: "Missing gcp-resource-clusters.json. Re-run Phase 1."
   - If invalid JSON: **STOP**. Output: "gcp-resource-clusters.json is corrupted (invalid JSON). Re-run Phase 1."
   - If `clusters` array is empty: **STOP**. Output: "No clusters found. Re-run Phase 1."
3. Read `gcp-resource-inventory.json` from `$MIGRATION_DIR`. If missing: **STOP**. Output: "Missing gcp-resource-inventory.json. Re-run Phase 1."
   - If invalid JSON: **STOP**. Output: "gcp-resource-inventory.json is corrupted (invalid JSON). Re-run Phase 1."
   - If `resources` array is empty: **STOP**. Output: "No resources found. Re-run Phase 1."
   - This file provides per-resource `config` (machine_type, database_version, etc.) needed by design rubric eliminators and feature parity checks.

## Step 1: Order Clusters

Sort clusters by `creation_order_depth` (lowest first, representing foundational infrastructure).

## Step 2: Two-Pass Mapping per Cluster

For each cluster:

### Pass 1: Fast-Path Lookup

For each PRIMARY resource in the cluster:

1. Extract GCP type (e.g., `google_sql_database_instance`)
2. Look up in `design-refs/fast-path.md` → Direct Mappings table
3. If found (deterministic 1:1 match): assign AWS service with confidence = `deterministic`
4. If not found: proceed to Pass 2

### Pass 2: Rubric-Based Selection

For resources not covered by fast-path:

1. Determine service category (via `design-refs/index.md`):
   - `google_compute_instance` → compute
   - `google_cloudfunctions_function` → compute
   - `google_sql_database_instance` → database
   - `google_storage_bucket` → storage
   - `google_compute_network` → networking
   - etc.

   **Catch-all for unknown types**: If resource type not found in `index.md`:
   - Check resource name pattern (e.g., "scheduler" → orchestration, "log" → monitoring, "metric" → monitoring)
   - If pattern match: use that category
   - If no pattern match: Add to `warnings[]` with message: "Unknown GCP resource type: [type]. Not in fast-path.md or index.md. Skipped — file an issue to add support." Continue with remaining resources.

2. Load rubric from corresponding `design-refs/*.md` file (e.g., `compute.md`, `database.md`)

3. Evaluate 6 criteria (1-sentence each):
   - **Eliminators**: Feature incompatibility (hard blocker)
   - **Operational Model**: Managed vs self-hosted fit
   - **User Preference**: From `clarified.json` answers
   - **Feature Parity**: GCP feature → AWS feature availability
   - **Cluster Context**: Affinity with other resources in this cluster
   - **Simplicity**: Prefer fewer resources / less config

4. Select best-fit AWS service. Confidence = `inferred`

## Step 3: Handle Secondary Resources

For each SECONDARY resource:

1. Use `design-refs/index.md` for category
2. Apply fast-path (most secondaries have deterministic mappings)
3. If rubric needed: apply same 6-criteria approach

## Step 3.5: Validate AWS Architecture (using awsknowledge)

**Validation checks** (if awsknowledge available):

For each mapped AWS service, verify:

1. **Regional Availability**: Is the service available in the target region (e.g., `us-east-1`)?
   - Use awsknowledge to check regional support
   - If unavailable: add warning, suggest fallback region

2. **Feature Parity**: Do required features exist in AWS service?
   - Match GCP features from `clarified.json` answers
   - Check AWS feature availability via awsknowledge
   - If feature missing: add warning, suggest alternative service

3. **Service Compatibility**: Are there known issues or constraints?
   - Check best practices and gotchas via awsknowledge
   - Add to warnings if applicable

**If awsknowledge unavailable:**

- Set `validation_status: "skipped"` in output
- **Display prominent warning to user**: "⚠️ WARNING: Architecture validation skipped (awsknowledge MCP unavailable). Regional availability, feature parity, and service constraints were NOT verified. Manually verify before proceeding."
- Add same warning to `aws-design-report.md` header
- Continue with design (validation is informational, not blocking)

**If validation succeeds:**

- Set `validation_status: "completed"` in output
- List validated services in report

## Step 4: Write Design Output

**File 1: `aws-design.json`**

```json
{
  "validation_status": {
    "status": "completed|skipped",
    "message": "All services validated|Validation unavailable (awsknowledge MCP unreachable)"
  },
  "clusters": [
    {
      "cluster_id": "compute_instance_us-central1_001",
      "gcp_region": "us-central1",
      "aws_region": "us-east-1",
      "resources": [
        {
          "gcp_address": "google_compute_instance.web",
          "gcp_type": "google_compute_instance",
          "gcp_config": {
            "machine_type": "n2-standard-2",
            "zone": "us-central1-a",
            "boot_disk_size_gb": 100
          },
          "aws_service": "Fargate",
          "aws_config": {
            "cpu": "0.5",
            "memory": "1024",
            "region": "us-east-1"
          },
          "confidence": "inferred",
          "rationale": "Compute mapping; always-on; Fargate for simplicity",
          "rubric_applied": [
            "Eliminators: PASS",
            "Operational Model: Managed Fargate",
            "User Preference: Speed (q2)",
            "Feature Parity: Full (always-on compute)",
            "Cluster Context: Standalone compute tier",
            "Simplicity: Fargate (managed, no EC2)"
          ]
        }
      ]
    }
  ],
  "warnings": [
    "service X not fully supported in us-east-1; fallback to us-west-2"
  ],
  "timestamp": "2026-02-26T14:30:00Z"
}
```

**File 2: `aws-design-report.md`**

```
# AWS Architecture Design Report

## Overview
Mapped X GCP resources to Y AWS services across Z clusters.

## Cluster: compute_instance_us-central1_001
### Compute
- google_compute_instance.web → Fargate (0.5 CPU, 1 GB memory)
  Confidence: deterministic
  Rationale: Direct compute mapping, Cold Start not applicable (always-on)

[repeat per resource]

## Warnings
- Service X: falling back to region Y due to regional unavailability
```

## Step 5: Update Phase Status

Update `.phase-status.json`:

```json
{
  "phase": "design",
  "status": "completed",
  "timestamp": "2026-02-26T14:30:00Z",
  "version": "1.0.0"
}
```

Output to user: "AWS Architecture designed. Proceeding to Phase 4: Estimate Costs."
