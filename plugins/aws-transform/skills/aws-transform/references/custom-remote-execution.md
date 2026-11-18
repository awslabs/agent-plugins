# Remote Execution

Run AWS Transform custom transformations at scale in containers in the user's own AWS
account, on AWS Batch (Fargate) or Amazon EC2. Remote execution is built into the AWS
Transform CLI: `atx ct remote` provisions the infrastructure, and
`atx ct remote remediation --transformation-name <name>` runs a transformation definition
directly against each repository, with no analysis or findings needed. There is no
separate infrastructure repository, setup script, or CDK app. Do not call the stack's
Lambda functions or AWS Batch directly; use the CLI commands below.

This file covers what is specific to custom transformations. For provisioning and
command detail, follow the continuous modernization references it links to:
[remote Batch execution](continuous-modernization-batch-execution.md),
[remote EC2 execution](continuous-modernization-ec2-execution.md),
[sources](continuous-modernization-source.md) and
[setup](continuous-modernization-setup.md).

Key resources in the user's account:

- Transformed code in Amazon S3 (`atx-custom-output-{accountId}`)
- Local-source repositories uploaded to Amazon S3 (`atx-source-code-{accountId}`)
- A CloudWatch log group and dashboard per stack
- Source tokens in AWS Secrets Manager (`atx/<source>/<provider>-token`)
- To find the account: `aws sts get-caller-identity --query Account --output text`

Every `atx ct` command needs the region: prefix `AWS_REGION=<region>` on each command
line (see [Choose your region](continuous-modernization-setup.md#step-2-choose-your-region)).
Tell the user which region is being used. Remote execution is available only in the
regions where continuous modernization is; an unsupported region returns a region error.

## Table of Contents

- [Infrastructure Check](#infrastructure-check)
- [User Consent Prompt](#user-consent-prompt)
- [Deployment](#deployment)
- [Repository Sources](#repository-sources)
- [Private Repository Access](#private-repository-access)
- [Job Submission](#job-submission)
- [Polling](#polling)
- [Results Location](#results-location)
- [Monitoring](#monitoring)
- [Container Customization](#container-customization)
- [Pricing](#pricing)
- [Cleanup](#cleanup)

## Infrastructure Check

Ask whether any repositories are private first ([Repository Access (Remote Mode)](custom.md#repository-access-remote-mode)); run these checks only after the user answers.

```bash
AWS_REGION=<region> atx ct remote detect --mode batch --json
AWS_REGION=<region> atx ct remote detect --mode ec2 --json
```

Without `--stack-name` or `--tags`, each lists every stack of that mode
(`AtxInfrastructureStack*` for Batch, `atx-runner*` for EC2). A stack with status
`deployed` is ready: note its `stackName` and go to [Repository Sources](#repository-sources).
For any other status, or no stack, get explicit user consent before deploying.

A Batch stack named `AtxInfrastructureStack` may be left from the earlier setup script.
Offer to bring it up to date with `atx ct remote update` (see
[Deployment Failures](#deployment-failures)) instead of deploying a second stack.

## User Consent Prompt

Explain what gets created: a Batch (Fargate) compute environment or an EC2 instance,
S3 buckets, IAM roles, a CloudWatch log group and dashboard, and the job-queueing
resources the CLI deploys alongside the stack. With the pre-built image, no Docker is
needed and no container registry is created. A custom image needs Docker and an
Amazon ECR repository the user owns. One-time setup.
Do NOT deploy until the user confirms.

## Deployment

### Batch or EC2

Default to Batch: one Fargate container per repository, nothing running between runs.
Use EC2 when the user wants a persistent instance (1-5 parallel workers) or already has
one. See "When to Use" in the
[Batch](continuous-modernization-batch-execution.md#when-to-use)
and [EC2](continuous-modernization-ec2-execution.md#when-to-use)
files.

### Network

Remote compute runs in private subnets with outbound internet access (NAT). AWS
Transform does not pick the network for the user. List candidates (public subnets are
excluded):

```bash
AWS_REGION=<region> atx ct remote network discover --json
```

Let the user choose the VPC, subnets, and (for Batch, required) security group. If
there is no suitable VPC, `atx ct remote network create` creates one with private
subnets, a NAT gateway, and a security group. It needs admin credentials and the NAT
gateway is billed while it exists, so confirm first and give the user the command to
run (see [Provision](continuous-modernization-batch-execution.md#2-provision)).

### Pre-built Image Path (No Docker Required)

You decide the image during the Verify Runtime Compatibility step in
[custom](custom.md). Do NOT ask the user to choose.

The default image `public.ecr.aws/d9h8z6l7/aws-transform:latest` includes:

- **Java**: 8, 11, 17, 21, 25 (Amazon Corretto) with Maven and Gradle 9.4
- **Python**: 3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 3.14 (dnf + pyenv)
- **Node.js**: 16, 18, 20, 22, 24 (nvm) with yarn, pnpm, TypeScript, ts-node
- **Build tools**: gcc, g++, make, patch
- **CLI tools**: AWS CLI v2, AWS Transform CLI, git, jq, curl, unzip, tar
- **OS**: Amazon Linux 2023 (x86_64)

Preview first. Without `--execute`, `provision` only writes the CloudFormation
template to a local file, so you can run it:

```bash
AWS_REGION=<region> atx ct remote provision --mode batch \
  --vpc <vpc-id> --subnets <subnet-1>,<subnet-2> --securityGroup <sg-id>
```

Deploying needs admin credentials. You MUST NOT run it yourself: give the user the
command to run in their own terminal with an admin profile:

```
AWS_PROFILE=<your-admin-profile> AWS_REGION=<region> atx ct remote provision --mode batch \
  --vpc <vpc-id> --subnets <subnet-1>,<subnet-2> --securityGroup <sg-id> --execute --ack
```

For EC2, use `--mode ec2` (`--securityGroup` optional, `--workers 1-5`). Optional flags
such as `--job-timeout` (Batch, default 12 hours) and `--tags` are in
[Provision](continuous-modernization-batch-execution.md#2-provision)
(Batch) and [Provision](continuous-modernization-ec2-execution.md#2-provision)
(EC2). After the user confirms, re-run `atx ct remote detect --mode <batch|ec2>` to get the stack name.

### Custom Image Path (Docker Required)

If the transformation needs a runtime (source or target) or other software that is
not in the pre-built image, build an image on top of it (see
[Container Customization](#container-customization)), push it to an Amazon ECR
repository in the user's account, and add `--image-uri <uri>` to the provision
command above. This needs Docker installed and running.

A later `atx ct remote update` resets the image to the default. To keep the custom
image, re-run `provision` with `--image-uri` instead.

### Deployment Failures

The CLI prints the cause. Fix it and re-run the same command; the error tables in
[Batch error handling](continuous-modernization-batch-execution.md#error-handling)
and [EC2 error handling](continuous-modernization-ec2-execution.md#error-handling)
list the common ones. Do not try to fix individual CloudFormation resources by hand.

A stack deployed by an older CLI or by the earlier setup script keeps its old
infrastructure. Preview the update, then have the user apply it with admin credentials:

```bash
AWS_REGION=<region> atx ct remote update --mode batch --stack-name <stack>
AWS_PROFILE=<your-admin-profile> AWS_REGION=<region> atx ct remote update --mode batch --stack-name <stack> --execute --ack
```

If the stack is stuck in a failed state that `update` can't apply to, have the user
tear it down (see [Cleanup](#cleanup)) and provision again.

### Attach IAM Policies

Day-to-day submission and polling need only the Executor role, not admin. Direct the
user to attach the Executor policy described in
[Permission Model](continuous-modernization-batch-execution.md#permission-model)
(Batch) or [Permission Model](continuous-modernization-ec2-execution.md#permission-model)
(EC2) to the identity they use for running jobs. You MUST NOT attach it yourself.

## Repository Sources

Remote runs read repositories from a registered source, not from individual URLs or
paths. Repositories are named `<source>::<repo>`.

| User provides                                                                         | Register as                                                                                                                                         |
| ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| HTTPS repos on GitHub, GitLab, or Bitbucket (GitLab and Bitbucket can be self-hosted) | The org, group/user, or workspace/project: `--provider github\|gitlab\|bitbucket --org <org>` (self-hosted GitLab or Bitbucket: `--url <base-url>`) |
| Local folders                                                                         | Their parent folder: `--provider local --path <parent-dir>` (each subdirectory is one repository)                                                   |
| SSH URLs, GitHub Enterprise Server, or other git hosts                                | Clone locally into one parent folder, then register it as a local source                                                                            |
| S3 zips                                                                               | Download and extract locally into one parent folder, then register it as a local source                                                             |

Commands, token scopes, and provider details are in
[Source](continuous-modernization-source.md).
Before adding, run `atx ct source list --json`; an existing source is updated with
`atx ct source update`, not added again. After adding, discover its repositories and
get their slugs:

```bash
AWS_REGION=<region> atx ct discovery scan --source <source>
AWS_REGION=<region> atx ct repository list --source <source> --json
```

For a local source, `atx ct discovery scan --source <source> --repo <name>` registers
only that subdirectory. When a run starts, the CLI uploads local-source repositories to
`atx-source-code-{accountId}`. One submission can't mix local and git-hosted
repositories; submit them separately.

**Repo analysis:** Do NOT scan or inspect repository contents locally in remote mode.
The repos may not be on the local machine. Let the user specify which transformation
definitions to apply, or use the one already selected.

## Private Repository Access

Git-hosted sources always use a token. **Never ask the user to paste or type a token
into this chat**, or to confirm or repeat its value. Give the user the one-liner from
[Token handling](continuous-modernization-source.md#token-handling)
to run in their own terminal, for example:

```bash
read -s TOKEN && AWS_REGION=<region> atx ct source add --name <source> --provider github --org <org> --token "$TOKEN"; unset TOKEN
```

`source add` and `source update --token` also store the token in AWS Secrets Manager
(`atx/<source>/<provider>-token`) for remote containers. If the user's role can't write
secrets, the CLI warns, and someone with admin credentials stores it later:

```bash
read -s TOKEN && AWS_REGION=<region> atx ct remote credentials --source <source> --token "$TOKEN" --ack; unset TOKEN
```

`atx ct remote credentials --source <source> --remove` deletes the stored secret. AWS
credentials for the AWS Transform CLI inside the container come from the stack's IAM
role; the user provides none.

The default image reads only the per-source clone tokens stored as
`atx/<source>/<provider>-token`. It has no setting for private package registry
credentials, and the CLI has no option to pass any. If a build needs one, run it in
local mode.

## Job Submission

**Transformation definition category:** a transformation definition from the user's own
account runs remotely only if it was published with `--category remediation`; check its
`category` in `atx custom def list --json`. An uncategorized or `analysis` one is
rejected: republish it with `atx custom def publish -n <name> --sd <dir> --description "<desc>" --category remediation`.
AWS-managed (`AWS/...`) transformation definitions run unless they are tagged `analysis`.

Present the plan (transformation definition, repositories, configuration, stack) and
get confirmation, then submit one transformation definition per submission:

```bash
AWS_REGION=<region> atx ct remote remediation \
  --transformation-name <td> \
  --repos <source>::<repo-1>,<source>::<repo-2> \
  -g 'additionalPlanContext=<context from Collect Configuration>' \
  --mode batch --stack-name <stack> \
  --batch-name <name> \
  --telemetry "agent=<agent>,executionMode=fargate" \
  --json
```

- `--repos` takes comma-separated, source-qualified slugs (`<source>::<repo>`, never a
  bare name). `--sources <source>` runs every repository in a source; add `--labels` to filter it.
- `-g` accepts a config file path or `key=value` pairs (`additionalPlanContext`,
  `buildCommand`). Do not use commas inside a value. Omit `-g` if there is no extra
  context.
- Do NOT pass `--ids`, `--severity`, or `--min-severity`: they select findings, and
  this path runs without findings.
- For EC2, use `--mode ec2` with `--stack-name` (or `--existing-instance <id>`) and
  `executionMode=ec2` in `--telemetry`. See
  [Telemetry](continuous-modernization-batch-execution.md#telemetry)
  for the `--telemetry` values; omit the flag for the rest of the session if the user
  opts out.
- To apply several transformation definitions, submit once per transformation
  definition.

**Limits:** up to 1,000 repositories per submission; split larger lists. Jobs beyond
the account's concurrent-job limit wait in a queue and start as slots free (see
[Limits](continuous-modernization-batch-execution.md#limits)).
`--batch-name` must be unique; omit it for a generated ID.

The command validates source tokens and the transformation definition, then returns a
batch ID (Batch) or group ID (EC2) to poll. Track every ID you get.

## Polling

Poll every 60 seconds for the first 10 polls, then every 5 minutes after.
Report only on status change.

```bash
AWS_REGION=<region> atx ct remote status --batch <batch-id> --stack-name <stack> --json   # Batch
AWS_REGION=<region> atx ct remote status --group <group-id> --json                       # EC2
```

`atx ct remote status --stack-name <stack>` without `--batch` lists recent Batch runs.
A waiting job shows why (for example `pending (waiting for capacity)`); `--verbose`
adds the raw wait data.

To stop work, after user confirmation:

```bash
AWS_REGION=<region> atx ct remote cancel --batch <batch-id> --stack-name <stack> [--job <job-name>]   # Batch
AWS_REGION=<region> atx ct remote cancel --group <group-id> [--job <job-key>]                        # EC2
```

## Results Location

Do NOT download results locally. For each repository, the status output shows its
`resultId` (the remediation ID) and:

- **GitHub, GitLab, Bitbucket sources:** the pull request or merge request opened from a
  new branch with the changes.
- **Every source:** the transformed code, zipped, in Amazon S3:

```
s3://atx-custom-output-{account-id}/<remediation-id>/<source>::<repo>/code.zip
```

The bucket name is `outputBucketName` in `atx ct remote detect --mode <batch|ec2> --stack-name <stack> --json`. Per-repository
detail: `atx ct remediation status --id <remediation-id> --json`.

If the user explicitly asks to download, provide the command but let them run it:

```
aws s3 cp "s3://atx-custom-output-{account-id}/<remediation-id>/<source>::<repo>/code.zip" ./code.zip
```

## Monitoring

`atx ct remote detect --mode <batch|ec2> --stack-name <stack> --json` returns the
stack's `dashboardName`, and for Batch its `logGroupName`. An EC2 stack's container
logs are in the log group `/atx/ct/ec2/<stackName>`. Build the dashboard URL with the
region you are using:

```
https://<region>.console.aws.amazon.com/cloudwatch/home?region=<region>#dashboards/dashboard/<dashboardName>
```

Include this link in the final output when remote execution completes.

## Container Customization

If a transformation requires a language or tool that is not in the pre-built image, you
handle this during the Verify Runtime Compatibility step in [custom](custom.md). Build
on the pre-built image so the AWS Transform CLI and the container's entrypoint stay in
place:

```dockerfile
FROM public.ecr.aws/d9h8z6l7/aws-transform:latest
# Example: add Rust (install as atxuser so binaries land in /home/atxuser/.cargo)
USER atxuser
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
USER root
ENV PATH="/home/atxuser/.cargo/bin:$PATH"
```

When adding to the image:

- Do not use `dnf` in your layers: pyenv overrides the system `python3` that `dnf`
  needs, which fails with `No module named 'dnf'`.
- Install another Amazon Corretto version as root from its tarball
  (`https://corretto.aws/downloads/latest/amazon-corretto-<N>-x64-linux-jdk.tar.gz`,
  extracted under `/usr/lib/jvm`).
- Install Node.js versions with nvm (`. /home/atxuser/.nvm/nvm.sh && nvm install <N>`)
  and Python versions with pyenv (`/home/atxuser/.pyenv/bin/pyenv install <version>`)
  as `atxuser`.

Build for `linux/amd64`, push it to an Amazon ECR repository in the user's account, and
deploy it as in [Custom Image Path](#custom-image-path-docker-required). Never bake
credentials into the image.

The CLI sends no per-job runtime version setting (such as `JAVA_VERSION`), so a target
version the image lacks needs a custom image. Make the added version the image's default (for example
`ENV JAVA_HOME`, `nvm alias default <N>`, or `pyenv global <version>`) so builds use it.

## Pricing

Do NOT quote specific prices or cost estimates to the user. If the user asks about
pricing, direct them to: https://aws.amazon.com/transform/pricing/

A Batch stack has no fixed compute cost: Fargate is billed per task. An EC2 stack's
instance is billed while it runs, and a NAT gateway created with
`atx ct remote network create` is billed while it exists.

## Cleanup

After every remote execution completes (all jobs finished or failed), prompt the
user with the following:

> Your remote infrastructure is still deployed in your AWS account. You can leave it
> in place for future transformations, or tear it down now. [Batch: it has no fixed
> compute cost when idle. EC2: the instance is billed while it runs.]
>
> For pricing details: https://aws.amazon.com/transform/pricing/
>
> If you tear down:
>
> - The stack (its compute and IAM roles) is removed
> - The S3 buckets (with your results) and the source tokens in Secrets Manager are kept
> - Your VPC and subnets are not deleted
> - You'll need to provision again next time you use remote mode
>
> Would you like to keep the infrastructure or tear it down?

If the user chooses to tear down, preview it, then give the user the command to run
with admin credentials:

```bash
AWS_REGION=<region> atx ct remote teardown --mode <batch|ec2> --stack-name <stack>
AWS_PROFILE=<your-admin-profile> AWS_REGION=<region> atx ct remote teardown --mode <batch|ec2> --stack-name <stack> --execute --ack
```

If the user chooses to keep it, confirm: "Infrastructure will stay deployed. Next
time you run remote transformations, everything will be ready immediately."
