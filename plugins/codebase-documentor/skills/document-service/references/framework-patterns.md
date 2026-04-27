# Framework Patterns

Common framework conventions for extracting architecture and documentation from application code.

## Web Frameworks

### Express.js / Node.js

| Pattern                                   | Where to Find    | What It Reveals                        |
| ----------------------------------------- | ---------------- | -------------------------------------- |
| `app.listen(port)`                        | Entry point file | Server port, startup sequence          |
| `app.use(middleware)`                     | App setup        | Middleware chain (auth, logging, CORS) |
| `router.get/post/put/delete`              | Route files      | API endpoints                          |
| `mongoose.model()` / `sequelize.define()` | Model files      | Data models and relationships          |
| `new SQSClient()` / `new S3Client()`      | Service files    | AWS service dependencies               |

### FastAPI / Python

| Pattern                      | Where to Find  | What It Reveals                    |
| ---------------------------- | -------------- | ---------------------------------- |
| `@app.get()` / `@app.post()` | Router files   | API endpoints with type hints      |
| `class Model(BaseModel)`     | Schema files   | Request/response models (Pydantic) |
| `class Model(Base)`          | Model files    | Database models (SQLAlchemy)       |
| `Depends()`                  | Route handlers | Dependency injection chain         |
| `boto3.client('service')`    | Service files  | AWS service dependencies           |

### Django / Python

| Pattern                                         | Where to Find  | What It Reveals                      |
| ----------------------------------------------- | -------------- | ------------------------------------ |
| `urlpatterns = [path()]`                        | urls.py        | URL routing structure                |
| `class Model(models.Model)`                     | models.py      | Database schema                      |
| `class Serializer(serializers.ModelSerializer)` | serializers.py | API contracts (DRF)                  |
| `DATABASES` in settings                         | settings.py    | Database configuration               |
| `INSTALLED_APPS`                                | settings.py    | Application modules and dependencies |

### Spring Boot / Java

| Pattern                                      | Where to Find         | What It Reveals                 |
| -------------------------------------------- | --------------------- | ------------------------------- |
| `@RestController`                            | Controller classes    | API endpoint groups             |
| `@GetMapping` / `@PostMapping`               | Controller methods    | Individual endpoints            |
| `@Entity`                                    | Entity classes        | JPA data models                 |
| `@Repository`                                | Repository interfaces | Data access patterns            |
| `application.yml` / `application.properties` | Config files          | All configuration including AWS |

### Go

| Pattern                                               | Where to Find        | What It Reveals                      |
| ----------------------------------------------------- | -------------------- | ------------------------------------ |
| `http.HandleFunc()` / `mux.Handle()`                  | Main or router files | HTTP endpoints                       |
| `struct` definitions                                  | Model files          | Data structures                      |
| `sql.Open()` / `gorm.Open()`                          | Database setup       | Database connections                 |
| `config.LoadDefaultConfig()` / `session.NewSession()` | AWS client setup     | AWS service dependencies (v2/v1 SDK) |

### Flask / Python

| Pattern                            | Where to Find    | What It Reveals                     |
| ---------------------------------- | ---------------- | ----------------------------------- |
| `@app.route()` / `@bp.route()`     | App or blueprint | URL routes and HTTP methods         |
| `app.register_blueprint()`         | App setup        | Modular route groups                |
| `class X(db.Model)`                | Model files      | SQLAlchemy models                   |
| `Flask(__name__)` / `create_app()` | Entry point      | App factory pattern, config loading |
| `boto3.client('service')`          | Service files    | AWS service dependencies            |

### Next.js / React

| Pattern                                     | Where to Find             | What It Reveals                             |
| ------------------------------------------- | ------------------------- | ------------------------------------------- |
| `pages/**/*.{ts,tsx,js,jsx}` (pages router) | `pages/`                  | File-based routes (pre-App Router)          |
| `app/**/page.{ts,tsx}` (app router)         | `app/`                    | Route segments (App Router)                 |
| `app/**/route.{ts,js}` / `pages/api/**`     | `app/api/` or `pages/api` | API route handlers                          |
| `getServerSideProps` / `getStaticProps`     | Page files                | Data fetching strategy (SSR/SSG)            |
| `middleware.{ts,js}` at root                | Root                      | Edge middleware                             |
| `next.config.{js,ts,mjs}`                   | Root                      | Build config, redirects, rewrites, env vars |

### Rust

| Pattern                                     | Where to Find      | What It Reveals                       |
| ------------------------------------------- | ------------------ | ------------------------------------- |
| `#[get("/")] / #[post("/")]` (Actix/Rocket) | Handler modules    | HTTP routes                           |
| `Router::new().route(...)` (Axum)           | Router setup       | Axum route definitions                |
| `struct` with `#[derive(Serialize)]`        | Model modules      | Request/response types                |
| `sqlx::query!` / `diesel::table!`           | Repository modules | Database schema and queries           |
| `aws_sdk_<service>::Client`                 | Service modules    | AWS service dependencies (AWS SDK v2) |

### .NET / C&#35;

| Pattern                                   | Where to Find      | What It Reveals                    |
| ----------------------------------------- | ------------------ | ---------------------------------- |
| `[ApiController]` + `[Route("/")]`        | Controller classes | API endpoint groups                |
| `[HttpGet]` / `[HttpPost]`                | Controller methods | Individual endpoints               |
| `DbContext` subclass                      | Data context       | EF Core entities and relationships |
| `Program.cs` / `Startup.cs`               | Entry point        | DI container, middleware pipeline  |
| `appsettings.json` / `appsettings.*.json` | Root               | All configuration including AWS    |
| `AmazonS3Client` / `AmazonDynamoDBClient` | Service classes    | AWS service dependencies           |

### Ruby on Rails

| Pattern                            | Where to Find        | What It Reveals                          |
| ---------------------------------- | -------------------- | ---------------------------------------- |
| `Rails.application.routes.draw`    | `config/routes.rb`   | URL routing (`resources`, `get`, `post`) |
| `class X < ApplicationController`  | `app/controllers/`   | Controller actions                       |
| `class X < ApplicationRecord`      | `app/models/`        | ActiveRecord models                      |
| `db/migrate/*.rb` / `db/schema.rb` | Migration files      | Database schema                          |
| `Aws::S3::Client.new`              | Service or lib files | AWS SDK dependencies (aws-sdk-ruby)      |

### PHP / Laravel

| Pattern                                      | Where to Find                      | What It Reveals      |
| -------------------------------------------- | ---------------------------------- | -------------------- |
| `Route::get()` / `Route::post()`             | `routes/web.php`, `routes/api.php` | URL routes           |
| `class X extends Controller`                 | `app/Http/Controllers/`            | Controller actions   |
| `class X extends Model`                      | `app/Models/`                      | Eloquent models      |
| `database/migrations/*.php`                  | Migration files                    | Database schema      |
| `config/aws.php` / `Aws\\*\\<Service>Client` | Service providers                  | AWS SDK dependencies |

### Elixir / Phoenix

| Pattern                              | Where to Find               | What It Reveals                        |
| ------------------------------------ | --------------------------- | -------------------------------------- |
| `scope "/" do ... end`               | `lib/*_web/router.ex`       | Phoenix route scopes                   |
| `get "/"` / `post "/"` / `resources` | Router                      | URL routes                             |
| `defmodule X.Controller`             | `lib/*_web/controllers/`    | Controller actions                     |
| `schema "table" do ... end` (Ecto)   | `lib/*/schemas/` or similar | Ecto schemas / DB models               |
| `priv/repo/migrations/*.exs`         | Migrations                  | Database schema                        |
| `mix.exs` `deps` list                | Root                        | Hex dependencies, including `ex_aws_*` |
| `application/0` in `lib/*.ex`        | OTP application             | Supervision tree, startup children     |

### Serverless Framework

| Pattern                | Where to Find    | What It Reveals                          |
| ---------------------- | ---------------- | ---------------------------------------- |
| `functions:` block     | `serverless.yml` | Lambda functions, handlers, events       |
| `events:` per function | `serverless.yml` | Event sources (http, sqs, sns, schedule) |
| `resources:` block     | `serverless.yml` | Extra CloudFormation resources           |
| `provider:` block      | `serverless.yml` | Runtime, region, IAM, environment vars   |
| `plugins:` block       | `serverless.yml` | Build pipeline (esbuild, webpack, etc.)  |

## AWS CDK Patterns

| Pattern                                | What It Creates      | Key Properties                       |
| -------------------------------------- | -------------------- | ------------------------------------ |
| `new lambda.Function()`                | Lambda function      | handler, runtime, environment        |
| `new sqs.Queue()`                      | SQS queue            | visibilityTimeout, deadLetterQueue   |
| `new dynamodb.Table()`                 | DynamoDB table       | partitionKey, sortKey, billingMode   |
| `new apigateway.RestApi()`             | API Gateway          | endpoints, authorizers               |
| `new ecs.FargateService()`             | Fargate service      | taskDefinition, desiredCount         |
| `new s3.Bucket()`                      | S3 bucket            | encryption, versioned, removalPolicy |
| `addEventSource(new SqsEventSource())` | Event source mapping | Lambda-to-SQS binding                |

## Configuration Patterns

| Source                            | What to Extract                          |
| --------------------------------- | ---------------------------------------- |
| `.env.example` / `.env.template`  | Environment variable names and purposes  |
| `process.env.VAR_NAME` (Node.js)  | Runtime configuration dependencies       |
| `os.environ['VAR_NAME']` (Python) | Runtime configuration dependencies       |
| `ssm.GetParameter()`              | AWS Systems Manager parameter references |
| `secretsmanager.GetSecretValue()` | AWS Secrets Manager references           |

## Monorepo Patterns

| Pattern                         | Where to Find       | What It Reveals                    |
| ------------------------------- | ------------------- | ---------------------------------- |
| `pnpm-workspace.yaml`           | Root                | Workspace roots and package layout |
| `packages/*/package.json`       | Package manifests   | Internal dependencies, shared libs |
| `extensions/*/package.json`     | Extension manifests | Plugin/extension ecosystem         |
| `.projenrc.ts` / `.projenrc.js` | Root                | Full project config, deps, tasks   |
| `turbo.json` / `nx.json`        | Root                | Build pipeline, task dependencies  |
| `lerna.json`                    | Root                | Package management strategy        |

## CLI Patterns

| Pattern                                    | Where to Find          | What It Reveals                     |
| ------------------------------------------ | ---------------------- | ----------------------------------- |
| `commander` / `yargs` / `clipanion` import | Entry point / CLI file | CLI framework and command structure |
| `.command()` / `.addCommand()`             | CLI setup              | Available commands and subcommands  |
| `.option()` / `.argument()`                | Command definitions    | CLI arguments and flags             |
| `bin` field in `package.json`              | Package manifest       | CLI entry point binary name         |

## Test Patterns

| Pattern                | What It Reveals                              |
| ---------------------- | -------------------------------------------- |
| Integration test setup | External service dependencies, test fixtures |
| Mock definitions       | Expected interfaces of external services     |
| Test data factories    | Domain object shapes and relationships       |
| E2E test scenarios     | Key user workflows and business processes    |
