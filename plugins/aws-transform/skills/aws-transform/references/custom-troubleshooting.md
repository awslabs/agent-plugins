# Troubleshooting

## Quick Reference

| Issue                                                              | Resolution                                                                                                                                                                                                                         |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `atx` not found                                                    | Install: `curl -fsSL https://transform-cli.awsstatic.com/install.sh` piped to `bash` (Windows PowerShell: `irm https://transform-cli.awsstatic.com/install.ps1` piped to `iex`)                                                    |
| AWS credentials error or expiry                                    | Run `aws sts get-caller-identity`. Check `AWS_PROFILE` or access key env vars                                                                                                                                                      |
| Permission denied                                                  | Local mode: need `transform-custom:*` — see Prerequisites -> IAM Permissions in [custom](custom.md). Remote mode: Admin and Executor roles — see Remote Mode Caller Permissions in [custom-cli-reference](custom-cli-reference.md) |
| Network error                                                      | Resolve region: `REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}; REGION=${REGION:-us-east-1}`. Check access to `transform-custom.${REGION}.api.aws`                                          |
| Build fails during transform                                       | Verify build command works locally first. Try interactive mode for debugging                                                                                                                                                       |
| Transform not found                                                | Run `atx custom def list --json` to check available transformation definitions                                                                                                                                                     |
| Transformation definition download fails (`def get`, `def exec`)   | The CLI downloads it from the AWS Transform endpoint. To download from an Amazon S3 URL instead (needs network access to Amazon S3), set `ATX_STREAMING_DOWNLOAD=0`                                                                |
| Configuration fails with commas                                    | Do not use commas inside `additionalPlanContext` values — they break the CLI parser. Rephrase to avoid commas                                                                                                                      |
| Conversation expired                                               | Conversations expire after 30 days. Start a new one                                                                                                                                                                                |
| Problems on native Windows                                         | The CLI runs natively on Windows, but this workflow runs bash scripts, so it needs Windows Subsystem for Linux (WSL). See the Platform Check                                                                                       |
| Run exits with code 2                                              | The `--limit` Agent Minutes budget was reached. Resume with a higher `--limit`                                                                                                                                                     |
| Run exits with code 130, 143, or 129                               | The run was stopped by Ctrl+C, SIGTERM, or a closed terminal. It did not finish; resume or re-run it                                                                                                                               |
| Remote run fails to clone or push                                  | See "Remote Source Token Issues" section below                                                                                                                                                                                     |
| Remote submission rejects the transformation definition's category | Republish it with `--category remediation` — see Job Submission in [custom-remote-execution](custom-remote-execution.md)                                                                                                           |
| Timeout                                                            | Set `export ATX_SHELL_TIMEOUT=1800` (default: 900s)                                                                                                                                                                                |
| Stale .exit file                                                   | The `.exit` file in `atx-agent-session/` may be left over from a previous run. Always use `kill -0 <pid>` to check if the process is still running — do not rely solely on the `.exit` file                                        |
| Poor quality results                                               | See Improving Quality section below                                                                                                                                                                                                |

## Remote Source Token Issues

If a remote job fails to clone or push (status failed, logs show authentication or 403
errors), work through these steps with the user. Never ask the user to paste a token
into this chat; give them the command to run in their own terminal.

**1. Is the token stored for remote execution?**

```bash
AWS_REGION=<region> atx ct source list --json
aws secretsmanager describe-secret --secret-id "atx/<source>/<provider>-token" --region <region> 2>/dev/null && echo "EXISTS" || echo "MISSING"
```

If missing, the user stores it with admin credentials:

```bash
read -s TOKEN && AWS_REGION=<region> atx ct remote credentials --source <source> --token "$TOKEN" --ack; unset TOKEN
```

**2. Does the token have the right scope?**
GitHub fine-grained tokens can be scoped to specific repos. If the user created a
token for repos A and B but is now transforming repo C, the clone will fail with 403.
Ask: "Does your token have access to [repo name]? Fine-grained tokens need
each repo explicitly listed." Required scopes per provider are in
[continuous-modernization-source](continuous-modernization-source.md#commands).

**3. Has the token expired?**
Tokens can have expiration dates. Ask: "When did you create this token? It may
have expired."

For 2 and 3, the user updates or creates the token with the provider, then updates the
source, which also updates the stored secret:

```bash
read -s TOKEN && AWS_REGION=<region> atx ct source update --name <source> --token "$TOKEN"; unset TOKEN
```

**4. Is the repository in the source?**
A remote run only reaches repositories under the registered org, group, or workspace.
Check with `atx ct repository list --source <source> --json`; re-run
`atx ct discovery scan --source <source>` after adding repos. SSH URLs and other git
hosts are not sources: clone those locally and register the parent folder as a local
source.

**5. Classic vs fine-grained GitHub token?**
Classic tokens with `repo` scope work for all repos the user has access to.
Fine-grained tokens need each repo explicitly added. If the user is unsure, suggest
a classic token with `repo` scope as the simpler option.

**6. Was the push rejected by a repository rule?**
Set the commit message or branch name template the repository requires on the source.
See "Optional: shape the commits and branches a remediation produces" in
[continuous-modernization-source](continuous-modernization-source.md).

## Local Mode Debugging

| Log              | Path                                                                    |
| ---------------- | ----------------------------------------------------------------------- |
| Developer logs   | `~/.aws/atx/logs/debug*.log` and `~/.aws/atx/logs/error.log`            |
| Conversation log | `~/.aws/atx/custom/<conversation_id>/logs/<timestamp>-conversation.log` |

Network errors may indicate VPN/firewall issues with AWS endpoints.

## Remote Mode Debugging

- `atx ct remote status --batch <batch-id> --stack-name <stack> --verbose` (Batch) or
  `--group <group-id> --verbose` (EC2) shows each job's state and why a queued job waits
- `atx ct remediation status --id <remediation-id> --json` shows per-repository results
- CloudWatch logs: Batch, the stack's `logGroupName` from `atx ct remote detect --mode batch --stack-name <stack> --json`;
  EC2, the log group `/atx/ct/ec2/<stackName>`
- The S3 output bucket contains artifacts even for failed jobs

## Deployment Failures

The CLI prints the cause of a failed `atx ct remote provision` or `update`. Fix it and
re-run the same command. Common errors and fixes are in Error Handling in
[continuous-modernization-batch-execution](continuous-modernization-batch-execution.md#error-handling)
and
[continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md#error-handling).
If the stack is left in a failed state, it has to be torn down and provisioned again.
Get the user's consent, show the preview, then give the user the command to run in
their own terminal with admin credentials. You MUST NOT run it yourself:

```bash
AWS_REGION=<region> atx ct remote teardown --mode <batch|ec2> --stack-name <stack>
AWS_PROFILE=<your-admin-profile> AWS_REGION=<region> atx ct remote teardown --mode <batch|ec2> --stack-name <stack> --execute --ack
```

Common causes: insufficient IAM permissions, service quota limits, public subnets
(remote compute needs private subnets with NAT), missing `--securityGroup` for Batch,
Docker not running (only needed to build a custom container image).

## Improving Quality

Diagnose in this order:

1. **Reference materials**: Provide migration guides or API specs via `additionalPlanContext`.
2. **Complexity**: Decompose very complex transforms into smaller steps.
3. **Knowledge items**: Review learnings from previous runs. Enable good ones, disable irrelevant ones.

## Network Requirements

| Endpoint                                      | Purpose                      |
| --------------------------------------------- | ---------------------------- |
| `transform-cli.awsstatic.com`                 | CLI installation and updates |
| `desktop-release.transform.us-east-1.api.aws` | Fallback for CLI updates     |
| `transform-custom.${REGION}.api.aws`          | Transformation service API   |

## Pre-built Container Image

The default pre-built image URI is `public.ecr.aws/d9h8z6l7/aws-transform:latest`.
`atx ct remote provision` uses it unless `--image-uri` is given.

## Infrastructure From the Earlier Setup Script

Remote infrastructure used to be deployed from a sample repository with `setup.sh`.
That repository and its scripts are no longer used; do not clone it or run its
scripts. A Batch stack it deployed (`AtxInfrastructureStack`) shows up in
`atx ct remote detect --mode batch`. Bring it up to date with
`atx ct remote update --mode batch --stack-name AtxInfrastructureStack` (preview). After
the user consents, give them the same command with `--execute --ack` to run with admin
credentials (`AWS_PROFILE=<your-admin-profile>`). The update works in place on such a
stack when its status is `CREATE_COMPLETE`, `UPDATE_COMPLETE` or `UPDATE_ROLLBACK_COMPLETE`;
it reads the VPC, subnets and security group from the deployed template. If the update
fails or the stack is in any other status, the user tears it
down the same way (see [Deployment Failures](#deployment-failures)) and provisions again.
