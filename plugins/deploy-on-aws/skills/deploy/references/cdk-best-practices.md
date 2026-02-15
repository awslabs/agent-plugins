# CDK Best Practices

Patterns for generating CDK IaC in the deploy workflow.

## Resource Naming

**DO NOT** explicitly specify resource names. Let CDK generate unique names:

```typescript
// ✅ Let CDK generate: StackName-MyFunctionXXXXXX
new lambda.Function(this, 'MyFunction', { /* no functionName */ });
```

**Why**: Enables reusable patterns, parallel deployments, and stack isolation.

## Lambda Constructs

Use language-specific constructs for automatic bundling:

- **TypeScript**: `NodejsFunction` from `aws-cdk-lib/aws-lambda-nodejs`
- **Python**: `PythonFunction` from `@aws-cdk/aws-lambda-python-alpha`

Benefits: Automatic dependency resolution, transpilation, and packaging.

## IAM Permissions

Use grant methods instead of raw policies:

```typescript
table.grantReadWriteData(handler);  // ✅
// NOT: handler.addToRolePolicy({ actions: ['dynamodb:*'], resources: ['*'] })
```

## Construct Levels

Prefer L3 (`LambdaRestApi`) > L2 (`Function`) > L1 (`CfnFunction`).

## Validation

1. Add **cdk-nag** for automated best-practice checks during synthesis
2. Run `cdk synth` to validate
3. Suppress findings with documented reasons via `NagSuppressions`

## Testing

- **Snapshot tests**: `expect(template.toJSON()).toMatchSnapshot()`
- **Assertions**: `template.hasResourceProperties('AWS::Lambda::Function', { ... })`

## Stack Organization

- Split at ~200 resources per stack
- Separate stateful (DB, S3) from stateless (compute) resources
- Export values via `CfnOutput` for cross-stack references

## Anti-Patterns

| Anti-Pattern                  | Fix                                     |
| ----------------------------- | --------------------------------------- |
| Hardcoded resource names      | Let CDK generate names                  |
| `actions: ['*']` in IAM       | Use grant methods                       |
| Manual Lambda bundling        | Use `NodejsFunction` / `PythonFunction` |
| Missing environment variables | Pass via `environment` prop             |
| No stack outputs              | Add `CfnOutput` for API URLs, ARNs      |
