# CloudTrail Data Source Selection Strategy

## Purpose

This is a utility guide referenced by `security-auditing.md` and other reference files for CloudTrail data access priority logic. It is not intended to be loaded directly in response to user queries.

## Data Source Priority

### Priority 1: CloudTrail Lake (Event Data Store)

**Tool**: `list_event_data_stores` from CloudTrail MCP server

**When to use**: Event data store exists with management events enabled.

- Native SQL support for complex queries
- Configurable retention (up to 2,557 days / ~7 years)
- Cross-account and cross-region aggregation

### Priority 2: CloudWatch Logs (CloudTrail Integration)

**Tool**: `describe_log_groups` from CloudWatch MCP server

**When to use**: CloudTrail is configured to send events to CloudWatch Logs.

- Real-time event streaming with alarm integration
- CloudWatch Logs Insights query support
- Common log group patterns: `/aws/cloudtrail/logs`, `/aws/cloudtrail/<trail-name>`, `CloudTrail/logs`

### Priority 3: CloudTrail Lookup Events API

**Tool**: `lookup_events` from CloudTrail MCP server

**When to use**: Neither CloudTrail Lake nor CloudWatch Logs available.

- Only last 90 days of events
- Limited to 50 results per API call
- Basic filtering only (no SQL support)

## Implementation Workflow

1. **Check CloudTrail Lake**: Call `list_event_data_stores`. If an enabled store with management events exists, use `lake_query` for SQL-based analysis.
2. **Check CloudWatch Logs**: Call `describe_log_groups` searching for "cloudtrail". If found, use `execute_log_insights_query`.
3. **Fall back to Lookup Events**: Use `lookup_events` with `LookupAttributes`. Limited to 90 days and 50 results per call.

## Decision Tree

```
Need CloudTrail Data?
    |
    v
Check CloudTrail Lake (list_event_data_stores)
    +-- Enabled? --> YES --> Use lake_query
    +-- NO --> Check CloudWatch Logs (describe_log_groups)
                +-- CloudTrail Log Group? --> YES --> Use execute_log_insights_query
                +-- NO --> Use lookup_events (90 days, basic filtering)
```

## Query Translation Example: Find IAM User Deletions

**CloudTrail Lake (SQL)**:

```sql
SELECT eventTime, userIdentity.userName,
       requestParameters.userName AS deletedUser, sourceIPAddress
FROM <event_data_store_id>
WHERE eventName = 'DeleteUser'
  AND eventTime > timestamp '2024-01-01 00:00:00'
ORDER BY eventTime DESC
```

**CloudWatch Logs Insights**:

```
fields eventTime, userIdentity.userName, requestParameters.userName, sourceIPAddress
| filter eventName = "DeleteUser"
| sort eventTime desc | limit 50
```

**Lookup Events API**:

```
lookup_events(
    LookupAttributes=[{'AttributeKey': 'EventName', 'AttributeValue': 'DeleteUser'}],
    StartTime='2024-01-01T00:00:00Z', MaxResults=50
)
```

## Error Handling

- **CloudTrail Lake not available**: `list_event_data_stores` returns empty or no enabled stores. Proceed to Priority 2.
- **CloudWatch Logs not available**: No CloudTrail log groups found. Proceed to Priority 3.
- **Lookup Events limits exceeded**: Data older than 90 days or complex filtering needed. Inform user that CloudTrail Lake or CloudWatch Logs integration is required.
