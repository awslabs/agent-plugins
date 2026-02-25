# Places Search

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Search for places, points of interest, businesses, and addresses using Amazon Location Service Places APIs.

## Table of Contents

- [Overview](#overview)
- [API Selection Guide](#api-selection-guide)
- [Additional Features](#additional-features)
- [SearchText Examples](#searchtext-examples)
- [SearchNearby Examples](#searchnearby-examples)
- [Suggest Examples](#suggest-examples)
- [Response Handling](#response-handling)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

Amazon Location provides three main search APIs:

- **SearchText** - General text-based search ("tacos in Austin")
- **SearchNearby** - Location-proximity search (find restaurants within 5km)
- **Suggest** - Predictive search with partial/misspelled input
- **GetPlace** - Fetch complete details by PlaceId

## API Selection Guide

| Use Case                                   | API          | Example                                           |
| ------------------------------------------ | ------------ | ------------------------------------------------- |
| User searches for business/POI by name     | SearchText   | "Starbucks near downtown"                         |
| User searches by category                  | SearchText   | "restaurants in Vancouver"                        |
| Find places near a point on map            | SearchNearby | Find gas stations within 10km of current location |
| Type-ahead for place names (not addresses) | Suggest      | "star" → Starbucks, Starwood Hotel                |
| Type-ahead for addresses                   | Autocomplete | Use address-input reference instead               |
| Get full details after search              | GetPlace     | Fetch hours, contact info by PlaceId              |

## Additional Features

Places APIs support an `AdditionalFeatures` parameter that returns extra details beyond the default response. Request them by adding `AdditionalFeatures: ["Contact", "TimeZone", ...]` to your API call.

> **Pricing note**: Requesting additional features moves the request into the **Advanced** pricing bucket, which is priced higher than the default **Core** bucket. Review [Places pricing](https://docs.aws.amazon.com/location/latest/developerguide/places-pricing.html) before enabling them in production.

| Feature       | GetPlace | SearchText | SearchNearby | Suggest |
| ------------- | -------- | ---------- | ------------ | ------- |
| Contact       | Yes      | Yes        | Yes          | No      |
| Opening Hours | Yes      | Yes        | Yes          | No      |
| Time Zone     | Yes      | Yes        | Yes          | Yes     |
| Phonemes      | Yes      | Yes        | Yes          | Yes     |
| Access Points | Yes      | Yes        | Yes          | Yes     |

For the full feature-by-API matrix (including Geocode, ReverseGeocode, and Autocomplete), see [Additional features](https://docs.aws.amazon.com/location/latest/developerguide/additional-features.html).

### Contacts and Opening Hours

Contact and opening hours data is available on GetPlace, SearchText, and SearchNearby. Request both by including `"Contact"` in the `AdditionalFeatures` array. The valid `AdditionalFeatures` enum values are `TimeZone`, `Phonemes`, `Access`, and `Contact` (GetPlace also supports `SecondaryAddresses`). There is no separate `"OpeningHours"` enum value — requesting `"Contact"` returns both contact details and opening hours.

Contacts can include:

- **Phone number** — primary contact number, may include international dialing codes
- **Email address** — primary contact email from the public listing
- **Website** — link to the official site

Opening hours can include:

- **Regular hours** — standard weekly schedule (e.g., Mon–Fri 9 AM–5 PM)
- **Special hours** — holiday or event overrides to the regular schedule
- **Open now** — whether the location is currently open based on local time

```javascript
// Request contacts and opening hours
const command = new amazonLocationClient.places.SearchTextCommand({
  QueryText: "coffee shops in Austin",
  AdditionalFeatures: ["Contact"],
  MaxResults: 5,
});

const response = await client.send(command);

response.ResultItems.forEach((place) => {
  console.log(place.Title);
  console.log("Phone:", place.Contacts?.Phones?.[0]?.Value);
  console.log("Website:", place.Contacts?.Websites?.[0]?.Value);
  console.log("Hours:", place.OpeningHours);
});
```

For more details, see [Contacts and opening hours](https://docs.aws.amazon.com/location/latest/developerguide/contacts-opening-hours.html).

## SearchText Examples

For exact request parameters and response structure, see the [SearchText API Reference](https://docs.aws.amazon.com/location/latest/APIReference/API_geoplaces_SearchText.html).

### Basic Text Search

```javascript
const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
const client = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

async function searchPlaces(query) {
  try {
    const command = new amazonLocationClient.places.SearchTextCommand({
      QueryText: query,
      MaxResults: 10,
    });

    const response = await client.send(command);

    // Display results
    response.ResultItems.forEach((place) => {
      console.log(place.Title); // "Starbucks"
      console.log(place.Address?.Label); // "123 Main St, Austin, TX"
      console.log(place.Position); // [lon, lat]
      // Categories are objects: { Id: string, Name: string, LocalizedName?: string, Primary?: boolean }
      console.log(place.Categories); // [{ Id: "9000", Name: "Coffee Shop" }, { Id: "5814", Name: "Café" }]
      console.log(place.PlaceId); // For fetching details
    });

    return response.ResultItems;
  } catch (error) {
    console.error("Search error:", error);
    return [];
  }
}

// Usage
searchPlaces("coffee shops in Austin");
```

### Search with Geographic Bias

```javascript
// Bias results toward a specific location
async function searchNear(query, biasPosition) {
  const command = new amazonLocationClient.places.SearchTextCommand({
    QueryText: query,
    BiasPosition: biasPosition, // [lon, lat] - prefer results near here
    MaxResults: 10,
  });

  const response = await client.send(command);
  return response.ResultItems;
}

// Usage - find tacos near Austin
searchNear("tacos", [-97.7431, 30.2747]);
```

### Search with Category Filter

```javascript
async function searchByCategory(query, categories) {
  const command = new amazonLocationClient.places.SearchTextCommand({
    QueryText: query,
    Filter: {
      Categories: categories, // Filter by category codes
    },
    MaxResults: 20,
  });

  const response = await client.send(command);
  return response.ResultItems;
}

// Usage - find only restaurants
searchByCategory("food near downtown", ["Restaurant"]);
```

### Search with Bounding Box

```javascript
// Restrict search to specific geographic area
async function searchInBounds(query, boundingBox) {
  const command = new amazonLocationClient.places.SearchTextCommand({
    QueryText: query,
    Filter: {
      BoundingBox: boundingBox, // [west, south, east, north]
    },
    MaxResults: 10,
  });

  const response = await client.send(command);
  return response.ResultItems;
}

// Usage - find hotels in downtown Austin area
const austinDowntown = [-97.7535, 30.2586, -97.7327, 30.2747];
searchInBounds("hotels", austinDowntown);
```

## SearchNearby Examples

For exact request parameters and response structure, see the [SearchNearby API Reference](https://docs.aws.amazon.com/location/latest/APIReference/API_geoplaces_SearchNearby.html).

### Basic Proximity Search

```javascript
async function searchNearby(position, radius, categories = null) {
  const params = {
    QueryPosition: position, // [lon, lat]
    MaxResults: 20,
  };

  // Optional: filter by categories
  if (categories) {
    params.Filter = { Categories: categories };
  }

  // Optional: specify radius (default is context-dependent)
  if (radius) {
    params.MaxDistance = radius; // in meters
  }

  const command = new amazonLocationClient.places.SearchNearbyCommand(params);

  try {
    const response = await client.send(command);

    // Results are already sorted by distance
    response.ResultItems.forEach((place) => {
      console.log(place.Title);
      console.log(place.Distance, "meters away");
      console.log(place.Position);
    });

    return response.ResultItems;
  } catch (error) {
    console.error("Nearby search error:", error);
    return [];
  }
}

// Usage - find restaurants within 5km
const userLocation = [-97.7431, 30.2747];
searchNearby(userLocation, 5000, ["Restaurant"]);
```

### Find Nearest of Type

```javascript
// Find single nearest place of a specific type
async function findNearest(position, category) {
  const command = new amazonLocationClient.places.SearchNearbyCommand({
    QueryPosition: position,
    Filter: { Categories: [category] },
    MaxResults: 1, // Just the nearest
  });

  const response = await client.send(command);

  if (response.ResultItems.length === 0) {
    return null;
  }

  return response.ResultItems[0];
}

// Usage - find nearest gas station
const nearest = await findNearest([-97.7431, 30.2747], "Gas Station");
if (nearest) {
  console.log(`Nearest: ${nearest.Title}, ${nearest.Distance}m away`);
}
```

### Search with Map Integration

```javascript
// Display nearby search results on map
async function showNearbyOnMap(map, position, category) {
  const results = await searchNearby(position, 2000, [category]);

  // Clear existing markers
  document.querySelectorAll(".nearby-marker").forEach((el) => el.remove());

  // Add markers for each result
  results.forEach((place, index) => {
    const marker = new maplibregl.Marker({ color: "#FF0000" })
      .setLngLat(place.Position)
      .setPopup(
        new maplibregl.Popup().setHTML(`
          <h4>${place.Title}</h4>
          <p>${place.Address?.Label || ""}</p>
          <p>${Math.round(place.Distance)}m away</p>
        `),
      )
      .addTo(map);

    marker.getElement().classList.add("nearby-marker");
  });

  // Fit map to show all results
  if (results.length > 0) {
    const bounds = new maplibregl.LngLatBounds();
    results.forEach((place) => bounds.extend(place.Position));
    bounds.extend(position); // Include search center
    map.fitBounds(bounds, { padding: 50 });
  }
}
```

## Suggest Examples

For exact request parameters and response structure, see the [Suggest API Reference](https://docs.aws.amazon.com/location/latest/APIReference/API_geoplaces_Suggest.html).

### Suggest Response Structure

Suggest returns items with a `SuggestResultItemType` that can be `"Place"` or `"Query"`:

- **Place results**: Have `item.Place.PlaceId`, `item.Place.Position`, `item.Place.Address` — use `PlaceId` with `GetPlace` for full details
- **Query results**: Have `item.Query.QueryText` — these are search refinement suggestions, not actual places

Always check `item.Place?.PlaceId` before attempting to call `GetPlace`.

### Predictive Place Search

```javascript
// Like Autocomplete but for places/POIs (not just addresses)
async function suggestPlaces(partialQuery, biasPosition = null) {
  const params = {
    QueryText: partialQuery,
    MaxResults: 5,
  };

  if (biasPosition) {
    params.BiasPosition = biasPosition;
  }

  const command = new amazonLocationClient.places.SuggestCommand(params);

  try {
    const response = await client.send(command);

    response.ResultItems.forEach((item) => {
      console.log(item.Title); // "Starbucks"
      console.log(item.Place?.PlaceId); // For fetching full details
      console.log(item.SuggestResultItemType); // "Place" or "Query"
    });

    return response.ResultItems;
  } catch (error) {
    console.error("Suggest error:", error);
    return [];
  }
}

// Usage - type-ahead for place search
document.getElementById("place-search").addEventListener("input", async (e) => {
  const query = e.target.value;

  if (query.length < 3) return;

  const suggestions = await suggestPlaces(query);

  // Display suggestions (similar to autocomplete)
  displaySuggestions(suggestions);
});
```

## Response Handling

For exact request parameters and response structure for fetching place details, see the [GetPlace API Reference](https://docs.aws.amazon.com/location/latest/APIReference/API_geoplaces_GetPlace.html).

### Parse Place Details

```javascript
function parsePlaceResult(place) {
  return {
    id: place.PlaceId,
    name: place.Title,
    address: place.Address?.Label || "Address not available",
    coordinates: {
      lat: place.Position[1],
      lon: place.Position[0],
    },
    categories: (place.Categories || []).map((c) => c.Name), // Category is { Id, Name, LocalizedName?, Primary? }
    primaryCategory: place.Categories?.find((c) => c.Primary)?.Name,
    distance: place.Distance, // Only in SearchNearby results

    // Optional fields - check before using
    phone: place.Contacts?.Phones?.[0]?.Value,
    website: place.Contacts?.Websites?.[0]?.Value,

    // Use GetPlace for more details
    hasMoreDetails: !!place.PlaceId,
  };
}

// Usage
const results = await searchPlaces("coffee");
const parsed = results.map(parsePlaceResult);
```

### Fetch Complete Details

```javascript
// Get full details including hours, contact info
async function getPlaceDetails(placeId) {
  const command = new amazonLocationClient.places.GetPlaceCommand({
    PlaceId: placeId,
  });

  try {
    const response = await client.send(command);

    return {
      name: response.Title,
      address: response.Address,
      position: response.Position,
      categories: response.Categories,
      contacts: {
        phones: response.Contacts?.Phones || [],
        websites: response.Contacts?.Websites || [],
        emails: response.Contacts?.Emails || [],
      },
      openingHours: response.OpeningHours || [],
      accessPoints: response.AccessPoints || [], // Entrances
      timeZone: response.TimeZone,
    };
  } catch (error) {
    console.error("GetPlace error:", error);
    return null;
  }
}

// Usage - user clicks on search result to see details
async function showPlaceDetails(placeId) {
  const details = await getPlaceDetails(placeId);

  if (details) {
    console.log("Phone:", details.contacts.phones[0]?.Value);
    console.log("Hours:", details.openingHours);
  }
}
```

## Error Handling

### Common Errors

```javascript
async function searchWithErrorHandling(query) {
  try {
    const command = new amazonLocationClient.places.SearchTextCommand({
      QueryText: query,
      MaxResults: 10,
    });

    const response = await client.send(command);

    if (response.ResultItems.length === 0) {
      // No results found
      showMessage("No places found. Try a different search.");
      return [];
    }

    return response.ResultItems;
  } catch (error) {
    // API errors
    if (error.name === "ValidationException") {
      showMessage("Invalid search query. Please check your input.");
    } else if (error.name === "AccessDeniedException") {
      showMessage("API key lacks permission for place search.");
    } else if (error.name === "ThrottlingException") {
      showMessage("Too many requests. Please wait and try again.");
    } else {
      showMessage("Search failed. Please try again.");
    }

    console.error("Search error:", error);
    return [];
  }
}
```

### Retry with Fallback

```javascript
// Try nearby search, fall back to text search if no results
async function searchWithFallback(query, position) {
  // Try nearby search first
  let results = await searchNearby(position, 5000);

  if (results.length === 0) {
    console.log("No nearby results, trying text search...");
    // Fall back to text search with position bias
    results = await searchNear(query, position);
  }

  return results;
}
```

## Best Practices

### Performance

- **Debounce search input**: Wait 300ms after user stops typing
- **Consider pricing for caching**: If storing results beyond temporary session caching, review [Places API Stored Pricing](https://docs.aws.amazon.com/location/latest/developerguide/places-pricing.html#stored-pricing) and use `IntendedUse: "Storage"` parameter.
- **Limit MaxResults**: Request only what you'll display (10-20 typically)
- **Cancel in-flight requests**: Cancel previous search when user types new query

### User Experience

- **Show loading state**: Spinner or skeleton UI during search
- **Display distance**: Show distance for SearchNearby results
- **Group by category**: Organize results by Categories
- **Pagination**: Load more results as user scrolls
- **Empty states**: Helpful message when no results ("Try different keywords")

### Data Quality

- **Validate coordinates**: Ensure Position is valid [lon, lat]
- **Handle missing fields**: Not all places have phone/website/hours
- **Use PlaceId**: Store PlaceId for future GetPlace calls, not full details
- **Respect Categories**: Use Categories array for filtering and display

### Search Optimization

- **Use BiasPosition**: Improves relevance for location-aware searches
- **Combine filters**: Use Categories + BoundingBox for precise results
- **Choose right API**: SearchText for queries, SearchNearby for proximity
- **Prefer SearchNearby**: For "near me" features (faster, more relevant)

### Error Handling

- **Handle no results**: Suggest alternative searches or expand radius
- **Show partial results**: Display what you have even if some fail
- **Retry on network errors**: Retry once after brief delay
- **Log for debugging**: Log errors with search parameters for troubleshooting
