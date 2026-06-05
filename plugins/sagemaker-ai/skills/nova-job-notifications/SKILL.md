---
name: nova-job-notifications
description: Enables email notifications for Nova Forge training and evaluation jobs. Use when the user wants alerts when jobs complete, fail, or stop. Supports both SMTJ and SMHP platforms. This is a Nova Forge SDK feature — not available for OSS model training jobs.
metadata:
  version: "1.0.0"
---

# Nova Job Notifications

Enables email notifications for Nova Forge SDK training and evaluation jobs via CloudFormation/SNS/Lambda/EventBridge.

## Principles

1. **One thing at a time.** Each response handles one notification setup decision.
2. **Confirm before proceeding.** Wait for user to confirm email addresses and platform settings.
3. **Don't read references until needed.** Load the reference file when you reach the setup step.

## Workflow

### Step 1: Determine Platform

If not already known from context, ask:

> "Are you using SMTJ or SMHP (HyperPod) for your training jobs? SMHP requires additional setup for notifications."

⏸ Wait for user.

### Step 2: Collect Email Addresses

> "Which email addresses should receive notifications? You can provide multiple, separated by commas."

⏸ Wait for user.

### Step 3: Enable Notifications

Read `references/job-notifications.md` and guide the user through enabling notifications for their platform (SMTJ or SMHP).

For SMHP, this includes additional steps for kubectl Lambda layer and EKS access entry setup.

⏸ Wait for user to confirm notifications enabled.

### Step 4: Confirm Email Subscriptions

> "Each recipient will receive an SNS confirmation email. They must click the confirmation link to start receiving notifications. Please check your inbox (and spam folder) and confirm the subscription."

⏸ Wait for user.

## Important Notes

- Infrastructure is created automatically on first use and shared across all jobs in the region
- SMHP notifications require a kubectl Lambda layer — see the reference for setup instructions
- Emails include: job ID, platform, status, timestamp, and artifact validation
- To delete notification infrastructure when no longer needed, use `NotificationManager.delete_notification_stack()`
- For SMHP, disable the EventBridge Scheduled Rule when not tracking jobs to avoid unnecessary Lambda invocations

## References

- `references/job-notifications.md` — Complete notification setup, troubleshooting, and platform-specific instructions
