# CloudWatch Alarm Recipes

Production-ready alarm configurations organized by service. Each recipe includes the metric, threshold rationale, and recommended settings.

## Alarm Configuration Defaults

Unless stated otherwise, all alarms below should use these settings:

| Setting | Value | Rationale |
|---|---|---|
| EvaluationPeriods | 5 | Avoids flapping on transient spikes |
| DatapointsToAlarm | 3 | 3 of 5 datapoints must breach |
| TreatMissingData | `notBreaching` | Avoids false alarms during low traffic |
| ActionsEnabled | true | Always wire to SNS |
| Period | 60 (seconds) | 1-minute granularity for most metrics |

Override `TreatMissingData` to `breaching` for health-check style alarms where missing data means the resource is down.

## Lambda

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| Errors | Errors | Sum | > 0 | 60s | Any error is worth knowing about |
| High error rate | Metric math: Errors/Invocations*100 | - | > 5% | 60s | Percentage-based avoids noise on low volume |
| Throttles | Throttles | Sum | > 0 | 60s | Indicates concurrency pressure |
| Duration p99 | Duration | p99 | > 80% of timeout | 60s | Approaching timeout = about to fail |
| Concurrent executions | ConcurrentExecutions | Maximum | > 80% of account limit | 300s | Prevent account-wide throttling |
| Iterator age (streams) | IteratorAge | Maximum | > 60000 ms | 60s | Stream processing falling behind |

### Lambda Error Rate Metric Math Example

```yaml
# CloudFormation snippet
LambdaErrorRateAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub "${FunctionName}-error-rate"
    Metrics:
      - Id: errors
        MetricStat:
          Metric:
            Namespace: AWS/Lambda
            MetricName: Errors
            Dimensions:
              - Name: FunctionName
                Value: !Ref MyFunction
          Period: 60
          Stat: Sum
      - Id: invocations
        MetricStat:
          Metric:
            Namespace: AWS/Lambda
            MetricName: Invocations
            Dimensions:
              - Name: FunctionName
                Value: !Ref MyFunction
          Period: 60
          Stat: Sum
      - Id: error_rate
        Expression: "IF(invocations > 0, errors / invocations * 100, 0)"
        Label: "Error Rate %"
    ComparisonOperator: GreaterThanThreshold
    Threshold: 5
    EvaluationPeriods: 5
    DatapointsToAlarm: 3
    TreatMissingData: notBreaching
    AlarmActions:
      - !Ref AlertSNSTopic
```

## ALB / Application Load Balancer

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| 5XX errors | HTTPCode_Target_5XX_Count | Sum | > 0 | 300s | Backend is returning errors |
| High 5XX rate | Metric math: 5XX/RequestCount*100 | - | > 1% | 60s | Percentage-based for noisy services |
| Latency p99 | TargetResponseTime | p99 | > your SLA (e.g., 2s) | 60s | Tail latency breach |
| Unhealthy hosts | UnHealthyHostCount | Maximum | > 0 | 60s | Targets failing health checks |
| Rejected connections | RejectedConnectionCount | Sum | > 0 | 60s | ALB at connection limit |
| Active connections | ActiveConnectionCount | Sum | > 80% of expected max | 60s | Connection exhaustion risk |

## RDS / Aurora

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| CPU utilization | CPUUtilization | Average | > 80% | 300s | Sustained high CPU |
| Free storage | FreeStorageSpace | Minimum | < 20% of allocated | 300s | Prevent disk full |
| Connections | DatabaseConnections | Maximum | > 80% of max_connections | 60s | Connection exhaustion |
| Read latency | ReadLatency | p99 | > 20ms | 60s | Disk I/O bottleneck |
| Write latency | WriteLatency | p99 | > 20ms | 60s | Disk I/O bottleneck |
| Replica lag | ReplicaLag | Maximum | > 30s | 60s | Replication falling behind |
| Freeable memory | FreeableMemory | Minimum | < 256 MB | 300s | Instance under memory pressure |

### RDS Storage Alarm with Percentage Threshold

```yaml
RDSStorageAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: !Sub "${DBInstanceId}-storage-low"
    Metrics:
      - Id: free
        MetricStat:
          Metric:
            Namespace: AWS/RDS
            MetricName: FreeStorageSpace
            Dimensions:
              - Name: DBInstanceIdentifier
                Value: !Ref DBInstance
          Period: 300
          Stat: Minimum
      - Id: threshold
        Expression: !Sub "${AllocatedStorageGB} * 1073741824 * 0.2"
        Label: "20% of allocated"
    ComparisonOperator: LessThanThreshold
    Threshold: 0
    # Use the expression as the threshold by comparing free < threshold
    # Alternative: hardcode the byte value for your instance size
    EvaluationPeriods: 3
    DatapointsToAlarm: 2
    TreatMissingData: breaching
    AlarmActions:
      - !Ref AlertSNSTopic
```

## DynamoDB

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| Throttled requests | ThrottledRequests | Sum | > 0 | 60s | Capacity insufficient |
| Read throttles | ReadThrottleEvents | Sum | > 0 | 60s | Separate from write throttles |
| Write throttles | WriteThrottleEvents | Sum | > 0 | 60s | Separate from read throttles |
| System errors | SystemErrors | Sum | > 0 | 60s | DynamoDB-side errors (rare) |
| User errors | UserErrors | Sum | > 10 | 60s | Conditional check failures, validation |
| Consumed RCU | ConsumedReadCapacityUnits | Sum | > 80% of provisioned | 300s | Provisioned mode only |
| Consumed WCU | ConsumedWriteCapacityUnits | Sum | > 80% of provisioned | 300s | Provisioned mode only |

## SQS

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| Queue depth | ApproximateNumberOfMessagesVisible | Maximum | > your processing capacity | 60s | Queue building up |
| Message age | ApproximateAgeOfOldestMessage | Maximum | > your processing SLA | 60s | Messages stuck in queue |
| DLQ depth | ApproximateNumberOfMessagesVisible (DLQ) | Sum | > 0 | 60s | Failed messages accumulating |
| Messages not visible | ApproximateNumberOfMessagesNotVisible | Maximum | > expected in-flight | 60s | Processing bottleneck |

## ECS

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| CPU utilization | CPUUtilization | Average | > 80% | 300s | Scaling trigger |
| Memory utilization | MemoryUtilization | Average | > 80% | 300s | Scaling trigger |
| Running task count | RunningTaskCount | Minimum | < desired count | 60s | Tasks crashing |

## CloudFront

| Alarm | Metric | Statistic | Threshold | Period | Notes |
|---|---|---|---|---|---|
| 5xx error rate | 5xxErrorRate | Average | > 1% | 300s | Origin errors |
| 4xx error rate | 4xxErrorRate | Average | > 10% | 300s | Client errors (may indicate misconfiguration) |
| Origin latency | OriginLatency | p99 | > 5s | 60s | Slow origin responses |
| Total error rate | TotalErrorRate | Average | > 5% | 300s | Combined error rate |

## Composite Alarm Example

Reduce alert fatigue by combining related alarms.

```yaml
ServiceHealthCompositeAlarm:
  Type: AWS::CloudWatch::CompositeAlarm
  Properties:
    AlarmName: "my-service-unhealthy"
    AlarmRule: |
      ALARM("my-service-5xx-rate") AND
      (ALARM("my-service-latency-p99") OR ALARM("my-service-error-rate"))
    AlarmActions:
      - !Ref PagerDutySNSTopic
    InsufficientDataActions: []
    OKActions:
      - !Ref PagerDutySNSTopic
```

This composite alarm fires only when there are 5XX errors AND either high latency or high application error rate. A single noisy metric alone will not page anyone.

## Anomaly Detection Alarm Example

```yaml
LatencyAnomalyAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: "api-latency-anomaly"
    Metrics:
      - Id: latency
        MetricStat:
          Metric:
            Namespace: AWS/ApiGateway
            MetricName: Latency
            Dimensions:
              - Name: ApiName
                Value: !Ref ApiName
          Period: 300
          Stat: p99
      - Id: anomaly_band
        Expression: "ANOMALY_DETECTION_BAND(latency, 2)"
        Label: "Anomaly Detection Band"
    ComparisonOperator: GreaterThanUpperThreshold
    ThresholdMetricId: anomaly_band
    EvaluationPeriods: 3
    DatapointsToAlarm: 2
    TreatMissingData: notBreaching
    AlarmActions:
      - !Ref AlertSNSTopic
```

The band width of 2 (standard deviations) is a reasonable starting point. Widen to 3 if too noisy. Narrow to 1.5 for critical paths where you want early warning.
