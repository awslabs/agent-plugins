# Greengrass v2 Patterns

## Core Concepts

Greengrass v2 runs on edge devices (called core devices) and uses a component-based architecture. The **nucleus** is the core runtime. Components are deployable units with a recipe (metadata, dependencies, lifecycle) and artifacts (code, binaries, config).

### Installation

```bash
# Download and install Greengrass v2 nucleus
# Requires Java 8+ (Corretto recommended) and root/admin access

curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus.zip
unzip greengrass-nucleus.zip -d GreengrassInstaller

java -Droot="/greengrass/v2" \
  -Dlog.store=FILE \
  -jar ./GreengrassInstaller/lib/Greengrass.jar \
  --aws-region REGION \
  --thing-name "edge-gateway-001" \
  --thing-group-name "edge-gateways" \
  --thing-policy-name "greengrass-core-policy" \
  --tes-role-name "GreengrassTESRole" \
  --tes-role-alias-name "GreengrassTESRoleAlias" \
  --component-default-user ggc_user:ggc_group \
  --provision true \
  --setup-system-service true
```

The `--provision true` flag auto-creates the thing, certificate, and policy in IoT Core. The `--setup-system-service true` flag registers Greengrass as a systemd service so it starts on boot.

## Component Recipes

### Custom Telemetry Processor Component

This component reads sensor data, aggregates it, and publishes summaries to IoT Core via the local MQTT bridge.

**Recipe (`recipe.yaml`):**
```yaml
---
RecipeFormatVersion: "2020-01-25"
ComponentName: com.acme.telemetry-processor
ComponentVersion: "1.0.0"
ComponentDescription: Aggregates raw sensor telemetry and publishes 1-minute summaries to IoT Core
ComponentPublisher: Acme Corp
ComponentDependencies:
  aws.greengrass.Nucleus:
    VersionRequirement: ">=2.5.0"
    DependencyType: HARD
  aws.greengrass.clientdevices.mqtt.Bridge:
    VersionRequirement: ">=2.2.0"
    DependencyType: HARD
ComponentConfiguration:
  DefaultConfiguration:
    aggregation_interval_seconds: 60
    source_topic: "local/sensors/+/telemetry"
    destination_topic: "acme/prod/edge-gateway-001/aggregated/telemetry"
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        com.acme.telemetry-processor:mqttproxy:1:
          policyDescription: Subscribe to local sensor topics
          operations:
            - "aws.greengrass#SubscribeToIoTCore"
            - "aws.greengrass#PublishToIoTCore"
          resources:
            - "local/sensors/+/telemetry"
            - "acme/prod/edge-gateway-001/aggregated/*"
Manifests:
  - Platform:
      os: linux
    Lifecycle:
      install: "pip3 install -r {artifacts:path}/requirements.txt"
      run:
        script: "python3 {artifacts:path}/telemetry_processor.py"
        RequiresPrivilege: false
    Artifacts:
      - URI: "s3://acme-greengrass-artifacts/telemetry-processor/1.0.0/telemetry_processor.py"
      - URI: "s3://acme-greengrass-artifacts/telemetry-processor/1.0.0/requirements.txt"
```

### ML Inference Component

Runs a pre-trained model at the edge for anomaly detection on sensor data.

**Recipe (`recipe.yaml`):**
```yaml
---
RecipeFormatVersion: "2020-01-25"
ComponentName: com.acme.anomaly-detector
ComponentVersion: "1.0.0"
ComponentDescription: Runs anomaly detection ML model on edge sensor data
ComponentPublisher: Acme Corp
ComponentDependencies:
  aws.greengrass.Nucleus:
    VersionRequirement: ">=2.5.0"
    DependencyType: HARD
  aws.greengrass.TokenExchangeService:
    VersionRequirement: ">=2.0.0"
    DependencyType: HARD
ComponentConfiguration:
  DefaultConfiguration:
    model_path: "{artifacts:decompressedPath}/model"
    confidence_threshold: 0.85
    accessControl:
      aws.greengrass.ipc.mqttproxy:
        com.acme.anomaly-detector:mqttproxy:1:
          policyDescription: Subscribe to telemetry, publish anomalies
          operations:
            - "aws.greengrass#SubscribeToIoTCore"
            - "aws.greengrass#PublishToIoTCore"
          resources:
            - "acme/prod/edge-gateway-001/aggregated/telemetry"
            - "acme/prod/edge-gateway-001/anomalies"
Manifests:
  - Platform:
      os: linux
      architecture: aarch64
    Lifecycle:
      install: |
        pip3 install -r {artifacts:path}/requirements.txt
      run:
        script: "python3 {artifacts:path}/anomaly_detector.py --model {configuration:/model_path} --threshold {configuration:/confidence_threshold}"
        RequiresPrivilege: false
    Artifacts:
      - URI: "s3://acme-greengrass-artifacts/anomaly-detector/1.0.0/anomaly_detector.py"
      - URI: "s3://acme-greengrass-artifacts/anomaly-detector/1.0.0/requirements.txt"
      - URI: "s3://acme-greengrass-artifacts/anomaly-detector/1.0.0/model.tar.gz"
        Unarchive: ZIP
```

### Docker Application Component

Runs a containerized application on the Greengrass core device.

**Recipe (`recipe.yaml`):**
```yaml
---
RecipeFormatVersion: "2020-01-25"
ComponentName: com.acme.data-dashboard
ComponentVersion: "1.0.0"
ComponentDescription: Local Grafana dashboard for real-time edge data visualization
ComponentPublisher: Acme Corp
ComponentDependencies:
  aws.greengrass.Nucleus:
    VersionRequirement: ">=2.5.0"
    DependencyType: HARD
  aws.greengrass.DockerApplicationManager:
    VersionRequirement: ">=2.0.0"
    DependencyType: HARD
ComponentConfiguration:
  DefaultConfiguration:
    grafana_port: 3000
Manifests:
  - Platform:
      os: linux
    Lifecycle:
      run:
        script: |
          docker run --rm \
            -p {configuration:/grafana_port}:3000 \
            -v /greengrass/v2/work/com.acme.data-dashboard/grafana:/var/lib/grafana \
            grafana/grafana:latest
      shutdown:
        script: "docker stop $(docker ps -q --filter ancestor=grafana/grafana:latest)"
        timeout: 30
```

## Deployment Configuration

### Create a Deployment via CLI

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:REGION:ACCOUNT:thinggroup/edge-gateways" \
  --deployment-name "telemetry-processor-v1" \
  --components '{
    "com.acme.telemetry-processor": {
      "componentVersion": "1.0.0",
      "configurationUpdate": {
        "merge": "{\"aggregation_interval_seconds\": 30}"
      }
    },
    "aws.greengrass.clientdevices.mqtt.Bridge": {
      "componentVersion": "2.3.0",
      "configurationUpdate": {
        "merge": "{\"mqttTopicMapping\": {\"telemetryMapping\": {\"topic\": \"local/sensors/+/telemetry\", \"source\": \"LocalMqtt\", \"target\": \"IotCore\"}, \"commandMapping\": {\"topic\": \"acme/prod/+/commands\", \"source\": \"IotCore\", \"target\": \"LocalMqtt\"}}}"
      }
    },
    "aws.greengrass.clientdevices.mqtt.Moquette": {
      "componentVersion": "2.3.0"
    },
    "aws.greengrass.StreamManager": {
      "componentVersion": "2.1.0"
    }
  }' \
  --deployment-policies '{
    "failureHandlingPolicy": "ROLLBACK",
    "componentUpdatePolicy": {
      "timeoutInSeconds": 300,
      "action": "NOTIFY_COMPONENTS"
    }
  }'
```

### Deployment Best Practices

- **Always use thing groups as deployment targets**, not individual things. This enables automatic deployment to new devices added to the group.
- **Set `failureHandlingPolicy` to `ROLLBACK`** for production deployments. If any component fails to deploy, the device reverts to the previous configuration instead of running in a degraded state.
- **Use `NOTIFY_COMPONENTS`** component update policy so running components can gracefully shut down before update, preventing data loss in stream buffers.
- **Pin component versions** in production deployments. Do not use version ranges (e.g., `>=1.0.0`) because they may auto-upgrade to untested versions.
- **Test deployments on a staging thing group first.** Create separate thing groups for staging and production. Deploy to staging, verify via CloudWatch, then deploy to production.

### Rollout Configuration

For large fleets, configure deployment rollout to avoid updating all devices simultaneously:

```bash
aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:REGION:ACCOUNT:thinggroup/edge-gateways" \
  --deployment-name "firmware-update-v2.3" \
  --components '{...}' \
  --iot-job-configuration '{
    "jobExecutionsRolloutConfig": {
      "maximumPerMinute": 10,
      "exponentialRate": {
        "baseRatePerMinute": 5,
        "incrementFactor": 2,
        "rateIncreaseCriteria": {
          "numberOfSucceededThings": 100
        }
      }
    },
    "abortConfig": {
      "criteriaList": [
        {
          "failureType": "FAILED",
          "action": "CANCEL",
          "thresholdPercentage": 5,
          "minNumberOfExecutedThings": 20
        }
      ]
    },
    "timeoutConfig": {
      "inProgressTimeoutInMinutes": 30
    }
  }'
```

This configuration starts rolling out at 5 devices/minute, doubles the rate after every 100 successes, and aborts the entire deployment if more than 5% of devices fail (after at least 20 have been attempted).

## Stream Manager Setup

### Configure Stream Manager Component

```json
{
  "aws.greengrass.StreamManager": {
    "componentVersion": "2.1.0",
    "configurationUpdate": {
      "merge": "{\"STREAM_MANAGER_STORE_ROOT_DIR\": \"/greengrass/v2/streams\", \"STREAM_MANAGER_SERVER_PORT\": 8088, \"STREAM_MANAGER_AUTHENTICATE_CLIENT\": true, \"STREAM_MANAGER_EXPORTER_MAX_BANDWIDTH\": 5242880}"
    }
  }
}
```

| Parameter | Recommended Value | Why |
|---|---|---|
| `STREAM_MANAGER_STORE_ROOT_DIR` | `/greengrass/v2/streams` | Dedicated directory for stream data; use an SSD for high throughput |
| `STREAM_MANAGER_SERVER_PORT` | 8088 | Default port; change if conflicting with other services |
| `STREAM_MANAGER_AUTHENTICATE_CLIENT` | `true` | Only Greengrass components can interact with streams; prevents unauthorized local processes from reading/writing |
| `STREAM_MANAGER_EXPORTER_MAX_BANDWIDTH` | 5242880 (5 MB/s) | Limits upload bandwidth so telemetry does not saturate the network link, leaving headroom for control-plane traffic |

### Create and Write to a Stream (Python SDK)

```python
from stream_manager import (
    StreamManagerClient,
    MessageStreamDefinition,
    StrategyOnFull,
    ExportDefinition,
    KinesisConfig,
    S3ExportTaskExecutorConfig,
    StatusConfig,
    StatusLevel,
    StatusMessage
)

client = StreamManagerClient()

# Create a stream that exports to Kinesis
client.create_message_stream(
    MessageStreamDefinition(
        name="sensor-telemetry-stream",
        max_size=268435456,  # 256 MB local buffer
        stream_segment_size=16777216,  # 16 MB segments
        strategy_on_full=StrategyOnFull.OverwriteOldestData,
        export_definition=ExportDefinition(
            kinesis=[
                KinesisConfig(
                    identifier="kinesis-export",
                    kinesis_stream_name="iot-telemetry-stream",
                    batch_size=500,
                    batch_interval_millis=5000,
                    priority=10
                )
            ]
        )
    )
)

# Write data to the stream
import json
data = json.dumps({
    "device_id": "sensor-001",
    "temperature": 23.5,
    "humidity": 65.2,
    "timestamp": 1712400000
})
client.append_message("sensor-telemetry-stream", data.encode())
```

### Stream Export Destinations

| Destination | Use Case | Configuration Class |
|---|---|---|
| Kinesis Data Streams | Real-time analytics pipeline | `KinesisConfig` |
| S3 | Bulk archival of edge data | `S3ExportTaskExecutorConfig` |
| IoT Analytics | Channel ingestion for IoT Analytics pipelines | `IoTAnalyticsConfig` |
| IoT SiteWise | Industrial asset property values | `IoTSiteWiseConfig` |

### Stream Manager Best Practices

- **Set `strategy_on_full` to `OverwriteOldestData`** for telemetry streams where recent data is more valuable than historical. Use `RejectNewData` for streams where every message must be delivered (alerts, commands).
- **Size the local buffer based on expected offline duration.** If the site loses connectivity for up to 4 hours and generates 1 MB/min of telemetry, set `max_size` to at least 240 MB.
- **Set batch size and interval together.** `batch_size=500` with `batch_interval_millis=5000` means: send a batch when 500 messages accumulate OR 5 seconds pass, whichever comes first. This balances latency and throughput.
- **Monitor stream health** via the Greengrass log manager component. Look for `ExportTaskFailure` log entries.

## Local MQTT Bridge Configuration

The MQTT bridge connects local MQTT topics (Moquette broker on the core device) to IoT Core MQTT topics, enabling client devices (sensors, actuators) to communicate with the cloud through the Greengrass core.

### Bridge Topic Mapping

```json
{
  "aws.greengrass.clientdevices.mqtt.Bridge": {
    "componentVersion": "2.3.0",
    "configurationUpdate": {
      "merge": "{\"mqttTopicMapping\": {\"sensorTelemetryToCloud\": {\"topic\": \"local/sensors/+/telemetry\", \"source\": \"LocalMqtt\", \"target\": \"IotCore\"}, \"cloudCommandsToLocal\": {\"topic\": \"acme/prod/+/commands\", \"source\": \"IotCore\", \"target\": \"LocalMqtt\"}, \"localDeviceToDevice\": {\"topic\": \"local/actuators/+/control\", \"source\": \"LocalMqtt\", \"target\": \"LocalMqtt\"}}}"
    }
  }
}
```

| Mapping | Source | Target | Purpose |
|---|---|---|---|
| `sensorTelemetryToCloud` | LocalMqtt | IotCore | Forward sensor data from local devices to AWS IoT Core |
| `cloudCommandsToLocal` | IotCore | LocalMqtt | Deliver cloud commands to local actuators |
| `localDeviceToDevice` | LocalMqtt | LocalMqtt | Enable local device-to-device communication without cloud round-trip |

### Client Device Authentication

Greengrass core authenticates local client devices using their certificates. Configure the client device auth component:

```json
{
  "aws.greengrass.clientdevices.Auth": {
    "componentVersion": "2.4.0",
    "configurationUpdate": {
      "merge": "{\"deviceGroups\": {\"formatVersion\": \"2021-03-05\", \"definitions\": {\"localSensors\": {\"selectionRule\": \"thingName: sensor-*\", \"policyName\": \"localSensorPolicy\"}}, \"policies\": {\"localSensorPolicy\": {\"AllowPublish\": {\"statementDescription\": \"Allow sensors to publish telemetry\", \"operations\": [\"mqtt:publish\"], \"resources\": [\"local/sensors/${iot:clientId}/telemetry\"]}, \"AllowSubscribe\": {\"statementDescription\": \"Allow sensors to receive commands\", \"operations\": [\"mqtt:subscribe\"], \"resources\": [\"local/sensors/${iot:clientId}/commands\"]}}}}}"
    }
  }
}
```

### Components to Deploy Together

For a typical edge gateway setup, deploy these components together:

| Component | Purpose |
|---|---|
| `aws.greengrass.Nucleus` | Core runtime (always present) |
| `aws.greengrass.clientdevices.mqtt.Moquette` | Local MQTT broker for client devices |
| `aws.greengrass.clientdevices.mqtt.Bridge` | Routes messages between local broker and IoT Core |
| `aws.greengrass.clientdevices.Auth` | Authenticates local client devices |
| `aws.greengrass.StreamManager` | Reliable edge-to-cloud data transfer |
| `aws.greengrass.LogManager` | Uploads component logs to CloudWatch |
| `aws.greengrass.TokenExchangeService` | Provides temporary AWS credentials to components |

## Monitoring Greengrass Deployments

### CloudWatch Logs

Deploy the Log Manager component to ship Greengrass logs to CloudWatch:

```json
{
  "aws.greengrass.LogManager": {
    "componentVersion": "2.3.0",
    "configurationUpdate": {
      "merge": "{\"logsUploaderConfiguration\": {\"systemLogsConfiguration\": {\"uploadToCloudWatch\": true, \"minimumLogLevel\": \"INFO\", \"diskSpaceLimit\": 10, \"diskSpaceLimitUnit\": \"MB\"}, \"componentLogsConfigurationMap\": {\"com.acme.telemetry-processor\": {\"minimumLogLevel\": \"INFO\", \"diskSpaceLimit\": 25, \"diskSpaceLimitUnit\": \"MB\"}}}}"
    }
  }
}
```

### Health Check via CLI

```bash
# Check the status of all components on a core device
aws greengrassv2 list-installed-components \
  --core-device-thing-name "edge-gateway-001"

# Check the status of a specific deployment
aws greengrassv2 get-deployment \
  --deployment-id "DEPLOYMENT_ID"

# List core devices and their status
aws greengrassv2 list-core-devices \
  --status HEALTHY
```

### Key Metrics to Monitor

| What to Check | How | Alarm Threshold |
|---|---|---|
| Component deployment status | `greengrassv2:list-installed-components` | Any component in ERRORED state |
| Core device connectivity | IoT Core lifecycle events (`$aws/events/presence/connected`) | Device disconnected > 5 minutes |
| Stream manager export failures | CloudWatch Logs for `ExportTaskFailure` | Any failure in production |
| Disk usage on core device | Custom component publishing to CloudWatch | > 80% disk utilization |
| Component crash loops | CloudWatch Logs for rapid restart patterns | > 3 restarts in 10 minutes |
