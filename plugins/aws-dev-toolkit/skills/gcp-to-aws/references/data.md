# GCP to AWS: Data Service Mappings

## Cloud SQL → RDS

Nearly 1:1 mapping. Both support MySQL, PostgreSQL, SQL Server.

| Aspect | GCP Cloud SQL | AWS RDS |
|---|---|---|
| HA | Regional instances (automatic) | Multi-AZ deployment |
| Max storage | 64 TB | Varies by engine (64 TB for Aurora) |
| IAM auth | Cloud SQL IAM authentication | RDS IAM authentication |
| Performance | Cloud SQL Insights | Performance Insights |
| Proxy | Cloud SQL Auth Proxy | RDS Proxy |

**Migration**: Use AWS DMS with Cloud SQL as source. Requires public IP or proxy for connectivity.

```bash
# GCP: Get Cloud SQL details
gcloud sql instances describe INSTANCE --format=json

# AWS: Create equivalent RDS instance
aws rds create-db-instance --db-instance-identifier my-db --engine postgres --db-instance-class db.r6g.xlarge --allocated-storage 100
```

## Cloud Spanner → Aurora Global (HARD MIGRATION)

**No direct equivalent.** Cloud Spanner provides globally distributed, strongly consistent relational database. Options:

| Approach | Service | Trade-off |
|---|---|---|
| Accept eventual consistency | Aurora Global Database | Async cross-region replication, strong within region |
| Go NoSQL | DynamoDB Global Tables | Multi-region, but not relational |
| Application-level consistency | Aurora + custom logic | Complex, error-prone |

**Recommendation**: If strong global consistency is non-negotiable, this workload may need to stay on GCP or be fundamentally rearchitected.

## BigQuery → Redshift Serverless or Athena

| Aspect | BigQuery | Redshift Serverless | Athena |
|---|---|---|---|
| Pricing | Per query (on-demand) or per slot | Per RPU-hour | Per TB scanned |
| Serverless | Yes (native) | Yes (serverless option) | Yes |
| Nested types | STRUCT/ARRAY native | SUPER type (different syntax) | Supported via Glue |
| ML | BigQuery ML | Redshift ML (SageMaker) | N/A (use SageMaker) |
| Streaming | BigQuery Storage Write API | Kinesis Firehose → Redshift | Kinesis Firehose → S3 → Athena |

**Gotcha**: BigQuery's nested/repeated fields need schema transformation. BigQuery BI Engine (in-memory caching) → Redshift materialized views.

## Firestore → DynamoDB

| Aspect | Firestore | DynamoDB |
|---|---|---|
| Model | Documents with subcollections | Items in tables (single-table design) |
| Real-time | Built-in real-time listeners | DynamoDB Streams + AppSync |
| Security | Firestore Security Rules (client-side) | IAM + fine-grained access control |
| Offline sync | Built-in (mobile SDKs) | AppSync + Amplify DataStore |
| Pricing | Per read/write/delete operation | Per RCU/WCU or on-demand |
| Indexing | Automatic on all fields | Must define GSIs/LSIs explicitly |

**Gotcha**: Firestore subcollections don't map to DynamoDB. Flatten to single-table design with composite keys (PK: `ENTITY#id`, SK: `SUB#subid`).

## Cloud Storage → S3

Nearly 1:1 mapping.

| GCP | AWS |
|---|---|
| gsutil cp/mv/ls | aws s3 cp/mv/ls |
| Uniform bucket-level access | Bucket policies |
| Signed URLs | Presigned URLs |
| Object lifecycle | S3 Lifecycle rules |
| Transfer Service | DataSync or S3 Batch Operations |
| Nearline/Coldline/Archive | S3 IA/Glacier Instant/Glacier |

**Gotcha**: GCS HMAC keys provide S3-compatible access — useful during migration for applications that can talk to S3 API. No equivalent to S3 Select or S3 Object Lambda in GCS.

## Bigtable → DynamoDB or Keyspaces

Bigtable is wide-column (HBase-compatible). For performance workloads, DynamoDB is closest. For HBase API compatibility, use Amazon Keyspaces (Cassandra-compatible) or EMR with HBase.

**Gotcha**: Bigtable's tall-and-narrow schema patterns may need redesign for DynamoDB's partition/sort key model.
