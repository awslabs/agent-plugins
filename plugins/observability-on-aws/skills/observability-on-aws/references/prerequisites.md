# Prerequisites and Configuration

## Requirements

1. **AWS CLI configured** with credentials (`aws configure` or `~/.aws/credentials`)
2. **Python 3.10+** and `uv` installed
3. **Application Signals enabled** in your AWS account when applicable

## MCP Server Configuration

After installing this plugin, update the `env` section for each stdio MCP server with your AWS profile and region:

```json
"env": {
  "AWS_PROFILE": "your-profile-name",
  "AWS_REGION": "us-east-1",
  "FASTMCP_LOG_LEVEL": "ERROR"
}
```

Servers requiring AWS credentials: `awslabs.cloudwatch-mcp-server`, `awslabs.cloudwatch-applicationsignals-mcp-server`, `awslabs.cloudtrail-mcp-server`, `awslabs.billing-cost-management-mcp-server`.

**Default:** Uses `default` AWS profile and `us-east-1` region.

## Required IAM Permissions (read-only, least-privilege)

- **CloudWatch Metrics & Alarms**: `cloudwatch:GetMetricData`, `cloudwatch:GetMetricStatistics`, `cloudwatch:ListMetrics`, `cloudwatch:DescribeAlarms`, `cloudwatch:DescribeAlarmsForMetric`, `cloudwatch:DescribeAlarmHistory`, `cloudwatch:DescribeAnomalyDetectors`
- **CloudWatch Logs**: `logs:DescribeLogGroups`, `logs:DescribeLogStreams`, `logs:GetLogEvents`, `logs:FilterLogEvents`, `logs:StartQuery`, `logs:StopQuery`, `logs:GetQueryResults`, `logs:DescribeQueries`
- **X-Ray**: `xray:BatchGetTraces`, `xray:GetTraceSummaries`, `xray:GetTraceGraph`, `xray:GetServiceGraph`, `xray:GetTimeSeriesServiceStatistics`
- **CloudTrail (events + Lake queries)**: `cloudtrail:LookupEvents`, `cloudtrail:DescribeTrails`, `cloudtrail:GetTrail`, `cloudtrail:ListTrails`, `cloudtrail:GetEventSelectors`, `cloudtrail:ListEventDataStores`, `cloudtrail:GetEventDataStore`, `cloudtrail:StartQuery`, `cloudtrail:DescribeQuery`, `cloudtrail:GetQueryResults`, `cloudtrail:ListQueries`, `cloudtrail:CancelQuery`
- **Application Signals**: `application-signals:GetService`, `application-signals:ListServices`, `application-signals:ListServiceOperations`, `application-signals:GetServiceLevelObjective`, `application-signals:ListServiceLevelObjectives`, `application-signals:BatchGetServiceLevelObjectiveBudgetReport`
- **Billing & Cost Management (read-only)**: `ce:GetCostAndUsage`, `ce:GetCostAndUsageWithResources`, `ce:GetCostForecast`, `ce:GetCostCategories`, `ce:GetDimensionValues`, `ce:GetTags`, `ce:GetAnomalies`, `ce:GetAnomalyMonitors`, `ce:GetReservationUtilization`, `ce:GetSavingsPlansUtilization`, `ce:DescribeCostCategoryDefinition`, `cost-optimization-hub:ListRecommendations`, `cost-optimization-hub:GetRecommendation`, `compute-optimizer:GetEnrollmentStatus`, `compute-optimizer:GetRecommendationSummaries`, `compute-optimizer:GetEC2InstanceRecommendations`, `compute-optimizer:GetAutoScalingGroupRecommendations`, `compute-optimizer:GetLambdaFunctionRecommendations`, `budgets:ViewBudget`, `pricing:GetProducts`, `pricing:DescribeServices`, `freetier:GetFreeTierUsage`
- `synthetics:GetCanary`, `synthetics:GetCanaryRuns` for canary analysis
- `s3:GetObject`, `s3:ListBucket` for canary artifacts
- `iam:GetRole`, `iam:ListAttachedRolePolicies`, `iam:GetPolicy`, `iam:GetPolicyVersion` for enablement guides
