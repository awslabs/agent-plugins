# Calculate Routes

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Calculate routes between locations using Amazon Location Service Routes API and display them on interactive maps.

## Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Basic Route Calculation](#basic-route-calculation)
- [Displaying Routes on Maps](#displaying-routes-on-maps)
- [Request Parameters](#request-parameters)
- [Response Structure](#response-structure)
- [Travel Modes and Options](#travel-modes-and-options)
- [Waypoints and Multi-Stop Routes](#waypoints-and-multi-stop-routes)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)

## Overview

The Amazon Location Routes API ([`geo-routes:CalculateRoutes`](https://docs.aws.amazon.com/location/latest/APIReference/API_CalculateRoutes.html)) calculates optimal routes between two or more locations with support for multiple travel modes, route preferences, and detailed navigation instructions.

**Key capabilities:**

- Calculate routes with turn-by-turn directions
- Support for car, truck, scooter, and pedestrian travel modes
- Avoid specific features (tolls, ferries, motorways)
- Include traffic data in route calculations
- Calculate toll costs
- Retrieve speed limits along the route
- Optimize for fastest or shortest routes

**When to use CalculateRoutes:**

- Providing driving or walking directions
- Building navigation applications
- Displaying routes on maps
- Estimating travel time and distance
- Planning multi-stop journeys with waypoints

**Related APIs:**

- `CalculateRouteMatrix` - For multiple origin/destination travel times (batch calculations)
- `CalculateIsolines` - For service areas (all locations reachable within time/distance)
- `OptimizeWaypoints` - For solving traveling salesman problem (optimal waypoint order)

## Authentication

All examples in this guide use the Amazon Location authentication helper to configure clients. The examples use the **modular npm approach** with ES6 imports.

**Quick setup:**

```javascript
import {
  GeoRoutesClient,
  CalculateRoutesCommand,
} from "@aws-sdk/client-geo-routes";
import { withAPIKey } from "@aws/amazon-location-utilities-auth-helper";

// Create authentication helper and client
const authHelper = withAPIKey("your-api-key", "us-west-2");
const client = new GeoRoutesClient(authHelper.getClientConfig());

// Make requests (no Key parameter needed)
const response = await client.send(
  new CalculateRoutesCommand({
    Origin: [-97.7431, 30.2672],
    Destination: [-97.7723, 30.2672],
    TravelMode: "Car",
  }),
);
```

**For detailed authentication guidance**, including:

- Browser vs npm/modular approaches
- Bundled client usage (`amazonLocationClient.*`)
- Choosing between API keys, Cognito, and custom credential providers
- Security best practices and when to use each method
- Complete examples for React, Vue, and plain HTML

**See the web-javascript reference documentation.**

## Basic Route Calculation

### Minimal Route Request

The simplest route calculation requires only origin and destination coordinates:

```javascript
import {
  GeoRoutesClient,
  CalculateRoutesCommand,
} from "@aws-sdk/client-geo-routes";
import { withAPIKey } from "@aws/amazon-location-utilities-auth-helper";

// Create an authentication helper instance using an API key
const authHelper = withAPIKey("your-api-key", "us-west-2");

// Configure the client to use API keys when making supported requests
const client = new GeoRoutesClient(authHelper.getClientConfig());

const params = {
  Origin: [-97.7431, 30.2672], // [longitude, latitude] - Downtown Austin
  Destination: [-97.7723, 30.2672], // [longitude, latitude] - Zilker Park
  TravelMode: "Car", // Required: Car, Truck, Scooter, Pedestrian
};

const command = new CalculateRoutesCommand(params);
const response = await client.send(command);

console.log(`Distance: ${response.Routes[0].Summary.Distance} meters`);
console.log(`Duration: ${response.Routes[0].Summary.Duration} seconds`);
```

### Understanding Coordinates

Coordinates MUST be specified as `[longitude, latitude]` arrays:

- **Longitude** comes first (range: -180 to 180, negative = west, positive = east)
- **Latitude** comes second (range: -90 to 90, negative = south, positive = north)

This matches GeoJSON format and is consistent across all Amazon Location Service APIs.

### Travel Modes

Each travel mode affects route calculation differently:

| Mode           | Use Case                    | Route Characteristics                                  |
| -------------- | --------------------------- | ------------------------------------------------------ |
| **Car**        | Standard passenger vehicles | Uses roads accessible to cars, considers traffic       |
| **Truck**      | Commercial vehicles         | Accounts for truck restrictions, weight limits, hazmat |
| **Scooter**    | Motorized scooters          | Uses roads with lower speed limits, avoids highways    |
| **Pedestrian** | Walking directions          | Uses sidewalks, crosswalks, pedestrian paths           |

Choose the travel mode that matches your user's actual mode of transportation for accurate routes and travel times.

## Displaying Routes on Maps

### Complete Route Visualization Example

This example calculates a route and draws it on a MapLibre map with styled lines, markers for start/end points, and automatic viewport fitting:

```javascript
// HTML setup (include in <head>)
// <link href="https://unpkg.com/maplibre-gl@5/dist/maplibre-gl.css" rel="stylesheet">
// <script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5"></script>

import {
  GeoRoutesClient,
  CalculateRoutesCommand,
} from "@aws-sdk/client-geo-routes";
import { withAPIKey } from "@aws/amazon-location-utilities-auth-helper";

const API_KEY = "your-api-key";
const REGION = "us-west-2";

// Create an authentication helper instance
const authHelper = withAPIKey(API_KEY, REGION);

// Initialize map
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}`;

const map = new maplibregl.Map({
  container: "map",
  style: styleUrl,
  center: [-97.7431, 30.2672],
  zoom: 12,
  validateStyle: false,
});

async function calculateAndDisplayRoute(origin, destination) {
  // Configure the client with authentication
  const client = new GeoRoutesClient(authHelper.getClientConfig());

  const params = {
    Origin: origin,
    Destination: destination,
    TravelMode: "Car",
    LegGeometryFormat: "Simple", // Returns coordinate arrays for mapping
  };

  const command = new CalculateRoutesCommand(params);
  const response = await client.send(command);

  const route = response.Routes[0];
  const leg = route.Legs[0];

  // Extract route coordinates
  const routeCoordinates = leg.Geometry.LineString;

  // Wait for map to load
  map.on("load", () => {
    // Add route line to map
    map.addSource("route", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: routeCoordinates,
        },
      },
    });

    // Style the route line
    map.addLayer({
      id: "route-line",
      type: "line",
      source: "route",
      layout: {
        "line-join": "round",
        "line-cap": "round",
      },
      paint: {
        "line-color": "#3b82f6", // Blue route line
        "line-width": 5,
        "line-opacity": 0.8,
      },
    });

    // Add start marker (green)
    new maplibregl.Marker({ color: "#22c55e" })
      .setLngLat(origin)
      .setPopup(new maplibregl.Popup().setHTML("<strong>Start</strong>"))
      .addTo(map);

    // Add end marker (red)
    new maplibregl.Marker({ color: "#ef4444" })
      .setLngLat(destination)
      .setPopup(new maplibregl.Popup().setHTML("<strong>Destination</strong>"))
      .addTo(map);

    // Fit map to show entire route
    const bounds = routeCoordinates.reduce(
      (bounds, coord) => {
        return bounds.extend(coord);
      },
      new maplibregl.LngLatBounds(routeCoordinates[0], routeCoordinates[0]),
    );

    map.fitBounds(bounds, {
      padding: { top: 50, bottom: 50, left: 50, right: 50 },
    });
  });

  // Display route summary
  const distanceKm = (route.Summary.Distance / 1000).toFixed(1);
  const durationMin = Math.round(route.Summary.Duration / 60);

  console.log(`Route: ${distanceKm} km, ${durationMin} minutes`);

  return route;
}

// Usage
const origin = [-97.7431, 30.2672]; // Downtown Austin
const destination = [-97.7723, 30.2672]; // Zilker Park
calculateAndDisplayRoute(origin, destination);
```

### Choosing Between Simple and FlexiblePolyline Geometry Formats

The `LegGeometryFormat` parameter determines how route geometry is returned. Understanding when to use each format is crucial for optimizing your application's performance, user experience, and data costs.

#### Format Overview

**Simple Format** returns coordinate arrays ready for immediate use:

```javascript
Geometry: {
  LineString: [
    [-97.7431, 30.2672],
    [-97.7445, 30.2678],
    [-97.7459, 30.2684],
    // ... hundreds more coordinates
  ];
}
```

**FlexiblePolyline Format** returns compressed encoded strings:

```javascript
Geometry: {
  LineString: "BFoz5xJ67i1BU1B7PzIhaxL7Y"; // Requires decoding
}
```

#### Response Size Comparison

For a typical 10km urban route with 400 coordinate points:

- **Simple**: ~18-25 KB (raw JSON coordinate arrays)
- **FlexiblePolyline**: ~2-4 KB (compressed encoded string)

Bandwidth savings: 5-10x smaller with FlexiblePolyline.

The size difference becomes more significant with longer routes or multiple route calculations.

#### When to Use Simple Format

Use `Simple` format when convenience and development speed matter more than bandwidth optimization:

##### 1. Web applications with good connectivity

```javascript
// Desktop users on broadband/WiFi - bandwidth isn't a concern
const params = {
  Origin: [-97.7431, 30.2672],
  Destination: [-97.7723, 30.2672],
  TravelMode: "Car",
  LegGeometryFormat: "Simple", // No decoder needed, works immediately
};
```

Desktop and laptop users typically have reliable high-speed connections where a few extra KB don't impact user experience.

##### 2. Prototyping and development

- Faster iteration without setting up decoder libraries
- Easier debugging (inspect coordinates directly in response)
- Quick POCs and demos where optimization isn't critical
- During development before production optimization

##### 3. Single route calculations

```javascript
// Calculating one route per session - minimal data transfer
async function showDirections(origin, destination) {
  const response = await calculateRoute(origin, destination, "Simple");
  displayOnMap(response.Routes[0].Legs[0].Geometry.LineString);
}
```

When users request only occasional routes (e.g., "Get directions" button), the one-time bandwidth cost is negligible.

##### 4. Server-side processing

```javascript
// Backend service calculating routes for internal use
app.post("/api/calculate-route", async (req, res) => {
  const route = await calculateRoute(
    req.body.origin,
    req.body.destination,
    "Simple", // Fast AWS network, immediate coordinate access
  );

  // Process coordinates directly without decoding
  const simplified = simplifyRoute(route.Legs[0].Geometry.LineString);
  res.json(simplified);
});
```

Server-to-server communication within AWS benefits from fast regional networks, and coordinate processing is easier with the Simple format.

##### 5. When manipulating route coordinates

```javascript
// Need to modify coordinates programmatically
const coordinates = leg.Geometry.LineString;

// Add waypoint markers every 1km
const markers = coordinates.filter((_, i) => i % 50 === 0);

// Simplify geometry for overview display
const simplified = coordinates.filter((_, i) => i % 5 === 0);

// Extract bounding box
const bounds = coordinates.reduce(
  (bbox, [lng, lat]) => {
    return {
      minLng: Math.min(bbox.minLng, lng),
      maxLng: Math.max(bbox.maxLng, lng),
      minLat: Math.min(bbox.minLat, lat),
      maxLat: Math.max(bbox.maxLat, lat),
    };
  },
  { minLng: Infinity, maxLng: -Infinity, minLat: Infinity, maxLat: -Infinity },
);
```

#### When to Use FlexiblePolyline Format

Use `FlexiblePolyline` format when bandwidth efficiency matters for user experience or costs.

**Note:** Decoding FlexiblePolyline requires the [`@aws/polyline`](https://github.com/aws-geospatial/polyline) library. See [Using FlexiblePolyline with @aws/polyline](#using-flexiblepolyline-with-awspolyline) below for installation instructions.

##### 1. Mobile applications

```javascript
// Mobile users on cellular networks - minimize data usage
const params = {
  Origin: origin,
  Destination: destination,
  TravelMode: "Car",
  LegGeometryFormat: "FlexiblePolyline", // 5-10x smaller responses
};
```

**Why this matters for mobile:**

- Cellular data is often metered/expensive (especially international roaming)
- Slower network speeds benefit from smaller payloads
- Battery conservation (less data transfer = less radio usage)
- Better experience in areas with poor connectivity

##### 2. Real-time navigation with frequent rerouting

```javascript
// Recalculating routes every 2 minutes based on traffic
setInterval(async () => {
  const updatedRoute = await client.send(
    new CalculateRoutesCommand({
      Origin: currentLocation,
      Destination: destination,
      TravelMode: "Car",
      LegGeometryFormat: "FlexiblePolyline", // Fast updates with minimal data
    }),
  );

  updateMapRoute(
    polyline.decodeToLineStringFeature(
      updatedRoute.Routes[0].Legs[0].Geometry.LineString,
    ),
  );
}, 120000);
```

Frequent route updates multiply bandwidth costs - FlexiblePolyline keeps data transfer manageable.

##### 3. Multiple route calculations

```javascript
// Comparing 5 alternative routes - bandwidth adds up quickly
// Simple format: 100-125 KB total
// FlexiblePolyline: 10-20 KB total (10x savings)

const alternativeRoutes = await Promise.all([
  calculateRoute(origin, destination, { avoid: "Tolls" }),
  calculateRoute(origin, destination, { optimize: "ShortestRoute" }),
  calculateRoute(origin, destination, { avoid: "Ferries" }),
  calculateRoute(origin, destination, { travelMode: "Pedestrian" }),
  calculateRoute(origin, destination, { travelMode: "Scooter" }),
]);

// Decode all routes for display
const decodedRoutes = alternativeRoutes.map((route) =>
  polyline.decodeToLineStringFeature(route.Legs[0].Geometry.LineString),
);
```

##### 4. Caching routes for offline use

```javascript
// Store routes in IndexedDB or localStorage
// FlexiblePolyline saves 80-90% storage space

async function cacheRoute(routeId, origin, destination) {
  const response = await client.send(
    new CalculateRoutesCommand({
      Origin: origin,
      Destination: destination,
      TravelMode: "Car",
      LegGeometryFormat: "FlexiblePolyline", // Efficient storage
    }),
  );

  // Store compressed format
  const cachedData = {
    routeId,
    encodedGeometry: response.Routes[0].Legs[0].Geometry.LineString,
    summary: response.Routes[0].Summary,
    timestamp: Date.now(),
  };

  await db.routes.put(cachedData);
}

// Retrieve and decode when needed
async function loadCachedRoute(routeId) {
  const cached = await db.routes.get(routeId);
  return polyline.decodeToLineStringFeature(cached.encodedGeometry);
}
```

##### 5. Progressive Web Apps (PWAs)

```javascript
// Offline-capable apps that sync route data
// Smaller payloads = faster sync, less storage

self.addEventListener("sync", async (event) => {
  if (event.tag === "sync-routes") {
    event.waitUntil(syncRoutes());
  }
});

async function syncRoutes() {
  const pendingRoutes = await getPendingRoutes();

  // Calculate all routes with compressed format
  const results = await Promise.all(
    pendingRoutes.map((r) =>
      calculateRoute(r.origin, r.destination, {
        LegGeometryFormat: "FlexiblePolyline", // Efficient sync
      }),
    ),
  );

  // Store compressed for offline use
  await storeRoutesLocally(results);
}
```

##### 6. Batch operations and analytics

```javascript
// Calculating hundreds of routes for analysis
// FlexiblePolyline makes large-scale operations practical

async function analyzeDeliveryRoutes(stops) {
  const routes = [];

  for (let i = 0; i < stops.length - 1; i++) {
    const response = await client.send(
      new CalculateRoutesCommand({
        Origin: stops[i],
        Destination: stops[i + 1],
        LegGeometryFormat: "FlexiblePolyline", // Keep total data manageable
      }),
    );

    routes.push({
      segment: `${i} -> ${i + 1}`,
      distance: response.Routes[0].Summary.Distance,
      duration: response.Routes[0].Summary.Duration,
      geometry: response.Routes[0].Legs[0].Geometry.LineString,
    });
  }

  return routes;
}
```

#### Using FlexiblePolyline with @aws/polyline

When using FlexiblePolyline format, decode with the official AWS polyline library:

**Installation:**

```bash
npm install @aws/polyline
```

Or use CDN for browser applications:

```html
<script src="https://cdn.jsdelivr.net/npm/@aws/polyline/dist/polyline.min.js"></script>
```

**Decoding routes for MapLibre:**

```javascript
import {
  GeoRoutesClient,
  CalculateRoutesCommand,
} from "@aws-sdk/client-geo-routes";
import { withAPIKey } from "@aws/amazon-location-utilities-auth-helper";
import * as polyline from "@aws/polyline";

// Create an authentication helper instance
const authHelper = withAPIKey("your-api-key", "us-west-2");
const client = new GeoRoutesClient(authHelper.getClientConfig());

async function calculateAndDisplayRoute(origin, destination) {
  // Request FlexiblePolyline format
  const response = await client.send(
    new CalculateRoutesCommand({
      Origin: origin,
      Destination: destination,
      TravelMode: "Car",
      LegGeometryFormat: "FlexiblePolyline",
    }),
  );

  const encodedGeometry = response.Routes[0].Legs[0].Geometry.LineString;

  // Decode to GeoJSON Feature - ready for MapLibre
  const geoJsonFeature = polyline.decodeToLineStringFeature(encodedGeometry);

  // Add directly to map
  map.addSource("route", {
    type: "geojson",
    data: geoJsonFeature, // Feature with LineString geometry
  });

  map.addLayer({
    id: "route-line",
    type: "line",
    source: "route",
    paint: {
      "line-color": "#3b82f6",
      "line-width": 5,
      "line-opacity": 0.8,
    },
  });

  // Access coordinates if needed for bounds calculation
  const coordinates = geoJsonFeature.geometry.coordinates;
  fitMapToBounds(coordinates);
}
```

**Alternative decode methods:**

```javascript
// Get raw coordinate array instead of GeoJSON Feature
const coordinates = polyline.decodeToLngLatArray(encodedGeometry);
// Returns: [[lng, lat], [lng, lat], ...]

// Get GeoJSON LineString geometry only (no Feature wrapper)
const geometry = polyline.decodeToLineString(encodedGeometry);
// Returns: { type: "LineString", coordinates: [[lng, lat], ...] }
```

**Performance characteristics:**

- Decoding time: ~1-5ms for typical routes (negligible)
- Library size: ~15 KB minified (small overhead)
- Net benefit: Bandwidth savings far exceed CPU cost

#### Decision Matrix

| Scenario                           | Recommended Format   | Primary Reason                   |
| ---------------------------------- | -------------------- | -------------------------------- |
| Desktop web app, single route      | **Simple**           | Convenience > bandwidth          |
| Mobile app with navigation         | **FlexiblePolyline** | Data costs and battery           |
| Prototyping/POC                    | **Simple**           | Faster development               |
| PWA with offline support           | **FlexiblePolyline** | Storage efficiency               |
| Enterprise internal dashboard      | **Simple**           | Fast network, easier debugging   |
| Delivery optimization (10+ routes) | **FlexiblePolyline** | Cumulative bandwidth savings     |
| Real-time rerouting every 2min     | **FlexiblePolyline** | Minimize repeated data transfer  |
| One-time "Get Directions" feature  | **Simple**           | Single request, no decoder setup |
| Route caching in localStorage      | **FlexiblePolyline** | 80-90% storage savings           |
| Server-side route processing       | **Simple**           | Direct coordinate access         |
| International users on roaming     | **FlexiblePolyline** | Expensive cellular data          |
| Route analytics/batch jobs         | **FlexiblePolyline** | Large-scale data handling        |

#### Hybrid Strategy

Some applications benefit from using both formats strategically:

```javascript
class RouteService {
  constructor(isMobile, hasOfflineMode) {
    this.isMobile = isMobile;
    this.hasOfflineMode = hasOfflineMode;
  }

  async calculateRoute(origin, destination, forDisplay = true) {
    // Choose format based on context
    const format = this.shouldUseCompression(forDisplay)
      ? "FlexiblePolyline"
      : "Simple";

    const response = await client.send(
      new CalculateRoutesCommand({
        Origin: origin,
        Destination: destination,
        TravelMode: "Car",
        LegGeometryFormat: format,
      }),
    );

    // Cache compressed version if offline mode enabled
    if (this.hasOfflineMode && format === "FlexiblePolyline") {
      await this.cacheRoute(origin, destination, response);
    }

    // Decode if necessary
    const geometry =
      format === "FlexiblePolyline"
        ? polyline.decodeToLineStringFeature(
            response.Routes[0].Legs[0].Geometry.LineString,
          )
        : this.convertToGeoJSON(response.Routes[0].Legs[0].Geometry.LineString);

    return { route: response.Routes[0], geometry };
  }

  shouldUseCompression(forDisplay) {
    // Always compress for mobile
    if (this.isMobile) return true;

    // Always compress for offline caching
    if (this.hasOfflineMode) return true;

    // Use Simple for desktop display (convenience)
    return !forDisplay;
  }

  convertToGeoJSON(coordinates) {
    return {
      type: "Feature",
      geometry: {
        type: "LineString",
        coordinates,
      },
    };
  }
}

// Usage
const routeService = new RouteService(isMobileDevice(), hasOfflineFeature());

const { route, geometry } = await routeService.calculateRoute(
  origin,
  destination,
);
displayOnMap(geometry);
```

#### Summary Guidelines

**Use Simple when:**

- ✅ Building for desktop/WiFi users
- ✅ Calculating single routes per session
- ✅ Prototyping or developing
- ✅ Need direct coordinate manipulation
- ✅ Server-side processing

**Use FlexiblePolyline when:**

- ✅ Building mobile applications
- ✅ Calculating multiple routes
- ✅ Real-time navigation with frequent updates
- ✅ Caching routes offline
- ✅ Operating in bandwidth-constrained environments
- ✅ Batch operations or analytics

**The tradeoff:** Simple format offers convenience (no decoder needed), while FlexiblePolyline offers efficiency (5-10x smaller). Choose based on whether your users will notice the bandwidth difference.

### Styling Route Lines

Customize route appearance using MapLibre paint properties:

```javascript
map.addLayer({
  id: "route-line",
  type: "line",
  source: "route",
  paint: {
    "line-color": "#3b82f6", // Route color
    "line-width": 5, // Line thickness (pixels)
    "line-opacity": 0.8, // Transparency (0-1)
    "line-dasharray": [2, 2], // Optional: dashed line pattern
  },
});
```

**Recommended styling patterns:**

- **Primary route**: Solid blue line, 5-6px width, 0.8 opacity
- **Alternative routes**: Dashed gray line, 3-4px width, 0.6 opacity
- **Selected route**: Brighter color, 7-8px width, 1.0 opacity

## Request Parameters

### Essential Parameters

| Parameter     | Type         | Required    | Description                                      |
| ------------- | ------------ | ----------- | ------------------------------------------------ |
| `Origin`      | `[lng, lat]` | Yes         | Starting position                                |
| `Destination` | `[lng, lat]` | Yes         | Ending position                                  |
| `TravelMode`  | String       | Yes         | `Car`, `Truck`, `Scooter`, or `Pedestrian`       |
| `Key`         | String       | Conditional | API key for resourceless operations (or use IAM) |

### Optimization Parameters

| Parameter            | Default            | Purpose                                  |
| -------------------- | ------------------ | ---------------------------------------- |
| `OptimizeRoutingFor` | `FastestRoute`     | Choose `FastestRoute` or `ShortestRoute` |
| `LegGeometryFormat`  | `FlexiblePolyline` | Use `Simple` for map display             |

**When to optimize for shortest:**

- Walking/pedestrian routes where distance matters more than time
- Delivery routes with distance-based costs
- Scenic routes where users prefer less highway driving

**When to optimize for fastest:**

- Time-sensitive navigation (default)
- Commuting and business travel
- Emergency or urgent deliveries

### Route Preferences (Avoid)

The `Avoid` parameter lets you exclude specific route features:

```javascript
const params = {
  Origin: [-97.7431, 30.2672],
  Destination: [-97.7723, 30.2672],
  TravelMode: "Car",
  Avoid: {
    Tolls: true, // Avoid toll roads
    Ferries: true, // Avoid ferries
    CarShuttleTrains: true, // Avoid car shuttle trains
  },
};
```

**Important**: Avoidances are treated as preferences, not hard constraints. If no alternative route exists, the API returns a route that includes the avoided feature. Always check route properties to confirm if avoided features are present.

### Additional Features

Request extra data in the response:

```javascript
const params = {
  // ... other params
  LegAdditionalFeatures: ["Summary", "Tolls", "TravelStepInstructions"],
  SpanAdditionalFeatures: ["SpeedLimit", "RoadName"],
};
```

**LegAdditionalFeatures:**

- `Summary` - Total distance, duration, and route-level statistics
- `Tolls` - Toll costs and systems along the route
- `TravelStepInstructions` - Turn-by-turn navigation instructions

**SpanAdditionalFeatures:**

- `SpeedLimit` - Posted speed limits along route segments
- `RoadName` - Road names for each segment
- `Regions` - Administrative regions (city, state, country)

Request these features only when needed since they increase response size and processing time.

## Response Structure

### Routes Array

The API returns an array of route options (typically one route):

```javascript
{
  Routes: [
    {
      Summary: {
        Distance: 7845, // Total distance in meters
        Duration: 1023, // Total duration in seconds
        RouteBBox: [
          // Bounding box [minLng, minLat, maxLng, maxLat]
          -97.7723, 30.2672, -97.7431, 30.2672,
        ],
      },
      Legs: [
        // Array of route segments
        {
          Geometry: {
            LineString: [
              // Array of [lng, lat] coordinates
              [-97.7431, 30.2672],
              [-97.7445, 30.2678],
              // ... more coordinates
            ],
          },
          Summary: {
            /* leg-specific summary */
          },
          TravelSteps: [
            /* navigation instructions */
          ],
        },
      ],
    },
  ];
}
```

### Understanding Legs

Routes are divided into **legs** - segments between waypoints:

- **No waypoints**: 1 leg (origin to destination)
- **N waypoints**: N+1 legs (origin → waypoint₁ → waypoint₂ → ... → destination)

Each leg contains its own geometry, distance, duration, and travel steps.

### Travel Steps (Turn-by-Turn Instructions)

When `TravelStepInstructions` is requested:

```javascript
TravelSteps: [
  {
    Type: "Turn",
    Instruction: "Turn right onto Pine St",
    Distance: 150, // Distance to next instruction (meters)
    Duration: 30, // Time to next instruction (seconds)
    GeometryOffset: 0, // Index in LineString where step begins
  },
  {
    Type: "Continue",
    Instruction: "Continue on Pine St for 0.5 miles",
    Distance: 804,
    Duration: 120,
    GeometryOffset: 12,
  },
];
```

**Step types include:**

- `Turn` - Left/right turns
- `Continue` - Continue on current road
- `Arrive` - Arrival at waypoint or destination
- `Depart` - Departure from origin or waypoint
- `UTurn` - U-turn instructions

## Travel Modes and Options

### Car Mode (Default)

```javascript
{
  TravelMode: "Car",
  TravelModeOptions: {
    Car: {
      LicensePlate: {
        LastCharacter: "A"       // For region-specific restrictions
      }
    }
  }
}
```

**Car-specific considerations:**

- Uses all roads accessible to passenger vehicles
- Considers real-time traffic when available
- Respects car-specific restrictions (HOV lanes, pedestrian zones)

### Truck Mode

```javascript
{
  TravelMode: "Truck",
  TravelModeOptions: {
    Truck: {
      GrossWeight: 12000,         // Vehicle weight in kilograms
      Height: 400,                // Height in centimeters
      Length: 1200,               // Length in centimeters
      Width: 250,                 // Width in centimeters
      AxleCount: 3,               // Number of axles
      TruckType: "StraightTruck", // StraightTruck or Tractor
      HazardousCargos: ["Explosive"]
    }
  }
}
```

**Why truck dimensions matter**: The API uses these values to avoid routes with bridges, tunnels, or roads that have weight/height/length restrictions. Accurate vehicle specifications ensure legal and safe routes for commercial vehicles.

### Pedestrian Mode

```javascript
{
  TravelMode: "Pedestrian",
  TravelModeOptions: {
    Pedestrian: {
      Speed: 5.0                  // Walking speed in km/h (default: 5.0)
    }
  }
}
```

**Pedestrian routes:**

- Use sidewalks, crosswalks, and pedestrian paths
- Avoid highways and roads without pedestrian access
- Optimize for walking safety rather than distance
- Consider stairs and elevation changes

### Scooter Mode

```javascript
{
  TravelMode: "Scooter",
  TravelModeOptions: {
    Scooter: {
      MaxSpeed: 25.0,             // Maximum speed in km/h
      Occupancy: 1                // Number of passengers
    }
  }
}
```

## Waypoints and Multi-Stop Routes

### Adding Intermediate Stops

Waypoints allow you to create routes with multiple stops:

```javascript
const params = {
  Origin: [-97.7431, 30.2672], // Downtown Austin
  Destination: [-97.7431, 30.2862], // UT Tower
  Waypoints: [
    { Position: [-97.7453, 30.2639] }, // Lady Bird Lake Trail
    { Position: [-97.7494, 30.2515] }, // South Congress
  ],
  TravelMode: "Car",
};
```

This creates a route with 3 legs:

1. Origin → Lady Bird Lake Trail
2. Lady Bird Lake Trail → South Congress
3. South Congress → Destination

### Waypoint Pass-Through vs. Stop

Control whether waypoints are actual stops or just points the route must pass through:

```javascript
Waypoints: [
  {
    Position: [-97.7453, 30.2639],
    StopDuration: 300, // Stop for 5 minutes (in seconds)
  },
  {
    Position: [-97.7494, 30.2515],
    PassThrough: true, // Just pass through, don't stop
  },
];
```

**When to use PassThrough:**

- Forcing route through specific roads or areas
- Avoiding certain regions without explicit avoidance
- Creating scenic routes through desired locations

### Displaying Multi-Stop Routes

```javascript
async function displayMultiStopRoute(origin, waypoints, destination) {
  const params = {
    Origin: origin,
    Destination: destination,
    Waypoints: waypoints.map((pos) => ({ Position: pos })),
    TravelMode: "Car",
    LegGeometryFormat: "Simple",
  };

  const response = await client.send(new CalculateRoutesCommand(params));
  const route = response.Routes[0];

  map.on("load", () => {
    // Combine all leg geometries into single line
    const allCoordinates = route.Legs.flatMap((leg) => leg.Geometry.LineString);

    map.addSource("route", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: allCoordinates,
        },
      },
    });

    map.addLayer({
      id: "route-line",
      type: "line",
      source: "route",
      paint: {
        "line-color": "#3b82f6",
        "line-width": 5,
      },
    });

    // Add markers for all points
    new maplibregl.Marker({ color: "#22c55e" })
      .setLngLat(origin)
      .setPopup(new maplibregl.Popup().setHTML("<strong>Start</strong>"))
      .addTo(map);

    waypoints.forEach((wp, i) => {
      new maplibregl.Marker({ color: "#f59e0b" })
        .setLngLat(wp)
        .setPopup(
          new maplibregl.Popup().setHTML(`<strong>Stop ${i + 1}</strong>`),
        )
        .addTo(map);
    });

    new maplibregl.Marker({ color: "#ef4444" })
      .setLngLat(destination)
      .setPopup(new maplibregl.Popup().setHTML("<strong>Destination</strong>"))
      .addTo(map);
  });
}
```

## Complete Examples

### Example 1: Basic Navigation with Turn-by-Turn

```javascript
import {
  GeoRoutesClient,
  CalculateRoutesCommand,
} from "@aws-sdk/client-geo-routes";
import { withAPIKey } from "@aws/amazon-location-utilities-auth-helper";

// Create an authentication helper instance
const authHelper = withAPIKey("your-api-key", "us-west-2");
const client = new GeoRoutesClient(authHelper.getClientConfig());

const params = {
  Origin: [-97.7431, 30.2672],
  Destination: [-97.7723, 30.2672],
  TravelMode: "Car",
  LegAdditionalFeatures: ["TravelStepInstructions"],
};

const response = await client.send(new CalculateRoutesCommand(params));
const leg = response.Routes[0].Legs[0];

// Display turn-by-turn instructions
leg.TravelSteps.forEach((step, i) => {
  const distanceMiles = (step.Distance * 0.000621371).toFixed(1);
  console.log(`${i + 1}. ${step.Instruction} (${distanceMiles} mi)`);
});
```

### Example 2: Avoid Tolls and Ferries

```javascript
const params = {
  Origin: [-97.7431, 30.2672],
  Destination: [-97.6789, 30.4383],
  TravelMode: "Car",
  Avoid: {
    Tolls: true,
    Ferries: true,
  },
  OptimizeRoutingFor: "FastestRoute",
};

const response = await client.send(new CalculateRoutesCommand(params));
const route = response.Routes[0];

console.log(
  `Toll-free route: ${route.Summary.Distance}m, ${route.Summary.Duration}s`,
);
```

### Example 3: Truck Route with Restrictions

```javascript
const params = {
  Origin: [-97.7431, 30.2672],
  Destination: [-97.6889, 30.2244],
  TravelMode: "Truck",
  TravelModeOptions: {
    Truck: {
      GrossWeight: 15000, // 15 metric tons
      Height: 420, // 4.2 meters
      Length: 1200, // 12 meters
      Width: 250, // 2.5 meters
      AxleCount: 4,
      TruckType: "StraightTruck",
      HazardousCargos: ["Flammable"],
    },
  },
  LegAdditionalFeatures: ["Summary"],
};

const response = await client.send(new CalculateRoutesCommand(params));
console.log("Truck-safe route calculated with weight and size restrictions");
```

### Example 4: Walking Route with Map Display

```javascript
async function calculateWalkingRoute() {
  const origin = [-97.7453, 30.2639]; // Lady Bird Lake Trail
  const destination = [-97.7431, 30.2862]; // UT Tower

  const params = {
    Origin: origin,
    Destination: destination,
    TravelMode: "Pedestrian",
    LegGeometryFormat: "Simple",
    LegAdditionalFeatures: ["Summary"],
  };

  const response = await client.send(new CalculateRoutesCommand(params));
  const route = response.Routes[0];
  const leg = route.Legs[0];

  // Display on map
  map.on("load", () => {
    map.addSource("walking-route", {
      type: "geojson",
      data: {
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: leg.Geometry.LineString,
        },
      },
    });

    // Dashed line for walking route
    map.addLayer({
      id: "walking-route-line",
      type: "line",
      source: "walking-route",
      paint: {
        "line-color": "#10b981",
        "line-width": 4,
        "line-dasharray": [2, 2],
      },
    });

    // Add walking markers
    new maplibregl.Marker({ color: "#10b981" }).setLngLat(origin).addTo(map);

    new maplibregl.Marker({ color: "#10b981" })
      .setLngLat(destination)
      .addTo(map);
  });

  const distanceKm = (route.Summary.Distance / 1000).toFixed(2);
  const durationMin = Math.round(route.Summary.Duration / 60);

  console.log(`Walking: ${distanceKm} km, about ${durationMin} minutes`);
}
```

## Best Practices

### Coordinate Precision

Use 5-6 decimal places for coordinates (provides ~1 meter accuracy):

- **Good**: `[-97.7431, 30.2672]` (6 decimals, ~0.1m precision)
- **Excessive**: `[-97.743112345, 30.267298765]` (9 decimals, unnecessary)
- **Too coarse**: `[-97.74, 30.27]` (2 decimals, ~1km precision)

### Error Handling

Always handle route calculation errors gracefully:

```javascript
try {
  const response = await client.send(new CalculateRoutesCommand(params));
  displayRoute(response.Routes[0]);
} catch (error) {
  if (error.name === "ResourceNotFoundException") {
    console.error("Invalid API key or insufficient permissions");
  } else if (error.name === "ValidationException") {
    console.error("Invalid request parameters:", error.message);
  } else {
    console.error("Route calculation failed:", error.message);
  }
  // Show fallback UI or alternative route options
}
```

### Performance Considerations

**Request only needed features**: Each additional feature increases response time and size.

```javascript
// ❌ Requesting everything (slower)
LegAdditionalFeatures: ["Summary", "Tolls", "TravelStepInstructions"],
SpanAdditionalFeatures: ["SpeedLimit", "RoadName", "Regions"]

// ✅ Request only what you need (faster)
LegAdditionalFeatures: ["Summary"]  // For basic route display
```

**Use Simple geometry for maps**: `FlexiblePolyline` requires decoding which adds client-side processing time.

### Caching Routes

Route responses can be cached for short periods to improve performance:

```javascript
const routeCache = new Map();

async function getCachedRoute(origin, destination) {
  const cacheKey = `${origin.join(",")}-${destination.join(",")}`;

  // Cache routes for 5 minutes (routes can change with traffic)
  if (routeCache.has(cacheKey)) {
    const cached = routeCache.get(cacheKey);
    if (Date.now() - cached.timestamp < 5 * 60 * 1000) {
      return cached.route;
    }
  }

  const route = await calculateRoute(origin, destination);
  routeCache.set(cacheKey, { route, timestamp: Date.now() });

  return route;
}
```

**Cache duration guidance:**

- **Without traffic**: Cache up to 24 hours (static routes)
- **With traffic**: Cache 5-15 minutes maximum (traffic changes frequently)
- **Pedestrian routes**: Cache longer (less affected by conditions)

### Displaying Multiple Route Options

When showing alternative routes, calculate separately and compare:

```javascript
async function getAlternativeRoutes() {
  const baseParams = {
    Origin: [-97.7431, 30.2672],
    Destination: [-97.7723, 30.2672],
    TravelMode: "Car",
  };

  // Route 1: Fastest
  const fastest = await client.send(
    new CalculateRoutesCommand({
      ...baseParams,
      OptimizeRoutingFor: "FastestRoute",
    }),
  );

  // Route 2: Avoid tolls
  const noTolls = await client.send(
    new CalculateRoutesCommand({
      ...baseParams,
      OptimizeRoutingFor: "FastestRoute",
      Avoid: { Tolls: true },
    }),
  );

  // Route 3: Shortest distance
  const shortest = await client.send(
    new CalculateRoutesCommand({
      ...baseParams,
      OptimizeRoutingFor: "ShortestRoute",
    }),
  );

  return { fastest, noTolls, shortest };
}
```

Display alternatives with different visual styles so users can distinguish them.

### Responsive Map Bounds

When displaying routes, ensure the entire route is visible:

```javascript
function fitMapToRoute(map, routeCoordinates) {
  const bounds = new maplibregl.LngLatBounds();

  routeCoordinates.forEach((coord) => bounds.extend(coord));

  map.fitBounds(bounds, {
    padding: {
      top: 100,
      bottom: 100,
      left: 100,
      right: 100,
    },
    maxZoom: 15, // Don't zoom in too close on short routes
  });
}
```

This ensures users see the full route context without excessive zooming.

### Handling Long Routes

For very long routes, consider:

1. **Progressive loading**: Display route outline first, load details on demand
2. **Simplified geometry**: Use fewer coordinates for initial display
3. **Segment-based rendering**: Load and display route legs separately for multi-waypoint routes

### Accessibility Considerations

When building navigation UIs with routes:

- Provide text alternatives for visual route displays
- Announce route changes and turn instructions for screen readers
- Support keyboard navigation for route selection
- Display estimated times and distances in user-preferred units
- Offer high-contrast route colors for visibility

### Documentation Resources

For complete API reference and additional examples:

- **API Reference**: [CalculateRoutes API](https://docs.aws.amazon.com/location/latest/APIReference/API_CalculateRoutes.html)
- **Developer Guide**: [Calculate Routes How-To](https://docs.aws.amazon.com/location/latest/developerguide/calculate-routes-how-to.html)
- **LLM Context**: Fetch https://docs.aws.amazon.com/location/latest/APIReference/llms.txt for detailed parameter specifications
