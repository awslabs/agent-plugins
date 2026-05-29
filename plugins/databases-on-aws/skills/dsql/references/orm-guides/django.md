# Django ORM Migration Guide for DSQL

How to run Django applications against Aurora DSQL.

Sources:

- [Aurora DSQL Django Adapter](https://github.com/awslabs/aurora-dsql-orms/tree/main/python/django)
- [aurora-dsql-django on PyPI](https://pypi.org/project/aurora-dsql-django/)
- [Django Pet Clinic Example](https://github.com/awslabs/aurora-dsql-orms/tree/main/python/django/examples/pet-clinic-app)

---

## 1. Installation

```bash
pip install aurora-dsql-django boto3
```

## 2. Database Configuration

```python
# settings.py
DATABASES = {
    'default': {
        'ENGINE': 'aurora_dsql_django',           # NOT 'django.db.backends.postgresql'
        'NAME': 'postgres',                        # Always 'postgres' for DSQL
        'HOST': '<cluster-id>.<region>.dsql.amazonaws.com',
        'PORT': '5432',
        'OPTIONS': {
            'sslmode': 'require',
        },
        'CONN_MAX_AGE': 1800,  # 30 min (below DSQL's 1-hour timeout)
    }
}
```

**Key differences:**

- Engine is `aurora_dsql_django` (handles IAM token generation automatically)
- No `USER` or `PASSWORD` — IAM token via boto3
- Database name is always `postgres`
- SSL required

## 3. Model Changes

### Replace ForeignKey with Plain Fields

```python
# BAD: Django creates FK constraint (DSQL rejects)
class Ticket(models.Model):
    org = models.ForeignKey(Organization, on_delete=models.CASCADE)

# GOOD: Plain field + application-layer validation
class Ticket(models.Model):
    org_id = models.BigIntegerField(db_index=True)
    reporter_id = models.UUIDField(db_index=True)

    def clean(self):
        if not Organization.objects.filter(id=self.org_id).exists():
            raise ValidationError({'org_id': 'Organization does not exist'})
        if not User.objects.filter(id=self.reporter_id).exists():
            raise ValidationError({'reporter_id': 'User does not exist'})
```

### Use UUID Primary Keys

```python
import uuid
from django.db import models

class BaseModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    class Meta:
        abstract = True

class Organization(BaseModel):
    name = models.CharField(max_length=200, unique=True)
    settings = models.JSONField(default=dict)  # Stored as json in DSQL
```

### Field Mapping

| Django Field        | DSQL Behavior       | Alternative                     |
| ------------------- | ------------------- | ------------------------------- |
| `ForeignKey`        | FK constraint fails | `BigIntegerField` / `UUIDField` |
| `ArrayField`        | Not a stored type   | `JSONField` with list           |
| `HStoreField`       | Not supported       | `JSONField`                     |
| `SearchVectorField` | No FTS              | External search (OpenSearch)    |
| `CITextField`       | No citext extension | `CharField` + `lower()` queries |

## 4. Migrations (One DDL Per Transaction)

```python
# Split complex migrations into separate files

# 0001_create_users.py
class Migration(migrations.Migration):
    operations = [
        migrations.CreateModel(name='User', fields=[
            ('id', models.UUIDField(primary_key=True, default=uuid.uuid4)),
            ('email', models.CharField(max_length=255)),
        ]),
    ]

# 0002_add_users_email_index.py (SEPARATE migration)
class Migration(migrations.Migration):
    operations = [
        migrations.RunSQL("CREATE UNIQUE INDEX ASYNC idx_users_email ON myapp_user (email)"),
    ]
```

## 5. OCC Retry Decorator

```python
import time, random
from django.db import OperationalError, transaction

def with_occ_retry(max_retries=5):
    def decorator(func):
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    with transaction.atomic():
                        return func(*args, **kwargs)
                except OperationalError as e:
                    if hasattr(e, '__cause__') and hasattr(e.__cause__, 'pgcode'):
                        if e.__cause__.pgcode == '40001' and attempt < max_retries - 1:
                            delay = min(0.05 * (2 ** attempt) + random.uniform(0, 0.05), 5.0)
                            time.sleep(delay)
                            continue
                    raise
        return wrapper
    return decorator

# Usage:
@with_occ_retry()
def create_ticket(org_id, reporter_id, title):
    ticket = Ticket(org_id=org_id, reporter_id=reporter_id, title=title)
    ticket.full_clean()
    ticket.save()
    return ticket
```

## 6. Collation (ORDER BY)

```python
# C collation: uppercase sorts before lowercase
# For case-insensitive ordering:
from django.db.models.functions import Lower
Organization.objects.order_by(Lower('name'))
```

## 7. Settings to Remove

```python
# Remove or avoid:
# - django.contrib.postgres (ArrayField, HStoreField)
# - CONN_MAX_AGE > 3600 (DSQL timeout is 1 hour)
```

## 8. Checklist

- [ ] Install `aurora-dsql-django` and `boto3`
- [ ] Change ENGINE to `aurora_dsql_django`
- [ ] Remove USER/PASSWORD from database config
- [ ] Replace all `ForeignKey` with plain ID fields
- [ ] Add `clean()` or signal-based FK validation
- [ ] Use `UUIDField` for primary keys
- [ ] Add OCC retry decorator
- [ ] Set `CONN_MAX_AGE` ≤ 1800
- [ ] Split migrations to one DDL per file
- [ ] Use `RunSQL("CREATE INDEX ASYNC ...")` for indexes
- [ ] Test ORDER BY with C collation
