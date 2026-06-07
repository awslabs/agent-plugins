# SDK IAM Role/Policies Setup

The first role you will need to create is the role you will assume when running training jobs.
The following is a full list of permissions you need to perform most actions using the SDK.
However, not all permissions are required.
Please refer to the "Sid" of each statement to determine which policies you need to include in your role.

## Basic SDK IAM Role

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "ConnectToHyperPodCluster",
    "Effect": "Allow",
    "Action": [
      "eks:DescribeCluster",
      "eks:ListAddons",
      "sagemaker:DescribeCluster"
    ],
    "Resource": [
      "arn:aws:eks:<region>:<account_id>:cluster/*",
      "arn:aws:sagemaker:<region>:<account_id>:cluster/*"
    ]
  }, {
    "Sid": "ManageHyperPodCluster",
    "Effect": "Allow",
    "Action": [
      "sagemaker:UpdateCluster"
    ],
    "Resource": [
      "arn:aws:sagemaker:<region>:<account_id>:cluster/*"
    ]
  }, {
    "Sid": "StartSageMakerTrainingJob",
    "Effect": "Allow",
    "Action": [
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob"
    ],
    "Resource": "arn:aws:sagemaker:<region>:<account_id>:training-job/*"
  }, {
    "Sid": "SageMakerHubContent",
    "Effect": "Allow",
    "Action": ["sagemaker:DescribeHubContent"],
    "Resource": [
      "arn:aws:sagemaker:<region>:aws:hub/SageMakerPublicHub",
      "arn:aws:sagemaker:<region>:aws:hub-content/SageMakerPublicHub/*/*"
    ]
  }, {
    "Sid": "InteractWithSageMakerAndBedrockExecutionRoles",
    "Effect": "Allow",
    "Action": [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:SimulatePrincipalPolicy",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:ListAttachedRolePolicies"
    ],
    "Resource": "arn:aws:iam::<account_id>:role/*"
  }, {
    "Sid": "CreateSageMakerAndBedrockExecutionRolePolicies",
    "Effect": "Allow",
    "Action": [
      "iam:CreatePolicy",
      "iam:GetPolicy"
    ],
    "Resource": "arn:aws:iam::<account_id>:policy/*"
  }, {
    "Sid": "HandleTrainingInputAndOutput",
    "Effect": "Allow",
    "Action": [
      "s3:CreateBucket",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ],
    "Resource": "arn:aws:s3:::*"
  }, {
    "Sid": "AccessCloudWatchLogs",
    "Effect": "Allow",
    "Action": [
      "logs:DescribeLogStreams",
      "logs:FilterLogEvents",
      "logs:GetLogEvents"
    ],
    "Resource": "arn:aws:logs:<region>:<account_id>:log-group:*"
  }, {
    "Sid": "ImportModelToBedrock",
    "Effect": "Allow",
    "Action": [
      "bedrock:CreateCustomModel"
    ],
    "Resource": "*"
  }, {
    "Sid": "DeployModelInBedrock",
    "Effect": "Allow",
    "Action": [
      "bedrock:CreateCustomModelDeployment",
      "bedrock:CreateProvisionedModelThroughput",
      "bedrock:GetCustomModel",
      "bedrock:GetCustomModelDeployment",
      "bedrock:GetProvisionedModelThroughput",
      "bedrock:ListCustomModelDeployments"
    ],
    "Resource": "arn:aws:bedrock:<region>:<account_id>:custom-model/*"
  }, {
    "Sid": "DeployAndInvokeModelInSageMaker",
    "Effect": "Allow",
    "Action": [
      "sagemaker:CreateEndpoint",
      "sagemaker:CreateEndpointConfig",
      "sagemaker:CreateModel",
      "sagemaker:DeleteEndpoint",
      "sagemaker:DeleteEndpointConfig",
      "sagemaker:DeleteModel",
      "sagemaker:DescribeEndpoint",
      "sagemaker:DescribeEndpointConfig",
      "sagemaker:InvokeEndpoint",
      "sagemaker:InvokeEndpointWithResponseStream",
      "sagemaker:UpdateEndpoint"
    ],
    "Resource": [
      "arn:aws:sagemaker:<region>:<account_id>:endpoint/*",
      "arn:aws:sagemaker:<region>:<account_id>:endpoint-config/*",
      "arn:aws:sagemaker:<region>:<account_id>:model/*"
    ]
  }, {
    "Sid": "MLflowSageMaker",
    "Effect": "Allow",
    "Action": [
      "sagemaker-mlflow:AccessUI",
      "sagemaker-mlflow:CreateExperiment",
      "sagemaker-mlflow:CreateModelVersion",
      "sagemaker-mlflow:CreateRegisteredModel",
      "sagemaker-mlflow:CreateRun",
      "sagemaker-mlflow:DeleteTag",
      "sagemaker-mlflow:FinalizeLoggedModel",
      "sagemaker-mlflow:Get*",
      "sagemaker-mlflow:ListArtifacts",
      "sagemaker-mlflow:ListLoggedModelArtifacts",
      "sagemaker-mlflow:LogBatch",
      "sagemaker-mlflow:LogInputs",
      "sagemaker-mlflow:LogLoggedModelParams",
      "sagemaker-mlflow:LogMetric",
      "sagemaker-mlflow:LogModel",
      "sagemaker-mlflow:LogOutputs",
      "sagemaker-mlflow:LogParam",
      "sagemaker-mlflow:RenameRegisteredModel",
      "sagemaker-mlflow:RestoreExperiment",
      "sagemaker-mlflow:RestoreRun",
      "sagemaker-mlflow:Search*",
      "sagemaker-mlflow:SetExperimentTag",
      "sagemaker-mlflow:SetLoggedModelTags",
      "sagemaker-mlflow:SetRegisteredModelAlias",
      "sagemaker-mlflow:SetRegisteredModelTag",
      "sagemaker-mlflow:SetTag",
      "sagemaker-mlflow:TransitionModelVersionStage",
      "sagemaker-mlflow:UpdateExperiment",
      "sagemaker-mlflow:UpdateModelVersion",
      "sagemaker-mlflow:UpdateRegisteredModel"
    ],
    "Resource": "arn:aws:sagemaker:<region>:<account_id>:mlflow-tracking-server/*"
  }, {
    "Sid": "BedrockCustomizationJobs",
    "Effect": "Allow",
    "Action": [
      "bedrock:CreateModelCustomizationJob",
      "bedrock:GetModelCustomizationJob",
      "bedrock:StopModelCustomizationJob"
    ],
    "Resource": [
      "arn:aws:bedrock:<region>:<account_id>:model-customization-job/*",
      "arn:aws:bedrock:<region>:<account_id>:custom-model/*"
    ]
  }]
}
```

- _Note that you might not require all permissions depending on your use case._
- [HyperPod only] If your cluster uses namespace access control, you must have access to the Kubernetes namespace

### Job Monitoring via Email Notifications

If you want to enable email notifications for SMTJ training jobs, your IAM role needs additional permissions to create and manage the notification infrastructure. The notification system uses CloudFormation to automatically provision resources including DynamoDB, SNS, Lambda, EventBridge, and IAM roles.

**Required Permissions:**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ManageNotificationCloudFormationStack",
            "Effect": "Allow",
            "Action": [
                "cloudformation:CreateStack",
                "cloudformation:DeleteStack",
                "cloudformation:DescribeStacks",
                "cloudformation:DescribeStackEvents",
                "cloudformation:GetTemplate"
            ],
            "Resource": "arn:aws:cloudformation:<region>:<account_id>:stack/NovaForgeSDK-*-JobNotifications/*"
        },
        {
            "Sid": "ManageNotificationDynamoDBTable",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DeleteTable",
                "dynamodb:DescribeTable",
                "dynamodb:DescribeTimeToLive",
                "dynamodb:PutItem",
                "dynamodb:UpdateTimeToLive"
            ],
            "Resource": "arn:aws:dynamodb:<region>:<account_id>:table/NovaForgeSDK-*-JobNotifications"
        },
        {
            "Sid": "ManageNotificationSNSTopic",
            "Effect": "Allow",
            "Action": [
                "sns:CreateTopic",
                "sns:DeleteTopic",
                "sns:GetTopicAttributes",
                "sns:ListSubscriptionsByTopic",
                "sns:Subscribe",
                "sns:Unsubscribe"
            ],
            "Resource": "arn:aws:sns:<region>:<account_id>:NovaForgeSDK-*-Notifications"
        },
        {
            "Sid": "ManageNotificationLambdaFunction",
            "Effect": "Allow",
            "Action": [
                "lambda:CreateFunction",
                "lambda:DeleteFunction",
                "lambda:GetFunction",
                "lambda:AddPermission",
                "lambda:RemovePermission"
            ],
            "Resource": "arn:aws:lambda:<region>:<account_id>:function:NovaForgeSDK-*-NotificationHandler"
        },
        {
            "Sid": "ManageNotificationEventBridgeRule",
            "Effect": "Allow",
            "Action": [
                "events:PutRule",
                "events:DeleteRule",
                "events:DescribeRule",
                "events:PutTargets",
                "events:RemoveTargets"
            ],
            "Resource": "arn:aws:events:<region>:<account_id>:rule/NovaForgeSDK-*-Job-State-Change"
        },
        {
            "Sid": "ManageNotificationIAMRoles",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:PassRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy"
            ],
            "Resource": [
                "arn:aws:iam::<account_id>:role/NovaForgeSDK-*-NotificationLambdaRole",
                "arn:aws:iam::<account_id>:role/NovaForgeSDK-*-EventBridgeRole"
            ]
        },
        {
            "Sid": "AccessCloudWatchLogsForNotifications",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:DeleteLogGroup",
                "logs:DescribeLogGroups"
            ],
            "Resource": "arn:aws:logs:<region>:<account_id>:log-group:/aws/lambda/NovaForgeSDK-*-NotificationHandler*"
        },
        {
            "Sid": "ManageNotificationKMSKey",
            "Effect": "Allow",
            "Action": [
                "kms:CreateKey",
                "kms:CreateAlias",
                "kms:CreateGrant",
                "kms:DeleteAlias",
                "kms:DescribeKey",
                "kms:GetKeyPolicy",
                "kms:PutKeyPolicy",
                "kms:RevokeGrant",
                "kms:ScheduleKeyDeletion",
                "kms:TagResource",
                "kms:UntagResource"
            ],
            # If using a customer KMS key, that specific key can be specified here.
            "Resource": "arn:aws:kms:<region>:<account_id>:key/*"
        },
        {
            "Sid": "UseNotificationKMSKey",
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:Encrypt",
                "kms:GenerateDataKey"
            ],
            "Resource": "arn:aws:kms:<region>:<account_id>:key/*"
        }
    ]
}
```

**Notes:**

- These permissions are only required if you plan to use the `enable_job_notifications()` feature
- The wildcard `*` in resource ARNs matches both SMTJ and SMHP platform names (e.g., `NovaForgeSDK-SMTJ-JobNotifications`)
- The notification infrastructure is created automatically the first time you enable notifications
- You can delete the notification stack using `NotificationManager.delete_notification_stack()` when no longer needed
- KMS permissions use `Resource: "*"` because:
  - Key ARNs are not known until the key is created
  - Alias-based conditions don't work for key creation operations
  - The permissions are still scoped to your account through IAM

## Execution Role

The execution role is the role that SageMaker assumes to execute training jobs on your behalf. This can be separate from the role defined above, which is the role _you_ assume when using the SDK.
_**Please see AWS documentation for the recommended set of [execution role permissions](https://docs.aws.amazon.com/sagemaker/latest/dg/sagemaker-roles.html#sagemaker-roles-createtrainingjob-perms).**_

The execution role's trust policy must include the following statement:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "sagemaker.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

If performing RFT training, your execution role also must include the following statement:

```
{
    "Effect": "Allow",
    "Action": "lambda:InvokeFunction",
    "Resource": "arn:aws:lambda:<region>:<account_id>:function:MySageMakerRewardFunction"
}
```

If you use `deploy_lambda()` or `validate_lambda()` from the SDK, your calling role also needs the following permissions:

```
{
    "Effect": "Allow",
    "Action": [
        "lambda:CreateFunction",
        "lambda:GetFunction",
        "lambda:UpdateFunctionCode",
        "lambda:InvokeFunction"
    ],
    "Resource": "arn:aws:lambda:<region>:<account_id>:function:*"
},
{
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::<account_id>:role/*",
    "Condition": {
        "StringEquals": {
            "iam:PassedToService": "lambda.amazonaws.com"
        }
    }
}
```

**Note:** `lambda:CreateFunction`, `lambda:GetFunction`, `lambda:UpdateFunctionCode`, and `iam:PassRole` are required only when calling `deploy_lambda()`. `validate_lambda()` only requires `lambda:InvokeFunction`.

If performing RFT Multiturn training, you also need the following additional permissions on your **caller role**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SSMCommandsForRFTMultiturn",
      "Effect": "Allow",
      "Action": ["ssm:SendCommand"],
      "Resource": [
        "arn:aws:ec2:<region>:<account_id>:instance/*",
        "arn:aws:ssm:<region>::document/AWS-RunShellScript"
      ]
    },
    {
      "Sid": "SSMReadForRFTMultiturn",
      "Effect": "Allow",
      "Action": [
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:DescribeInstanceInformation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSTaskManagementForRFTMultiturn",
      "Effect": "Allow",
      "Action": [
        "ecs:DeregisterTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RunTask",
        "ecs:StopTask"
      ],
      "Resource": [
        "arn:aws:ecs:<region>:<account_id>:cluster/*",
        "arn:aws:ecs:<region>:<account_id>:task/*",
        "arn:aws:ecs:<region>:<account_id>:task-definition/*"
      ]
    },
    {
      "Sid": "IAMInstanceProfileForRFTMultiturnEC2",
      "Effect": "Allow",
      "Action": ["iam:GetInstanceProfile"],
      "Resource": "*"
    },
    {
      "Sid": "EC2ValidateForRFTMultiturn",
      "Effect": "Allow",
      "Action": ["ec2:DescribeInstances", "ec2:DescribeImages"],
      "Resource": "*"
    },
    {
      "Sid": "RFTMultiturnInfraDiscovery",
      "Effect": "Allow",
      "Action": [
        "cloudformation:ListStacks",
        "ecs:DescribeClusters"
      ],
      "Resource": "*"
    }
  ]
}
```

If you don’t explicitly set an execution role when creating a runtime manager, the SDK automatically uses the IAM role associated with the credentials you’re using to make the SDK call.

## **EKS Cluster Access (HyperPod Only)**

After creating your execution role, you must grant it access to your HyperPod cluster's EKS cluster. This is required for the SDK to submit jobs to HyperPod.

### Step 1: Create an access entry for your execution role

```bash
aws eks create-access-entry \
  --cluster-name <your-cluster-name> \
  --principal-arn arn:aws:iam::<account_id>:role/<your-execution-role-name>
```

### Step 2: Associate the cluster admin policy

```bash
aws eks associate-access-policy \
  --cluster-name <your-cluster-name> \
  --principal-arn arn:aws:iam::<account_id>:role/<your-execution-role-name> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

Replace the following placeholders:

- `<your-cluster-name>`: Your HyperPod cluster's EKS cluster name (e.g., `sagemaker-my-cluster-eks`)
- `<account_id>`: Your AWS account ID
- `<your-execution-role-name>`: The name of your execution role (e.g., `NovaForgeSdkExecutionRole`)
