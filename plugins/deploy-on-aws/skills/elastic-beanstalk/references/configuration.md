# Configuration and Customization

## Configuration Hierarchy

Elastic Beanstalk configuration is applied in this order (later overrides earlier
for option settings):

1. Platform defaults (managed by AWS)
2. Saved configurations (reusable templates)
3. `.ebextensions/*.config` files (in source bundle)
4. Platform hooks (`/platform/hooks/prebuild/`, `predeploy/`, `postdeploy/`)
5. Environment properties (set via console/CLI/API)

For option settings, later sources override earlier ones. `.ebextensions` and
platform hooks also support resource declarations and deploy-time commands that
are not expressible as option settings.

Platform hooks are the preferred customization mechanism on AL2023. Use
`.ebextensions/` for option settings and resource declarations; use platform
hooks for shell scripts that run during deployment lifecycle.

## `.ebextensions/` Patterns

Place YAML `.config` files in `.ebextensions/` at the source bundle root.
Common patterns:

### Install system packages

```yaml
packages:
  yum:
    ImageMagick: []
    postgresql-devel: []
```

### Run commands on deploy

```yaml
container_commands:
  01_migrate:
    command: "python manage.py migrate --noinput"
    leader_only: true
```

Use `leader_only: true` for commands that should run on only one instance
(database migrations, cache warmup).

## Procfile

Define the process to run. EB uses this instead of platform defaults:

```
web: gunicorn myapp.wsgi --bind 0.0.0.0:8000
```

For worker environments, the Procfile defines the HTTP server that receives
SQS daemon POST requests (not a queue consumer like Celery — EB Workers use
HTTP, not a message broker SDK).

## Environment Properties and Secrets

Set application configuration as environment variables. Never hardcode secrets
in `.ebextensions/` or source code. Reference secrets via Secrets Manager:

```yaml
option_settings:
  aws:elasticbeanstalk:application:environment:
    DB_SECRET_ARN: arn:aws:secretsmanager:us-east-1:123456789:secret:myapp/db
    APP_ENV: production
```

The application reads the secret value at runtime using the Secrets Manager SDK.
Provision databases and secrets as separate resources (via CDK, Terraform, or
console) — not coupled to the EB environment lifecycle.

## Deployment Policies

| Policy | Use Case | Downtime |
| --- | --- | --- |
| All at once | Dev environments | Yes |
| Rolling | Production, cost-sensitive | No (partial capacity) |
| Rolling with additional batch | Production, full capacity | No |
| Immutable | Production, safest | No |

Default: All at once for dev, Rolling with additional batch for production.

## Health Check Configuration

```yaml
option_settings:
  aws:elasticbeanstalk:environment:process:default:
    HealthCheckPath: /health
    HealthCheckInterval: '15'
    HealthyThresholdCount: '3'
    UnhealthyThresholdCount: '5'
```

Always configure a dedicated health check endpoint. Do not use `/` if it
performs database queries or heavy computation.

The agent should verify that the application exposes a health check endpoint
(default: `/health`). If no health route exists, scaffold a minimal one that
returns 200 OK. The ALB health check will fail without this, causing deployment
to roll back.
