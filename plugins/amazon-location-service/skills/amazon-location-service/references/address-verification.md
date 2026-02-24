# Address Verification

> **Audience Note**: Keywords MUST, SHOULD, MAY in this document indicate requirements for agent recommendations to users, following RFC 2119.

Validate and standardize addresses before persisting to databases or taking actions.

**Distinction from Address Input**: The address-input reference covers the UI/UX of collecting addresses from users (autocomplete, type-ahead). This reference covers validation and standardization of addresses AFTER collection, before storage or processing.

## Table of Contents

- [Overview](#overview)
- [When to Verify Addresses](#when-to-verify-addresses)
- [Basic Verification](#basic-verification)
- [Handling Verification Results](#handling-verification-results)
- [Complete Validation Flows](#complete-validation-flows)
- [Storage Considerations and Pricing](#storage-considerations-and-pricing)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

Address verification ensures data quality by:

1. **Validating** - Confirming address exists in postal database
2. **Standardizing** - Converting to canonical format (proper casing, abbreviations)
3. **Enriching** - Adding coordinates, postal codes, country codes
4. **Cleaning** - Fixing typos, removing ambiguity

Use `geo-places:Geocode` for address verification AFTER user has completed input.

## When to Verify Addresses

Verify addresses in these scenarios:

- **Before database insertion**: Ensure only valid, standardized addresses are stored
- **Before shipping/delivery**: Verify delivery address is valid and complete
- **Before API calls**: Validate address before passing to routing or distance APIs
- **Batch processing**: Clean existing address databases
- **Form submission**: Final validation before accepting user submission
- **Integration imports**: Validate addresses from external systems

Do NOT verify on every keystroke (use Autocomplete for that - see address-input reference).

## Basic Verification

### Single Address Verification

```javascript
const authHelper = amazonLocationClient.withAPIKey(API_KEY, REGION);
const client = new amazonLocationClient.GeoPlacesClient(authHelper.getClientConfig());

async function verifyAddress(addressString) {
  try {
    const command = new amazonLocationClient.places.GeocodeCommand({
      QueryText: addressString,
      MaxResults: 5  // Get multiple matches to detect ambiguity
    });

    const response = await client.send(command);

    if (response.ResultItems.length === 0) {
      return {
        valid: false,
        reason: 'ADDRESS_NOT_FOUND',
        message: 'Address not found in postal database'
      };
    }

    const topResult = response.ResultItems[0];

    // Check for ambiguous input (multiple strong matches)
    const isAmbiguous = response.ResultItems.length > 1 &&
      response.ResultItems[1].Address.Label.toLowerCase() !== topResult.Address.Label.toLowerCase();

    return {
      valid: true,
      ambiguous: isAmbiguous,
      standardized: topResult.Address,
      coordinates: {
        lat: topResult.Position[1],
        lon: topResult.Position[0]
      },
      originalInput: addressString,
      allMatches: response.ResultItems
    };

  } catch (error) {
    console.error('Verification error:', error);
    return {
      valid: false,
      reason: 'VERIFICATION_ERROR',
      message: error.message
    };
  }
}

// Usage
const result = await verifyAddress("500 E 4th St, Austin, TX 78701");

if (result.valid) {
  console.log('Valid address:', result.standardized.Label);
  console.log('Coordinates:', result.coordinates);
} else {
  console.log('Invalid:', result.message);
}
```

### Structured Address Verification

```javascript
// Verify address from form fields
async function verifyStructuredAddress(fields) {
  // Build address string from components
  const parts = [
    fields.street,
    fields.city,
    fields.state,
    fields.postalCode,
    fields.country
  ].filter(Boolean);

  const addressString = parts.join(', ');

  return await verifyAddress(addressString);
}

// Usage
const formData = {
  street: "500 E 4th St",
  city: "Austin",
  state: "CA",
  postalCode: "94043",
  country: "USA"
};

const verification = await verifyStructuredAddress(formData);
```

## Handling Verification Results

### Perfect Match

```javascript
if (result.valid && !result.ambiguous) {
  // Address is valid and unambiguous
  // Store standardized version
  await saveAddress({
    original: result.originalInput,
    standardized: result.standardized.Label,
    street: result.standardized.Street,
    addressNumber: result.standardized.AddressNumber,
    locality: result.standardized.Locality,
    region: result.standardized.Region?.Code,
    postalCode: result.standardized.PostalCode,
    country: result.standardized.Country?.Code2,
    latitude: result.coordinates.lat,
    longitude: result.coordinates.lon,
    verified: true,
    verifiedAt: new Date().toISOString()
  });
}
```

### Address Not Found

```javascript
if (!result.valid && result.reason === 'ADDRESS_NOT_FOUND') {
  // Show error to user
  showError(
    'We could not verify this address. Please check for typos and try again.'
  );

  // Offer suggestions
  if (result.originalInput.length > 10) {
    // Suggest using autocomplete
    showSuggestion(
      'Try using the address autocomplete field for better results.'
    );
  }

  // Still allow submission if user insists
  showOption(
    'Submit anyway (address will be marked as unverified)',
    async () => {
      await saveAddress({
        original: result.originalInput,
        verified: false,
        verifiedAt: null
      });
    }
  );
}
```

### Ambiguous Address

```javascript
if (result.valid && result.ambiguous) {
  // Present user with options
  showAmbiguityDialog(
    'We found multiple matches for this address. Please select the correct one:',
    result.allMatches.map(match => ({
      label: match.Address.Label,
      details: {
        locality: match.Address.Locality,
        region: match.Address.Region?.Name,
        postalCode: match.Address.PostalCode
      },
      onSelect: async () => {
        await saveAddress({
          standardized: match.Address.Label,
          latitude: match.Position[1],
          longitude: match.Position[0],
          verified: true
        });
      }
    }))
  );
}
```

### Standardization Differences

```javascript
// Check if geocoded address differs from input
if (result.valid) {
  const inputNormalized = result.originalInput.toLowerCase().trim();
  const standardizedNormalized = result.standardized.Label.toLowerCase().trim();

  if (inputNormalized !== standardizedNormalized) {
    // Show user the standardized version
    const confirmed = await confirmDialog(
      'We found a slight difference in the address:',
      {
        original: result.originalInput,
        standardized: result.standardized.Label,
        question: 'Use the standardized version?'
      }
    );

    if (confirmed) {
      // Use standardized
      await saveAddress({
        standardized: result.standardized.Label,
        ...result.coordinates,
        verified: true
      });
    } else {
      // Keep original but mark as manually confirmed
      await saveAddress({
        original: result.originalInput,
        ...result.coordinates,
        verified: true,
        manuallyConfirmed: true
      });
    }
  }
}
```

## Complete Validation Flows

### Pre-Submission Validation

```javascript
// Validate form before submission
async function validateAddressForm(formElement) {
  const submitButton = formElement.querySelector('button[type="submit"]');
  const statusDiv = document.getElementById('validation-status');

  formElement.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Show loading state
    submitButton.disabled = true;
    statusDiv.innerHTML = 'Verifying address...';

    // Get address from form
    const addressInput = formElement.querySelector('#address').value;

    try {
      const result = await verifyAddress(addressInput);

      if (!result.valid) {
        statusDiv.innerHTML = `
          <div class="error">
            <strong>Address verification failed:</strong>
            <p>${result.message}</p>
            <button onclick="submitAnyway()">Submit Anyway</button>
            <button onclick="editAddress()">Edit Address</button>
          </div>
        `;
        submitButton.disabled = false;
        return;
      }

      if (result.ambiguous) {
        statusDiv.innerHTML = '<div class="warning">Multiple matches found. Please select:</div>';
        showAmbiguityOptions(result.allMatches);
        submitButton.disabled = false;
        return;
      }

      // Update form with standardized address
      if (result.standardized.Label !== addressInput) {
        const useStandardized = confirm(
          `Use standardized address?\n\nYou entered:\n${addressInput}\n\nStandardized:\n${result.standardized.Label}`
        );

        if (useStandardized) {
          formElement.querySelector('#address').value = result.standardized.Label;
        }
      }

      // Store coordinates in hidden fields
      formElement.querySelector('#latitude').value = result.coordinates.lat;
      formElement.querySelector('#longitude').value = result.coordinates.lon;

      // Mark as verified
      formElement.querySelector('#verified').value = 'true';

      // Submit form
      statusDiv.innerHTML = '<div class="success">Address verified!</div>';
      formElement.submit();

    } catch (error) {
      statusDiv.innerHTML = `
        <div class="error">
          Verification error: ${error.message}
        </div>
      `;
      submitButton.disabled = false;
    }
  });
}
```

### Batch Verification

```javascript
// Verify multiple addresses (e.g., cleaning existing database)
async function batchVerifyAddresses(addresses) {
  const results = [];

  for (const address of addresses) {
    try {
      const result = await verifyAddress(address.text);

      results.push({
        id: address.id,
        originalAddress: address.text,
        verified: result.valid,
        standardized: result.valid ? result.standardized.Label : null,
        coordinates: result.valid ? result.coordinates : null,
        ambiguous: result.ambiguous,
        error: result.valid ? null : result.message
      });

      // Rate limiting - wait between requests
      await new Promise(resolve => setTimeout(resolve, 100));

    } catch (error) {
      results.push({
        id: address.id,
        originalAddress: address.text,
        verified: false,
        error: error.message
      });
    }

    // Progress indicator
    console.log(`Verified ${results.length}/${addresses.length}`);
  }

  return results;
}

// Generate report
function generateVerificationReport(results) {
  const stats = {
    total: results.length,
    verified: results.filter(r => r.verified && !r.ambiguous).length,
    ambiguous: results.filter(r => r.ambiguous).length,
    invalid: results.filter(r => !r.verified).length,
    errors: results.filter(r => r.error).length
  };

  console.log('Verification Report:', stats);

  return {
    stats,
    needsReview: results.filter(r => !r.verified || r.ambiguous)
  };
}

// Usage
const addressesToVerify = [
  { id: 1, text: "500 E 4th St, Austin, TX 78701" },
  { id: 2, text: "301 Congress Ave, Austin, TX 78701" },
  // ... more addresses
];

const verificationResults = await batchVerifyAddresses(addressesToVerify);
const report = generateVerificationReport(verificationResults);
```

## Storage Considerations and Pricing

**IMPORTANT**: How you store Places API results affects pricing. Review the [Places API Stored Pricing documentation](https://docs.aws.amazon.com/location/latest/developerguide/places-pricing.html#stored-pricing) before implementing storage.

### Pricing Tiers Based on Storage

Amazon Location Places API has different pricing based on the `IntendedUse` parameter:

**Stored Pricing** (`IntendedUse: "Storage"`):

- ✅ Can store results indefinitely
- ✅ Supports all features (Label, Core, Advanced)
- ✅ Price cap - maximum cost per API call
- 💰 Higher per-request cost
- **Use when**: Building applications that cache results long-term or perform analysis on historical data

**Other Pricing Tiers**:

- ⚠️ Label & Core: Results cannot be stored permanently
- ⚠️ Advanced: Results can be cached temporarily but not stored indefinitely
- 💰 Lower per-request cost
- **Use when**: Real-time lookups without long-term storage needs

### Setting Stored Pricing

```javascript
// To enable stored pricing (allows indefinite storage)
const command = new amazonLocationClient.places.GeocodeCommand({
  QueryText: addressString,
  IntendedUse: "Storage",  // Required for long-term storage
  MaxResults: 1
});
```

### Storage Decision Guide

Ask yourself:

1. **Do you need to store results indefinitely?**
   - YES → Use `IntendedUse: "Storage"` and pay stored pricing
   - NO → Use default pricing, don't store permanently

2. **Will you reuse results to reduce API calls?**
   - YES → Consider stored pricing for cost-effectiveness over time
   - NO → Use real-time lookups with default pricing

3. **Are you building analytics on historical place data?**
   - YES → Use `IntendedUse: "Storage"`
   - NO → Use default pricing

## Error Handling

### Validation Error Types

```javascript
async function verifyAddressWithDetailedErrors(addressString) {
  try {
    const result = await verifyAddress(addressString);

    if (!result.valid) {
      // Classify error
      if (addressString.length < 10) {
        return {
          valid: false,
          errorCode: 'TOO_SHORT',
          message: 'Address is too short. Please provide a complete address.',
          suggestion: 'Include street, city, and state/postal code.'
        };
      }

      if (!/\d/.test(addressString)) {
        return {
          valid: false,
          errorCode: 'MISSING_NUMBER',
          message: 'Address appears to be missing a street number.',
          suggestion: 'Add the building or house number.'
        };
      }

      if (!/[A-Z]{2}/.test(addressString.toUpperCase())) {
        return {
          valid: false,
          errorCode: 'MISSING_STATE',
          message: 'Please include the state or province.',
          suggestion: 'Add the 2-letter state code (e.g., CA, NY).'
        };
      }

      return {
        valid: false,
        errorCode: 'NOT_FOUND',
        message: 'Address not found in postal database.',
        suggestion: 'Check for typos or try entering in a different format.'
      };
    }

    return result;

  } catch (error) {
    return {
      valid: false,
      errorCode: 'VERIFICATION_FAILED',
      message: 'Unable to verify address due to technical error.',
      technicalError: error.message
    };
  }
}
```

## Best Practices

### When to Verify

- **Always verify before storage**: Prevent bad data from entering database
- **Verify before critical actions**: Shipping, delivery, routing
- **Don't verify on every keystroke**: Use autocomplete during input, geocode at submission
- **Batch verification**: For data imports, verify in batches with rate limiting

### Data Quality

- **Understand pricing implications**: Review stored pricing before implementing long-term storage
- **Use IntendedUse parameter**: Set `IntendedUse: "Storage"` if storing results indefinitely
- **Consider caching vs storage**: Temporary session caching doesn't require stored pricing
- **Handle missing components**: Not all addresses have all fields (street number, etc.)

### User Experience

- **Show what changed**: When standardizing, show user the difference
- **Allow manual override**: Let users keep their version if they insist
- **Handle ambiguity gracefully**: Present options, don't guess
- **Provide helpful errors**: Explain WHY address is invalid and how to fix

### Performance

- **Cache results**: Cache verification results temporarily within your session
- **Rate limit batch jobs**: Wait 100ms between batch verifications
- **Verify once per session**: Don't re-verify address user already confirmed
- **Use autocomplete first**: Preferred over post-hoc verification
