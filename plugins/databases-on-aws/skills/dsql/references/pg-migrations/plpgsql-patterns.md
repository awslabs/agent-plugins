# PL/pgSQL → SQL Transpilation Patterns

DSQL uses pure SQL functions (`LANGUAGE sql`). This file provides 10 recognized patterns for converting
PL/pgSQL trigger functions and procedures to pure SQL functions that work
in Aurora DSQL.

`dsql-lint` does NOT handle PL/pgSQL conversion — it flags PL/pgSQL as unsupported but
generates no replacement. Use these patterns to produce the converted output.

Sources:

- [Migration Guide — Application-level logic](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-migration-guide.html)
- [Supported SQL Features — CREATE FUNCTION](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-supported-sql-features.html)

## Table of Contents

1. [Pattern Detection Quick Reference](#pattern-detection-quick-reference)
2. [Pattern 1: SET_COLUMN](#pattern-1-set_column)
3. [Pattern 2: VALIDATION → CHECK Constraint](#pattern-2-validation--check-constraint)
4. [Pattern 3: AUDIT_INSERT](#pattern-3-audit_insert)
5. [Pattern 4: CASCADE_DML](#pattern-4-cascade_dml)
6. [Pattern 5: FOR_LOOP → Set-Based](#pattern-5-for_loop--set-based)
7. [Pattern 6: IF_ELSE → CASE WHEN](#pattern-6-if_else--case-when)
8. [Pattern 7: EXCEPTION unique_violation → ON CONFLICT](#pattern-7-exception-unique_violation--on-conflict)
9. [Pattern 8: Dynamic SQL → Expanded Per-Table](#pattern-8-dynamic-sql--expanded-per-table)
10. [Pattern 9: CURSOR → Set-Based](#pattern-9-cursor--set-based)
11. [Pattern 10: EXCEPTION no_data_found → COALESCE](#pattern-10-exception-no_data_found--coalesce)
12. [Unconvertible Patterns (Generate Stubs)](#unconvertible-patterns-generate-stubs)
13. [Conversion Workflow](#conversion-workflow)
14. [App Integration Cheat Sheet](#app-integration-cheat-sheet)

---

## Pattern Detection Quick Reference

| #  | Pattern      | Detection Signal                      | Output                   |
| -- | ------------ | ------------------------------------- | ------------------------ |
| 1  | SET_COLUMN   | `NEW.<col> = <expr>; RETURN NEW;`     | SQL UPDATE function      |
| 2  | VALIDATION   | `IF NEW.<col> ... RAISE EXCEPTION`    | CHECK constraint         |
| 3  | AUDIT_INSERT | `INSERT INTO audit_log ... TG_OP`     | SQL INSERT function      |
| 4  | CASCADE_DML  | `UPDATE/DELETE ... WHERE ... OLD.id`  | SQL DML function         |
| 5  | FOR_LOOP     | `FOR r IN SELECT ... LOOP UPDATE`     | Set-based UPDATE...FROM  |
| 6  | IF_ELSE      | `IF cond THEN RETURN x ELSE RETURN y` | CASE WHEN expression     |
| 7  | UPSERT       | `EXCEPTION WHEN unique_violation`     | ON CONFLICT clause       |
| 8  | DYNAMIC_SQL  | `EXECUTE format(...)`                 | One function per table   |
| 9  | CURSOR       | `DECLARE cur CURSOR ... LOOP`         | INSERT...SELECT          |
| 10 | COALESCE     | `EXCEPTION WHEN no_data_found`        | COALESCE(subquery, NULL) |

---

## Pattern 1: SET_COLUMN

**Intent:** Set a column value on INSERT/UPDATE (e.g., updated_at timestamp)

**Detection:** Function body contains `NEW.<column> = <expression>; RETURN NEW;`

**Before (PL/pgSQL trigger):**

```sql
CREATE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

**After (SQL function — call from application):**

```sql
CREATE FUNCTION apply_set_updated_at_users(p_id bigint) RETURNS void
LANGUAGE sql AS $$
  UPDATE users SET updated_at = now() WHERE id = p_id;
$$;
```

**App responsibility:** Call `SELECT apply_set_updated_at_users(id)` after every UPDATE on the table. Alternatively, include `updated_at = now()` directly in your UPDATE statement.

**Simpler alternative:** Skip the function entirely — just add `updated_at = now()` to every UPDATE in your application code.

---

## Pattern 2: VALIDATION → CHECK Constraint

**Intent:** Reject invalid data on INSERT/UPDATE

**Detection:** Function body contains `IF NEW.<col> <condition> THEN RAISE EXCEPTION`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION validate_price() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.price < 0 THEN
    RAISE EXCEPTION 'price must be non-negative';
  END IF;
  IF NEW.quantity > 10000 THEN
    RAISE EXCEPTION 'quantity exceeds maximum';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**After (CHECK constraints — automatic enforcement):**

```sql
-- Add at CREATE TABLE time (use Table Recreation Pattern for existing tables)
CREATE TABLE products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  price numeric(10,2) CHECK (price >= 0),
  quantity integer CHECK (quantity <= 10000)
);
```

**App responsibility:** None — CHECK is enforced automatically by DSQL.

**Important:** Define CHECK constraints at CREATE TABLE time. Use the Table Recreation Pattern to add constraints to existing tables.

---

## Pattern 3: AUDIT_INSERT

**Intent:** Log changes to an audit table after DML

**Detection:** Function body contains `INSERT INTO audit_log` with `TG_OP`, `TG_TABLE_NAME`, `row_to_json`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION log_change() RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (table_name, action, old_data, new_data, changed_at)
  VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::text, row_to_json(NEW)::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL function):**

```sql
CREATE FUNCTION audit_log_orders(
  p_action text,
  p_old_data text,
  p_new_data text
) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO audit_log (table_name, action, old_data, new_data, changed_at)
  VALUES ('orders', p_action, p_old_data, p_new_data, now());
$$;
```

**App responsibility:** Call after INSERT/UPDATE/DELETE:

```python
# Python example
old_json = json.dumps(old_row) if old_row else None
new_json = json.dumps(new_row) if new_row else None
cursor.execute("SELECT audit_log_orders(%s, %s, %s)", ['UPDATE', old_json, new_json])
```

---

## Pattern 4: CASCADE_DML

**Intent:** Update/delete related rows when a parent changes (ON DELETE CASCADE replacement)

**Detection:** Function body contains `UPDATE/DELETE ... WHERE <fk_col> = OLD.id`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION cascade_delete_user() RETURNS TRIGGER AS $$
BEGIN
  UPDATE orders SET status = 'cancelled' WHERE user_id = OLD.id;
  DELETE FROM sessions WHERE user_id = OLD.id;
  DELETE FROM preferences WHERE user_id = OLD.id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL function):**

```sql
CREATE FUNCTION cascade_delete_user(p_user_id bigint) RETURNS void
LANGUAGE sql AS $$
  UPDATE orders SET status = 'cancelled' WHERE user_id = p_user_id;
  DELETE FROM sessions WHERE user_id = p_user_id;
  DELETE FROM preferences WHERE user_id = p_user_id;
$$;
```

**App responsibility:** Call BEFORE deleting the parent row:

```python
cursor.execute("SELECT cascade_delete_user(%s)", [user_id])
cursor.execute("DELETE FROM users WHERE id = %s", [user_id])
```

---

## Pattern 5: FOR_LOOP → Set-Based

**Intent:** Process rows one at a time (batch update pattern)

**Detection:** Function body contains `FOR r IN SELECT ... LOOP ... UPDATE ... END LOOP`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION expire_old_tickets() RETURNS void AS $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT id FROM tickets WHERE due_date < CURRENT_DATE AND NOT resolved
  LOOP
    UPDATE tickets SET resolved = TRUE, resolved_at = now() WHERE id = r.id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL — single set-based statement):**

```sql
CREATE FUNCTION expire_old_tickets() RETURNS void
LANGUAGE sql AS $$
  UPDATE tickets SET resolved = TRUE, resolved_at = now()
  FROM (SELECT id FROM tickets WHERE due_date < CURRENT_DATE AND NOT resolved) AS _src
  WHERE tickets.id = _src.id;
$$;
```

**App responsibility:** None — call the function directly. Much faster than row-by-row.

**Note:** If the UPDATE affects >3,000 rows, batch it in the application layer.

---

## Pattern 6: IF_ELSE → CASE WHEN

**Intent:** Return different values based on conditions

**Detection:** Function body contains `IF cond THEN RETURN x; ELSE RETURN y; END IF;`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION get_priority_label(sev integer) RETURNS text AS $$
BEGIN
  IF sev = 1 THEN RETURN 'critical';
  ELSIF sev = 2 THEN RETURN 'high';
  ELSIF sev = 3 THEN RETURN 'medium';
  ELSE RETURN 'low';
  END IF;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL with CASE WHEN):**

```sql
CREATE FUNCTION get_priority_label(sev integer) RETURNS text
LANGUAGE sql AS $$
  SELECT CASE
    WHEN sev = 1 THEN 'critical'
    WHEN sev = 2 THEN 'high'
    WHEN sev = 3 THEN 'medium'
    ELSE 'low'
  END;
$$;
```

**App responsibility:** None — pure SQL function.

---

## Pattern 7: EXCEPTION unique_violation → ON CONFLICT

**Intent:** Insert or update (upsert)

**Detection:** Function body contains `EXCEPTION WHEN unique_violation THEN UPDATE`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION upsert_setting(p_user_id uuid, p_key text, p_value text) RETURNS void AS $$
BEGIN
  INSERT INTO user_settings (user_id, key, value) VALUES (p_user_id, p_key, p_value);
EXCEPTION WHEN unique_violation THEN
  UPDATE user_settings SET value = p_value WHERE user_id = p_user_id AND key = p_key;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL with ON CONFLICT):**

```sql
CREATE FUNCTION upsert_setting(p_user_id uuid, p_key text, p_value text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO user_settings (user_id, key, value)
  VALUES (p_user_id, p_key, p_value)
  ON CONFLICT (user_id, key) DO UPDATE SET value = EXCLUDED.value;
$$;
```

**App responsibility:** None — ON CONFLICT is handled by DSQL natively.

**Note:** Requires a UNIQUE constraint or index on the conflict columns.

---

## Pattern 8: Dynamic SQL → Expanded Per-Table

**Intent:** Run same DML on different tables passed as parameter

**Detection:** Function body contains `EXECUTE format('... %I ...', table_name)`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION cleanup_old_records(tbl text, days integer) RETURNS void AS $$
BEGIN
  EXECUTE format('DELETE FROM %I WHERE created_at < now() - interval ''%s days''', tbl, days);
END;
$$ LANGUAGE plpgsql;
```

**After (one concrete function per table):**

```sql
CREATE FUNCTION cleanup_orders(p_days integer) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM orders WHERE created_at < now() - make_interval(days => p_days);
$$;

CREATE FUNCTION cleanup_logs(p_days integer) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM logs WHERE created_at < now() - make_interval(days => p_days);
$$;

CREATE FUNCTION cleanup_sessions(p_days integer) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM sessions WHERE created_at < now() - make_interval(days => p_days);
$$;
```

**App responsibility:** Call the table-specific function instead of the generic one.

---

## Pattern 9: CURSOR → Set-Based

**Intent:** Process query results row by row with a cursor

**Detection:** Function body contains `DECLARE cur CURSOR FOR ... FOR rec IN cur LOOP`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION notify_inactive_users() RETURNS void AS $$
DECLARE
  cur CURSOR FOR SELECT id, email FROM users
    WHERE last_login < now() - interval '90 days' AND active = true;
  rec RECORD;
BEGIN
  FOR rec IN cur LOOP
    INSERT INTO notifications (user_id, message, created_at)
    VALUES (rec.id, 'Your account will be deactivated soon', now());
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL — INSERT...SELECT):**

```sql
CREATE FUNCTION notify_inactive_users() RETURNS void
LANGUAGE sql AS $$
  INSERT INTO notifications (user_id, message, created_at)
  SELECT id, 'Your account will be deactivated soon', now()
  FROM users
  WHERE last_login < now() - interval '90 days' AND active = true;
$$;
```

**App responsibility:** None — single statement, much faster.

**Note:** If the INSERT affects >3,000 rows, batch in the application layer with LIMIT/OFFSET.

---

## Pattern 10: EXCEPTION no_data_found → COALESCE

**Intent:** Return NULL instead of raising error when no rows found

**Detection:** Function body contains `EXCEPTION WHEN no_data_found THEN RETURN NULL`

**Before (PL/pgSQL):**

```sql
CREATE FUNCTION safe_get_org_name(p_id integer) RETURNS text AS $$
DECLARE result text;
BEGIN
  SELECT name INTO STRICT result FROM organizations WHERE id = p_id;
  RETURN result;
EXCEPTION WHEN no_data_found THEN
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
```

**After (SQL with COALESCE or plain subquery):**

```sql
CREATE FUNCTION safe_get_org_name(p_id integer) RETURNS text
LANGUAGE sql AS $$
  SELECT name FROM organizations WHERE id = p_id;
$$;
-- Returns NULL naturally when no rows match (no STRICT = no exception)
```

**App responsibility:** None — SQL functions return NULL for empty result sets by default.

---

## Unconvertible Patterns (Generate Stubs)

These cannot be automatically converted. Generate a stub with TODO comments:

| Pattern                                       | Why                                                                  | Resolution                                               |
| --------------------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------- |
| PERFORM                                       | Calls function for side effects, discards result. No SQL equivalent. | Move logic to application code or AWS Lambda             |
| Complex ELSIF (3+ branches with side effects) | Multiple DML statements in branches — too complex for CASE WHEN      | Rewrite as multiple SQL functions or move to application |
| RAISE NOTICE/LOG                              | Diagnostic output — no SQL equivalent                                | Use application logging                                  |
| Dynamic table/column names (complex)          | Cannot expand all combinations                                       | Move to application code                                 |
| LOOP with EXIT WHEN                           | Iterative logic with break conditions                                | Rewrite as recursive CTE or application loop             |

**Stub template:**

```sql
-- TODO: Manual conversion required
-- Original function: <function_name>
-- Pattern: PERFORM / Complex ELSIF / Dynamic SQL
-- Original body:
--   <paste original PL/pgSQL body as comments>
--
-- Suggested approach:
--   Move this logic to application code (Python/Node/Java)
--   or implement as an AWS Lambda function called via application layer.
```

---

## Conversion Workflow

1. **Identify all PL/pgSQL functions:** `SELECT proname, prosrc FROM pg_proc WHERE prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql');`
2. **Identify all triggers:** `SELECT tgname, tgrelid::regclass, proname FROM pg_trigger JOIN pg_proc ON tgfoid = pg_proc.oid WHERE NOT tgisinternal;`
3. **Match each function to a pattern** (use detection signals above)
4. **Generate SQL replacement** using the templates
5. **Drop the trigger** (triggers are not supported in DSQL)
6. **Create the SQL function** via `transact`
7. **Update application code** to call the function where the trigger used to fire
8. **Run `dsql-lint`** on the generated SQL to verify compatibility

---

## App Integration Cheat Sheet

| Original Trigger Timing | Replacement Call Point                                          |
| ----------------------- | --------------------------------------------------------------- |
| BEFORE INSERT           | Call validation function before INSERT                          |
| BEFORE UPDATE           | Call SET_COLUMN function after UPDATE (or inline in UPDATE SET) |
| AFTER INSERT            | Call audit/notification function after INSERT                   |
| AFTER UPDATE            | Call audit function after UPDATE                                |
| BEFORE DELETE           | Call cascade function before DELETE                             |
| AFTER DELETE            | Call audit function after DELETE                                |
