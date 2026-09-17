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
Cluster environment in the account. Two more roles apply in narrower cases: an
image build role (`codebuild.amazonaws.com`) when Elastic Beanstalk builds the
image from source, and an optional application role (`pods.eks.amazonaws.com`)
when the application itself calls AWS services.

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
  --image-source Uri=public.ecr.aws/my-org/my-service:1.0.0

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
immediately deployable. Only source bundles are processed, because only they
need building. To deploy source instead of an image, supply a source bundle and
Elastic Beanstalk builds the image with AWS CodeBuild, from a Dockerfile if
there is one or from a buildpack if there is not.

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

Elastic Beanstalk configures an HTTPS listener on port 443 and leaves port 80
closed. Always verify over `https://`. An `http://` request hangs until it times
out and reads as a broken deployment.

Elastic Beanstalk creates and attaches a certificate for the environment's own
domain, so HTTPS works without configuration. Set `certificate-arn` only to add
a certificate for a custom domain. Setting `ssl-redirect` alone does nothing,
because it needs an HTTP listener that the environment does not have by default;
add one through `listen-ports` if the user wants the redirect.

## Multiple Services

A Cluster mode environment runs one service. An application made of several
services is several environments, one per service, and each can carry its own
Elastic Beanstalk application so it keeps its own version history.

Environments that share subnets land on the same EKS cluster, which is what lets
them reach each other privately and means the user pays for one cluster however
many services run on it.

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

A `metrics-api` endpoint that needs credentials also needs `application-role`
set on the environment — the credentials are mounted through Pod Identity, which
does not exist without it, and the replicas fail to start. Grant that role both
`secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret`; with only
the first, the environment starts normally and then fails on every later
credential refresh.

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

Logs go to three account-wide log groups, shared across every environment rather
than one per environment. The container's output is in
`/aws/elasticbeanstalk/application/logs`, with one stream per pod named
`eb-<environment>.deployment-<environment>-<replicaset>-<pod>`:

```bash
aws logs tail /aws/elasticbeanstalk/application/logs \
  --log-stream-name-prefix eb-<environment-name> --since 30m
```

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
- EBS volumes for any persistent storage, plus data transfer.

Only the cluster charge is shared. Everything else scales per workload: each
environment brings its own replicas, its share of node capacity, its own load
balancer, its own storage and its own traffic. So the _second_ service on a
cluster is cheaper than the first because it does not pay for another cluster —
but it is not close to free, and a multi-service application is not cheap simply
because one cluster is shared. Do not present it that way.

Cluster mode therefore has a floor that Standard mode does not: a single small
service usually costs more here than the same service on one EC2 instance. The
economics improve with the number of services sharing the cluster.

Query the `awspricing` MCP server for region-accurate figures rather than quoting
rates, and remember that `cpu` and `memory` are reservations — they decide how
many replicas fit on a node, and so how much node capacity the environment draws.
