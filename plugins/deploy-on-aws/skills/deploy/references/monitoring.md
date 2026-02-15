# Monitoring and Observability

Post-deployment monitoring patterns. Set up after successful deployment.

## When to Add Monitoring

- **Always**: Error alerting for deployed compute (Fargate, Lambda)
- **Production**: Full observability (alarms + dashboards + logs)
- **Dev**: Basic error alerting only

## Lambda Alarms

| Metric          | Threshold      | Periods |
| --------------- | -------------- | ------- |
| Errors (Sum)    | 10 per 5 min   | 1       |
| Duration (Max)  | 80% of timeout | 2       |
| Throttles (Sum) | 5 per 5 min    | 1       |

## ECS/Fargate Alarms

| Metric                 | Threshold     | Periods |
| ---------------------- | ------------- | ------- |
| CPU Utilization        | 80%           | 3       |
| Memory Utilization     | 85%           | 2       |
| Running Task Count < 1 | 1 (less-than) | 2       |

## ALB Alarms

| Metric               | Threshold    | Periods |
| -------------------- | ------------ | ------- |
| 5XX Error Count      | 10 per 5 min | 1       |
| Unhealthy Host Count | 1            | 2       |
| Response Time p99    | 1 second     | 2       |

## RDS/Aurora Alarms

| Metric               | Threshold  | Periods |
| -------------------- | ---------- | ------- |
| CPU Utilization      | 80%        | 3       |
| Free Storage Space   | < 10 GB    | 1       |
| Database Connections | 80% of max | 2       |

## Alarm Notification

Use SNS topic with email subscription for alarm actions:

```typescript
const topic = new sns.Topic(this, 'AlarmTopic');
topic.addSubscription(new subscriptions.EmailSubscription('ops@example.com'));
alarm.addAlarmAction(new actions.SnsAction(topic));
```

## Threshold Guidelines

| Category    | Warning      | Critical    |
| ----------- | ------------ | ----------- |
| CPU/Memory  | 70-80%       | 80-90%      |
| Error rate  | Based on SLA | 2× warning  |
| Latency p99 | 80% of SLA   | 100% of SLA |
| Storage     | 70% used     | 85% used    |

## Production Dashboard

Include these widget groups:

1. **Service Overview**: Request rate, error %, latency (p50/p95/p99)
2. **Resource Utilization**: CPU, memory, network by service
3. **Cost Metrics**: Daily spend, month-to-date
4. **Errors**: Error counts by type, recent logs
