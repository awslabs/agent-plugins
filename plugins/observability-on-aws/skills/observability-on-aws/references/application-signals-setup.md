# Application Signals Setup and Enablement Guide

This reference provides comprehensive guidance for setting up AWS Application Signals using the plugin's enablement guide feature.

## Quick Start: Get Enablement Guide

**First Step**: Always start by getting the official enablement guide from AWS:

```
Use the awslabs.cloudwatch-applicationsignals-mcp-server's get_enablement_guide tool with the following required parameters:
  - service_platform (required): "ec2", "ecs", "lambda", or "eks"
  - service_language (required): "python", "nodejs", "java", or "dotnet"
  - iac_directory (required): Absolute path to your Infrastructure as Code directory
  - app_directory (required): Absolute path to your application code directory
```

This tool provides:

- Current prerequisites and requirements
- Step-by-step enablement instructions
- Service instrumentation guidance
- Best practices and recommendations
- Troubleshooting common issues

## Application Signals Setup Workflow

### Phase 1: Prerequisites Check

Before enabling Application Signals, verify:

1. **AWS Account Requirements**:
   - Application Signals is available in your region
   - Sufficient IAM permissions for CloudWatch and X-Ray
   - EC2/ECS/EKS/Lambda services are running

2. **Service Requirements**:
   - Applications are instrumented with AWS X-Ray SDK or OpenTelemetry
   - Services are running in supported compute environments
   - Network connectivity allows telemetry data transmission

### Phase 2: Enable Application Signals

1. **Get the Latest Guide**:

   ```
   Use get_enablement_guide to get current setup instructions
   ```

2. **Enable at Account Level**:
   - Use AWS Console or CLI to enable Application Signals
   - Configure service discovery settings
   - Set up data retention policies

3. **Verify Enablement**:
   - Check that Application Signals is active
   - Confirm data ingestion is working
   - Validate service discovery

### Phase 3: Service Instrumentation

Based on the enablement guide, instrument your services:

1. **For Lambda Functions**:
   - Enable X-Ray tracing
   - Add AWS X-Ray SDK to function code
   - Configure environment variables

2. **For ECS/EKS Services**:
   - Deploy X-Ray daemon as sidecar
   - Configure service mesh integration (if applicable)
   - Set up OpenTelemetry collectors

3. **For EC2 Applications**:
   - Install X-Ray daemon
   - Configure application instrumentation
   - Set up auto-discovery tags

### Phase 4: Configure Monitoring

1. **Service Level Objectives (SLOs)**:
   - Define availability targets
   - Set latency thresholds
   - Configure error rate limits

2. **Dashboards and Alarms**:
   - Create service overview dashboards
   - Set up performance alarms
   - Configure notification channels

## Common Setup Patterns

### Pattern 1: Microservices Architecture

For distributed microservices:

1. Get enablement guide for microservices setup
2. Enable Application Signals at the account level
3. Instrument each service with X-Ray SDK
4. Configure service maps and dependencies
5. Set up cross-service SLOs

### Pattern 2: Serverless Applications

For Lambda-based applications:

1. Get enablement guide for serverless setup
2. Enable X-Ray tracing on all Lambda functions
3. Configure API Gateway integration
4. Set up end-to-end tracing
5. Create function-level SLOs

### Pattern 3: Container Workloads

For ECS/EKS applications:

1. Get enablement guide for container setup
2. Deploy X-Ray daemon containers
3. Configure service discovery
4. Set up cluster-level monitoring
5. Create pod/task-level SLOs

## Troubleshooting Setup Issues

### Common Problems and Solutions

1. **No Data Appearing**:
   - Re-run get_enablement_guide for latest troubleshooting steps
   - Verify service instrumentation
   - Check IAM permissions
   - Validate network connectivity

2. **Incomplete Service Maps**:
   - Ensure all services are instrumented
   - Check X-Ray sampling rules
   - Verify service naming consistency

3. **Missing Metrics**:
   - Confirm Application Signals is enabled
   - Check service discovery configuration
   - Validate metric emission

## Best Practices from Enablement Guide

Always refer to the latest enablement guide, but common best practices include:

1. **Instrumentation**:
   - Use consistent service naming
   - Implement proper error handling
   - Configure appropriate sampling rates

2. **Monitoring**:
   - Start with basic SLOs and iterate
   - Use composite alarms for complex scenarios
   - Set up proper alerting channels

3. **Performance**:
   - Monitor instrumentation overhead
   - Optimize sampling configurations
   - Use async telemetry transmission

## Integration with Other Plugin Features

### Combine with CloudWatch Logs

Use Logs Insights queries to correlate Application Signals data with logs:

```
fields @timestamp, @message, traceId, duration
| filter ispresent(traceId)
| sort duration desc
| limit 100
```

### Combine with CloudTrail

Track Application Signals configuration changes:

- Monitor EnableApplicationSignals API calls
- Track service configuration modifications
- Audit SLO changes

## Validation Steps

After setup, validate your Application Signals implementation:

1. **Data Flow Validation**:
   - Confirm traces are appearing in X-Ray
   - Verify metrics in CloudWatch
   - Check service maps are populated

2. **SLO Validation**:
   - Test SLO calculations
   - Verify alarm triggering
   - Confirm notification delivery

3. **Performance Validation**:
   - Monitor instrumentation overhead
   - Check data ingestion costs
   - Validate query performance

## Next Steps After Setup

Once Application Signals is enabled:

1. Create comprehensive service dashboards
2. Set up automated alerting workflows
3. Implement SLO-based incident response
4. Train team on Application Signals features
5. Establish monitoring best practices

## Resources

- Use `get_enablement_guide` tool for latest official documentation
- [Application Signals User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Application-Signals.html)
- [X-Ray Developer Guide](https://docs.aws.amazon.com/xray/latest/devguide/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)

---

**Remember**: Always start with the `get_enablement_guide` tool to get the most current and accurate setup instructions for your specific environment and use case.
