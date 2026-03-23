# GCP Service → Design Reference Mapping

## Compute Services

| GCP Service         | Resource Type                    | Reference File | Fast-Path          |
| ------------------- | -------------------------------- | -------------- | ------------------ |
| Cloud Run           | `google_cloud_run_service`       | `compute.md`   | Fargate            |
| Cloud Functions     | `google_cloudfunctions_function` | `compute.md`   | Lambda             |
| Compute Engine (VM) | `google_compute_instance`        | `compute.md`   | EC2 or Fargate     |
| GKE                 | `google_container_cluster`       | `compute.md`   | EKS                |
| App Engine          | `google_app_engine_application`  | `compute.md`   | Fargate or Amplify |

## Database Services

| GCP Service            | Resource Type                  | Reference File | Fast-Path             |
| ---------------------- | ------------------------------ | -------------- | --------------------- |
| Cloud SQL (PostgreSQL) | `google_sql_database_instance` | `database.md`  | RDS Aurora PostgreSQL |
| Cloud SQL (MySQL)      | `google_sql_database_instance` | `database.md`  | RDS Aurora MySQL      |
| Cloud SQL (SQL Server) | `google_sql_database_instance` | `database.md`  | RDS SQL Server        |
| Firestore (instance)   | `google_firestore_database`    | `database.md`  | DynamoDB              |
| Firestore (document)   | `google_firestore_document`    | `database.md`  | DynamoDB              |
| BigQuery               | `google_bigquery_dataset`      | `database.md`  | Redshift or Athena    |
| Memorystore (Redis)    | `google_redis_instance`        | `database.md`  | ElastiCache Redis     |

## Storage Services

| GCP Service         | Resource Type           | Reference File | Fast-Path |
| ------------------- | ----------------------- | -------------- | --------- |
| Cloud Storage (GCS) | `google_storage_bucket` | `storage.md`   | S3        |

## Networking Services

| GCP Service          | Resource Type                     | Reference File  | Fast-Path          |
| -------------------- | --------------------------------- | --------------- | ------------------ |
| VPC Network          | `google_compute_network`          | `networking.md` | VPC                |
| Firewall Rules       | `google_compute_firewall`         | `networking.md` | Security Groups    |
| Cloud Load Balancing | `google_compute_forwarding_rule`  | `networking.md` | ALB/NLB            |
| Cloud CDN            | (part of compute_backend_service) | `networking.md` | CloudFront         |
| Cloud DNS            | `google_dns_managed_zone`         | `networking.md` | Route 53           |
| Cloud Interconnect   | (custom config)                   | `networking.md` | AWS Direct Connect |

## Messaging Services

| GCP Service | Resource Type              | Reference File | Fast-Path          |
| ----------- | -------------------------- | -------------- | ------------------ |
| Pub/Sub     | `google_pubsub_topic`      | `messaging.md` | SNS or SQS         |
| Cloud Tasks | `google_cloud_tasks_queue` | `messaging.md` | SQS or EventBridge |

## AI/ML Services

| GCP Service           | Resource Type      | Reference File | Fast-Path               |
| --------------------- | ------------------ | -------------- | ----------------------- |
| Vertex AI (models)    | (custom endpoints) | `ai.md`        | SageMaker               |
| Vertex AI (pipelines) | (custom config)    | `ai.md`        | SageMaker Pipelines     |
| Cloud Vision API      | (managed API)      | `ai.md`        | Textract or Rekognition |

## Secondary/Infrastructure Services

| GCP Service      | Resource Type            | Reference File    | Fast-Path  |
| ---------------- | ------------------------ | ----------------- | ---------- |
| Service Accounts | `google_service_account` | `networking.md`   | IAM Roles  |
| Cloud Monitoring | (managed)                | Not in v1.0 scope | CloudWatch |

---

**Usage:**

1. Extract GCP resource type from Terraform
2. Find in table above
3. If resource found in `fast-path.md` Direct Mappings table: use that mapping (confidence = deterministic)
4. Otherwise: load Reference File listed above and apply 6-criteria rubric (confidence = inferred)
