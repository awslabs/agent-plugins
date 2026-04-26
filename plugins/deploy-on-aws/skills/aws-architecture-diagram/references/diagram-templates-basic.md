# Diagram Templates — Basic

Ready-to-use patterns for common AWS architectures. Use these as starting points.

## Serverless Web Application

Services: CloudFront → API Gateway → Lambda → DynamoDB, with S3 for static assets and Cognito for auth.

```
Layout (left to right):
  [Users] → [CloudFront] → [S3 Bucket (static)]
                         → [API Gateway] → [Lambda] → [DynamoDB]
                                                     → [S3 Bucket (data)]
  [Cognito] connected to [API Gateway] (auth)
```

Typical cell arrangement:

- Users icon at x=50
- CloudFront at x=250
- S3 static at x=450, y offset up
- API Gateway at x=450
- Lambda at x=650
- DynamoDB at x=850
- Cognito at x=450, y offset down

## VPC with Public/Private Subnets

```
Layout (nested groups):
  [AWS Cloud]
    [Region]
      [VPC 10.0.0.0/16]
        [AZ-1]
          [Public Subnet 10.0.1.0/24]
            - NAT Gateway
            - ALB
          [Private Subnet 10.0.2.0/24]
            - EC2 / ECS instances
            - RDS (primary)
        [AZ-2]
          [Public Subnet 10.0.3.0/24]
            - NAT Gateway
          [Private Subnet 10.0.4.0/24]
            - EC2 / ECS instances
            - RDS (standby)
      [Internet Gateway] at VPC boundary
  [Users] → [Internet Gateway] → [ALB] → [EC2/ECS]
```

## Microservices on ECS/EKS

```
Layout:
  [Route 53] → [CloudFront] → [ALB]

  [VPC]
    [ECS/EKS Cluster]
      [Service A] ←→ [Service B] ←→ [Service C]

    [ElastiCache] connected to services
    [RDS Aurora] connected to services

  [ECR] connected to [ECS/EKS Cluster]
  [CloudWatch] monitoring all services
```

## Data Pipeline / Analytics

```
Layout (left to right, pipeline flow):
  [Data Sources]
    - [Kinesis Data Streams] ← external data
    - [S3 Bucket (raw)] ← batch uploads

  [Processing]
    - [Kinesis Data Firehose] → [S3 (processed)]
    - [Glue ETL Jobs] → [S3 (curated)]
    - [Lambda] for real-time transforms

  [Storage]
    - [S3 Data Lake] (multiple buckets)
    - [Glue Data Catalog]

  [Analytics]
    - [Athena] → queries S3
    - [Redshift] → warehouse
    - [QuickSight] → dashboards

  [Lake Formation] governing access across the pipeline
```

## CI/CD Pipeline

```
Layout (left to right, pipeline stages):
  [Developer] → [CodeCommit] → [CodePipeline] → [CodeBuild] → [S3 (artifacts)]
  [CodePipeline] → [CodeDeploy (staging)] → [Manual Approval] → [CodeDeploy (prod)]
  [ECR] if deploying containers
  [CloudWatch] monitoring, [SNS] for notifications
```
