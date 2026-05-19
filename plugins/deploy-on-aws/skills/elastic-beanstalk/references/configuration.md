# Configuration and Customization

## Configuration Hierarchy

Option settings are applied in this order (later overrides earlier):

1. Platform defaults (managed by AWS)
2. Saved configurations (reusable templates)
3. `.ebextensions/*.config` files (in source bundle)
4. Environment properties (set via console/CLI/API)

Platform hooks (`/platform/hooks/prebuild/`, `predeploy/`, `postdeploy/`) run
shell scripts during deployment lifecycle but do not set option settings.
They are the preferred customization mechanism on AL2023 for non-option-setting
tasks. Use `.ebextensions/` for option settings and resource declarations.

See [Configuration options precedence](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/command-options.html#configuration-options-precedence)
for full details.

## Key Patterns

### Run commands on deploy

```yaml
container_commands:
  01_migrate:
    command: "python manage.py migrate --noinput"
    leader_only: true
```

Use `leader_only: true` for commands that should run on only one instance
(database migrations, cache warmup).

### Procfile

Define the process to run. EB uses this instead of platform defaults:

```
web: gunicorn myapp.wsgi --bind 0.0.0.0:8000
```

For worker environments, the Procfile defines the HTTP server that receives
SQS daemon POST requests (not a queue consumer like Celery — EB Workers use
HTTP, not a message broker SDK).

## Environment Properties and Secrets

Non-secret config uses `aws:elasticbeanstalk:application:environment`. For
secrets, use the native secrets integration which injects Secrets Manager
values as environment variables without application-side SDK calls:

```yaml
option_settings:
  aws:elasticbeanstalk:application:environment:
    APP_ENV: production
  aws:elasticbeanstalk:application:environmentsecrets:
    DB_PASSWORD: arn:aws:secretsmanager:us-east-1:123456789:secret:myapp/db
```

Never hardcode secrets in `.ebextensions/` or source code. Provision databases
and secrets as separate resources — not coupled to the EB environment lifecycle.

See [Environment secrets](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuration-envvars.html#configuration-envvars-secrets)
for supported secret sources.

## Deployment Policies

| Policy                        | Use Case                   | Downtime              |
| ----------------------------- | -------------------------- | --------------------- |
| All at once                   | Dev environments           | Yes                   |
| Rolling                       | Production, cost-sensitive | No (partial capacity) |
| Rolling with additional batch | Production, full capacity  | No                    |
| Immutable                     | Production, safest         | No                    |

Default: All at once for dev, Rolling with additional batch for production.

See [Deployment policies and settings](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.rolling-version-deploy.html)
for configuration details.

## Health Check

Always configure a dedicated health check endpoint. Do not use `/` if it
performs database queries or heavy computation.

The agent should verify that the application exposes a health endpoint
(default: `/health`). If no health route exists, scaffold a minimal one that
returns 200 OK. The ALB health check will fail without this, causing deployment
to roll back.

See [Health check setting](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/environments-cfg-alb.html#environments-cfg-alb-health)
for ALB health check configuration.

## Heroku Migration

When migrating from Heroku/Render/Railway, audit for these patterns:

- `DATABASE_URL` → Provision RDS/Aurora separately, pass via environment secrets
- `REDIS_URL` → Provision ElastiCache, pass endpoint via environment properties
- Add-on env vars (e.g., `SENDGRID_API_KEY`) → Store in Secrets Manager
- `PORT` → EB sets this automatically, no change needed
- `Procfile` → Works as-is (same format)
- Explicit AWS credentials → Remove; use IAM instance profile instead
