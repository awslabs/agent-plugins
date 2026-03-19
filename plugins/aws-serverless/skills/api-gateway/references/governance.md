# API Governance

This document focuses on governance of REST APIs (API Gateway V1), as governance and compliance controls are primarily a concern in enterprise environments where REST APIs are the typical choice due to their full API management capabilities (usage plans, WAF, resource policies, request validation).

## Governance Framework

Four types of security controls:

1. **Preventative**: Prevent unauthorized changes before they occur (IAM policies, SCPs)
2. **Proactive**: Prevent noncompliant resources before deployment (CloudFormation Hooks, Guard rules)
3. **Detective**: React to configuration changes after they happen (AWS Config rules, EventBridge)
4. **Responsive**: Remediate adverse events (automated remediation via Lambda)

## Governance Tools

### Preventative Controls

- **IAM policies and permission boundaries**: Fine-grained API Gateway control plane access
- **Service Control Policies (SCPs)**: Organization-wide guardrails using API Gateway condition keys. Policy examples below show statement bodies only. SCPs require a complete policy document with `Version`, `Statement` array, and `"Effect"`, while SCP statements implicitly apply to all principals (`"Principal": "*"` is not needed in SCPs but is required in resource-based policies)
- **Over 20 IAM condition keys** available for API Gateway governance, split into two categories:
  - `apigateway:Request/*`: Evaluates the new values being set in the request
  - `apigateway:Resource/*`: Evaluates the current values on the existing resource being acted upon
  - Both are preventative, evaluated at IAM authorization time before the action occurs
- Key condition keys: `apigateway:Request/EndpointType`, `apigateway:Request/SecurityPolicy`, `apigateway:Resource/ApiKeyRequired`, `apigateway:Request/AuthorizationType`, `apigateway:Request/AccessLoggingDestination`, `apigateway:Request/MtlsTrustStoreUri`

### Proactive Controls

- **CloudFormation Hooks**: Evaluate resource configuration before deployment. Noncompliant resources block deploy or warn
- **AWS Control Tower**: Preconfigured proactive controls for API Gateway
- **CloudFormation Guard**: Open-source policy-as-code evaluation tool with declarative DSL. Managed rule set available for API Gateway
- **Limitation**: CloudFormation-based proactive controls may not work with non-CloudFormation IaC tools (Terraform, Pulumi)

### Detective Controls

- **AWS Config**: Managed rules + custom rules (Guard DSL or Lambda). Key managed rules:
  - `api-gw-xray-enabled`
  - `api-gw-associated-with-waf`
  - `api-gw-ssl-enabled`
  - `api-gw-execution-logging-enabled`
  - `api-gw-endpoint-type-check`
- **Amazon EventBridge**: React to API Gateway events in real-time with Lambda
- **AWS Security Hub**: Findings trigger EventBridge events for automated remediation
- **AWS Trusted Advisor**: Service-level checks for optimization, performance, security

## Enforcing Observability

### Require X-Ray Tracing

- Preventative: N/A (no IAM/SCP conditions)
- Proactive: Custom CloudFormation Hook or Guard rule
- Detective: AWS Config rule `api-gw-xray-enabled`

### Require Access Logging

- Preventative: SCP using `apigateway:Request/AccessLoggingDestination` and `apigateway:Request/AccessLoggingFormat`

```json
{
  "Effect": "Deny",
  "Action": ["apigateway:PATCH", "apigateway:POST", "apigateway:PUT"],
  "Resource": ["arn:aws:apigateway:*::/restapis/*/stages/*"],
  "Condition": { "StringLikeIfExists": { "apigateway:Request/AccessLoggingDestination": "" } }
}
```

- **Side effect**: `StringLikeIfExists` means any stage update that does not explicitly include `AccessLoggingDestination` (e.g., updating cache settings or stage variables) will also be denied. This is intentionally strict; use detective controls instead if this is too restrictive
- Detective: AWS Config custom Guard rule: `configuration.accessLogSettings.destinationArn is_string`

### Require Execution Logging

- Preventative: N/A (no IAM/SCP conditions)
- Proactive: Custom CloudFormation Hook or Guard rule
- Detective: AWS Config rule `api-gw-execution-logging-enabled`

**Caveat**: Preventative/proactive controls may block first deployment via AWS Console (Console does not allow specifying these settings on new stage creation). IaC/CLI works fine.

## Enforcing Security

### Require WAF

- Preventative: N/A
- Proactive: Custom CloudFormation Hook
- Detective: AWS Config rule `api-gw-associated-with-waf`

### Require TLS 1.2+

- Preventative: SCP denying `apigateway:Request/SecurityPolicy` value `TLS_1_0`
- Detective: EventBridge rule or AWS Config custom rule

### Require mTLS

- Preventative: SCP requiring `apigateway:Request/MtlsTrustStoreUri` is present
- Detective: EventBridge rule or AWS Config custom rule

### Require Specific Authorizer Type

- Preventative: SCP using `apigateway:Request/AuthorizationType` (valid values: `NONE`, `AWS_IAM`, `CUSTOM`, `COGNITO_USER_POOLS`)
- Use `apigateway:Request/AuthorizerUri` to enforce a specific Lambda authorizer. Note: the URI is the full invocation path (`arn:aws:apigateway:REGION:lambda:path/2015-03-31/functions/FUNCTION_ARN/invocations`), not just the Lambda ARN. Use `StringLike` with wildcards for flexibility

### Require API Key

- Preventative: SCP with `apigateway:Resource/ApiKeyRequired` or `apigateway:Request/ApiKeyRequired`
- Detective: EventBridge rule or AWS Config custom rule

### Require Request Validation

- Preventative: N/A
- Proactive: Custom CloudFormation Hook
- Detective: EventBridge rule or AWS Config custom rule

### Restrict VPCs in Private API Resource Policy

- Preventative: N/A
- Proactive: Custom CloudFormation Hook
- Detective: EventBridge rule or AWS Config custom rule

### Audit Resource Policies for Overly Broad Access

- Preventative: N/A (resource policy content is not exposed via IAM condition keys)
- Proactive: Custom CloudFormation Hook to reject policies with `"Principal": "*"` without `Condition` constraints
- Detective: AWS Config custom rule to flag resource policies granting unrestricted access (e.g., missing `aws:SourceVpce` or `aws:SourceIp` conditions on private APIs)

## Enforcing Management Control

### Freeze API Modifications by Tag

```json
{
  "Effect": "Deny",
  "Action": ["apigateway:DELETE", "apigateway:PATCH", "apigateway:POST", "apigateway:PUT"],
  "Resource": "*",
  "Condition": { "StringEquals": { "aws:ResourceTag/EnvironmentState": "frozen" } }
}
```

- To lift freeze: temporarily disable the IAM policy. Note: the `frozen` tag itself cannot be removed while the policy is active (tag operations use `apigateway:PUT` which is denied)
- Alternative: Freeze deployments by stage name using `apigateway:Request/StageName`

### Prevent Custom Domains in Child Accounts

```json
{
  "Effect": "Deny",
  "Action": ["apigateway:DELETE", "apigateway:PUT", "apigateway:PATCH", "apigateway:POST"],
  "Resource": ["arn:aws:apigateway:*::/domainnames", "arn:aws:apigateway:*::/domainnames/*"]
}
```

### Prevent Public APIs in Non-Central Accounts

- SCP denying `EDGE` or `REGIONAL` endpoint types in child accounts
- Detective: AWS Config rule `api-gw-endpoint-type-check`

### Require Tags

```json
{
  "Effect": "Deny",
  "Action": ["apigateway:POST"],
  "Resource": ["arn:aws:apigateway:*::/restapis"],
  "Condition": { "Null": { "aws:RequestTag/owner": "true" } }
}
```

- Use `aws:RequestTag` for enforcing tags at creation time; use `aws:ResourceTag` for enforcing tags on updates to existing resources
- REST API child resources of RestApi, DomainName, UsagePlan inherit parent tags

### Require Documentation

- Proactive: Custom CloudFormation Hook
- Detective: AWS Config custom Guard rule: `configuration.documentationVersion is_string`

### Require Compression

- Proactive: Custom CloudFormation Hook
- Detective: AWS Config custom Guard rule: `configuration.minimumCompressionSize >= 0`

## Management Access Control

### API Management (Control Plane)

- IAM policy scoped to specific API ARN: `arn:aws:apigateway:region::/restapis/apiId/*`
- **Tip**: Use `arn:aws:apigateway:region::/restapis/??????????/*` (10 question marks) to match any API ID. REST API IDs are observed to be exactly 10 alphanumeric characters. This scopes permissions to REST APIs without hardcoding specific IDs. Note: this length is not formally documented by AWS, but the risk of it changing is low given the installed base
- This does NOT grant access to: custom domains, client certificates, VPC links, API keys, usage plans
- IAM principals denied by default

### Observability Access

- Execution logs: IAM for CloudWatch Logs; use data protection policies to mask sensitive data
- Access logs: IAM for CloudWatch Logs or Firehose; control access at both Firehose AND destination
- Metrics: IAM for CloudWatch
- Traces: IAM for X-Ray
- CloudTrail: IAM for CloudTrail
- Sensitive data protection: CloudWatch Logs data protection policies, Amazon Macie for S3-stored logs

## API Lifecycle

**Design** -> **Build** -> **Manage** -> **Adoption**

1. **Plan**: Protocol selection, endpoint type, topology, standards
2. **Develop/Test**: IaC, OpenAPI specs, integration testing
3. **Secure**: Auth, WAF, mTLS, resource policies
4. **Deploy/Publish**: CI/CD, canary, blue/green
5. **Scale**: Quotas, caching, cell-based architecture
6. **Monitor**: Metrics, logs, traces, dashboards
7. **Insights**: CloudWatch Logs Insights, Contributor Insights, QuickSight
8. **Monetize**: Usage plans, API segmentation, AWS Marketplace, AWS Data Exchange
9. **Discover**: API Gateway Portal, Backstage, partner portals (Readme, Apiable, SmartBear)

## Audit

- **CloudTrail**: All REST API management calls captured as events
- **AWS Config**: Record configuration changes, detect drift, enforce compliance
- **EventBridge**: React to changes in real-time
- Example EventBridge rule for stage updates:

```json
{
  "detail": {
    "eventSource": ["apigateway.amazonaws.com"],
    "requestParameters": { "restApiId": ["abcd123456"], "stageName": ["prod"] },
    "eventName": ["UpdateStage"],
    "errorCode": [{ "exists": false }]
  }
}
```
