# Observability: Metrics, Alarms, and Tracing

## CloudWatch Metrics

| Metric               | Description                                                                                                             |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `Count`              | Total API requests                                                                                                      |
| `Latency`            | Time from API Gateway receiving the request to returning the response (does not include client-to-gateway network time) |
| `IntegrationLatency` | Time spent in backend integration                                                                                       |
| `4XXError` / `4xx`   | Client error count. REST API: `4XXError`; HTTP API: `4xx`                                                               |
| `5XXError` / `5xx`   | Server error count. REST API: `5XXError`; HTTP API: `5xx`                                                               |
| `CacheHitCount`      | Cache hits (REST only)                                                                                                  |
| `CacheMissCount`     | Cache misses (REST only)                                                                                                |
| `DataProcessed`      | Amount of data processed in bytes (HTTP API only)                                                                       |

- Default: metrics per API stage
- Detailed metrics: per method (enable on stage)
- Use CloudWatch Embedded Metric Format for business-specific metrics

## CloudWatch Alarms

### Recommended Alarms

Always configure these alarms for production APIs:

**Error rate alarms:**

- `5XXError` rate > 1% of total requests: server errors indicate backend or configuration problems
- `4XXError` rate anomaly detection: spikes indicate breaking changes, auth failures, or abuse
- `IntegrationLatency` p99 > SLA threshold: detect backend degradation before timeouts

**Throttling alarm:**

- `Count` approaching account throttle limit (10,000 rps default). Alert at 80% utilization to request limit increases proactively

**Cache alarms (REST API):**

- Cache hit ratio (`CacheHitCount / (CacheHitCount + CacheMissCount)`) drop below threshold: indicates cache invalidation issues or misconfiguration

### Alarm Examples (CloudFormation)

```yaml
# REST API alarms: use ApiName dimension and 5XXError/4XXError metric names
# HTTP API alarms: use ApiId dimension and 5xx/4xx metric names instead
Api5xxAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub "${AWS::StackName}-api-5xx-errors"
    MetricName: 5XXError
    Namespace: AWS/ApiGateway
    Dimensions:
      - Name: ApiName
        Value: !Ref MyApi
    Statistic: Sum
    Period: 60
    EvaluationPeriods: 3
    Threshold: 5
    ComparisonOperator: GreaterThanThreshold
    TreatMissingData: notBreaching
    AlarmActions:
      - !Ref AlertSnsTopic

ApiLatencyAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub "${AWS::StackName}-api-p99-latency"
    MetricName: Latency
    Namespace: AWS/ApiGateway
    Dimensions:
      - Name: ApiName
        Value: !Ref MyApi
    ExtendedStatistic: p99
    Period: 300
    EvaluationPeriods: 3
    Threshold: 5000
    ComparisonOperator: GreaterThanThreshold
    TreatMissingData: notBreaching
    AlarmActions:
      - !Ref AlertSnsTopic
```

### Composite Alarms

Combine signals to reduce noise:

- High 5xx AND high latency = likely backend failure (page on-call)
- High 4xx only = likely client-side issue (lower priority)

## CloudWatch Metric Filters

Create custom CloudWatch metrics from access log patterns. Metric filters run on the log group and extract numeric values or count pattern matches.

### Error Count by Response Type

```
{ $.[\"error-responseType\"] = \"THROTTLED\" }
```

Publishes a metric counting throttled requests. Useful since excessive 429s may not be logged by API Gateway itself.

### Slow Requests

```
{ $.responseLatency > 5000 }
```

Counts requests exceeding 5 seconds. Can alarm on this custom metric for tighter latency SLOs than the built-in p99.

### Requests by API Key

Add `"apiKey": "$context.identity.apiKey"` to your log format first, then use:

```
{ $.apiKey != "-" }
```

Use with metric dimensions to track per-consumer request volumes.

## X-Ray Tracing

- **REST API**: Active tracing supported; enable per stage. API Gateway creates the trace segment and adds trace headers to integration requests
- **HTTP API**: X-Ray tracing is [not supported](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html). For distributed tracing, enable X-Ray active tracing on downstream Lambda functions and correlate using the `$context.integration.requestId` access log variable
- Configure sampling rules to control costs and recording criteria
- Service map for latency visualization
- Cross-account tracing requires CloudWatch Observability Access Manager (OAM) configuration between monitoring and source accounts

### Enabling X-Ray in SAM/CloudFormation

```yaml
# REST API with SAM implicit API
Globals:
  Api:
    TracingEnabled: true

# Explicit REST API stage
MyApiStage:
  Type: AWS::ApiGateway::Stage
  Properties:
    TracingEnabled: true
    StageName: prod
    RestApiId: !Ref MyApi
```

For end-to-end distributed tracing, enable X-Ray in both API Gateway and downstream Lambda functions (`Tracing: Active` in SAM function properties). Use X-Ray Groups to filter traces by error, fault, or latency thresholds.
