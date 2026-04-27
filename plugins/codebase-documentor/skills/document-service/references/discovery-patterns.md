# Discovery Patterns

Patterns for detecting project type, entry points, frameworks, IaC, API surface, data models, and external dependencies during codebase analysis.

## Project Type Detection

Detect the project type early — it determines which entry points to look for, which frameworks to expect, and which patterns matter most.

| Indicator File(s)                                           | Project Type  | Primary Language      |
| ----------------------------------------------------------- | ------------- | --------------------- |
| `package.json`                                              | Node.js       | JavaScript/TypeScript |
| `requirements.txt`, `pyproject.toml`, `setup.py`, `Pipfile` | Python        | Python                |
| `go.mod`                                                    | Go            | Go                    |
| `Cargo.toml`                                                | Rust          | Rust                  |
| `pom.xml`, `build.gradle`, `build.gradle.kts`               | Java/Kotlin   | Java/Kotlin           |
| `*.csproj`, `*.sln`                                         | .NET          | C#                    |
| `Gemfile`                                                   | Ruby          | Ruby                  |
| `mix.exs`                                                   | Elixir        | Elixir                |
| `composer.json`                                             | PHP           | PHP                   |
| `cdk.json` (with above)                                     | AWS CDK       | (see above)           |
| `serverless.yml`                                            | Serverless    | (see above)           |
| `.projenrc.ts`, `.projenrc.js`                              | Projen        | (see above)           |
| `pnpm-workspace.yaml`                                       | pnpm monorepo | (see above)           |
| `*.tf`                                                      | Terraform     | HCL                   |

When multiple indicators are present (e.g., `package.json` + `requirements.txt`), the project is **polyglot** — note all detected types and analyze each stack's entry points.

### Entry Points by Project Type

| Project Type | Entry Point Files                                          |
| ------------ | ---------------------------------------------------------- |
| Node.js      | `index.ts`, `index.js`, `app.ts`, `server.ts`, `main.ts`   |
| Python       | `main.py`, `app.py`, `manage.py`, `__main__.py`, `wsgi.py` |
| Go           | `main.go`, `cmd/*/main.go`                                 |
| Rust         | `src/main.rs`, `src/lib.rs`                                |
| Java/Kotlin  | `*Application.java`, `src/main/java/**/Main.java`          |
| .NET         | `Program.cs`, `Startup.cs`                                 |
| Ruby         | `config.ru`, `app.rb`, `bin/rails`                         |
| PHP          | `index.php`, `public/index.php`, `artisan`                 |
| Elixir       | `mix.exs`, `lib/<app>/application.ex`, `lib/<app>.ex`      |
| CDK          | `bin/*.ts`, `bin/*.py`, `app.py`                           |

## General Discovery Order

After detecting the project type and entry points, analyze files in this order for maximum information yield:

1. Package manifests (dependencies reveal the technology stack)
2. IaC files (infrastructure reveals the architecture)
3. Entry points (reveal the application structure)
4. Route/handler definitions (reveal API surface)
5. Data models and schemas (reveal domain objects)
6. Tests (reveal expected behavior and edge cases)
7. CI/CD configs (reveal deployment and build process)
8. README and docs (reveal intent, even if stale)

## Framework Detection

| Indicator                         | Framework            | Key Files                                |
| --------------------------------- | -------------------- | ---------------------------------------- |
| `package.json` with `express`     | Express.js           | `app.js`, `routes/`, `middleware/`       |
| `package.json` with `next`        | Next.js              | `pages/`, `app/`, `next.config.*`        |
| `package.json` with `react`       | React SPA            | `src/App.*`, `src/components/`           |
| `requirements.txt` with `django`  | Django               | `manage.py`, `settings.py`, `urls.py`    |
| `requirements.txt` with `fastapi` | FastAPI              | `main.py`, `routers/`, `models/`         |
| `requirements.txt` with `flask`   | Flask                | `app.py`, `routes/`, `templates/`        |
| `go.mod`                          | Go                   | `main.go`, `cmd/`, `internal/`           |
| `Cargo.toml`                      | Rust                 | `src/main.rs`, `src/lib.rs`              |
| `pom.xml` or `build.gradle`       | Java/Spring          | `src/main/java/`, `application.yml`      |
| `cdk.json`                        | AWS CDK              | `lib/*-stack.ts`, `bin/*.ts`             |
| `.projenrc.ts`                    | Projen               | `.projenrc.ts` (full project config)     |
| `pnpm-workspace.yaml`             | pnpm monorepo        | `packages/*/`, `apps/*/`, `extensions/*` |
| `serverless.yml`                  | Serverless Framework | `handler.*`, `functions/`                |

## IaC Detection

| File/Pattern                       | IaC Type             | Key Information                |
| ---------------------------------- | -------------------- | ------------------------------ |
| `cdk.json` + `lib/*-stack.ts`      | CDK TypeScript       | Constructs, resources, props   |
| `cdk.json` + `lib/*_stack.py`      | CDK Python           | Constructs, resources, props   |
| `template.yaml` or `template.json` | CloudFormation       | Resources, outputs, parameters |
| `*.tf` files                       | Terraform            | Resources, modules, variables  |
| `serverless.yml`                   | Serverless Framework | Functions, events, resources   |
| `sam-template.yaml`                | AWS SAM              | Functions, APIs, tables        |

## API Surface Detection

### REST APIs

Look for route definitions:

- Express: `app.get()`, `router.post()`, `app.use()`
- FastAPI: `@app.get()`, `@router.post()`
- Django: `urlpatterns`, `path()`, `re_path()`
- Spring: `@GetMapping`, `@PostMapping`, `@RequestMapping`
- Go: `http.HandleFunc()`, `mux.Handle()`, `gin.GET()`

### GraphQL

Look for schema definitions:

- `schema.graphql`, `*.graphql` files
- `typeDefs` in code
- `@Query`, `@Mutation` decorators

### Event-Driven

Look for event handlers:

- SQS: `SqsEvent`, `sqs.receiveMessage`, queue URL references
- SNS: `SnsEvent`, topic ARN references
- EventBridge: rule definitions, event patterns
- Kafka: consumer group configs, topic references

## Data Model Detection

| Pattern                                                      | What to Extract                            |
| ------------------------------------------------------------ | ------------------------------------------ |
| ORM models (Sequelize, SQLAlchemy, TypeORM, Prisma)          | Entity names, fields, types, relationships |
| Migration files                                              | Schema evolution, table structures         |
| Type definitions (TypeScript interfaces, Python dataclasses) | Domain object shapes                       |
| JSON Schema files                                            | Validation rules, field constraints        |
| Protobuf/Avro definitions                                    | Message formats, service contracts         |

## Dependency Detection

Look for external and internal dependencies:

- SDK client instantiation (`new S3Client()`, `boto3.client('s3')`)
- HTTP client calls to external or internal service URLs
- Database connection strings and queue/topic ARN references
- Environment variables referencing endpoints
- Shared library imports and cross-service event publishing/subscribing
