# SAM Service Integration Templates

Direct AWS service integrations without Lambda. These templates connect API Gateway directly to AWS services using VTL mapping templates (REST API) or WebSocket request templates.

## Table of Contents

- [EventBridge](#direct-aws-service-integration-eventbridge)
- [SQS](#direct-aws-service-integration-sqs)
- [DynamoDB Full CRUD](#direct-aws-service-integration-dynamodb-full-crud)
  - [Option A: OpenAPI-based definition](#option-a-openapi-based-definition-recommended-for-complex-apis)
  - [Option B: Inline CloudFormation methods](#option-b-inline-cloudformation-methods-simpler-for-small-apis)
- [Kinesis Data Streams](#direct-aws-service-integration-kinesis-data-streams)
- [Step Functions (REST API)](#direct-aws-service-integration-step-functions)
- [Step Functions (WebSocket API)](#websocket-api-express-workflow-sync-and-standard-workflow-async-with-callback)

---

## Direct AWS Service Integration (EventBridge)

Based on [aws-samples/serverless-patterns/apigw-rest-api-eventbridge-sam](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-rest-api-eventbridge-sam). Supports batching multiple events via `#foreach`.

```yaml
MyCustomEventBus:
  Type: AWS::Events::EventBus
  Properties:
    Name: !Sub "${AWS::StackName}-EventBus"

ApiGatewayEventBridgeRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: apigateway.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: EBPutEvents
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action: events:PutEvents
              Resource: !GetAtt MyCustomEventBus.Arn

EventBridgeIntegration:
  Type: AWS::ApiGateway::Method
  Properties:
    HttpMethod: POST
    ResourceId: !GetAtt Api.RootResourceId
    RestApiId: !Ref Api
    AuthorizationType: NONE
    Integration:
      Type: AWS
      IntegrationHttpMethod: POST
      Credentials: !GetAtt ApiGatewayEventBridgeRole.Arn
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:events:action/PutEvents"
      PassthroughBehavior: WHEN_NO_TEMPLATES
      RequestTemplates:
        application/json: !Sub
          - |-
            #set($context.requestOverride.header.X-Amz-Target = "AWSEvents.PutEvents")
            #set($context.requestOverride.header.Content-Type = "application/x-amz-json-1.1")
            #set($inputRoot = $input.path('$'))
            {
              "Entries": [
                #foreach($elem in $inputRoot.items)
                {
                  "Detail": "$util.escapeJavaScript($elem.Detail).replaceAll("\\'","'")",
                  "DetailType": "$elem.DetailType",
                  "EventBusName": "${EventBusName}",
                  "Source": "$elem.Source"
                }#if($foreach.hasNext),#end
                #end
              ]
            }
          - EventBusName: !Ref MyCustomEventBus
      IntegrationResponses:
        - StatusCode: "200"
          ResponseTemplates:
            application/json: '{}'
    MethodResponses:
      - StatusCode: "200"
        ResponseModels:
          application/json: Empty
```

## Direct AWS Service Integration (SQS)

Based on [aws-samples/serverless-patterns/apigw-sqs-lambda-iot](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-sqs-lambda-iot). Uses query protocol with `PassthroughBehavior: NEVER` to reject unmatched content types.

```yaml
SqsIntegration:
  Type: AWS::ApiGateway::Method
  Properties:
    HttpMethod: POST
    ResourceId: !Ref MessagesResource
    RestApiId: !Ref MyRestApi
    AuthorizationType: CUSTOM
    AuthorizerId: !Ref MyAuthorizer
    RequestValidatorId: !Ref BodyValidator
    RequestModels:
      application/json: !Ref MessageModel
    Integration:
      Type: AWS
      IntegrationHttpMethod: POST
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:sqs:path/${AWS::AccountId}/${MyQueue.QueueName}"
      Credentials: !GetAtt SqsRole.Arn
      PassthroughBehavior: NEVER
      RequestParameters:
        integration.request.header.Content-Type: "'application/x-www-form-urlencoded'"
      RequestTemplates:
        application/json: "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
      IntegrationResponses:
        - StatusCode: "200"
          ResponseTemplates:
            application/json: '{"messageId": "$input.path(''$.SendMessageResponse.SendMessageResult.MessageId'')"}'
    MethodResponses:
      - StatusCode: "200"

SqsRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: apigateway.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: SqsSendMessage
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action: sqs:SendMessage
              Resource: !GetAtt MyQueue.Arn
```

## Direct AWS Service Integration (DynamoDB Full CRUD)

Full CRUD pattern based on [aws-samples/serverless-patterns](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-dynamodb-lambda-scheduler-ses-auto-deletion-sam). Uses OpenAPI definition with `AWS::Include` for clean separation of API spec and infrastructure.

### Option A: OpenAPI-based definition (recommended for complex APIs)

SAM template references an external OpenAPI file:

```yaml
MyApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: v1
    EndpointConfiguration:
      Type: REGIONAL
    DefinitionBody:
      'Fn::Transform':
        Name: 'AWS::Include'
        Parameters:
          Location: './restapi/api.yaml'
    MethodSettings:
      - ResourcePath: "/*"
        HttpMethod: "*"
        LoggingLevel: ERROR

MyTable:
  Type: AWS::DynamoDB::Table
  Properties:
    AttributeDefinitions:
      - AttributeName: id
        AttributeType: S
    KeySchema:
      - AttributeName: id
        KeyType: HASH
    BillingMode: PAY_PER_REQUEST
    StreamSpecification:
      StreamViewType: NEW_IMAGE

APIGatewayDynamoDBRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: apigateway.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: DynamoDbCrud
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action:
                - dynamodb:GetItem
                - dynamodb:UpdateItem
                - dynamodb:DeleteItem
                - dynamodb:Scan
                - dynamodb:Query
              Resource: !GetAtt MyTable.Arn
```

OpenAPI file (`restapi/api.yaml`), key methods shown:

```yaml
openapi: "3.0.1"
info:
  title: "my-api"
paths:
  /items:
    ## Create: uses UpdateItem with $context.requestId as auto-generated ID
    post:
      requestBody:
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/item"
        required: true
      x-amazon-apigateway-request-validator: "Validate body"
      x-amazon-apigateway-integration:
        credentials:
          Fn::GetAtt: [APIGatewayDynamoDBRole, Arn]
        httpMethod: "POST"
        uri:
          Fn::Sub: "arn:aws:apigateway:${AWS::Region}:dynamodb:action/UpdateItem"
        requestTemplates:
          application/json:
            Fn::Sub: |
              {
                "TableName": "${MyTable}",
                "Key": {
                  "id": {"S": "$context.requestId"}
                },
                "UpdateExpression": "set description = :description, #dt = :dt, #email = :email",
                "ExpressionAttributeValues": {
                  ":description": {"S": "$input.path('$.description')"},
                  ":dt": {"S": "$input.path('$.datetime')"},
                  ":email": {"S": "$input.path('$.email')"}
                },
                "ExpressionAttributeNames": {
                  "#dt": "datetime",
                  "#email": "email"
                },
                "ReturnValues": "ALL_NEW"
              }
        responses:
          default:
            statusCode: "200"
            responseTemplates:
              application/json: |
                #set($inputRoot = $input.path('$'))
                {
                  "message": "Item created successfully",
                  "data": {
                    "id": "$inputRoot.Attributes.id.S",
                    "description": "$inputRoot.Attributes.description.S",
                    "datetime": "$inputRoot.Attributes.datetime.S"
                  }
                }
        type: "aws"
    ## List: Scan with #foreach to build JSON array
    get:
      x-amazon-apigateway-integration:
        credentials:
          Fn::GetAtt: [APIGatewayDynamoDBRole, Arn]
        httpMethod: "POST"
        uri:
          Fn::Sub: "arn:aws:apigateway:${AWS::Region}:dynamodb:action/Scan"
        requestTemplates:
          application/json:
            Fn::Sub: |
              #set($startKey = $input.params('startKey'))
              {
                "TableName": "${MyTable}",
                "Limit": 25
                #if($startKey != "")
                ,"ExclusiveStartKey": {"id": {"S": "$startKey"}}
                #end
              }
        responses:
          default:
            statusCode: "200"
            responseTemplates:
              application/json: |
                #set($inputRoot = $input.path('$'))
                {
                  "items": [
                  #foreach($elem in $inputRoot.Items)
                    {
                      "id": "$elem.id.S",
                      "description": "$elem.description.S",
                      "datetime": "$elem.datetime.S"
                    }#if($foreach.hasNext),#end
                  #end
                  ]
                  #if($inputRoot.LastEvaluatedKey.id.S != "")
                  ,"nextKey": "$inputRoot.LastEvaluatedKey.id.S"
                  #end
                }
        type: "aws"
  /items/{id}:
    ## Read
    get:
      parameters:
        - name: "id"
          in: "path"
          required: true
          schema:
            type: "string"
      x-amazon-apigateway-integration:
        credentials:
          Fn::GetAtt: [APIGatewayDynamoDBRole, Arn]
        httpMethod: "POST"
        uri:
          Fn::Sub: "arn:aws:apigateway:${AWS::Region}:dynamodb:action/GetItem"
        requestTemplates:
          application/json:
            Fn::Sub: |
              {
                "TableName": "${MyTable}",
                "Key": {
                  "id": {"S": "$input.params().path.id"}
                }
              }
        responses:
          default:
            statusCode: "200"
            responseTemplates:
              application/json: |
                #set($inputRoot = $input.path('$'))
                {
                  "id": "$inputRoot.Item.id.S",
                  "description": "$inputRoot.Item.description.S",
                  "datetime": "$inputRoot.Item.datetime.S"
                }
        type: "aws"
    ## Delete: returns deleted item via ReturnValues: ALL_OLD
    delete:
      parameters:
        - name: "id"
          in: "path"
          required: true
          schema:
            type: "string"
      x-amazon-apigateway-integration:
        credentials:
          Fn::GetAtt: [APIGatewayDynamoDBRole, Arn]
        httpMethod: "POST"
        uri:
          Fn::Sub: "arn:aws:apigateway:${AWS::Region}:dynamodb:action/DeleteItem"
        requestTemplates:
          application/json:
            Fn::Sub: |
              {
                "TableName": "${MyTable}",
                "Key": {
                  "id": {"S": "$input.params().path.id"}
                },
                "ReturnValues": "ALL_OLD"
              }
        responses:
          default:
            statusCode: "200"
            responseTemplates:
              application/json: |
                #set($inputRoot = $input.path('$'))
                {
                  "message": "Item deleted successfully",
                  "data": {
                    "id": "$inputRoot.Attributes.id.S",
                    "description": "$inputRoot.Attributes.description.S"
                  }
                }
        type: "aws"
components:
  schemas:
    item:
      required: [description, datetime, email]
      type: object
      properties:
        description:
          type: string
        datetime:
          type: string
          format: date-time
        email:
          type: string
          format: email
x-amazon-apigateway-gateway-responses:
  BAD_REQUEST_BODY:
    statusCode: 400
    responseTemplates:
      application/json: '{"error": "$context.error.validationErrorString"}'
x-amazon-apigateway-request-validators:
  Validate body:
    validateRequestParameters: false
    validateRequestBody: true
```

### Option B: Inline CloudFormation methods (simpler for small APIs)

```yaml
## Single-method example: use Option A for full CRUD APIs
DynamoDbGetIntegration:
  Type: AWS::ApiGateway::Method
  Properties:
    HttpMethod: GET
    ResourceId: !Ref ItemResource
    RestApiId: !Ref MyRestApi
    AuthorizationType: CUSTOM
    AuthorizerId: !Ref MyAuthorizer
    RequestParameters:
      method.request.path.id: true
    Integration:
      Type: AWS
      IntegrationHttpMethod: POST
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:dynamodb:action/GetItem"
      Credentials: !GetAtt DynamoDbRole.Arn
      RequestTemplates:
        application/json: !Sub |
          {
            "TableName": "${MyTable}",
            "Key": {
              "id": {"S": "$input.params('id')"}
            }
          }
      IntegrationResponses:
        - StatusCode: "200"
          ResponseTemplates:
            application/json: |
              #set($item = $input.path('$.Item'))
              {
                "id": "$item.id.S",
                "data": "$item.data.S",
                "createdAt": "$item.createdAt.S"
              }
    MethodResponses:
      - StatusCode: "200"
```

## Direct AWS Service Integration (Kinesis Data Streams)

Based on [aws-samples/serverless-patterns/apigw-kinesis-lambda](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-kinesis-lambda). Uses REST API resources with path parameter for stream name and Lambda as stream consumer.

```yaml
KinesisStream:
  Type: AWS::Kinesis::Stream
  Properties:
    ShardCount: 1

APIGatewayRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: apigateway.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: APIGWKinesisPolicy
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action:
                - kinesis:PutRecord
                - kinesis:PutRecords
              Resource: !Sub "${KinesisStream.Arn}*"

Api:
  Type: AWS::ApiGateway::RestApi
  Properties:
    Name: apigw-kinesis-api

## Resources: /streams/{stream-name}/record and /streams/{stream-name}/records
## (resource definitions omitted for brevity)

## PutRecord: single record ingestion
recordMethodPut:
  Type: AWS::ApiGateway::Method
  Properties:
    RestApiId: !Ref Api
    ResourceId: !Ref record
    HttpMethod: PUT
    AuthorizationType: NONE
    Integration:
      Type: AWS
      Credentials: !GetAtt APIGatewayRole.Arn
      IntegrationHttpMethod: POST
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:kinesis:action/PutRecord"
      PassthroughBehavior: WHEN_NO_TEMPLATES
      RequestTemplates:
        application/json: |
          {
            "StreamName": "$input.params('stream-name')",
            "Data": "$util.base64Encode($input.json('$.Data'))",
            "PartitionKey": "$input.path('$.PartitionKey')"
          }
      IntegrationResponses:
        - StatusCode: "200"
    MethodResponses:
      - StatusCode: "200"

## PutRecords: batch ingestion with #foreach
recordsMethodPut:
  Type: AWS::ApiGateway::Method
  Properties:
    RestApiId: !Ref Api
    ResourceId: !Ref records
    HttpMethod: PUT
    AuthorizationType: NONE
    Integration:
      Type: AWS
      Credentials: !GetAtt APIGatewayRole.Arn
      IntegrationHttpMethod: POST
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:kinesis:action/PutRecords"
      PassthroughBehavior: WHEN_NO_TEMPLATES
      RequestTemplates:
        application/json: |
          {
            "StreamName": "$input.params('stream-name')",
            "Records": [
              #foreach($elem in $input.path('$.records'))
              {
                "Data": "$util.base64Encode($elem.data)",
                "PartitionKey": "$elem.partition-key"
              }#if($foreach.hasNext),#end
              #end
            ]
          }
      IntegrationResponses:
        - StatusCode: "200"
    MethodResponses:
      - StatusCode: "200"

## Lambda consumer triggered by Kinesis stream
LambdaConsumer:
  Type: AWS::Serverless::Function
  Properties:
    Handler: lambda_function.lambda_handler
    Runtime: python3.13
    CodeUri: src/
    Policies:
      - KinesisStreamReadPolicy:
          StreamName: !Ref KinesisStream
    Events:
      Stream:
        Type: Kinesis
        Properties:
          Stream: !GetAtt KinesisStream.Arn
          StartingPosition: LATEST
          BatchSize: 100
```

## Direct AWS Service Integration (Step Functions)

REST API pattern based on [aws-samples/serverless-patterns/apigw-rest-stepfunction](https://github.com/aws-samples/serverless-patterns/tree/main/apigw-rest-stepfunction). WebSocket pattern based on [aws-samples/serverless-samples/apigw-ws-integrations](https://github.com/aws-samples/serverless-samples/tree/main/apigw-ws-integrations).

### REST API: Standard workflow (async, fire-and-forget with polling)

```yaml
WaitableStateMachine:
  Type: AWS::Serverless::StateMachine
  Properties:
    DefinitionUri: statemachine/workflow.asl.json
    DefinitionSubstitutions:
      DDBTable: !Ref StatusTable
    Policies:
      - DynamoDBWritePolicy:
          TableName: !Ref StatusTable

StatusTable:
  Type: AWS::Serverless::SimpleTable
  Properties:
    PrimaryKey:
      Name: Id
      Type: String

ApiGatewayStepFunctionsRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: apigateway.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: CallStepFunctions
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action: states:StartExecution
              Resource: !Ref WaitableStateMachine

StartExecutionMethod:
  Type: AWS::ApiGateway::Method
  Properties:
    RestApiId: !Ref Api
    ResourceId: !GetAtt Api.RootResourceId
    HttpMethod: POST
    AuthorizationType: NONE
    Integration:
      Type: AWS
      IntegrationHttpMethod: POST
      Credentials: !GetAtt ApiGatewayStepFunctionsRole.Arn
      Uri: !Sub "arn:aws:apigateway:${AWS::Region}:states:action/StartExecution"
      PassthroughBehavior: WHEN_NO_TEMPLATES
      RequestTemplates:
        application/json: !Sub
          - |-
            #set($data = $util.escapeJavaScript($input.json('$')))
            {
              "input": "$data",
              "stateMachineArn": "${StateMachineArn}"
            }
          - StateMachineArn: !Ref WaitableStateMachine
      IntegrationResponses:
        - StatusCode: "200"
          ResponseTemplates:
            application/json: ''
    MethodResponses:
      - StatusCode: "200"
        ResponseModels:
          application/json: Empty
```

### WebSocket API: Express workflow (sync) and Standard workflow (async with callback)

```yaml
## Express workflow: synchronous, returns result to WebSocket client
SyncSFn:
  Type: AWS::Serverless::StateMachine
  Properties:
    Type: EXPRESS
    Definition:
      StartAt: ProcessRequest
      States:
        ProcessRequest:
          Type: Wait
          Seconds: 5
          End: true

SFnSyncRouteIntegration:
  Type: AWS::ApiGatewayV2::Integration
  Properties:
    ApiId: !Ref WebSocketApi
    IntegrationType: AWS
    IntegrationMethod: POST
    IntegrationUri: !Sub "arn:aws:apigateway:${AWS::Region}:states:action/StartSyncExecution"
    CredentialsArn: !GetAtt StepFunctionsSyncExecutionRole.Arn
    TemplateSelectionExpression: \$default
    RequestTemplates:
      "$default":
        Fn::Sub: >
          #set($sfn_input=$util.escapeJavaScript($input.json("$.data")).replaceAll("\\'","'"))
          {
            "input": "$sfn_input",
            "stateMachineArn": "${SyncSFn}"
          }

## Standard workflow: async, pushes result back via @connections API
AsyncSFn:
  Type: AWS::Serverless::StateMachine
  Properties:
    Type: STANDARD
    Definition:
      StartAt: ProcessRequest
      States:
        ProcessRequest:
          Type: Wait
          Seconds: 5
          Next: NotifyClient
        NotifyClient:
          Type: Task
          Resource: arn:aws:states:::apigateway:invoke
          Parameters:
            ApiEndpoint: !Sub "${WebSocketApi}.execute-api.${AWS::Region}.amazonaws.com"
            Method: POST
            Stage: !Ref ApiStageName
            Path.$: "States.Format('/@connections/{}', $.ConnectionID)"
            RequestBody:
              Message: Processing complete!
            AuthType: IAM_ROLE
          End: true

SFnAsyncRouteIntegration:
  Type: AWS::ApiGatewayV2::Integration
  Properties:
    ApiId: !Ref WebSocketApi
    IntegrationType: AWS
    IntegrationMethod: POST
    IntegrationUri: !Sub "arn:aws:apigateway:${AWS::Region}:states:action/StartExecution"
    CredentialsArn: !GetAtt StepFunctionsAsyncExecutionRole.Arn
    TemplateSelectionExpression: \$default
    RequestTemplates:
      "$default":
        Fn::Sub: >
          #set($sfn_input=$util.escapeJavaScript($input.json("$.data")).replaceAll("\\'","'"))
          {
            "input": "{\"data\":$sfn_input, \"ConnectionID\":\"$context.connectionId\"}",
            "stateMachineArn": "${AsyncSFn}"
          }

## Async workflow role needs @connections permission to push results back
AsyncSFnRole:
  Type: AWS::IAM::Role
  Properties:
    AssumeRolePolicyDocument:
      Version: "2012-10-17"
      Statement:
        - Effect: Allow
          Principal:
            Service: states.amazonaws.com
          Action: sts:AssumeRole
    Policies:
      - PolicyName: APIGWConnectionsAccess
        PolicyDocument:
          Version: "2012-10-17"
          Statement:
            - Effect: Allow
              Action: execute-api:ManageConnections
              Resource: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${WebSocketApi}/${ApiStageName}/POST/@connections/*"
```
