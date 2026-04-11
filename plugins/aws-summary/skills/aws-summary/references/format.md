# Output Format

## Category Filtering (CRITICAL)

When `category` parameter is provided:

- ONLY include announcements from the specified category/categories
- Single category example: "ai/ml" → only AI/ML announcements
- Multiple categories example: "ai/ml, compute" or "ai and compute" → only AI/ML and Compute
- DO NOT include announcements from other categories when specific categories are requested
- If no category is specified, include all categories

## Category Normalization

Recognize common variations:

- **AI/ML**: "ai", "ml", "ai/ml", "machine learning", "artificial intelligence", "generative ai", "genai"
- **Compute**: "compute", "ec2", "lambda", "serverless"
- **Containers**: "containers", "ecs", "eks", "kubernetes", "docker"
- **Databases**: "database", "databases", "db", "rds", "dynamodb"
- **Storage**: "storage", "s3"
- **Networking**: "networking", "network", "vpc", "cloudfront"
- **Security**: "security", "iam", "cognito"
- **DevOps**: "devops", "cicd", "ci/cd", "management", "governance", "observability", "monitoring"

## Structure

1. **Dynamically group by category**: Analyze all announcements and intelligently group them (AI/ML, Compute, Containers, Databases, Storage, Networking, Security, DevOps, Analytics, etc.)
2. **Category sections**: Use appropriate emoji for each category (e.g., 🤖 AI/ML, 💻 Compute, 📦 Containers, 💾 Databases, 🔐 Security)
3. **For each item include**:
   - Clear title and business-focused description
   - Full URL as plain text (NOT markdown links - Slack auto-converts)
   - Use 📝 for blog posts, 📢 for "What's New" announcements
4. **Keep descriptions concise** - focus on business impact, not technical details
5. **Only show categories with announcements** - omit empty categories

## File Output

- Save to: `aws-summary-YYYY-MM-DD-HHMMSS.md` (use current date/time)
- Location: current working directory
- DO NOT include footer or attribution line (e.g., "Generated with...")
