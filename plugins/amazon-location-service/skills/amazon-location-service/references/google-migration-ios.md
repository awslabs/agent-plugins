# Google Maps Migration (iOS)

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Migrate iOS applications from Google Maps SDK for iOS to Amazon Location Service using the AWS SDK for Swift and MapLibre Native.

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

| Aspect             | Google Maps SDK                               | Amazon Location Service                 |
| ------------------ | --------------------------------------------- | --------------------------------------- |
| **Drop-in SDK**    | ❌ Not available                              | Direct AWS SDK migration required       |
| **Map rendering**  | Google Maps renderer                          | MapLibre Native iOS                     |
| **API style**      | Delegate/completion-based                     | Swift async/await                       |
| **Coordinates**    | `CLLocationCoordinate2D(latitude:longitude:)` | `[longitude, latitude]` - GeoJSON order |
| **Authentication** | API Key in AppDelegate                        | AWS API Key or Cognito credentials      |
| **SDK frameworks** | `GoogleMaps`, `GooglePlaces`                  | `AWSGeoPlaces`, `AWSGeoRoutes`, etc.    |

**Migration timeline:** Expect 1-2 weeks for a typical app with maps, places, and routing features.

**No migration SDK available** - Unlike JavaScript, there is no drop-in replacement for iOS. You'll need to refactor your Google Maps code to use Amazon Location APIs directly.

## Setup and Dependencies

### Remove Google Maps Dependencies

**In your `Podfile`:**

```ruby
# Remove Google Maps pods
# pod 'GoogleMaps'
# pod 'GooglePlaces'
# pod 'GoogleMapsUtils'
```

**Or if using Swift Package Manager, remove Google Maps packages from Xcode:**

- File → Swift Packages → Remove Package

### Add Amazon Location Dependencies

**Using Swift Package Manager (Recommended):**

1. In Xcode: File → Add Packages...
2. Add **Amazon Location Mobile Auth SDK**:
   - URL: `https://github.com/aws-geospatial/amazon-location-mobile-auth-sdk-ios`
   - Select product: `AmazonLocationiOSAuthSDK`
3. Add **AWS SDK for Swift**:
   - URL: `https://github.com/awslabs/aws-sdk-swift`
   - Select products: `AWSGeoPlaces`, `AWSGeoRoutes`, `AWSGeoMaps`, `AWSLocation`
4. Add **MapLibre**:
   - URL: `https://github.com/maplibre/maplibre-gl-native-distribution`

**Using CocoaPods - Add to your `Podfile`:**

```ruby
# Amazon Location Mobile Auth SDK (recommended)
pod 'AmazonLocationiOSAuthSDK'

# MapLibre for map display
pod 'MapLibre', '~> 6.0'

# AWS SDK for Swift
pod 'AWSGeoPlaces'
pod 'AWSGeoRoutes'
pod 'AWSGeoMaps'
pod 'AWSLocation'
```

**Note:** MapLibre is the open-source fork of Mapbox GL Native and is the recommended way to display maps with Amazon Location Service on iOS.

### Update Info.plist

**Remove Google Maps API key:**

```xml
<!-- Remove this -->
<key>GMSServicesApiKey</key>
<string>YOUR_GOOGLE_API_KEY</string>
```

**Add location permissions (if not already present):**

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to show nearby places</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location for tracking features</string>
```

## Authentication

Amazon Location Service supports API Key and Cognito authentication. Use the **Amazon Location Mobile Auth SDK** for simplified authentication setup.

### API Key Authentication (Recommended for Maps, Places, Routes)

**Using the Amazon Location Mobile Auth SDK:**

```swift
import AmazonLocationiOSAuthSDK
import AWSGeoPlaces

class AmazonLocationAuth {
    static let apiKey = "YOUR_AMAZON_LOCATION_API_KEY"
    static let region = "us-west-2"

    // Create an authentication helper using your API key and region
    static func createAuthHelper() async throws -> AuthHelper {
        return try await AuthHelper.withApiKey(apiKey: apiKey, region: region)
    }

    // Create a Places client
    static func createPlacesClient() async throws -> GeoPlacesClient {
        let authHelper = try await createAuthHelper()
        return GeoPlacesClient(config: authHelper.getGeoPlacesClientConfig())
    }

    // Create a Routes client
    static func createRoutesClient() async throws -> GeoRoutesClient {
        let authHelper = try await createAuthHelper()
        return GeoRoutesClient(config: authHelper.getGeoRoutesClientConfig())
    }

    // Create a Location client (for geofencing/tracking)
    static func createLocationClient() async throws -> LocationClient {
        let authHelper = try await createAuthHelper()
        return LocationClient(config: authHelper.getLocationClientConfig())
    }
}
```

**Usage:**

```swift
import AWSGeoPlaces

class PlacesViewController: UIViewController {
    var placesClient: GeoPlacesClient?

    override func viewDidLoad() {
        super.viewDidLoad()

        Task {
            // Simple one-line client creation
            placesClient = try await AmazonLocationAuth.createPlacesClient()

            // Use client for API calls
            let input = SearchTextInput(
                queryText: "coffee shops",
                biasPosition: [-97.7431, 30.2747]
            )
            let response = try await placesClient?.searchText(input: input)
        }
    }
}
```

### Cognito Authentication (Required for Geofencing, Tracking)

**Using the Amazon Location Mobile Auth SDK with Cognito:**

```swift
import AmazonLocationiOSAuthSDK
import AWSLocation

func createLocationClientWithCognito() async throws -> LocationClient {
    let identityPoolId = "YOUR_IDENTITY_POOL_ID"

    // Create authentication helper using Cognito credentials
    let authHelper = try await AuthHelper.withIdentityPoolId(identityPoolId: identityPoolId)

    // Configure the LocationClient to use credentials from Cognito
    return LocationClient(config: authHelper.getLocationClientConfig())
}
```

**Key benefits of using the Auth SDK:**

- ✅ Simplified API Key and Cognito authentication
- ✅ Automatic credential management
- ✅ Pre-configured client configurations for all Amazon Location services
- ✅ Handles region and endpoint configuration automatically

## API Mappings Reference

### Places API

| Google Maps iOS                                 | Amazon Location iOS               | Migration Notes                       |
| ----------------------------------------------- | --------------------------------- | ------------------------------------- |
| `GMSPlacesClient.currentPlace()`                | `SearchNearbyCommand`             | Use device location with SearchNearby |
| `GMSPlacesClient.fetchPlace()`                  | `GetPlaceCommand`                 | Fetch place details by PlaceId        |
| `GMSAutocompleteViewController`                 | `AutocompleteCommand` + custom UI | Address autocomplete                  |
| `GMSPlacesClient.findAutocompletePredictions()` | `AutocompleteCommand`             | Programmatic autocomplete             |

**Example - Place Search:**

```swift
// Google Maps (Before)
import GooglePlaces

let placesClient = GMSPlacesClient.shared()
let filter = GMSAutocompleteFilter()
filter.types = ["restaurant"]

placesClient.currentPlace { (placeLikelihoodList, error) in
    if let error = error {
        print("Error: \(error)")
        return
    }

    guard let placeLikelihoods = placeLikelihoodList?.likelihoods else {
        return
    }

    for likelihood in placeLikelihoods {
        let place = likelihood.place
        print("Place: \(place.name), \(place.coordinate)")
    }
}

// Amazon Location (After)
import AmazonLocationiOSAuthSDK
import AWSGeoPlaces
import CoreLocation

let placesClient = try await AmazonLocationAuth.createPlacesClient()

// Assume you have device location
let deviceLocation: [Double] = [-97.7431, 30.2747] // [lng, lat]

let input = SearchNearbyInput(
    queryPosition: deviceLocation,
    maxResults: 20,
    filter: SearchNearbyInputFilter(
        includeCategories: ["Restaurant"]
    )
)

let response = try await placesClient.searchNearby(input: input)

response.resultItems?.forEach { place in
    print("Place: \(place.title ?? ""), \(place.position ?? [])")
}
```

### Geocoding API

| Google Maps iOS                          | Amazon Location iOS     | Migration Notes                           |
| ---------------------------------------- | ----------------------- | ----------------------------------------- |
| `GMSGeocoder.geocodeAddressString()`     | `GeocodeCommand`        | Forward geocoding (address → coordinates) |
| `GMSGeocoder.reverseGeocodeCoordinate()` | `ReverseGeocodeCommand` | Reverse geocoding (coordinates → address) |

**Example - Geocoding:**

```swift
// Google Maps (Before)
import GoogleMaps

let geocoder = GMSGeocoder()
geocoder.geocodeAddressString("Austin, TX") { response, error in
    guard let response = response, let result = response.firstResult() else {
        return
    }

    print("Lat: \(result.coordinate.latitude), Lng: \(result.coordinate.longitude)")
}

// Amazon Location (After)
import AmazonLocationiOSAuthSDK
import AWSGeoPlaces

let placesClient = try await AmazonLocationAuth.createPlacesClient()

let input = GeocodeInput(
    queryText: "Austin, TX",
    maxResults: 1
)

let response = try await placesClient.geocode(input: input)

if let result = response.resultItems?.first,
   let position = result.position {
    let lng = position[0]
    let lat = position[1]
    print("Lat: \(lat), Lng: \(lng)")
}
```

### Directions/Routing API

| Google Maps iOS                          | Amazon Location iOS           | Migration Notes        |
| ---------------------------------------- | ----------------------------- | ---------------------- |
| `GMSDirectionsService.fetchDirections()` | `CalculateRoutesCommand`      | Route calculation      |
| `GMSDistanceMatrixService`               | `CalculateRouteMatrixCommand` | Many-to-many distances |

**Example - Directions:**

```swift
// Google Maps (Before)
import GoogleMaps

let origin = "Austin, TX"
let destination = "Dallas, TX"

GMSDirectionsService().fetchDirections(from: origin, to: destination) { response, error in
    guard let response = response, let route = response.routes.first else {
        return
    }

    let leg = route.legs.first
    print("Distance: \(leg?.distance.value ?? 0)")
}

// Amazon Location (After)
import AmazonLocationiOSAuthSDK
import AWSGeoRoutes

let routesClient = try await AmazonLocationAuth.createRoutesClient()

let input = CalculateRoutesInput(
    origin: [-97.7431, 30.2747], // Austin [lng, lat]
    destination: [-96.7970, 32.7767], // Dallas [lng, lat]
    travelMode: .car,
    legAdditionalFeatures: [.summary]
)

let response = try await routesClient.calculateRoutes(input: input)

if let route = response.routes?.first,
   let leg = route.legs?.first,
   let distance = leg.vehicleLegDetails?.summary?.overview?.distance {
    print("Distance: \(distance) meters")
}
```

### Map Display

| Google Maps iOS     | Amazon Location iOS     | Migration Notes            |
| ------------------- | ----------------------- | -------------------------- |
| `GMSMapView`        | `MLNMapView` (MapLibre) | Different rendering engine |
| `GMSMarker`         | `MLNPointAnnotation`    | MapLibre annotation API    |
| `GMSPolyline`       | `MLNPolyline`           | Similar polyline API       |
| `GMSCameraPosition` | `MLNMapCamera`          | Similar camera API         |

**Example - Display Map:**

```swift
// Google Maps (Before)
import GoogleMaps

class MapViewController: UIViewController {
    var mapView: GMSMapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let camera = GMSCameraPosition.camera(
            withLatitude: 30.2747,
            longitude: -97.7431,
            zoom: 10
        )
        mapView = GMSMapView.map(withFrame: view.bounds, camera: camera)
        view.addSubview(mapView)

        // Add marker
        let marker = GMSMarker()
        marker.position = CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431)
        marker.title = "Austin"
        marker.map = mapView
    }
}

// Amazon Location (After)
import Mapbox  // MapLibre pod imports as Mapbox for compatibility

class MapViewController: UIViewController {
    var mapView: MLNMapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create map with Amazon Location style
        let apiKey = AmazonLocationAuth.apiKey
        let region = AmazonLocationAuth.region
        let styleURL = URL(string: "https://maps.geo.\(region).amazonaws.com/v2/styles/Standard/descriptor?key=\(apiKey)")!

        mapView = MLNMapView(frame: view.bounds, styleURL: styleURL)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.setCenter(
            CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431),
            zoomLevel: 10,
            animated: false
        )
        view.addSubview(mapView)

        // Add marker
        let annotation = MLNPointAnnotation()
        annotation.coordinate = CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431)
        annotation.title = "Austin"
        mapView.addAnnotation(annotation)
    }
}
```

## Helper and Math Libraries

Google Maps SDK includes utility classes for geometry operations. For Amazon Location, use these alternatives:

### Polyline Encoding/Decoding

| Google Maps iOS             | Amazon Location Alternative | Package                            |
| --------------------------- | --------------------------- | ---------------------------------- |
| `GMSPath(fromEncodedPath:)` | Custom implementation       | Implement using polyline algorithm |
| `GMSPath.encodedPath()`     | Custom implementation       | Implement using polyline algorithm |

**Example - Polyline Decoding (Custom Implementation):**

```swift
// Google Maps (Before)
import GoogleMaps

let path = GMSPath(fromEncodedPath: encodedPolyline)

// Amazon Location (After) - Custom implementation
class PolylineDecoder {
    static func decode(_ encodedPolyline: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encodedPolyline.startIndex
        var lat = 0
        var lng = 0

        while index < encodedPolyline.endIndex {
            var result = 1
            var shift = 0
            var b: Int

            repeat {
                b = Int(encodedPolyline[index].asciiValue!) - 63 - 1
                index = encodedPolyline.index(after: index)
                result += b << shift
                shift += 5
            } while b >= 0x1f

            lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            result = 1
            shift = 0

            repeat {
                b = Int(encodedPolyline[index].asciiValue!) - 63 - 1
                index = encodedPolyline.index(after: index)
                result += b << shift
                shift += 5
            } while b >= 0x1f

            lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1)

            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }

        return coordinates
    }
}
```

### Geometry Operations

| Google Maps iOS                 | Amazon Location Alternative | Approach                 |
| ------------------------------- | --------------------------- | ------------------------ |
| `GMSGeometryDistance()`         | Use Haversine formula       | Implement calculation    |
| `GMSGeometryContainsLocation()` | Point-in-polygon algorithm  | Implement or use library |
| `GMSGeometryIsLocationOnPath()` | Point-to-line distance      | Implement calculation    |

**Example - Distance Calculation:**

```swift
// Google Maps (Before)
import GoogleMaps

let from = CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431)
let to = CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970)
let distance = GMSGeometryDistance(from, to)

// Amazon Location (After) - Haversine implementation
import CoreLocation

extension CLLocationCoordinate2D {
    func distance(to: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0 // meters

        let lat1 = self.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - self.latitude) * .pi / 180
        let dLng = (to.longitude - self.longitude) * .pi / 180

        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) *
                sin(dLng / 2) * sin(dLng / 2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

let from = CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431)
let to = CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970)
let distance = from.distance(to: to)
```

**For complex geometry operations**, consider:

- Implementing standard algorithms (Haversine, point-in-polygon)
- Using [Turf Swift](https://github.com/mapbox/turf-swift) - Port of Turf.js for iOS

### Coordinate System Differences

**Critical:** Google Maps uses `CLLocationCoordinate2D(latitude:longitude:)` while Amazon Location uses `[longitude, latitude]` (GeoJSON order).

```swift
// Google Maps
let coordinate = CLLocationCoordinate2D(latitude: 30.2747, longitude: -97.7431)

// Amazon Location
let position: [Double] = [-97.7431, 30.2747] // [lng, lat]

// Converting between them
extension CLLocationCoordinate2D {
    func toGeoJsonPosition() -> [Double] {
        return [longitude, latitude]
    }

    init(geoJsonPosition: [Double]) {
        self.init(latitude: geoJsonPosition[1], longitude: geoJsonPosition[0])
    }
}
```

## Migration Patterns

### Pattern 1: Places Autocomplete

**Google Maps:**

```swift
import GooglePlaces

let autocompleteController = GMSAutocompleteViewController()
autocompleteController.delegate = self

present(autocompleteController, animated: true, completion: nil)

// GMSAutocompleteViewControllerDelegate
func viewController(_ viewController: GMSAutocompleteViewController,
                   didAutocompleteWith place: GMSPlace) {
    print("Place: \(place.name), \(place.coordinate)")
    dismiss(animated: true, completion: nil)
}
```

**Amazon Location:**

```swift
import AWSGeoPlaces
import UIKit

// Custom autocomplete UI
class AutocompleteViewController: UIViewController, UISearchBarDelegate {
    let searchBar = UISearchBar()
    let tableView = UITableView()
    var suggestions: [GeocodingResultItem] = []

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard searchText.count >= 3 else { return }

        Task {
            let input = AutocompleteInput(
                queryText: searchText,
                maxResults: 5
            )

            let response = try await placesClient.autocomplete(input: input)
            suggestions = response.resultItems ?? []
            tableView.reloadData()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let suggestion = suggestions[indexPath.row]

        Task {
            if let placeId = suggestion.placeId {
                let input = GetPlaceInput(placeId: placeId)
                let response = try await placesClient.getPlace(input: input)

                if let position = response.position {
                    let coordinate = CLLocationCoordinate2D(geoJsonPosition: position)
                    print("Selected: \(coordinate)")
                }
            }
        }
    }
}
```

### Pattern 2: Current Location on Map

**Google Maps:**

```swift
import GoogleMaps
import CoreLocation

class MapViewController: UIViewController, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var mapView: GMSMapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager,
                        didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        let camera = GMSCameraPosition.camera(
            withTarget: location.coordinate,
            zoom: 15
        )
        mapView.camera = camera

        let marker = GMSMarker(position: location.coordinate)
        marker.map = mapView

        locationManager.stopUpdatingLocation()
    }
}
```

**Amazon Location:**

```swift
import Mapbox  // MapLibre
import CoreLocation

class MapViewController: UIViewController, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var mapView: MLNMapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let styleURL = URL(string: "https://maps.geo.us-west-2.amazonaws.com/v2/styles/Standard/descriptor?key=\(apiKey)")!
        mapView = MLNMapView(frame: view.bounds, styleURL: styleURL)
        view.addSubview(mapView)

        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager,
                        didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }

        mapView.setCenter(
            location.coordinate,
            zoomLevel: 15,
            animated: true
        )

        let annotation = MLNPointAnnotation()
        annotation.coordinate = location.coordinate
        mapView.addAnnotation(annotation)

        locationManager.stopUpdatingLocation()
    }
}
```

### Pattern 3: Route Display on Map

**Google Maps:**

```swift
import GoogleMaps

let path = GMSMutablePath()
routeCoordinates.forEach { path.add($0) }

let polyline = GMSPolyline(path: path)
polyline.strokeColor = .blue
polyline.strokeWidth = 5
polyline.map = mapView
```

**Amazon Location:**

```swift
import Mapbox  // MapLibre

// Create polyline from coordinates
let polyline = MLNPolyline(coordinates: routeCoordinates, count: UInt(routeCoordinates.count))

// Add polyline to map
mapView.addAnnotation(polyline)

// Customize appearance using MLNMapViewDelegate
func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
    return .blue
}

func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
    return 5
}
```

## Migration Guide

### Official AWS Migration Guide

- **[iOS Application Migration Guide](https://location.aws.com/migrate-an-ios-app)** - Step-by-step guide for iOS apps

### AWS SDK Documentation

- **[Amazon Location Mobile Auth SDK for iOS](https://github.com/aws-geospatial/amazon-location-mobile-auth-sdk-ios)** - Simplified authentication for API keys and Cognito
- **[AWS SDK for Swift](https://aws.amazon.com/sdk-for-swift/)** - Official SDK documentation
- **[Amazon Location Service Developer Guide](https://docs.aws.amazon.com/location/)** - Service documentation
- **[API Reference](https://docs.aws.amazon.com/location/latest/APIReference/)** - Complete API reference

### MapLibre Documentation

- **[MapLibre Native iOS](https://maplibre.org/maplibre-native/ios/)** - Map rendering documentation
- **[MapLibre iOS Examples](https://github.com/maplibre/maplibre-native/tree/main/platform/ios)** - Code examples

## Best Practices

### Swift Concurrency

- Use `async/await` for API calls
- Handle errors with `do-catch` blocks
- Use `Task` for launching asynchronous work from synchronous contexts

```swift
Task {
    do {
        let response = try await placesClient.geocode(input: input)
        // Handle response
    } catch {
        print("Geocoding failed: \(error)")
        // Show error to user
    }
}
```

### Coordinate Conversion

- Create extension methods for easy conversion
- Always verify coordinate order when debugging

```swift
extension CLLocationCoordinate2D {
    func toGeoJsonPosition() -> [Double] {
        [longitude, latitude]
    }

    init(geoJsonPosition: [Double]) {
        self.init(latitude: geoJsonPosition[1], longitude: geoJsonPosition[0])
    }
}
```

### Memory Management

- Weak reference delegates to avoid retain cycles
- Properly manage MapView lifecycle

```swift
class MapViewController: UIViewController, MLNMapViewDelegate {
    var mapView: MLNMapView!

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.delegate = self
    }

    deinit {
        mapView.delegate = nil
    }
}
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
- **Fix:** Implement custom autocomplete UI with UISearchBar and UITableView

**Issue:** Build errors after adding dependencies

- **Cause:** Dependency conflicts or version mismatches
- **Fix:** Verify CocoaPods/SPM configuration, check dependency versions

**Issue:** Async/await not available

- **Cause:** Minimum iOS version too low
- **Fix:** Set minimum deployment target to iOS 15.0 or higher

### Getting Help

- **Amazon Location Mobile Auth SDK:** [GitHub - Auth SDK iOS](https://github.com/aws-geospatial/amazon-location-mobile-auth-sdk-ios)
- **AWS SDK Issues:** [GitHub - AWS SDK Swift](https://github.com/awslabs/aws-sdk-swift)
- **MapLibre Issues:** [GitHub - MapLibre Native](https://github.com/maplibre/maplibre-native)
- **Amazon Location:** [AWS Forums](https://forums.aws.amazon.com/forum.jspa?forumID=356)
