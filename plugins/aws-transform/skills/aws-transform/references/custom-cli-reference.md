# AWS Transform CLI Reference

## Execution Flags (`atx custom def exec`)

| Flag   | Long Form                        | Description                                                                                             |
| ------ | -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `-n`   | `--transformation-name <name>`   | Transformation definition name (from `atx custom def list --json`)                                      |
| `-p`   | `--code-repository-path <path>`  | Path to code repo (`.` for current dir)                                                                 |
| `-c`   | `--build-command <command>`      | Command to run when building the repository                                                             |
| `-x`   | `--non-interactive`              | No user prompts (always use this flag)                                                                  |
| `-t`   | `--trust-all-tools`              | Auto-approve tool executions (required with `-x`)                                                       |
| `-q`   | `--quiet`                        | Mute output from auto-approved tools                                                                    |
| `-d`   | `--do-not-learn`                 | Prevent knowledge item extraction                                                                       |
| `-g`   | `--configuration <config>`       | Config file (JSON or YAML) or inline `key=value` pairs (`'key=val'`)                                    |
| `--tv` | `--transformation-version <ver>` | Specific transformation definition version                                                              |
|        | `--limit <minutes>`              | Agent Minutes budget; the run exits with code 2 when it is reached (resume with a higher `--limit`)     |
|        | `--classic`                      | Line-oriented output instead of the terminal UI (automatic when output is redirected to a file or pipe) |

## Configuration

Inline: `--configuration 'additionalPlanContext=Target Python 3.13'`

Example: `atx custom def exec -n my-td -p <repo-path> -g 'additionalPlanContext=Target Java 17' -x -t`

- See [custom-single-transformation](custom-single-transformation.md) and [custom-multi-transformation](custom-multi-transformation.md) for how to wrap this around a runner/launcher script to ensure this is executed in a non-blocking way, so that user is updated while the process is running instead of having to wait until it exits.

`--configuration` is optional. Omit if no extra context needed.

## Other Commands

| Action                                         | Command                                                                                                                                                                         |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Start interactive conversation                 | `atx`                                                                                                                                                                           |
| Resume most recent conversation                | `atx --resume`                                                                                                                                                                  |
| Resume specific conversation                   | `atx --conversation-id <id>` (30-day limit)                                                                                                                                     |
| Set an Agent Minutes budget for a conversation | `atx --limit <minutes>` (also with `--resume` or `--conversation-id`)                                                                                                           |
| Show CLI version                               | `atx --version`                                                                                                                                                                 |
| List transformation definitions                | `atx custom def list --json`                                                                                                                                                    |
| Download transformation definition             | `atx custom def get -n <name>` (optional: `--tv <version>`, `--td <directory>`). AWS-managed (`AWS/...`) definitions can't be downloaded                                        |
| Delete transformation definition               | `atx custom def delete -n <name>`                                                                                                                                               |
| Save as draft                                  | `atx custom def save-draft -n <name> --description "<desc>" --sd <dir>` (optional: `--category analysis` or `remediation`)                                                      |
| Publish transformation definition              | `atx custom def publish -n <name> --description "<desc>" --sd <dir>` (optional: `--category analysis` or `remediation`)                                                         |
| Publish an existing version                    | `atx custom def publish -n <name> --tv <version>`                                                                                                                               |
| List knowledge items                           | `atx custom def list-ki -n <name>`                                                                                                                                              |
| View knowledge item                            | `atx custom def get-ki -n <name> --id <id>`                                                                                                                                     |
| Enable/disable KI                              | `atx custom def update-ki-status -n <name> --id <id> --status ENABLED or DISABLED`                                                                                              |
| KI auto-approval on/off                        | `atx custom def update-ki-config -n <name> --auto-enabled TRUE or FALSE`                                                                                                        |
| Export KIs                                     | `atx custom def export-ki-markdown -n <name>`                                                                                                                                   |
| Delete KI                                      | `atx custom def delete-ki -n <name> --id <id>`                                                                                                                                  |
| View and manage automated learnings            | `atx custom def learnings -n <name>` (interactive; `--json` for non-interactive output)                                                                                         |
| Update CLI                                     | `atx update`                                                                                                                                                                    |
| Check for CLI updates only                     | `atx update --check`                                                                                                                                                            |
| Update CLI to a specific version               | `atx update --target-version <version>`                                                                                                                                         |
| Reinstall even if already on latest            | `atx update --force`                                                                                                                                                            |
| List configured MCP servers and their tools    | `atx mcp tools` (optional: `-s <server-id>`)                                                                                                                                    |
| Programmatic NDJSON session over stdio         | `atx json` (optional: `-g <config>`)                                                                                                                                            |
| List tags                                      | `atx custom def list-tags --arn <arn>`                                                                                                                                          |
| Tag a transformation definition                | `atx custom def tag --arn <arn> --tags '{"key":"value"}'`                                                                                                                       |
| Remove tags                                    | `atx custom def untag --arn <arn> --tag-keys <key1,key2>`                                                                                                                       |
| Run a transformation definition remotely       | `atx ct remote remediation --transformation-name <name> --repos <source>::<repo> --mode batch --stack-name <stack>` — see [custom-remote-execution](custom-remote-execution.md) |

## Environment Variables

| Variable                                             | Default                        | Description                                                                                                                        |
| ---------------------------------------------------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `ATX_SHELL_TIMEOUT`                                  | 900 (15 min)                   | Shell command timeout in seconds                                                                                                   |
| `ATX_DISABLE_UPDATE_CHECK`                           | false                          | Disable version check                                                                                                              |
| `ATX_DISABLE_TELEMETRY`                              | false                          | `true` turns off usage telemetry during transformation execution                                                                   |
| `ATX_CLASSIC`                                        | —                              | `1` is the same as `--classic`                                                                                                     |
| `ATX_GIT_COMMITTER_NAME` / `ATX_GIT_COMMITTER_EMAIL` | `ATX Bot <checkpoint@atx.bot>` | Author identity for the CLI's checkpoint commits                                                                                   |
| `ATX_STREAMING_DOWNLOAD`                             | on                             | `0` makes `def get` and `def exec` download transformation definitions from an Amazon S3 URL instead of the AWS Transform endpoint |
| `AWS_PROFILE`                                        | —                              | AWS credentials profile                                                                                                            |
| `AWS_ACCESS_KEY_ID`                                  | —                              | AWS access key                                                                                                                     |
| `AWS_SECRET_ACCESS_KEY`                              | —                              | AWS secret key                                                                                                                     |
| `AWS_SESSION_TOKEN`                                  | —                              | Session token (temporary credentials)                                                                                              |

## IAM Permissions

Minimum: `transform-custom:*` on `Resource: "*"`.

| Permission                                             | Operation                                                                                          |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| `transform-custom:ConverseStream`                      | Interactive conversations                                                                          |
| `transform-custom:ExecuteTransformation`               | Execute transforms                                                                                 |
| `transform-custom:ListTransformationPackageMetadata`   | List transforms (`atx custom def list --json`)                                                     |
| `transform-custom:DeleteTransformationPackage`         | Delete transforms                                                                                  |
| `transform-custom:CompleteTransformationPackageUpload` | Upload transformation definitions                                                                  |
| `transform-custom:CreateTransformationPackageUrl`      | Create upload URLs                                                                                 |
| `transform-custom:GetTransformationPackageUrl`         | Download transformation definitions (`def get`, `def exec`), by streaming or from an Amazon S3 URL |
| `transform-custom:ListKnowledgeItems`                  | List knowledge items                                                                               |
| `transform-custom:GetKnowledgeItem`                    | View knowledge item details                                                                        |
| `transform-custom:DeleteKnowledgeItem`                 | Delete knowledge items                                                                             |
| `transform-custom:UpdateKnowledgeItemConfiguration`    | Configure auto-approval                                                                            |
| `transform-custom:UpdateKnowledgeItemStatus`           | Enable/disable items                                                                               |
| `transform-custom:ListTagsForResource`                 | List tags                                                                                          |
| `transform-custom:TagResource`                         | Add tags                                                                                           |
| `transform-custom:UntagResource`                       | Remove tags                                                                                        |

### Remote Mode Caller Permissions

Remote mode uses two roles. The Executor role also needs `transform-custom:*`.

| Role                  | Commands                                                                         | Policy                           |
| --------------------- | -------------------------------------------------------------------------------- | -------------------------------- |
| Admin (one-time)      | `atx ct remote provision`, `update`, `teardown`, `credentials`, `network create` | Admin permissions in the account |
| Executor (day-to-day) | `atx ct remote remediation`, `status`, `cancel`, `detect`, `network discover`    | The Executor policy for the mode |

See Permission Model in
[continuous-modernization-batch-execution](continuous-modernization-batch-execution.md#permission-model)
(Batch) or
[continuous-modernization-ec2-execution](continuous-modernization-ec2-execution.md#permission-model)
(EC2) for the Executor policy. The user creates and attaches it; do not attach IAM
policies yourself.
