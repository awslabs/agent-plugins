---
name: aws-lambda-managed-instances
description: >
  Evaluate, configure, and migrate workloads to AWS Lambda Managed Instances (LMI).
  Triggers on: Lambda Managed Instances, LMI, capacity provider, multi-concurrency Lambda,
  dedicated instance Lambda, EC2-backed Lambda, cold start elimination, Graviton Lambda,
  instance type for Lambda, Lambda cost optimization with Reserved Instances or Savings Plans.
  Also trigger when users describe high-volume predictable workloads seeking cost savings,
  or compare Lambda vs EC2 for steady-state traffic. For standard Lambda without LMI,
  use the aws-lambda skill instead.
argument-hint: "[describe your workload or what you need help with]"
metadata:
  tags: lambda, lmi, managed-instances, ec2, capacity-provider, multi-concurrency, cost-optimization
---

# AWS Lambda Managed Instances (LMI)

Run Lambda functions on current-generation EC2 instances in your account while AWS manages provisioning, patching, scaling, routing, and load balancing. Combines Lambda's developer experience with EC2's pricing and hardware options.

For standard Lambda development, see [aws-lambda skill](../aws-lambda/). For SAM/CDK deployment, see [aws-serverless-deployment skill](../aws-serverless-deployment/).

## When to Load Reference Files

- **Cost comparison**, **pricing analysis**, **Lambda vs LMI cost**, **Savings Plans**, or **Reserved Instances** -> see [references/cost-comparison.md](references/cost-comparison.md)
- **Instance types**, **memory sizing**, **vCPU ratios**, **scaling tuning**, or **capacity provider config** -> see [references/configuration-guide.md](references/configuration-guide.md)
- **Thread safety**, **code review checklist**, or **multi-concurrency readiness** -> see [references/thread-safety.md](references/thread-safety.md)
- **Before/after code examples**, **runtime-specific migration** (Node.js, Python, Java, .NET), or **connection pooling** -> see [references/migration-patterns.md](references/migration-patterns.md)
- **IAM roles**, **VPC setup**, **CLI commands**, **SAM template**, or **CDK example** -> see [references/infrastructure-setup.md](references/infrastructure-setup.md)
- **Errors**, **throttling**, **debugging**, or **stuck deployments** -> see [references/troubleshooting.md](references/troubleshooting.md)

## Quick Decision: Is LMI Right for This Workload?

| Signal | LMI is a strong fit | Standard Lambda is better |
|--------|---------------------|---------------------------|
| Traffic | Steady, predictable, 50M+ req/mo | Bursty, unpredictable, long idle |
| Cost | Duration-heavy spend at scale | Low or sporadic invocations |
| Cold starts | Unacceptable (LMI has zero) | Tolerable or mitigated by SnapStart |
| Compute | Latest CPUs, specific families, high network BW | Standard Lambda memory/CPU sufficient |
| Compliance | Single-tenant required, VPC control | Multi-tenant Firecracker acceptable |
| Scale-to-zero | Not needed (min 3 instances always run) | Required (pay nothing when idle) |
| Code readiness | Thread-safe or feasible to refactor | Non-thread-safe, expensive to change |

## Instructions

### Step 1: Assess the Workload

Gather these signals before recommending:

1. **Traffic pattern**: Steady vs bursty? Requests per second?
2. **Current costs**: Monthly Lambda spend? Existing Savings Plans?
3. **Runtime**: Node.js, Java, .NET, or Python?
4. **Memory/CPU**: How much memory? CPU-bound or I/O-bound?
5. **Execution duration**: Average and P99?
6. **Thread safety**: Mutable globals, shared `/tmp` paths, non-thread-safe libs?
7. **VPC**: Already in a VPC? Private resource access needed?

### Step 2: Build the Cost Comparison

REQUIRED: Present a 4-column comparison before recommending LMI.

| Scenario | When it wins |
|----------|-------------|
| Lambda on-demand | Low volume, bursty traffic |
| Lambda + Savings Plan | Moderate steady volume (~17% duration discount) |
| LMI on-demand | High volume, steady traffic |
| LMI + 3yr Savings Plan | High volume + commitment (up to 72% EC2 discount) |

Rule of thumb: LMI becomes cost-competitive at 50-100M+ req/month with steady traffic.

See [references/cost-comparison.md](references/cost-comparison.md) for formulas, worked example, and comparison table template.

### Step 3: Configure the Deployment

**Instance families** (400+ types, .large and up): C-series (compute), M-series (general), R-series (memory). ARM (Graviton) for best price-performance.

**Memory-to-vCPU ratios**: 2:1 (compute), 4:1 (general, default), 8:1 (memory). Min 2 GB, max 32 GB.

**Multi-concurrency defaults/vCPU**: Node.js 64, Java 32, .NET 32, Python 16.

**Scaling**: MinExecutionEnvironments (default 3), MaxVCpuCount (required), TargetResourceUtilization.

See [references/configuration-guide.md](references/configuration-guide.md) for decision trees and detailed tuning.

### Step 4: Migrate the Code

Review code for thread safety. LMI runs multiple invocations concurrently per execution environment.

**Common issues**: mutable globals, shared `/tmp` paths, non-thread-safe libs, per-invocation DB connections.

See [references/thread-safety.md](references/thread-safety.md) for the review checklist and [references/migration-patterns.md](references/migration-patterns.md) for runtime-specific before/after code.

### Step 5: Set Up Infrastructure

Two IAM roles required (execution + operator). VPC with 3+ AZ subnets. Create capacity provider, attach function, publish version.

See [references/infrastructure-setup.md](references/infrastructure-setup.md) for CLI commands, SAM, and CDK templates.

### Step 6: Validate and Cut Over

1. Test locally with LocalStack (supports LMI emulation)
2. Monitor CloudWatch: CPU utilization, memory, concurrency, throttle rate
3. Gradual traffic shift with weighted aliases (10% → 50% → 100%)
4. Compare costs after 1-2 weeks of production data
5. Decommission standard Lambda once stable

## Best Practices

### Configuration

- Do: Start with 4:1 ratio and runtime default concurrency
- Do: Use ARM (Graviton) unless x86 dependencies exist
- Do: Let Lambda choose instance types unless specific hardware needed
- Do: Set MaxVCpuCount to control cost ceiling
- Don't: Set MinExecutionEnvironments below 3 (breaks AZ resiliency)
- Don't: Over-restrict instance types (lowers availability)

### Migration

- Do: Review all code for thread safety before attaching to capacity provider
- Do: Use weighted aliases for gradual traffic shift
- Do: Include request IDs in all log statements
- Do: Initialize DB pools and SDK clients outside the handler
- Don't: Write to hardcoded `/tmp` paths without request-unique naming
- Don't: Skip cost comparison — LMI is not always cheaper

### Operations

- Do: Set CloudWatch alarms on throttle rate > 1% and CPU > 80%
- Do: Plan for 14-day instance rotation (automatic)
- Don't: Manually terminate LMI EC2 instances (delete the capacity provider instead)
- Don't: Forget to publish a version — unpublished functions cannot run on LMI

## Limits Quick Reference

| Resource | Limit |
|----------|-------|
| Memory | 2 GB min, 32 GB max |
| Instances | 3 minimum (AZ resiliency) |
| Instance lifespan | 14 days (auto-replaced) |
| Concurrency/vCPU | 64 (Node.js), 32 (Java/.NET), 16 (Python) |
| Runtimes | Node.js, Java, .NET, Python |
| Instance families | C, M, R (.large and up) |
| Scaling | Absorbs 50% spike; doubles within 5 min |

## Troubleshooting Quick Reference

| Issue | Cause | Fix |
|-------|-------|-----|
| 429 throttles | Traffic exceeds scaling speed | Increase MinExecutionEnvironments or lower TargetResourceUtilization |
| Function stuck PENDING | Provisioning instances | Wait; check VPC/IAM config |
| Architecture mismatch | Function ≠ capacity provider arch | Align both to same architecture |
| Cannot terminate instances | Managed by capacity provider | Delete capacity provider instead |
| Race conditions | Code not thread-safe | See [references/thread-safety.md](references/thread-safety.md) |

See [references/troubleshooting.md](references/troubleshooting.md) for detailed resolution steps.

## Configuration

### AWS CLI Setup

REQUIRED: AWS credentials configured on the host machine.

**Verify access**: Run `aws sts get-caller-identity`

### Regional Availability

us-east-1, us-east-2, us-west-2, ap-northeast-1, eu-west-1

## Language Selection

Default: TypeScript

Override: "use Python" → Python, "use JavaScript" → JavaScript. When not specified, ALWAYS use TypeScript.

## IaC Framework Selection

Default: CDK

Override: "use SAM" → SAM YAML, "use CloudFormation" → CloudFormation YAML. When not specified, ALWAYS use CDK.

## Error Scenarios

### Serverless MCP Server Unavailable

- Inform user: "AWS Serverless MCP not responding"
- Ask: "Proceed without MCP support?"
- DO NOT continue without user confirmation

### Unsupported Runtime

- State: "Lambda Managed Instances does not yet support [runtime]"
- List supported runtimes
- Suggest standard Lambda as alternative

### Unsupported Region

- State: "Lambda Managed Instances is not yet available in [region]"
- List available regions

## Resources

- [Lambda Managed Instances Docs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html)
- [Introducing LMI (AWS Blog)](https://aws.amazon.com/blogs/aws/introducing-aws-lambda-managed-instances-serverless-simplicity-with-ec2-flexibility/)
- [Build High-Performance Apps with LMI](https://aws.amazon.com/blogs/compute/build-high-performance-apps-with-aws-lambda-managed-instances/)
- [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/)
