# LMI Infrastructure Setup

## IAM Roles (Two Required)

### 1. Execution Role (for the function)
```bash
aws iam create-role --role-name LMIExecutionRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name LMIExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

### 2. Operator Role (for capacity provider EC2 management)
```bash
aws iam create-role --role-name LMIOperatorRole \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name LMIOperatorRole \
  --policy-arn arn:aws:iam::aws:policy/AWSLambdaManagedEC2ResourceOperator
```

First-time capacity provider creation also requires `iam:CreateServiceLinkedRole`.

## VPC Requirements

- 3+ subnets across different AZs (for default 3-instance fleet)
- Security groups restricting to necessary traffic only
- NAT Gateway or VPC endpoints for egress (CloudWatch Logs, X-Ray)
- Function invocations bypass VPC (routed through Lambda service)
- Recommended VPC endpoints: CloudWatch Logs, X-Ray, S3, DynamoDB, SQS

## CLI Workflow

```bash
# 1. Create capacity provider
aws lambda create-capacity-provider \
  --capacity-provider-name my-cp \
  --vpc-config SubnetIds=[$SUBNET1,$SUBNET2,$SUBNET3],SecurityGroupIds=[$SG_ID] \
  --permissions-config CapacityProviderOperatorRoleArn=arn:aws:iam::$ACCT:role/LMIOperatorRole \
  --instance-requirements Architectures=[arm64] \
  --capacity-provider-scaling-config MaxVCpuCount=30

# 2. Create function
aws lambda create-function --function-name my-fn --runtime python3.13 \
  --handler app.handler --zip-file fileb://function.zip \
  --role arn:aws:iam::$ACCT:role/LMIExecutionRole --architectures arm64 \
  --memory-size 4096 \
  --capacity-provider-config \
    LambdaManagedInstancesCapacityProviderConfig='{CapacityProviderArn=arn:aws:lambda:$REGION:$ACCT:capacity-provider:my-cp}'

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
