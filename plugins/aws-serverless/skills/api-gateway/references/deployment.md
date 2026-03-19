# Deployment Strategies

## Deployment Basics

### Understanding Deployments

A Deployment in API Gateway is an **immutable snapshot of your API configuration**, not an action. Think of it like a git commit: changes to your API (resources, methods, integrations, authorizers) are like commits to a main branch that cannot be invoked externally. To make changes callable, you create a Deployment (snapshot) and point a Stage to it.

- **Creating a Deployment** = taking a snapshot of the current API state
- **Deploying to a Stage** = updating a stage to point to that snapshot
- Multiple stages can point to the same or different deployments
- **Console "Test Invoke" bypasses deployments**: it always uses the current API state (not a deployed snapshot). Bypasses IAM auth, Lambda authorizers, Cognito authorizers, API key validation, throttling, WAF, resource policies, and mTLS. Use [`TestInvokeAuthorizer`](https://docs.aws.amazon.com/apigateway/latest/api/API_TestInvokeAuthorizer.html) to test authorizer logic separately. This is why "it works in console but not when invoked" is a common complaint

### REST API

- Explicit deployment required to make changes live. Each deployment is immutable
- A stage cannot be created without a deployment (deploymentId is required in CreateStage)
- A deployment can be created without deploying to a stage (stageName is optional in CreateDeployment)
- **Always redeploy after**: changing resource policy, adding/modifying methods, updating integrations, configuring authorizers, modifying models or request validators
- **No redeployment needed for**: throttling/usage plan changes, logging configuration, caching TTL (capacity changes take effect without redeployment but cause ~4 minutes of cache unavailability during resizing), stage variable values, client certificate changes, WAF association changes (propagation takes minutes). These take effect on the stage without a new deployment
- Max 10 stages per API (adjustable via [Service Quotas](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html))
- Stage variables: max 100 per stage, referenced as `${stageVariables.variableName}` in integration URIs and `$stageVariables.variableName` in VTL mapping templates

### HTTP API

- A stage can be created without a deployment (then updated via UpdateStage)
- Supports automatic deployments (AutoDeploy); changes deploy immediately
- Explicit deployments also supported for manual control
- **AutoDeploy caveat**: AutoDeploy is a **security risk**. It triggers a new deployment after each API management operation completes. When making multiple changes via separate API calls, intermediate states are briefly live. A new route may be deployed before its authorizer is attached, **exposing an unauthenticated endpoint to the internet** for seconds to minutes. Routes may also deploy before their integration or IAM role, causing 500 errors. With explicit deployments (or SAM/CDK), all configuration changes are made first, then a single deployment snapshot is created, avoiding intermediate states. **Avoid AutoDeploy in production**; it is a security and availability risk, not just an operational inconvenience

### WebSocket API

- A stage can be created without a deployment (then updated via UpdateStage)
- Does **not** support automatic deployments (AutoDeploy); every change requires an explicit redeployment

### Deployment Propagation

Changes do not propagate to all API Gateway data plane hosts simultaneously. During propagation:

- Some hosts serve the new deployment while others still serve the old one
- If you delete a resource (e.g., Lambda function) that the old deployment references, requests hitting hosts still propagating will get 500 errors
- **Always retain old resources** until propagation completes, then remove them in a subsequent deployment

## Canary Deployments (REST API Only)

Route a percentage of traffic to a canary deployment for testing **API configuration changes** (not code changes):

1. Deploy new version to a canary
2. Configure canary traffic percentage (e.g., 10%)
3. Monitor via CloudWatch Logs (`API-Gateway-Execution-Logs_<api-id>/<stage>`)
4. **Promote**: "Promote Canary" replaces the stage's deployment with the canary's deployment and removes all canary settings in a single operation. All traffic then uses the new configuration. **Note**: If `useStageCache: false` (canary used a separate cache), the canary cache is discarded on promotion, causing a cache miss spike. Consider flushing the stage cache or setting short TTLs during canary testing
5. **Rollback**: **Delete the canary release** to revert all traffic to the base stage deployment. Setting the percentage to 0% merely stops canary traffic but does not remove canary settings, so it is not a proper rollback

- Configure via `canarySettings` on a stage: `percentTraffic` (0.0–100.0), `useStageCache` (whether canary uses the stage cache or a separate one)
- **Canary releases test API Gateway configuration** (new resources, integrations, mapping templates, authorizers), not Lambda code changes. For Lambda code canary, use Lambda aliases with weighted routing
- Monitor `Latency`, `5XXError`, `4XXError` CloudWatch metrics filtered by canary stage to compare against the production baseline before promoting
- SAM: Define canary settings programmatically with `sam deploy`
- Stage variable overrides supported during canary period
- For direct service integrations (DynamoDB, SQS, etc.): canary deployments are the only way to do gradual rollouts since there are no Lambda aliases involved

## Manual Rollback via Deployment History (REST API)

REST APIs retain a history of all deployments. The fastest rollback mechanism is to point the stage back to a previous deployment ID using `UpdateStage`:

```
aws apigateway update-stage --rest-api-id <api-id> --stage-name <stage> \
  --patch-operations op=replace,path=/deploymentId,value=<previous-deployment-id>
```

- Near-instant — no CloudFormation involved, no new deployment created
- Use `GetDeployments` to list available deployment IDs with creation dates
- **This is the recommended emergency rollback path** — faster than CloudFormation rollback and avoids the drift risk (pitfall #4)
- Does not affect Lambda code — only reverts API Gateway configuration (routes, integrations, authorizers, mapping templates). For Lambda code rollback, update the alias to the previous version
- **CloudFormation drift warning**: After manual rollback, the stage's deploymentId diverges from what CloudFormation tracks. The next `sam deploy` or stack update will overwrite your manual rollback with whatever deployment CloudFormation computes. Always follow up with a proper IaC deployment to re-synchronize state

## Blue/Green Zero-Downtime Deployments

Based on the blog https://aws.amazon.com/blogs/compute/zero-downtime-blue-green-deployments-with-amazon-api-gateway/

Use custom domain API mapping to switch traffic between two environments:

### Architecture

1. **Blue stack**: Current production REST API (separate SAM stack)
2. **Green stack**: New version REST API (separate SAM stack)
3. **Custom domain stack**: Route 53 record + ACM certificate + API Gateway custom domain with API mapping

### Workflow

1. Deploy blue stack
2. Deploy custom domain stack pointing to blue
3. Deploy green stack
4. Test green via its direct invoke URL
5. Update custom domain stack to activate green stack
6. Monitor and rollback by re-pointing to blue if needed (see notes on propagation below)
7. **Cleanup**: Delete the **inactive** (old) API stack first (it receives no traffic). Keep the custom domain stack and active API stack running. Only delete the custom domain stack when decommissioning the entire service. **Never delete the custom domain stack while APIs are still serving traffic**, as this removes the production endpoint immediately

### Notes

- **Propagation**: API mapping changes propagate within minutes (no DNS change involved; the custom domain DNS record stays the same). During propagation, some API Gateway hosts serve the old mapping while others serve the new one
- **In-flight request risk**: During the propagation window, clients may receive responses from either blue or green non-deterministically. API Gateway does not maintain request affinity. **Both blue and green must be fully functional and backward-compatible during transition.** Persist all state in the backend (DynamoDB, SQS, etc.); do not rely on in-memory state in Lambda, as a multi-step workflow may start on blue and complete on green. Verify propagation is complete by returning a version identifier from your integration and polling until 100% of responses show the new version
- **Rollback**: Re-pointing to blue has the same propagation delay as the initial switch; it is not instant. Plan for minutes of mixed traffic during rollback
- External custom domain URL never changes
- Each environment is a complete, independent API deployment

## Routing Rules for A/B Testing (REST API Only)

- **REST API only**. HTTP API and WebSocket API do not support routing rules (use base path mappings instead)
- Route specific users by header value to different API/stage combinations on a custom domain without Lambda
- Configure via `AWS::ApiGatewayV2::RoutingRule` resources with conditions (headers, base paths) and actions (target API + stage)
- Combine with stage variables for flexible targeting
- Zero-downtime: Start in "Routing rules then API mappings" mode, existing mappings serve as fallback
- See `references/custom-domains-routing.md` for rule structure, priority, and routing modes

## Infrastructure as Code

For IaC framework selection (SAM vs CDK), project setup, CI/CD pipelines, and environment management, see the [aws-serverless-deployment skill](../../aws-serverless-deployment/).

API Gateway IaC best practices:

- Embed OpenAPI specifications in IaC templates rather than defining APIs with IaC syntax directly
- Export OpenAPI specs from development tools, import into API Gateway
- Use IaC for all production deployments, not console

## Deployment Pitfalls

1. **Changes not taking effect**: Must create a new deployment for REST APIs after any change
2. **CloudFormation logical ID must change**: `AWS::ApiGateway::Deployment` is immutable. If the logical ID stays the same, CloudFormation won't create a new deployment on subsequent stack updates. SAM and CDK auto-generate unique logical IDs by hashing the API definition, but if changes are made outside the API definition (e.g., only Lambda code changed), the hash stays the same and no new deployment is created. **Fix**: Change the API description or any definition field to force a new hash
3. **Deleting old resources causes 5XX during propagation**: If CloudFormation deletes the old Lambda function (or role, alias, etc.) while API Gateway is still propagating the new deployment, hosts still pointing to the old snapshot will return 500. **Fix**: Use a two-phase deployment: (1) deploy the new resources alongside the old ones with `DeletionPolicy: Retain` on resources being replaced, (2) after propagation completes, deploy again to remove the old resources. For Lambda aliases, point the alias to the new version but keep the old version published until propagation is confirmed
4. **CloudFormation rollback creates new snapshot, not the original**: When CloudFormation rolls back, it creates a new Deployment with the current API state; it does not restore the original deployment ID. If there's stack drift (e.g., manual console changes to the API), the rollback snapshots the _drifted_ state, not the last known-good state — the operator believes they rolled back to safety but are running an untested configuration. **Mitigations**: Avoid manual/console changes to production APIs; run `aws cloudformation detect-stack-drift` before relying on rollback; set up drift detection alarms. For fastest recovery, use manual rollback via deployment history (see below) instead of CloudFormation rollback
5. **Limited deployment inspection**: `GetDeployment` returns only ID, description, and date (not the API snapshot). However, you can use `GetExport` on a stage pointing to a deployment to retrieve the full API definition as OpenAPI. To diff two deployments, export from two stages pointing to different deployments and diff the exports. Track changes primarily through IaC version control
6. **`DeploymentStatus: DEPLOYED` is misleading**: HTTP/WebSocket API reports `DEPLOYED` even for deployments never associated with any stage. The status means "snapshot created successfully", not "deployed to a stage"
7. **Stage variable Lambda permissions**: When referencing Lambda via `${stageVariables.functionName}` in an integration URI, you must manually add a resource-based invoke permission — SAM/CDK do NOT auto-generate these for stage-variable references (only for direct ARN references). Without it, every invocation returns a 500 "Internal server error" with no hint about the cause. Add permission with `aws lambda add-permission --function-name <function> --statement-id apigw-<stage> --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:<region>:<account>:<api-id>/<stage>/*"`. **This must be repeated for every new stage and every new Lambda function referenced by stage variables**
8. **Circular dependency**: Never reference `ServerlessRestApi` or `ServerlessHttpApi` in Lambda environment variables, `Outputs`, IAM policy resources, or other resource properties — all of these create circular dependencies. For request-handling Lambda functions, derive API URL at runtime from `event["requestContext"]`. For non-request contexts (callback URLs, webhook registrations), use SSM Parameter Store — write the API URL via a post-deploy script, or use an explicit `AWS::Serverless::Api` resource which breaks the circular dependency
9. **YAML duplicate keys**: Automated template patching can silently introduce duplicate keys. Validate: `sam validate` or `python3 -c "import yaml; yaml.safe_load(open('template.yaml'))"`
10. **Management API rate limit**: Management API calls share an aggregate rate limit of 10 rps with 40-burst across all API Gateway operations in the account. Individual operations have stricter limits. `CreateDeployment` is limited to **1 request every 5 seconds** (0.2 rps, fixed, not adjustable). CI/CD pipelines deploying many APIs in parallel will be throttled. CloudFormation reports a generic error, not a throttling message. Stagger parallel deployments or use a single pipeline with sequential stages
11. **Cache flush on redeployment**: Creating a new deployment to a stage with caching enabled flushes the entire cache, causing a temporary spike in backend load ("thundering herd"). Mitigations: (a) ensure backend auto-scaling can handle full uncached load before deploying, (b) script synthetic requests to cached endpoints after deployment to pre-warm the cache, (c) use canary deployments to limit the blast radius of cache flush, (d) backends with cold-start issues (Lambda with VPC, containers scaling from zero) compound the thundering herd — use provisioned concurrency on critical paths during deployment windows. See `references/performance-scaling.md`
