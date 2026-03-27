# AWS Service Selection Guide

## Compute Decision Tree

| Workload Type | Default Choice | Consider Instead When |
|---|---|---|
| Stateless HTTP API | Lambda + API Gateway | >15min execution, sustained high RPS → Fargate |
| Long-running process | Fargate | GPU needed → EC2, batch → Step Functions + Lambda |
| Container orchestration | ECS Fargate | Team has K8s expertise → EKS |
| Batch processing | Step Functions + Lambda | Large data → EMR Serverless, ML → SageMaker |
| Static site | CloudFront + S3 | SSR needed → Lambda@Edge or CloudFront Functions |

## Database Decision Tree

| Access Pattern | Default Choice | Consider Instead When |
|---|---|---|
| Key-value lookups | DynamoDB | Complex queries → Aurora, full-text search → OpenSearch |
| Relational with joins | Aurora PostgreSQL | Simple schema, low traffic → RDS PostgreSQL |
| Document store | DynamoDB | Need MongoDB compat → DocumentDB |
| Time series | Timestream | Already using InfluxDB → InfluxDB on EC2 |
| Graph relationships | Neptune | Simple graphs → DynamoDB adjacency list |
| Caching | ElastiCache Redis | Simple caching → DAX (if DynamoDB) |

## Messaging & Integration

| Pattern | Default Choice | Notes |
|---|---|---|
| Async decoupling | SQS | FIFO for ordering guarantees, Standard for throughput |
| Pub/sub fan-out | SNS → SQS | EventBridge for event-driven with filtering |
| Event bus | EventBridge | Schema registry for contract enforcement |
| Workflow orchestration | Step Functions | Express for high-volume, short-duration |
| Streaming | Kinesis Data Streams | MSK if team knows Kafka |

## Common Anti-Patterns

- Using SQS as a database (store state in DynamoDB, use SQS for work dispatch)
- Putting everything in one Lambda (separate by bounded context)
- Using API Gateway REST API when HTTP API suffices (HTTP API is cheaper and faster)
- Over-engineering with microservices when a modular monolith on Fargate would work
- Using EKS "because Kubernetes" without the team to support it
