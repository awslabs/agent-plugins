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
