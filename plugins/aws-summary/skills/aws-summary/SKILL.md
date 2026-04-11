---
name: aws-summary
description: >
  Generate business-ready summaries of AWS announcements, blogs, and press releases.
  Triggers on: "aws summary", "aws updates", "latest AWS news", "what's new in AWS",
  "AWS announcements", "recent AWS launches". Supports time ranges (7-30 days) and
  category filtering (AI/ML, Compute, Containers, Databases, Storage, Networking,
  Security, DevOps). Output formatted for Slack/email with Unicode bold and emojis.
license: MIT
metadata:
  tags: aws, announcements, blogs, news, updates, summaries, whats-new
---

# AWS Summary Generator

Generate summaries of AWS announcements, blogs, and press releases from a specified time period (default: 7 days).

## Parameters

- **days**: Number of days to look back (default: 7)
- **category**: Optional category filter (single: "ai/ml" or multiple: "ai/ml, compute" or "ai and security")

## Usage Examples

- Default (all categories, last 7 days): natural language request like "show me AWS updates"
- Specific timeframe: "aws updates last 14 days" or "aws summary 30 days"
- Category filter: "ai/ml updates" or "compute and containers announcements"
- Combined: "last 2 weeks ai and security updates"

## Workflow

### Step 1: Parse Request

Extract parameters from user input:

- Days: Look for numbers followed by "days", "weeks" (convert weeks to days)
- Category: Extract category keywords (ai, ml, compute, containers, databases, storage, networking, security, devops)
- If not specified, use defaults (days=7, category=all)

### Step 2: Calculate Cutoff Date

- REQUIRED: Calculate cutoff date = today's date - days parameter
- Example: If today is April 11, 2026 and days=7, cutoff is April 4, 2026

### Step 3: Fetch Content

- REQUIRED: Use WebFetch tool to retrieve content from ALL sources (see references/sources.md)
- Fetch in parallel when possible for performance
- Filter results to include only items published after cutoff date

### Step 4: Filter & Categorize

- Apply announcement filtering (see references/sources.md for rules)
- If category parameter provided, apply category filter (see references/format.md for normalization)
- Intelligently categorize all announcements into relevant groups
- CRITICAL: If specific categories requested, ONLY include those categories in output

### Step 5: Format Output

- Structure content per references/format.md
- Apply style guidelines from references/style.md
- Group by category with appropriate emojis
- Include only categories with announcements

### Step 6: Save & Report

- REQUIRED: Save output to `aws-summary-YYYY-MM-DD-HHMMSS.md` in current working directory
- Inform user of file location
- DO NOT include footer or attribution

## Error Handling

### WebFetch Failure

- If source unavailable: Log warning, continue with available sources
- If ALL sources fail: Report error to user: "Unable to fetch AWS announcements. Check network connection."
- DO NOT proceed with empty results

### No Results Found

- If zero announcements match filters: Inform user: "No announcements found for [timeframe] [categories]. Try expanding date range or removing category filter."
- Suggest adjustments: wider date range or different categories

### Invalid Category

- If unrecognized category provided: Show warning with valid category list
- Proceed with closest match or ask for clarification

## Reference Files

- **references/sources.md** - Complete list of data sources and filtering rules
- **references/format.md** - Output structure and category normalization
- **references/style.md** - Writing style and formatting guidelines
