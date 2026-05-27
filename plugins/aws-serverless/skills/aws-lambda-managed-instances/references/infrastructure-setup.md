# LMI Infrastructure Setup

## IAM Roles (Two Required)

### 1. Execution Role (for the function)

Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
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
    "Principal": { "Service": "lambda.amazonaws.com" },
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

- Subnets across multiple AZs recommended (minimum 1 required; 3+ for multi-AZ resiliency)
- Security groups: HTTPS egress (port 443) for AWS API calls; no ingress needed
- VPC endpoints (if no NAT gateway) for AWS service access:

| Endpoint              | Type      | Purpose               |
| --------------------- | --------- | --------------------- |
| S3                    | Gateway   | Object storage access |
| DynamoDB              | Gateway   | Table access          |
| SQS                   | Interface | Queue operations      |
| CloudWatch Logs       | Interface | Log delivery          |
| CloudWatch Monitoring | Interface | Metrics/EMF           |
| X-Ray                 | Interface | Distributed tracing   |

## CLI Workflow

### Required Parameters

| Parameter            | Description                                 |
| -------------------- | ------------------------------------------- |
| `SUBNET_IDS`         | Comma-separated subnet IDs across 3+ AZs    |
| `SECURITY_GROUP_ID`  | Security group ID for the capacity provider |
| `ACCOUNT_ID`         | AWS account ID                              |
| `OPERATOR_ROLE_ARN`  | ARN of the operator role (see above)        |
| `EXECUTION_ROLE_ARN` | ARN of the execution role (see above)       |
| `FUNCTION_NAME`      | Name for the Lambda function                |
| `CP_NAME`            | Name for the capacity provider              |
| `ARCHITECTURE`       | `arm64` (Graviton) or `x86_64`              |

### Automated Setup

See [`scripts/setup-lmi.sh`](../scripts/setup-lmi.sh) — set the environment variables above and run:

```bash
./scripts/setup-lmi.sh <function-name> <capacity-provider-name> <architecture>
```

### Manual Steps

```bash
# 1. Create capacity provider
aws lambda create-capacity-provider \
  --capacity-provider-name $CP_NAME \
  --vpc-config "SubnetIds=[$SUBNET_IDS],SecurityGroupIds=[$SECURITY_GROUP_ID]" \
  --permissions-config "CapacityProviderOperatorRoleArn=$OPERATOR_ROLE_ARN" \
  --instance-requirements "Architectures=[$ARCHITECTURE]" \
  --capacity-provider-scaling-config "MaxVCpuCount=30"

# 2. Create function
aws lambda create-function --function-name $FUNCTION_NAME --runtime python3.13 \
  --handler app.handler --zip-file fileb://function.zip \
  --role $EXECUTION_ROLE_ARN --architectures $ARCHITECTURE \
  --memory-size 4096 \
  --capacity-provider-config \
    "LambdaManagedInstancesCapacityProviderConfig={CapacityProviderArn=arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:capacity-provider:$CP_NAME}"

# 3. Publish version (triggers provisioning — takes several minutes)
aws lambda publish-version --function-name $FUNCTION_NAME

# 4. Invoke (must use versioned ARN)
aws lambda invoke --function-name $FUNCTION_NAME:1 --payload '{}' response.json
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
