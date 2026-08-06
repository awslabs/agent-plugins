# Google Maps Migration (Android)

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Migrate Android applications from Google Maps SDK for Android to Amazon Location Service using the AWS SDK for Kotlin and MapLibre Native.

## Table of Contents

- [Migration Overview](#migration-overview)
- [Setup and Dependencies](#setup-and-dependencies)
- [Authentication](#authentication)
- [API Mappings Reference](#api-mappings-reference)
- [Helper and Math Libraries](#helper-and-math-libraries)
- [Migration Patterns](#migration-patterns)
- [Migration Guide](#migration-guide)

## Migration Overview

**Key differences from Google Maps:**

| Aspect             | Google Maps SDK               | Amazon Location Service               |
| ------------------ | ----------------------------- | ------------------------------------- |
| **Drop-in SDK**    | ❌ Not available              | Direct AWS SDK migration required     |
| **Map rendering**  | Google Maps renderer          | MapLibre Native Android               |
| **API style**      | Callback/listener-based       | Kotlin coroutines / suspend functions |
| **Coordinates**    | `LatLng(lat, lng)`            | `listOf(lng, lat)` - GeoJSON order    |
| **Authentication** | API Key in manifest           | AWS API Key or Cognito credentials    |
| **SDK packages**   | `com.google.android.gms.maps` | `aws.sdk.kotlin.services.*`           |

**Migration timeline:** Expect 1-2 weeks for a typical app with maps, places, and routing features.

**No migration SDK available** - Unlike JavaScript, there is no drop-in replacement for Android. You'll need to refactor your Google Maps code to use Amazon Location APIs directly.

## Setup and Dependencies

### Remove Google Maps Dependencies

**In your app-level `build.gradle.kts`:**

```kotlin
// Remove Google Maps dependencies
dependencies {
    // ❌ Remove these
    // implementation("com.google.android.gms:play-services-maps:18.2.0")
    // implementation("com.google.android.gms:play-services-location:21.0.1")
    // implementation("com.google.android.libraries.places:places:3.3.0")
}
```

### Add Amazon Location Dependencies

**Add AWS SDK for Kotlin and MapLibre:**

```kotlin
dependencies {
    // MapLibre for map display
    implementation("org.maplibre.gl:android-sdk:11.0.0")

    // AWS SDK for Kotlin - add only what you need
    implementation("aws.sdk.kotlin:geoplaces:1.3.+")  // Places, Geocoding
    implementation("aws.sdk.kotlin:georoutes:1.3.+")  // Routing
    implementation("aws.sdk.kotlin:geomaps:1.3.+")    // Static maps
    implementation("aws.sdk.kotlin:location:1.3.+")   // Geofencing, Tracking

    // For authentication
    implementation("aws.sdk.kotlin:cognitoidentity:1.3.+")

    // Coroutines (required for AWS SDK)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

**In your project-level `build.gradle.kts`, add the MapLibre repository:**

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        // Add MapLibre repository
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = project.findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?
                    ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN")
            }
        }
    }
}
```

**Note:** MapLibre is the open-source fork of Mapbox GL Native and is the recommended way to display maps with Amazon Location Service on Android.

### Update AndroidManifest.xml

**Remove Google Maps API key:**

```xml
<!-- Remove this -->
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_API_KEY"/>
```

**Add permissions (if not already present):**

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

## Authentication

Amazon Location Service supports API Key and Cognito authentication.

### API Key Authentication (Recommended for Maps, Places, Routes)

**Create a credential provider:**

```kotlin
import aws.sdk.kotlin.runtime.auth.credentials.StaticCredentialsProvider
import aws.sdk.kotlin.services.geoplaces.GeoPlacesClient
import aws.smithy.kotlin.runtime.auth.awscredentials.Credentials

class AmazonLocationAuth {
    companion object {
        private const val API_KEY = "YOUR_AMAZON_LOCATION_API_KEY"
        private const val REGION = "us-west-2"

        // Create credentials provider for API Key
        fun getApiKeyCredentials(): StaticCredentialsProvider {
            return StaticCredentialsProvider(
                Credentials.invoke(
                    accessKeyId = API_KEY,
                    secretAccessKey = ""
                )
            )
        }

        // Create a Places client
        suspend fun createPlacesClient(): GeoPlacesClient {
            return GeoPlacesClient {
                region = REGION
                credentialsProvider = getApiKeyCredentials()
            }
        }
    }
}
```

**Usage:**

```kotlin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MyActivity : AppCompatActivity() {
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        scope.launch {
            val placesClient = AmazonLocationAuth.createPlacesClient()
            // Use client for API calls
        }
    }
}
```

### Cognito Authentication (Required for Geofencing, Tracking)

```kotlin
import aws.sdk.kotlin.services.cognitoidentity.CognitoIdentityClient
import aws.sdk.kotlin.services.cognitoidentity.model.GetCredentialsForIdentityRequest
import aws.sdk.kotlin.services.cognitoidentity.model.GetIdRequest

suspend fun getCognitoCredentials(identityPoolId: String): Credentials {
    val cognitoClient = CognitoIdentityClient {
        region = "us-west-2"
    }

    // Get identity ID
    val getIdResponse = cognitoClient.getId(GetIdRequest {
        this.identityPoolId = identityPoolId
    })

    // Get temporary credentials
    val credentialsResponse = cognitoClient.getCredentialsForIdentity(
        GetCredentialsForIdentityRequest {
            identityId = getIdResponse.identityId
        }
    )

    return Credentials.invoke(
        accessKeyId = credentialsResponse.credentials?.accessKeyId ?: "",
        secretAccessKey = credentialsResponse.credentials?.secretKey ?: "",
        sessionToken = credentialsResponse.credentials?.sessionToken
    )
}
```

## API Mappings Reference

### Places API

| Google Maps Android                          | Amazon Location Android | Migration Notes                       |
| -------------------------------------------- | ----------------------- | ------------------------------------- |
| `PlacesClient.findCurrentPlace()`            | `SearchNearbyCommand`   | Use device location with SearchNearby |
| `PlacesClient.fetchPlace()`                  | `GetPlaceCommand`       | Fetch place details by PlaceId        |
| `PlacesClient.findAutocompletePredictions()` | `AutocompleteCommand`   | Address autocomplete                  |
| N/A (use Autocomplete widget)                | `SuggestCommand`        | Place name suggestions                |

**Example - Place Search:**

```kotlin
// Google Maps (Before)
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FindCurrentPlaceRequest
import com.google.android.libraries.places.api.net.PlacesClient

val placesClient = Places.createClient(context)
val placeFields = listOf(Place.Field.NAME, Place.Field.LAT_LNG)
val request = FindCurrentPlaceRequest.newInstance(placeFields)

placesClient.findCurrentPlace(request).addOnSuccessListener { response ->
    for (placeLikelihood in response.placeLikelihoods) {
        val place = placeLikelihood.place
        Log.i(TAG, "Place: ${place.name}, ${place.latLng}")
    }
}

// Amazon Location (After)
import aws.sdk.kotlin.services.geoplaces.GeoPlacesClient
import aws.sdk.kotlin.services.geoplaces.model.SearchNearbyRequest

val placesClient = GeoPlacesClient {
    region = "us-west-2"
    credentialsProvider = AmazonLocationAuth.getApiKeyCredentials()
}

// Assume you have the device location
val deviceLocation = listOf(-97.7431, 30.2747) // [lng, lat]

val response = placesClient.searchNearby(SearchNearbyRequest {
    queryPosition = deviceLocation
    maxResults = 20
})

response.resultItems?.forEach { place ->
    Log.i(TAG, "Place: ${place.title}, ${place.position}")
}
```

### Geocoding API

| Google Maps Android              | Amazon Location Android | Migration Notes                           |
| -------------------------------- | ----------------------- | ----------------------------------------- |
| `Geocoder.getFromLocationName()` | `GeocodeCommand`        | Forward geocoding (address → coordinates) |
| `Geocoder.getFromLocation()`     | `ReverseGeocodeCommand` | Reverse geocoding (coordinates → address) |

**Example - Geocoding:**

```kotlin
// Google Maps (Before)
import android.location.Geocoder
import android.location.Address

val geocoder = Geocoder(context)
val addresses = geocoder.getFromLocationName("Austin, TX", 1)
if (addresses.isNotEmpty()) {
    val location = addresses[0]
    Log.i(TAG, "Lat: ${location.latitude}, Lng: ${location.longitude}")
}

// Amazon Location (After)
import aws.sdk.kotlin.services.geoplaces.model.GeocodeRequest

val response = placesClient.geocode(GeocodeRequest {
    queryText = "Austin, TX"
    maxResults = 1
})

response.resultItems?.firstOrNull()?.let { result ->
    val (lng, lat) = result.position ?: return@let
    Log.i(TAG, "Lat: $lat, Lng: $lng")
}
```

### Directions/Routing API

| Google Maps Android              | Amazon Location Android       | Migration Notes        |
| -------------------------------- | ----------------------------- | ---------------------- |
| `DirectionsApi.newRequest()`     | `CalculateRoutesCommand`      | Route calculation      |
| `DistanceMatrixApi.newRequest()` | `CalculateRouteMatrixCommand` | Many-to-many distances |

**Example - Directions:**

```kotlin
// Google Maps (Before)
import com.google.maps.DirectionsApi
import com.google.maps.GeoApiContext
import com.google.maps.model.TravelMode

val context = GeoApiContext.Builder()
    .apiKey("YOUR_API_KEY")
    .build()

val directions = DirectionsApi.newRequest(context)
    .origin("Austin, TX")
    .destination("Dallas, TX")
    .mode(TravelMode.DRIVING)
    .await()

Log.i(TAG, "Distance: ${directions.routes[0].legs[0].distance}")

// Amazon Location (After)
import aws.sdk.kotlin.services.georoutes.GeoRoutesClient
import aws.sdk.kotlin.services.georoutes.model.CalculateRoutesRequest

val routesClient = GeoRoutesClient {
    region = "us-west-2"
    credentialsProvider = AmazonLocationAuth.getApiKeyCredentials()
}

val response = routesClient.calculateRoutes(CalculateRoutesRequest {
    origin = listOf(-97.7431, 30.2747) // Austin [lng, lat]
    destination = listOf(-96.7970, 32.7767) // Dallas [lng, lat]
    travelMode = aws.sdk.kotlin.services.georoutes.model.RouteTravelMode.Car
    legAdditionalFeatures = listOf(aws.sdk.kotlin.services.georoutes.model.RouteLegAdditionalFeature.Summary)
})

response.routes?.firstOrNull()?.let { route ->
    val leg = route.legs?.firstOrNull()
    val distance = leg?.vehicleLegDetails?.summary?.overview?.distance
    Log.i(TAG, "Distance: $distance meters")
}
```

### Map Display

| Google Maps Android       | Amazon Location Android  | Migration Notes            |
| ------------------------- | ------------------------ | -------------------------- |
| `MapFragment` / `MapView` | `MapView` (MapLibre)     | Different rendering engine |
| `GoogleMap.addMarker()`   | `SymbolManager.create()` | MapLibre marker API        |
| `GoogleMap.addPolyline()` | Add LineLayer            | GeoJSON-based rendering    |
| `GoogleMap.moveCamera()`  | `mapboxMap.moveCamera()` | Similar camera API         |

**Example - Display Map:**

```kotlin
// Google Maps (Before)
import com.google.android.gms.maps.MapFragment
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.OnMapReadyCallback
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MarkerOptions

class MapActivity : AppCompatActivity(), OnMapReadyCallback {
    override fun onMapReady(googleMap: GoogleMap) {
        val austin = LatLng(30.2747, -97.7431)
        googleMap.addMarker(
            MarkerOptions()
                .position(austin)
                .title("Austin")
        )
        googleMap.moveCamera(CameraUpdateFactory.newLatLngZoom(austin, 10f))
    }
}

// Amazon Location (After)
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.Style
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.plugins.annotation.SymbolManager
import org.maplibre.android.plugins.annotation.SymbolOptions

class MapActivity : AppCompatActivity() {
    private lateinit var mapView: MapView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        mapView = MapView(this)
        setContentView(mapView)

        mapView.getMapAsync { map ->
            // Get Amazon Location map style
            val styleUrl = "https://maps.geo.us-west-2.amazonaws.com/v2/styles/Standard/descriptor?key=$API_KEY"

            map.setStyle(Style.Builder().fromUri(styleUrl)) { style ->
                // Add marker
                val symbolManager = SymbolManager(mapView, map, style)
                symbolManager.create(
                    SymbolOptions()
                        .withLatLng(LatLng(30.2747, -97.7431))
                        .withTextField("Austin")
                )

                // Move camera
                map.cameraPosition = CameraPosition.Builder()
                    .target(LatLng(30.2747, -97.7431))
                    .zoom(10.0)
                    .build()
            }
        }
    }
}
```

## Helper and Math Libraries

Google Maps SDK includes utility classes for geometry operations. For Amazon Location, use these alternatives:

### Polyline Encoding/Decoding

| Google Maps Android | Amazon Location Alternative                       | Package                            |
| ------------------- | ------------------------------------------------- | ---------------------------------- |
| `PolyUtil.encode()` | Use custom implementation or AWS polyline utility | N/A (implement or use server-side) |
| `PolyUtil.decode()` | Use custom implementation or AWS polyline utility | N/A (implement or use server-side) |

**Example - Polyline Decoding (Custom Implementation):**

```kotlin
// Google Maps (Before)
import com.google.maps.android.PolyUtil

val points = PolyUtil.decode(encodedPolyline)

// Amazon Location (After) - Custom implementation
object PolylineDecoder {
    fun decode(encoded: String): List<Pair<Double, Double>> {
        val poly = ArrayList<Pair<Double, Double>>()
        var index = 0
        var lat = 0
        var lng = 0

        while (index < encoded.length) {
            var result = 1
            var shift = 0
            var b: Int
            do {
                b = encoded[index++].code - 63 - 1
                result += b shl shift
                shift += 5
            } while (b >= 0x1f)
            lat += if (result and 1 != 0) (result shr 1).inv() else result shr 1

            result = 1
            shift = 0
            do {
                b = encoded[index++].code - 63 - 1
                result += b shl shift
                shift += 5
            } while (b >= 0x1f)
            lng += if (result and 1 != 0) (result shr 1).inv() else result shr 1

            poly.add(Pair(lat / 1e5, lng / 1e5))
        }
        return poly
    }
}
```

**Recommendation:** For complex polyline operations, consider using the server-side AWS SDK or implement a lightweight utility based on the polyline algorithm.

### Geometry Operations

| Google Maps Android                      | Amazon Location Alternative    | Approach                 |
| ---------------------------------------- | ------------------------------ | ------------------------ |
| `SphericalUtil.computeDistanceBetween()` | Use Haversine formula          | Implement or use library |
| `PolyUtil.containsLocation()`            | Use point-in-polygon algorithm | Implement or use library |
| `PolyUtil.isLocationOnPath()`            | Use point-to-line distance     | Implement or use library |

**Example - Distance Calculation:**

```kotlin
// Google Maps (Before)
import com.google.maps.android.SphericalUtil
import com.google.android.gms.maps.model.LatLng

val distance = SphericalUtil.computeDistanceBetween(
    LatLng(30.2747, -97.7431),
    LatLng(32.7767, -96.7970)
)

// Amazon Location (After) - Haversine implementation
object GeoUtils {
    private const val EARTH_RADIUS = 6371000.0 // meters

    fun computeDistanceBetween(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double
    ): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)

        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2)

        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return EARTH_RADIUS * c
    }
}

val distance = GeoUtils.computeDistanceBetween(
    30.2747, -97.7431,
    32.7767, -96.7970
)
```

**For complex geometry operations**, consider using:

- [Turf for Android](https://github.com/mapbox/mapbox-java) - Port of Turf.js for Android
- Implement algorithms based on standard formulas (Haversine, point-in-polygon, etc.)

### Coordinate System Differences

**Critical:** Google Maps uses `LatLng(lat, lng)` while Amazon Location uses `listOf(lng, lat)` (GeoJSON order).

```kotlin
// Google Maps
val location = LatLng(30.2747, -97.7431) // lat, lng

// Amazon Location
val position = listOf(-97.7431, 30.2747) // lng, lat

// Converting between them
fun LatLng.toAmazonLocation(): List<Double> = listOf(longitude, latitude)
fun List<Double>.toLatLng(): LatLng = LatLng(this[1], this[0])
```

## Migration Patterns

### Pattern 1: Places Autocomplete

**Google Maps:**

```kotlin
import com.google.android.libraries.places.widget.AutocompleteSupportFragment

val autocompleteFragment = supportFragmentManager.findFragmentById(R.id.autocomplete_fragment)
    as AutocompleteSupportFragment

autocompleteFragment.setOnPlaceSelectedListener(object : PlaceSelectionListener {
    override fun onPlaceSelected(place: Place) {
        Log.i(TAG, "Place: ${place.name}, ${place.latLng}")
    }

    override fun onError(status: Status) {
        Log.e(TAG, "Error: $status")
    }
})
```

**Amazon Location:**

```kotlin
import aws.sdk.kotlin.services.geoplaces.model.AutocompleteRequest
import kotlinx.coroutines.launch

// In your custom autocomplete UI
searchEditText.addTextChangedListener(object : TextWatcher {
    override fun afterTextChanged(s: Editable?) {
        val query = s.toString()
        if (query.length < 3) return

        scope.launch {
            val response = placesClient.autocomplete(AutocompleteRequest {
                queryText = query
                maxResults = 5
            })

            response.resultItems?.let { suggestions ->
                updateSuggestionsList(suggestions)
            }
        }
    }
})

// When user selects a suggestion
fun onSuggestionSelected(placeId: String) {
    scope.launch {
        val response = placesClient.getPlace(GetPlaceRequest {
            this.placeId = placeId
        })

        response.position?.let { position ->
            val (lng, lat) = position
            Log.i(TAG, "Selected: Lat $lat, Lng $lng")
        }
    }
}
```

### Pattern 2: Current Location on Map

**Google Maps:**

```kotlin
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices

val fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

fusedLocationClient.lastLocation.addOnSuccessListener { location ->
    if (location != null) {
        val currentLatLng = LatLng(location.latitude, location.longitude)
        googleMap.addMarker(MarkerOptions().position(currentLatLng))
        googleMap.moveCamera(CameraUpdateFactory.newLatLngZoom(currentLatLng, 15f))
    }
}
```

**Amazon Location:**

```kotlin
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices

// Still use FusedLocationProviderClient for device location
val fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

fusedLocationClient.lastLocation.addOnSuccessListener { location ->
    if (location != null) {
        val currentLatLng = LatLng(location.latitude, location.longitude)

        // Use MapLibre to display
        mapLibreMap.cameraPosition = CameraPosition.Builder()
            .target(currentLatLng)
            .zoom(15.0)
            .build()

        symbolManager.create(
            SymbolOptions()
                .withLatLng(currentLatLng)
                .withIconImage("marker-icon")
        )
    }
}
```

### Pattern 3: Route Display on Map

**Google Maps:**

```kotlin
import com.google.android.gms.maps.model.PolylineOptions

val polylineOptions = PolylineOptions()
    .addAll(decodedPath)
    .color(Color.BLUE)
    .width(5f)

googleMap.addPolyline(polylineOptions)
```

**Amazon Location:**

```kotlin
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory.*
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.geojson.Feature
import org.maplibre.geojson.LineString
import org.maplibre.geojson.Point

// Convert route to GeoJSON
val coordinates = routePoints.map { Point.fromLngLat(it.second, it.first) }
val lineString = LineString.fromLngLats(coordinates)
val feature = Feature.fromGeometry(lineString)

// Add source and layer
val source = GeoJsonSource("route-source", feature)
style.addSource(source)

val lineLayer = LineLayer("route-layer", "route-source").withProperties(
    lineColor(Color.BLUE),
    lineWidth(5f)
)
style.addLayer(lineLayer)
```

## Migration Guide

### Official AWS Migration Guide

- **[Android Application Migration Guide](https://location.aws.com/migrate-an-android-app)** - Step-by-step guide for Android apps

### AWS SDK Documentation

- **[AWS SDK for Kotlin](https://aws.amazon.com/sdk-for-kotlin/)** - Official SDK documentation
- **[Amazon Location Service Developer Guide](https://docs.aws.amazon.com/location/)** - Service documentation
- **[API Reference](https://docs.aws.amazon.com/location/latest/APIReference/)** - Complete API reference

### MapLibre Documentation

- **[MapLibre Native Android](https://maplibre.org/maplibre-native/android/)** - Map rendering documentation
- **[MapLibre Android Examples](https://github.com/maplibre/maplibre-native/tree/main/platform/android)** - Code examples

## Best Practices

### Coroutines and Lifecycle

- Use `lifecycleScope` or `viewModelScope` for API calls
- Cancel coroutines when Activity/Fragment is destroyed
- Handle errors with try-catch blocks

```kotlin
lifecycleScope.launch {
    try {
        val response = placesClient.geocode(/* ... */)
        // Handle response
    } catch (e: Exception) {
        Log.e(TAG, "Geocoding failed", e)
        // Show error to user
    }
}
```

### Coordinate Conversion

- Create extension functions for easy conversion between Google and Amazon Location formats
- Always verify coordinate order when debugging

```kotlin
fun LatLng.toGeoJsonPosition(): List<Double> = listOf(longitude, latitude)
fun List<Double>.toLatLng(): LatLng = LatLng(this[1], this[0])
```

### Error Handling

- Implement proper error handling for network failures
- Show user-friendly error messages
- Implement retry logic for transient failures

### Testing

- Test with different device locations
- Verify coordinate conversions
- Test offline behavior

## Troubleshooting

### Common Issues

**Issue:** Map not displaying

- **Cause:** Incorrect API key or style URL
- **Fix:** Verify API key has Maps permissions, check style URL format

**Issue:** Coordinates in wrong location

- **Cause:** Lat/Lng order swapped
- **Fix:** Remember Amazon Location uses [lng, lat] order

**Issue:** Autocomplete not working

- **Cause:** Need to build custom UI, no widget available
- **Fix:** Implement custom autocomplete UI with EditText and RecyclerView

**Issue:** Build errors after adding dependencies

- **Cause:** Dependency conflicts or missing repositories
- **Fix:** Check MapLibre repository is added, verify dependency versions

### Getting Help

- **AWS SDK Issues:** [GitHub - AWS SDK Kotlin](https://github.com/awslabs/aws-sdk-kotlin)
- **MapLibre Issues:** [GitHub - MapLibre Native](https://github.com/maplibre/maplibre-native)
- **Amazon Location:** [AWS Forums](https://forums.aws.amazon.com/forum.jspa?forumID=356)
