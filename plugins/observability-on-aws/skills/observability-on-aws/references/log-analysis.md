# CloudWatch Logs Insights Analysis

## Purpose

This reference provides guidance for using CloudWatch Logs Insights QL syntax for log analysis, troubleshooting, and data extraction via the CloudWatch MCP server.

## MCP Server Tools

### Primary Tools

- `execute_log_insights_query` - Run Logs Insights queries with automatic polling
- `describe_log_groups` - Discover log groups and saved queries
- `analyze_log_group` - Detect anomalies and common patterns
- `get_logs_insight_query_results` - Retrieve results from timed-out queries
- `cancel_logs_insight_query` - Cancel running queries

### Key Parameters for execute_log_insights_query

- `query_string` - The Logs Insights QL query
- `log_group_names` OR `log_group_identifiers` - Target log groups (exactly one required)
- `start_time` / `end_time` - ISO 8601 format (e.g., "2025-02-06T10:00:00+00:00")
- `limit` - Max results (CRITICAL: always use to avoid context overflow)

## Query Construction Principles

### 1. Always Limit Results

Every query should include a limit to avoid overwhelming context:

```
fields @timestamp, @message
| limit 50
```

### 2. Use Pipe Syntax

Commands are separated by pipe (`|`) characters:

```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

### 3. Built-in Fields Use @ Prefix

CloudWatch auto-discovers these fields:

- `@timestamp` - Log event timestamp
- `@message` - Raw log message
- `@logStream` - Log stream name
- `@log` - Log group identifier
- `@ingestionTime` - When CloudWatch received the event

### 4. Comments Use Hash

```
# This is a comment
fields @timestamp, @message
| limit 50
```

## Core Commands

### fields

Select and transform fields:

```
fields @timestamp, @message, @logStream
fields @timestamp, concat(@logStream, '-', @message) as combined
```

### filter

Filter log events:

```
filter @message like /ERROR/
filter @message like /(?i)exception/
filter statusCode >= 400
filter ispresent(requestId)
filter @message not like /DEBUG/
```

### stats

Aggregate statistics:

```
stats count(*) by bin(1h)
stats avg(duration), max(duration), min(duration) by serviceName
stats count(*) as errorCount by errorType
| sort errorCount desc
```

### parse

Extract fields from messages:

```
# Glob pattern
parse @message "user=* action=* status=*" as user, action, status

# Regex pattern
parse @message /user=(?<user>\S+)/
parse @message /duration=(?<duration>\d+)ms/
```

### sort

Order results:

```
sort @timestamp desc
sort duration desc
sort errorCount asc
```

### limit

Cap result count:

```
limit 100
```

### dedup

Remove duplicates:

```
dedup requestId
dedup @logStream, errorType
```

## Common Query Patterns

### Pattern 1: Basic Error Search

```
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
```

### Pattern 2: Count Errors by Type

```
filter @message like /ERROR/
| parse @message /ERROR: (?<errorType>[^:]+)/
| stats count(*) as count by errorType
| sort count desc
| limit 20
```

### Pattern 3: Lambda Cold Starts

```
filter @type = "REPORT"
| parse @message /Init Duration: (?<initDuration>[\d\.]+)/
| filter ispresent(initDuration)
| stats count(*) as coldStarts, avg(initDuration) as avgInitMs by bin(1h)
| limit 100
```

### Pattern 4: API Latency Analysis

```
filter ispresent(duration)
| stats avg(duration) as avgMs,
        pct(duration, 95) as p95Ms,
        pct(duration, 99) as p99Ms,
        max(duration) as maxMs
  by bin(5m)
| sort @timestamp desc
| limit 100
```

### Pattern 5: HTTP Status Code Distribution

```
filter ispresent(statusCode)
| stats count(*) as requests by statusCode
| sort statusCode asc
| limit 100
```

### Pattern 6: Find Slow Requests

```
filter duration > 1000
| fields @timestamp, @requestId, duration, @message
| sort duration desc
| limit 25
```

### Pattern 7: JSON Log Parsing

```
fields @timestamp, @message
| parse @message '{"level":"*","message":"*","requestId":"*"}' as level, msg, reqId
| filter level = "ERROR"
| limit 50
```

### Pattern 8: Unique Error Messages

```
filter @message like /ERROR/
| dedup @message
| limit 30
```

### Pattern 9: Request Tracing

```
filter @requestId = "abc-123-def"
| fields @timestamp, @message, @logStream
| sort @timestamp asc
| limit 100
```

### Pattern 10: Anomaly Detection

```
pattern @message
| anomaly
| limit 50
```

## Functions Reference

### String Functions

- `strlen(field)` - String length
- `trim(field)` - Remove whitespace
- `tolower(field)` / `toupper(field)` - Case conversion
- `concat(a, b, ...)` - Concatenate strings
- `replace(field, 'old', 'new')` - Replace substring

### Numeric Functions

- `abs(num)` - Absolute value
- `ceil(num)` / `floor(num)` - Rounding
- `greatest(a, b, ...)` / `least(a, b, ...)` - Min/max of values
- `log(num)` / `sqrt(num)` - Math functions

### Date/Time Functions

- `datefloor(timestamp, period)` - Round down to period
- `dateceil(timestamp, period)` - Round up to period
- `bin(period)` - Group by time bucket (1m, 5m, 1h, 1d)
- `fromMillis(ms)` - Convert epoch ms to timestamp
- `toMillis(timestamp)` - Convert timestamp to epoch ms

### Aggregation Functions (use with stats)

- `count(*)` / `count(field)` - Count events
- `sum(field)` - Sum values
- `avg(field)` - Average
- `min(field)` / `max(field)` - Min/max
- `pct(field, percentile)` - Percentile (e.g., pct(duration, 95))
- `stddev(field)` - Standard deviation
- `earliest(field)` / `latest(field)` - First/last by time

### Conditional Functions

- `ispresent(field)` - Check if field exists
- `isempty(field)` - Check if field is empty
- `isblank(field)` - Check if field is blank
- `coalesce(a, b, ...)` - First non-null value

### IP Functions

- `isValidIp(field)` - Validate IP address
- `isValidIpV4(field)` / `isValidIpV6(field)` - Validate specific version
- `isIpInSubnet(ip, subnet)` - Check subnet membership

## Best Practices

1. **Start with describe_log_groups** - Discover available log groups first
2. **Use narrow time ranges** - Minimize scanned data and costs
3. **Always include limit** - Prevent context window overflow
4. **Test incrementally** - Start simple, add complexity
5. **Use filterIndex for indexed fields** - Improves performance on large datasets
6. **Parse JSON early** - Extract fields before filtering when possible
7. **Use analyze_log_group** - For quick anomaly and pattern detection

## Common Pitfalls

1. **Missing limit** - Queries can return massive results
2. **Wrong time format** - Use ISO 8601 with timezone
3. **Case sensitivity** - Field names and regex are case-sensitive
4. **Missing ispresent()** - Filter on field existence before using it
5. **Regex escaping** - Use `/pattern/` syntax, escape special chars
6. **Large time ranges** - Can be slow and expensive

## Query Construction Workflow

When a user asks for log analysis:

1. **Discover log groups** - Use `describe_log_groups` if unknown
2. **Define time range** - Ask for or suggest appropriate window
3. **Identify requirements** - What fields, filters, aggregations?
4. **Build query** - Start simple, use patterns above
5. **Add limit** - Always cap results (50-100 typical)
6. **Execute and iterate** - Refine based on results

---

**Remember**: Always include a `limit` clause to avoid overwhelming the agent context. Start with 50-100 results and increase if needed.
