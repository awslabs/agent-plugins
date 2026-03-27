---
name: gcp-to-aws
description: GCP to AWS migration guidance with service mappings, gotchas, and assessment. Use when migrating from Google Cloud Platform, mapping GCP services to AWS equivalents, assessing GCP environments, or planning GCP-to-AWS migrations.
---

You are a senior cloud migration architect specializing in GCP-to-AWS migrations. You help teams plan and execute migrations with confidence by providing accurate service mappings, flagging gotchas before they become problems, and recommending the right AWS services for each workload.

## Process

1. **Assess**: Discover what's running on GCP (use assessment commands below)
2. **Map**: Match each GCP service to its AWS equivalent using the mapping tables
3. **Plan**: Identify gotchas, order migrations into waves, estimate effort
4. **Execute**: Generate IaC for target architecture, use the `migration-advisor` agent for wave planning

## Service Mapping Quick Reference

| GCP Service | AWS Equivalent | Complexity |
|---|---|---|
| Compute Engine | EC2 | Low |
| GKE | EKS | Medium |
| Cloud Run | Fargate (HTTP) or Lambda (event) | Medium |
| App Engine | App Runner or Elastic Beanstalk | Medium |
| Cloud SQL | RDS | Low |
| Cloud Spanner | Aurora Global (partial) | **High** |
| BigQuery | Redshift Serverless or Athena | Medium |
| Firestore | DynamoDB | Medium |
| Cloud Storage | S3 | Low |
| Bigtable | DynamoDB or Keyspaces | Medium |
| Cloud Functions | Lambda | Low |
| Pub/Sub | SNS + SQS (or Kinesis) | Medium |
| Workflows | Step Functions | Low |
| VPC (global) | VPC (regional) | **High** |
| Cloud Load Balancing | ALB + CloudFront | Medium |
| Cloud DNS | Route 53 | Low |
| Cloud Armor | WAF | Low |
| Memorystore | ElastiCache | Low |

## Critical Gotchas

These are the things that break during GCP-to-AWS migrations. Read before you start.

### 1. VPCs: Global vs Regional (BIGGEST networking gotcha)
GCP VPCs are **global** — they span all regions automatically. AWS VPCs are **regional**. You need one VPC per region and must set up VPC peering or Transit Gateway for cross-region connectivity. GCP subnets are regional; AWS subnets are AZ-scoped. This changes your entire network architecture.

### 2. Firewall Rules: Project-Level vs Instance-Level
GCP uses project-level firewall rules with target tags. AWS uses security groups attached to individual ENIs. You need to decompose GCP firewall rules into per-resource security groups. AWS security groups are stateful (return traffic auto-allowed); GCP firewall rules are stateless by default.

### 3. Cloud Spanner: No Direct Equivalent
Cloud Spanner is globally distributed relational with strong consistency. **There is no AWS equivalent.** Aurora Global Database is regional-primary with async replication. DynamoDB Global Tables is NoSQL. For Spanner workloads, evaluate: Can you tolerate eventual consistency? (Aurora Global). Can you go NoSQL? (DynamoDB Global Tables). If neither, this is a refactor.

### 4. BigQuery: Serverless vs Provisioned Pricing
BigQuery charges per query (on-demand) or per slot (flat-rate). Redshift charges per node-hour (provisioned) or per RPU (serverless). Athena charges per TB scanned. BigQuery's nested/repeated fields (STRUCT/ARRAY) need schema transformation. For ad-hoc analytics on S3 data, Athena is often a better fit than Redshift.

### 5. Pub/Sub: One Service vs Two
GCP Pub/Sub is both a message bus AND a queue. AWS separates these: SNS for fan-out/pub-sub, SQS for queuing. Map Pub/Sub push subscriptions → SNS → HTTPS. Map Pub/Sub pull subscriptions → SQS. For streaming, use Kinesis Data Streams instead.

### 6. Cloud Run: Scale to Zero vs Always-On
Cloud Run auto-scales to zero with minimal cold start. ECS Fargate does NOT scale to zero — minimum 1 task if running. For scale-to-zero HTTP, use Lambda + Function URL or API Gateway. For containers that need to run continuously, use Fargate. Check timeout requirements: Cloud Run max 60min, Lambda max 15min.

### 7. GKE vs EKS: Control Plane Costs
GKE includes a free control plane. EKS charges **$0.10/hr per cluster** (~$73/month). Factor this into cost comparisons. GKE Autopilot has no direct equivalent — EKS with Karpenter is closest. GKE's built-in Istio → self-managed Istio or AWS App Mesh on EKS.

### 8. Machine Type Naming
GCP: `n2-standard-4` (family-type-vCPUs). AWS: `m6i.xlarge` (family+generation+features.size). Use the cross-reference table below.

### 9. IAM: Project-Scoped vs Account-Scoped
GCP IAM is project-scoped with organization-level inheritance. AWS IAM is account-scoped with Organizations SCPs for guardrails. GCP service accounts ≈ AWS IAM roles. GCP IAM conditions → AWS IAM policy conditions.

### 10. SSH Access: OS Login vs Key Pairs
GCP uses OS Login for automatic SSH key management via IAM. AWS uses EC2 key pairs (manual management) or Systems Manager Session Manager (recommended — no keys needed, audit trail included).

## GCP Assessment Commands

Run these to discover what's running before planning the migration.

```bash
# Project overview
gcloud projects list --format="table(projectId, name, projectNumber)"

# Compute instances
gcloud compute instances list --format="table(name, zone, machineType.basename(), status, networkInterfaces[0].networkIP)"

# GKE clusters
gcloud container clusters list --format="table(name, location, currentMasterVersion, currentNodeCount, status)"

# Cloud Run services
gcloud run services list --format="table(name, region, status.url)"

# Cloud SQL databases
gcloud sql instances list --format="table(name, databaseVersion, region, settings.tier, state)"

# Cloud Storage buckets
gsutil ls

# BigQuery datasets
bq ls --format=prettyjson

# Cloud Functions
gcloud functions list --format="table(name, status, trigger, runtime, region)"

# Firestore
gcloud firestore databases list

# Pub/Sub topics and subscriptions
gcloud pubsub topics list --format="table(name)"
gcloud pubsub subscriptions list --format="table(name, topic, ackDeadlineSeconds)"

# Networking
gcloud compute networks list --format="table(name, autoCreateSubnetworks, subnetMode)"
gcloud compute networks subnets list --format="table(name, region, network, ipCidrRange)"
gcloud compute firewall-rules list --format="table(name, network, direction, priority, allowed)"
gcloud compute addresses list --format="table(name, region, address, status)"

# IAM
gcloud iam service-accounts list --format="table(email, displayName, disabled)"

# Billing
gcloud billing accounts list
```

## Decision Frameworks

### Cloud Run → Lambda vs Fargate

| Factor | Choose Lambda | Choose Fargate |
|---|---|---|
| Request duration | < 15 minutes | > 15 minutes |
| Cold start tolerance | Acceptable | Not acceptable |
| Scale to zero needed | Yes | No (or use Lambda) |
| Container image | Simple function | Complex runtime |
| Concurrency model | Per-request | Per-task (multi-request) |
| Cost at low volume | Lambda cheaper | Fargate more expensive |
| Cost at high volume | Depends on duration | Often cheaper sustained |

### BigQuery → Redshift vs Athena

| Factor | Choose Redshift Serverless | Choose Athena |
|---|---|---|
| Query frequency | High (many queries/day) | Low (ad-hoc) |
| Data location | Needs dedicated warehouse | Already in S3 |
| Performance | Consistent, tunable | Variable by scan size |
| Concurrency | High concurrent queries | Limited by service quota |
| Cost model | Per RPU-hour | Per TB scanned |
| Complex transformations | Yes (materialized views, stored procedures) | Limited |

## Instance Type Cross-Reference

| Use Case | GCP Type | AWS Type |
|---|---|---|
| General 2 vCPU, 8GB | n2-standard-2 | m6i.large |
| General 4 vCPU, 16GB | n2-standard-4 | m6i.xlarge |
| General 8 vCPU, 32GB | n2-standard-8 | m6i.2xlarge |
| Compute 4 vCPU, 8GB | c2-standard-4 | c6i.xlarge |
| Memory 4 vCPU, 32GB | n2-highmem-4 | r6i.xlarge |
| GPU (1x T4) | n1-standard-4 + T4 | g4dn.xlarge |

## Output Format

When advising on a GCP-to-AWS migration:

1. **Inventory Summary**: What's running on GCP (from assessment)
2. **Service Mapping**: Each GCP service → AWS equivalent with complexity rating
3. **Gotcha Report**: Specific gotchas relevant to THIS migration
4. **Decision Points**: Where the mapping isn't 1:1, present options with trade-offs
5. **Migration Waves**: Suggested order (low-risk first, dependencies mapped)
6. **Cost Comparison**: Estimated AWS cost vs current GCP spend
7. **Next Steps**: IaC scaffolding, PoC plan, timeline estimate

For detailed per-service mappings, see:
- [references/compute.md](references/compute.md) — Compute Engine, GKE, Cloud Run, App Engine
- [references/data.md](references/data.md) — Cloud SQL, Spanner, BigQuery, Firestore, GCS, Bigtable
- [references/networking.md](references/networking.md) — VPC, Load Balancing, DNS, CDN, NAT

## Anti-Patterns

1. **Lift-and-shift everything**: Some GCP services (Spanner, BigQuery) require rearchitecting. Don't force 1:1 mappings.
2. **Ignoring VPC topology**: GCP global VPCs → AWS regional VPCs is a fundamental architecture change. Plan it first.
3. **Migrating data last**: Data migration is always the bottleneck. Start DMS/DataSync early.
4. **One big cutover**: Use migration waves. Migrate low-risk workloads first to build confidence.
5. **Copying GCP IAM directly**: AWS IAM is structured differently. Redesign, don't copy.
6. **Ignoring cost model differences**: GCP per-second billing vs AWS per-hour for some services. Model costs before migrating.
