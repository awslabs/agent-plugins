# CloudTrail Security Auditing

## Purpose

Guidance for accessing and analyzing CloudTrail audit data for security auditing, compliance monitoring, and governance analysis.

## Prerequisites and Data Source Selection

Follow the priority order defined in `cloudtrail-data-source-selection.md`:

1. **CloudTrail Lake** (preferred): Use `list_event_data_stores` then `lake_query` for SQL-based analysis. Configurable retention (up to 2,557 days / ~7 years).
2. **CloudWatch Logs**: Use `describe_log_groups` to find groups matching "cloudtrail". Use `execute_log_insights_query` for real-time monitoring.
3. **Lookup Events API** (fallback): Use `lookup_events` from CloudTrail MCP server. Limited to last 90 days, 50 results per call.

## When to Load This Reference

Load when the user needs to investigate security incidents, track API activity, perform compliance audits, monitor IAM changes, or detect unauthorized access. For investigation queries, see `security-investigations.md`. For monitoring and alerting, see `security-monitoring.md`.

## CloudTrail Overview

CloudTrail logs all API calls in your AWS account for governance, compliance, and audit. Supports real-time analysis, CloudWatch Logs Insights queries, cross-service correlation, multi-region/multi-account, and configurable retention.

## Core Concepts

### Event Types

- **Management Events**: Control plane operations (CreateBucket, RunInstances, CreateUser)
- **Data Events**: Data plane operations (GetObject, PutObject, Invoke)
- **Insights Events**: ML-detected unusual API activity (rate and error rate anomalies)

### Event Structure

```json
{
  "eventTime": "2024-12-08T10:30:00Z",
  "eventName": "CreateBucket",
  "eventSource": "s3.amazonaws.com",
  "userIdentity": { "type": "IAMUser", "userName": "alice" },
  "sourceIPAddress": "203.0.113.0",
  "userAgent": "aws-cli/2.0.0",
  "requestParameters": { "bucketName": "my-new-bucket" },
  "errorCode": null
}
```

## Querying CloudTrail Data

### CloudTrail Lake (Priority 1)

```sql
SELECT eventTime, eventName, userIdentity.userName, sourceIPAddress
FROM <event_data_store_id>
WHERE eventName IN ('DeleteBucket', 'TerminateInstances')
    AND eventTime > timestamp '2024-01-01 00:00:00'
ORDER BY eventTime DESC
LIMIT 50
```

### CloudWatch Logs (Priority 2)

```
fields eventTime, eventName, userIdentity.userName, sourceIPAddress
| filter eventName = "DeleteBucket" or eventName = "TerminateInstances"
| sort eventTime desc
| limit 50
```

### Lookup Events API (Priority 3)

```
lookup_events(
    LookupAttributes=[{ 'AttributeKey': 'EventName', 'AttributeValue': 'DeleteBucket' }],
    StartTime='2024-10-01T00:00:00Z',  # Must be within 90 days
    EndTime='2024-12-31T23:59:59Z',
    MaxResults=50
)
```

## Quick Reference

### Common Event Names

- **IAM**: CreateUser, DeleteUser, AttachUserPolicy, CreateAccessKey
- **EC2**: RunInstances, TerminateInstances, AuthorizeSecurityGroupIngress
- **S3**: CreateBucket, DeleteBucket, PutBucketPolicy
- **RDS**: CreateDBInstance, DeleteDBInstance, ModifyDBInstance
- **Lambda**: CreateFunction, DeleteFunction, UpdateFunctionCode

### User Identity Types

- **IAMUser**: Standard IAM user | **AssumedRole**: Role via STS | **Root**: Root account
- **FederatedUser**: Federated identity | **AWSService**: AWS service acting on your behalf

### Error Codes

- **AccessDenied**: Permission denied | **UnauthorizedOperation**: Not authorized
- **InvalidParameter**: Invalid request parameter | **ResourceNotFound**: Resource doesn't exist
