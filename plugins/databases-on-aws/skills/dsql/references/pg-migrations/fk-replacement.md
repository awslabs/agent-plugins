# Foreign Key → Validation Function Replacement

`dsql-lint` removes FK declarations and generates no replacement code. Use application-layer
referential integrity enforcement instead. This file provides the templates.

Sources:

- [Migration Guide](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-migration-guide.html)
- [Considerations](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/considerations.html)

## Table of Contents

1. [Generated Function Templates](#generated-function-templates)
2. [Cascade Function Templates](#cascade-function-templates)
3. [Application Integration Patterns](#application-integration-patterns)
4. [Calling Point Reference](#calling-point-reference)
5. [Generation Workflow](#generation-workflow)

---

## Generated Function Templates

### Basic FK Validation (EXISTS check)

For each removed FK constraint, generate a validation function:

```sql
-- Template: validate_fk_{child_table}_{fk_column}
-- Generated from: FOREIGN KEY (fk_column) REFERENCES parent_table(parent_column)

CREATE FUNCTION validate_fk_{child_table}_{fk_column}(p_value {fk_type}) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM {parent_table} WHERE {parent_column} = p_value);
$$;
```

**Example:**

```sql
-- Original FK: tickets.org_id REFERENCES organizations(id)
CREATE FUNCTION validate_fk_tickets_org_id(p_value bigint) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM organizations WHERE id = p_value);
$$;

-- Original FK: tickets.reporter_id REFERENCES users(id)
CREATE FUNCTION validate_fk_tickets_reporter_id(p_value uuid) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM users WHERE id = p_value);
$$;
```

### Tenant-Scoped FK Validation

For multi-tenant schemas, FK validation MUST be scoped to the same tenant:

```sql
-- Template: validate_fk_{child_table}_{fk_column}_tenant
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
-- Tenant-scoped: orders.customer_id REFERENCES customers(id) within same tenant
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

---

## Cascade Function Templates

### ON DELETE CASCADE Replacement

```sql
-- Template: cascade_delete_{parent_table}
-- Generated from: FOREIGN KEY ... ON DELETE CASCADE
CREATE FUNCTION cascade_delete_{parent_table}(p_parent_id {pk_type}) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM {child_table_1} WHERE {fk_column_1} = p_parent_id;
  DELETE FROM {child_table_2} WHERE {fk_column_2} = p_parent_id;
$$;
```

**Example:**

```sql
-- Original: orders.user_id REFERENCES users(id) ON DELETE CASCADE
--           sessions.user_id REFERENCES users(id) ON DELETE CASCADE
CREATE FUNCTION cascade_delete_users(p_user_id bigint) RETURNS void
LANGUAGE sql AS $$
  DELETE FROM orders WHERE user_id = p_user_id;
  DELETE FROM sessions WHERE user_id = p_user_id;
$$;
```

### ON DELETE SET NULL Replacement

```sql
-- Template: cascade_set_null_{parent_table}
CREATE FUNCTION cascade_set_null_{parent_table}(p_parent_id {pk_type}) RETURNS void
LANGUAGE sql AS $$
  UPDATE {child_table} SET {fk_column} = NULL WHERE {fk_column} = p_parent_id;
$$;
```

**Example:**

```sql
-- Original: tickets.assignee_id REFERENCES users(id) ON DELETE SET NULL
CREATE FUNCTION cascade_set_null_users_assignee(p_user_id uuid) RETURNS void
LANGUAGE sql AS $$
  UPDATE tickets SET assignee_id = NULL WHERE assignee_id = p_user_id;
$$;
```

### ON UPDATE CASCADE Replacement

```sql
-- Template: cascade_update_{parent_table}_{column}
CREATE FUNCTION cascade_update_{parent_table}_{column}(
  p_old_value {pk_type},
  p_new_value {pk_type}
) RETURNS void
LANGUAGE sql AS $$
  UPDATE {child_table} SET {fk_column} = p_new_value WHERE {fk_column} = p_old_value;
$$;
```

---

## Application Integration Patterns

### Pattern A: Service Layer (Recommended)

```python
# Python — validate before INSERT
def create_ticket(tenant_id, org_id, reporter_id, title):
    with db.cursor() as cur:
        # Validate FKs
        cur.execute("SELECT validate_fk_tickets_org_id(%s, %s)", [tenant_id, org_id])
        if not cur.fetchone()[0]:
            raise ValueError(f"Organization {org_id} does not exist for tenant")

        cur.execute("SELECT validate_fk_tickets_reporter_id(%s, %s)", [tenant_id, reporter_id])
        if not cur.fetchone()[0]:
            raise ValueError(f"Reporter {reporter_id} does not exist for tenant")

        # Insert
        cur.execute(
            "INSERT INTO tickets (tenant_id, org_id, reporter_id, title) VALUES (%s,%s,%s,%s)",
            [tenant_id, org_id, reporter_id, title]
        )
    db.commit()
```

### Pattern B: Database Function Wrapper

Wrap INSERT with validation in a single SQL function:

```sql
CREATE FUNCTION insert_ticket(
  p_tenant_id uuid,
  p_org_id bigint,
  p_reporter_id uuid,
  p_title text
) RETURNS uuid
LANGUAGE sql AS $$
  -- Validation + insert in one call
  -- Returns NULL if FK validation fails, otherwise returns new ticket ID
  SELECT CASE
    WHEN NOT validate_fk_tickets_org_id(p_tenant_id, p_org_id) THEN NULL
    WHEN NOT validate_fk_tickets_reporter_id(p_tenant_id, p_reporter_id) THEN NULL
    ELSE (
      INSERT INTO tickets (id, tenant_id, org_id, reporter_id, title)
      VALUES (gen_random_uuid(), p_tenant_id, p_org_id, p_reporter_id, p_title)
      RETURNING id
    )
  END;
$$;
```

### Pattern C: ORM Hooks

**Django:**

```python
from django.db.models.signals import pre_save
from django.dispatch import receiver

@receiver(pre_save, sender=Ticket)
def validate_ticket_fks(sender, instance, **kwargs):
    if not Organization.objects.filter(id=instance.org_id, tenant_id=instance.tenant_id).exists():
        raise ValidationError({'org_id': 'Organization does not exist'})
```

**SQLAlchemy:**

```python
from sqlalchemy import event

@event.listens_for(Ticket, 'before_insert')
def validate_ticket_fks(mapper, connection, target):
    result = connection.execute(
        text("SELECT validate_fk_tickets_org_id(:tid, :oid)"),
        {"tid": target.tenant_id, "oid": target.org_id}
    )
    if not result.scalar():
        raise IntegrityError("FK violation: org_id does not exist")
```

**Spring/Hibernate:**

```java
@Service
public class TicketService {
    @Transactional
    public Ticket createTicket(UUID tenantId, Long orgId, UUID reporterId, String title) {
        if (!organizationRepository.existsByIdAndTenantId(orgId, tenantId)) {
            throw new EntityNotFoundException("Organization not found");
        }
        if (!userRepository.existsByIdAndTenantId(reporterId, tenantId)) {
            throw new EntityNotFoundException("Reporter not found");
        }
        return ticketRepository.save(new Ticket(tenantId, orgId, reporterId, title));
    }
}
```

### Pattern D: Cascade on DELETE

```python
def delete_organization(tenant_id, org_id):
    with db.cursor() as cur:
        # Check for dependents first (optional — or just cascade)
        cur.execute(
            "SELECT COUNT(*) FROM tickets WHERE tenant_id = %s AND org_id = %s AND NOT resolved",
            [tenant_id, org_id]
        )
        active_tickets = cur.fetchone()[0]
        if active_tickets > 0:
            raise ValueError(f"Cannot delete: {active_tickets} active tickets exist")

        # Cascade
        cur.execute("SELECT cascade_delete_organizations(%s)", [org_id])
        # Delete parent
        cur.execute("DELETE FROM organizations WHERE id = %s AND tenant_id = %s", [org_id, tenant_id])
    db.commit()
```

---

## Calling Point Reference

| Original FK Action | When to Call Replacement                   | Where                        |
| ------------------ | ------------------------------------------ | ---------------------------- |
| REFERENCES (basic) | Before INSERT/UPDATE of child              | Service layer or DB function |
| ON DELETE CASCADE  | Before DELETE of parent                    | Service layer                |
| ON DELETE SET NULL | Before DELETE of parent                    | Service layer                |
| ON UPDATE CASCADE  | After UPDATE of parent PK                  | Service layer (rare)         |
| ON DELETE RESTRICT | Before DELETE of parent (check dependents) | Service layer                |

---

## Generation Workflow

Given a PostgreSQL schema with FKs:

1. **Extract all FK constraints:**

   ```sql
   SELECT
     tc.table_name AS child_table,
     kcu.column_name AS fk_column,
     ccu.table_name AS parent_table,
     ccu.column_name AS parent_column,
     rc.delete_rule,
     rc.update_rule
   FROM information_schema.table_constraints tc
   JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
   JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
   JOIN information_schema.referential_constraints rc ON tc.constraint_name = rc.constraint_name
   WHERE tc.constraint_type = 'FOREIGN KEY';
   ```

2. **For each FK, generate:**
   - A `validate_fk_*()` function (always)
   - A `cascade_*()` function (if ON DELETE CASCADE/SET NULL)

3. **Run `dsql-lint`** on the generated functions to verify compatibility

4. **Deploy** each function via `transact(["CREATE FUNCTION ..."])` — one per call

5. **Update application code** to call validation before INSERT/UPDATE and cascade before DELETE
