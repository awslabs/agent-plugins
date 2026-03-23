# Storage Services Design Rubric

**Applies to:** Cloud Storage (GCS)

**Quick lookup (no rubric):** Check `fast-path.md` first (Cloud Storage → S3, deterministic)

## Deterministic Mapping

**Cloud Storage (`google_storage_bucket`) → S3 (`aws_s3_bucket`)**

Confidence: `deterministic` (always 1:1, no decision tree)

**Behavior preservation:**

- Bucket versioning → S3 versioning
- Lifecycle rules → S3 Lifecycle policies
- Access control (UNIFORM vs FINE-GRAINED) → S3 ACLs + Bucket Policies
- Regional location → S3 region selection
- Encryption (default or CSEK) → S3 encryption (default AES-256 or KMS)

## GCS → S3 Attribute Mapping

| GCS Attribute                 | S3 Equivalent                               | Notes                                        |
| ----------------------------- | ------------------------------------------- | -------------------------------------------- |
| `location` (region)           | `region`                                    | Direct mapping; respect user's region choice |
| `versioning_enabled`          | `versioning_enabled`                        | 1:1 copy                                     |
| `lifecycle_rules`             | `lifecycle_rule`                            | Adapt rule conditions                        |
| `uniform_bucket_level_access` | `block_public_acl` + policies               | Convert UNIFORM to S3 ACL block              |
| `encryption` (CSEK)           | `sse_algorithm = "aws:kms"`                 | Use AWS KMS (customer-managed key)           |
| `cors`                        | `cors_rule`                                 | 1:1 copy                                     |
| `retention_policy`            | `object_lock_configuration` (if applicable) | Object Lock stricter than GCS retention      |

## Output Schema

```json
{
  "gcp_type": "google_storage_bucket",
  "gcp_address": "my-app-assets",
  "gcp_config": {
    "location": "us-central1",
    "versioning_enabled": true,
    "lifecycle_rule": [
      {
        "action": "Delete",
        "condition": { "age_days": 90 }
      }
    ]
  },
  "aws_service": "S3",
  "aws_config": {
    "bucket": "my-app-assets-us-east-1",
    "versioning_enabled": true,
    "lifecycle_rule": [
      {
        "id": "delete-old-versions",
        "status": "Enabled",
        "noncurrent_version_expiration": { "days": 90 }
      }
    ],
    "region": "us-east-1"
  },
  "confidence": "deterministic",
  "rationale": "GCS → S3 is 1:1 deterministic; preserve versioning, lifecycle, encryption"
}
```

## No Decision Required

Cloud Storage has no AWS equivalent variations. All mappings are direct.

For non-storage use cases (static site hosting, data lakes, etc.), the hosting compute service (Fargate, Amplify) determines architecture, not the bucket itself.
