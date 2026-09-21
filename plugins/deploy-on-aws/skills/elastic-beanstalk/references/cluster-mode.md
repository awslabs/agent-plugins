# Beanstalk Cluster mode

These rules apply after the [Elastic Beanstalk skill](../SKILL.md) has selected
Cluster mode. For Standard mode on EC2, see [platforms](platforms.md) and
[configuration](configuration.md) instead — none of it transfers.

Cluster mode runs a containerised application on an Amazon EKS Auto Mode cluster
in the user's account. You supply a container image (or source that Elastic
Beanstalk builds into one), the port it listens on, and environment variables.
Elastic Beanstalk creates and operates the cluster, node capacity, the Kubernetes
Deployment and Service, an Application Load Balancer with an HTTPS listener,
autoscaling, and log and metric delivery. The user writes no Kubernetes
manifests and runs no `kubectl`.

## The Application Contract

Cluster mode runs the application as one or more **identical, interchangeable
replicas**, and each replica's local storage is **ephemeral** — it is lost when
the replica restarts, and replicas restart on every deployment, every scaling
event, and every configuration change of severity `RestartRequired`.

Confirm all of the following before recommending Cluster mode. If any of them
fails, the application needs changing first, or it belongs in Standard mode:

- Every service runs as interchangeable replicas. No replica is special, and no
  request needs to reach a particular one.
- All durable state lives outside the container — uploads in Amazon S3, sessions
  and caches in a shared store, data in a database. An application that writes
  uploads, caches, or working files to local disk and needs them after a restart
  is incompatible.
- Requests are distributed across replicas, so in-process session state, local
  file locks, and singleton background schedulers do not survive.

There is no persistent volume or PVC surface in Cluster mode. The configuration
options include nothing for attaching storage, and EKS Auto Mode block storage
being available to the cluster does not give an environment a managed volume.
Durable state is an external service the user provisions and manages separately.
Do not imply that an EBS volume or an EFS mount can be attached through Cluster
mode configuration.

## The Namespace Boundary

A Cluster mode environment accepts twelve `aws:elasticbeanstalk:eks*`
namespaces and nothing else. Passing a classic namespace — `aws:autoscaling:*`,
`aws:elasticbeanstalk:environment:process:*`, `aws:elasticbeanstalk:application:environment`
— returns `InvalidParameterValueException` rather than being ignored.

Do not carry Standard mode habits across. There is no platform, no solution
stack, no `.ebextensions`, no `Procfile`, no platform hooks, no nginx reverse
proxy, no instance type, and no Auto Scaling group. Configuration is option
settings only.

These are the twelve, in full. Do not shorten or invent one — every option below
sits under the exact string in the left column, and there is no
`aws:elasticbeanstalk:eks:scaling` or `aws:elasticbeanstalk:eks:readiness-probe`:

| Namespace                                                          | Holds                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `aws:elasticbeanstalk:eks`                                         | `cluster-role`, `node-role`                                                                                                                                                                                                                                                                               |
| `aws:elasticbeanstalk:eks:environment`                             | `service-port`, `env-variables`, `secrets`, `subnets`, `cpu`, `cpu-limit`, `memory`, `memory-limit`, `arch`, `language`, `load-balancer-type`, `ingress-groups`, `ingress-allowlist-groups`, `ingress-allowlist-environments`, `observability-role`, `application-role`, `instance-category`, `node-pool` |
| `aws:elasticbeanstalk:eks:environment:deployment`                  | `strategy`                                                                                                                                                                                                                                                                                                |
| `aws:elasticbeanstalk:eks:environment:deployment:strategy:rolling` | `max-surge`, `max-unavailable`                                                                                                                                                                                                                                                                            |
| `aws:elasticbeanstalk:eks:environment:autoscaling`                 | `min-replica`, `max-replica`, `polling-interval`, `cooldown-period`                                                                                                                                                                                                                                       |
| `aws:elasticbeanstalk:eks:environment:autoscaling:trigger`         | `cpu-metric-type`, `cpu-value`, `memory-metric-type`, `memory-value`, `scaler-type`, `scaler-metadata`, `scaler-auth-mode`, `scaler-auth-secret`                                                                                                                                                          |
| `aws:elasticbeanstalk:eks:environment:autoscaling:behavior`        | `scaleup-*` and `scaledown-*` rate limits                                                                                                                                                                                                                                                                 |
| `aws:elasticbeanstalk:eks:environment:readiness-probe`             | `enabled`, `http-path`, `http-port`, and the timing options                                                                                                                                                                                                                                               |
| `aws:elasticbeanstalk:eks:environment:liveness-probe`              | The same options as the readiness probe                                                                                                                                                                                                                                                                   |
| `aws:elasticbeanstalk:eks:environment:startup-probe`               | The same options as the readiness probe                                                                                                                                                                                                                                                                   |
| `aws:elasticbeanstalk:eks:alb`                                     | `scheme`, `subnets`, `listen-ports`, `certificate-arn`, `ssl-redirect`, `healthcheck-path`, `arn`, and the rest of the load balancer configuration                                                                                                                                                        |
| `aws:elasticbeanstalk:eks:observability`                           | `logs-backend`, `metrics-backend`, `traces-backend`, `custom-config`, `custom-credentials`                                                                                                                                                                                                                |

Note that the probe option is `http-path`, not `path`, and that the probe
namespaces sit under `:environment` while `:alb` and `:observability` do not.

If you are unsure whether an option exists, read it from the API rather than
guessing — `aws elasticbeanstalk describe-configuration-options --tier
Name=Cluster,Type=EKS` lists every namespace and option with its default.

See [Configuration options for Beanstalk Cluster environments](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/command-options-general-eks.html)
for accepted values and defaults.

## Required IAM Roles

Three roles must exist before an environment can be created:

| Role          | Name                                          | Trusted service          | Option                                                      |
| ------------- | --------------------------------------------- | ------------------------ | ----------------------------------------------------------- |
| Cluster       | `aws-elasticbeanstalk-eks-cluster-role`       | `eks.amazonaws.com`      | `aws:elasticbeanstalk:eks` `cluster-role`                   |
| Node          | `aws-elasticbeanstalk-eks-node-role`          | `ec2.amazonaws.com`      | `aws:elasticbeanstalk:eks` `node-role`                      |
| Observability | `aws-elasticbeanstalk-eks-observability-role` | `pods.eks.amazonaws.com` | `aws:elasticbeanstalk:eks:environment` `observability-role` |

**The console creates these; the CLI and the API do not.** On a clean account,
create all three first or `create-environment` fails. Use exactly these names —
the console matches existing roles by name, and Elastic Beanstalk registers the
three roles against the cluster it creates, so a later environment on the same
subnets must supply the same three. An environment whose roles differ is
rejected rather than placed on a separate cluster.

Read each ARN back from IAM rather than composing it. A role created with a path
(`/service-role/`, which is where the console puts them) carries that path in its
ARN, and a wrong path is accepted at create time and only fails later during
provisioning, with an error that does not name the cause.

```bash
for r in cluster node observability; do
  aws iam get-role --role-name "aws-elasticbeanstalk-eks-$r-role" \
    --query Role.Arn --output text
done
```

The principal creating the environment also needs `iam:GetRole` and
`iam:PassRole` on each role, and `iam:CreateServiceLinkedRole` for the first
Cluster environment in the account. Two more roles apply in narrower cases:

- **Image build role**, `aws-elasticbeanstalk-eks-image-build-role`, trusted by
  `codebuild.amazonaws.com`. Required when Elastic Beanstalk builds the image
  from source — see [Application Versions](#application-versions).
- **Application role**, trusted by `pods.eks.amazonaws.com`, with a name the user
  chooses. Optional in principle, but required in practice by more than its
  description suggests — see [Secrets and the Application Role](#secrets-and-the-application-role).

For the managed policies on each role, the trust policies, and a ready-made
`PassRole` policy, see [Permissions for Beanstalk Cluster](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-cluster-permissions.html).

## Creating an Environment

The three role ARNs are the only required option settings. `subnets` is in the
example below because it cannot be changed afterwards, so it is the one option
worth setting even in a minimal configuration. Add `service-port` when the
container listens on anything other than `8080`:

```json
[
  {
    "Namespace": "aws:elasticbeanstalk:eks",
    "OptionName": "cluster-role",
    "Value": "arn:aws:iam::111122223333:role/service-role/aws-elasticbeanstalk-eks-cluster-role"
  },
  {
    "Namespace": "aws:elasticbeanstalk:eks",
    "OptionName": "node-role",
    "Value": "arn:aws:iam::111122223333:role/service-role/aws-elasticbeanstalk-eks-node-role"
  },
  {
    "Namespace": "aws:elasticbeanstalk:eks:environment",
    "OptionName": "observability-role",
    "Value": "arn:aws:iam::111122223333:role/service-role/aws-elasticbeanstalk-eks-observability-role"
  },
  {
    "Namespace": "aws:elasticbeanstalk:eks:environment",
    "OptionName": "subnets",
    "Value": "subnet-aaaa1111,subnet-bbbb2222"
  }
]
```

Three API calls, and the tier is what selects Cluster mode:

```bash
aws elasticbeanstalk create-application --application-name my-app

aws elasticbeanstalk create-application-version \
  --application-name my-app --version-label v1 \
  --image-configuration Source={Uri=public.ecr.aws/my-org/my-service:1.0.0}

aws elasticbeanstalk create-environment \
  --application-name my-app --environment-name my-app-env \
  --tier Name=Cluster,Type=EKS \
  --version-label v1 --option-settings file://options.json
```

Confirm the roles resolved as intended once the environment is `Ready`:

```bash
aws elasticbeanstalk describe-configuration-settings \
  --application-name my-app --environment-name my-app-env \
  --query "ConfigurationSettings[0].OptionSettings[?OptionName=='cluster-role' || OptionName=='node-role' || OptionName=='observability-role'].[OptionName,Value]" \
  --output table
```

An image-based application version reports `Status: UNPROCESSED` and is
immediately deployable — `UNPROCESSED` is not a failure here, because an image
that is already built needs no processing.

## Application Versions

A Cluster mode application version carries an `ImageConfiguration` with exactly
one of two members. `Source` names an image that is already built;
`Build` tells Elastic Beanstalk to build one from a source bundle. Supplying
both, neither, `Source` together with a `--source-bundle`, or
`ImageConfiguration` together with the Standard mode `--build-configuration` is
rejected.

**A source build is never automatic.** Nothing is inferred from the contents of
the bundle — there is no Dockerfile-or-buildpack detection. A source build needs
all four of these, and omitting `--process` leaves the version `UNPROCESSED`
with no build started, which reads as a hang:

| Piece                        | Requirement                                                                 |
| ---------------------------- | --------------------------------------------------------------------------- |
| `--source-bundle`            | `S3Bucket=` and `S3Key=` for an archive already uploaded to Amazon S3       |
| `--process`                  | Starts the build. Without it, nothing happens                               |
| `Build.Type`                 | `docker` or `buildpack`. Required — not detected                            |
| `Build.CodeBuildServiceRole` | Required. The image build role, `aws-elasticbeanstalk-eks-image-build-role` |

A `docker` build takes `DockerfileLocation`, defaulting to `Dockerfile` at the
root. A `buildpack` build must name its builder in `Buildpack` (for example
`paketobuildpacks/builder-jammy-base`); Elastic Beanstalk does not pick one, and
a buildpack build with no builder set fails.

```bash
aws elasticbeanstalk create-application-version \
  --application-name my-app --version-label v1-build --process \
  --source-bundle S3Bucket=my-source-bucket,S3Key=my-app/v1.zip \
  --image-configuration '{
    "Build": {
      "Type": "docker",
      "DockerfileLocation": "Dockerfile",
      "CodeBuildServiceRole": "arn:aws:iam::111122223333:role/service-role/aws-elasticbeanstalk-eks-image-build-role"
    }
  }'
```

`Architecture` sets the image's target CPU architecture, `amd64` or `arm64`, and
must match the environment's `arch` option — an image built for one does not run
on the other. Both default to `amd64`.

**Poll to a terminal status before deploying.** A source build reports
`BUILDING`, then `PROCESSED` on success or `FAILED` on failure. Deploy only
`PROCESSED`. `describe-events --version-label <label> --severity ERROR` names the
stage that failed; the version's `BuildArn` identifies the CodeBuild execution,
and `aws codebuild batch-get-builds --ids <arn>` gives its log location. A failed
version cannot be repaired — create a new one with a new label.

**Do not reuse the Standard mode source workflow.** `create-storage-location`,
an S3 source bundle deployed directly, solution stacks, and
`--build-configuration` all belong to Standard mode. In Cluster mode the bundle
is only ever build input, and the thing that gets deployed is the image.

Version lifecycle policies do not delete Cluster mode application versions, and
`DeleteApplicationVersion` removes only the Elastic Beanstalk record — not the
image, the Amazon ECR repository, or the source bundle in S3.

See [Building container images for Beanstalk Cluster environments](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-cluster-app-versions.html)
for the full procedure and both build types.

## Creation Timing

The first environment on a given set of subnets builds the EKS cluster first and
takes around 15 minutes. Later environments on those subnets join the existing
cluster and are ready in a few minutes. Warn the user before the first create so
the wait does not read as a hang.

## Defaults to Set Deliberately

Cluster mode has a default for nearly everything, and four of them cause
surprises. Set these explicitly rather than inheriting them:

| Option                                            | Default                           | Why set it                                                                                     |
| ------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------- |
| `max-replica`                                     | `10`                              | Ten replicas is a cost surprise, not a failure. Pin it to what the workload needs.             |
| `aws:elasticbeanstalk:eks:alb` `healthcheck-path` | `/`                               | `/` is rarely a real health endpoint and often does real work. Point it at one that is.        |
| `subnets`                                         | public subnets of the default VPC | Always set these. See [Subnets](#subnets) — the default is public and cannot be changed later. |
| `readiness-probe` `enabled`                       | `false`                           | All three container probes are off until enabled.                                              |

Two more worth knowing rather than setting. `service-port` defaults to `8080`
and is injected into the container as `PORT`, overriding any `PORT` the user
supplies in `env-variables`. And `env-variables` is a single option holding a
JSON object of every variable, not one option per variable — the same is true of
`secrets`.

Cluster mode does not inject `AWS_REGION`. An application that reads it from the
environment needs it set in `env-variables`.

## Secrets and the Application Role

The parent skill's rule still holds: never put a secret value in
`env-variables`. In Cluster mode the `secrets` option is how a secret reaches the
container — a single JSON object mapping each name to the ARN of a Secrets
Manager secret or a Parameter Store parameter, which Elastic Beanstalk mounts
into the container.

**`secrets` does not work on its own.** Elastic Beanstalk reads each value
through the pod's identity, which exists only when `application-role` is set. Set
`secrets` without it and the volume mount fails and the replicas never start — so
the environment does not come up at all, rather than coming up without its
secrets. Set up all three of these together:

1. **The role**, created before the environment. Its trust policy must allow
   `sts:AssumeRole` and `sts:TagSession` for the `pods.eks.amazonaws.com` service
   principal — that is what makes it usable as an EKS Pod Identity, and an
   otherwise-correct role with the wrong trust policy fails the same way.
2. **Read permission on every referenced value.** For a Secrets Manager secret,
   grant both `secretsmanager:GetSecretValue` and
   `secretsmanager:DescribeSecret`. With only the first, the environment starts
   normally and then fails on a later credential refresh — a failure that arrives
   hours after the deployment that caused it.
3. **`application-role`** set on the environment, in
   `aws:elasticbeanstalk:eks:environment`.

The same prerequisite applies wherever else Cluster mode reads a secret, and the
failure mode is the same in each case:

| Option                                                        | Reads a secret for                                             |
| ------------------------------------------------------------- | -------------------------------------------------------------- |
| `aws:elasticbeanstalk:eks:environment` `secrets`              | The application's own secrets and parameters                   |
| `...:autoscaling:trigger` `scaler-auth-secret`                | Credentials for a `metrics-api` scaling endpoint               |
| `aws:elasticbeanstalk:eks:observability` `custom-credentials` | Credentials for a third-party logs, metrics, or traces backend |

The application role is also what the application uses to call AWS services at
all, so scope it per environment rather than sharing one role across a set of
services. See [Permissions for Beanstalk Cluster](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-cluster-permissions.html)
for the trust policy and a worked example.

## Subnets

**Default to private subnets.** Omitting `subnets` puts the environment's nodes
in the public subnets of the default VPC, which is rarely what the user wants for
a production workload. Set the `subnets` option in
`aws:elasticbeanstalk:eks:environment` explicitly, to private subnets, unless the
user asks for public placement.

**Confirm the placement with the user before creating the environment.** Subnets
cannot be changed afterwards — they select the cluster the environment joins, so
correcting them means creating a replacement environment and swapping CNAMEs.
This is the single most expensive thing to get wrong here.

Two consequences to carry:

- The load balancer's `scheme` is derived from the subnets when it is not set.
  Private subnets give an `internal` load balancer, public subnets an
  `internet-facing` one. A private-subnet environment that needs public traffic
  needs `scheme` set to `internet-facing` and public subnets given to the load
  balancer through `aws:elasticbeanstalk:eks:alb` `subnets`.
- Nodes in private subnets need outbound network access to pull the container
  image, so those subnets need a NAT gateway or the relevant VPC endpoints.

The value is a comma-separated list, which the CLI shorthand form reads as a
field separator, so pass subnets in a JSON file rather than on the command line.

## HTTPS Only

**This section describes a load balancer that Elastic Beanstalk creates.** Check
first — HTTPS is only configured for you in that case:

| Load balancer                                               | Who owns the listeners and TLS          |
| ----------------------------------------------------------- | --------------------------------------- |
| Default — Elastic Beanstalk creates it                      | Elastic Beanstalk. This section applies |
| `aws:elasticbeanstalk:eks:alb` `arn` set to an existing ALB | The user. This section does not apply   |
| `load-balancer-type` set to `None`                          | No load balancer, so no listeners       |

With an Elastic Beanstalk-managed load balancer, it configures an HTTPS listener
on port 443 and leaves port 80 closed. Always verify over `https://`. An
`http://` request hangs until it times out and reads as a broken deployment.

Elastic Beanstalk creates and attaches an ACM certificate for the environment's
own domain and renews it, so HTTPS works without configuration. Set
`certificate-arn` only to add a certificate for a custom domain. `ssl-redirect`
alone does nothing, because it needs an HTTP listener that the environment does
not have by default; add one through `listen-ports` if the user wants the
redirect. `listen-ports` is a JSON array mapping protocol to port, such as
`[{"HTTPS":443},{"HTTP":80}]`, and an HTTP listener never serves application
traffic directly.

**With a load balancer the user supplies through `arn`, assume nothing.** Elastic
Beanstalk does not add a listener or a certificate to it; it registers the
application as a target and reports that load balancer as the environment's. The
listeners, the TLS configuration, and the scheme are the user's, so check what
the load balancer actually has before telling them a URL to test, and do not set
`certificate-arn`, `listen-ports`, `ssl-redirect`, `scheme`, or the `:alb`
`subnets` options expecting them to take effect. The value must be an Application
Load Balancer — a Network Load Balancer ARN is rejected.

## Multiple Services

A Cluster mode environment runs one service. An application made of several
services is several environments, one per service, and each can carry its own
Elastic Beanstalk application so it keeps its own version history.

Environments that share subnets land on the same EKS cluster, which is what lets
them reach each other privately and means the user pays for one cluster however
many services run on it.

**Decide the isolation boundary before recommending that, because the subnets
cannot be changed afterwards.** A shared cluster is soft multi-tenancy: the
environments share the EKS control plane, and by default they share worker nodes.
Elastic Beanstalk separates them logically — each environment runs in its own
partition and inbound traffic between environments is blocked by default, with no
option to turn that off — but logical separation is not infrastructure
separation, and the cluster is the boundary that Amazon EKS treats as a security
boundary.

| Requirement                                                                   | Boundary                                      |
| ----------------------------------------------------------------------------- | --------------------------------------------- |
| Services one team owns and operates together, as one application              | Shared cluster — same subnets                 |
| Environments belonging to different end customers                             | Separate clusters — **different subnet sets** |
| Environments running code the user does not control                           | Separate clusters — **different subnet sets** |
| A compliance regime requiring infrastructure separation                       | Separate clusters — **different subnet sets** |
| Production separated from development (common, even when nothing requires it) | Separate clusters — **different subnet sets** |

So propose a shared cluster for the services of a single application, and propose
different subnet sets otherwise. Separate clusters cost more and use capacity
less efficiently, and that is the trade being made — do not resolve it silently in
favour of the cheaper option.

Three things a shared cluster does not separate, each removed only by using
different subnets:

- **Outbound traffic is not restricted at all.** The default separation blocks
  traffic arriving at an environment, not traffic it sends. No option restricts
  egress; that has to come from the application or from the subnets' own network
  configuration.
- **The control plane is shared**, including its Kubernetes version, which is
  fixed for the life of the cluster.
- **A cluster-wide failure affects every environment on it.** If the cluster
  drifts from the configuration Elastic Beanstalk expects, updates fail for every
  environment on that cluster until the drift is reverted.

`node-pool` gives an environment dedicated nodes and is the right answer to a
node-capacity or noisy-neighbour requirement. It is not a security boundary: the
control plane is still shared, the failure domain is still shared, and
environments that share a `node-pool` value share nodes with each other — so a
value another environment already uses is not dedicated at all. If the goal is
separating environments from one another, different subnets are simpler and
separate the cluster too. See [Multi-tenancy for Beanstalk Cluster environments](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/beanstalk-cluster-multi-tenancy.html).

**Service discovery.** Environments address each other at a fixed pattern —
note the `eb-` prefix on the namespace but not on the service name:

```text
http://service-<environment-name>.eb-<environment-name>.svc.cluster.local:<service-port>
```

Because the address is built from the environment name, decide the names of a set
of services that call each other _before_ creating any of them.

**Isolation is the default.** Getting the address right is not enough.
Environments on a shared cluster cannot reach each other until they opt in, by
carrying a matching `ingress-groups` value. If the group is missing or differs,
DNS still resolves and the connection is then refused — a confusing failure,
because working name resolution suggests the address is right. For finer control
than a shared group, `ingress-allowlist-environments` and
`ingress-allowlist-groups` name who may send traffic in.

**Internal services need no load balancer.** Set `load-balancer-type` to `None`
for a service that only receives in-cluster traffic. Such an environment reports
`Grey` / `No Data` health permanently, because Cluster mode derives health from
load balancer metrics. That is expected and is not a fault to chase.

## Autoscaling

Cluster mode scales replicas of the application, not a fleet of instances, and
EKS supplies the node capacity to fit them. `min-replica` and `max-replica`
bound the count; triggers decide where between them it sits.

**Autoscaling is already on.** An environment with no trigger configured scales
on CPU utilization with a target of 80 percent. That applied trigger is not
returned by `describe-configuration-settings`, so an agent that reads the
configuration sees no scaling and concludes there is none. Do not add a second
trigger on that basis. Set `cpu-metric-type` and `cpu-value` explicitly when the
target matters, so it is readable in the configuration.

Setting `min-replica` and `max-replica` to different values without a trigger
does not give a fixed replica count — it gives the default CPU behaviour within
those bounds. Set both to the same value for a fixed count.

Beyond CPU and memory, `scaler-type` takes `cron` for a scheduled window or
`metrics-api` to scale on a number read from an HTTP endpoint the user supplies,
which is how queue depth becomes a scaling signal. Two behaviours to hold on to:
setting `scaler-type` replaces the default CPU scaling, so set the CPU trigger
explicitly to keep both, and when several triggers apply the highest replica
count wins.

A `metrics-api` endpoint whose credentials come from `scaler-auth-secret` also
needs `application-role`, and the replicas fail to start without it. See
[Secrets and the Application Role](#secrets-and-the-application-role).

See [Scaling Beanstalk Cluster environments](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/configuring-cluster-scaling.html)
for the full model.

## Verifying a Deployment

`Ready` / `Green` / `Ok` means the environment is running, not that the
application works. The load balancer health check only asks whether the service
behind it responds, and a failed update can roll back and still report `Ready`.
A single HTTP 200 is no better — many applications answer on a path that never
touches their dependencies.

Verify in this order:

1. `describe-environments` — status is `Ready`.
2. `describe-events --severity ERROR` — nothing there.
3. A request that exercises the behaviour the user asked for, over `https://`.

For a multi-service application, that third step means checking the service that
depends on the others, not each service in isolation.

Replica count is the signal for scaling and crash loops, and it is not in the
event stream. Elastic Beanstalk records an event when a scaling _setting_
changes, but a replica count that moves because a trigger fired may not appear:

```bash
aws cloudwatch get-metric-statistics \
  --namespace ElasticBeanstalk/Infrastructure --metric-name EnvironmentReplicas \
  --dimensions Name=namespace,Value=eb-<environment-name> \
  --start-time "$START" --end-time "$END" --period 60 --statistics Maximum
```

## Troubleshooting

Work in this order. It resolves most Cluster mode problems and each step narrows
the next.

1. **Events** (`describe-events`) — did Elastic Beanstalk fail at something, or
   did it succeed at building the wrong thing? An empty ERROR list is
   informative: the configuration does not match the application, and Elastic
   Beanstalk has no way to know that.
2. **Health** (`describe-environment-health --attribute-names All`) — the
   `Causes` field. `ELB health is failing or not available for all instances.`
   means the load balancer cannot get a healthy response.
3. **Target group** (`elbv2 describe-target-health`) — the port and the reason.
   `Target.Timeout` on a port is the strongest single clue available.
4. **Replica count** — a steady count means a pod is running and staying
   running, so the application is alive and unreachable rather than crashing.
5. **Application logs** — the only place the application itself speaks.

Logs go to four log groups with fixed names, shared across every Cluster mode
environment in the account and Region — every cluster, not one group per
environment. Environments are separated by stream name, not by group:

| Log group                                      | Contents                                | Stream name                        |
| ---------------------------------------------- | --------------------------------------- | ---------------------------------- |
| `/aws/elasticbeanstalk/application/logs`       | The container's own output              | `eb-<environment-name>.<pod-name>` |
| `/aws/elasticbeanstalk/application/metrics`    | Metrics the application emits           | `<environment-name>/<pod-name>`    |
| `/aws/elasticbeanstalk/infrastructure/logs`    | The components Elastic Beanstalk runs   | `<k8s-namespace>.<pod-name>`       |
| `/aws/elasticbeanstalk/infrastructure/metrics` | Elastic Beanstalk's own metrics, in EMF | `<k8s-namespace>.<pod-name>`       |

Note the two different prefixes: application log streams carry the `eb-` prefix
and a period, application metric streams carry the environment name and a slash
with no prefix. The application's output is the first group:

```bash
aws logs tail /aws/elasticbeanstalk/application/logs \
  --log-stream-name-prefix eb-<environment-name> --since 30m
```

These groups are created **without a retention policy**, so nothing expires. The
stream name contains the pod name, so every deployment and every scaling event
creates new streams and the old ones stay. Suggest setting retention on all four
after the first environment is created — it is an account-level cost that grows on
its own and nothing in the environment surfaces it.

Distrust one event message: the launch event may report `logs-backend=s3
(default)` and link an S3 bucket. The default is CloudWatch, and that is where
the logs are.

**The most common real fault is a port mismatch.** `service-port` builds the
Kubernetes Service and the load balancer target group, and is injected as `PORT`.
An application that honours `PORT` follows along; one that binds a hard-coded
port does not, and the two disagree silently — no error, no exception, healthy
pod, failing health check. Check what the application logged it bound to against
what `service-port` says.

## What Cannot Change After Create

| Change severity   | Applies                           | Examples                                                     |
| ----------------- | --------------------------------- | ------------------------------------------------------------ |
| `NoInterruption`  | Without restarting anything       | Autoscaling bounds, most load balancer options               |
| `RestartRequired` | Replicas restart                  | `service-port`, `env-variables`, `cpu`, `memory`             |
| `NoChange`        | Fixed once the environment exists | `cluster-role`, `node-role`, `observability-role`, `subnets` |

The roles and the subnets are the ones to get right the first time. An update
that changes them is rejected. Moving an application to different subnets or
roles means creating a new environment and swapping the two CNAMEs — so confirm
network placement with the user before the first create, not after.

The cluster's Kubernetes version is also fixed. Elastic Beanstalk picks the most
recent version it supports when it creates a cluster, and that version stays for
the life of the cluster; an environment added to an existing cluster runs
whatever version that cluster has.

Deployments use `RollingUpdate` by default with `max-surge` of 1 and
`max-unavailable` of 0, so a new replica becomes ready before an old one goes.
`Recreate` is the all-at-once equivalent.

## Operating the Cluster

Manage the cluster through Elastic Beanstalk. Modifying it with `kubectl` or
`eksctl`, or editing its CloudFormation stack, can leave it in a state Elastic
Beanstalk does not recognise, which pauses maintenance and fails environment
updates until the change is reverted. Reading the cluster is fine and is often
worth doing.

Never delete the cluster or its CloudFormation stack directly. Elastic Beanstalk
schedules the shared cluster for deletion a few hours after the last environment
on it terminates.

Cluster mode maintains nodes and keeps its own cluster add-ons current. It does
not patch the application runtime or the container image, so keeping the image
current stays with the user.

## Cost

Elastic Beanstalk adds no service fee. A Cluster mode environment costs:

- The Amazon EKS cluster's hourly charge.
- The EC2 instances that EKS Auto Mode provisions to hold the replicas, **plus
  the EKS Auto Mode management charge on those instances**, which is billed per
  instance on top of the instance price and varies by instance type.
- An Application Load Balancer per environment, unless `load-balancer-type` is
  `None`.
- Data transfer.

Four more that are easy to miss, because they are on by default and none of them
appear in the environment's own configuration:

- **CloudWatch custom metrics.** Elastic Beanstalk publishes to three custom
  namespaces — `ElasticBeanstalk/Infrastructure`, `ElasticBeanstalk/System`, and
  `ElasticBeanstalk/Application` — and custom metrics are charged per metric. The
  container metrics are published per replica, so this grows with replica count.
  Standard mode publishes to `AWS/ElasticBeanstalk`, which CloudWatch provides at
  no charge, so this line item is new in Cluster mode rather than larger.
- **CloudWatch logs with no retention.** The four shared log groups never expire
  and accumulate a new set of streams on every deployment.
- **NAT gateway or VPC endpoints** for a private-subnet environment, which needs
  outbound access to pull its image.
- **CodeBuild and Amazon ECR** when Elastic Beanstalk builds the image from
  source, per build and then for image storage.

Only the cluster charge is shared. Everything else scales per workload: each
environment brings its own replicas, its share of node capacity, its own load
balancer, its own custom metrics and its own traffic. So the _second_ service on a
cluster is cheaper than the first because it does not pay for another cluster —
but it is not close to free, and a multi-service application is not cheap simply
because one cluster is shared. Do not present it that way.

Cluster mode therefore has a floor that Standard mode does not: a single small
service usually costs more here than the same service on one EC2 instance. The
economics improve with the number of services sharing the cluster.

Query the `awspricing` MCP server for region-accurate figures rather than quoting
rates, and remember that `cpu` and `memory` are reservations — they decide how
many replicas fit on a node, and so how much node capacity the environment draws.
See the deploy skill's
[cost estimation patterns](../../deploy/references/cost-estimation.md#beanstalk-cluster-mode-managed-eks)
for the service codes and for the Standard-versus-Cluster comparison.
