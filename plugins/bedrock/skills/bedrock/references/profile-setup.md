# AWS CLI Profile Setup

How to configure a named AWS CLI profile for use with this plugin.

## Creating a Profile

A named profile keeps your plugin's AWS access separate from other tools. Create one with:

```bash
aws configure --profile my-bedrock-dev
```

You'll be prompted for:

- **AWS Access Key ID** and **Secret Access Key** — from your IAM user or from your organization's credential vending process
- **Default region** — `us-east-1` recommended for broadest Bedrock model availability
- **Output format** — `json` recommended

### If You Use IAM Identity Center (SSO)

```bash
aws configure sso --profile my-bedrock-dev
```

This walks through SSO login configuration. After setup, authenticate with:

```bash
aws sso login --profile my-bedrock-dev
```

### If You Use Role Assumption

If your organization provides a base identity and you assume a role for Bedrock access, configure the profile in `~/.aws/config`:

```
[profile my-bedrock-dev]
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>
source_profile = <BASE_PROFILE>
region = us-east-1
```

Replace `<ACCOUNT_ID>`, `<ROLE_NAME>`, and `<BASE_PROFILE>` with your values. The role should have the Bedrock permissions listed in [iam-permissions.md](iam-permissions.md).

## Verifying the Profile

```bash
# List all configured profiles
aws configure list-profiles

# Verify credentials work and confirm which account you're in
aws sts get-caller-identity --profile my-bedrock-dev
```

Expected output shows the account ID and IAM principal (user or assumed role ARN).

## Multiple Accounts

A common setup for startups:

| Profile           | Purpose                                       | Account           |
| ----------------- | --------------------------------------------- | ----------------- |
| `claude-code`     | Claude Code inference (powers the CLI itself) | Inference account |
| `my-bedrock-dev`  | Application development with Bedrock          | Dev account       |
| `my-bedrock-prod` | Production Bedrock access                     | Prod account      |

Each profile points to a different account. When the plugin asks which profile to use, pick the one matching the account you want to operate in. The plugin passes `--profile` explicitly to every AWS command — it never reads `AWS_PROFILE` from the environment.

## What the Plugin Needs

The profile you select must have IAM permissions for the plugin commands you want to use. See [iam-permissions.md](iam-permissions.md) for the full permissions reference.

At minimum, for basic validation:

- `sts:GetCallerIdentity`
- `bedrock:ListFoundationModels`
- `bedrock:GetFoundationModel`
- `bedrock:Converse`
