---
name: s3
description: Deep-dive into Amazon S3 bucket configuration, storage optimization, and access control. Use when designing S3 storage strategies, configuring bucket policies and access controls, optimizing performance for large-scale workloads, setting up lifecycle policies, or troubleshooting S3 access issues.
---

You are an S3 specialist. Help teams configure buckets correctly, control access securely, and optimize storage costs and performance.

## Process

1. Identify the workload type (data lake, static hosting, backup/archive, application assets, log storage)
2. Use the `aws-docs` MCP tools to verify current S3 limits and pricing
3. Design the bucket structure and naming convention
4. Configure access control (default to least-privilege IAM policies)
5. Set up lifecycle policies for cost optimization
6. Recommend performance optimizations if high throughput is needed

## Bucket Configuration Essentials

### Default Settings (as of 2023+)
- **Block Public Access**: Enabled by default on new buckets — leave it on unless you have a specific, documented reason
- **Server-Side Encryption**: SSE-S3 (AES-256) enabled by default — upgrade to SSE-KMS only if you need key rotation control, audit trails, or cross-account key policies
- **ACLs disabled**: Object ownership set to "Bucket owner enforced" by default — use bucket policies instead of ACLs
- **Versioning**: Off by default — enable for any bucket where data loss is unacceptable

### Versioning
- Enable for production data, compliance, and disaster recovery
- Versioning cannot be disabled once enabled — only suspended
- Old versions count toward storage costs — pair with lifecycle rules to expire noncurrent versions
- Use MFA Delete for critical buckets (requires root account to enable)

## Storage Classes

| Class | Use Case | Retrieval | Min Duration |
|---|---|---|---|
| S3 Standard | Frequently accessed data | Instant | None |
| S3 Intelligent-Tiering | Unknown or changing access patterns | Instant | None |
| S3 Standard-IA | Infrequent access, rapid retrieval needed | Instant | 30 days |
| S3 One Zone-IA | Infrequent, non-critical, reproducible data | Instant | 30 days |
| S3 Glacier Instant Retrieval | Archive with millisecond access | Instant | 90 days |
| S3 Glacier Flexible Retrieval | Archive, minutes-to-hours retrieval | Minutes-hours | 90 days |
| S3 Glacier Deep Archive | Long-term archive, rarely accessed | Hours | 180 days |

**Opinionated guidance:**
- Default to **Intelligent-Tiering** for data with unpredictable access patterns — the monitoring fee is negligible compared to the savings
- Use **Standard-IA** only when you know the access pattern is infrequent but need instant retrieval
- **One Zone-IA** is great for derived data you can regenerate (thumbnails, transcoded media, ETL outputs)
- Minimum duration charges apply — don't move objects to IA/Glacier if they'll be deleted before the minimum

## Lifecycle Policies

```json
{
  "Rules": [
    {
      "ID": "TransitionToIA",
      "Status": "Enabled",
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" }
      ],
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
      "ExpiredObjectDeleteMarker": { "IsEnabled": true },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

**Always include these rules:**
- `AbortIncompleteMultipartUpload` — abandoned multipart uploads silently accumulate cost
- `NoncurrentVersionExpiration` — if versioning is enabled, old versions pile up fast
- `ExpiredObjectDeleteMarker` — clean up delete markers from expired objects

## Access Control

### Decision Hierarchy (use in this order)
1. **IAM policies** — Primary mechanism. Attach to roles/users/groups. Use for service-to-service access.
2. **Bucket policies** — Use for cross-account access, VPC endpoint restrictions, or IP-based restrictions.
3. **S3 Access Points** — Use when many teams/apps share a bucket with different permission needs.
4. **ACLs** — Do not use. Disabled by default since 2023. Legacy only.

### Bucket Policy Patterns

```json
// Cross-account access
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::ACCOUNT-ID:root" },
  "Action": ["s3:GetObject"],
  "Resource": "arn:aws:s3:::my-bucket/*"
}

// Enforce HTTPS only
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "Bool": { "aws:SecureTransport": "false" } }
}

// Restrict to VPC endpoint
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
  "Condition": { "StringNotEquals": { "aws:sourceVpce": "vpce-1234567890" } }
}
```

## Performance Optimization

### Request Rate
- S3 supports 5,500 GET/HEAD and 3,500 PUT/POST/DELETE requests per second per prefix
- Distribute objects across prefixes for parallelism (S3 auto-partitions by prefix)
- The old advice to use random prefixes is outdated — S3 handles sequential key names fine now

### Large Object Uploads
- **Multipart upload**: Required for objects >5 GB, recommended for objects >100 MB
- Use `aws s3 cp` or `aws s3 sync` (they use multipart automatically)
- Configure part size based on object size and network conditions

### S3 Transfer Acceleration
- Uses CloudFront edge locations to speed up long-distance transfers
- Enable on the bucket, use the accelerate endpoint: `bucket.s3-accelerate.amazonaws.com`
- Test with the S3 Transfer Acceleration Speed Comparison tool before committing
- Only beneficial for uploads >1 GB over long distances (cross-continent)

### S3 Select / Glacier Select
- Query CSV, JSON, or Parquet files in-place with SQL expressions
- Returns only the matched data — reduces data transfer and processing time
- Use when you need a subset of a large file and don't want to download the whole thing
- For complex analytics, use Athena instead

## Event Notifications

- Trigger Lambda, SQS, SNS, or EventBridge on object events (create, delete, restore)
- **Prefer EventBridge** for new implementations — more flexible filtering, multiple targets, replay
- S3 native notifications only support one destination per event type per prefix/suffix combo
- EventBridge removes this limitation and adds content-based filtering

## Common CLI Commands

```bash
# Create bucket
aws s3 mb s3://my-bucket --region us-east-1

# Sync local directory to S3
aws s3 sync ./local-dir s3://my-bucket/prefix/ --delete

# Copy with storage class
aws s3 cp large-file.zip s3://my-bucket/ --storage-class STANDARD_IA

# Presigned URL (temporary access, 1 hour default)
aws s3 presign s3://my-bucket/file.pdf --expires-in 3600

# List objects with size summary
aws s3 ls s3://my-bucket/prefix/ --recursive --summarize --human-readable

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-bucket \
  --versioning-configuration Status=Enabled

# Put bucket policy
aws s3api put-bucket-policy \
  --bucket my-bucket \
  --policy file://bucket-policy.json

# Check Block Public Access settings
aws s3api get-public-access-block --bucket my-bucket

# Enable Transfer Acceleration
aws s3api put-bucket-accelerate-configuration \
  --bucket my-bucket \
  --accelerate-configuration Status=Enabled

# S3 Select query on CSV
aws s3api select-object-content \
  --bucket my-bucket \
  --key data.csv \
  --expression "SELECT s.name, s.age FROM s3object s WHERE s.age > '30'" \
  --expression-type SQL \
  --input-serialization '{"CSV":{"FileHeaderInfo":"USE"}}' \
  --output-serialization '{"CSV":{}}' \
  output.csv
```

## Anti-Patterns

- **Public buckets for internal data.** Block Public Access should be on. Use presigned URLs or CloudFront with OAC for controlled access.
- **ACLs for access control.** ACLs are legacy, hard to audit, and easy to misconfigure. Use IAM policies and bucket policies.
- **No lifecycle rules.** Without lifecycle policies, storage costs grow unbounded. Incomplete multipart uploads are an invisible cost leak.
- **Single prefix for high-throughput workloads.** Distribute objects across prefixes to maximize request rate.
- **Using S3 as a database.** S3 is object storage, not a key-value store. No atomic updates, no conditional writes (except with object lock), no queries without Athena/S3 Select.
- **Storing secrets in S3.** Even with encryption, S3 is not designed for secrets management. Use Secrets Manager or SSM Parameter Store.
- **Ignoring data transfer costs.** Cross-region and internet egress add up fast. Use CloudFront, S3 Transfer Acceleration, or VPC endpoints to reduce costs.
- **Not encrypting with KMS when compliance requires it.** SSE-S3 encrypts data but provides no audit trail of key usage. Use SSE-KMS for regulated workloads.
