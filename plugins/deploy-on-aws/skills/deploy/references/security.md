# Security Defaults

Security configurations applied by default. Override only when explicitly requested.

## Philosophy

**Secure by default, right-sized by environment.** Dev environments allow more permissive
access for debugging. Production environments enforce strict boundaries.

## Secure-by-Default Checklist

Apply these patterns automatically when generating IaC:

- [ ] **Private S3 buckets** - Block all public access unless explicitly serving static content
- [ ] **Encryption at rest** - Enable for all storage (S3, RDS, EBS, Secrets Manager)
- [ ] **HTTPS enforcement** - TLS 1.2+ with automatic HTTP→HTTPS redirect
- [ ] **Origin Access Control** - CloudFront accesses S3 via AWS internal network, not public URLs
- [ ] **IAM least privilege** - Minimal required permissions per service, no wildcards
- [ ] **Security scanning** - Detect exposed secrets before deployment
- [ ] **Quality gates** - Run available tests and static analysis before deploy

## Encryption

| Component       | Default (Dev)               | Default (Prod)             | Override Trigger |
| --------------- | --------------------------- | -------------------------- | ---------------- |
| S3 buckets      | SSE-S3 (AES-256)            | SSE-KMS (customer-managed) | "no encryption"  |
| RDS/Aurora      | Encrypted (AWS-managed key) | Encrypted (CMK)            | -                |
| DocumentDB      | Encrypted (AWS-managed key) | Encrypted (CMK)            | -                |
| EBS volumes     | Encrypted                   | Encrypted                  | -                |
| ALB             | TLS 1.2+ only               | TLS 1.2+ only              | -                |
| Secrets Manager | AWS-managed key             | CMK                        | -                |
| CloudFront      | TLS 1.2+                    | TLS 1.2+                   | -                |

### Why SSE-S3 for dev, SSE-KMS for prod

SSE-S3 is zero-config and free. Production benefits from CMK for audit trails,
key rotation control, and cross-account access patterns.

## S3 Security

| Setting             | Default                      |
| ------------------- | ---------------------------- |
| Block Public Access | **Enabled** (all 4 settings) |
| Bucket Policy       | Deny by default              |
| Object Ownership    | Bucket owner enforced        |
| Versioning          | Enabled for production       |
| Access Logging      | Enabled for production       |

### CloudFront + S3 Pattern

When serving static content via CloudFront:

- S3 bucket remains **private** (no public access)
- Use **Origin Access Control (OAC)** - CloudFront accesses S3 via internal AWS network
- Do NOT use legacy Origin Access Identity (OAI)

## VPC Placement

| Component     | Default (Dev)                    | Default (Prod)                   |
| ------------- | -------------------------------- | -------------------------------- |
| Fargate tasks | Private subnet + NAT Gateway     | Private subnet + NAT Gateway     |
| ALB           | Public subnet                    | Public subnet                    |
| RDS/Aurora    | Private subnet (no public IP)    | Private subnet (no public IP)    |
| DocumentDB    | Private subnet (no public IP)    | Private subnet (no public IP)    |
| Lambda        | VPC-attached if DB access needed | VPC-attached if DB access needed |

### Why private subnets for compute

Public IPs on compute resources invite direct attack. Route outbound traffic
through NAT Gateway. ALB is the only public-facing component.

### Dev simplification

For dev, a single-AZ VPC with 1 public + 1 private subnet is sufficient.
Use `awsknowledge` topic `vpc_patterns` for multi-AZ production layouts.

## IAM

| Pattern              | Default                                          |
| -------------------- | ------------------------------------------------ |
| Task/function roles  | Least privilege (only resources explicitly used) |
| Service-linked roles | Use AWS-managed where available                  |
| Cross-service access | Via IAM roles, never access keys                 |
| Admin access         | Not created (user manages separately)            |

### Principle: Explicit grants only

Never use `*` for resources or actions unless unavoidable (e.g., S3 bucket
contents require `s3:GetObject` on `bucket/*`). Enumerate specific ARNs.
Use conditions where possible.

Consult `awsiac` MCP for IAM policy patterns by service.

## Security Groups

| Component    | Default Inbound              | Default Outbound   |
| ------------ | ---------------------------- | ------------------ |
| ALB          | 443 from 0.0.0.0/0           | Fargate SG only    |
| Fargate      | ALB SG only (on app port)    | 443 (HTTPS), DB SG |
| RDS/Aurora   | Fargate SG only (on DB port) | None               |
| DocumentDB   | Fargate SG only (port 27017) | None               |
| Lambda (VPC) | None                         | 443, DB SG         |

### Why deny-by-default

Start with no access, add only what's needed. Outbound 443 allows AWS API
calls and package downloads. Lock down further for compliance if needed.

## Secrets Management

| Secret Type                | Default Storage                 | Access Pattern            |
| -------------------------- | ------------------------------- | ------------------------- |
| Database credentials       | Secrets Manager                 | IAM role + GetSecretValue |
| API keys                   | Secrets Manager                 | IAM role + GetSecretValue |
| Config values (non-secret) | Parameter Store                 | IAM role + GetParameter   |
| Environment-specific       | Secrets Manager with env prefix | `/app/{env}/secret-name`  |

### Why Secrets Manager over Parameter Store for secrets

Secrets Manager provides automatic rotation, cross-account sharing, and
audit logging. Parameter Store SecureString works but lacks rotation.

**Always inject secrets at runtime, never bake into images.**

## Pre-Deployment Security Checks

### Secret Detection

Before deployment, scan for exposed secrets:

- Check for hardcoded credentials, API keys, tokens
- Use git-secrets, truffleHog, or detect-secrets
- Fail deployment if secrets detected in codebase

### IaC Security Scanning

Validate generated IaC before deployment:

| Tool        | Purpose                                                      |
| ----------- | ------------------------------------------------------------ |
| **cfn-nag** | CloudFormation security linting (AWS-native)                 |
| **checkov** | Multi-framework IaC scanner (CDK, CloudFormation, Terraform) |
| **cdk-nag** | CDK-specific security checks via Aspects                     |
| **tfsec**   | Terraform security scanner                                   |

Recommend running `checkov` or `cfn-nag` on generated templates before `cdk deploy`.

### Quality Gates

Before deployment, run available checks:

1. Unit tests (if test suite exists)
2. Static code analysis (linters, type checkers)
3. IaC security scan
4. Secret detection scan

## Logging & Monitoring

| Component       | Default (Dev)          | Default (Prod)             |
| --------------- | ---------------------- | -------------------------- |
| CloudTrail      | Account-level (shared) | Account-level (shared)     |
| VPC Flow Logs   | Disabled               | Enabled (S3 destination)   |
| ALB Access Logs | Disabled               | Enabled (S3 destination)   |
| Container logs  | CloudWatch Logs        | CloudWatch Logs            |
| RDS/Aurora logs | Error log only         | Error + slow query + audit |
| DocumentDB logs | Profiler (slow ops)    | Profiler + audit           |
| S3 Access Logs  | Disabled               | Enabled                    |

### Why minimal logging in dev

Logging has cost. Dev environments rarely need audit trails. Enable
VPC Flow Logs and ALB logs for production debugging and compliance.

## Production Hardening Checklist

When user requests "production" or "prod", additionally enable:

- [ ] Multi-AZ for all stateful services
- [ ] VPC Flow Logs
- [ ] ALB Access Logs
- [ ] S3 Access Logs
- [ ] RDS Performance Insights
- [ ] DocumentDB profiler + audit logs exported to CloudWatch Logs
- [ ] AWS WAF on ALB (if public-facing web app)
- [ ] GuardDuty (recommend, don't auto-enable)
- [ ] Run `checkov` or `cfn-nag` before deployment

## MCP References

- `awsknowledge` topics: `vpc_patterns`, `iam_best_practices`, `security`
- `awsiac` for CDK security constructs (L2 constructs apply many defaults)
