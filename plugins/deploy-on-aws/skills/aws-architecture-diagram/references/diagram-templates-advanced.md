# Diagram Templates — Advanced

Multi-region, hybrid, and sizing guidelines. See `diagram-templates-basic.md` for basic patterns.

## Multi-Region Active-Active

```
Layout (two regions side by side):
  [Route 53 (latency-based routing)] at top

  [Region 1: us-east-1]              [Region 2: eu-west-1]
    [CloudFront]                        [CloudFront]
    [ALB]                               [ALB]
    [ECS/Lambda]                        [ECS/Lambda]
    [Aurora (primary)]  ←──replication──→  [Aurora (replica)]
    [DynamoDB Global Table] ←──sync──→  [DynamoDB Global Table]
    [S3] ←──replication──→              [S3]

  [Global Accelerator] optionally at top
```

## Hybrid Architecture (On-Premises + AWS)

```
Layout:
  [Corporate Data Center]
    [Traditional Server]
    [Database]
    [Active Directory]

  ←── [Direct Connect] / [Site-to-Site VPN] ──→

  [AWS Cloud]
    [Transit Gateway]
      [VPC - Production]
        [workloads]
      [VPC - Shared Services]
        [Directory Service]
        [Systems Manager]
      [VPC - Development]
        [workloads]
```

## Sizing Guidelines for Templates

- **Small diagram** (3-5 services): pageWidth=800, pageHeight=600
- **Medium diagram** (6-12 services): pageWidth=1169, pageHeight=827 (default A3)
- **Large diagram** (13+ services): pageWidth=1600, pageHeight=1200
- **Multi-region**: pageWidth=2000, pageHeight=1000
- **Complex VPC**: pageWidth=1400, pageHeight=1000
