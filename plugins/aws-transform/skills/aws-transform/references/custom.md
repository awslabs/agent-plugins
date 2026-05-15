# AWS Transform custom

## Table of Contents

- [Overview](#overview)
- [Greeting](#greeting)
- [Usage](#usage)
- [Core Concepts](#core-concepts)
- [Philosophy](#philosophy)
- [Prerequisites](#prerequisites)
- [Workflow](#workflow)
- [Execution Modes](#execution-modes)
- [Critical Rules](#critical-rules)
- [Guardrails](#guardrails)
- [Telemetry](#telemetry)
- [Output Structure](#output-structure)
- [References](#references)
- [License](#license)
- [Issues](#issues)
- [Changelog](#changelog)

## Overview

Perform code upgrades, migrations, and transformations using AWS Transform custom.
Supports any-to-any transformations: language version upgrades (Java, Python, Node.js, etc.),
framework migrations, AWS SDK migrations, library upgrades, code refactoring, architecture
changes, and custom organization-specific transformations.

Two execution modes:

- **Local mode**: Runs the AWS Transform CLI directly on the user's machine. Best for 1-9 repos.
- **Remote mode**: Runs transformations at scale via AWS Batch/Fargate containers.
  Best for 10+ repos or when the user prefers cloud execution. Infrastructure is
  auto-deployed with user consent.

You handle the full workflow: inspecting repos, matching them to available
transformation definitions, collecting configuration, and executing transformations
in either mode — the user just provides repos and confirms the plan.

## Greeting

"AWS Transform custom can help you:

- Upgrade Java, Python, and Node.js to modern versions
- Migrate AWS SDKs (Java SDK v1->v2, boto2->boto3, JS SDK v2->v3)
- Handle framework migrations, library upgrades, and code refactoring
- Analyze codebases and generate documentation
- Define and run your own custom transformations using natural language, docs,
  and code samples

Run locally on a few repos for fast iteration, or at scale on hundreds of repos (up to 128 in-parallel). Note: this skill collects telemetry. To opt out, see [here](https://docs.aws.amazon.com/transform/latest/userguide/transform-usage-telemetry.html).

What would you like to transform today?"

Do NOT inspect any files, run any commands, or check prerequisites until the user responds.

## Usage

Use when the user wants to:

- Transform, upgrade, or migrate code (Java, Python, Node.js, etc.)
- Migrate AWS SDKs (Java SDK v1->v2, boto2->boto3, JS SDK v2->v3, etc.)
- Run bulk code transformations at scale via AWS Batch/Fargate
- Analyze which AWS Transform transformations apply to their repositories
- Perform comprehensive codebase analysis
- Create a new custom Transformation definition

## Core Concepts

- **Transformation definition**: A reusable transformation recipe discovered via `atx custom def list --json`
- **Match Report**: Auto-generated mapping of repos to applicable transformation definitions based on code inspection
- **Local Mode**: Runs AWS Transform CLI on the user's machine (1-9 repos, max 3 concurrent)
- **Remote Mode**: Runs transformations in AWS Batch/Fargate (10+ repos, or by preference)

## Philosophy

Wait for the user. On activation, present what this skill can do and ask the user
what they'd like to accomplish. Do NOT automatically inspect the working directory,
open files, or any repository until the user explicitly provides repos to work with.

Once the user provides repositories, match — don't ask. Inspect those repositories
and present which transformations apply automatically. Never show a raw transformation definition list and
ask the user to pick.

## Prerequisites

Prerequisite checks run ONCE at the start of a session. Do not repeat per repo.
Do NOT run prerequisite checks until the user has stated what they want to do.

### Platform Check (Required — All Modes)

Detect the user's operating system. If on Windows (not WSL), stop immediately and
inform the user:

> AWS Transform custom does not support native Windows. You need to install
> Windows Subsystem for Linux (WSL) and run this from within WSL.
>
> Install WSL: `wsl --install` in PowerShell (as Administrator), then restart.
> After that, open a WSL terminal and re-run this skill from there.

Check by running:

```bash
uname -s
```

- `Linux` or `Darwin` -> proceed normally
- `MINGW*`, `MSYS*`, `CYGWIN*`, or any Windows-like output -> block and show the WSL message above
- Command fails, errors, or is not found -> treat as native Windows, block and show the WSL message above

Do NOT proceed with any other steps on native Windows.

### AWS CLI (Required — All Modes)

```bash
aws --version
```

If not installed, guide the user:

- macOS: `brew install awscli` or `curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" && sudo installer -pkg AWSCLIV2.pkg -target /`
- Linux: `curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install`

Do NOT proceed until `aws --version` succeeds.

### AWS Credentials (Required — All Modes)

```bash
aws sts get-caller-identity
```

If credentials are NOT configured, walk the user through setup:

```
AWS Transform custom requires AWS credentials to authenticate with the service. Configure authentication using one of the following methods.

1. AWS CLI Configure (~/.aws/credentials):
   aws configure

2. AWS Credentials File (manual). Configure credentials in ~/.aws/credentials:

[default]
aws_access_key_id = your_access_key
aws_secret_access_key = your_secret_key

3. Environment Variables. Set the following environment variables:

export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_SESSION_TOKEN=your_session_token

You can also specify a profile using the AWS_PROFILE environment variable:

export AWS_PROFILE=your_profile_name
```

Do NOT proceed until credentials are verified. Re-run `aws sts get-caller-identity` after setup.

Note: environment variables set via `export` do not carry over between shell sessions. If you spawn a new shell, credentials set as env vars may be lost. Prefer `aws configure` or `~/.aws/credentials` for persistence.

### AWS Transform CLI (Required — All Modes)

Required in all modes for transformation definition discovery (`atx custom def list --json`).
Local mode also uses it for transformation execution.

```bash
atx --version
# Install: curl -fsSL https://transform-cli.awsstatic.com/install.sh | bash
```

**Mandatory: always run `atx update` once at the start of every session**, even if you just ran it recently. This catches new AWS Transform CLI versions and new transformation definitions. Run it before any other ATX command (including `atx custom def list --json`):

```bash
atx update
```

Do NOT skip this step. Do NOT ask the user whether to update. Do NOT condition it on whether the CLI "needs" an update. Run it unconditionally.

### IAM Permissions (Required — All Modes)

Local mode requires `transform-custom:*` minimum. Verify by running a transformation definition list:

```bash
atx custom def list --json
```

If this succeeds, permissions are sufficient — skip the rest of this section.

If it fails with a permissions error, the caller needs the `transform-custom:*`
IAM permission. Explain to the user what's needed and get confirmation before proceeding:

> Your identity needs the `transform-custom:*` permission to use the AWS Transform CLI.
> I can attach the AWS-managed policy `AWSTransformCustomFullAccess` to your
> identity. Shall I proceed?

Only after the user confirms, attach the managed policy:

```bash
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
if echo "$CALLER_ARN" | grep -q ":user/"; then
  IDENTITY_NAME=$(echo "$CALLER_ARN" | awk -F'/' '{print $NF}')
  aws iam attach-user-policy --user-name "$IDENTITY_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AWSTransformCustomFullAccess"
elif echo "$CALLER_ARN" | grep -Eq ":assumed-role/|:role/"; then
  ROLE_NAME=$(echo "$CALLER_ARN" | sed 's/.*:\(assumed-\)\{0,1\}role\///' | cut -d'/' -f1)
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AWSTransformCustomFullAccess"
fi
```

If the attachment command itself fails (e.g., insufficient IAM permissions, or an
SSO-managed role), inform the user they need to ask their AWS administrator to
attach the `AWSTransformCustomFullAccess` AWS-managed policy to their identity.
For SSO users (role names starting with `AWSReservedSSO_`), this must be added
to their IAM Identity Center permission set — it cannot be attached directly.

Do NOT proceed until `atx custom def list --json` succeeds.

Remote mode requires additional permissions (Lambda invoke, S3, KMS, Secrets Manager,
CloudWatch). These are generated and attached as part of the deployment flow — see
[custom-remote-execution](custom-remote-execution.md).

See [custom-cli-reference](custom-cli-reference.md) for the full permission list.

### AWS CDK (Remote Mode Only)

Required for deploying remote infrastructure. Check if installed:

```bash
cdk --version
```

If not installed, install it globally:

```bash
npm install -g aws-cdk
```

Do NOT proceed with remote deployment until `cdk --version` succeeds.

### Remote Infrastructure (Remote Mode Only — Deferred)

Only verify if user chooses remote mode. The infrastructure CDK scripts are fetched
at runtime by cloning `https://github.com/aws-samples/aws-transform-custom-samples.git` (branch `atx-remote-infra`) —
they are not bundled with this skill. See [custom-remote-execution](custom-remote-execution.md).

## Workflow

Generate a session timestamp once and reuse it for all paths in this session:

```bash
SESSION_TS=$(date +%Y%m%d-%H%M%S)
```

### Collect Repositories

Ask the user for local paths or git URLs. Accept one or many. Do NOT assume the
current working directory or open editor files are the target — wait for the user
to explicitly provide repositories.

Accepted source formats:

- **Local paths** — directories on the user's machine (e.g., `/home/user/my-project`)
- **HTTPS git URLs** — public or private (e.g., `https://github.com/org/repo.git`)
- **SSH git URLs** — e.g., `git@github.com:org/repo.git`
- **S3 bucket path with zips** — e.g., `s3://my-bucket/repos/`
  containing zip files of repositories. Each zip becomes one transformation job.

#### S3 Bucket Input

If the user provides an S3 path containing zip files, ask which execution mode
they prefer (if not already specified). S3 input works in both modes:

**Remote mode:** Copy the zips from the user's bucket to the managed source bucket,
then submit jobs pointing to the managed copies:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SOURCE_BUCKET="atx-source-code-${ACCOUNT_ID}"

# List all zips in the user's bucket path
aws s3 ls s3://user-bucket/repos/ --recursive | grep '\.zip$'

# Copy each zip to the managed source bucket
aws s3 sync s3://user-bucket/repos/ s3://${SOURCE_BUCKET}/repos/ --exclude "*" --include "*.zip"
```

Then submit a batch job with one job per zip, each pointing to
`s3://${SOURCE_BUCKET}/repos/<filename>.zip`. The container handles zip extraction
automatically. See [custom-multi-transformation](custom-multi-transformation.md) for batch submission.
The managed source bucket has a 7-day lifecycle — copied zips auto-delete.

**Local mode:** Download and extract each zip locally:

```bash
mkdir -p ~/.aws/atx/custom/atx-agent-session/repos
aws s3 sync s3://user-bucket/repos/ ~/.aws/atx/custom/atx-agent-session/repos/ --exclude "*" --include "*.zip"
for zip in ~/.aws/atx/custom/atx-agent-session/repos/*.zip; do
  name=$(basename "$zip" .zip)
  unzip -qo "$zip" -d "$HOME/.aws/atx/custom/atx-agent-session/repos/${name}-$SESSION_TS/"
done
```

Use the extracted directories as `<repo-path>` for local execution. Standard local
mode limits apply (max 3 concurrent repos).

#### Private Repository Detection (Remote Mode)

**Always ask the user** — do NOT try to determine repo visibility yourself. Never
attempt to clone, curl, or probe a URL to check if it's public or private. Simply
ask the user. As soon as the user provides git URLs and remote mode is selected
(or likely), ask:

> "Are any of these repositories private? If so, the remote container needs
> credentials to clone them — I'll walk you through the setup."

Do NOT skip this question. Do NOT try to infer visibility by attempting a clone,
curl, or any other network request. Just ask.

If the user confirms repos are private, determine the credential type based on URL format:

First, resolve the region (use for all Secrets Manager commands below):

```bash
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}
REGION=${REGION:-us-east-1}
```

**For HTTPS URLs** — check whether a GitHub PAT is already configured:

```bash
aws secretsmanager describe-secret --secret-id "atx/github-token" --region "$REGION" 2>/dev/null \
  && echo "CONFIGURED" || echo "NOT_CONFIGURED"
```

If CONFIGURED, ask the user: "A GitHub PAT is already stored. Would you like to
keep using it, or replace it with a new one?" If they want to replace it, tell
them to run:

```
aws secretsmanager put-secret-value --secret-id "atx/github-token" --region "$REGION" --secret-string "YOUR_TOKEN_HERE"
```

If NOT_CONFIGURED, explain what's needed and tell the user to run the create command:

> "Private HTTPS repos need a GitHub Personal Access Token (PAT) stored in AWS
> Secrets Manager. The remote container fetches it at startup to clone your repos.
> The token stays in your AWS account — you can delete it anytime.
>
> The PAT needs the `repo` scope for private repositories. Create one at
> https://github.com/settings/tokens and then run:
>
> ```
> aws secretsmanager create-secret --name "atx/github-token" --region "$REGION" --secret-string "YOUR_TOKEN_HERE"
> ```
>
> Delete anytime: `aws secretsmanager delete-secret --secret-id atx/github-token --region "$REGION" --force-delete-without-recovery`"

Do NOT ask the user to paste their token in chat. They run the command themselves.
Wait for the user to confirm it's done, then verify:

```bash
aws secretsmanager describe-secret --secret-id "atx/github-token" --region "$REGION" 2>/dev/null \
  && echo "CONFIGURED" || echo "NOT_CONFIGURED"
```

**For SSH URLs** (`git@...` or `ssh://...`) — check whether an SSH key is configured:

```bash
aws secretsmanager describe-secret --secret-id "atx/ssh-key" --region "$REGION" 2>/dev/null \
  && echo "CONFIGURED" || echo "NOT_CONFIGURED"
```

If CONFIGURED, ask the user: "An SSH key is already stored. Would you like to
keep using it, or replace it with a new one?" If they want to replace it, tell
them to run:

```
aws secretsmanager put-secret-value --secret-id "atx/ssh-key" --region "$REGION" --secret-string "$(cat <path-to-your-private-key>)"
```

If NOT_CONFIGURED, explain what's needed and tell the user to run the create command:

> "SSH repos need an SSH private key stored in AWS Secrets Manager. The remote
> container fetches it at startup to clone your repos.
>
> Run:
>
> ```
> aws secretsmanager create-secret --name "atx/ssh-key" --region "$REGION" --secret-string "$(cat <path-to-your-private-key>)"
> ```
>
> Delete anytime: `aws secretsmanager delete-secret --secret-id atx/ssh-key --region "$REGION" --force-delete-without-recovery`"

Do NOT ask the user to paste their SSH key in chat. They run the command themselves.

For local mode, private repo credentials are not needed — the user's local git
config handles authentication. Skip this check entirely for local mode.

### Discover Transformation Definitions (Silent)

Run silently — do NOT show output to user:

```bash
atx custom def list --json
```

Inspect the JSON output directly to build an internal lookup of available transformation definitions.
Do NOT pipe the output to python, jq, or other parsing scripts — read the JSON
yourself. Never hardcode transformation definition names.

#### Creating a New Transformation Definition

**User explicitly asks to create a transformation definition**, or **no existing transformation definition matches the user's goal**:

If no match, confirm with the user first:

> "I didn't find an existing transformation definition that covers [describe the user's goal]. Would
> you like to create a new one?"

If the user confirms (or explicitly asked), open a terminal and launch `atx -t`
for them:

```bash
atx -t
```

Run this in a new terminal so the user can interact with it directly. Then tell
the user:

> "I've opened a terminal with `atx -t` — describe the transformation you want
> to build (e.g., 'migrate log4j to SLF4J') and AWS Transform will walk you through it.
> Come back here once it's published and I'll pick it up automatically."

After the user returns, re-run `atx custom def list --json` to pick up the newly
published transformation definition and continue with the normal workflow.

### Inspect Each Repository

Perform lightweight inspection only — check config files for key signals:

| Signal          | Files to Check                                                                        | Likely Transformation Type |
| --------------- | ------------------------------------------------------------------------------------- | -------------------------- |
| Python version  | `.python-version`, `pyproject.toml`, `setup.cfg`, `requirements.txt`                  | Python version upgrade     |
| Java version    | `pom.xml` (`<java.version>`), `build.gradle` (`sourceCompatibility`), `.java-version` | Java version upgrade       |
| Node.js version | `package.json` (`engines.node`), `.nvmrc`, `.node-version`                            | Node.js version upgrade    |
| Python boto2    | `import boto` (NOT boto3)                                                             | boto2->boto3 migration     |
| Java SDK v1     | `com.amazonaws` imports, `aws-java-sdk` in pom.xml                                    | Java SDK v1->v2            |
| Node.js SDK v2  | `"aws-sdk"` in package.json (NOT `@aws-sdk`)                                          | JS SDK v2->v3              |
| x86 Java        | `x86_64`/`amd64` in Dockerfiles, build configs                                        | Graviton migration         |

Cross-reference detected signals against transformation definitions from the discovery step. Only match transformation definitions that
actually exist in the user's account.

See [custom-repo-analysis](custom-repo-analysis.md) for full detection commands.

### Present Match Report

Format:

```
Transformation Match Report
=============================
Repository: <name> (<path>)
  Language: <lang> <version>
  Matching transformation definitions:
    - <td-name> — <description>

Summary: N repos analyzed, M have applicable transformations (T total jobs)
```

Present the match report and wait for user confirmation before proceeding.
Do NOT start any transformation without explicit user consent.

### Collect Configuration

Ask the user for any additional plan context (e.g., target version for upgrade transformation definitions).
This is mandatory — always ask, even if the transformation definition doesn't strictly require config.
The user may have preferences or constraints you don't know about.
Skip only if the user explicitly says no additional context is needed.

### Verify Runtime Compatibility (Remote and Local)

#### Remote Mode

**Infrastructure check:** To verify whether remote infrastructure is deployed, use CloudFormation — do NOT check individual Lambda functions by name:

```bash
aws cloudformation describe-stacks --stack-name AtxInfrastructureStack \
  --query 'Stacks[0].StackStatus' --output text || echo "NOT_DEPLOYED"
```

Before submitting remote jobs, determine whether the pre-built image covers the
target runtime or if a custom Docker build is needed.

**Pre-built image includes:**

- **Java**: 8, 11, 17, 21, 25 (Amazon Corretto) with Maven and Gradle 9.4
- **Python**: 3.8, 3.9, 3.10, 3.11, 3.12, 3.13, 3.14 (dnf + pyenv)
- **Node.js**: 16, 18, 20, 22, 24 (nvm) with yarn, pnpm, TypeScript, ts-node
- **Build tools**: gcc, g++, make, patch
- **CLI tools**: AWS CLI v2, AWS Transform CLI, git, jq, curl, unzip, tar
- **OS**: Amazon Linux 2023 (x86_64)

**Decision logic:**

1. Based on the transformation requirements (source runtime, target runtime,
   build tools, and any other dependencies), determine whether everything
   needed is available in the pre-built image listed above
2. If **yes** -> use the pre-built image path (no Docker required). Proceed to deployment
   using the pre-built image instructions in [custom-remote-execution](custom-remote-execution.md).
3. If **no** -> use the custom image path (Docker required). Inform the user:

> The remote container doesn't include [language/tool version]. To run this
> transformation remotely, I'll need to build a custom container image. This
> requires Docker installed and running on your machine. It's a one-time change
> — about 5-10 minutes. Want me to proceed?

If the user confirms, follow the custom image path in
[custom-remote-execution](custom-remote-execution.md): clear `prebuiltImageUri`,
customize the Dockerfile, and deploy.

If the user declines, suggest local mode as an alternative (if the tools are
available on their machine).

**Dockerfile customization (custom image path only):**

First, read the Dockerfile to see what's installed:

```bash
ATX_INFRA_DIR="$HOME/.aws/atx/custom/remote-infra"
cat "$ATX_INFRA_DIR/container/Dockerfile" 2>/dev/null
```

1. Ensure the infrastructure repo is cloned and up to date:

   ```bash
   ATX_INFRA_DIR="$HOME/.aws/atx/custom/remote-infra"
   if [ -d "$ATX_INFRA_DIR" ]; then
     git -C "$ATX_INFRA_DIR" add -A
     git -C "$ATX_INFRA_DIR" commit -m "Local customizations" -q 2>/dev/null || true
     git -C "$ATX_INFRA_DIR" pull -q
   else
     git clone -b atx-remote-infra --single-branch https://github.com/aws-samples/aws-transform-custom-samples.git "$ATX_INFRA_DIR"
   fi
   ```

   If `git pull` reports a merge conflict, resolve it by keeping both upstream
   changes and the user's customizations in the `CUSTOM LANGUAGES AND TOOLS`
   section of the Dockerfile, then commit the merge.

2. Edit `$ATX_INFRA_DIR/container/Dockerfile`. Find the section marked
   `# CUSTOM LANGUAGES AND TOOLS` and insert `RUN` commands after the comment
   block, before the `USER root` line.

   For missing versions of already-installed languages, add the version in the
   custom section. Examples:

   ```dockerfile
   # Java 23 (Amazon Corretto — direct install, must run as root)
   # Do NOT use dnf in the custom section — pyenv overrides the system python3
   # that dnf depends on, causing "No module named 'dnf'" errors.
   USER root
   RUN curl -fsSL "https://corretto.aws/downloads/latest/amazon-corretto-23-x64-linux-jdk.tar.gz" -o /tmp/corretto23.tar.gz && \
       mkdir -p /usr/lib/jvm && \
       tar -xzf /tmp/corretto23.tar.gz -C /usr/lib/jvm && \
       rm /tmp/corretto23.tar.gz && \
       ln -sfn /usr/lib/jvm/amazon-corretto-23.* /usr/lib/jvm/corretto-23

   # Node.js 23 (via nvm — must run as atxuser)
   USER atxuser
   RUN . /home/atxuser/.nvm/nvm.sh && nvm install 23
   USER root

   # Python 3.15 (via pyenv — must run as atxuser)
   USER atxuser
   RUN eval "$(/home/atxuser/.pyenv/bin/pyenv init -)" && \
       MAKE_OPTS="-j$(nproc)" /home/atxuser/.pyenv/bin/pyenv install 3.15.0
   USER root
   ```

   For entirely new languages, avoid `dnf` in the custom section — pyenv
   overrides the system python3 that `dnf` depends on. Use language-specific
   installers instead:

   ```dockerfile
   # Go
   RUN curl -fsSL https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | tar -C /usr/local -xz
   ENV PATH="/usr/local/go/bin:$PATH"

   # Ruby (via rbenv — must run as atxuser)
   USER atxuser
   RUN git clone --depth 1 https://github.com/rbenv/rbenv.git /home/atxuser/.rbenv && \
       git clone --depth 1 https://github.com/rbenv/ruby-build.git /home/atxuser/.rbenv/plugins/ruby-build && \
       /home/atxuser/.rbenv/bin/rbenv install 3.3.0 && \
       /home/atxuser/.rbenv/bin/rbenv global 3.3.0
   ENV PATH="/home/atxuser/.rbenv/shims:/home/atxuser/.rbenv/bin:$PATH"
   USER root

   # Rust
   USER atxuser
   RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
   ENV PATH="/home/atxuser/.cargo/bin:$PATH"
   USER root
   ```

3. Update the version switcher in `$ATX_INFRA_DIR/container/entrypoint.sh`.
   Find the relevant `switch_*_version` function and add a case for the new
   version. For Java versions installed via direct download, find the extracted
   directory name under `/usr/lib/jvm/`. For example, to add Java 23:

   ```bash
   # In switch_java_version(), add to the case statement:
   23) java_home="/usr/lib/jvm/corretto-23" ;;
   ```

   Check the actual directory name: `ls /usr/lib/jvm/` — use the directory
   that matches the version you installed.

   For Node.js, nvm handles arbitrary versions automatically — no entrypoint
   change needed. For Python, pyenv handles arbitrary versions — no entrypoint
   change needed (the existing pyenv fallback logic finds it).

4. Deploy (or redeploy): `cd "$ATX_INFRA_DIR" && ./setup.sh`
   CDK hashes the `container/` directory — any file change triggers a rebuild
   and push to ECR automatically.

After redeployment, set the `environment` field on the job to the exact target
version (e.g., `"JAVA_VERSION":"23"`, not `"21"`). The version switcher in the
entrypoint reads this and activates the correct runtime.

If the user declines, suggest local mode as an alternative (if the tools are
available on their machine).

#### Local Mode

Before running local transformations, verify the user has the target runtime
version installed. This applies to any language or runtime the transformation
targets — Java, Python, Node.js, Ruby, Go, Rust, .NET, etc. Check the current
version of whatever runtime the transformation definition requires. For example:

```bash
java -version    # Java transformations
python3 --version # Python transformations
node --version   # Node.js transformations
ruby --version   # Ruby transformations
go version       # Go transformations
```

If the target version is not active, check whether it's already installed:

```bash
# Java: check common install locations
/usr/libexec/java_home -V 2>&1          # macOS
ls /usr/lib/jvm/ 2>/dev/null            # Linux
# Python: check if the specific version binary exists
which python3.12 2>/dev/null            # adjust version as needed
# Node.js: check if nvm is available, or look for the binary
command -v nvm &>/dev/null && nvm ls 2>/dev/null
which node 2>/dev/null && node --version
```

If the target version is found, switch to it:

- Java: `export JAVA_HOME=<path to JDK> && export PATH="$JAVA_HOME/bin:$PATH"`
- Python: `pyenv shell 3.15.0`
- Node.js: `nvm use 23`

Only if the target version is not installed at all, ask the user for permission before installing. Do NOT install runtimes without explicit user confirmation.
Suggest the appropriate version manager:

- Java: `brew install --cask corretto23` (macOS), `sudo yum install java-23-amazon-corretto-devel` (RHEL/AL2), or `sudo apt install java-23-amazon-corretto-jdk` (Debian/Ubuntu)
- Python: `pyenv install 3.15.0 && pyenv shell 3.15.0`, or `brew install python@3.15`
- Node.js: `nvm install 23 && nvm use 23`

The active runtime must match the transformation's target version so that builds
and tests run correctly. Do NOT proceed with the transformation until the correct
version is active.

### Confirm Transformation Plan

Present final plan with repo, transformation definition, config, and execution mode. Do NOT proceed
until user confirms.

### Execute

- **1 repo**: See [custom-single-transformation](custom-single-transformation.md)
- **Multiple repos**: See [custom-multi-transformation](custom-multi-transformation.md)

## Execution Modes

| Mode                                   | Best For                                                    | Prerequisites                    |
| -------------------------------------- | ----------------------------------------------------------- | -------------------------------- |
| **Local** (default for 1-9 repos)      | Quick transforms, dev machines with ATX                     | AWS Transform CLI installed      |
| **Remote** (recommended for 10+ repos) | Bulk transforms, up to 512 repos (128 concurrent per batch) | AWS account, auto-deployed infra |

Mode inference:

- User says "local"/"here"/"on my machine" -> Local (honor the request regardless of repo count)
- User says "remote"/"cloud"/"AWS"/"batch"/"at scale" -> Remote
- 10+ repos without preference -> Recommend remote, explain local cap recommendation of 3 concurrent
- 1-9 repos without preference -> Local, note remote available

See [custom-remote-execution](custom-remote-execution.md) for infrastructure setup.

## Critical Rules

1. **Discover transformation definitions dynamically** — Always run `atx custom def list --json`. Never hardcode transformation definition names.
2. **Match, don't ask** — Inspect repos and present matches. Never show raw transformation definition lists.
3. **Lightweight inspection only** — Check config files and key signals. No deep analysis.
4. **Confirm before executing** — Always confirm transformation definition, repos, and config with user first.
5. **No time estimates** — Never include duration predictions.
6. **Parallel execution** — Local: max 3 concurrent repos. Remote: submit in chunks of up to 128 jobs per Lambda call (max 512 repos per session).
7. **Preserve outputs** — Do not delete generated output folders.
8. **Recommend remote for 10+ repos** — Default to local for 1-9 repos. Recommend remote for 10+. Always respect user preference.
9. **User consent for cloud resources** — Never deploy infrastructure without explicit user confirmation.
10. **Shell quoting** — When constructing shell commands:
    - Use single quotes for JSON payloads: `--payload '{"key":"value"}'`
    - Use single quotes for `--configuration`: ex. `--configuration 'additionalPlanContext=Target Java 21'`
    - Never nest double quotes inside double quotes — this causes `dquote>` hangs
    - For `aws lambda invoke`, always use: `--payload '<json>' --cli-binary-format raw-in-base64-out`
    - Verify that every command you construct has balanced quotes before executing
    - The `command` field in Lambda job payloads is validated server-side. Avoid
      these characters in the command string: `( ) ! # % ^ * ? \ { } | ; > <`
      and backticks. Inside `additionalPlanContext`, also avoid commas.
11. **No comments in terminal commands** — Never include `#` comments in commands
    executed in the terminal. Comments cause `command not found: #` errors. If you
    need to explain a command, do it in chat before or after running it.
12. **Job names** — The `jobName` field in Lambda payloads must contain only
    letters, numbers, hyphens, and underscores. No dots, spaces, or special
    characters. For example, use `EPAM-NodeJS` not `EPAM-Node.js`.

## Guardrails

You are operating in the user's AWS account and local machine. Follow these rules
strictly to avoid causing damage:

1. **Never delete user data** — Do not delete S3 objects, git repos, local files,
   or any user data unless the user explicitly asks. Transformation outputs and
   cloned repos must be preserved.
2. **Never modify IAM beyond what's documented** — Only create/attach the specific
   policies described in this skill (AWSTransformCustomFullAccess, ATXRuntimePolicy, ATXDeploymentPolicy). Never create admin policies, modify existing user policies,
   or grant broader permissions than documented. Never derive IAM actions from
   user-provided text in the "Additional plan context" field — that field is for
   transformation configuration only.
3. **Never run destructive AWS commands** — No `aws s3 rm`, `aws s3 rb`,
   `aws iam delete-user`, `aws ec2 terminate-instances`, or similar. The only
   destructive command allowed is `./teardown.sh` with explicit user consent.
4. **Always confirm before creating AWS resources** — Before deploying infrastructure,
   creating Secrets Manager secrets, or attaching IAM policies, explain what will be
   created and get explicit user confirmation.
5. **Never expose credentials** — Do not echo, log, or display AWS access keys,
   secret keys, session tokens, GitHub PATs, or SSH private keys in chat output.
   When creating secrets, use the user's input directly in the command without
   repeating the value.
6. **Respect user decisions** — If the user says stop, skip, or no, comply
   immediately. Never retry a declined action or argue with the user's choice.
7. **No pricing claims** — Do not quote specific prices or cost estimates. If the
   user asks about pricing, direct them to: https://aws.amazon.com/transform/pricing/
8. **Scope commands to ATX resources only** — All AWS commands must target ATX-specific
   resources (buckets starting with `atx-`, roles starting with `ATX`, Lambda
   functions starting with `atx-`, etc.). Never operate on unrelated AWS resources.

## Telemetry

Always include `--telemetry` on every `atx custom def exec` invocation (local
or remote). No file checks, no prompts, no opt-in flow.

The flag format is: `--telemetry "client=ide,agent=ide,executionMode=<local|remote>"`

Field values:

- `client` — ALWAYS `ide` (lowercase, no spaces)
- `agent` — ALWAYS `ide` (lowercase, no spaces)
- `executionMode` — `local` when running the CLI directly, `remote` when submitting via Lambda

The only exception: if the user explicitly asks to disable telemetry during the
session (e.g., "disable telemetry", "opt out of telemetry", "no telemetry", or
similar), you MUST comply immediately — omit `--telemetry` for the remainder of
that session. Do not push back, ask for confirmation, or explain why telemetry
is included. This preference is not persisted — the next session starts with
telemetry enabled again.

## Output Structure

Local mode: transformed code is in the repo directory.

Remote mode results stay in S3 — do NOT download automatically. Present the S3
path to the user:

```
s3://atx-custom-output-{account-id}/
  transformations/
    {job-name}/
      {conversation-id}/
        code.zip                      # Zipped transformed source code
        logs.zip                      # AWS Transform conversation logs
```

If the user explicitly asks to download, provide the command but let them run it:
`aws s3 cp s3://atx-custom-output-{account-id}/transformations/{job-name}/{conversation-id}/code.zip ./code.zip`

Bulk results summary: `~/.aws/atx/custom/atx-agent-session/transformation-summaries/` — see [custom-results-synthesis](custom-results-synthesis.md).

## References

| Reference                                                       | When to Use                                                          |
| --------------------------------------------------------------- | -------------------------------------------------------------------- |
| [custom-repo-analysis](custom-repo-analysis.md)                 | Detection commands, signal matching, match report format             |
| [custom-single-transformation](custom-single-transformation.md) | Applying one transformation definition to one repo (local or remote) |
| [custom-multi-transformation](custom-multi-transformation.md)   | Applying transformation definitions to multiple repos in parallel    |
| [custom-remote-execution](custom-remote-execution.md)           | Infrastructure deployment, job submission, monitoring                |
| [custom-results-synthesis](custom-results-synthesis.md)         | Generating consolidated reports after bulk transforms                |
| [custom-cli-reference](custom-cli-reference.md)                 | AWS Transform CLI flags, commands, env vars, IAM permissions         |
| [custom-troubleshooting](custom-troubleshooting.md)             | Error resolution, debugging, quality improvement                     |

## License

AWS Service Terms. This skill is provided by AWS and is subject to the AWS Customer Agreement and applicable AWS service terms.

## Issues

https://github.com/awslabs/agent-plugins/issues

## Changelog

Share if the user asks what changed, what's new, etc.

### [1.0.0] - 2026-04-14

- Initial release of the AWS Transform skill
- Supported transformation definitions:
  - AWS/java-version-upgrade
  - AWS/python-version-upgrade
  - AWS/nodejs-version-upgrade
  - AWS/java-aws-sdk-v1-to-v2
  - AWS/nodejs-aws-sdk-v2-to-v3
  - AWS/python-boto2-to-boto3
  - AWS/comprehensive-codebase-analysis
  - AWS/java-performance-optimization
  - AWS/angular-version-upgrade
  - AWS/vue.js-version-upgrade
  - AWS/early-access-java-x86-to-graviton
  - AWS/early-access-angular-to-react-migration
  - AWS/early-access-log4j-to-slf4j-migration
