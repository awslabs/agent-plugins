# Security Investigations

## Purpose

Investigation workflows for security incidents, compliance audits, and resource change tracking using CloudTrail data via CloudWatch Logs Insights.

## Security Incident Investigation

```
# Identify failed access attempts
fields eventTime, eventName, userIdentity.userName, sourceIPAddress, errorCode, errorMessage
| filter errorCode = "AccessDenied" or errorCode = "UnauthorizedOperation"
| sort eventTime desc
| limit 100

# Trace specific user activity
fields eventTime, eventName, requestParameters, responseElements
| filter userIdentity.userName = "suspect-user"
| sort eventTime desc
| limit 100

# Check IAM changes before incident
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter eventSource = "iam.amazonaws.com"
| filter eventName like /Create|Delete|Update|Attach|Detach/
| sort eventTime desc
| limit 50
```

## Compliance Audit

```
# List all IAM changes in period
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter eventSource = "iam.amazonaws.com"
| filter eventName like /Create|Delete|Update|Attach|Detach/
| sort eventTime desc
| limit 100

# Track privileged actions
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter eventName = "AssumeRole" or eventName = "GetFederationToken"
| sort eventTime desc
| limit 100
```

## Resource Change Tracking

```
# Find specific resource changes (replace with actual resource ARN)
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter requestParameters like /arn:aws:s3:::my-bucket/
| sort eventTime desc
| limit 50

# Track configuration changes for a service
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter eventSource = "ec2.amazonaws.com"
| filter eventName like /Update|Modify|Put/
| sort eventTime desc
| limit 100
```

## Investigation Workflows

```
# Privilege escalation check
fields eventTime, eventName, requestParameters.policyDocument as policy
| filter userIdentity.userName = "suspect-user"
| filter eventName in ["CreatePolicy", "AttachUserPolicy", "PutUserPolicy", "AttachRolePolicy", "PutRolePolicy"]
| sort eventTime asc
| limit 100

# Summarize resources accessed by suspect user
fields eventName, eventSource
| filter userIdentity.userName = "suspect-user"
| stats count() as accessCount by eventName, eventSource
| sort accessCount desc
| limit 100

# Identify who deleted a resource (replace event name and resource)
fields eventTime, userIdentity.userName, userIdentity.arn, sourceIPAddress, userAgent
| filter eventName = "DeleteBucket"
| filter requestParameters.bucketName = "my-critical-bucket"
| sort eventTime desc
| limit 10
```

## Compliance Audit Tasks

```
# Users created, access keys, and KMS key operations in audit period
fields eventTime, eventName, userIdentity.userName, requestParameters
| filter eventName in ["CreateUser", "CreateAccessKey", "CreateKey", "ScheduleKeyDeletion", "DisableKey"]
| sort eventTime asc
| limit 500
```

To correlate CloudTrail with application logs: query for security events, extract timestamps, then query application logs for the same period (Logs Insights does not support JOINs across log groups).
