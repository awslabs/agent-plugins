# IAM Policy Patterns Reference

Detailed policy examples for common IAM scenarios. See the parent `SKILL.md` for evaluation logic and guidance.

---

## Identity-Based Policy: Least Privilege S3 Access

Scoped to a specific bucket prefix and region. Separate read/write into distinct statements for clarity.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3Read",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/data/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    },
    {
      "Sid": "AllowS3Write",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::my-bucket/data/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "us-east-1"
        }
      }
    }
  ]
}
```

---

## Trust Policies

### Lambda Execution Role Trust

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

### EC2 Instance Profile Trust

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

### ECS Task Role Trust

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ecs-tasks.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

### Cross-Account AssumeRole Trust (with External ID)

Prevents the confused deputy problem. Always use `sts:ExternalId` for cross-account access.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::111122223333:root"},
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": {
        "sts:ExternalId": "unique-external-id-here"
      }
    }
  }]
}
```

### Federated Access Trust (SAML)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:saml-provider/MyIdP"},
    "Action": "sts:AssumeRoleWithSAML",
    "Condition": {
      "StringEquals": {
        "SAML:aud": "https://signin.aws.amazon.com/saml"
      }
    }
  }]
}
```

### GitHub Actions OIDC Trust

Used with GitHub Actions to avoid storing AWS credentials as secrets.

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

---

## Resource-Based Policies

### S3 Bucket Policy: Cross-Account Read

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCrossAccountRead",
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::111122223333:role/DataConsumerRole"},
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::shared-data-bucket",
      "arn:aws:s3:::shared-data-bucket/*"
    ]
  }]
}
```

### S3 Bucket Policy: Organization-Wide Access

Use `aws:PrincipalOrgID` instead of listing individual account IDs.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowOrgAccess",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::shared-artifacts/*",
    "Condition": {
      "StringEquals": {
        "aws:PrincipalOrgID": "o-abc123def4"
      }
    }
  }]
}
```

### KMS Key Policy: Cross-Account Decrypt

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowKeyAdmin",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:root"},
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowCrossAccountDecrypt",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::111122223333:role/DecryptorRole"},
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "*"
    }
  ]
}
```

### SQS Queue Policy: Allow SNS to Publish

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowSNSPublish",
    "Effect": "Allow",
    "Principal": {"Service": "sns.amazonaws.com"},
    "Action": "sqs:SendMessage",
    "Resource": "arn:aws:sqs:us-east-1:123456789012:my-queue",
    "Condition": {
      "ArnEquals": {
        "aws:SourceArn": "arn:aws:sns:us-east-1:123456789012:my-topic"
      }
    }
  }]
}
```

---

## Permission Boundary

Allows broad actions but blocks privilege escalation paths.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    },
    {
      "Effect": "Deny",
      "Action": [
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "organizations:*",
        "account:*"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## Service Control Policies (SCPs)

### Region Restriction with Break-Glass Exemption

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyRegionsOutsideAllowed",
    "Effect": "Deny",
    "Action": "*",
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "aws:RequestedRegion": ["us-east-1", "us-west-2", "eu-west-1"]
      },
      "ArnNotLike": {
        "aws:PrincipalARN": "arn:aws:iam::*:role/OrganizationAdmin"
      }
    }
  }]
}
```

### Deny Leaving Organization

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyLeavingOrg",
    "Effect": "Deny",
    "Action": "organizations:LeaveOrganization",
    "Resource": "*"
  }]
}
```

### Require IMDSv2

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "RequireIMDSv2",
    "Effect": "Deny",
    "Action": "ec2:RunInstances",
    "Resource": "arn:aws:ec2:*:*:instance/*",
    "Condition": {
      "StringNotEquals": {
        "ec2:MetadataHttpTokens": "required"
      }
    }
  }]
}
```

### Deny Public RDS Instances

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyPublicRDS",
    "Effect": "Deny",
    "Action": [
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance"
    ],
    "Resource": "*",
    "Condition": {
      "Bool": {
        "rds:PubliclyAccessible": "true"
      }
    }
  }]
}
```

### Deny Unencrypted EBS Volumes

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyUnencryptedVolumes",
    "Effect": "Deny",
    "Action": "ec2:CreateVolume",
    "Resource": "*",
    "Condition": {
      "Bool": {
        "ec2:Encrypted": "false"
      }
    }
  }]
}
```

### Deny Root Access Key Creation

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "DenyRootAccessKeys",
    "Effect": "Deny",
    "Action": "iam:CreateAccessKey",
    "Resource": "arn:aws:iam::*:root",
    "Condition": {
      "ArnNotLike": {
        "aws:PrincipalARN": "arn:aws:iam::*:role/OrganizationAdmin"
      }
    }
  }]
}
```

---

## Condition Keys Quick Reference

| Condition Key | Use Case |
|---|---|
| `aws:RequestedRegion` | Restrict actions to specific regions |
| `aws:PrincipalOrgID` | Allow access from any account in your org |
| `aws:SourceVpc` / `aws:SourceVpce` | Restrict to VPC or VPC endpoint origin |
| `aws:PrincipalARN` | Exempt specific roles from deny statements |
| `aws:MultiFactorAuthPresent` | Require MFA for sensitive actions |
| `aws:PrincipalTag/*` | Attribute-based access control (ABAC) |
| `aws:ResourceTag/*` | Restrict based on resource tags |
| `sts:ExternalId` | Prevent confused deputy in cross-account |
| `s3:prefix` | Scope S3 ListBucket to a key prefix |
| `ec2:MetadataHttpTokens` | Enforce IMDSv2 |
