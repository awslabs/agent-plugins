# Supported Platforms

These rules apply after Elastic Beanstalk has been selected as the deployment
target by the deploy skill.

Detect the application's language and framework, then map to an EB platform branch.

## Platform Detection

| Signal in Codebase | EB Platform | Notes |
| --- | --- | --- |
| `requirements.txt`, `Pipfile`, `pyproject.toml` | Python on AL2023 | Django, Flask, FastAPI |
| `package.json` (backend Node.js) | Node.js on AL2023 | Express, NestJS, Fastify, Hono |
| `pom.xml`, `build.gradle`, `.jar`/`.war` | Corretto on AL2023 | Spring Boot, Quarkus |
| `Gemfile`, `config.ru` | Ruby on AL2023 | Rails, Sinatra |
| `go.mod` | Go on AL2023 | Any Go HTTP server |
| `*.csproj`, `*.sln` (ASP.NET Core) | .NET on AL2023 | ASP.NET Core on Linux |
| `*.csproj`, `*.sln` (.NET Framework) | .NET on Windows Server | IIS, .NET Framework 4.x |
| `composer.json` | PHP on AL2023 | Laravel, Symfony |
| `Dockerfile` | Docker on AL2023 | Any containerized app |

## Platform Selection Rules

1. If `Dockerfile` exists AND a language runtime is also detected, prefer the
   language platform unless the Dockerfile adds system dependencies not available
   in the managed platform.
2. If multiple languages detected, prefer Docker platform.
3. Always use Amazon Linux 2023 unless the app requires Windows (.NET Framework,
   IIS dependencies).
4. For Java apps: if `.war` file, deploy to Tomcat platform. If `.jar` with
   embedded server (Spring Boot), use Corretto platform.
5. Always use the latest supported runtime version unless the application
   specifies a version constraint (e.g., `engines` in `package.json`,
   `<TargetFramework>` in `.csproj`).

## Supported Deployment Artifacts

| Platform | Accepted Input |
| --- | --- |
| Language platforms | Source bundle (zip of source code) |
| Docker | Source bundle containing Dockerfile |
| Docker (pre-built) | Dockerfile with `FROM` referencing ECR/registry image |

## Worker Platform Considerations

Worker environments use the same platforms as web server environments. The
difference is the SQS daemon that delivers messages to the application over HTTP
on `localhost`. The application must expose an HTTP endpoint (default: `POST /`)
that processes each message.
