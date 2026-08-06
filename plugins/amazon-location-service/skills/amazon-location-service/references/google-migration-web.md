# Google Maps Migration (JavaScript)

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Migrate JavaScript web applications from Google Maps API to Amazon Location Service with minimal code changes using the Migration SDK, or transition to native Amazon Location APIs for full feature access.

## Table of Contents

- [Migration Strategy Overview](#migration-strategy-overview)
- [Phase 1: Migration SDK (Recommended First)](#phase-1-migration-sdk-recommended-first)
- [Phase 2: Native Amazon Location APIs](#phase-2-native-amazon-location-apis)
- [API Mappings Reference](#api-mappings-reference)
- [Helper and Math Libraries](#helper-and-math-libraries)
- [Migration Guides](#migration-guides)

## Migration Strategy Overview

Amazon Location provides two migration paths for JavaScript applications:

### Two-Phase Approach (Recommended)

```
Phase 1: Migration SDK          Phase 2: Native APIs
┌────────────────────┐          ┌────────────────────┐
│ Drop-in replacement│   →      │ Full feature access│
│ Minimal changes    │          │ Direct AWS SDK     │
│ Quick migration    │          │ No google.maps     │
└────────────────────┘          └────────────────────┘
     Hours to Days                  Days to Weeks
```

**When to use each phase:**

| Situation                                      | Recommended Phase | Why                                                                                 |
| ---------------------------------------------- | ----------------- | ----------------------------------------------------------------------------------- |
| Need to migrate quickly                        | Phase 1 (SDK)     | Hours instead of weeks - just change the script import                              |
| Using unsupported Google APIs                  | Phase 2 (Native)  | SDK doesn't support all Google APIs (see [limitations](#migration-sdk-limitations)) |
| Want maximum performance                       | Phase 2 (Native)  | No abstraction layer overhead                                                       |
| Building new application                       | Phase 2 (Native)  | Start with native APIs from the beginning                                           |
| Legacy codebase with complex Google Maps usage | Phase 1 → Phase 2 | Migrate incrementally - SDK first, then refactor                                    |

### Decision Flowchart

```
Are you migrating existing Google Maps code?
├─ Yes → Does Migration SDK support your Google APIs?
│        ├─ Yes → START with Phase 1 (Migration SDK)
│        │        Can transition to Phase 2 later for optimization
│        └─ No → Use Phase 2 (Native APIs)
│                 SDK won't work - go directly to native
└─ No (new app) → Use Phase 2 (Native APIs)
                  Start with native APIs from the beginning
```

## Phase 1: Migration SDK (Recommended First)

The [Amazon Location Migration SDK](https://github.com/aws-geospatial/amazon-location-migration) provides a drop-in replacement for Google Maps JavaScript API.

### Key Benefits

- **Minimal code changes** - Often just changing the script import
- **Keeps google.maps namespace** - Existing code works as-is
- **Fast migration** - Hours instead of weeks
- **Incremental transition** - Migrate to native APIs later

### Installation

**Replace your Google Maps import with the Migration SDK:**

#### Dynamic Library Import

**Before (Google Maps):**

```javascript
<script>
  (g=>{var h,a,k,p="The Google Maps JavaScript API",c="google",...
    key: "YOUR_GOOGLE_API_KEY",
    v: "weekly",
  });
</script>
```

**After (Migration SDK):**

```html
<script src="https://cdn.jsdelivr.net/npm/@aws/amazon-location-migration-sdk/dist/amazonLocationMigrationSDK.min.js?region=us-west-2&apiKey=YOUR_AMAZON_LOCATION_API_KEY"></script>
```

#### Legacy Script Tag

**Before (Google Maps):**

```html
<script
  async
  src="https://maps.googleapis.com/maps/api/js?key=YOUR_API_KEY&loading=async&callback=initMap&libraries=places"
></script>
```

**After (Migration SDK):**

```html
<script
  async
  src="https://cdn.jsdelivr.net/npm/@aws/amazon-location-migration-sdk/dist/amazonLocationMigrationSDK.min.js?callback=initMap&region=us-west-2&apiKey=YOUR_AMAZON_LOCATION_API_KEY"
></script>
```

#### NPM js-api-loader

**Before (Google Maps):**

```javascript
import { Loader } from "@googlemaps/js-api-loader";

const loader = new Loader({
  apiKey: "YOUR_GOOGLE_API_KEY",
  version: "weekly",
});
```

**After (Migration SDK):**

```javascript
import { Loader } from "@aws/amazon-location-migration-sdk";

const loader = new Loader({
  apiKey: "YOUR_AMAZON_LOCATION_API_KEY",
  region: "us-west-2", // Optional, defaults to us-west-2
  version: "weekly",
});
```

### Your Existing Code Works

**The rest of your application code remains unchanged:**

```javascript
// This code works with BOTH Google Maps and Migration SDK
let map;

async function initMap() {
  const { Map } = await google.maps.importLibrary("maps");

  map = new Map(document.getElementById("map"), {
    center: { lat: 30.268193, lng: -97.7457518 },
    zoom: 8,
  });

  // Add marker
  const { Marker } = await google.maps.importLibrary("marker");
  new Marker({
    position: { lat: 30.268193, lng: -97.7457518 },
    map: map,
  });
}

initMap();
```

### Migration SDK Supported APIs

The Migration SDK supports most commonly-used Google Maps APIs:

**Core Library:**

- ✅ Map, Marker, AdvancedMarkerElement
- ✅ InfoWindow, Circle, Polyline
- ✅ LatLng, LatLngBounds, Point, Size
- ✅ Event handling (event.addListener, etc.)

**Places Library:**

- ✅ PlacesService (textSearch, nearbySearch, getDetails, findPlaceFromQuery, findPlaceFromPhoneNumber)
- ✅ Autocomplete widget
- ✅ AutocompleteService (getPlacePredictions, getQueryPredictions)
- ✅ SearchBox widget

**Routes Library:**

- ✅ DirectionsService (route method)
- ✅ DirectionsRenderer
- ✅ DistanceMatrixService
- ⚠️ Travel modes: DRIVING and WALKING only (no TRANSIT, BICYCLING)

**Geocoding Library:**

- ✅ Geocoder (geocode method for address → coordinates)
- ✅ Reverse geocoding (coordinates → address)

**Geometry Library:**

- ✅ encoding (encodePath, decodePath)
- ✅ poly (containsLocation, isLocationOnEdge)
- ✅ spherical (computeHeading, computeDistanceBetween, etc.)

**Map Features:**

- ✅ TrafficLayer
- ✅ TransitLayer

For the complete list with detailed limitations, see [Migration SDK Supported APIs](https://github.com/aws-geospatial/amazon-location-migration/blob/main/documentation/supportedLibraries.md).

### Migration SDK Limitations

**Not supported by Migration SDK:**

- **Transit routing** - No TRANSIT or BICYCLING travel modes
- **Street View** - Not available in Amazon Location
- **3D Maps** - No Maps3D support
- **Elevation API** - Not available in Amazon Location
- **Advanced geometry features** - Some specialized APIs
- **KML/GeoRSS layers** - Not supported
- **Data layer styling** - No data-driven styling

**If you need these features:** Use Phase 2 (Native APIs) or check if Amazon Location provides alternative approaches.

### When to Move to Phase 2

Consider transitioning from Migration SDK to native APIs when:

- You need features not supported by the SDK
- You want to optimize performance (remove abstraction layer)
- You're refactoring your application architecture
- You need access to new Amazon Location features before SDK update

## Phase 2: Native Amazon Location APIs

Transition to native Amazon Location Service APIs for full control and feature access.

### Overview

Phase 2 involves:

1. **Replace google.maps imports** with Amazon Location clients
2. **Update API calls** to use Amazon Location Service APIs
3. **Replace helper libraries** for client-side operations
4. **Update authentication** to use API Keys or Cognito

### Authentication Setup

**API Key (Recommended for Maps, Places, Routes):**

```javascript
// Import bundled client
<script src="https://cdn.jsdelivr.net/npm/@aws/amazon-location-client@1"></script>

<script>
  const API_KEY = "YOUR_API_KEY";
  const REGION = "us-west-2";

  const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
</script>
```

**For detailed authentication patterns, see the [Web JavaScript reference](./web-javascript.md#authentication).**

### Client Usage Pattern

Every Amazon Location API call follows this pattern:

```javascript
// 1. Create auth helper (once at app startup)
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
```

## API Mappings Reference

### Places API

| Google Maps API                             | Amazon Location API                       | Migration Notes                           |
| ------------------------------------------- | ----------------------------------------- | ----------------------------------------- |
| `PlacesService.textSearch()`                | `SearchTextCommand`                       | General text search for places            |
| `PlacesService.nearbySearch()`              | `SearchNearbyCommand`                     | Proximity-based search                    |
| `PlacesService.getDetails()`                | `GetPlaceCommand`                         | Fetch details by PlaceId                  |
| `PlacesService.findPlaceFromQuery()`        | `SearchTextCommand`                       | Use SearchText with query                 |
| `PlacesService.findPlaceFromPhoneNumber()`  | Not directly supported                    | Use SearchText with phone as query text   |
| `Autocomplete` widget                       | `AutocompleteCommand` OR `SuggestCommand` | See note below on Autocomplete vs Suggest |
| `AutocompleteService.getPlacePredictions()` | `AutocompleteCommand` OR `SuggestCommand` | Depends on use case (addresses vs places) |
| `SearchBox` widget                          | `SuggestCommand` + `SearchTextCommand`    | Place suggestions, then search            |

#### Important: Autocomplete vs Suggest

Google Maps Autocomplete handles both addresses AND place names (e.g., "123 Main St" or "Starbucks"). Amazon Location splits this functionality into two separate APIs:

- **`AutocompleteCommand`** - Address-specific predictions only (street addresses, postal codes)
  - Use for: Address input forms, shipping addresses, location entry
  - Returns: Structured address components
  - Example: "123 Main St, Austin, TX" ✅, "Starbucks" ❌

- **`SuggestCommand`** - Place and POI name predictions (businesses, landmarks, parks)
  - Use for: Finding named places, business search, POI discovery
  - Returns: Place names with categories
  - Example: "Starbucks" ✅, "Central Park" ✅, "123 Main St" ❌

**Migration decision:**

- If your Google Autocomplete is for **address-only input** (e.g., shipping forms) → Use `AutocompleteCommand`
- If your Google Autocomplete allows **place/business names** OR **both addresses and places** → Use `SuggestCommand`

**Note:** `SuggestCommand` can return both place names and addresses, making it the closest equivalent to Google's Autocomplete behavior. Only use `AutocompleteCommand` if you specifically need address-only predictions

See [Address Input reference](./address-input.md) for `AutocompleteCommand` patterns and [Places Search reference](./places-search.md) for `SuggestCommand` patterns.

**Example - Place Search:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
const service = new google.maps.places.PlacesService(map);
service.textSearch(
  {
    query: "coffee shops in Austin",
    location: new google.maps.LatLng(30.2747, -97.7431),
  },
  (results, status) => {
    if (status === google.maps.places.PlacesServiceStatus.OK) {
      results.forEach((place) => {
        console.log(place.name, place.geometry.location);
      });
    }
  },
);

// Amazon Location (Phase 2 - Native)
const placesClient = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

const command = new amazonLocationClient.places.SearchTextCommand({
  QueryText: "coffee shops in Austin",
  BiasPosition: [-97.7431, 30.2747], // Note: [lng, lat]
  MaxResults: 10,
});

const response = await placesClient.send(command);
response.ResultItems.forEach((place) => {
  console.log(place.Title, place.Position); // [lng, lat]
});
```

**For detailed Places API usage, see [Places Search reference](./places-search.md).**

### Geocoding API

| Google Maps API                  | Amazon Location API     | Migration Notes        |
| -------------------------------- | ----------------------- | ---------------------- |
| `Geocoder.geocode({ address })`  | `GeocodeCommand`        | Address to coordinates |
| `Geocoder.geocode({ location })` | `ReverseGeocodeCommand` | Coordinates to address |
| `Geocoder.geocode({ placeId })`  | `GetPlaceCommand`       | Get place by ID        |

**Example - Geocoding:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
const geocoder = new google.maps.Geocoder();
geocoder.geocode({ address: "Austin, TX" }, (results, status) => {
  if (status === "OK") {
    const location = results[0].geometry.location;
    console.log(location.lat(), location.lng());
  }
});

// Amazon Location (Phase 2 - Native)
const placesClient = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

const command = new amazonLocationClient.places.GeocodeCommand({
  QueryText: "Austin, TX",
  MaxResults: 1,
});

const response = await placesClient.send(command);
const [lng, lat] = response.ResultItems[0].Position;
console.log(lat, lng);
```

### Directions/Routing API

| Google Maps API                             | Amazon Location API           | Migration Notes                    |
| ------------------------------------------- | ----------------------------- | ---------------------------------- |
| `DirectionsService.route()`                 | `CalculateRoutesCommand`      | Get route with turn-by-turn        |
| `DistanceMatrixService.getDistanceMatrix()` | `CalculateRouteMatrixCommand` | Many-to-many distance/time         |
| N/A (no direct Google equivalent)           | `CalculateIsolinesCommand`    | Reachability areas (time/distance) |

**Example - Directions:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
const directionsService = new google.maps.DirectionsService();
directionsService.route(
  {
    origin: "Austin, TX",
    destination: "Dallas, TX",
    travelMode: google.maps.TravelMode.DRIVING,
  },
  (result, status) => {
    if (status === "OK") {
      console.log(result.routes[0].legs[0].distance);
    }
  },
);

// Amazon Location (Phase 2 - Native)
const routesClient = new amazonLocationClient.GeoRoutesClient(
  authHelper.getClientConfig(),
);

const command = new amazonLocationClient.routes.CalculateRoutesCommand({
  Origin: [-97.7431, 30.2747], // Austin [lng, lat]
  Destination: [-96.797, 32.7767], // Dallas [lng, lat]
  TravelMode: "Car",
  LegGeometryFormat: "Simple", // Returns coordinate arrays for easy rendering
  LegAdditionalFeatures: ["Summary"], // Required for distance/duration
});

const response = await routesClient.send(command);
const distance =
  response.Routes[0].Legs[0].VehicleLegDetails.Summary.Overview.Distance;
console.log(distance); // meters
```

**Route Geometry Formats:**

Amazon Location returns route geometry in two formats via the `LegGeometryFormat` parameter:

- **`Simple`** (recommended for migration) - Returns coordinate arrays `[[lng, lat], ...]` ready for MapLibre rendering, no decoder needed
- **`FlexiblePolyline`** - Returns encoded string, 5-10x smaller but requires decoding with `@aws/polyline`

For straightforward migration from Google Maps, use `LegGeometryFormat: "Simple"` (the default). For bandwidth optimization in mobile apps or high-volume scenarios, see [Choosing Route Geometry Formats](./calculate-routes.md#choosing-between-simple-and-flexiblepolyline-geometry-formats) in the Calculate Routes reference.

**For detailed routing usage, see [Calculate Routes reference](./calculate-routes.md).**

### Map Display

| Google Maps API          | Amazon Location API                         | Migration Notes                                  |
| ------------------------ | ------------------------------------------- | ------------------------------------------------ |
| `google.maps.Map`        | MapLibre GL JS + Amazon Location map styles | Use MapLibre with Amazon Location tile endpoints |
| `google.maps.Marker`     | `maplibregl.Marker`                         | MapLibre marker API                              |
| `google.maps.InfoWindow` | `maplibregl.Popup`                          | MapLibre popup API                               |
| `google.maps.Polyline`   | MapLibre line layer                         | GeoJSON-based rendering                          |
| `google.maps.Circle`     | MapLibre circle layer                       | GeoJSON circle with Turf.js                      |

**For detailed map integration, see [Dynamic Map reference](./dynamic-map.md).**

## Helper and Math Libraries

Google Maps provides client-side geometry and math utilities. For Amazon Location, use these open-source alternatives:

### Polyline Encoding/Decoding

| Google Maps API                                     | Amazon Location Alternative          | Package         |
| --------------------------------------------------- | ------------------------------------ | --------------- |
| `google.maps.geometry.encoding.encodePath(path)`    | `encodeFromLngLatArray(lngLatArray)` | `@aws/polyline` |
| `google.maps.geometry.encoding.decodePath(encoded)` | `decodeToLngLatArray(encoded)`       | `@aws/polyline` |

**Example - Polyline Encoding:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
import { encoding } from "google.maps.geometry";

const path = [
  new google.maps.LatLng(30.2747, -97.7431),
  new google.maps.LatLng(32.7767, -96.797),
];
const encoded = encoding.encodePath(path);

// Amazon Location (Phase 2 - with Migration SDK utilities)
import { MigrationEncoding } from "@aws/amazon-location-migration-sdk";

const encoded = MigrationEncoding.encodePath(path);

// Amazon Location (Phase 2 - Native with @aws/polyline)
import { encodeFromLngLatArray } from "@aws/polyline";

const lngLatArray = [
  [-97.7431, 30.2747],
  [-96.797, 32.7767],
];
const encoded = encodeFromLngLatArray(lngLatArray);
```

**Package installation:**

```bash
npm install @aws/polyline
```

### Polygon and Geometry Operations

| Google Maps API                                                         | Amazon Location Alternative                                | Package      |
| ----------------------------------------------------------------------- | ---------------------------------------------------------- | ------------ |
| `google.maps.geometry.poly.containsLocation(point, polygon)`            | `turf.booleanPointInPolygon(point, polygon)`               | `@turf/turf` |
| `google.maps.geometry.poly.isLocationOnEdge(point, poly, tolerance)`    | `turf.pointToLineDistance()` + `turf.booleanPointOnLine()` | `@turf/turf` |
| `google.maps.geometry.spherical.computeDistanceBetween(from, to)`       | `turf.distance(from, to)`                                  | `@turf/turf` |
| `google.maps.geometry.spherical.computeHeading(from, to)`               | `turf.bearing(from, to)`                                   | `@turf/turf` |
| `google.maps.geometry.spherical.computeOffset(from, distance, heading)` | `turf.destination(from, distance, bearing)`                | `@turf/turf` |
| `google.maps.geometry.spherical.computeArea(path)`                      | `turf.area(polygon)`                                       | `@turf/turf` |
| `google.maps.geometry.spherical.interpolate(from, to, fraction)`        | `turf.along(line, distance)`                               | `@turf/turf` |

**Example - Point in Polygon:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
import { poly } from "google.maps.geometry";

const point = new google.maps.LatLng(30.2747, -97.7431);
const polygonPath = [
  new google.maps.LatLng(30.0, -98.0),
  new google.maps.LatLng(31.0, -98.0),
  new google.maps.LatLng(31.0, -97.0),
  new google.maps.LatLng(30.0, -97.0),
];
const polygon = new google.maps.Polygon({ paths: polygonPath });
const contains = poly.containsLocation(point, polygon);

// Amazon Location (Phase 2 - with Migration SDK utilities)
import { MigrationPoly } from "@aws/amazon-location-migration-sdk";

const contains = MigrationPoly.containsLocation(point, polygon);

// Amazon Location (Phase 2 - Native with Turf.js)
import * as turf from "@turf/turf";

const turfPoint = turf.point([-97.7431, 30.2747]); // [lng, lat]
const turfPolygon = turf.polygon([
  [
    [-98.0, 30.0],
    [-98.0, 31.0],
    [-97.0, 31.0],
    [-97.0, 30.0],
    [-98.0, 30.0], // Close the polygon
  ],
]);
const contains = turf.booleanPointInPolygon(turfPoint, turfPolygon);
```

**Example - Distance Between Points:**

```javascript
// Google Maps (Phase 1 - Migration SDK)
import { spherical } from "google.maps.geometry";

const from = new google.maps.LatLng(30.2747, -97.7431);
const to = new google.maps.LatLng(32.7767, -96.797);
const distanceMeters = spherical.computeDistanceBetween(from, to);

// Amazon Location (Phase 2 - Native with Turf.js)
import * as turf from "@turf/turf";

const fromPoint = turf.point([-97.7431, 30.2747]);
const toPoint = turf.point([-96.797, 32.7767]);
const distanceKm = turf.distance(fromPoint, toPoint, { units: "kilometers" });
const distanceMeters = distanceKm * 1000;
```

**Package installation:**

```bash
npm install @turf/turf
```

**Note:** The Migration SDK includes `MigrationEncoding` and `MigrationPoly` classes that wrap `@aws/polyline` and `@turf/turf`, making Phase 1 → Phase 2 transition smoother. When moving to pure native APIs, use the underlying packages directly.

### Coordinate System Differences

**Important:** Google Maps uses `[lat, lng]` order, while Amazon Location and GeoJSON use `[lng, lat]` order.

```javascript
// Google Maps (Phase 1)
const location = new google.maps.LatLng(30.2747, -97.7431); // lat, lng
console.log(location.lat(), location.lng()); // 30.2747, -97.7431

// Amazon Location (Phase 2)
const position = [-97.7431, 30.2747]; // lng, lat (GeoJSON standard)
console.log(position[1], position[0]); // 30.2747, -97.7431 (lat, lng)
```

**Always verify coordinate order when migrating:**

- Google Maps: `{ lat: 30.2747, lng: -97.7431 }`
- Amazon Location: `[-97.7431, 30.2747]` (array) or `{ longitude: -97.7431, latitude: 30.2747 }` (object)

## Migration Guides

### Official AWS Migration Guides

- **[Web Application Migration Guide](https://location.aws.com/migrate-a-web-app)** - Step-by-step guide for web apps
- **[Android Application Migration Guide](https://location.aws.com/migrate-an-android-app)** - For Android/Kotlin apps
- **[iOS Application Migration Guide](https://location.aws.com/migrate-an-ios-app)** - For iOS/Swift apps

### Migration SDK Documentation

- **[Migration SDK GitHub](https://github.com/aws-geospatial/amazon-location-migration)** - Source code and examples
- **[Supported Libraries](https://github.com/aws-geospatial/amazon-location-migration/blob/main/documentation/supportedLibraries.md)** - Complete API support matrix
- **[NPM Package](https://www.npmjs.com/package/@aws/amazon-location-migration-sdk)** - Package documentation

### Related Amazon Location References

For detailed usage of native Amazon Location APIs:

- **[Web JavaScript](./web-javascript.md)** - Authentication, client setup, error handling
- **[Places Search](./places-search.md)** - SearchText, SearchNearby, Suggest, GetPlace
- **[Address Input](./address-input.md)** - Autocomplete for address forms
- **[Calculate Routes](./calculate-routes.md)** - Directions, route matrix, isolines
- **[Dynamic Map](./dynamic-map.md)** - Map display with MapLibre GL JS

## Common Migration Patterns

### Migrating a Simple Map

**Google Maps:**

```javascript
const map = new google.maps.Map(document.getElementById("map"), {
  center: { lat: 30.2747, lng: -97.7431 },
  zoom: 10,
});

const marker = new google.maps.Marker({
  position: { lat: 30.2747, lng: -97.7431 },
  map: map,
  title: "Austin",
});
```

**Phase 1 (Migration SDK):** No code changes needed - just update the script import.

**Phase 2 (Native with MapLibre):**

```javascript
// Add MapLibre GL JS
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";

// Get Amazon Location map style
const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
const mapStyleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}`;

const map = new maplibregl.Map({
  container: "map",
  style: mapStyleUrl,
  center: [-97.7431, 30.2747], // [lng, lat]
  zoom: 10,
});

const marker = new maplibregl.Marker()
  .setLngLat([-97.7431, 30.2747])
  .setPopup(new maplibregl.Popup().setText("Austin"))
  .addTo(map);
```

### Migrating Autocomplete

**Google Maps:**

```javascript
const autocomplete = new google.maps.places.Autocomplete(inputElement);

autocomplete.addListener("place_changed", () => {
  const place = autocomplete.getPlace();
  console.log(place.geometry.location);
});
```

**Phase 1 (Migration SDK):** No code changes needed.

**Phase 2 (Native):**

```javascript
const placesClient = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

let debounceTimer;
inputElement.addEventListener("input", async (e) => {
  clearTimeout(debounceTimer);

  debounceTimer = setTimeout(async () => {
    const command = new amazonLocationClient.places.AutocompleteCommand({
      QueryText: e.target.value,
      MaxResults: 5,
    });

    const response = await placesClient.send(command);
    displaySuggestions(response.ResultItems);
  }, 300);
});

// When user selects a suggestion
async function onSuggestionSelected(placeId) {
  const command = new amazonLocationClient.places.GetPlaceCommand({
    PlaceId: placeId,
  });

  const response = await placesClient.send(command);
  console.log(response.Position); // [lng, lat]
}
```

**See [Address Input reference](./address-input.md) for complete autocomplete patterns.**

### Migrating Place Search

**Google Maps:**

```javascript
const service = new google.maps.places.PlacesService(map);

service.nearbySearch(
  {
    location: { lat: 30.2747, lng: -97.7431 },
    radius: 5000,
    type: "restaurant",
  },
  (results, status) => {
    if (status === google.maps.places.PlacesServiceStatus.OK) {
      results.forEach((place) => {
        addMarker(place);
      });
    }
  },
);
```

**Phase 1 (Migration SDK):** No code changes needed.

**Phase 2 (Native):**

```javascript
const placesClient = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

const command = new amazonLocationClient.places.SearchNearbyCommand({
  QueryPosition: [-97.7431, 30.2747], // [lng, lat]
  MaxDistance: 5000, // meters
  Filter: {
    IncludeCategories: ["restaurant"], // Use valid Category IDs
  },
  MaxResults: 20,
});

const response = await placesClient.send(command);
response.ResultItems.forEach((place) => {
  addMarker(place);
});
```

**Category/Type Differences:**

Google Maps and Amazon Location use different category systems:

- **Google Maps**: Generic type strings (e.g., `"restaurant"`, `"cafe"`, `"bank"`)
- **Amazon Location**: Specific Category IDs (e.g., `"restaurant"`, `"coffee_shop"`, `"bank"`, `"fueling_station"`, `"hotel"`, `"grocery"`)

When migrating, verify category names match Amazon Location's supported Category IDs. See [Place Categories Documentation](https://docs.aws.amazon.com/location/latest/developerguide/places-filtering.html#place-categories) for the complete list.

## Best Practices

### Phase 1 Best Practices

- **Start with Migration SDK** - Fastest path to migration for most apps
- **Test thoroughly** - SDK behavior may differ slightly from Google Maps
- **Check API support** - Verify your Google APIs are supported before committing
- **Plan Phase 2** - Consider SDK as temporary bridge, not permanent solution

### Phase 2 Best Practices

- **Coordinate order** - Always verify [lng, lat] vs [lat, lng] when migrating
- **Authentication** - Use API Keys for Maps/Places/Routes, Cognito for Geofencing/Tracking
- **Error handling** - Implement proper try-catch and retry logic
- **Client reuse** - Create clients once at app startup, reuse for all requests
- **Caching** - Cache geocoding and search results (with appropriate TTLs)
- **Helper libraries** - Use `@aws/polyline` for encoding, `@turf/turf` for geometry

### Testing Your Migration

**Create a comparison page during migration:**

```javascript
// Load both Google Maps and Migration SDK side-by-side
// Test identical operations and compare results
// Useful for validating behavior before full cutover
```

**Incremental migration:**

- Start with Phase 1 (SDK) for quick win
- Identify high-value areas for Phase 2 optimization
- Migrate module by module, not all at once
- Keep both implementations temporarily for A/B testing

## Troubleshooting

### Common Issues

**Issue:** Coordinates are backwards

- **Cause:** Google uses [lat, lng], Amazon Location uses [lng, lat]
- **Fix:** Swap coordinate order when migrating from Phase 1 to Phase 2

**Issue:** Autocomplete not working

- **Cause:** Different API between Phase 1 and Phase 2
- **Fix:** See [Address Input reference](./address-input.md) for native implementation

**Issue:** Map not displaying

- **Cause:** Missing MapLibre setup or incorrect map style URL
- **Fix:** See [Dynamic Map reference](./dynamic-map.md) for complete setup

**Issue:** Places search returns no results

- **Cause:** Query format or filter differences
- **Fix:** Review [Places Search reference](./places-search.md) for correct parameters

**Issue:** Routes not calculating

- **Cause:** Coordinate order or travel mode not supported
- **Fix:** Verify [lng, lat] order and use supported travel modes (Car, Walking, Truck)

### Getting Help

- **Migration SDK Issues:** [GitHub Issues](https://github.com/aws-geospatial/amazon-location-migration/issues)
- **Amazon Location Service:** [AWS Documentation](https://docs.aws.amazon.com/location/)
- **API Reference:** [Amazon Location API Reference](https://docs.aws.amazon.com/location/latest/APIReference/)
