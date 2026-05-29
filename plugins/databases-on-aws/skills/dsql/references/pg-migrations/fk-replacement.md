# Foreign Key → Validation Function Replacement

`dsql-lint` removes FK declarations. Use application-layer referential integrity instead.

The basic pattern (check-then-insert in a transaction) is assumed knowledge. This file
provides the **tenant-scoped template** that ensures FK validation is scoped to the same
tenant — the key DSQL-specific pattern.

---

## Tenant-Scoped FK Validation Template

For multi-tenant schemas, FK validation MUST be scoped to the same tenant:

```sql
-- Template: validate_fk_{child_table}_{fk_column}
CREATE FUNCTION validate_fk_{child_table}_{fk_column}(
  p_tenant_id uuid,
  p_value {fk_type}
) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM {parent_table}
    WHERE {parent_column} = p_value AND tenant_id = p_tenant_id
  );
$$;
```

**Example:**

```sql
CREATE FUNCTION validate_fk_orders_customer_id(
  p_tenant_id uuid,
  p_customer_id uuid
) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM customers WHERE id = p_customer_id AND tenant_id = p_tenant_id
  );
$$;
```

## Cascade Delete Template

```sql
CREATE FUNCTION cascade_delete_{parent_table}(p_parent_id {pk_type}) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM {child_table} WHERE {fk_column} = p_parent_id;
$$;
```

## Calling Points

| Original FK Action | When to Call                  | Function               |
| ------------------ | ----------------------------- | ---------------------- |
| REFERENCES         | Before INSERT/UPDATE of child | `validate_fk_*()`      |
| ON DELETE CASCADE  | Before DELETE of parent       | `cascade_delete_*()`   |
| ON DELETE SET NULL | Before DELETE of parent       | `cascade_set_null_*()` |
