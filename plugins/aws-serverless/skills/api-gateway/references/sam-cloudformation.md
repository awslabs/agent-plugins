# SAM and CloudFormation Patterns

## Table of Contents

- [OpenAPI Extensions](#openapi-extensions)
- [Common SAM Patterns](#common-sam-patterns)
  - [Custom Domain with Base Path Mapping](#custom-domain-with-base-path-mapping)
- [Infrastructure Patterns](#infrastructure-patterns)
  - [Private API with VPC Endpoint](#private-api-with-vpc-endpoint)
  - [Gateway Responses with CORS Headers](#gateway-responses-with-cors-headers)
  - [Response Streaming](#response-streaming)
  - [Routing Rules](#routing-rules)
- [Key Pitfalls](#key-pitfalls)
- [VTL Mapping Templates (REST API)](#vtl-mapping-templates-rest-api)
- [HTTP API Parameter Mapping](#http-api-parameter-mapping)
- [Binary Data Handling](#binary-data-handling)

For direct AWS service integration templates (EventBridge, SQS, DynamoDB, Kinesis, Step Functions), see `references/sam-service-integrations.md`.

---

## OpenAPI Extensions

Define API Gateway configuration inline in OpenAPI specs:

| Extension                                      | Purpose                                                      |
| ---------------------------------------------- | ------------------------------------------------------------ |
| `x-amazon-apigateway-integration`              | Integration configuration (Lambda, HTTP, AWS service, mock)  |
| `x-amazon-apigateway-request-validators`       | Request validation rules                                     |
| `x-amazon-apigateway-binary-media-types`       | Binary content type registration                             |
| `x-amazon-apigateway-gateway-responses`        | Custom error responses                                       |
| `x-amazon-apigateway-cors`                     | HTTP API CORS configuration                                  |
| `x-amazon-apigateway-endpoint-configuration`   | Endpoint type, VPC endpoint IDs, `disableExecuteApiEndpoint` |
| `x-amazon-apigateway-authorizer`               | Authorizer definitions                                       |
| `x-amazon-apigateway-policy`                   | Embedded resource policy                                     |
| `x-amazon-apigateway-minimum-compression-size` | Payload compression threshold                                |
| `x-amazon-apigateway-integrations`             | Reusable integration components (HTTP API only)              |
| `x-amazon-apigateway-importexport-version`     | OpenAPI 3.0 export format version                            |

## Common SAM Patterns

For basic Lambda proxy and auth SAM templates (JWT authorizer, Cognito authorizer, Lambda authorizer, API keys), see the [aws-lambda web-app-deployment reference](../../aws-lambda/references/web-app-deployment.md).

### Custom Domain with Base Path Mapping

```yaml
MyDomain:
  Type: AWS::ApiGatewayV2::DomainName
  Properties:
    DomainName: api.example.com
    DomainNameConfigurations:
      - EndpointType: REGIONAL
        CertificateArn: !Ref MyCertificate

MyMapping:
  Type: AWS::ApiGatewayV2::ApiMapping
  Properties:
    DomainName: !Ref MyDomain
    ApiId: !Ref MyApi
    Stage: !Ref MyStage
    ApiMappingKey: v1/orders
```

## Infrastructure Patterns

### Private API with VPC Endpoint

```yaml
MyApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: prod
    EndpointConfiguration:
      Type: PRIVATE
      VPCEndpointIds:
        - !Ref VpcEndpoint
    Auth:
      ResourcePolicy:
        CustomStatements:
          - Effect: Allow
            Principal: "*"
            Action: execute-api:Invoke
            Resource: execute-api:/*
            Condition:
              StringEquals:
                aws:SourceVpce: !Ref VpcEndpoint
```

### Gateway Responses with CORS Headers

```yaml
MyApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: Prod
    Cors:
      AllowMethods: "'GET,POST,OPTIONS'"
      AllowHeaders: "'Content-Type,Authorization'"
      AllowOrigin: "'https://example.com'"
    GatewayResponses:
      DEFAULT_4XX:
        ResponseParameters:
          Headers:
            Access-Control-Allow-Origin: "'https://example.com'"
            Access-Control-Allow-Headers: "'Content-Type,Authorization'"
      DEFAULT_5XX:
        ResponseParameters:
          Headers:
            Access-Control-Allow-Origin: "'https://example.com'"
            Access-Control-Allow-Headers: "'Content-Type,Authorization'"
```

### Response Streaming

```yaml
MyFunction:
  Type: AWS::Serverless::Function
  Properties:
    Handler: app.handler
    Runtime: nodejs20.x
    Events:
      Stream:
        Type: Api
        Properties:
          Path: /stream
          Method: get
          RestApiId: !Ref MyApi

MyApi:
  Type: AWS::Serverless::Api
  Properties:
    StageName: Prod
    DefinitionBody:
      openapi: "3.0"
      paths:
        /stream:
          get:
            x-amazon-apigateway-integration:
              type: aws_proxy
              httpMethod: POST
              uri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${MyFunction.Arn}/invocations"
              responseTransferMode: STREAM
```

### Routing Rules

```yaml
# Based on https://github.com/aws-samples/serverless-samples/blob/main/apigw-header-routing/template-header-based-routing.yaml
MyRoutingRule:
  Type: AWS::ApiGatewayV2::RoutingRule
  Properties:
    DomainNameArn: !Sub "arn:aws:apigateway:${AWS::Region}::/domainnames/${MyDomain}"
    Priority: 100
    Conditions:
      - MatchHeaders:
          AnyOf:
            - Header: X-API-Version
              ValueGlob: "v2*"
    Actions:
      - InvokeApi:
          ApiId: !Ref MyV2Api
          Stage: prod
          StripBasePath: false
```

## Key Pitfalls

For general SAM/CloudFormation pitfalls (circular dependencies, `!Sub` defaults, YAML duplicate keys, build issues, layer nesting, `confirm_changeset`), see the [aws-serverless-deployment skill](../../aws-serverless-deployment/).

API-Gateway-specific pitfalls:

1. **Root-level `security` in OpenAPI is ignored**. Must set per-operation
2. **`$ref` cannot reference external files** in OpenAPI; only internal references (`#/definitions/` for Swagger 2.0, `#/components/schemas/` for OpenAPI 3.0)
3. **JSON Schema draft 4 only**: no `discriminator`, `nullable`, `exclusiveMinimum`, no `oneOf`/`anyOf`/`allOf` with `$ref` in same schema

## VTL Mapping Templates (REST API)

### Key Variables

- `$input.body`: Raw request body
- `$input.json('$.jsonpath')`: Extract JSON
- `$input.path('$.jsonpath')`: Extract as object
- `$input.params('name')`: Get parameter by name
- `$input.params().header`, `.querystring`, `.path`: Parameter maps
- `$context.*`: Request context
- `$stageVariables.*`: Stage variables
- `$util.escapeJavaScript()`, `$util.parseJson()`, `$util.urlEncode()`, `$util.base64Encode()`, `$util.base64Decode()`

### Limits

- Template size: 300 KB
- `#foreach` iterations: 1,000

### Passthrough Behavior

- `WHEN_NO_MATCH`: Pass through when no template matches Content-Type
- `WHEN_NO_TEMPLATES`: Pass through when no templates defined
- `NEVER`: Reject with 415 Unsupported Media Type

### Response Override

```velocity
#set($context.responseOverride.status = 400)
#set($context.responseOverride.header.X-Custom = "value")
```

**Gotcha**: Applying override to same parameter twice causes 5XX

## HTTP API Parameter Mapping

No VTL. Simple expressions:

- `$request.header.name`, `$request.querystring.name`, `$request.body.jsonpath`, `$request.path.name`
- `$context.*`, `$stageVariables.*`
- Actions: `overwrite`, `append`, `remove`

## Binary Data Handling

### REST API

- Register binary media types (e.g., `image/png`, `*/*`)
- `contentHandling` on Integration/IntegrationResponse: `CONVERT_TO_BINARY` or `CONVERT_TO_TEXT`
- Lambda proxy: `isBase64Encoded: true` in response; request body arrives as base64 when binary
- Only the first `Accept` media type is honored

### HTTP API

- Payload format 2.0: `isBase64Encoded` in request event automatically. Lambda returns `isBase64Encoded: true`
- No need to register binary media types explicitly
