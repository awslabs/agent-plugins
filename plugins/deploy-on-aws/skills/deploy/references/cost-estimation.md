# Cost Estimation Patterns

Use the **awspricing** MCP server to get accurate cost estimates before generating IaC.

## Workflow

1. Identify all AWS services in the architecture
2. Query pricing for each service
3. Calculate monthly estimates based on expected usage
4. Present total before proceeding

## Service Codes

| Service           | Code                | Notes                                          |
| ----------------- | ------------------- | ---------------------------------------------- |
| Fargate           | `AmazonECS`         | Filter by `usagetype` containing "Fargate"     |
| Aurora PostgreSQL | `AmazonRDS`         | Filter: `databaseEngine` = "Aurora PostgreSQL" |
| Aurora MySQL      | `AmazonRDS`         | Filter: `databaseEngine` = "Aurora MySQL"      |
| RDS PostgreSQL    | `AmazonRDS`         | Filter: `databaseEngine` = "PostgreSQL"        |
| DocumentDB        | `AmazonDocDB`       | MongoDB-compatible managed database            |
| ALB               | `AWSELB`            | Application Load Balancer                      |
| S3                | `AmazonS3`          | Storage and requests                           |
| CloudFront        | `AmazonCloudFront`  | CDN distribution                               |
| Amplify           | `AWSAmplify`        | Hosting, build minutes                         |
| Lambda            | `AWSLambda`         | Requests and duration                          |
| DynamoDB          | `AmazonDynamoDB`    | On-demand or provisioned                       |
| Secrets Manager   | `AWSSecretsManager` | Per secret per month                           |

## Fargate Pricing

Fargate charges per vCPU-hour and per GB-hour. Query with usagetype filters:

```
usagetype: "USE1-Fargate-vCPU-Hours:perCPU"  # vCPU pricing
usagetype: "USE1-Fargate-GB-Hours"           # Memory pricing
```

**Typical small app (0.5 vCPU, 1GB):**

- us-east-1: ~$18/month running 24/7

## Aurora Serverless v2 Pricing

Aurora Serverless v2 charges per ACU-hour (Aurora Capacity Unit).

- Minimum: 0.5 ACU
- 1 ACU ≈ 2GB memory

**Dev estimate (0.5-2 ACU range):**

- ~$45-90/month depending on usage patterns

**Production estimate (2-8 ACU range):**

- ~$180-360/month depending on load

## DocumentDB Serverless Pricing

DocumentDB Serverless charges per DCU-hour (DocumentDB Capacity Unit),
storage (GB-month), and I/O (standard config only).

- Minimum: 0.5 DCU
- 1 DCU ≈ 2 GiB memory

**Dev estimate (0.5-2 DCU range, 10GB storage):**

- ~$35-120/month depending on usage patterns (scales to 0.5 DCU when idle)

**Production estimate (2-8 DCU range, 100GB storage, multi-AZ):**

- ~$130-400/month depending on load

## Quick Reference Estimates

**Small web app (Fargate + Aurora Serverless v2 + ALB):**

- Dev: ~$70-100/month
- Production: ~$200-400/month

**Small web app (Fargate + DocumentDB Serverless + ALB):**

- Dev: ~$70-155/month
- Production: ~$200-450/month

**Static site / SPA (Amplify Hosting):**

- Low traffic: ~$0-5/month (free tier covers most small sites)
- High traffic: ~$15-40/month

**Static site (S3 + CloudFront):**

- Low traffic: ~$1-5/month
- High traffic: ~$20-50/month

**Serverless API (Lambda + API Gateway + DynamoDB):**

- Low traffic: ~$5-20/month
- High traffic: scales with requests

## Presenting Estimates

Always show:

1. Per-service breakdown
2. Monthly total
3. Key assumptions (e.g., "assumes 24/7 uptime", "assumes 1M requests/month")
4. Cost optimization tips if relevant
