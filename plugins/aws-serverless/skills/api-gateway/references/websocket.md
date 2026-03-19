# WebSocket API

## Route Selection

- `$connect`: Called when client connects; authorization is enforced only at connection time. Once connected, all subsequent messages bypass authorization checks. Lambda authorizer's cached policy must cover all routes the client will access during the connection lifetime
- `$disconnect`: Best-effort delivery when client disconnects
- `$default`: Fallback for unmatched messages
- Custom routes: Matched by `routeSelectionExpression` (e.g., `$request.body.action`)

## @connections Management API

- `POST @connections/{connectionId}`: Send message to client
- `GET @connections/{connectionId}`: Get connection info
- `DELETE @connections/{connectionId}`: Disconnect client
- IAM action: `execute-api:ManageConnections`

## Session Management

- Store connectionId **together with user ID** in DynamoDB on `$connect`. When a user reconnects (new connectionId), update the mapping (the user ID stays the same; only the connectionId changes). This allows the session to continue seamlessly across reconnects, network drops, and the 2-hour connection limit
- Use a GSI on user ID to look up the current connectionId for a given user (e.g., to send a targeted message to a specific user regardless of which connectionId they currently hold)
- Use DynamoDB TTL to clean up stale connections
- For anonymous users: client generates random user ID, sends via `Sec-WebSocket-Protocol` header
- Backend should echo `Sec-WebSocket-Protocol` in response, as many browser clients will reject the connection if a requested subprotocol is not echoed back
- Handle `GoneException` from `post_to_connection` to detect stale connections

## Client Resilience Best Practices

- **Automatic reconnect**: Clients must implement reconnect logic with exponential backoff to handle network interruptions, server-side disconnects, and the 2-hour maximum connection duration limit. The connection will be dropped at 2 hours regardless of activity. Clients should treat this as expected and reconnect transparently
- **Heartbeat / keep-alive**: Clients should send a periodic heartbeat message (e.g., every 5-9 minutes) to prevent the 10-minute idle timeout from closing the connection. Use a lightweight message on `$default` or a dedicated `heartbeat` route. Without heartbeats, idle connections are silently closed and the client may not detect the drop until the next send fails
- **Connection state recovery**: On reconnect, clients should re-authenticate and restore application state (e.g., re-subscribe to topics, re-join rooms). Store enough context client-side to resume without data loss

## SAM Template: Basic WebSocket API

```yaml
WebSocketApi:
  Type: AWS::ApiGatewayV2::Api
  Properties:
    Name: !Sub "${AWS::StackName}-ws"
    ProtocolType: WEBSOCKET
    RouteSelectionExpression: "$request.body.action"

ConnectRoute:
  Type: AWS::ApiGatewayV2::Route
  Properties:
    ApiId: !Ref WebSocketApi
    RouteKey: $connect
    AuthorizationType: NONE
    Target: !Sub "integrations/${ConnectIntegration}"

ConnectIntegration:
  Type: AWS::ApiGatewayV2::Integration
  Properties:
    ApiId: !Ref WebSocketApi
    IntegrationType: AWS_PROXY
    IntegrationUri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${ConnectFunction.Arn}/invocations"

ConnectPermission:
  Type: AWS::Lambda::Permission
  Properties:
    Action: lambda:InvokeFunction
    FunctionName: !Ref ConnectFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${WebSocketApi}/*/$connect"

DisconnectRoute:
  Type: AWS::ApiGatewayV2::Route
  Properties:
    ApiId: !Ref WebSocketApi
    RouteKey: $disconnect
    Target: !Sub "integrations/${DisconnectIntegration}"

DisconnectIntegration:
  Type: AWS::ApiGatewayV2::Integration
  Properties:
    ApiId: !Ref WebSocketApi
    IntegrationType: AWS_PROXY
    IntegrationUri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${DisconnectFunction.Arn}/invocations"

DisconnectPermission:
  Type: AWS::Lambda::Permission
  Properties:
    Action: lambda:InvokeFunction
    FunctionName: !Ref DisconnectFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${WebSocketApi}/*/$disconnect"

DefaultRoute:
  Type: AWS::ApiGatewayV2::Route
  Properties:
    ApiId: !Ref WebSocketApi
    RouteKey: $default
    Target: !Sub "integrations/${DefaultIntegration}"

DefaultIntegration:
  Type: AWS::ApiGatewayV2::Integration
  Properties:
    ApiId: !Ref WebSocketApi
    IntegrationType: AWS_PROXY
    IntegrationUri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${MessageFunction.Arn}/invocations"

DefaultPermission:
  Type: AWS::Lambda::Permission
  Properties:
    Action: lambda:InvokeFunction
    FunctionName: !Ref MessageFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${WebSocketApi}/*/$default"

Stage:
  Type: AWS::ApiGatewayV2::Stage
  Properties:
    ApiId: !Ref WebSocketApi
    StageName: prod
    AutoDeploy: true
```

## Lambda: Sending Messages via @connections

```python
import boto3
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()

def send_to_connection(domain_name, stage, connection_id, message):
    """Send a message to a WebSocket client."""
    apigw = boto3.client(
        "apigatewaymanagementapi",
        endpoint_url=f"https://{domain_name}/{stage}"
    )
    try:
        apigw.post_to_connection(
            ConnectionId=connection_id,
            Data=message.encode("utf-8")
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "GoneException":
            logger.info("Connection %s is gone, cleaning up", connection_id)
            # Remove stale connection from DynamoDB
            return False
        raise
    return True
```

## Limits

- Frame size: 32 KB, message payload: 128 KB
- Connection duration: 2 hours, idle timeout: 10 minutes
- New connections: 500/s (adjustable), routes: 300
- **Route-level throttling**: Configure `ThrottlingBurstLimit` and `ThrottlingRateLimit` per route via stage `RouteSettings` to protect backend integrations from message floods. Cannot exceed account-level limit
- Account-level throttle: 10,000 rps / 5,000 burst for WebSocket `@connections` callback, per region (adjustable)
- These are default quotas; check [latest limits](https://docs.aws.amazon.com/apigateway/latest/developerguide/limits.html) and request increases as needed

## Pricing

- Connection minutes: charged per minute of connection time
- Messages: charged per million messages (both sent and received)
- The @connections callback API messages count toward message charges
- No minimum fees or upfront commitments
- See [API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/) for current rates

## Multi-Region WebSocket

- DynamoDB Global Tables for connection state tracking
- Route 53 latency-based or geo-based routing for initial connection
- ConnectionId is region-specific; messages must be sent via the region that owns the connection
- Cross-region message propagation via EventBridge or DynamoDB Streams + Lambda

## Related Templates

- **Basic WebSocket SAM template**: See above
- **Step Functions integration (sync Express + async with @connections callback)**: See `references/sam-service-integrations.md` (Step Functions section)
- **WebSocket access log format**: See `references/observability-logging.md` (WebSocket API Access Log Format section)
