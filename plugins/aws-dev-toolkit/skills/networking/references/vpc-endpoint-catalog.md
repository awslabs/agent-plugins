# VPC Endpoint Catalog

Commonly used VPC endpoints with configuration guidance. Organized by priority.

## Always Create (Free Gateway Endpoints)

These are free. There is no reason not to create them in every VPC.

| Service | Endpoint Type | Service Name | Cost |
|---|---|---|---|
| S3 | Gateway | com.amazonaws.\<region\>.s3 | Free |
| DynamoDB | Gateway | com.amazonaws.\<region\>.dynamodb | Free |

**Gateway endpoint notes:**
- Added to route tables (not subnet ENIs)
- No security group required
- Use VPC endpoint policies to restrict which buckets/tables can be accessed
- Must be associated with the route tables for subnets that need access

```bash
# Create S3 gateway endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.us-east-1.s3 \
  --route-table-ids rtb-aaa rtb-bbb rtb-ccc

# Create DynamoDB gateway endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.us-east-1.dynamodb \
  --route-table-ids rtb-aaa rtb-bbb rtb-ccc
```

## Priority 1: Essential for Isolated Subnets

If you have subnets with no internet access (isolated/private without NAT), you need these interface endpoints for basic AWS service connectivity.

| Service | Service Name | Why |
|---|---|---|
| STS | com.amazonaws.\<region\>.sts | IAM role assumption, temporary credentials |
| CloudWatch Logs | com.amazonaws.\<region\>.logs | Send logs to CloudWatch |
| CloudWatch Monitoring | com.amazonaws.\<region\>.monitoring | Publish metrics |
| KMS | com.amazonaws.\<region\>.kms | Encrypt/decrypt with KMS keys |
| Secrets Manager | com.amazonaws.\<region\>.secretsmanager | Retrieve secrets at runtime |
| SSM (Systems Manager) | com.amazonaws.\<region\>.ssm | Parameter Store, Session Manager |
| SSM Messages | com.amazonaws.\<region\>.ssmmessages | Session Manager shell access |
| EC2 Messages | com.amazonaws.\<region\>.ec2messages | SSM agent communication |

**Cost per interface endpoint:** ~$0.01/hour per AZ (~$7.20/month per AZ) + $0.01/GB data processed.

For 3 AZs: ~$21.60/month per endpoint. 8 endpoints = ~$173/month. Compare against NAT Gateway cost.

## Priority 2: Container Workloads (ECS/EKS)

Required when running containers in private/isolated subnets.

| Service | Service Name | Why |
|---|---|---|
| ECR API | com.amazonaws.\<region\>.ecr.api | Pull container image manifests |
| ECR Docker | com.amazonaws.\<region\>.ecr.dkr | Pull container image layers |
| S3 (Gateway) | com.amazonaws.\<region\>.s3 | ECR stores image layers in S3 |

**All three are required for ECR image pulls.** Missing any one causes pull failures.

```bash
# Create ECR endpoints (both required)
for svc in ecr.api ecr.dkr; do
  aws ec2 create-vpc-endpoint \
    --vpc-id vpc-xxx \
    --vpc-endpoint-type Interface \
    --service-name com.amazonaws.us-east-1.$svc \
    --subnet-ids subnet-aaa subnet-bbb subnet-ccc \
    --security-group-ids sg-xxx \
    --private-dns-enabled
done
```

**EKS additional endpoints:**

| Service | Service Name | Why |
|---|---|---|
| EKS | com.amazonaws.\<region\>.eks | Kubernetes API server communication |
| EKS Auth | com.amazonaws.\<region\>.eks-auth | Pod identity |
| EC2 | com.amazonaws.\<region\>.ec2 | Node registration and ENI management |
| Elastic Load Balancing | com.amazonaws.\<region\>.elasticloadbalancing | ALB/NLB for Kubernetes services |
| Auto Scaling | com.amazonaws.\<region\>.autoscaling | Cluster Autoscaler / Karpenter |

## Priority 3: Lambda in VPC

Lambda in a VPC needs these endpoints to call AWS services without NAT Gateway.

| Service | Service Name | Why |
|---|---|---|
| Lambda | com.amazonaws.\<region\>.lambda | Invoke other Lambda functions |
| SQS | com.amazonaws.\<region\>.sqs | Process SQS messages |
| SNS | com.amazonaws.\<region\>.sns | Publish to SNS topics |
| Events (EventBridge) | com.amazonaws.\<region\>.events | Put events to EventBridge |
| Step Functions | com.amazonaws.\<region\>.states | Interact with state machines |

Note: Lambda functions in a VPC already need the Priority 1 endpoints (STS, Logs, KMS, etc.).

## Priority 4: Data and Analytics

| Service | Service Name | Why |
|---|---|---|
| Kinesis Streams | com.amazonaws.\<region\>.kinesis-streams | Stream data ingestion |
| Kinesis Firehose | com.amazonaws.\<region\>.firehose | Delivery stream |
| SageMaker API | com.amazonaws.\<region\>.sagemaker.api | Model management |
| SageMaker Runtime | com.amazonaws.\<region\>.sagemaker.runtime | Model inference |
| Athena | com.amazonaws.\<region\>.athena | Query execution |
| Glue | com.amazonaws.\<region\>.glue | ETL jobs and crawlers |
| Bedrock | com.amazonaws.\<region\>.bedrock-runtime | Invoke foundation models |

## Priority 5: Security and Compliance

| Service | Service Name | Why |
|---|---|---|
| CloudTrail | com.amazonaws.\<region\>.cloudtrail | API logging |
| Config | com.amazonaws.\<region\>.config | Compliance checks |
| GuardDuty | com.amazonaws.\<region\>.guardduty-data | Threat detection data |
| Security Hub | com.amazonaws.\<region\>.securityhub | Aggregate security findings |
| ACM (Private CA) | com.amazonaws.\<region\>.acm-pca | Private certificate issuance |

## Interface Endpoint Configuration

All interface endpoints share these configuration requirements:

### Security Group

Create a dedicated security group for VPC endpoints:

```bash
# Create endpoint security group
aws ec2 create-security-group \
  --group-name vpc-endpoints-sg \
  --description "Security group for VPC interface endpoints" \
  --vpc-id vpc-xxx

# Allow HTTPS from VPC CIDR
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/16
```

All AWS API calls go over HTTPS (port 443). The security group only needs inbound 443 from your VPC CIDR.

### Private DNS

- **Enable Private DNS** on interface endpoints so the default AWS service endpoint (e.g., `sqs.us-east-1.amazonaws.com`) resolves to the private endpoint IP
- Without Private DNS, you must configure your SDK/application to use the VPC endpoint DNS name
- Private DNS requires `enableDnsSupport` and `enableDnsHostnames` on the VPC

### Subnet Placement

- Place endpoints in the same subnets as the resources that use them
- For high availability, create the endpoint in all AZs where you have workloads
- Each AZ creates one ENI per endpoint

## Cost Optimization

**VPC endpoints vs. NAT Gateway:**

| Factor | VPC Endpoints | NAT Gateway |
|---|---|---|
| Hourly cost | $0.01/AZ/endpoint | $0.045/AZ/gateway |
| Data processing | $0.01/GB | $0.045/GB |
| Scales with | Number of services used | Total egress volume |
| Security | Restricts to specific AWS services | Open to all internet |

**Break-even analysis:**
- If you use <5 AWS services from private subnets, endpoints are cheaper
- If you use 5+ services AND need general internet access, NAT Gateway may be simpler
- If you have isolated subnets (no internet), endpoints are your only option
- Combining both is common: endpoints for high-volume AWS services (S3, ECR, Logs), NAT for occasional internet access

**Cost-saving tips:**
- Gateway endpoints (S3, DynamoDB) are always free. Create them first.
- Share endpoints across subnets in the same AZ. One endpoint serves all resources in its AZ.
- Review endpoint data processing costs. High-volume services (S3, ECR pulls) benefit most from endpoints.

## Endpoint Policies

Restrict what actions can be performed through an endpoint. Defense in depth.

```json
{
  "Statement": [
    {
      "Sid": "AllowSpecificBucket",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::my-app-bucket/*"
    }
  ]
}
```

Use endpoint policies to:
- Restrict S3 access to specific buckets (prevent data exfiltration)
- Restrict ECR access to your account's repositories
- Limit KMS to specific key ARNs
- Prevent calling services in other accounts
