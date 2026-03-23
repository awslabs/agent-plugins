# Phase 2: Clarify Requirements

## Step 0: Validate Inputs

1. Read `gcp-resource-inventory.json` from `$MIGRATION_DIR`. If missing: **STOP**. Output: "Missing gcp-resource-inventory.json. Complete Phase 1 (Discover) first."
2. If invalid JSON: **STOP**. Output: "gcp-resource-inventory.json is corrupted (invalid JSON). Re-run Phase 1."
3. If `resources` array is empty: **STOP**. Output: "gcp-resource-inventory.json contains no resources. Re-run Phase 1 with valid Terraform files."
4. Read `gcp-resource-clusters.json` from `$MIGRATION_DIR`. If missing: **STOP**. Output: "Missing gcp-resource-clusters.json. Complete Phase 1 (Discover) first."
5. If invalid JSON: **STOP**. Output: "gcp-resource-clusters.json is corrupted (invalid JSON). Re-run Phase 1."
6. If `clusters` array is empty: **STOP**. Output: "gcp-resource-clusters.json contains no clusters. Re-run Phase 1 with valid Terraform files."

## Step 1: Load Inventory

Read `gcp-resource-inventory.json` and `gcp-resource-clusters.json` from `$MIGRATION_DIR` (already validated in Step 0).

## Step 2: Select Answering Mode

Present 4 modes to user:

| Mode  | Style       | When to use                                  |
| ----- | ----------- | -------------------------------------------- |
| **A** | All at once | "I'll answer all 8 questions together"       |
| **B** | One-by-one  | "Ask me each question separately"            |
| **C** | Defaults    | "Use default answers (no questions)"         |
| **D** | Free text   | "I'll describe requirements in my own words" |

If user selects **Mode C** or **Mode D**: use default answers from `shared/clarify-questions.md` and continue to Step 3.

If user selects **Mode A** or **Mode B**: Present all 8 questions (from `shared/clarify-questions.md`), collect answers, continue to Step 3.

**Fallback handling:** If user selects Mode A or B but then declines to answer questions or provides incomplete answers, offer Mode C (use defaults) or Mode D (free-text description) as alternatives. Phase 2 completes using whichever mode provides answers.

## Step 3: Normalize Answers

For Modes A/B (Q1-Q8 answered):

- Validate each answer is within the option set
- If user gives free-form answer, map to closest option
- Store normalized answers

For Mode C:

- Use all defaults from `shared/clarify-questions.md`

For Mode D (free-text):

1. Parse user text to extract answers for Q1-Q8
   - Look for keywords matching question option descriptions
   - For each question, mark as "extracted" if found or "default" if not

2. **Confirmation step**: Present to user:

   ```
   Based on your requirements, I extracted:
   - Q1 (Timeline): [extracted value]
   - Q2 (Primary concern): [extracted value]
   - Q3 (Team experience): [default value] ← using default
   - ...

   Accept these, or re-run with Mode A/B to override?
   ```

3. If user accepts: store answers with source tracking (extracted vs default)
4. If user declines: fall back to Mode A or B

## Step 4: Write Clarified Output

Write `clarified.json` to `.migration/[MMDD-HHMM]/` directory.

**Schema:** See `references/shared/output-schema.md` → `clarified.json (Phase 2 output)` section for complete schema and field documentation.

**Key fields:**

- `mode`: "A", "B", "C", or "D" (answering mode selected in Step 2)
- `answers`: Object with keys q1_timeline through q8_compliance
- `timestamp`: ISO 8601 timestamp

## Step 5: Update Phase Status

Update `.phase-status.json`:

```json
{
  "phase": "clarify",
  "status": "completed",
  "timestamp": "2026-02-26T14:30:00Z",
  "version": "1.0.0"
}
```

Output to user: "Clarification complete. Proceeding to Phase 3: Design AWS Architecture."
