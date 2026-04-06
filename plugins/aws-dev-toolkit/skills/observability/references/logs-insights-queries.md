# CloudWatch Logs Insights Query Examples

Ready-to-use Logs Insights queries organized by use case. Copy and adapt for your log groups.

## Lambda Function Debugging

```
# Find errors in Lambda functions
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

# Cold starts — frequency and duration
filter @type = "REPORT"
| fields @requestId, @duration, @initDuration
| filter ispresent(@initDuration)
| stats count(*) as cold_starts, avg(@initDuration) as avg_init_ms, max(@initDuration) as max_init_ms by bin(1h)

# Lambda timeout detection
filter @message like /Task timed out/
| fields @timestamp, @requestId, @message
| sort @timestamp desc

# Memory usage near limit
filter @type = "REPORT"
| fields @requestId, @maxMemoryUsed, @memorySize
| filter @maxMemoryUsed / @memorySize > 0.8
| sort @maxMemoryUsed desc
| limit 50

# P99 duration over time
filter @type = "REPORT"
| stats percentile(@duration, 99) as p99, percentile(@duration, 95) as p95, avg(@duration) as avg_ms by bin(5m)

# Invocations and errors over time
filter @type = "REPORT"
| stats count(*) as invocations, sum(strcontains(@message, "ERROR")) as errors by bin(5m)
```

## Structured Log Analysis

These queries assume JSON-formatted log output with fields like `level`, `message`, `errorCode`, `duration_ms`, `requestId`, `userId`.

```
# P99 latency from structured logs
fields @timestamp, duration_ms
| stats percentile(duration_ms, 99) as p99, percentile(duration_ms, 95) as p95, avg(duration_ms) as avg_ms by bin(5m)

# Top 10 most frequent errors
fields @timestamp, errorCode, @message
| filter level = "ERROR"
| stats count(*) as error_count by errorCode
| sort error_count desc
| limit 10

# Error rate percentage over time
stats count(*) as total, sum(level = "ERROR") as errors by bin(5m)
| fields @timestamp, total, errors, errors / total * 100 as error_rate_pct

# Find slow requests
fields @timestamp, duration_ms, requestId, userId
| filter duration_ms > 5000
| sort duration_ms desc
| limit 20

# Errors by user
fields @timestamp, userId, errorCode
| filter level = "ERROR"
| stats count(*) as error_count by userId
| sort error_count desc
| limit 20

# Unique users over time
fields userId
| stats count_distinct(userId) as unique_users by bin(1h)
```

## API Gateway

```
# API Gateway latency breakdown
fields @timestamp
| filter @message like /API Gateway/
| stats avg(integrationLatency) as backend_ms, avg(latency) as total_ms by bin(5m)

# 4xx and 5xx error rates
fields @timestamp, status
| stats count(*) as total,
        sum(status >= 400 and status < 500) as client_errors,
        sum(status >= 500) as server_errors by bin(5m)
| fields @timestamp, total, client_errors, server_errors,
         client_errors / total * 100 as client_error_pct,
         server_errors / total * 100 as server_error_pct

# Top API paths by request volume
fields path
| stats count(*) as requests by path
| sort requests desc
| limit 20

# Slowest API endpoints
fields path, latency
| stats avg(latency) as avg_ms, percentile(latency, 99) as p99_ms, count(*) as requests by path
| sort p99_ms desc
| limit 20
```

## ECS / Container Logs

```
# OOM kills
fields @timestamp, @message
| filter @message like /OutOfMemory/ or @message like /OOMKilled/ or @message like /oom-kill/
| sort @timestamp desc

# Container restart events
fields @timestamp, @message
| filter @message like /Starting/ or @message like /Stopping/ or @message like /SIGTERM/
| sort @timestamp desc
| limit 50

# Request rate by container
fields @timestamp, containerId
| stats count(*) as requests by containerId, bin(5m)
```

## VPC Flow Logs

```
# Rejected connections (potential security concern)
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter action = "REJECT"
| stats count(*) as rejected by srcAddr, dstAddr, dstPort
| sort rejected desc
| limit 25

# Top talkers by bytes
fields srcAddr, dstAddr, bytes
| stats sum(bytes) as total_bytes by srcAddr, dstAddr
| sort total_bytes desc
| limit 20

# Traffic to a specific port
fields @timestamp, srcAddr, dstAddr, dstPort, action, bytes
| filter dstPort = 443
| stats sum(bytes) as total_bytes, count(*) as connections by srcAddr
| sort total_bytes desc
| limit 20

# Connections from outside the VPC CIDR
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter not ispresent(srcAddr like "10.0.")
| filter action = "ACCEPT"
| stats count(*) as connections by srcAddr, dstPort
| sort connections desc
```

## CloudFront

```
# Top requested URIs
fields @timestamp, cs-uri-stem, sc-status
| stats count(*) as requests by cs-uri-stem
| sort requests desc
| limit 20

# Cache hit ratio
fields @timestamp, x-edge-result-type
| stats count(*) as total,
        sum(x-edge-result-type = "Hit") as hits by bin(5m)
| fields @timestamp, total, hits, hits / total * 100 as hit_rate_pct

# 5xx errors by URI
fields cs-uri-stem, sc-status
| filter sc-status >= 500
| stats count(*) as errors by cs-uri-stem, sc-status
| sort errors desc
| limit 20
```

## General Patterns

```
# Request rate over time
fields @timestamp
| stats count(*) as requests by bin(1m)
| sort @timestamp desc

# Count log volume by log stream
fields @logStream
| stats count(*) as lines by @logStream
| sort lines desc
| limit 20

# Search for a specific request/correlation ID
fields @timestamp, @message
| filter @message like /abc-123-request-id/
| sort @timestamp asc

# Extract and analyze JSON fields dynamically
fields @timestamp, @message
| parse @message '{"action":"*","duration":*}' as action, duration
| stats avg(duration) as avg_ms, count(*) as calls by action
| sort avg_ms desc
```

## CLI: Running Logs Insights Queries

```bash
# Start a query (returns query ID)
aws logs start-query \
  --log-group-name /aws/lambda/my-function \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | limit 20'

# Get query results (poll until status is "Complete")
aws logs get-query-results --query-id "query-id-here"

# Query multiple log groups at once
aws logs start-query \
  --log-group-names /aws/lambda/fn-a /aws/lambda/fn-b /aws/lambda/fn-c \
  --start-time $(date -d '6 hours ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | stats count(*) by @logStream'
```
