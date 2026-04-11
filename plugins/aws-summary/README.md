# AWS Summary Plugin

Generate business-ready summaries of AWS announcements, blogs, and press releases optimized for Slack and email.

## Overview

This plugin fetches the latest AWS announcements from multiple official sources and formats them into concise, business-focused summaries with category grouping, Unicode bold formatting, and emoji icons.

## Skills

- **aws-summary** - Generate summaries of AWS announcements, blogs, and press releases with time range and category filtering

## Data Sources

- AWS What's New feed
- AWS News Blog
- AWS Press Releases
- 8 Category-specific AWS blogs (ML, Compute, Containers, Databases, Storage, Networking, Security, Management)

## Installation

### From Marketplace

```bash
/plugin marketplace add awslabs/agent-plugins
/plugin install aws-summary@agent-plugins-for-aws
```

### Local Development

```bash
claude --plugin-dir ./plugins/aws-summary
```

## Usage

### Natural Language Examples

```
"Show me AWS updates"
"What's new in AWS last 2 weeks?"
"AWS AI/ML announcements from last 30 days"
"Recent compute and container launches"
"AWS security updates last week"
```

### Supported Parameters

- **Time range**: 7 days (default), 14 days, 30 days, or any custom number
- **Categories**: AI/ML, Compute, Containers, Databases, Storage, Networking, Security, DevOps

### Category Filtering

```
# Single category
"ai/ml updates"
"compute announcements"

# Multiple categories
"ai and compute updates"
"security, networking, and databases from last 2 weeks"
```

## Output Format

Generates `aws-summary-YYYY-MM-DD-HHMMSS.md` with:

- **Unicode bold formatting** - Works when pasted into Slack
- **Emoji icons** - 📢 announcements, 📝 blogs, 🤖 AI/ML, 💻 compute, 📦 containers, etc.
- **Plain text URLs** - Auto-convert to clickable links in Slack
- **Category grouping** - Dynamically organized by service area
- **Business-focused** - Emphasizes "what" and "why it matters" over technical details

## Examples

### All Categories, Last 7 Days

```
"aws summary"
```

### Specific Timeframe

```
"aws updates last 14 days"
"aws summary 30 days"
```

### Category-Specific

```
"latest ai/ml announcements"
"compute and containers updates"
"security announcements last 2 weeks"
```

## Requirements

- WebFetch capability (for retrieving RSS feeds and web content)

## License

MIT
