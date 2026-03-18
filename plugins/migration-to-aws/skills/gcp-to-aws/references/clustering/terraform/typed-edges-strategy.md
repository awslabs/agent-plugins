# Terraform Clustering: Typed Edge Strategy

Infers edge types from HCL context to classify relationships between resources.

## Pass 1: Extract References from HCL

Parse HCL configuration text for all `resource_type.name.attribute` patterns:

- Regex: `(google_\w+)\.(\w+)\.(\w+)` or `google_\w+\.[\w\.]+`
- Capture fully qualified references: `google_sql_database_instance.prod.id`
- Include references in: attribute values, `depends_on` arrays, variable interpolations

Store each reference with:

- `reference`: target resource address
- `field_path`: HCL attribute path where reference appears
- `raw_context`: surrounding HCL text (10 lines for LLM context)

## Pass 2: Classify Edge Type by Field Context

For each reference, determine edge type:

### Data Dependencies

Field name matches: `DATABASE*`, `DB_*`, `SQL*`, `CONNECTION_*`

Environment variable name matches: `DATABASE*`, `DB_HOST`, `SQL_*`

- **Type**: `data_dependency`
- **Example**: `google_cloud_run_service.app.env.DATABASE_URL` → `google_sql_database_instance.prod.id`

### Cache Dependencies

Field name matches: `REDIS*`, `CACHE*`, `MEMCACHE*`

- **Type**: `cache_dependency`
- **Example**: `google_cloudfunctions_function.worker.env.REDIS_HOST` → `google_redis_instance.cache.host`

### Publish Dependencies

Field name matches: `PUBSUB*`, `TOPIC*`, `QUEUE*`, `STREAM*`

- **Type**: `publishes_to`
- **Example**: `google_cloud_run_service.publisher.env.PUBSUB_TOPIC` → `google_pubsub_topic.events.id`

### Storage Dependencies

Field name matches: `BUCKET*`, `STORAGE*`, `S3*`

Direction determined by context:

- Write context (upload, save, persist) → `writes_to`
- Read context (download, fetch, load) → `reads_from`
- Bidirectional → Both edge types

- **Example**: `google_cloud_run_service.worker.env.STORAGE_BUCKET` → `google_storage_bucket.data.name`

### Network Path

Field name: `vpc_connector`

- **Type**: `network_path`
- **Example**: `google_cloudfunctions_function.app.vpc_connector` → `google_vpc_access_connector.main.id`

### Encryption

Field name: `kms_key_name`, `encryption_key`, `key_ring`

- **Type**: `encryption`
- **Example**: `google_sql_database_instance.db.backup_encryption_key_name` → `google_kms_crypto_key.sql.id`

### Orchestration

Explicit `depends_on` array

- **Type**: `orchestration`
- **Example**: `depends_on = [google_project_service.run]`

## Default Fallback

If no patterns match, use LLM to infer edge type from:

- Resource types (compute → storage likely data_dependency)
- Field names and values
- Raw HCL context

If LLM uncertain: `unknown_dependency` with confidence field.

## Evidence Structure

Store edge evidence:

```json
{
  "target": "google_sql_database_instance.prod",
  "relationship_type": "data_dependency",
  "evidence": {
    "field_path": "env.DATABASE_URL",
    "env_var_name": "DATABASE_URL",
    "reference": "google_sql_database_instance.prod.connection_name"
  }
}
```

All edges stored in resource's `typed_edges[]` array.
