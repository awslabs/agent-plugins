# Discover Phase: IaC (Terraform) Discovery

Extracts and clusters GCP resources from Terraform files. Produces final inventory and clusters JSON files.
**Execute ALL steps in order. Do not skip or optimize.**

## Step 1: Parse Terraform Files

1. Read all `.tf`, `.tfvars`, and `.tfstate` files in working directory (recursively)
2. Extract all resources matching `google_*` pattern (e.g., `google_compute_instance`, `google_sql_database_instance`)
3. For each resource, capture exactly:
   - `address` (e.g., `google_compute_instance.web`)
   - `type` (e.g., `google_compute_instance`)
   - `config` (object with key attributes: `machine_type`, `name`, `region`, etc.)
   - `raw_hcl` (raw HCL text for this resource, needed for Step 3)
   - `depends_on` (array of addresses this resource depends on)
4. Report total resources found to user (e.g., "Parsed 50 GCP resources from Terraform")

## Step 2: Classify Resources (PRIMARY vs SECONDARY)

1. Read `references/clustering/terraform/classification-rules.md` completely
2. For EACH resource from Step 1, apply classification rules in priority order:
   - **Priority 1**: Check if in PRIMARY list → mark `classification: "PRIMARY"`, continue
   - **Priority 2**: Check if type matches SECONDARY patterns → mark `classification: "SECONDARY"` with `secondary_role` (one of: `identity`, `access_control`, `network_path`, `configuration`, `encryption`, `orchestration`)
   - **Priority 3**: Apply LLM inference heuristics → mark as SECONDARY with `secondary_role` and confidence field
   - **Default**: Mark as `SECONDARY` with `secondary_role: "configuration"` and `confidence: 0.5`
3. Confirm ALL resources have `classification` and (if SECONDARY) `secondary_role` fields
4. Report counts (e.g., "Classified: 12 PRIMARY, 38 SECONDARY")

## Step 3: Build Dependency Edges and Populate Serves

1. Read `references/clustering/terraform/typed-edges-strategy.md` completely
2. For EACH resource from Step 1, extract references from `raw_hcl`:
   - Extract all `google_\w+\.[\w\.]+` patterns (or the capturing form `(google_\w+)\.(\w+)\.(\w+)` — see typed-edges-strategy.md)
   - Classify edge type by field name/value context (see typed-edges-strategy.md)
   - Store as `{from, to, relationship_type, evidence}` in `typed_edges[]` array
3. For SECONDARY resources, populate `serves[]` array:
   - Trace outgoing references to PRIMARY resources
   - Trace incoming `depends_on` references from PRIMARY resources
   - Include transitive chains (e.g., IAM → SA → Cloud Run)
4. Report dependency summary (e.g., "Found 45 typed edges, 38 secondaries populated serves arrays")

## Step 4: Calculate Topological Depth

1. Read `references/clustering/terraform/depth-calculation.md` completely
2. Use Kahn's algorithm (or equivalent topological sort) to assign `depth` field:
   - Depth 0: resources with no incoming dependencies
   - Depth N: resources where at least one dependency is depth N-1
3. **Detect cycles**: If any resource cannot be assigned depth, flag error: "Circular dependency detected between: [resources]. Breaking lowest-confidence edge."
4. Confirm ALL resources have `depth` field (integer ≥ 0)
5. Report depth summary (e.g., "Depth 0: 8 resources, Depth 1: 15 resources, ..., Max depth: 3")

## Step 5: Apply Clustering Algorithm

1. Read `references/clustering/terraform/clustering-algorithm.md` completely
2. Apply Rules 1-6 in exact priority order:
   - **Rule 1: Networking Cluster** — `google_compute_network` + all `network_path` secondaries → 1 cluster
   - **Rule 2: Same-Type Grouping** — ALL primaries of identical type → 1 cluster (not one per resource)
   - **Rule 3: Seed Clusters** — Each remaining PRIMARY gets cluster + its `serves[]` secondaries
   - **Rule 4: Merge on Dependencies** — Merge only if single deployment unit (rare)
   - **Rule 5: Skip API Services** — `google_project_service` never gets own cluster; attach to service it enables
   - **Rule 6: Deterministic Naming** — `{service_category}_{service_type}_{gcp_region}_{sequence}` (e.g., `compute_cloudrun_us-central1_001`, `database_sql_us-central1_001`)
3. Assign `cluster_id` to EVERY resource (must match one of generated clusters)
4. Confirm ALL resources have `cluster_id` field
5. Report clustering results (e.g., "Generated 6 clusters from 50 resources")

## Step 6: Write Final Output Files

**This step is MANDATORY. Write both files with exact schemas.**

### 6a: Write gcp-resource-inventory.json

1. Create file: `.migration/[MMDD-HHMM]/gcp-resource-inventory.json`
2. Write with exact schema per `references/shared/output-schema.md` → `gcp-resource-inventory.json (Phase 1 output)` section

**CRITICAL field names (use EXACTLY these):**

- `address` (resource Terraform address)
- `type` (resource Terraform type)
- `classification` (PRIMARY or SECONDARY)
- `secondary_role` (for secondaries only; one of: identity, access_control, network_path, configuration, encryption, orchestration)
- `cluster_id` (assigned cluster)
- `config` (resource configuration object: machine_type, database_version, region, etc.)
- `dependencies` (list of Terraform addresses this resource depends on)
- `depth` (topological depth, integer ≥ 0)
- `serves` (for secondaries only; list of resources this secondary supports)

### 6b: Write gcp-resource-clusters.json

1. Create file: `.migration/[MMDD-HHMM]/gcp-resource-clusters.json`
2. Write with exact schema per `references/shared/output-schema.md` → `gcp-resource-clusters.json (Phase 1 output)` section

**CRITICAL field names (use EXACTLY these):**

- `cluster_id` (matches resources' cluster_id)
- `name` (human-readable cluster name)
- `type` (cluster category: compute, database, network, storage, etc.)
- `description` (brief description of cluster contents)
- `primary_resources` (array of addresses)
- `secondary_resources` (array of addresses)
- `creation_order_depth` (matches resource depths)
- `gcp_region` (GCP region for this cluster)
- `network` (cluster_id of the network cluster this cluster belongs to, or null)
- `must_migrate_together` (boolean: true if resources must move together)
- `dependencies` (array of cluster_ids this cluster depends on)
- `edges` (array of {from, to, relationship_type})

### 6c: Validate Both Files Exist

1. Confirm `.migration/[MMDD-HHMM]/gcp-resource-inventory.json` exists and is valid JSON
2. Confirm `.migration/[MMDD-HHMM]/gcp-resource-clusters.json` exists and is valid JSON
3. Verify all resource addresses in inventory appear in exactly one cluster
4. Verify all cluster IDs match resource cluster_id assignments
5. Report to user: "✅ Wrote gcp-resource-inventory.json (X resources) and gcp-resource-clusters.json (Y clusters)"
