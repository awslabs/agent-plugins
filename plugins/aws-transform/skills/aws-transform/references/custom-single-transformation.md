# Single Transformation

Apply one transformation definition to one repo. Transformation definition, config, and repo are already confirmed from the match report.

## Table of Contents

- [Local Mode](#local-mode)
- [Remote Mode](#remote-mode)
- [Error Handling](#error-handling)
- [MANDATORY: Cleanup](#mandatory-cleanup)

## Local Mode

### Verify AWS Transform CLI (once per session, skip if already verified)

```bash
atx --version
```

### Verify Language Version

The active language runtime must match the transformation's target version so that builds and tests run correctly. For example, a Java 8 -> 17 upgrade needs Java 17 available locally.

Check the installed version matches the target:

```bash
java -version    # Java transformations
python3 --version # Python transformations
node --version   # Node.js transformations
```

If there is a mismatch, resolve it before proceeding:

- Look for the correct version already installed (e.g., check `/usr/lib/jvm/`, `pyenv versions`, `nvm ls`)
- If found, switch to it (e.g., `export JAVA_HOME=<path to JDK> && export PATH="$JAVA_HOME/bin:$PATH"`, `pyenv shell 3.12`, `nvm use 22`)
- If not installed, ask the user for permission before installing (e.g., `brew install --cask corretto17` (macOS), `sudo yum install java-17-amazon-corretto-devel` (RHEL/AL2), or `sudo apt install java-17-amazon-corretto-jdk` (Debian/Ubuntu), `pyenv install 3.12`, `nvm install 22`)
- Verify the switch succeeded by re-checking the version before continuing

### Prepare Source

If the user provided a git URL (HTTPS or SSH) instead of a local path, clone it
locally first. The user's local git config handles authentication for private repos
— no Secrets Manager setup needed in local mode.

```bash
CLONE_DIR=~/.aws/atx/custom/atx-agent-session/repos/<repo-name>-$SESSION_TS
git clone <git-url> "$CLONE_DIR"
```

If the user provided an S3 path to a zip, download and extract it locally:

```bash
aws s3 cp s3://user-bucket/repos/<project>.zip ~/.aws/atx/custom/atx-agent-session/<project>-$SESSION_TS.zip
unzip -qo ~/.aws/atx/custom/atx-agent-session/<project>-$SESSION_TS.zip -d ~/.aws/atx/custom/atx-agent-session/repos/<project>-$SESSION_TS/
```

Use the cloned/extracted path as `<repo-path>` for all subsequent steps. If the
user provided a local path, use it directly.

### Validate Repository

```bash
ls -la <repo-path>
git -C <repo-path> status
```

If not a git repo: `cd <repo-path> && git init && git add . && git commit -m "Initial commit"`

### Telemetry

When running `atx custom def exec`, always include the `--telemetry` flag (see the Telemetry section in [custom](custom.md)). Format:
`--telemetry "client=<client>,agent=<agent>,executionMode=local"`

- `client` is the MCP host for this session (lowercase, no spaces) — e.g., `kiro`, `vscode`, `cursor`, `windsurf`, `claudecode`, `amazonqcli`. Use the real host name; do not default to any example.
- `agent` is the AI assistant for this session (lowercase, no spaces) — e.g., `kiro`, `amazonq`, `claude`, `copilot`, `cline`, `codex`. Use the real assistant name; do not default to any example.
- `executionMode` is `local` for direct CLI invocation

For `atx ct remote remediation`, use `--telemetry "agent=<agent>,executionMode=<fargate|ec2>"`
instead (`fargate` for Batch, `ec2` for EC2). The CLI adds its own `client`.

### Execute and Monitor

If the user is transforming the currently opened workspace project, `cd` into it
and run `pwd` to confirm the absolute path before using it with `-p`.

Launch the transformation in a way that returns control immediately. Some shell
tools block until all child processes exit, even with `&`. To avoid this, use bash to write
a launcher script and execute it, using exactly this:

```bash
mkdir -p ~/.aws/atx/custom/atx-agent-session
cat > ~/.aws/atx/custom/atx-agent-session/run.sh << 'RUNNER'
#!/bin/bash
atx custom def exec -n <td-name> -p <repo-path> -x -t \
  --configuration 'additionalPlanContext=<user-config>' \
  --telemetry "client=<client>,agent=<agent>,executionMode=local"
echo $? > ~/.aws/atx/custom/atx-agent-session/transform.exit
RUNNER
chmod +x ~/.aws/atx/custom/atx-agent-session/run.sh
nohup ~/.aws/atx/custom/atx-agent-session/run.sh > ~/.aws/atx/custom/atx-agent-session/transform.log 2>&1 &
echo $! > ~/.aws/atx/custom/atx-agent-session/transform.pid
cat ~/.aws/atx/custom/atx-agent-session/transform.pid
```

Omit `--configuration` if no config is needed. If the user wants to cap usage, add
`--limit <minutes>` (Agent Minutes budget; the run exits with code 2 when it is reached). The `--telemetry` flag is always included — see [custom](custom.md) for details.

This backgrounds the runner script (not the CLI directly), so the exit code is
captured to `~/.aws/atx/custom/atx-agent-session/transform.exit` when AWS Transform finishes. The PID file tracks
the runner process.

**As soon as you have the PID, immediately run the next command** — do NOT stop
and wait for the user. The AWS Transform CLI outputs the conversation log path within
30-60 seconds of starting. Read it from the process log:

```bash
grep "Conversation log:" ~/.aws/atx/custom/atx-agent-session/transform.log 2>/dev/null
```

If it hasn't appeared yet, wait 15 seconds and retry (up to 4 attempts). The
output looks like:

```
Conversation log: /Users/<user>/.aws/atx/custom/20260319_063712_e3479843/logs/2026-03-19T06-37-26-conversation.log
```

Extract the full path from this line — this is the conversation log for THIS
specific run. Do NOT use `ls -t` to find the most recent log across all
conversations, as that may return a log from a previous run.

Then start a monitoring loop. On each cycle:

1. Check if the process is still running: `kill -0 $(cat ~/.aws/atx/custom/atx-agent-session/transform.pid) 2>/dev/null && echo "RUNNING" || echo "DONE"`
2. Read the latest lines from the conversation log and tell the user what's happening
3. Wait 60 seconds, then repeat

**You MUST continue polling without waiting for user input.** After each poll,
immediately schedule the next one. The user should see continuous progress updates
like "AWS Transform is planning changes...", "Applying changes to 3 files...", "Running build...".

CRITICAL rules:

1. **Extract conversation ID and log path.** After launching the process, look for
   the conversation log line in stdout:

   ```
   Conversation log: /Users/<user>/.aws/atx/custom/<conversation-id>/logs/<timestamp>-conversation.log
   ```

   Extract the `<conversation-id>` (e.g., `20260311_233325_21bb5ef0`) and the full
   log file path. Report the conversation ID to the user immediately. Example:
   "Transformation started — conversation ID: `20260311_233325_21bb5ef0`"

2. **Tail the conversation log.** Once the log path is known, read new lines from
   the conversation log on each polling cycle and relay meaningful progress to the
   user. This is the primary way to keep the user informed of what AWS Transform is doing
   (e.g., planning steps, applying changes, running builds, encountering errors).

3. **Filter out noise.** When reading the conversation log or process stdout,
   silently IGNORE any lines containing "Thinking" — these are animated spinner
   indicators that repeat dozens of times and must NOT be echoed to the user.
   Surface everything else: planning output, file changes, build results, errors,
   and completion summaries.

4. **Completion = process exit only.** The transformation is done ONLY when the
   background process exits (i.e., `kill -0` returns non-zero). Do NOT treat
   exit code 0 from any other command (grep, cat, test, etc.) as transformation
   completion. Do NOT treat log messages like "TRANSFORMATION COMPLETE" as
   completion — AWS Transform performs additional steps after that (validation summary
   generation). Check the process exit code — do NOT parse terminal
   output or log content to determine completion. AWS Transform prints progress messages
   and spinner animations throughout execution that do NOT indicate completion.

5. **Polling interval.** Check the background process status and tail the
   conversation log every 60 seconds. Do NOT use escalating backoff for local
   mode — a fixed 60-second interval is sufficient. Do NOT sleep in the foreground
   terminal.

6. **Exit code determines success.** Once `kill -0` confirms the process has
   exited, read the exit code: `cat ~/.aws/atx/custom/atx-agent-session/transform.exit`.
   Check it in this order:
   - `0` = success, unless `transform.log` contains `Execution was not successful`
     (AWS Transform reported the transformation failed but still exits 0).
   - `2` = the Agent Minutes budget set with `--limit <minutes>` was reached. Not a failure:
     offer to resume with `atx --conversation-id <id> --limit <higher-minutes>`.
   - `130`, `129` or `143` = the run was interrupted (Ctrl+C, closed terminal, SIGTERM).
     Not a failure: it did not finish, so offer to resume or re-run it.
   - Any other non-zero code = failure.

   Only after reading the exit code should you report the transformation as complete or failed.

7. **Open artifacts in the IDE (local mode only).** Using the conversation ID
   from rule #1, the artifacts directory is
   `~/.aws/atx/custom/<conversation-id>/artifacts/`. During each polling cycle,
   list the directory and open any new files that appear. Open each file only
   once — track which ones you've already opened.

   Check and open during polling:

   ```bash
   ARTIFACTS_DIR=~/.aws/atx/custom/<conversation-id>/artifacts
   ls "$ARTIFACTS_DIR" 2>/dev/null
   ```

   When new files appear, open them in the current IDE window.

   If a file named `plan.json` appears, IMMEDIATELY after opening it — before
   doing anything else, before the next polling cycle — display this message:

   > ### Open Source Control to watch changes in real time
   >
   > **AWS Transform commits after each step — Source Control shows every file change with full diffs as they happen.**

   Do NOT defer this message. Do NOT batch it with other output. Send it
   right after opening plan.json.

   Continue polling and opening new artifacts until the process exits.

### Present Results

Show transformation definition, repo path, key changes. Also tell the user:
"You can review all changes in the Source Control panel — it shows the full
commit history with diffs for each file AWS Transform modified."

## Remote Mode

Remote runs go through the AWS Transform CLI's built-in remote execution — no
Lambda calls or separate infrastructure repo. Make sure the infrastructure is
deployed (`atx ct remote detect --mode <batch|ec2>`; deploy with
`atx ct remote provision` after user consent) and the repo is in a registered
source (`atx ct source add`; a local path or S3 zip becomes a `--provider local`
source). Then submit:

```bash
AWS_REGION=<region> atx ct remote remediation --mode <batch|ec2> --stack-name <stack> \
  --transformation-name <td-name> \
  --repos <source>::<repo> \
  --configuration 'additionalPlanContext=<user-config>' \
  --telemetry "agent=<agent>,executionMode=<fargate|ec2>"
```

`<stack>` is the `stackName` from `atx ct remote detect --mode <batch|ec2> --json`.
Omit `--configuration` if no config is needed. Your own transformation definitions
must be in the `remediation` category (AWS-managed ones work unless tagged `analysis`); if one has no
category, publish it again with `--category remediation`. Monitor with
`atx ct remote status` and present the result the status shows (pull/merge request
URL or S3 output path). See
[custom-remote-execution](custom-remote-execution.md) for
provisioning, sources, monitoring, results, and teardown.

## Error Handling

| Issue                      | Resolution                                                                                                                                                                                    |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Dependency incompatibility | Check package compatibility, may need manual update                                                                                                                                           |
| Build failure (remote)     | Check build command works locally; if the build needs a runtime or private registry the pre-built image lacks, use a custom image (see [custom-remote-execution](custom-remote-execution.md)) |
| Shell command timeout      | Set `ATX_SHELL_TIMEOUT=1800` (seconds; default 900) or break into smaller transforms                                                                                                          |

## MANDATORY: Cleanup

Clean up session files **before starting** and **after completing** each transformation:

```bash
[ -d ~/.aws/atx/custom/atx-agent-session ] && find ~/.aws/atx/custom/atx-agent-session -maxdepth 1 -type f \( -name "*.sh" -o -name "*.log" -o -name "*.pid" -o -name "*.exit" -o -name "*.zip" \) -delete 2>/dev/null || true
```
