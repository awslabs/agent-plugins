# LMI Infrastructure Setup

## IAM Roles (Two Required)

### 1. Execution Role (for the function)

Trust policy:
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

Minimum permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/*"
    }
  ]
}
```

Add VPC permissions only if the function accesses VPC resources:
```json
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateNetworkInterface",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DeleteNetworkInterface"
  ],
  "Resource": "*"
}
```

### 2. Operator Role (for capacity provider EC2 management)

Trust policy:
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

Minimum permissions (scoped with conditions):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:RunInstances", "ec2:CreateTags", "ec2:AttachNetworkInterface"],
      "Resource": [
        "arn:aws:ec2:*:*:instance/*",
        "arn:aws:ec2:*:*:network-interface/*",
        "arn:aws:ec2:*:*:volume/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:ManagedResourceOperator": "scaler.lambda.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeCapacityReservations",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["ec2:RunInstances", "ec2:CreateNetworkInterface"],
      "Resource": [
        "arn:aws:ec2:*:*:subnet/*",
        "arn:aws:ec2:*:*:security-group/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "ec2:RunInstances",
      "Resource": "arn:aws:ec2:*:*:image/*",
      "Condition": {
        "StringEquals": { "ec2:Owner": "amazon" }
      }
    },
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "<execution-role-arn>"
    }
  ]
}
```

The `ec2:ManagedResourceOperator` condition ensures RunInstances/CreateTags only apply to Lambda-managed instances. First-time capacity provider creation also requires `iam:CreateServiceLinkedRole`.

## VPC Requirements

LMI runs functions on EC2 instances inside the VPC. These instances need VPC endpoints or NAT to reach AWS services.

- 3+ subnets across different AZs (for default 3-instance fleet)
- Security groups: HTTPS egress (port 443) for AWS API calls; no ingress needed
- Required VPC endpoints:

| Endpoint | Type | Purpose | Cost |
|----------|------|---------|------|
| S3 | Gateway | Object storage access | Free |
| DynamoDB | Gateway | Table access | Free |
| SQS | Interface | Queue operations | $0.01/hr per AZ |
| CloudWatch Logs | Interface | Log delivery | $0.01/hr per AZ |
| CloudWatch Monitoring | Interface | Metrics/EMF | $0.01/hr per AZ |
| X-Ray | Interface | Distributed tracing | $0.01/hr per AZ |

Gateway endpoints are free; interface endpoints incur hourly charges per AZ.

## CLI Workflow

Use the setup script for automated provisioning:

```bash
# Set required environment variables
export SUBNET_IDS="subnet-abc,subnet-def,subnet-ghi"
export SECURITY_GROUP_ID="sg-123456"
export ACCOUNT_ID="123456789012"
export OPERATOR_ROLE_ARN="arn:aws:iam::123456789012:role/LMIOperatorRole"
export EXECUTION_ROLE_ARN="arn:aws:iam::123456789012:role/LMIExecutionRole"

# Run setup
./scripts/setup-lmi.sh my-function my-capacity-provider arm64
```

See [`scripts/setup-lmi.sh`](../scripts/setup-lmi.sh) for the full script with configurable options.

### Manual Steps (if not using the script)

```bash
# 1. Create capacity provider
aws lambda create-capacity-provider \
  --capacity-provider-name my-cp \
  --vpc-config "SubnetIds=[subnet-abc,subnet-def,subnet-ghi],SecurityGroupIds=[sg-123456]" \
  --permissions-config "CapacityProviderOperatorRoleArn=arn:aws:iam::$ACCT:role/LMIOperatorRole" \
  --instance-requirements "Architectures=[arm64]" \
  --capacity-provider-scaling-config "MaxVCpuCount=30"

# 2. Create function
aws lambda create-function --function-name my-fn --runtime python3.13 \
  --handler app.handler --zip-file fileb://function.zip \
  --role "arn:aws:iam::$ACCT:role/LMIExecutionRole" --architectures arm64 \
  --memory-size 4096 \
  --capacity-provider-config \
    "LambdaManagedInstancesCapacityProviderConfig={CapacityProviderArn=arn:aws:lambda:$REGION:$ACCT:capacity-provider:my-cp}"

# 3. Publish version (triggers provisioning — takes several minutes)
aws lambda publish-version --function-name my-fn

# 4. Invoke (must use versioned ARN)
aws lambda invoke --function-name my-fn:1 --payload '{}' response.json
```

Architecture must match between function and capacity provider.

## SAM Template

```yaml
Resources:
  MyCP:
    Type: AWS::Lambda::CapacityProvider
    Properties:
      CapacityProviderName: my-cp
      VpcConfig:
        SubnetIds: [!Ref Sub1, !Ref Sub2, !Ref Sub3]
        SecurityGroupIds: [!Ref SG]
      PermissionsConfig:
        CapacityProviderOperatorRoleArn: !GetAtt OpRole.Arn
      InstanceRequirements:
        Architectures: [arm64]
      CapacityProviderScalingConfig:
        MaxVCpuCount: 30

  MyFn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: python3.13
      Handler: app.handler
      MemorySize: 4096
      Architectures: [arm64]
      CapacityProviderConfig:
        LambdaManagedInstancesCapacityProviderConfig:
          CapacityProviderArn: !GetAtt MyCP.Arn
```

## Cleanup

```bash
aws lambda delete-function --function-name my-fn
aws lambda delete-capacity-provider --capacity-provider-name my-cp
```

Deleting the capacity provider destroys all associated EC2 instances.
