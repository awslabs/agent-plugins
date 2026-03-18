# MCP Database Operation Tools

Part of [Aurora DSQL MCP Tools Reference](../mcp-tools.md).

---

## 1. readonly_query - Execute read-only SQL queries

**Use for:** SELECT queries, data exploration, ad-hoc analysis

**Parameters:**

- `sql` (string, required) - SQL query to run

**Returns:** List of dictionaries containing query results

**Security:**

- Automatically prevents mutating keywords (INSERT, UPDATE, DELETE, etc.)
- Checks for SQL injection risks
- Prevents transaction bypass attempts

**Examples:**

```sql
-- Simple SELECT
SELECT * FROM entities WHERE tenant_id = 'tenant-123' LIMIT 10

-- Aggregate query
SELECT tenant_id, COUNT(*) as count FROM objectives GROUP BY tenant_id

-- Join query
SELECT e.entity_id, e.name, o.title
FROM entities e
INNER JOIN objectives o ON e.entity_id = o.entity_id
WHERE e.tenant_id = 'tenant-123'
```

**Note:** Parameterized queries ($1, $2) are NOT supported by this MCP tool. Use string interpolation carefully and validate inputs to prevent SQL injection.

---

## 2. transact - Execute write operations in a transaction

**Use for:** INSERT, UPDATE, DELETE, CREATE TABLE, ALTER TABLE

**Parameters:**

- `sql_list` (List[string], required) - **List of SQL statements** to execute in a transaction

**Returns:** List of dictionaries with execution results

**Requirements:**

- Server must be started with `--allow-writes` flag
- Cannot be used in read-only mode

**Behavior:**

- Automatically wraps statements in BEGIN/COMMIT
- Rolls back on any error
- All statements execute atomically

**Examples:**

```python
# Single DDL statement (still needs to be in a list)
["CREATE TABLE IF NOT EXISTS entities (...)"]

# Create table with index (two separate statements)
[
  "CREATE TABLE IF NOT EXISTS entities (...)",
  "CREATE INDEX ASYNC idx_entities_tenant ON entities(tenant_id)"
]

# Insert multiple rows in one transaction
[
  "INSERT INTO entities (entity_id, tenant_id, name) VALUES ('e1', 't1', 'Entity 1')",
  "INSERT INTO entities (entity_id, tenant_id, name) VALUES ('e2', 't1', 'Entity 2')",
  "INSERT INTO entities (entity_id, tenant_id, name) VALUES ('e3', 't1', 'Entity 3')"
]

# Safe migration pattern
[
  "ALTER TABLE entities ADD COLUMN status VARCHAR(50)"
]
# Then in a separate transaction:
[
  "UPDATE entities SET status = 'active' WHERE status IS NULL AND tenant_id = 'tenant-123'"
]

# Batch update
[
  "UPDATE entities SET status = 'archived', updated_at = CURRENT_TIMESTAMP WHERE tenant_id = 'tenant-123' AND created_at < '2024-01-01'"
]
```

**Important Notes:**

- Each ALTER TABLE must be in its own transaction (DSQL limitation)
- Keep transactions under 3,000 rows and 10 MiB
- For large batch operations, split into multiple transact calls
- Cannot use parameterized queries - validate inputs before building SQL strings

---

## 3. get_schema - Get table schema details

**Use for:** Understanding table structure, planning migrations, exploring database

**Parameters:**

- `table_name` (string, required) - Name of table to inspect

**Returns:** List of dictionaries with column information (name, type, nullable, default, etc.)

**Example:**

```python
# Get schema for entities table
table_name = "entities"

# Returns column definitions like:
# [
#   {"column_name": "entity_id", "data_type": "character varying", "is_nullable": "NO", ...},
#   {"column_name": "tenant_id", "data_type": "character varying", "is_nullable": "NO", ...},
#   ...
# ]
```

**Note:** There is no `list_tables` tool. To discover tables, use `readonly_query` with:

```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'
```
