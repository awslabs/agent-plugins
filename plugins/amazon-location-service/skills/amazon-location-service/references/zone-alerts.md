# Zone Alerts

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Detect when devices enter or exit geographic zones and trigger automated actions. This is the core geofencing pattern — applicable to delivery arrival notifications, fleet compliance monitoring, asset tracking, and any scenario where crossing a boundary should trigger a response.

The workflow is: **define zones → evaluate positions → react to events**.

> **Language note**: Code examples below use JavaScript (`@aws-sdk/client-location`). When the user's project uses a different language, translate the API calls to the equivalent AWS SDK — the operation names, parameters, and response shapes are identical across SDKs.

## Table of Contents

- [Step 1: Create a Geofence Collection](#step-1-create-a-geofence-collection)
- [Step 2: Define Zones](#step-2-define-zones)
- [Step 3: Evaluate Device Positions](#step-3-evaluate-device-positions)
- [Step 4: React to Events via EventBridge](#step-4-react-to-events-via-eventbridge)
- [Forecast Geofence Events](#forecast-geofence-events)
- [Error Handling](#error-handling)
- [Cost Considerations](#cost-considerations)
- [Best Practices](#best-practices)

## Step 1: Create a Geofence Collection

A geofence collection groups zones together. A collection holds up to 50,000 geofences.

```javascript
import { CreateGeofenceCollectionCommand } from "@aws-sdk/client-location";

const response = await client.send(
  new CreateGeofenceCollectionCommand({
    CollectionName: "my-delivery-zones",
    Description: "Warehouse and customer delivery zones",
    Tags: { Environment: "Production" },
  }),
);
// response.CollectionArn → "arn:aws:geo:us-east-1:123456789012:geofence-collection/my-delivery-zones"
```

## Step 2: Define Zones

Use `PutGeofence` (single) or `BatchPutGeofence` (bulk) to add geofences to the collection.

Four geometry types:

- **Circle** — center point `[lng, lat]` with `Radius` in meters. Simplest option, use when "within X meters of a point" is sufficient.
- **Polygon** — outer ring required, optional interior rings for exclusion holes. Use for irregular zone shapes. Maximum 1,000 vertices.
- **MultiPolygon** — multiple polygons as one geofence. Use when a single logical zone spans disconnected areas.
- **Geobuf** — base64-encoded binary for GeoJSON Polygon or MultiPolygon. Supports up to 100,000 vertices (vs 1,000 for plain Polygon). Use for complex boundaries like detailed coastlines or city limits.

Attach `GeofenceProperties` (key-value metadata, max 3 properties, key max 20 chars, value max 40 chars) to zones for downstream filtering in EventBridge rules.

```javascript
import {
  PutGeofenceCommand,
  BatchPutGeofenceCommand,
} from "@aws-sdk/client-location";

// Circle geofence — "within 500m of warehouse"
await client.send(
  new PutGeofenceCommand({
    CollectionName: "my-delivery-zones",
    GeofenceId: "warehouse-zone-1",
    GeofenceProperties: { Type: "Warehouse", Priority: "High" },
    Geometry: {
      Circle: {
        Center: [-122.3394, 47.6159], // [longitude, latitude]
        Radius: 500, // meters
      },
    },
  }),
);

// Polygon geofence — irregular boundary
await client.send(
  new PutGeofenceCommand({
    CollectionName: "my-delivery-zones",
    GeofenceId: "restricted-area-1",
    GeofenceProperties: { Type: "RestrictedArea" },
    Geometry: {
      Polygon: [
        [
          [-122.34, 47.62],
          [-122.34, 47.61],
          [-122.33, 47.61],
          [-122.33, 47.62],
          [-122.34, 47.62], // first and last point MUST match to close the ring
        ],
      ],
    },
  }),
);

// Bulk add — up to 10 geofences per batch
await client.send(
  new BatchPutGeofenceCommand({
    CollectionName: "my-delivery-zones",
    Entries: [
      {
        GeofenceId: "customer-zone-1",
        GeofenceProperties: { Type: "CustomerSite" },
        Geometry: { Circle: { Center: [-122.35, 47.62], Radius: 200 } },
      },
      {
        GeofenceId: "customer-zone-2",
        GeofenceProperties: { Type: "CustomerSite" },
        Geometry: { Circle: { Center: [-122.3, 47.6], Radius: 150 } },
      },
    ],
  }),
);
```

## Step 3: Evaluate Device Positions

Choose one of two approaches:

### Option A: Link a Tracker (recommended for most cases)

SHOULD be used when you need location history, map display, or continuous monitoring. Position updates sent to the tracker are automatically evaluated against all linked geofence collections. Trackers accept updates via AWS SDKs or MQTT (for IoT devices).

```javascript
import {
  CreateTrackerCommand,
  AssociateTrackerConsumerCommand,
  BatchUpdateDevicePositionCommand,
} from "@aws-sdk/client-location";

// 1. Create a tracker
await client.send(
  new CreateTrackerCommand({
    TrackerName: "my-fleet-tracker",
    PositionFiltering: "AccuracyBased", // or "DistanceBased" | "TimeBased"
  }),
);

// 2. Link tracker to geofence collection (max 5 collections per tracker)
await client.send(
  new AssociateTrackerConsumerCommand({
    TrackerName: "my-fleet-tracker",
    ConsumerArn:
      "arn:aws:geo:us-east-1:123456789012:geofence-collection/my-delivery-zones",
  }),
);

// 3. Send position updates — automatically evaluated against linked geofences
await client.send(
  new BatchUpdateDevicePositionCommand({
    TrackerName: "my-fleet-tracker",
    Updates: [
      {
        DeviceId: "truck-01",
        Position: [-122.3394, 47.6159], // [longitude, latitude]
        SampleTime: new Date().toISOString(),
        Accuracy: { Horizontal: 10.0 },
        PositionProperties: { VehicleType: "Truck" },
      },
    ],
  }),
);
```

**Note**: Tracker and geofence collection MUST be in the same AWS account — cross-account associations are not supported.

#### Tracker Position Filtering

Filtering mode controls cost and GPS jitter. See **Position Filtering Modes** in the **device-tracking** reference for the full comparison table (AccuracyBased, DistanceBased, TimeBased).

### Option B: Direct BatchEvaluateGeofences Call

SHOULD be used when you only need event detection without storing positions, or when you want to selectively evaluate (not every update). Maximum 10 device position updates per call.

```javascript
import { BatchEvaluateGeofencesCommand } from "@aws-sdk/client-location";

await client.send(
  new BatchEvaluateGeofencesCommand({
    CollectionName: "my-delivery-zones",
    DevicePositionUpdates: [
      {
        DeviceId: "truck-01",
        Position: [-122.3394, 47.6159], // [longitude, latitude]
        SampleTime: new Date().toISOString(),
        Accuracy: { Horizontal: 10.0 },
        PositionProperties: { VehicleType: "Truck" },
      },
    ],
  }),
);
// Returns HTTP 200 with empty body — events are emitted asynchronously to EventBridge
```

Both approaches emit `ENTER` and `EXIT` events to Amazon EventBridge when positions cross zone boundaries.

### Event Behavior Gotchas

**IMPORTANT**: Understand how events are generated to avoid surprises:

- **First evaluation DOES fire ENTER if inside a geofence**: The first position update for a new DeviceId generates an `ENTER` event immediately if the device is inside a geofence — there is no "warm-up" period. If outside all geofences, no event is generated and the position becomes the baseline. Subsequent updates generate events on boundary crossings. If you expect an ENTER event but don't see it processed, check the downstream target (Lambda, SQS) for errors before assuming the event wasn't generated.
- **30-day state retention**: Amazon Location maintains previous position state for 30 days per device. After 30 days of inactivity, the next update is treated as a fresh baseline (same rules as first evaluation).
- **Events fire on boundary crossings, not every update**: You will NOT receive an event for every position update — only when a device transitions between inside and outside a geofence.

## Step 4: React to Events via EventBridge

Create EventBridge rules to route geofence events to targets like Lambda, SNS (notifications), or SQS (queues).

### Match all geofence events

```json
{
  "source": ["aws.geo"],
  "detail-type": ["Location Geofence Event"]
}
```

### Match only ENTER events with property filter

```json
{
  "source": ["aws.geo"],
  "detail-type": ["Location Geofence Event"],
  "detail": {
    "EventType": ["ENTER"],
    "GeofenceProperties": { "Type": "Warehouse" },
    "PositionProperties": { "VehicleType": "Truck" }
  }
}
```

### Event payload structure

```json
{
  "detail-type": "Location Geofence Event",
  "source": "aws.geo",
  "detail": {
    "EventType": "ENTER",
    "GeofenceId": "warehouse-zone-1",
    "DeviceId": "truck-01",
    "SampleTime": "2024-01-15T12:00:00Z",
    "Position": [-122.3394, 47.6159],
    "Accuracy": { "Horizontal": 10.0 },
    "GeofenceProperties": { "Type": "Warehouse", "Priority": "High" },
    "PositionProperties": { "VehicleType": "Truck" }
  }
}
```

## Forecast Geofence Events

Use `ForecastGeofenceEvents` to predict upcoming boundary crossings based on a device's current position and speed. Returns forecasted ENTER, EXIT, or IDLE events within a time horizon. This API is **synchronous** — forecasted events are returned directly in the response. Use this when you need immediate results. For asynchronous evaluation that publishes events to Amazon EventBridge, use `BatchEvaluateGeofences` (see Option B above).

```javascript
import { ForecastGeofenceEventsCommand } from "@aws-sdk/client-location";

const response = await client.send(
  new ForecastGeofenceEventsCommand({
    CollectionName: "my-delivery-zones",
    DeviceState: {
      Position: [-122.3394, 47.6159],
      Speed: 50,
    },
    TimeHorizonMinutes: 30,
    SpeedUnit: "KilometersPerHour",
    DistanceUnit: "Kilometers",
  }),
);

response.ForecastedEvents.forEach((event) => {
  console.log(
    `${event.EventType} ${event.GeofenceId} — ` +
      `breach in ${event.ForecastedBreachTime}, ` +
      `distance: ${event.NearestDistance} ${response.DistanceUnit}`,
  );
});
// EventType: "ENTER" | "EXIT" | "IDLE"
// IDLE means device is inside the geofence and will remain inside through the time horizon
```

**Note**: Heading direction is not considered — the API takes a conservative approach and includes events for any heading. Omit `TimeHorizonMinutes` to perform a containment check only (which geofences is the device currently inside?).

## Error Handling

### Common Errors

| Error                           | HTTP Status | Cause                                                                        |
| ------------------------------- | ----------- | ---------------------------------------------------------------------------- |
| `ResourceNotFoundException`     | 404         | Collection or tracker name doesn't exist                                     |
| `ValidationException`           | 400         | Invalid geometry, coordinate order wrong, or parameter constraints violated  |
| `ConflictException`             | 409         | Collection name already exists, or tracker already linked to this collection |
| `ThrottlingException`           | 429         | Request rate exceeded — implement exponential backoff                        |
| `AccessDeniedException`         | 403         | IAM or Cognito permissions missing for the operation                         |
| `ServiceQuotaExceededException` | 402         | Account limit reached (e.g., max geofence collections)                       |

### Batch Operation Errors

`BatchPutGeofence` and `BatchEvaluateGeofences` return partial success — some entries MAY succeed while others fail. Always check the `Errors` array in the response:

```javascript
const response = await client.send(new BatchPutGeofenceCommand({/* ... */}));

if (response.Errors?.length > 0) {
  response.Errors.forEach((error) => {
    console.error(
      `Failed geofence ${error.GeofenceId}: ${error.Error.Message}`,
    );
  });
}
```

### Geometry Validation Errors

- Polygon first and last coordinates MUST be identical (ring must close)
- Maximum 1,000 vertices per polygon/multipolygon (use Geobuf for up to 100,000)
- Only one geometry type per geofence (Circle OR Polygon OR MultiPolygon)
- Circle radius MUST be greater than 0

## Cost Considerations

- Billed per **location update received** + per **geofence collection evaluation** per update
- Combine related zones into fewer collections to reduce evaluation costs
- Use position filtering (AccuracyBased or DistanceBased) to reduce unnecessary updates and lower costs
- See the **device-tracking** reference for detailed cost examples by filtering mode and update frequency

## Best Practices

- Use `GeofenceProperties` and `PositionProperties` as metadata for fine-grained EventBridge filtering
- De-duplicate events using the EventBridge event `id` field
- Set `Accuracy.Horizontal` when available to improve boundary crossing precision and enable accuracy-based filtering
- For high-frequency position updates, prefer tracker linking (Option A) over direct API calls
- Use `ForecastGeofenceEvents` to predict upcoming boundary crossings based on device trajectory
- To also query device positions and history, see the **device-tracking** reference
