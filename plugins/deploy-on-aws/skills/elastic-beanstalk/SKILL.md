---
name: elastic-beanstalk
description: "Deploy to AWS Elastic Beanstalk, in either Beanstalk Standard mode (EC2) or Beanstalk Cluster mode (managed EKS). Triggers on: elastic beanstalk, EB, beanstalk standard, beanstalk cluster, managed EC2 platform, web app with managed patching, worker on EC2, Heroku alternative, don't want to manage servers or container orchestration, migrate from Heroku, managed operational lifecycle, containerised app without operating Kubernetes, several services sharing a managed cluster, managed EKS without kubectl. Covers web and worker applications on EC2, and containerised single- and multi-service applications on managed EKS."
---

# Elastic Beanstalk

Deploy applications to production on AWS with full lifecycle management. Elastic
Beanstalk is an application management service: the user provides application
code or a container image, AWS manages everything underneath (deployment,
scaling, patching, monitoring, health response).

There are two modes, and the choice determines every setting that follows.
**Standard** runs the application on Amazon EC2; **Cluster** runs a container on
a managed Amazon EKS Auto Mode cluster. See [Choose the Mode](#choose-the-mode).

## When to Use

Elastic Beanstalk is the right choice when:

- User explicitly asks for Elastic Beanstalk, EB, or a managed application platform
- User says "don't want to manage servers", "managed patching", or "Heroku-like"
- User is migrating from Heroku, Render, or Railway
- User wants AWS to manage ongoing operational lifecycle (patching, scaling,
  health monitoring, rollback, deployments) after initial setup
- App is a web framework, API, or background worker on a standard runtime and
  the user signals low infrastructure involvement

Elastic Beanstalk is NOT the right choice when:

- User explicitly wants serverless/Lambda — this imposes a different programming
  model (event-driven functions, stateless, cold starts, 15-min max execution)
  rather than just eliminating server management
- User wants fine-grained container orchestration control (use ECS)
- User already has Kubernetes expertise and wants direct K8s access (use EKS)
- App is a static site or SPA (use Amplify Hosting for the frontend; deploy the
  backend API separately if present)
- User already has ECS task definitions or Fargate configuration

## Key Distinction

ECS and EKS are infrastructure management services: the user defines and
operates the deployment infrastructure (task definitions, services, clusters,
scaling policies) and owns ongoing operational decisions. Elastic Beanstalk is
an application management service: the user provides source code or a Docker
image, and AWS provisions and operates the production environment on an ongoing
basis. The result is the same reliability, but with lower ongoing maintenance
cost because operational responsibility stays with the provider.

Both models support IaC (CDK, CloudFormation, Terraform). The distinction is not
about tooling — it is about who manages the lifecycle after deployment.

Lambda/serverless is a different axis entirely. "Don't want to manage servers"
does not mean "wants serverless" — Elastic Beanstalk also eliminates server
management while preserving the standard application programming model
(long-running processes, persistent connections, threads, and — in Standard mode
only — local state; Cluster mode replicas have ephemeral local storage).
Serverless imposes a specific programming model: stateless functions, cold
starts, event-driven invocation, and a 15-minute execution ceiling. Route to
Lambda only when the user explicitly asks for serverless or the workload is
natively event-driven (e.g., S3 triggers, API Gateway request/response with
no session state).

## Choose the Mode

Decide before generating anything. The modes share an API and nothing else: a
Standard mode namespace passed to a Cluster mode environment is rejected, not
ignored.

**Cluster mode has an entry requirement, and it is checked first.** Route to
Cluster only when every service can run as identical, interchangeable replicas
_and_ all durable state — uploads, sessions, caches, working files — already lives
outside the container. Replica local storage is ephemeral and is lost on every
restart, and there is no persistent volume option. An application that fails this
goes to Standard mode, or gets changed first; a multi-service signal does not
override it. See the
[application contract](references/cluster-mode.md#the-application-contract).

Then the signals:

| Signal                                                      | Mode         |
| ----------------------------------------------------------- | ------------ |
| Source on a standard runtime; Windows or .NET Framework     | **Standard** |
| Worker consuming an SQS queue                               | **Standard** |
| Writes uploads, sessions, or working files to local disk    | **Standard** |
| One small application, cost is the priority                 | **Standard** |
| Several services needing private service-to-service traffic | **Cluster**  |
| Kubernetes underneath without operating Kubernetes          | **Cluster**  |
| Managed OpenTelemetry, or faster deploys and scaling        | **Cluster**  |

A container image alone does not settle it, because Standard mode has a Docker
platform too — ask. Prefer Cluster mode when the application is containerised,
multi-service, _and_ meets the contract above, since environments sharing subnets
share one cluster and reach each other privately. Prefer Standard for a single
container where a cluster is not yet justified. Do not propose migrating a working
Standard environment unless asked: there is no in-place conversion, only new
environments and a CNAME swap.

If the mode is Cluster, follow [cluster mode](references/cluster-mode.md) and
stop here. Everything below is Beanstalk Standard.

## Workflow (Standard)

This skill is invoked after the deploy skill selects Elastic Beanstalk as the
deployment target. The deploy skill handles codebase analysis and cost estimation.
This skill handles EB-specific configuration:

1. **Map to platform** - Select the EB platform branch (see [platforms](references/platforms.md))
2. **Configure** - Environment type (web server or worker), instance size, scaling
3. **Generate** - AWS CLI commands, CDK, or Terraform (see IaC section below)
4. **Deploy** - Execute with user confirmation

## Defaults

| Setting                   | Dev                               | Production                        |
| ------------------------- | --------------------------------- | --------------------------------- |
| Environment type (web)    | Load-balanced (min=1, max=1)      | Load-balanced, Multi-AZ           |
| Environment type (worker) | Auto Scaling group (min=1, max=1) | Auto Scaling group (min=2, max=4) |
| Instance                  | t3.small                          | t3.medium or larger               |
| Deployments               | All-at-once                       | Rolling with additional batch     |
| Health reporting          | Enhanced                          | Enhanced                          |
| Managed updates           | Enabled (weekly)                  | Enabled (maintenance window)      |
| HTTPS (web only)          | ACM certificate + ALB             | ACM certificate + ALB             |

Default to **dev** unless user says "production" or "prod".

Always use load-balanced environments for web server types. This ensures
instances stay in private subnets behind an ALB, HTTPS terminates via ACM
automatically, and scaling up later is a config change rather than an environment
type migration. Dev deployments with min=max=1 cause brief downtime on deploy
(single instance, all-at-once). If zero-downtime dev is needed, use min=1 max=2
with rolling.

Worker environments do not have load balancers — they receive work from SQS and
are scaled via Auto Scaling group settings.

## Environment Types

| Signal in Codebase                                    | Environment Type                         |
| ----------------------------------------------------- | ---------------------------------------- |
| HTTP listener, web framework, API routes              | Web server                               |
| Queue-based consumer, SQS processing, no HTTP serving | Worker                                   |
| HTTP serving + queue-based background processing      | Web server + separate Worker environment |

Worker environments receive work via an SQS queue managed by Elastic Beanstalk.
EB's SQS daemon sends HTTP POST requests to the application at a configurable
path (default: `POST /`). The application must expose this HTTP endpoint to
process each message — no SQS SDK integration required.

Worker environments also support periodic tasks via `cron.yaml` for scheduled
jobs (alternative to EventBridge + Lambda when the user is already using EB).

If the app uses in-process background threads or async tasks (not queue-based),
a single web server environment is sufficient — do not create a separate Worker.

## IaC Generation

**Default: AWS CLI** — no extra tooling to install. The agent orchestrates
the multi-step workflow:

1. `aws elasticbeanstalk create-storage-location` → returns the S3 bucket
   (idempotent — returns existing bucket if already created)
2. `aws elasticbeanstalk create-application`
3. Zip source bundle, upload to the bucket from step 1
4. `aws elasticbeanstalk create-application-version`
5. `aws elasticbeanstalk create-environment` with `--option-settings` (web:
   `--tier Name=WebServer,Type=Standard`, worker: `--tier Name=Worker,Type=SQS/HTTP`)
6. `aws elasticbeanstalk wait environment-updated`
7. Subsequent deploys: new version + `update-environment`

Resolve the `--solution-stack-name` by running
`aws elasticbeanstalk list-available-solution-stacks` and filtering for the
detected platform (e.g., ".NET" + "Amazon Linux 2023"). Alternatively, use
`--platform-arn` from `aws elasticbeanstalk list-platform-versions`.

Use `.ebextensions/` and platform hooks for customization.

See [AWS CLI EB reference](https://docs.aws.amazon.com/cli/latest/reference/elasticbeanstalk/)
for full command documentation.

**Override: CDK (TypeScript)** when the user has an existing CDK project, wants
repeatable IaC, or explicitly requests it:

- `CfnApplication`, `CfnEnvironment`, `CfnConfigurationTemplate`

**Override: Terraform** when the user's repo already has Terraform:

- `aws_elastic_beanstalk_application`, `aws_elastic_beanstalk_environment`

CDK and Terraform templates are scannable by `cfn-nag`/`checkov` pre-deploy.

## Security

Apply these automatically:

- Web server instances in private subnets behind ALB
- Worker instances in private subnets with NAT Gateway for outbound
- HTTPS via ACM certificate on ALB (web server environments)
- IAM instance profile with least-privilege permissions — scan source code for
  AWS SDK client usage to determine required actions (e.g.,
  `AmazonBedrockRuntimeClient` → `bedrock:InvokeModel`,
  `AmazonS3Client` → `s3:GetObject`/`s3:PutObject` on specific buckets)
- Enhanced health reporting enabled
- Managed platform updates enabled
- Security groups: ALB accepts 443, instances accept only from ALB

See the deploy skill's [security defaults](../deploy/references/security.md)
for encryption, VPC placement, and IAM patterns.

## Cost

Elastic Beanstalk has no service fee. Cost = underlying AWS resources.
Query the awspricing MCP server for region-accurate estimates. Approximate
us-east-1 pricing:

| Configuration                                 | Estimated Monthly Cost |
| --------------------------------------------- | ---------------------- |
| Dev web (1x t3.small + ALB)                   | ~$35-40                |
| Dev worker (1x t3.small, no ALB)              | ~$15-20                |
| Production web (4x t3.medium + ALB, Multi-AZ) | ~$150-200              |

Add RDS/Aurora costs separately if database is included.

## References

- [Beanstalk Cluster mode](references/cluster-mode.md) — containers on managed EKS
- [Supported platforms and detection](references/platforms.md) — Standard mode
- [Configuration and customization](references/configuration.md) — Standard mode
