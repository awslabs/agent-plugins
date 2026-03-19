# Alerting Setup

## Purpose

Guidance for setting up effective CloudWatch alarms using recommended configurations. For composite alarms, anomaly detection, SLO alerting, and tuning, see `alerting-advanced.md`.

## Core Concepts

**Alarm States**: OK (within threshold), ALARM (breached), INSUFFICIENT_DATA (not enough data).

**Alarm Components**: Metric (what to monitor), Statistic (how to aggregate), Threshold (trigger value), Evaluation Period (time window), Datapoints to Alarm (how many periods must breach).

**Alarm Types**: Metric Alarm (single metric), Composite Alarm (combines alarms with AND/OR/NOT), Anomaly Detection Alarm (ML-based).

## Getting Recommended Alarm Configurations

Use `get_recommended_metric_alarms` with namespace, metric_name, dimensions, and statistic. Returns recommended threshold, evaluation periods, datapoints to alarm, description, and rationale.

## Choosing the Right Statistic (must match metric type)

- **Count** (use `Sum`): Errors, Faults, Throttles, Invocations, RequestCount
- **Utilization** (use `Average`): CPUUtilization, MemoryUtilization, DiskUtilization
- **Latency/Time** (use `Average` or percentiles): Duration, Latency, ResponseTime
- **Size** (use `Average`): PayloadSize, MessageSize, RequestSize

## Alarm Configuration Patterns

### Lambda Function Errors

```
Metric: AWS/Lambda - Errors | Statistic: Sum | Threshold: > 5 errors
Evaluation Period: 5 min | Datapoints: 2 of 3
Rationale: Sum for count metrics; 2/3 reduces false positives
```

### EC2 CPU Utilization

```
Metric: AWS/EC2 - CPUUtilization | Statistic: Average | Threshold: > 80%
Evaluation Period: 5 min | Datapoints: 3 of 3
Rationale: Average smooths spikes; 3/3 ensures sustained high CPU
```

### API Gateway Latency

```
Metric: AWS/ApiGateway - Latency | Statistic: p99 | Threshold: > 1000ms
Evaluation Period: 5 min | Datapoints: 2 of 3
Rationale: p99 catches tail latency; 1000ms threshold for user experience
```

### RDS Database Connections

```
Metric: AWS/RDS - DatabaseConnections | Statistic: Average | Threshold: > 80% of max
Evaluation Period: 5 min | Datapoints: 3 of 3
Rationale: Average shows sustained usage; prevents connection pool exhaustion
```

### DynamoDB Throttles

```
Metric: AWS/DynamoDB - ReadThrottleEvents / WriteThrottleEvents | Statistic: Sum
Threshold: > 10 throttle events | Evaluation Period: 1 min | Datapoints: 2 of 2
Rationale: Sum for event counts; 1-min for quick detection; 2/2 confirms sustained throttling
```

## Alarm Best Practices

**Naming Convention**: `[severity]-[service]-[metric]-[condition]` (e.g., `critical-api-error-rate-high`)

**Descriptions** - use template: `"[Service] [Metric] is [Condition]. Current value: {{value}}. Threshold: {{threshold}}. Runbook: [link]. Dashboard: [link]."`

**Treat Missing Data**: `notBreaching` for most alarms, `breaching` when missing data indicates a problem, `ignore` for sparse data.

**Evaluation Periods**: Fast (1-2 min) for critical/user-facing. Balanced (5 min) for most metrics. Slow (10-15 min) for cost/capacity.

## Quick Reference

```
# Lambda Errors
get_recommended_metric_alarms(namespace="AWS/Lambda", metric_name="Errors",
  dimensions=[{name: "FunctionName", value: "my-function"}], statistic="Sum")
# EC2 CPU
get_recommended_metric_alarms(namespace="AWS/EC2", metric_name="CPUUtilization",
  dimensions=[{name: "InstanceId", value: "i-1234567890abcdef0"}], statistic="Average")
# API Gateway Latency
get_recommended_metric_alarms(namespace="AWS/ApiGateway", metric_name="Latency",
  dimensions=[{name: "ApiName", value: "my-api"}], statistic="p99")
# Check active alarms
get_active_alarms(state_value="ALARM")
# Review alarm history
get_alarm_history(alarm_name="my-alarm", history_item_type="StateUpdate",
  start_time="2026-01-01T00:00:00Z", end_time="2026-01-20T00:00:00Z")
```
