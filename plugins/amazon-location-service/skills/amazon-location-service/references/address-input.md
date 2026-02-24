# Address Input

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Create effective address input forms with type-ahead completion that improves input speed and accuracy using Amazon Location Service Places APIs.

## Table of Contents

- [Overview](#overview)
- [Complete Implementation Flow](#complete-implementation-flow)
- [API Details](#api-details)
- [Code Examples](#code-examples)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

Address input forms SHOULD implement this three-stage flow:

1. **Autocomplete** - Type-ahead suggestions as user types
2. **GetPlace** - Fetch complete details when user selects a suggestion
3. **Geocode** - Validate if user types complete address without selecting

## Complete Implementation Flow

```javascript
// Stage 1: User types in address field → Autocomplete
// Stage 2: User selects suggestion → GetPlace
// Stage 3: User submits without selection → Geocode

// HTML Structure
<input id="address-input" type="text" placeholder="Enter address">
<div id="suggestions"></div>
<button id="submit">Submit</button>
```

## API Details

### Autocomplete

**Purpose**: Provide type-ahead suggestions for partially typed addresses.

**When to use**: As user types in address input field (typically after 3+ characters).

**Critical**: Always display `Address.Label` to users, NOT `Title`. The `Title` field may show components in reverse order and is not suitable for display.

**Returns**: Array of suggestions, each with:

- `PlaceId` - Use this to fetch full details with GetPlace
- `Address.Label` - Display this to users (e.g., "123 Main St, Seattle, WA 98101")
- `Title` - DO NOT display (may be reversed: "98101, WA, Seattle, Main St, 123")

### GetPlace

**Purpose**: Retrieve complete place details after user selects autocomplete suggestion.

**When to use**: When user clicks/selects an autocomplete suggestion.

**Input**: `PlaceId` from Autocomplete result.

**Returns**: Complete place object with nested Address structure:

```javascript
{
  PlaceId: "string",
  Address: {
    Label: "123 Main St, Seattle, WA 98101, USA",
    Region: {
      Code: "WA",           // State/province code
      Name: "Washington"    // Full state name
    },
    Country: {
      Code2: "US",          // ISO 2-letter country code
      Code3: "USA",         // ISO 3-letter country code
      Name: "United States" // Full country name
    },
    Locality: "Seattle",    // City name (string)
    PostalCode: "98101",    // Postal code (string)
    Street: "Main St",      // Street name (string)
    AddressNumber: "123"    // Street number (string)
  },
  Position: [lon, lat]      // Coordinates
}
```

**Important**: Address properties are nested objects, not flat strings. Access as `address.Region.Code`, not `address.RegionCode`.

### Geocode

**Purpose**: Validate and standardize a complete address typed by user (when they don't select autocomplete).

**When to use**: On form submission if user typed address but didn't select any autocomplete suggestion.

**Input**: Complete address string.

**Returns**: Array of matching addresses with coordinates and standardized formatting.

## Code Examples

### Complete Implementation

```javascript
// Initialize client
const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
const client = new amazonLocationClient.GeoPlacesClient(
  authHelper.getClientConfig(),
);

let selectedPlaceId = null;

// Stage 1: Autocomplete as user types
document
  .getElementById("address-input")
  .addEventListener("input", async (e) => {
    const query = e.target.value;

    if (query.length < 3) {
      document.getElementById("suggestions").innerHTML = "";
      return;
    }

    try {
      const command = new amazonLocationClient.places.AutocompleteCommand({
        QueryText: query,
        MaxResults: 5,
      });

      const response = await client.send(command);

      // Display suggestions using Address.Label (NOT Title!)
      const suggestionsHtml = response.ResultItems.map(
        (item) =>
          `<div class="suggestion" data-place-id="${item.Place?.PlaceId}">
        ${item.Address.Label}
      </div>`,
      ).join("");

      document.getElementById("suggestions").innerHTML = suggestionsHtml;
    } catch (error) {
      console.error("Autocomplete error:", error);
      // Show error to user
    }
  });

// Stage 2: User selects suggestion → GetPlace
document.getElementById("suggestions").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("suggestion")) return;

  const placeId = e.target.dataset.placeId;
  selectedPlaceId = placeId;

  try {
    const command = new amazonLocationClient.places.GetPlaceCommand({
      PlaceId: placeId,
    });

    const response = await client.send(command);
    const place = response;

    // Populate form with complete details
    document.getElementById("address-input").value = place.Address.Label;
    document.getElementById("street").value =
      `${place.Address.AddressNumber || ""} ${place.Address.Street || ""}`.trim();
    document.getElementById("city").value = place.Address.Locality || "";
    document.getElementById("state").value = place.Address.Region?.Code || "";
    document.getElementById("zip").value = place.Address.PostalCode || "";
    document.getElementById("country").value =
      place.Address.Country?.Code2 || "";

    // Store coordinates for later use
    document.getElementById("lat").value = place.Position[1];
    document.getElementById("lon").value = place.Position[0];

    // Clear suggestions
    document.getElementById("suggestions").innerHTML = "";
  } catch (error) {
    console.error("GetPlace error:", error);
    alert("Failed to fetch address details");
  }
});

// Stage 3: User submits without selecting → Geocode
document.getElementById("submit").addEventListener("click", async () => {
  if (selectedPlaceId) {
    // User selected from autocomplete, proceed
    submitForm();
    return;
  }

  // User typed address without selecting, validate with Geocode
  const query = document.getElementById("address-input").value;

  if (!query) {
    alert("Please enter an address");
    return;
  }

  try {
    const command = new amazonLocationClient.places.GeocodeCommand({
      QueryText: query,
      MaxResults: 1,
    });

    const response = await client.send(command);

    if (response.ResultItems.length === 0) {
      alert("Address not found. Please check and try again.");
      return;
    }

    const result = response.ResultItems[0];

    // Confirm with user if address was standardized
    if (result.Address.Label !== query) {
      const confirmed = confirm(`Did you mean: ${result.Address.Label}?`);
      if (!confirmed) return;
    }

    // Populate with geocoded result
    document.getElementById("lat").value = result.Position[1];
    document.getElementById("lon").value = result.Position[0];

    submitForm();
  } catch (error) {
    console.error("Geocode error:", error);
    alert("Failed to validate address");
  }
});

function submitForm() {
  // Proceed with form submission
  console.log("Submitting form with validated address");
}
```

## Error Handling

### Autocomplete Errors

- **Rate limiting**: Implement debouncing (300ms delay) before calling API
- **Network failures**: Show cached suggestions or friendly message
- **No results**: Allow user to continue typing or submit for geocoding

### GetPlace Errors

- **Invalid PlaceId**: Should not happen if using autocomplete results, but handle gracefully
- **Network timeout**: Retry once, then show error message

### Geocode Errors

- **No results**: Prompt user to check spelling or use autocomplete
- **Multiple results**: Present user with options to select correct one
- **Ambiguous address**: Ask for more details (e.g., city/state)

## Best Practices

### Performance

- **Debounce autocomplete**: Wait 300ms after user stops typing before API call
- **Cancel previous requests**: Cancel in-flight autocomplete requests when new input arrives
- **Cache results**: Cache autocomplete results for repeated queries

### User Experience

- **Always use Address.Label**: Never display the `Title` field - it may be reversed
- **Show visual feedback**: Loading indicators during API calls
- **Keyboard navigation**: Allow arrow keys and Enter to navigate suggestions
- **Clear affordances**: Make it obvious when address is validated

### Data Handling

- **Store PlaceId**: Keep PlaceId with address for future reference
- **Store coordinates**: Save Position for mapping and distance calculations
- **Handle missing fields**: Not all addresses have all components (e.g., AddressNumber)
- **Respect nested structure**: Access `address.Region.Code`, not `address.RegionCode`

### Accessibility

- **ARIA labels**: Use proper ARIA attributes for autocomplete
- **Keyboard support**: Full keyboard navigation for suggestions
- **Screen reader announcements**: Announce number of suggestions found
