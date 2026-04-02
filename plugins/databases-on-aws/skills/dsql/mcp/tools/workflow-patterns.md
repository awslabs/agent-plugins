# MCP Common Workflow Patterns

Part of [Aurora DSQL MCP Tools Reference](../mcp-tools.md).

---

## Pattern 1: Explore Schema

```python
# Step 1: List all tables
readonly_query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'")

# Step 2: Get schema for specific table
get_schema("entities")

# Step 3: Query data
readonly_query("SELECT * FROM entities LIMIT 10")
```

## Pattern 2: Create Table with Index

```python
# WRONG - Combined DDL and index in single transaction
transact([
  "CREATE TABLE entities (...)",
  "CREATE INDEX ASYNC idx_tenant ON entities(tenant_id)"  # ❌ Will fail
])

# CORRECT - Separate transactions
transact(["CREATE TABLE entities (...)"])
transact(["CREATE INDEX ASYNC idx_tenant ON entities(tenant_id)"])
```

## Pattern 3: Safe Data Migration

```python
# Step 1: Add column (one transaction)
transact(["ALTER TABLE entities ADD COLUMN status VARCHAR(50)"])

# Step 2: Populate in batches (separate transactions)
transact(["UPDATE entities SET status = 'active' WHERE status IS NULL LIMIT 1000"])
transact(["UPDATE entities SET status = 'active' WHERE status IS NULL LIMIT 1000"])

# Step 3: Verify
readonly_query("SELECT COUNT(*) as total, COUNT(status) as with_status FROM entities")

# Step 4: Create index (separate transaction)
transact(["CREATE INDEX ASYNC idx_status ON entities(tenant_id, status)"])
```

## Pattern 4: Batch Inserts

```python
# Build list of INSERT statements
inserts = []
for i in range(100):  # Keep under 3,000 rows per transaction
    inserts.append(f"INSERT INTO entities (entity_id, tenant_id, name) VALUES ('e{i}', 't1', 'Entity {i}')")

# Execute in one transaction
transact(inserts)
```

## Pattern 5: Application-Layer Foreign Key Check

```python
# Step 1: Validate parent exists
result = readonly_query("SELECT entity_id FROM entities WHERE entity_id = 'parent-123' AND tenant_id = 'tenant-123'")

if len(result) == 0:
    raise Error("Invalid parent reference")

# Step 2: Insert child
transact([
    "INSERT INTO objectives (objective_id, entity_id, tenant_id, title) VALUES ('obj-456', 'parent-123', 'tenant-123', 'My Objective')"
])
```
