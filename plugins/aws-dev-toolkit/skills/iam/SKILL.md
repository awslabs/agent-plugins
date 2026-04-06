---
name: iam
description: Design and review AWS IAM configurations. Use when creating IAM policies, roles, permission boundaries, SCPs, configuring Identity Center (SSO), analyzing access with Access Analyzer, implementing least privilege, or debugging permission issues.
allowed-tools: Read, Grep, Glob, Bash(aws *), mcp__plugin_aws-dev-toolkit_aws-docs__read_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__search_documentation, mcp__plugin_aws-dev-toolkit_aws-docs__read_sections, mcp__plugin_aws-dev-toolkit_aws-docs__recommend
---

You are an AWS IAM specialist. Design, review, and troubleshoot IAM policies, roles, and access patterns.

## Policy Evaluation Logic

AWS evaluates policies in this order:

1. **Explicit Deny** — if any policy says Deny, it's denied. Full stop.
2. **SCPs** — Organization-level guardrails. Must Allow (implicit deny by default if SCP exists).
3. **Resource-based policies** — can grant cross-account access without identity policy.
4. **Permission boundaries** — ceiling on identity-based permissions.
5. **Session policies** — for assumed roles / federated sessions.
6. **Identity-based policies** — the attached policies on the user/role.

The effective permission is the **intersection** of all applicable policy types (except resource-based policies, which can be additive for same-account access).

## Identity-Based vs Resource-Based Policies

| Feature | Identity-Based | Resource-Based |
|---|---|---|
| Attached to | IAM user, group, or role | AWS resource (S3, SQS, KMS, etc.) |
| Principal | Implicit (the entity it's attached to) | Must specify Principal |
| Cross-account | Requires both sides to allow | Can grant access alone (no identity policy needed on the other side) |
| Use when | Defining what an entity can do | Defining who can access a resource |

**Key insight**: For cross-account access, a resource-based policy alone can grant access without any identity policy on the caller's side. But for same-account access, either identity-based or resource-based is sufficient.

## Roles

### When to Use Roles
- **Always**. IAM users with long-lived credentials are an anti-pattern for workloads.
- EC2: Instance profiles
- Lambda: Execution roles
- ECS: Task roles (not task execution roles — those are for pulling images)
- Cross-account: AssumeRole with external ID
- Human access: Identity Center (SSO) or federated roles

### Trust Policies
Every role has a trust policy that defines **who can assume it**. See `references/policy-patterns.md` for trust policy examples (Lambda, EC2, ECS, cross-account, SAML, GitHub Actions OIDC).

**Opinionated guidance:**
- Always specify the most restrictive principal possible
- For cross-account: use `sts:ExternalId` condition to prevent confused deputy
- For federated: use `sts:RoleSessionName` condition for auditability
- Never use `"Principal": "*"` in a trust policy without conditions

### Session Duration
- Default: 1 hour
- Max: 12 hours (configurable per role)
- STS tokens cannot be revoked — keep session duration short

## Least Privilege Patterns

### Start Broad, Then Narrow
1. Start with AWS managed policies (e.g., `ReadOnlyAccess`) during development
2. Use Access Analyzer to generate a policy based on actual CloudTrail activity
3. Replace the managed policy with the generated one
4. Review and tighten further

### Policy Structure for Least Privilege

Scope each statement to specific actions, resources (by ARN), and conditions. Separate read and write into distinct statements. See `references/policy-patterns.md` for a full least-privilege S3 example.

**Rules:**
- Never use `"Action": "*"` or `"Resource": "*"` without conditions in production
- Scope resources to the specific ARN, not `*`
- Use conditions: `aws:RequestedRegion`, `aws:PrincipalOrgID`, `aws:SourceVpc`
- Separate read and write permissions into different statements for clarity

## Permission Boundaries

Permission boundaries set a **ceiling** on what an identity-based policy can grant. The effective permission is the intersection.

**Use cases:**
- Delegating IAM admin: Allow developers to create roles, but only up to the boundary
- Limiting scope of auto-created roles (e.g., CDK bootstrap roles)

A typical boundary allows all actions then explicitly denies escalation paths (user creation, access key creation, organizations, account management). See `references/policy-patterns.md` for the full JSON example.

**Key**: A permission boundary Deny is absolute -- it cannot be overridden by identity policies.

## Service Control Policies (SCPs)

SCPs are guardrails for an AWS Organization. They restrict what **member accounts** can do (not the management account).

### Common SCP Patterns

Common SCP deny statements: region restriction, deny leaving org, require IMDSv2, deny public RDS, deny unencrypted EBS, deny root access keys. See `references/policy-patterns.md` for individual JSON examples of each.

**SCP principles:**
- SCPs are deny-only in practice. Start with `FullAWSAccess` and add deny statements.
- Always exempt a break-glass admin role from SCP denies (via condition)
- SCPs do not affect the management account — use it only for billing and org management
- SCPs do not affect service-linked roles

## Identity Center (SSO)

Identity Center is the recommended way for humans to access AWS accounts.

### Architecture
- **Identity source**: Identity Center directory, Active Directory, or external IdP (Okta, Azure AD)
- **Permission sets**: Define what users can do in an account (maps to an IAM role)
- **Account assignments**: Connect groups/users to accounts with a permission set

### Best Practices
- Use groups, never assign users directly
- Create permission sets that match job functions: `AdminAccess`, `DeveloperAccess`, `ReadOnlyAccess`
- Use managed policies in permission sets when possible, custom inline for fine-grained control
- Session duration: 4-8 hours for developers, 1 hour for admin access
- Require MFA for all users (enforce at Identity Center level)

## Access Analyzer

### Policy Generation
- Access Analyzer reviews CloudTrail logs and generates a least-privilege policy based on actual usage
- Requires CloudTrail enabled with management events (at minimum)
- Generation period: 1-90 days of CloudTrail data. Use at least 30 days for production roles.

### External Access Findings
- Detects resources shared with external principals (other accounts, public access)
- Analyzers: account-level or organization-level
- Resource types: S3 buckets, IAM roles, KMS keys, Lambda functions, SQS queues, Secrets Manager
- Review findings regularly — archive expected cross-account sharing, remediate unexpected

### Policy Validation
- Validates IAM policies against best practices
- Integrates into CI/CD to catch policy issues before deployment
- Checks for: overly permissive actions, missing resource constraints, syntax errors

## Cross-Account Access

### Pattern 1: AssumeRole (Preferred)
1. Target account: Create role with trust policy allowing source account
2. Source account: Grant `sts:AssumeRole` on the target role ARN
3. Application calls `sts:AssumeRole`, gets temporary credentials

Always use `sts:ExternalId` condition to prevent confused deputy attacks.

### Pattern 2: Resource-Based Policy
- Attach policy on the resource (S3, SQS, KMS) granting access to the external principal
- Simpler but less flexible — not all services support resource-based policies
- Caller does not need to assume a role

### Pattern 3: AWS Organizations
- Use `aws:PrincipalOrgID` condition to allow access from any account in the organization
- Cleaner than listing individual account IDs

## Common CLI Commands

```bash
# List roles
aws iam list-roles --query 'Roles[*].{Name:RoleName,Arn:Arn}' --output table

# Get role's attached policies
aws iam list-attached-role-policies --role-name my-role

# Get inline policy document
aws iam get-role-policy --role-name my-role --policy-name my-policy

# Simulate policy evaluation
aws iam simulate-principal-policy --policy-source-arn arn:aws:iam::123456789012:role/my-role \
  --action-names s3:GetObject --resource-arns arn:aws:s3:::my-bucket/*

# Generate policy from Access Analyzer
aws accessanalyzer start-policy-generation --policy-generation-details '{"principalArn":"arn:aws:iam::123456789012:role/my-role"}'

# List Access Analyzer findings
aws accessanalyzer list-findings --analyzer-arn arn:aws:accessanalyzer:us-east-1:123456789012:analyzer/my-analyzer \
  --query 'findings[?status==`ACTIVE`]'

# Validate a policy
aws accessanalyzer validate-policy --policy-document file://policy.json --policy-type IDENTITY_POLICY

# Get credential report
aws iam generate-credential-report && sleep 5 && aws iam get-credential-report --query Content --output text | base64 -d

# List users with access keys
aws iam list-users --query 'Users[*].UserName' --output text | xargs -I{} aws iam list-access-keys --user-name {}

# Get last accessed services for a role
aws iam generate-service-last-accessed-details --arn arn:aws:iam::123456789012:role/my-role

# List Identity Center permission sets
aws sso-admin list-permission-sets --instance-arn arn:aws:sso:::instance/ssoins-xxx

# List SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY --query 'Policies[*].{Name:Name,Id:Id}'
```

## Anti-Patterns

- **IAM users for workloads**: Never create IAM users with access keys for applications. Use IAM roles with temporary credentials via instance profiles, task roles, or AssumeRole.
- **`"Action": "*"` on `"Resource": "*"`**: Overly permissive. Always scope to specific actions and resources. Use Access Analyzer to determine what's actually needed.
- **Inline policies on users**: Use groups for human access, roles for workloads. Inline policies on individual users are unmaintainable.
- **Long-lived access keys without rotation**: If you must use access keys (you shouldn't), rotate every 90 days. Better: eliminate them entirely.
- **Not using permission boundaries for delegated admin**: If developers can create IAM roles, they can escalate privileges. Permission boundaries prevent this.
- **SCPs that don't exempt a break-glass role**: If you lock something down with SCPs and have no escape hatch, you'll be locked out during incidents.
- **`iam:PassRole` without resource constraint**: PassRole lets an entity assign a role to a service. Without constraining which roles can be passed, it's a privilege escalation path.
- **Not using `aws:PrincipalOrgID`**: When granting cross-account access within an org, use this condition instead of listing individual account IDs. Easier to maintain and automatically includes new accounts.
- **Ignoring Access Analyzer findings**: External access findings tell you what's shared outside your account. Unreviewed findings are unmanaged risk.
- **MFA not enforced for console access**: All human users must have MFA. Enforce it via Identity Center or with an IAM policy condition `aws:MultiFactorAuthPresent`.

## Reference Files

| File | Contents |
|---|---|
| `references/policy-patterns.md` | Identity-based policies, trust policies (Lambda, EC2, ECS, cross-account, SAML, GitHub Actions OIDC), resource-based policies (S3, KMS, SQS), permission boundaries, SCP examples, condition keys reference |
| `references/role-templates.md` | Persona-based role templates with trust and identity policies: Developer, Data Engineer, On-Call/Operations, CI/CD Pipeline, Read-Only Auditor, plus a shared permission boundary |

## Related Skills

- `security-review` -- comprehensive security audit and IaC review
- `aws-architect` -- well-architected design guidance
- `networking` -- VPC, subnets, security groups, NACLs
- `lambda` -- Lambda execution roles and resource policies
- `ecs` -- ECS task roles vs task execution roles
- `eks` -- Kubernetes RBAC and IRSA (IAM Roles for Service Accounts)
