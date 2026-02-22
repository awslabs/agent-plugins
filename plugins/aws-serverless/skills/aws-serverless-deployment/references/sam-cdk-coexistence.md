# SAM and CDK Coexistence

Most teams don't switch from SAM to CDK all at once. Both tools produce CloudFormation, so they can coexist in the same project, the same account, and even the same CI/CD pipeline.

## Incremental Migration

The lowest-risk approach is to add CDK alongside SAM rather than replacing it:

1. **Start with one new stack in CDK** — a supporting resource (DynamoDB table, SQS queue, event bus) that your SAM functions reference via SSM parameters or CloudFormation exports
2. **Keep existing SAM stacks untouched** — they continue to deploy via `sam build && sam deploy`
3. **Migrate function stacks gradually** — move functions to CDK one stack at a time as you gain confidence

Cross-stack references between SAM and CDK stacks work the same way as any CloudFormation cross-stack reference: export a value from one stack, import it in the other via `Fn::ImportValue` (SAM) or `cdk.Fn.importValue()` (CDK). Alternatively, write values to SSM Parameter Store and read them from either side.

## Using `sam build` with CDK Templates

SAM CLI can build and locally test functions defined in any CloudFormation template, including one synthesized by CDK:

```bash
# Synthesize the CDK app to cdk.out/
cdk synth

# Use sam build on the synthesized template
sam build --template cdk.out/MyStack.template.json

# Test a function locally
sam local invoke MyFunction --template cdk.out/MyStack.template.json
```

This gives you CDK's construct model for infrastructure while keeping `sam local invoke` for local testing.

## When to Use Which

| Scenario                                                                  | Recommendation                                   |
| ------------------------------------------------------------------------- | ------------------------------------------------ |
| New Lambda-centric project, small team                                    | SAM — simpler, `sam local invoke` built-in       |
| New project with complex infrastructure (VPCs, multiple services)         | CDK — richer abstractions, `grant*` methods      |
| Existing SAM project, works fine                                          | Keep SAM — migration cost isn't justified        |
| Existing SAM project, hitting limits (no loops, hard to share constructs) | Migrate incrementally to CDK                     |
| Reusable infrastructure patterns shared across teams                      | CDK construct libraries                          |
| Need `sam local invoke` + CDK constructs                                  | Hybrid — `cdk synth` + `sam build` on the output |
