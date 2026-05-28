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
- **Thread safety**, **concurrency model**, **code review checklist**, **Powertools compatibility**, or **multi-concurrency readiness** -> see [references/thread-safety.md](references/thread-safety.md)
- **Before/after code examples**, **runtime-specific migration** (Node.js, Python, Java, .NET), or **connection pooling** -> see [references/migration-patterns.md](references/migration-patterns.md)
- **IAM roles**, **VPC setup**, **CLI commands**, **SAM template**, or **CDK example** -> see [references/infrastructure-setup.md](references/infrastructure-setup.md) and [scripts/setup-lmi.sh](scripts/setup-lmi.sh)
- **Errors**, **throttling**, **debugging**, or **stuck deployments** -> see [references/troubleshooting.md](references/troubleshooting.md)

## Quick Decision: Is LMI Right for This Workload?

| Signal         | LMI is a strong fit                                                                     | Standard Lambda is better                              |
| -------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| Traffic        | Steady, predictable, 50M+ req/mo                                                        | Bursty, unpredictable, long idle                       |
| Cost           | Duration-heavy spend at scale                                                           | Low or sporadic invocations                            |
| Cold starts    | Unacceptable (LMI eliminates for provisioned capacity; scale-out may have brief delays) | Tolerable or mitigated by SnapStart                    |
| Compute        | Latest CPUs, specific families, high network bandwidth                                  | Standard Lambda memory/CPU sufficient                  |
| Isolation      | Dedicated EC2 instances in your account, full VPC control                               | Shared Firecracker micro-VMs acceptable                |
| Scale-to-zero  | Not needed (execution environments always running)                                      | Required (pay nothing when idle)                       |
| Code readiness | Thread-safe (Node.js/Java/.NET) or any Python code                                      | Non-thread-safe Node.js/Java/.NET, expensive to change |

## Instructions

### Step 1: Assess the Workload

Gather these signals before recommending:

1. **Traffic pattern**: Steady vs bursty? Requests per second?
2. **Current costs**: Monthly Lambda spend? Existing Savings Plans?
3. **Runtime**: Node.js, Java, .NET, or Python?
4. **Memory/CPU**: How much memory? CPU-bound or I/O-bound?
5. **Execution duration**: Average and P99?
6. **Concurrency readiness**: Thread safety (Node.js/Java/.NET)? Shared `/tmp` paths? Per-invocation DB connections?
7. **VPC**: Already in a VPC? Private resource access needed?

### Step 2: Build the Cost Comparison

REQUIRED: Present a cost comparison before recommending LMI. Compare at minimum:

| Scenario         | When it wins                |
| ---------------- | --------------------------- |
| Lambda on-demand | Low volume, bursty traffic  |
| LMI on-demand    | High volume, steady traffic |

Rule of thumb: LMI becomes cost-competitive when your Lambda spend exceeds ~$1,000/month with steady traffic.

For discount analysis (Savings Plans, Reserved Instances), refer users to the [AWS Pricing Calculator](https://calculator.aws/) and [references/cost-comparison.md](references/cost-comparison.md) for formulas and worked examples. Discount recommendations require workload-specific forecasting beyond this skill's scope.

### Step 3: Configure the Deployment

**Instance families** (~450 types): C-series (compute, .xlarge+), M-series (general, .large+), R-series (memory, .large+). ARM (Graviton) for best price-performance.

**Memory-to-vCPU ratios**: 2:1 (compute), 4:1 (general, default), 8:1 (memory). Min 2 GB, max 32 GB.

**Multi-concurrency defaults/vCPU**: Node.js 64, Java 32, .NET 32, Python 16.

**Scaling**: MinExecutionEnvironments (default 3), MaxVCpuCount (default 400), TargetResourceUtilization.

See [references/configuration-guide.md](references/configuration-guide.md) for decision trees and detailed tuning.

### Step 4: Migrate the Code

Review code for concurrency safety. LMI runs multiple invocations concurrently per execution environment, but the model differs by runtime:

- **Python**: Process-based isolation — globals are NOT shared. No thread-safety changes needed. Focus on `/tmp` conflicts and memory sizing (per-process × concurrency).
- **Node.js**: Worker threads — globals shared within a worker. Requires async safety. Callback handlers not supported on Node.js 22.
- **Java/.NET**: OS threads/Tasks — handler shared across threads. Requires full thread safety.

**Common issues (all runtimes)**: shared `/tmp` paths, per-invocation DB connections.
**Thread-safety issues (Node.js/Java/.NET only)**: mutable globals, non-thread-safe libs.

See [references/thread-safety.md](references/thread-safety.md) for the review checklist and [references/migration-patterns.md](references/migration-patterns.md) for runtime-specific before/after code.

### Step 5: Set Up Infrastructure

1. Create two IAM roles: execution role (for the function) and operator role (for capacity provider EC2 management)
2. Configure VPC with subnets across multiple AZs (recommended 3+ for resiliency)
3. Create capacity provider with VPC config and scaling limits
4. Create or update function with capacity provider attachment
5. Publish a version (triggers instance provisioning)

See [references/infrastructure-setup.md](references/infrastructure-setup.md) for CLI commands and SAM templates.

### Step 6: Validate and Cut Over

1. Deploy to a non-production environment first
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
- Don't: Set MinExecutionEnvironments below 3 in production (reduces multi-AZ coverage). Non-prod environments can use 1 as the minimum.
- Don't: Over-restrict instance types (lowers availability)

### Migration

- Do: Start with I/O-heavy functions (benefit most from multi-concurrency; CPU-bound functions compete for same CPU)
- Do: Review code for concurrency safety before attaching to capacity provider (thread safety for Node.js/Java/.NET; `/tmp` and memory for Python)
- Do: Use weighted aliases for gradual traffic shift
- Do: Include request IDs in all log statements
- Do: Initialize DB pools and SDK clients outside the handler
- Do: Estimate total `/tmp` usage under max concurrency
- Don't: Write to hardcoded `/tmp` paths without request-unique naming
- Don't: Skip cost comparison — LMI is not always cheaper

### Operations

- Do: Set CloudWatch alarms on throttle rate > 1% and CPU > 80%
- Don't: Manually terminate LMI EC2 instances (delete the capacity provider instead)
- Don't: Forget to publish a version — unpublished functions cannot run on LMI

## Limits Quick Reference

| Resource          | Limit                                     |
| ----------------- | ----------------------------------------- |
| Memory            | 2 GB min, 32 GB max                       |
| Concurrency/vCPU  | 64 (Node.js), 32 (Java/.NET), 16 (Python) |
| Instance lifespan | ~12 hours (auto-replaced by Lambda)       |
| EE lifespan       | ~4 hours (auto-replaced by Lambda)        |
| Runtimes          | Node.js, Java, .NET, Python               |
| Instance families | C (.xlarge+), M (.large+), R (.large+)    |
| Scaling           | Doubles within 5 min without throttles    |

## Troubleshooting Quick Reference

| Issue                      | Cause                             | Fix                                                                  |
| -------------------------- | --------------------------------- | -------------------------------------------------------------------- |
| 429 throttles              | Traffic exceeds scaling speed     | Increase MinExecutionEnvironments or lower TargetResourceUtilization |
| Function stuck PENDING     | Provisioning instances            | Wait; check VPC/IAM config                                           |
| Architecture mismatch      | Function ≠ capacity provider arch | Align both to same architecture                                      |
| Cannot terminate instances | Managed by capacity provider      | Delete capacity provider instead                                     |
| Race conditions            | Code not thread-safe              | See [references/thread-safety.md](references/thread-safety.md)       |

See [references/troubleshooting.md](references/troubleshooting.md) for detailed resolution steps.

## Configuration

### AWS CLI Setup

REQUIRED: AWS credentials configured on the host machine.

**Verify access**: Run `aws sts get-caller-identity`

### Regional Availability

Currently available: us-east-1, us-east-2, us-west-2, ap-northeast-1, eu-west-1. Expanding to all commercial regions soon.

Check the [Lambda Managed Instances documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-managed-instances.html) for the latest regional availability.

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
- [Migrating Functions to LMI (AWS Blog)](https://aws.amazon.com/blogs/compute/migrating-your-functions-to-aws-lambda-managed-instances/)
- [LMI Pricing Calculator](https://aws-samples.github.io/sample-aws-lambda-managed-instances/)
- [LMI Samples Repository](https://github.com/aws-samples/sample-aws-lambda-managed-instances)
- [AWS Lambda Pricing](https://aws.amazon.com/lambda/pricing/)
