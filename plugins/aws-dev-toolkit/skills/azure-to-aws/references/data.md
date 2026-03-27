# Azure to AWS: Data Service Mappings

## Azure SQL → RDS for SQL Server or Aurora

| Aspect | Azure SQL | RDS SQL Server | Aurora PostgreSQL |
|---|---|---|---|
| Compatibility | SQL Server (native) | SQL Server (native) | Requires query migration |
| Elastic pools | Yes (shared DTU/vCore) | No | Aurora Serverless v2 |
| Hyperscale | Yes (100 TB+) | No | Aurora auto-scales storage |
| Serverless tier | Yes (auto-pause) | No | Aurora Serverless v2 |
| Pricing | DTU or vCore | Instance-based | Instance or serverless |
| Licensing | Included | License included or BYOL | Open source |

**Migration**: AWS DMS supports Azure SQL → RDS SQL Server with minimal downtime. For Aurora PostgreSQL, use AWS Schema Conversion Tool (SCT) first.

```bash
# Azure: Inventory SQL databases
az sql server list --output table
az sql db list --server SERVER --resource-group RG --output table
az sql elastic-pool list --server SERVER --resource-group RG --output table

# AWS: Create RDS SQL Server
aws rds create-db-instance --engine sqlserver-se --db-instance-class db.r6i.xlarge --allocated-storage 100 --db-instance-identifier my-sql
```

## Cosmos DB → DynamoDB / DocumentDB / Neptune

Map by API used:

| Cosmos DB API | AWS Service | Data Model |
|---|---|---|
| Core (SQL/NoSQL) | DynamoDB | Key-value / document |
| MongoDB | DocumentDB | Document (MongoDB wire protocol) |
| Gremlin | Neptune | Graph |
| Table | DynamoDB | Key-value |
| Cassandra | Amazon Keyspaces | Wide-column |

**Gotchas**:
- Cosmos DB RU pricing → DynamoDB WCU/RCU conversion: 1 RU ≈ 1 strongly consistent read of 4KB item. Model carefully.
- Cosmos DB change feed → DynamoDB Streams (similar but different API)
- Cosmos DB stored procedures (JavaScript) have no DynamoDB equivalent — move to Lambda
- Cosmos DB's 5 consistency levels → DynamoDB offers eventual and strong only

## Blob Storage → S3

| Azure | AWS |
|---|---|
| Storage Account → Container → Blob | Bucket → Object |
| Hot / Cool / Archive | Standard / IA / Glacier |
| AzCopy | aws s3 cp/sync |
| SAS tokens | Presigned URLs |
| Lifecycle management | S3 Lifecycle rules |
| Blob index tags | S3 object tags |
| Immutable storage (WORM) | S3 Object Lock |

**Gotcha**: Azure Storage Accounts group Blob, File, Queue, Table storage. AWS separates these into S3, EFS, SQS, DynamoDB.

## Synapse Analytics → Redshift + Glue + Athena

| Synapse Component | AWS Service | Notes |
|---|---|---|
| Dedicated SQL pool | Redshift (provisioned or serverless) | Closest for warehouse workloads |
| Serverless SQL pool | Athena | Query S3 data without provisioning |
| Spark pool | EMR Serverless or Glue Spark | Spark processing |
| Pipelines | Glue ETL + Step Functions | Data pipeline orchestration |
| Data Explorer | OpenSearch or Timestream | Log/telemetry analytics |

This is a COMPLEX migration. Don't try to replicate Synapse 1:1 — choose the right AWS service for each component.

## Service Bus → SQS + SNS (or Amazon MQ)

| Service Bus Feature | AWS Equivalent |
|---|---|
| Queues | SQS Standard or FIFO |
| Topics + Subscriptions | SNS + SQS |
| Sessions (ordered by key) | SQS FIFO (MessageGroupId) |
| Dead-letter queue | SQS DLQ |
| Duplicate detection | SQS FIFO deduplication |
| Scheduled delivery | SQS delay queues (max 15 min) or EventBridge |
| Message deferral | No direct equivalent — use SQS visibility timeout |
| AMQP protocol | Amazon MQ (RabbitMQ or ActiveMQ) |

**Gotcha**: Service Bus max message size: Standard 256KB, Premium 100MB. SQS max 256KB (use S3 for larger via Extended Client Library).

## Event Hubs → Kinesis Data Streams or MSK

Event Hubs is very close to Kafka (has Kafka protocol support). For Kafka workloads, MSK is the direct path. For non-Kafka, Kinesis Data Streams. Event Hubs Capture (auto-archive) → Kinesis Data Firehose to S3.
