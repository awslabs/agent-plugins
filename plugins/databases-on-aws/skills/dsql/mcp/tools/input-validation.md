# MCP Input Validation & Security

Part of [Aurora DSQL MCP Tools Reference](../mcp-tools.md).

---

## Best Practices

### Follow General Developing Best Practices

Refer to the listed [Best Practices](../../references/development-guide.md#best-practices).

### Input Validation (Critical!)

Since parameterized queries are NOT supported, you MUST validate and sanitize inputs:

```python
# BAD - SQL injection risk
user_input = request.get("tenant_id")
sql = f"SELECT * FROM entities WHERE tenant_id = '{user_input}'"
readonly_query(sql)  # ❌ Vulnerable!

# GOOD - Validate input format
import re
user_input = request.get("tenant_id")
if not re.match(r'^[a-zA-Z0-9-]+$', user_input):
    raise ValueError("Invalid tenant_id format")
sql = f"SELECT * FROM entities WHERE tenant_id = '{user_input}'"
readonly_query(sql)  # ✓ Safe after validation

# BETTER - Use allowlist for tenant IDs
ALLOWED_TENANTS = {"tenant-123", "tenant-456"}
if user_input not in ALLOWED_TENANTS:
    raise ValueError("Unknown tenant")
sql = f"SELECT * FROM entities WHERE tenant_id = '{user_input}'"
readonly_query(sql)  # ✓ Most secure
```

### Quote Escaping

```python
# Escape single quotes in string values
name = user_input.replace("'", "''")
sql = f"INSERT INTO entities (name) VALUES ('{name}')"
```
