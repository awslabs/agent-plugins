---
name: job-notifications
description: Email notifications for training/evaluation jobs. Use when enabling job completion alerts, setting up notification infrastructure, or troubleshooting notification delivery.
triggers:
  keywords: [notification, notify, email, alert, job status, monitor job, enable_job_notifications, CloudFormation, SNS]
  task_types: [monitoring, notifications, infrastructure]
  error_patterns: ["kubectl error: Unauthorized", "namespace is required", "KMS Access Denied", "ResourceInUseException"]
  methods: [SFT, RFT, CPT, DPO, EVALUATION]
prerequisites: []
last_verified: 2026-04-13
sdk_version: ">=1.0.0"
---

> Ensure you've loaded best practices from the agent-memory skill before guiding the customer.

# Job Notifications

## When to Use This Skill

- Enabling email notifications for training or evaluation jobs
- Setting up notification infrastructure (SMTJ or SMHP)
- Troubleshooting notification delivery issues
- Managing or deleting notification infrastructure
- Configuring KMS encryption for notifications
- Setting up SMHP pod health monitoring

## When NOT to Use This Skill

- You're running a training job — use `docs/sdk/skills/training-workflow.md`
- You're monitoring logs or metrics — use `docs/sdk/skills/training-workflow.md` (CloudWatch section)
- You're debugging a training failure — use `docs/sdk/skills/troubleshooting-failures.md`

## Key Concepts

### How It Works

The SDK automatically provisions AWS infrastructure (CloudFormation, DynamoDB, SNS, Lambda, EventBridge) to monitor job state changes and send email notifications when jobs reach terminal states (Completed, Failed, Stopped).

### Platform Differences

| Feature               | SMTJ                    | SMHP                                       |
| --------------------- | ----------------------- | ------------------------------------------ |
| Trigger mechanism     | EventBridge (real-time) | Scheduled polling (default: 5 min)         |
| Additional params     | None                    | `namespace`, `kubectl_layer_arn` required  |
| Pod health monitoring | No                      | Yes (CrashLoopBackOff, excessive restarts) |
| Infrastructure scope  | One stack per region    | One stack per cluster                      |

### Prerequisites

- **Email confirmation**: Each recipient must click the SNS confirmation link to start receiving notifications
- **IAM permissions**: Additional permissions required — see `docs/sdk/reference/iam_setup.md` (Job Monitoring section)
- **SMHP only**: kubectl Lambda layer must be deployed first

## Step-by-Step Guide

### 1. Enable Notifications (SMTJ — Simplest)

```python
from amzn_nova_forge import ForgeTrainer

# After starting a training job
result = trainer.train(job_name="my-training-job")

# Enable email notifications
result.enable_job_notifications(
    emails=["user@example.com", "team@example.com"]
)
```

Infrastructure is created automatically on first use and shared across all jobs in the region.

### 2. Enable Notifications (SMHP)

SMHP requires additional parameters for Kubernetes access:

```python
result.enable_job_notifications(
    emails=["user@example.com"],
    namespace="kubeflow",  # REQUIRED: K8s namespace where job runs
    kubectl_layer_arn="arn:aws:lambda:<region>:123456789012:layer:kubectl:1"  # REQUIRED
)
```

**After first setup**, you must grant the Lambda function EKS access:

```bash
# 1. Get the Lambda role ARN from CloudFormation outputs
aws cloudformation describe-stacks \
  --stack-name NovaForgeSDK-SMHP-JobNotifications-YOUR-CLUSTER-NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`LambdaRoleArn`].OutputValue' \
  --output text

# 2. Create EKS access entry
aws eks create-access-entry \
  --cluster-name YOUR-EKS-CLUSTER-NAME \
  --principal-arn arn:aws:iam::ACCOUNT-ID:role/NovaForgeSDK-SMHP-NotifLambdaRole-HP-CLUSTER \
  --type STANDARD

# 3. Associate admin policy
aws eks associate-access-policy \
  --cluster-name YOUR-EKS-CLUSTER-NAME \
  --principal-arn arn:aws:iam::ACCOUNT-ID:role/NovaForgeSDK-SMHP-NotifLambdaRole-HP-CLUSTER \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### 3. With KMS Encryption (Optional)

```python
result.enable_job_notifications(
    emails=["user@example.com"],
    kms_key_id="1234abcd-12ab-34cd-56ef-1234567890ab"  # Key ID only, not full ARN
)
```

### 4. Notification Manager (Advanced)

For jobs started outside the SDK or to enable notifications on existing jobs:

```python
from amzn_nova_forge import SMTJNotificationManager, SMHPNotificationManager

# SMTJ
smtj_manager = SMTJNotificationManager(region="us-east-1")
smtj_manager.enable_notifications(
    job_name="existing-training-job",
    emails=["user@example.com"],
    output_s3_path="s3://bucket/output/"
)

# SMHP
smhp_manager = SMHPNotificationManager(cluster_name="my-cluster", region="us-east-1")
smhp_manager.enable_notifications(
    job_name="existing-pytorch-job",
    emails=["user@example.com"],
    output_s3_path="s3://bucket/output/",
    namespace="kubeflow",
    kubectl_layer_arn="arn:aws:lambda:<region>:123456789012:layer:kubectl:1"
)
```

### 5. Delete Notification Infrastructure

```python
from amzn_nova_forge import SMTJNotificationManager, SMHPNotificationManager

# SMTJ
SMTJNotificationManager().delete_notification_stack()

# SMHP
SMHPNotificationManager(
    cluster_name="cluster-name",
    region="us-east-1"
).delete_notification_stack()
```

> **Tip:** If you want to keep the infrastructure but aren't tracking jobs right now, disable the EventBridge Scheduled Rule via the AWS Console instead of deleting the stack.

## SMHP Pod Health Monitoring

For SMHP jobs, the notification system monitors master pod health:

- **CrashLoopBackOff**: Pod is repeatedly crashing
- **Excessive Restarts**: Pod has restarted more than 5 times

You'll receive a `Running (Degraded - CrashLoopBackOff)` notification before the job fully fails, giving you early warning to investigate.

## Common Pitfalls

### Pitfall 1: Emails Not Received

**Problem:** Notifications enabled but no emails arrive.

**Solutions:**

1. Check spam folder — SNS emails may be filtered
2. Click the confirmation link in the initial SNS subscription email
3. Verify subscription in AWS Console → SNS → Topics

### Pitfall 2: SMHP "kubectl error: Unauthorized"

**Problem:** Lambda can't query Kubernetes for job status.

**Solutions:**

1. Ensure EKS access entry exists for the Lambda role
2. Use `AmazonEKSClusterAdminPolicy` (not ViewPolicy — it doesn't include PyTorchJob permissions)
3. Verify kubectl layer ARN is correct and includes the version number
4. Check VPC configuration — Lambda needs network access to EKS API

### Pitfall 3: SMHP "namespace is required"

**Problem:** Missing required `namespace` parameter for SMHP notifications.

**Solution:** Always provide `namespace` when using SMHP:

```python
result.enable_job_notifications(
    emails=["user@example.com"],
    namespace="kubeflow",  # Required for SMHP
    kubectl_layer_arn="..."
)
```

### Pitfall 4: KMS Access Denied

**Problem:** Lambda can't decrypt/encrypt with customer KMS key.

**Solution:** If your KMS key has a restrictive key policy, manually grant access:

```bash
aws kms create-grant \
  --key-id YOUR-KEY-ID \
  --grantee-principal arn:aws:iam::ACCOUNT:role/NovaForgeSDK-*-NotificationLambda-Role-* \
  --operations Decrypt GenerateDataKey
```

### Pitfall 5: ResourceInUseException for EKS Access Entry

**Problem:** Previous stack was deleted but the EKS access entry wasn't cleaned up.

**Solution:** Delete the old access entry first, then recreate it. Find the old Lambda role in the AWS Console under the Lambda function's "Access" tab.

### Pitfall 6: Not Disabling EventBridge When Idle (SMHP)

**Problem:** Lambda keeps polling every 5 minutes even when no jobs are running, incurring unnecessary cost.

**Solution:** Disable the EventBridge Scheduled Rule via the AWS Console when not tracking any SMHP jobs. Re-enable it when you start new jobs.

## Debugging Notification Issues

Check the Lambda's CloudWatch logs for detailed error information:

1. Navigate to the Lambda function in AWS Console:
   - **SMTJ:** `NovaForgeSDK-SMTJ-NotificationHandler`
   - **SMHP:** `NovaForgeSDK-SMHP-NotificationHandler-CLUSTER-NAME`
2. Go to "Monitor" tab → "View CloudWatch Logs"
3. Check the newest log stream for errors

## Notification Content

Emails include:

- Job ID, Platform, Status, Timestamp
- Cluster name and namespace (SMHP only)
- Artifact validation (checks `manifest.json` exists for training jobs)
- Pod health info (for degraded SMHP jobs)

> **Note:** Evaluation jobs produce `results_*.json` files, not `manifest.json` — so "manifest.json not found" is expected for eval jobs.

## kubectl Lambda Layer Setup (SMHP Only)

1. Go to [AWS Serverless Application Repository — lambda-layer-kubectl](https://serverlessrepo.aws.amazon.com/applications/arn:aws:serverlessrepo:us-east-1:903779448426:applications~lambda-layer-kubectl)
2. Click "Deploy" and select your region
3. Name the layer and deploy
4. Note the layer ARN from generated outputs — use it as `kubectl_layer_arn`

## Related Documentation

- Full notification reference: `docs/sdk/reference/job_notifications.md`
- IAM permissions for notifications: `docs/sdk/reference/iam_setup.md`
- Training workflow: `docs/sdk/skills/training-workflow.md`
- Troubleshooting: `docs/sdk/skills/troubleshooting-failures.md`

---

_Last verified against amzn-nova-forge SDK on 2026-04-13. If you encounter discrepancies, check `docs/sdk/reference/job_notifications.md` for the latest reference._
