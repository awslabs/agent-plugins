# IAM Role Templates by Persona

Pre-built role templates for common team personas. Each template includes a trust policy and identity-based policy. Adapt resource ARNs, regions, and account IDs to your environment.

---

## Developer Role

For application developers who need to build and deploy in non-production accounts. Read/write access to application services, no IAM or networking modifications.

### Trust Policy (Identity Center / SSO)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalTag/Department": "Engineering"
      }
    }
  }]
}
```

### Identity Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ComputeAndStorage",
      "Effect": "Allow",
      "Action": [
        "lambda:*",
        "s3:*",
        "dynamodb:*",
        "sqs:*",
        "sns:*",
        "logs:*",
        "cloudwatch:*",
        "xray:*",
        "apigateway:*",
        "ssm:GetParameter*",
        "ssm:DescribeParameters",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    },
    {
      "Sid": "ReadOnlyInfra",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ecs:Describe*",
        "ecs:List*",
        "eks:Describe*",
        "eks:List*",
        "rds:Describe*",
        "elasticache:Describe*",
        "cloudformation:Describe*",
        "cloudformation:List*",
        "cloudformation:GetTemplate"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyDangerous",
      "Effect": "Deny",
      "Action": [
        "iam:*",
        "organizations:*",
        "account:*",
        "ec2:*Vpc*",
        "ec2:*Subnet*",
        "ec2:*SecurityGroup*",
        "ec2:*Route*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Data Engineer Role

For data engineers who need to build and manage data pipelines, ETL jobs, and analytics infrastructure.

### Trust Policy (Identity Center / SSO)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalTag/Department": "Data"
      }
    }
  }]
}
```

### Identity Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DataServices",
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "glue:*",
        "athena:*",
        "redshift:*",
        "redshift-data:*",
        "redshift-serverless:*",
        "kinesis:*",
        "firehose:*",
        "emr:*",
        "emr-serverless:*",
        "lakeformation:*",
        "databrew:*",
        "quicksight:*",
        "logs:*",
        "cloudwatch:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    },
    {
      "Sid": "DatabaseRead",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:ListTagsForResource",
        "dynamodb:*",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleToDataServices",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::*:role/GlueServiceRole*",
        "arn:aws:iam::*:role/EMRServiceRole*",
        "arn:aws:iam::*:role/DataPipeline*"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "glue.amazonaws.com",
            "elasticmapreduce.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DenyDangerous",
      "Effect": "Deny",
      "Action": [
        "iam:Create*",
        "iam:Delete*",
        "iam:Put*",
        "iam:Attach*",
        "iam:Detach*",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## On-Call / Operations Role

For SREs and operations engineers during incident response. Broad read access with targeted write access for remediation.

### Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "Bool": {
        "aws:MultiFactorAuthPresent": "true"
      }
    }
  }]
}
```

### Identity Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BroadReadAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ecs:Describe*",
        "ecs:List*",
        "eks:Describe*",
        "eks:List*",
        "lambda:Get*",
        "lambda:List*",
        "rds:Describe*",
        "elasticache:Describe*",
        "s3:Get*",
        "s3:List*",
        "sqs:Get*",
        "sqs:List*",
        "sns:Get*",
        "sns:List*",
        "logs:*",
        "cloudwatch:*",
        "xray:*",
        "health:*",
        "support:*",
        "ssm:Describe*",
        "ssm:Get*",
        "ssm:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IncidentRemediation",
      "Effect": "Allow",
      "Action": [
        "ec2:RebootInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ecs:UpdateService",
        "ecs:StopTask",
        "lambda:UpdateFunctionConfiguration",
        "rds:RebootDBInstance",
        "rds:FailoverDBCluster",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:UpdateAutoScalingGroup",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:RegisterTargets",
        "ssm:StartSession",
        "ssm:SendCommand"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyDangerous",
      "Effect": "Deny",
      "Action": [
        "ec2:TerminateInstances",
        "rds:DeleteDBInstance",
        "rds:DeleteDBCluster",
        "s3:DeleteBucket",
        "iam:*",
        "organizations:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## CI/CD Pipeline Role

For automated deployment pipelines (CodePipeline, GitHub Actions, GitLab CI). Scoped to deploy application resources only, with `iam:PassRole` restricted to pre-approved roles.

### Trust Policy (GitHub Actions OIDC)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
      }
    }
  }]
}
```

### Identity Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DeployApplicationResources",
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "lambda:*",
        "s3:*",
        "dynamodb:*",
        "sqs:*",
        "sns:*",
        "apigateway:*",
        "ecs:*",
        "ecr:*",
        "logs:*",
        "events:*",
        "states:*",
        "ssm:GetParameter*",
        "ssm:PutParameter",
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    },
    {
      "Sid": "PassRoleToServices",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::*:role/app-*",
        "arn:aws:iam::*:role/lambda-*",
        "arn:aws:iam::*:role/ecs-task-*"
      ],
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "lambda.amazonaws.com",
            "ecs-tasks.amazonaws.com",
            "states.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "DenyDangerous",
      "Effect": "Deny",
      "Action": [
        "iam:Create*",
        "iam:Delete*",
        "iam:Put*",
        "iam:Attach*",
        "iam:Detach*",
        "ec2:*Vpc*",
        "ec2:*Subnet*",
        "ec2:*SecurityGroup*",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Read-Only Auditor Role

For compliance auditors and security reviewers. Full read access across all services, no write access to anything.

### Trust Policy (Cross-Account from Security Account)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::999888777666:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "audit-external-id"
      },
      "Bool": {
        "aws:MultiFactorAuthPresent": "true"
      }
    }
  }]
}
```

### Identity Policy

Use the AWS managed `ReadOnlyAccess` policy as a base, then add explicit denies for sensitive data access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSecurityAuditRead",
      "Effect": "Allow",
      "Action": [
        "access-analyzer:*",
        "cloudtrail:LookupEvents",
        "cloudtrail:GetTrail*",
        "cloudtrail:Describe*",
        "cloudtrail:List*",
        "config:*",
        "guardduty:Get*",
        "guardduty:List*",
        "inspector2:*",
        "securityhub:*",
        "trustedadvisor:*",
        "iam:Get*",
        "iam:List*",
        "iam:GenerateCredentialReport",
        "iam:GetCredentialReport",
        "iam:GenerateServiceLastAccessedDetails",
        "iam:GetServiceLastAccessedDetails",
        "organizations:Describe*",
        "organizations:List*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyDataAccess",
      "Effect": "Deny",
      "Action": [
        "s3:GetObject",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "secretsmanager:GetSecretValue",
        "ssm:GetParameter",
        "rds-data:ExecuteStatement"
      ],
      "Resource": "*"
    }
  ]
}
```

**Note**: Pair this with the AWS managed `ReadOnlyAccess` policy for broad Describe/List/Get coverage. The explicit Deny on data-level reads prevents auditors from accessing application data while still seeing configuration and metadata.

---

## Permission Boundary for All Custom Roles

Apply this boundary to every role template above to prevent privilege escalation when developers or pipelines can create roles.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowMostActions",
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    },
    {
      "Sid": "DenyEscalationPaths",
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "iam:CreateLoginProfile",
        "iam:UpdateLoginProfile",
        "iam:DeleteRolePermissionsBoundary",
        "iam:SetDefaultPolicyVersion",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```
