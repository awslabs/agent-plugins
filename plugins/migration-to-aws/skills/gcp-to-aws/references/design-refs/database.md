# Database Services Design Rubric

**Applies to:** Cloud SQL, Firestore, BigQuery, Memorystore (Redis)

**Quick lookup (no rubric):** Check `fast-path.md` first (Cloud SQL PostgreSQL → RDS Aurora, Cloud SQL MySQL → RDS Aurora, etc.)

## Eliminators (Hard Blockers)

| GCP Service            | AWS        | Blocker                                                                                                    |
| ---------------------- | ---------- | ---------------------------------------------------------------------------------------------------------- |
| Firestore              | DynamoDB   | ACID transactions spanning >100 items required → use RDS (DynamoDB limit: 100 items/transaction)           |
| BigQuery               | Redshift   | OLTP-level latency (<100ms) required → use DynamoDB (point lookups) or Aurora (SQL OLTP); Redshift is OLAP |
| Cloud SQL (PostgreSQL) | RDS Aurora | PostGIS extension → supported (Aurora supports PostGIS)                                                    |

## Signals (Decision Criteria)

### Cloud SQL

- **PostgreSQL, MySQL, SQL Server** → Direct RDS mapping (fast-path)
- **High availability required** → RDS Multi-AZ or Aurora (preferred)
- **Dev/test sizing** → RDS Aurora Serverless v2 (scales to 0)
- **Production, always-on** → RDS Aurora Provisioned (or Serverless v2 if fluctuating)

### Firestore

- **Flexible schema** + **NoSQL** → DynamoDB
- **Strong consistency required** → DynamoDB supports strongly consistent reads via `ConsistentRead` parameter
- **Real-time sync** + **offline support** → DynamoDB Streams + Amplify (app-level)

### BigQuery

- **Data warehouse / OLAP analytics** → Redshift
- **Ad-hoc SQL queries** → Athena (serverless SQL; cheaper for infrequent queries)
- **ML models in warehouse** → Redshift ML (or SageMaker) vs BigQuery ML

### Memorystore (Redis)

- **In-memory cache** → ElastiCache Redis (fast-path, 1:1 mapping)
- **Cluster mode enabled** → ElastiCache Redis with cluster mode
- **High availability required** → ElastiCache Redis Multi-AZ with auto-failover

## 6-Criteria Rubric

Apply in order:

1. **Eliminators**: Does GCP config require AWS-unsupported features? If yes: switch
2. **Operational Model**: Managed (Aurora, DynamoDB) vs Provisioned (EC2-based RDS)?
   - Prefer managed unless: Production + cost-optimized + predictable load → Provisioned RDS
3. **User Preference**: From `clarified.json`, q5 (database requirements)?
   - `"structured"` → RDS (relational)
   - `"document"` → DynamoDB (NoSQL)
   - `"analytics"` → Redshift or Athena
4. **Feature Parity**: Does GCP config need features unavailable in AWS?
   - Example: Cloud SQL with binary log replication → Aurora (full support)
   - Example: Firestore with offline-first SDK → DynamoDB (plus app-level sync)
5. **Cluster Context**: Are other resources in cluster using RDS? Prefer same family
6. **Simplicity**: Fewer moving parts = higher score
   - Serverless > Provisioned > Self-Managed

## Examples

### Example 1: Cloud SQL PostgreSQL (dev environment)

- GCP: `google_sql_database_instance` (database_version=POSTGRES_13, region=us-central1)
- Signals: PostgreSQL, dev tier (implied from sizing)
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): Aurora Serverless v2 (dev best practice)
- → **AWS: RDS Aurora PostgreSQL Serverless v2 (0.5-1 ACU, dev tier)**
- Confidence: `deterministic`

### Example 2: Firestore (mobile app)

- GCP: `google_firestore_document` (root_path=users, auto_id=true)
- Signals: NoSQL, real-time, offline-first (inferred from Firestore choice)
- Criterion 1 (Eliminators): PASS (DynamoDB supports eventual consistency)
- Criterion 2 (Operational Model): DynamoDB (managed NoSQL)
- Criterion 3 (User Preference): If q5=`"document"` → DynamoDB confirmed
- → **AWS: DynamoDB (on-demand billing for dev)**
- Confidence: `inferred`

### Example 3: BigQuery (analytics)

- GCP: `google_bigquery_dataset` (location=us, schema=[large table])
- Signals: Analytics warehouse, large queries
- Criterion 1 (Eliminators): PASS
- Criterion 2 (Operational Model): Redshift (managed data warehouse) or Athena (serverless SQL)
- Criterion 3 (User Preference): If q6=`cost_sensitive` → Athena (pay per query, no idle cost)
- → **AWS: Athena (Glue catalog, parquet format in S3)**
- Confidence: `inferred`

## Output Schema

```json
{
  "gcp_type": "google_sql_database_instance",
  "gcp_address": "prod-postgres-db",
  "gcp_config": {
    "database_version": "POSTGRES_13",
    "region": "us-central1",
    "tier": "db-custom-2-7680"
  },
  "aws_service": "RDS Aurora PostgreSQL",
  "aws_config": {
    "engine_version": "14.7",
    "instance_class": "db.r6g.xlarge",
    "multi_az": true,
    "region": "us-east-1"
  },
  "confidence": "deterministic",
  "rationale": "1:1 mapping; Cloud SQL PostgreSQL → RDS Aurora PostgreSQL",
  "rubric_applied": [
    "Eliminators: PASS",
    "Operational Model: Managed RDS Aurora",
    "User Preference: Structured (q5)",
    "Feature Parity: Full (binary logs, replication)",
    "Cluster Context: Consistent with app tier",
    "Simplicity: RDS Aurora (managed, multi-AZ)"
  ]
}
```
