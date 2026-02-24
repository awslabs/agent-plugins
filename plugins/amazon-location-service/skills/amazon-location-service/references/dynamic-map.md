# Dynamic Map Rendering

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Render interactive maps using MapLibre GL JS with Amazon Location Service.

## Table of Contents

- [Basic Setup](#basic-setup)
- [Complete Examples](#complete-examples)
- [Map Styles](#map-styles)
- [Advanced Features](#advanced-features)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Basic Setup

### HTML Structure

```html
<!DOCTYPE html>
<html>
  <head>
    <link
      href="https://unpkg.com/maplibre-gl@5/dist/maplibre-gl.css"
      rel="stylesheet"
    />
    <script src="https://cdn.jsdelivr.net/npm/maplibre-gl@5"></script>
    <style>
      #map {
        height: 500px;
        width: 100%;
      }
    </style>
  </head>
  <body>
    <div id="map"></div>
    <script src="app.js"></script>
  </body>
</html>
```

### Minimal Map Initialization

```javascript
const API_KEY = "your-api-key";
const REGION = "us-west-2";

// Direct URL method - REQUIRED
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}`;

const map = new maplibregl.Map({
  container: "map",
  style: styleUrl,
  center: [-97.7723, 30.2672], // [longitude, latitude] - Zilker Park, Austin
  zoom: 10,
  validateStyle: false, // MUST set to false for faster loading
});
```

### validateStyle Parameter

**Always set `validateStyle: false`**

- **With false**: Map loads faster, skips unnecessary validation of Amazon's trusted styles
- **With true** (default): MapLibre validates every style property, adding ~500ms+ load time
- **Trade-off**: Validation helps catch errors in custom styles, but Amazon styles are pre-validated

## Complete Examples

### Map with Markers and Popups

```javascript
const API_KEY = "your-api-key";
const REGION = "us-west-2";

const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}`;

const map = new maplibregl.Map({
  container: "map",
  style: styleUrl,
  center: [-97.7723, 30.2672], // Zilker Park, Austin TX
  zoom: 12,
  validateStyle: false,
});

// Wait for map to load before adding markers
map.on("load", () => {
  console.log("Map loaded successfully");

  // Add marker with popup
  const marker = new maplibregl.Marker({ color: "#FF0000" })
    .setLngLat([-97.7723, 30.2672])
    .setPopup(
      new maplibregl.Popup({ offset: 25 }).setHTML(
        "<h3>Zilker Park</h3><p>Austin, Texas</p>",
      ),
    )
    .addTo(map);

  // Add multiple markers from data
  const locations = [
    { name: "Barton Springs Pool", coords: [-97.7708, 30.2639] },
    { name: "Zilker Botanical Garden", coords: [-97.7716, 30.2707] },
  ];

  locations.forEach((loc) => {
    new maplibregl.Marker()
      .setLngLat(loc.coords)
      .setPopup(new maplibregl.Popup().setHTML(`<h4>${loc.name}</h4>`))
      .addTo(map);
  });
});

// Handle errors
map.on("error", (e) => {
  console.error("Map error:", e);
  // Show user-friendly error message
});
```

## Map Styles

### Available Styles

Amazon Location provides four map styles:

- **Standard** (default) - General purpose map
- **Monochrome** - Simplified single-color palette
- **Hybrid** - Satellite imagery with labels
- **Satellite** - Satellite imagery only

```javascript
// Standard style (default)
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}`;

// Other styles
const monochromeUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Monochrome/descriptor?key=${API_KEY}`;
const hybridUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Hybrid/descriptor?key=${API_KEY}`;
const satelliteUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Satellite/descriptor?key=${API_KEY}`;
```

### Common Customizations

**Dark mode:**

```javascript
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}&color-scheme=Dark`;
```

**3D buildings:**

```javascript
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}&buildings=Buildings3D`;
```

**Traffic overlay:**

```javascript
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}&traffic=All`;
```

**Combined customizations:**

```javascript
const styleUrl = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/Standard/descriptor?key=${API_KEY}&color-scheme=Dark&buildings=Buildings3D&traffic=All`;
```

For all customization options (terrain, political views, travel modes, etc.), see the [GetStyleDescriptor API Reference](https://docs.aws.amazon.com/location/latest/APIReference/API_geomaps_GetStyleDescriptor.html).

### Feature Compatibility by Map Style

Not all features are available on every map style. Applying an unsupported feature parameter to an incompatible style will have no effect.

| Feature                      | Standard | Monochrome | Hybrid | Satellite |
| ---------------------------- | -------- | ---------- | ------ | --------- |
| Color Scheme (Light/Dark)    | Yes      | Yes        | No     | No        |
| Terrain (Hillshade)          | Yes      | Yes        | No     | No        |
| Terrain (Terrain3D)          | Yes      | Yes        | Yes    | Yes       |
| Contour Density              | Yes      | Yes        | Yes    | No        |
| Traffic                      | Yes      | No         | No     | No        |
| Buildings (3D)               | Yes      | Yes        | No     | No        |
| Travel Modes (Transit/Truck) | Yes      | No         | No     | No        |
| Language                     | Yes      | Yes        | Yes    | No        |
| Political View               | Yes      | Yes        | Yes    | No        |

> **Note**: Traffic and Travel Modes are only supported on the Standard map style. If you need real-time traffic visualization or transit/truck overlays, you must use Standard. See [Map concepts](https://docs.aws.amazon.com/location/latest/developerguide/maps-concepts.html) for the full compatibility matrix.

### Style Change Persistence

Calling `map.setStyle()` completely replaces the map's style object. This destroys all custom sources and layers added via `map.addSource()` / `map.addLayer()` — route lines, geofence polygons, heatmaps, cluster layers, etc. DOM-based elements like `maplibregl.Marker` survive because they exist outside the style.

Any code that switches map styles MUST re-add custom layers after the new style loads. The recommended pattern is:

1. Store the data needed to recreate custom layers (coordinates, paint options, etc.)
2. Listen for `style.load` after calling `setStyle()` and re-add the layers
3. Clear stored data only when layers are intentionally removed

```javascript
// Track data for any custom layers that need to survive style changes
let customLayerData = null;

function addCustomLayer(sourceId, layerId, geojsonData, paintOptions) {
  customLayerData = { sourceId, layerId, geojsonData, paintOptions };

  map.addSource(sourceId, { type: "geojson", data: geojsonData });
  map.addLayer({
    id: layerId,
    type: "line",
    source: sourceId,
    paint: paintOptions,
  });
}

function removeCustomLayer() {
  if (map.getLayer(customLayerData?.layerId))
    map.removeLayer(customLayerData.layerId);
  if (map.getSource(customLayerData?.sourceId))
    map.removeSource(customLayerData.sourceId);
  customLayerData = null;
}

function setMapStyle(styleName) {
  const url = `https://maps.geo.${REGION}.amazonaws.com/v2/styles/${styleName}/descriptor?key=${API_KEY}`;
  map.setStyle(url);

  map.once("style.load", () => {
    if (customLayerData) {
      addCustomLayer(
        customLayerData.sourceId,
        customLayerData.layerId,
        customLayerData.geojsonData,
        customLayerData.paintOptions,
      );
    }
  });
}
```

## Advanced Features

### Navigation Controls

```javascript
map.on("load", () => {
  // Add zoom and rotation controls
  map.addControl(new maplibregl.NavigationControl(), "top-right");

  // Add geolocation control
  map.addControl(
    new maplibregl.GeolocateControl({
      positionOptions: { enableHighAccuracy: true },
      trackUserLocation: true,
    }),
    "top-right",
  );

  // Add scale control
  map.addControl(new maplibregl.ScaleControl(), "bottom-left");
});
```

### Custom Markers with HTML

```javascript
// Create custom marker element
const el = document.createElement("div");
el.className = "custom-marker";
el.style.width = "30px";
el.style.height = "30px";
el.style.backgroundImage = "url(marker-icon.png)";

new maplibregl.Marker({ element: el })
  .setLngLat([-122.4194, 37.7749])
  .addTo(map);
```

### Map Event Handling

```javascript
// Click event
map.on("click", (e) => {
  console.log("Clicked at:", e.lngLat);
  new maplibregl.Marker().setLngLat(e.lngLat).addTo(map);
});

// Move event
map.on("move", () => {
  console.log("Center:", map.getCenter());
  console.log("Zoom:", map.getZoom());
});
```

## Error Handling

### Common Errors

```javascript
map.on("error", (e) => {
  console.error("Map error:", e.error);

  if (e.error.status === 401) {
    // Invalid API key
    showError("Authentication failed. Check your API key.");
  } else if (e.error.status === 403) {
    // API key lacks permissions
    showError("API key does not have permission to access maps.");
  } else if (e.error.message.includes("Failed to fetch")) {
    // Network error
    showError("Network error. Please check your connection.");
  } else {
    showError("Failed to load map. Please try again.");
  }
});

function showError(message) {
  document.getElementById("map").innerHTML =
    `<div style="padding: 20px; color: red;">${message}</div>`;
}
```

## Best Practices

### Performance

- **Set validateStyle: false**: Saves 500ms+ on initial load
- **Lazy load MapLibre**: Only load map library when user navigates to map view
- **Limit markers**: Use clustering for 100+ markers (maplibre-gl-cluster)

### Security

- **Restrict API key**: Use API key permissions to limit to specific operations
- **Domain restrictions**: Configure API key to only work from your domains
- **Never expose in public repos**: Use environment variables for API keys

### User Experience

- **Show loading state**: Display spinner while map initializes
- **Handle errors gracefully**: Show user-friendly error messages, not console errors
- **Responsive sizing**: Ensure map container has explicit height
- **Touch support**: MapLibre automatically handles touch events on mobile

### Debugging

- **Check browser console**: Map errors appear in console
- **Verify API key**: Test with simple example first
- **Check network tab**: Verify style descriptor and tile requests succeed
- **Test validateStyle: true**: During development only, to catch custom style issues
