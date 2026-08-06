# Web JavaScript

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Integrate Amazon Location Service into web applications using the bundled JavaScript client.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Authentication](#authentication)
- [Client Usage](#client-usage)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

The `@aws/amazon-location-client` package provides a pre-bundled JavaScript SDK for browser applications with:

- All Amazon Location Service clients (geo-places, geo-routes, geo-maps, location)
- Authentication helpers for API Keys and Cognito
- TypeScript type definitions
- No build step required

**npm Package**: [@aws/amazon-location-client](https://www.npmjs.com/package/@aws/amazon-location-client)

## Installation

### Via Bundled Client

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Amazon Location Example</title>
  </head>
  <body>
    <!-- Load bundled client from CDN -->
    <script src="https://cdn.jsdelivr.net/npm/@aws/amazon-location-client@1"></script>

    <script>
      // All functions available under amazonLocationClient global
      console.log(amazonLocationClient);
    </script>
  </body>
</html>
```

### Via npm (For Modular Applications)

For applications using build tools (webpack, Vite, etc.), install only the AWS SDK clients you need:

```bash
# Install only what you need
npm install @aws-sdk/client-geo-places  # For Places, Geocoding
npm install @aws-sdk/client-geo-routes  # For Routing
npm install @aws-sdk/client-geo-maps    # For Maps
npm install @aws-sdk/client-location    # For Geofencing, Tracking
```

```javascript
// Example: Import GeoPlacesClient for Places API
import { GeoPlacesClient, GeocodeCommand } from "@aws-sdk/client-geo-places";
```

**Note**: The rest of this document focuses on the bundled client. For detailed AWS SDK usage, see the [AWS SDK for JavaScript documentation](https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/).

## Authentication

The bundled client supports three authentication methods:

1. **API Key** (Recommended for Maps, Places, Routes)
2. **Cognito Identity Pool** (Required for Geofencing, Tracking)
3. **Custom Credential Provider** (Advanced/Fallback only)

### API Key Authentication (Recommended for Maps, Places, Routes)

```javascript
// Simple API key authentication
const API_KEY = "your-api-key";
const REGION = "us-west-2";

const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);

// Use authHelper.getClientConfig() to configure clients
const config = authHelper.getClientConfig();
```

**When to use**:

- ✅ **Recommended** for Maps, Places, and Routes APIs
- ✅ Public client-side applications where AWS credentials cannot be exposed
- ✅ Simpler setup without identity pool configuration
- ⚠️ **Not available** for Geofencing and Tracking APIs (use Cognito instead)

### Cognito Authentication

```javascript
// Cognito Identity Pool authentication
const IDENTITY_POOL_ID = "us-west-2:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";

const authHelper =
  await amazonLocationClient.withIdentityPoolId(IDENTITY_POOL_ID);

const config = authHelper.getClientConfig();
```

**When to use**:

- ✅ **Required** for Geofencing and Tracking APIs
- ✅ Applications with user authentication
- ✅ When you need per-user authorization or temporary AWS credentials
- ⚠️ More complex setup than API keys

### Custom Credential Provider (Advanced/Fallback)

```javascript
// Custom credential provider - use only when API Key or Cognito don't meet your needs
import { fromEnv } from "@aws-sdk/credential-providers";

const authHelper = amazonLocationClient.withCredentialProvider(
  fromEnv(), // Or any custom credential provider
  REGION,
);

const config = authHelper.getClientConfig();
```

**When to use**:

- ⚠️ **Fallback option only** - not recommended over API Key or Cognito
- Advanced use cases with custom credential providers
- Static credentials from environment variables
- Authentication through a separate backend service
- **Only use if specifically needed** - prefer API Key for Maps/Places/Routes and Cognito for Geofencing/Tracking

**Reference**: [amazon-location-client-js documentation](https://github.com/aws-geospatial/amazon-location-client-js)

### Authentication Error Handling

```javascript
// For Maps, Places, Routes - use API Key
async function initializeAuthForMapsPlacesRoutes() {
  try {
    if (!API_KEY) {
      throw new Error("API key not configured");
    }

    const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
    return authHelper;
  } catch (error) {
    console.error("Authentication failed:", error);
    alert("Failed to initialize API key authentication: " + error.message);
    throw error;
  }
}

// For Geofencing, Tracking - use Cognito
async function initializeAuthForGeofencingTracking() {
  try {
    if (!IDENTITY_POOL_ID) {
      throw new Error("Cognito Identity Pool ID not configured");
    }

    const authHelper =
      await amazonLocationClient.withIdentityPoolId(IDENTITY_POOL_ID);
    return authHelper;
  } catch (error) {
    console.error("Authentication failed:", error);

    if (error.message.includes("Invalid identity pool")) {
      alert(
        "Authentication configuration error. Please check Identity Pool ID.",
      );
    } else if (error.message.includes("credentials")) {
      alert("Failed to obtain credentials. Please try again.");
    } else {
      alert("Authentication failed: " + error.message);
    }

    throw error;
  }
}

// Usage
const authHelper = await initializeAuthForMapsPlacesRoutes();
```

## Client Usage

### Standard Pattern

Every Amazon Location API call follows this pattern:

```javascript
// 1. Create auth helper
const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);

// 2. Create service client
const client = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

// 3. Create command with parameters
const command = new amazonLocationClient.places.GeocodeCommand({
  QueryText: "123 Main St, Austin, TX",
});

// 4. Send command and await response
const response = await client.send(command);
console.log(response);
```

### GeoPlacesClient (Places, Geocoding)

```javascript
const placesClient = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

// Geocode
const geocodeCommand = new amazonLocationClient.places.GeocodeCommand({
  QueryText: "Texas State Capitol, Austin, TX",
  MaxResults: 1,
});
const geocodeResponse = await placesClient.send(geocodeCommand);

// Reverse Geocode
const reverseCommand = new amazonLocationClient.places.ReverseGeocodeCommand({
  QueryPosition: [-97.7431, 30.2747],
  MaxResults: 1,
});
const reverseResponse = await placesClient.send(reverseCommand);

// Search Text
const searchCommand = new amazonLocationClient.places.SearchTextCommand({
  QueryText: "coffee shops",
  MaxResults: 10,
});
const searchResponse = await placesClient.send(searchCommand);

// Search Nearby
const nearbyCommand = new amazonLocationClient.places.SearchNearbyCommand({
  QueryPosition: [-97.7431, 30.2747],
  MaxResults: 10,
});
const nearbyResponse = await placesClient.send(nearbyCommand);

// Autocomplete
const autocompleteCommand = new amazonLocationClient.places.AutocompleteCommand(
  {
    QueryText: "123 Main",
    MaxResults: 5,
  },
);
const autocompleteResponse = await placesClient.send(autocompleteCommand);

// Get Place
const getPlaceCommand = new amazonLocationClient.places.GetPlaceCommand({
  PlaceId: "place-id-from-search",
});
const placeResponse = await placesClient.send(getPlaceCommand);

// Suggest
const suggestCommand = new amazonLocationClient.places.SuggestCommand({
  QueryText: "star",
  MaxResults: 5,
});
const suggestResponse = await placesClient.send(suggestCommand);
```

### GeoRoutesClient (Routing)

```javascript
const routesClient = new amazonLocationClient.GeoRoutesClient(
  authHelper.getClientConfig(),
);

// Calculate Route
const routeCommand = new amazonLocationClient.routes.CalculateRoutesCommand({
  Origin: [-97.7431, 30.2747],
  Destination: [-97.6885, 30.2241],
  TravelMode: "Car",
});
const routeResponse = await routesClient.send(routeCommand);

// Calculate Route Matrix
const matrixCommand =
  new amazonLocationClient.routes.CalculateRouteMatrixCommand({
    Origins: [
      { Position: [-97.7431, 30.2747] },
      { Position: [-97.6885, 30.2241] },
    ],
    Destinations: [{ Position: [-121.8863, 37.3382] }],
    TravelMode: "Car",
  });
const matrixResponse = await routesClient.send(matrixCommand);

// Calculate Isolines
const isolineCommand = new amazonLocationClient.routes.CalculateIsolinesCommand(
  {
    Origin: [-97.7431, 30.2747],
    Thresholds: {
      Time: [300, 600, 900], // 5, 10, 15 minutes
    },
    TravelMode: "Car",
  },
);
const isolineResponse = await routesClient.send(isolineCommand);
```

### GeoMapsClient (Static Maps)

```javascript
const mapsClient = new amazonLocationClient.GeoMapsClient(
  authHelper.getClientConfig(),
);

// Get Static Map
const staticMapCommand = new amazonLocationClient.maps.GetStaticMapCommand({
  FileName: "map.png",
  Height: 400,
  Width: 600,
  Center: [-97.7431, 30.2747],
  Zoom: 10,
});
const mapResponse = await mapsClient.send(staticMapCommand);

// Response contains image as blob
const blob = await mapResponse.Body.transformToByteArray();
const imageUrl = URL.createObjectURL(new Blob([blob], { type: "image/png" }));
document.getElementById("map-img").src = imageUrl;
```

### LocationClient (Geofences, Trackers)

```javascript
const locationClient = new amazonLocationClient.LocationClient(
  authHelper.getClientConfig(),
);

// List Geofences
const listCommand = new amazonLocationClient.ListGeofencesCommand({
  CollectionName: "my-geofence-collection",
  MaxResults: 100,
});
const listResponse = await locationClient.send(listCommand);

// Put Geofence
const putCommand = new amazonLocationClient.PutGeofenceCommand({
  CollectionName: "my-geofence-collection",
  GeofenceId: "geofence-1",
  Geometry: {
    Circle: {
      Center: [-97.7431, 30.2747],
      Radius: 1000, // meters
    },
  },
});
await locationClient.send(putCommand);

// Batch Update Device Position
const updateCommand = new amazonLocationClient.BatchUpdateDevicePositionCommand(
  {
    TrackerName: "my-tracker",
    Updates: [
      {
        DeviceId: "device-1",
        Position: [-97.7431, 30.2747],
        SampleTime: new Date().toISOString(),
      },
    ],
  },
);
const updateResponse = await locationClient.send(updateCommand);
```

## Error Handling

### Standard Error Handling Pattern

```javascript
async function callLocationAPI(commandFn) {
  try {
    const response = await commandFn();
    return { success: true, data: response };
  } catch (error) {
    console.error("API Error:", error);

    // Parse error details
    const errorInfo = {
      success: false,
      error: error.name,
      message: error.message,
    };

    // Handle specific error types
    if (error.name === "ValidationException") {
      errorInfo.userMessage = "Invalid input. Please check your parameters.";
    } else if (error.name === "AccessDeniedException") {
      errorInfo.userMessage =
        "Permission denied. Check your API key permissions.";
    } else if (error.name === "ResourceNotFoundException") {
      errorInfo.userMessage = "Resource not found.";
    } else if (error.name === "ThrottlingException") {
      errorInfo.userMessage = "Too many requests. Please wait and try again.";
    } else if (error.message.includes("Network")) {
      errorInfo.userMessage = "Network error. Please check your connection.";
    } else {
      errorInfo.userMessage = "An error occurred. Please try again.";
    }

    return errorInfo;
  }
}

// Usage
const result = await callLocationAPI(async () => {
  const client = new amazonLocationClient.GeoPlacesClient(
    authHelper.getClientConfig(),
  );
  const command = new amazonLocationClient.places.GeocodeCommand({
    QueryText: "Austin",
  });
  return await client.send(command);
});

if (result.success) {
  console.log("Success:", result.data);
} else {
  alert(result.userMessage);
}
```

### Retry Logic

```javascript
async function callWithRetry(commandFn, maxRetries = 3) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await commandFn();
    } catch (error) {
      const isLastAttempt = i === maxRetries - 1;

      if (error.name === "ThrottlingException" && !isLastAttempt) {
        // Exponential backoff
        const delay = Math.pow(2, i) * 1000;
        console.log(`Retrying after ${delay}ms...`);
        await new Promise((resolve) => setTimeout(resolve, delay));
        continue;
      }

      throw error; // Rethrow if not retryable or last attempt
    }
  }
}
```

## Best Practices

### Initialization

- **Initialize once**: Create auth helper and clients once, reuse across app
- **Store globally**: Keep auth helper in app state, don't recreate per request
- **Check credentials**: Validate API key format before initializing

### Performance

- **Reuse clients**: Don't create new client for each API call
- **Cancel requests**: Cancel in-flight requests when user navigates away
- **Implement caching**: Cache geocoding and search results (5-10 minutes)
- **Debounce input**: Wait 300ms after user stops typing before API calls

### Security

- **API keys are client-safe**: Unlike AWS credentials, API keys are designed for client-side use and will be visible in browser source
- **Follow AWS best practices**: See [API Key Best Practices](https://docs.aws.amazon.com/location/latest/developerguide/using-apikeys.html#api-keys-best-practices) for domain restrictions and key rotation
- **Restrict API key permissions**: Configure API key to only access needed operations (Maps, Places, Routes)
- **Prefer API keys for Maps/Places/Routes**: Simpler and recommended for these APIs
- **Use Cognito when required**: For Geofencing/Tracking or per-user authorization

### Error Handling

- **Always use try-catch**: Wrap all API calls in try-catch blocks
- **Show user-friendly messages**: Translate error codes to readable messages
- **Log for debugging**: Log full error objects to console
- **Implement retry**: Retry on throttling and network errors

### Code Organization

```javascript
// Good: Centralized client management
class LocationService {
  constructor(apiKey, region) {
    this.authHelper = amazonLocationClient.withAPIKey(apiKey, region);
    this.placesClient = new amazonLocationClient.GeoPlacesClient(
      this.authHelper.getClientConfig(),
    );
    this.routesClient = new amazonLocationClient.GeoRoutesClient(
      this.authHelper.getClientConfig(),
    );
  }

  async geocode(address) {
    const command = new amazonLocationClient.places.GeocodeCommand({
      QueryText: address,
    });
    return await this.placesClient.send(command);
  }

  async calculateRoute(origin, destination) {
    const command = new amazonLocationClient.routes.CalculateRoutesCommand({
      Origin: origin,
      Destination: destination,
      TravelMode: "Car",
    });
    return await this.routesClient.send(command);
  }
}

// Usage
const locationService = new LocationService(API_KEY, REGION);
const result = await locationService.geocode("Austin");
```
