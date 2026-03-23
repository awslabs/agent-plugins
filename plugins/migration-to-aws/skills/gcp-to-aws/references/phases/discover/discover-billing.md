# Discover Phase: Billing Discovery (v1.2+)

**Status**: Not yet implemented (v1.2 feature).

## Overview

This discoverer will import GCP billing data from CSV/JSON exports to identify active services and cost signals.

## Expected Behavior (v1.2+)

- Read GCP billing CSV or JSON export files
- Extract service SKUs, monthly cost, consumption patterns
- Output: `billing_resources.json` with flat list of detected services

## Expected Output Schema (v1.2+)

```json
{
  "billing_resources": [
    {
      "service": "Cloud Run",
      "monthly_cost_usd": 150.50,
      "evidence": "billing export analysis",
      "confidence": 0.95
    }
  ]
}
```

## Integration with Unify Phase

**Note**: `unify-resources.md` does not exist yet — it is a planned v1.1+ file that will check for `billing_resources.json` and merge service evidence into the final inventory produced by `discover-iac.md`.

**Current Action**: Skip in v1.0. `discover.md` will not call this discoverer until v1.2+ when both this file and `unify-resources.md` are implemented.
