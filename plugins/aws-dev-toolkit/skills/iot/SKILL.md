---
name: iot
description: Deep-dive into AWS IoT architecture, device connectivity, edge computing, and fleet management. This skill should be used when the user asks to "design an IoT solution", "connect devices to AWS", "set up MQTT messaging", "configure IoT rules", "provision a device fleet", "use Greengrass at the edge", "build a device shadow", "set up IoT security", "manage OTA updates", "store telemetry data", "create IoT topic rules", "configure fleet provisioning", or mentions IoT Core, MQTT, Greengrass, Device Shadow, IoT Rules Engine, IoT Events, IoT SiteWise, fleet indexing, or device certificates.
---

Specialist guidance for AWS IoT. Covers IoT Core (MQTT, shadows, rules engine), Greengrass v2 edge compute, fleet provisioning, security, data storage patterns, and fleet management.

## Process

1. Identify the IoT workload characteristics: device count, message frequency, payload size, connectivity (always-on vs intermittent), edge processing needs
2. Use the `aws-docs` MCP tools to verify current IoT Core limits, Greengrass component versions, and service quotas
3. Select the appropriate IoT services using the decision matrix below
4. Design the communication and data ingestion topology (protocols, topics, rules)
5. Configure security (X.509 certificates, IoT policies, fleet provisioning method)
6. Design data storage and analytics pipeline
7. Plan fleet management (jobs, indexing, Device Defender)
8. Recommend operational best practices (monitoring, OTA updates, edge deployments)

## IoT Service Selection Decision Matrix

| Requirement | Recommendation | Why |
|---|---|---|
| Devices sending telemetry to cloud | IoT Core (MQTT) | Persistent connections, sub-second latency, bidirectional, scales to millions of concurrent connections |
| Request/response from constrained devices | IoT Core (HTTPS) | Stateless, no persistent connection needed, but higher latency and no server-to-device push |
| Browser or mobile app to IoT backend | IoT Core (MQTT over WebSocket) | Works through firewalls/proxies, uses IAM or Cognito auth instead of X.509 certificates |
| Edge preprocessing before cloud upload | Greengrass v2 | Reduces bandwidth cost and cloud ingestion volume by filtering/aggregating at the edge |
| Local device control when internet is down | Greengrass v2 | Local MQTT broker keeps device-to-device communication working during cloud disconnection |
| Industrial OPC-UA data collection | IoT SiteWise | Purpose-built for industrial protocols, asset modeling, and time-series with SiteWise Edge gateway |
| State machine on device events | IoT Events | Detector models react to patterns across multiple devices without custom Lambda logic |
| Time-series telemetry storage | Timestream | Purpose-built for time-series with automatic tiering (memory to magnetic), built-in interpolation and aggregation functions |
| Device metadata and state lookups | DynamoDB | Single-digit ms latency for key-value access to device config, state, and registry data |
| Bulk telemetry archival | S3 | Cheapest storage for raw telemetry; query with Athena when needed |
| Telemetry search and dashboards | OpenSearch | Full-text search and Kibana/OpenSearch Dashboards for operational visibility |

## Protocol Selection

### MQTT (Default Choice)

Use MQTT for device-to-cloud communication unless there is a specific reason not to. MQTT uses persistent TCP connections with minimal overhead (2-byte header minimum), supports QoS 0 (at most once) and QoS 1 (at least once), and enables server-initiated push to devices via subscriptions.

- **QoS 0**: Use for high-frequency telemetry where occasional message loss is acceptable (sensor readings every second). Lower overhead because no acknowledgment round-trip.
- **QoS 1**: Use for commands, configuration changes, and alerts where delivery must be confirmed. The broker retries until PUBACK is received.
- **QoS 2 is not supported** by AWS IoT Core. If exactly-once semantics are required, implement idempotency in the application layer.

### MQTT v5 Features (Prefer When Devices Support It)

- **Shared subscriptions**: Distribute messages across multiple subscribers for load balancing backend processors, avoiding hot-partition on a single consumer
- **Topic aliases**: Replace long topic strings with short integer aliases after first publish, reducing per-message overhead for bandwidth-constrained devices
- **Message expiry**: Set TTL on messages so stale commands are discarded rather than delivered to a device that reconnects hours later
- **Session expiry**: Control how long the broker holds session state after disconnect, preventing unbounded memory growth from abandoned devices

### HTTPS

Use HTTPS only for devices that wake up, send a single reading, and sleep (battery-powered sensors with cellular connectivity). HTTPS does not support subscriptions, so the device cannot receive commands without polling. Every request incurs TLS handshake overhead.

### MQTT over WebSocket

Use for browser-based dashboards and mobile apps that need real-time device data. Authenticates with IAM credentials or Cognito identity pools instead of X.509 certificates. Works through corporate proxies and firewalls that block raw TCP on port 8883.

## Topic Design

Design topics as a hierarchy with device identity and data type segments. This enables fine-grained IoT policy access control and targeted rules engine subscriptions.

### Recommended Structure

```
{org}/{environment}/{device-type}/{device-id}/{data-category}
```

Examples:
```
acme/prod/temperature-sensor/sensor-001/telemetry
acme/prod/temperature-sensor/sensor-001/alerts
acme/prod/temperature-sensor/sensor-001/commands
acme/prod/temperature-sensor/+/telemetry        # Rule subscribes to all sensors
```

### Topic Design Rules

- Include the device ID in the topic so IoT policies can use `${iot:Connection.Thing.ThingName}` to restrict each device to its own topics
- Separate telemetry, commands, and alerts into distinct subtopics so rules can target specific data types without parsing payloads
- Use `+` (single-level) and `#` (multi-level) wildcards in rules and subscriptions, never in publish topics
- Keep topics under 7 levels deep to stay within IoT Core limits and maintain readability

### Basic Ingest

For high-volume telemetry that goes directly to rules engine actions without needing the message broker, use the `$aws/rules/<rule-name>` topic prefix. Basic Ingest skips the message broker publish cost ($1.00 per million messages), saving significant cost at scale. The tradeoff: messages sent via Basic Ingest cannot be received by other MQTT subscribers.

## Device Shadow

Device Shadow maintains a JSON document of desired and reported state for each device. Use shadows when cloud applications need to read or set device state regardless of whether the device is currently connected.

### Classic vs Named Shadows

- **Classic shadow**: One per thing. Use for the primary device state (power on/off, firmware version, connectivity status).
- **Named shadows**: Up to 10 per thing. Use to separate independent state concerns (e.g., one shadow for configuration, another for diagnostics, another for firmware). Named shadows avoid state conflicts when multiple applications update different aspects of the same device.

### Shadow Best Practices

- Keep shadow documents small (<8 KB). Large shadows increase MQTT message size and DynamoDB read/write costs on the shadow service backend.
- Use `reported` state from the device, `desired` state from the cloud application. The `delta` field tells the device what to change.
- Set version-based optimistic locking on updates to prevent stale writes from overwriting newer state.

## IoT Rules Engine

The rules engine evaluates SQL statements against incoming MQTT messages and routes matching data to AWS service actions. Every production deployment should have at least one rule for data ingestion and error handling.

### Rule SQL Basics

```sql
SELECT temperature, humidity, timestamp() as ts, topic(4) as device_id
FROM 'acme/prod/temperature-sensor/+/telemetry'
WHERE temperature > 0 AND temperature < 150
```

- `topic(n)` extracts the nth level from the topic string (1-indexed)
- `timestamp()` adds server-side UTC timestamp
- `WHERE` clause filters before action execution, reducing downstream processing cost
- Use `SELECT *` sparingly; extract only the fields needed to minimize action payload size

### Action Selection Guide

| Data Destination | Rule Action | When to Use |
|---|---|---|
| Real-time processing | Lambda | Custom transformation, enrichment, or fan-out logic |
| Time-series storage | Timestream | Telemetry that needs time-range queries and aggregation |
| Key-value lookups | DynamoDB / DynamoDBv2 | Device metadata, latest state, configuration |
| Streaming analytics | Kinesis Data Streams | High-throughput ingestion for real-time analytics pipelines |
| Bulk archival | S3 | Raw telemetry archival for compliance or batch analytics |
| Notifications | SNS | Alert routing to email, SMS, or HTTP endpoints |
| Decoupled processing | SQS | Buffer messages for downstream consumers that process at their own rate |
| State machine triggers | IoT Events | Multi-device event correlation and complex event processing |
| Republish | IoT Core republish | Route to another MQTT topic for device-to-device via cloud |
| Search and dashboards | OpenSearch | Operational dashboards and full-text search over telemetry |

### Error Actions (Always Configure)

Every rule must have an error action. Without one, failed rule actions silently drop data with no notification and no retry. Configure error actions to route failures to S3 or SQS for later reprocessing.

See `references/rules-engine-patterns.md` for detailed SQL examples and error action configuration.

## IoT SiteWise (Industrial IoT)

Use IoT SiteWise instead of raw IoT Core + custom storage when the workload involves industrial equipment with OPC-UA data sources, asset hierarchies, and time-series metrics that need automatic aggregation (min, max, avg, count over time windows).

### When to Use IoT SiteWise

- Industrial environments with OPC-UA or Modbus data sources
- Need for asset hierarchy modeling (factory > line > machine > sensor)
- Pre-built portal/dashboard capabilities for operators (SiteWise Monitor)
- Edge data collection and processing via SiteWise Edge gateway

### When to Skip IoT SiteWise

- Consumer IoT devices using MQTT natively (use IoT Core directly)
- Custom data formats that do not fit the asset model structure
- Workloads already using Timestream with custom dashboards (Grafana)

## IoT Events

Use IoT Events when device telemetry needs to trigger state-machine logic across multiple devices or time windows, and the logic is too complex for simple IoT Rules Engine WHERE clauses.

### Detector Models

- Define states (e.g., NORMAL, WARNING, CRITICAL) with transitions based on input conditions
- Each detector instance tracks state for one device independently
- Actions on state entry/exit/transition: send SNS, publish to IoT Core, invoke Lambda, write to DynamoDB
- Use for: equipment health monitoring, multi-sensor correlation, threshold-with-hysteresis alerting (avoid alert flapping by requiring sustained condition before state change)

## Fleet Provisioning

### Method Selection

| Scenario | Method | Why |
|---|---|---|
| Factory installs unique certs per device | JITP (Just-in-Time Provisioning) | Simplest: device connects, CA is recognized, thing is auto-created. Requires trusted manufacturing chain. |
| Factory installs unique certs, need custom validation | JITR (Just-in-Time Registration) | Lambda hook validates additional attributes before activating the certificate |
| Cannot install unique certs during manufacturing | Fleet Provisioning by Claim | Devices share a claim certificate, exchange it for a unique identity on first boot. Use pre-provisioning Lambda hook to validate serial numbers against an allow-list. |
| End user or installer provisions device | Fleet Provisioning by Trusted User | Mobile app generates temporary credentials for the device. Highest security for consumer devices. |

### Provisioning Best Practices

- Always use a pre-provisioning Lambda hook with fleet provisioning by claim to validate the device identity against an allow-list. Without this, anyone with the claim certificate can provision unlimited devices.
- Scope provisioning templates to create minimal IoT policies. The provisioned policy should grant access only to that device's topics, using `${iot:Connection.Thing.ThingName}` policy variables.
- Store device private keys in hardware security modules (HSM) or secure elements when available. Software-stored keys are extractable.

See `references/security-provisioning.md` for provisioning templates, certificate management, and IoT policy examples.

## Security

### X.509 Certificates

- Every device must authenticate with a unique X.509 client certificate. Shared certificates across devices make revocation impossible without affecting the entire fleet.
- Use AWS Private CA for production fleets. It provides automated certificate issuance, revocation (CRL), and integration with JITP.
- Rotate certificates before expiry using IoT Jobs to push new certificates and a Lambda to register them. Expired certificates cause immediate connection failure with no grace period.

### IoT Policies

IoT policies control what MQTT topics a device can publish/subscribe to and what shadows/jobs it can access. Always use policy variables to scope per-device.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:REGION:ACCOUNT:client/${iot:Connection.Thing.ThingName}"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:REGION:ACCOUNT:topic/acme/prod/*/${iot:Connection.Thing.ThingName}/*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:REGION:ACCOUNT:topicfilter/acme/prod/*/${iot:Connection.Thing.ThingName}/*"
    }
  ]
}
```

### Custom Authorizers

Use custom authorizers when devices cannot use X.509 certificates (e.g., legacy devices with token-based auth or OAuth). The authorizer is a Lambda function that validates the token and returns an IoT policy document. Custom authorizers add latency (Lambda cold start) and cost (per-invocation), so prefer X.509 certificates for new device designs.

### Device Defender

- **Audit**: Scheduled checks for insecure configurations (overly permissive policies, shared certificates, disabled logging). Run at least weekly.
- **Detect**: Real-time anomaly detection on device metrics (message volume, connection patterns, authorization failures). Alerts when a device deviates from its baseline behavior, indicating compromise or misconfiguration.
- Configure mitigation actions to automatically quarantine compromised devices (move to a restricted thing group with minimal permissions).

## Data Storage Patterns

### Timestream (Time-Series Telemetry)

- Default choice for telemetry that needs time-range queries (temperature over last 24 hours, average power per hour).
- Automatic tiering: memory store (recent, fast queries) to magnetic store (historical, cheaper).
- Set memory store retention to match your hot-query window (1-24 hours typical). Data beyond this moves to magnetic automatically.
- Cost consideration: Timestream charges per write and per query scan. For very high-frequency telemetry (>1 msg/sec/device across thousands of devices), aggregate at the edge with Greengrass or use Basic Ingest to S3 with Athena for batch queries.

### DynamoDB (Device Metadata and State)

- Use for device registry extensions, latest-known state, configuration, and command history.
- Design the partition key as the device ID for even distribution.
- Use TTL to auto-expire old command records and reduce storage cost.
- Do not store raw time-series telemetry in DynamoDB. At 1 msg/sec from 10,000 devices, that is 864 million writes/day, which costs roughly $1,100/day in on-demand WCU charges.

### S3 (Bulk Archival)

- Use IoT Rules Engine S3 action with partitioned keys: `s3://bucket/year=2026/month=04/day=06/hour=12/device-id.json`
- Query archived data with Athena using partition projection for cost-effective ad-hoc analysis.
- Enable S3 Intelligent-Tiering for automatic cost optimization on infrequently accessed telemetry.
- Cheapest option for long-term retention and compliance requirements.

### OpenSearch (Search and Analytics)

- Use when operators need full-text search across telemetry fields or real-time dashboards.
- IoT Rules Engine can write directly to OpenSearch Service.
- Cost consideration: OpenSearch clusters run 24/7 with dedicated instances. For intermittent analysis, prefer Athena on S3.

## Greengrass v2 (Edge Compute)

### When to Use Edge Compute

- **Latency**: Local control loops that must respond in <100ms (actuator control, safety shutoffs). Cloud round-trip adds 50-200ms minimum.
- **Bandwidth**: Devices generate more data than the network can upload. Aggregate or filter at the edge, send summaries to cloud.
- **Intermittent connectivity**: Sites with unreliable internet (remote oil wells, ships, mines). Greengrass buffers data and syncs when connected.
- **Local ML inference**: Run ML models on edge hardware (image classification, anomaly detection) without sending raw data to cloud.

### When to Skip Edge Compute

- Devices with reliable, high-bandwidth connectivity and no latency requirements. Direct MQTT to IoT Core is simpler and eliminates edge infrastructure management.
- Very constrained devices (microcontrollers with <1MB RAM) that cannot run the Greengrass nucleus. Use FreeRTOS with direct IoT Core connectivity instead.

### Component Model

Greengrass v2 uses a component model where each capability is a deployable unit (recipe + artifacts). Components can be:
- **AWS-provided**: Pre-built components for common tasks (stream manager, log manager, MQTT bridge, Docker application manager)
- **Custom**: Your application logic, packaged as a recipe (YAML/JSON) referencing artifacts (code, binaries, configs)
- **Community**: Third-party components from the Greengrass component catalog

### Stream Manager

Use Stream Manager for reliable edge-to-cloud data transfer. It handles buffering, batching, bandwidth management, and automatic retry. Supports export to Kinesis Data Streams, S3, IoT Analytics, and IoT SiteWise.

- Configure per-stream: storage type (memory or file-system), max size, strategy when full (reject new or overwrite oldest)
- Set bandwidth limits to prevent telemetry uploads from starving control-plane traffic
- Minimum 70 MB RAM overhead for the stream manager component

See `references/greengrass-patterns.md` for component recipes, deployment configurations, and stream manager setup.

## Fleet Management

### IoT Jobs (OTA Updates)

- Use Jobs for firmware updates, configuration changes, and certificate rotation across the fleet.
- **Continuous jobs**: Automatically target new devices added to a thing group. Use for ongoing compliance (all devices in group X must have firmware v2.3+).
- **Snapshot jobs**: One-time execution against a fixed set of targets.
- Configure rollout rate (max devices per minute) and abort criteria (% failures before halting) to prevent fleet-wide bricking from a bad update.
- Use signed job documents with code signing to prevent tampering.

### Fleet Indexing

- Enables SQL-like queries across device registry, shadow, connectivity, and Device Defender violation data.
- Must be explicitly enabled (off by default). Without fleet indexing, you cannot query fleet state at scale.
- Example: `thingName:sensor-* AND shadow.reported.firmware:v2.1 AND connectivity.connected:false` finds all disconnected sensors on old firmware.
- Use fleet metrics to push aggregated fleet statistics to CloudWatch for dashboards and alarms.

### Key Limits (IoT Core)

| Resource | Default Limit | Notes |
|---|---|---|
| Maximum concurrent connections | 500,000 per account | Requestable increase |
| Maximum MQTT message size | 128 KB | Hard limit |
| Maximum publishes per second (per account) | 20,000 | Requestable increase |
| Maximum inbound publishes per second (per connection) | 100 | Per-device throttle |
| Persistent session expiry | 1 hour (default), up to 7 days | Configure per client |
| Maximum rules per account | 1,000 | Requestable increase |
| Maximum actions per rule | 10 | Hard limit |
| Maximum shadow document size | 8 KB (classic), 8 KB (named) | Hard limit |
| Named shadows per thing | 10 | Hard limit |
| Fleet provisioning templates per account | 256 | Requestable increase |
| Thing groups depth | 7 levels | Hard limit |

## Anti-Patterns

- **Polling instead of MQTT.** Devices that HTTP poll for commands waste battery, bandwidth, and IoT Core request costs. A device polling every 5 seconds generates 17,280 requests/day; MQTT keeps a persistent connection with near-zero overhead when idle, and the server pushes commands instantly.
- **No error actions on rules.** Without an error action, a failed rule action (IAM permission issue, DynamoDB throttle, Lambda error) silently drops the message. There is no retry, no alert, and no way to recover the data. Always route errors to S3 or SQS.
- **Overly permissive IoT policies (iot:* on *).** A compromised device with `iot:*` can publish to any topic, read any shadow, and trigger any job. Use policy variables (`${iot:Connection.Thing.ThingName}`) to scope each device to its own resources.
- **Single MQTT topic for all devices.** Publishing everything to `devices/telemetry` makes it impossible to apply per-device access control, filter rules by device type, or subscribe to a specific device's data. Use hierarchical topics with device identity segments.
- **Not using Device Shadow for desired/reported state sync.** Without shadows, setting device state requires the device to be online at the exact moment the command is sent. Shadows persist the desired state and deliver it when the device reconnects.
- **Storing raw telemetry in DynamoDB.** At IoT scale, DynamoDB write costs explode. 10,000 devices at 1 msg/sec = 864M writes/day = ~$1,100/day on-demand. Use Timestream for time-series (10-20x cheaper for write-heavy time-series workloads) or S3 for archival ($0.023/GB/month).
- **Ignoring Greengrass for edge preprocessing.** Sending raw high-frequency sensor data to the cloud wastes bandwidth and inflates ingestion costs. A Greengrass component that averages 1,000 readings into 1 summary per minute reduces cloud costs by 99.9%.
- **Not configuring fleet indexing.** Without fleet indexing enabled, you cannot query which devices are running old firmware, which are disconnected, or which have specific shadow states. You are flying blind on fleet health. Enable it proactively.
- **Shared X.509 certificates across devices.** If one device is compromised, you must revoke the shared certificate, disconnecting all devices that use it. One certificate per device limits the blast radius to a single device.
- **No rollout controls on IoT Jobs.** Pushing a firmware update to all devices simultaneously risks fleet-wide failure. Always configure max concurrent targets, rollout rate, and abort thresholds (e.g., abort if >5% of devices fail).
- **Ignoring Basic Ingest for high-volume telemetry.** Standard publish costs $1.00 per million messages. Basic Ingest ($0.00 publish cost, rules actions still charged) saves this entirely for telemetry that only needs to flow to rules engine actions.
- **Not setting MQTT session expiry.** Default persistent session expiry is 1 hour. Devices that reconnect after longer disconnections lose queued messages. Set session expiry to match the device's expected offline duration (up to 7 days max).

## Additional Resources

### Reference Files

For detailed operational guidance, consult:
- **`references/rules-engine-patterns.md`** -- Rule SQL examples for common routing patterns, error action configuration, topic structure best practices, and Basic Ingest setup
- **`references/security-provisioning.md`** -- X.509 certificate management, fleet provisioning templates (JITP, bulk, by claim), IoT policies with variables, and custom authorizer setup
- **`references/greengrass-patterns.md`** -- Greengrass v2 component recipes, deployment configurations, stream manager setup, and local MQTT bridge configuration

### Related Skills
- **`lambda`** -- Lambda functions as IoT rule actions and Greengrass components
- **`step-functions`** -- Orchestrating multi-step device provisioning and remediation workflows
- **`dynamodb`** -- Device metadata storage design, partition key strategy, TTL configuration
- **`s3`** -- Telemetry archival, lifecycle policies, Athena integration for batch queries
- **`messaging`** -- SQS/SNS integration with IoT rules for decoupled processing and alerting
- **`observability`** -- CloudWatch metrics, alarms, and dashboards for IoT fleet monitoring
- **`iam`** -- IAM roles for IoT rules engine actions, Greengrass token exchange, and fleet provisioning
- **`networking`** -- VPC endpoints for IoT Core, private connectivity for Greengrass core devices
- **`security-review`** -- Security audit of IoT policies, certificate management, and Device Defender configuration

## Output Format

When recommending an IoT architecture, include:

| Component | Choice | Rationale |
|---|---|---|
| Protocol | MQTT v5 over TLS 8883 | Bidirectional, persistent, low overhead |
| Authentication | X.509 per-device certificates via AWS Private CA | Hardware-bound identity, scalable revocation |
| Provisioning | Fleet Provisioning by Claim with pre-provisioning hook | Devices cannot be provisioned in factory |
| Topic Structure | `{org}/prod/{type}/{device-id}/{category}` | Per-device access control, rule targeting |
| Telemetry Ingestion | IoT Rules Engine to Timestream (Basic Ingest) | Cost-effective time-series storage |
| Device State | Named Shadows (config + diagnostics) | Offline-tolerant desired/reported sync |
| Edge Compute | Greengrass v2 with Stream Manager | Local filtering, buffered cloud upload |
| Fleet Management | Jobs (OTA) + Fleet Indexing + Device Defender | Update, query, and audit the fleet |
| Alerting | IoT Events detector model to SNS | Multi-device state correlation |

Include estimated monthly cost range using the `cost-check` skill.
