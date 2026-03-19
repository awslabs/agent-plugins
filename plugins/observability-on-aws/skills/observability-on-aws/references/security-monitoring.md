# Security Monitoring

## Purpose

Security monitoring use cases and alerting patterns using CloudTrail data via CloudWatch Logs Insights.

## Monitoring Use Cases

### Unauthorized Access Detection

```
fields eventTime, eventName, userIdentity.userName, sourceIPAddress, errorCode
| filter (eventName = "ConsoleLogin" or eventName = "AssumeRole")
| filter errorCode like /AccessDenied|AuthFailure|UnauthorizedOperation/
| stats count() as failedAttempts by userIdentity.userName, sourceIPAddress
| sort failedAttempts desc
| limit 50
```

### IAM Changes Audit

```
fields eventTime, eventName, userIdentity.userName as actor, requestParameters.userName as targetUser, sourceIPAddress
| filter eventSource = "iam.amazonaws.com"
| filter eventName in ["CreateUser", "DeleteUser", "CreateRole", "DeleteRole", "PutUserPolicy", "PutRolePolicy", "AttachUserPolicy", "AttachRolePolicy", "CreateAccessKey", "DeactivateMFADevice"]
| sort eventTime desc
| limit 100
```

### Resource Deletion Tracking

```
fields eventTime, eventName, userIdentity.userName, requestParameters, sourceIPAddress
| filter eventName like /Delete|Terminate/
| sort eventTime desc
| limit 100
```

### Security Group Changes

```
fields eventTime, eventName, userIdentity.userName as user, requestParameters.groupId as sgId, sourceIPAddress
| filter eventSource = "ec2.amazonaws.com"
| filter eventName in ["AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress", "RevokeSecurityGroupIngress", "RevokeSecurityGroupEgress"]
| sort eventTime desc
| limit 100
```

### Root Account Activity

```
fields eventTime, eventName, eventSource, sourceIPAddress, userIdentity.sessionContext.attributes.mfaAuthenticated as mfaUsed
| filter userIdentity.type = "Root"
| sort eventTime desc
| limit 100
```

### Cross-Account Access

```
fields eventTime, eventName, userIdentity.accountId, recipientAccountId, sourceIPAddress
| filter eventName = "AssumeRole"
| filter userIdentity.accountId != recipientAccountId
| sort eventTime desc
| limit 100
```

## Critical Alerting Patterns

Use the Root Account and Security Group queries above as CloudWatch Alarms. Additional critical alerts:

```
# IAM policy modifications → review changes, alert if suspicious
fields eventTime, eventName, userIdentity.userName as user, requestParameters
| filter eventName in ["PutUserPolicy", "PutRolePolicy", "AttachUserPolicy", "AttachRolePolicy"]
| sort eventTime desc
| limit 50

# KMS key deletion scheduled → confirm key is no longer needed
fields eventTime, userIdentity.userName as user, requestParameters.keyId as keyId
| filter eventName = "ScheduleKeyDeletion"
| sort eventTime desc
| limit 50
```

## Best Practices

- Enable CloudTrail in all regions/accounts with log file validation and CloudWatch Logs integration
- Set up CloudWatch Alarms and metric filters for critical events; automate threat response
- Configure retention policies; archive to S3/Glacier with Object Lock for immutability
- Restrict CloudTrail log group access; enable encryption; integrates with Application Signals, Security Hub, and GuardDuty
