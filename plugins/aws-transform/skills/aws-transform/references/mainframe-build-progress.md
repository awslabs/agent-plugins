# Mainframe Build Progress

> **Last Updated:** 2026-11-20

Shows a live progress dashboard, `ataa_progress_dashboard_<jobId>_<YYYYMMDD_HHMMSS>.html` in the user's workspace root (`<YYYYMMDD_HHMMSS>` is when the script started, so every start writes a new page), for the whole time a mainframe job's **Build** step runs: while it prepares the requirements, while it waits for the architecture style answers, and while it transforms the code. After Build ends, it shows Build's final page: whenever you check a job whose Build is `SUCCEEDED`, `FAILED` or `STOPPED`, even when the job itself is `COMPLETED`, make sure the script is running. The bundled script `ataa_progress_dashboard.py` does all the work: every 60 seconds it reads the Build progress data from AWS Transform and rewrites the page. When Build ends, it shows the final page and keeps serving it for 2 hours before it stops by itself. The page reloads itself every 60 seconds. The script also serves the page at a localhost link, which you MUST post in the chat: the chat is the only place the user can find it. You start the script once, post the link in the chat, and end your turn.

## When to Start

The trigger is the status of the plan step **Build** (`list_resources resource="plan"`). Never ask the user.

| Build status                           | Action                                                                                                                                                    |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `IN_PROGRESS` or `PENDING_HUMAN_INPUT` | Start the script (below), whatever the state of its scope task ("Specify build inputs").                                                                  |
| `SUCCEEDED`, `FAILED` or `STOPPED`     | Check whether the script is running; if it is not, start it (below), even when the job is `COMPLETED`. It shows the final page and serves it for 2 hours. |
| `NOT_STARTED`                          | Do not start.                                                                                                                                             |

If the worklogs show "AWS Transform started Build" while the plan step Build still shows `NOT_STARTED`, treat Build as `IN_PROGRESS` ([mainframe-job-tracking](mainframe-job-tracking.md) → Build Tracking).

Apply this every time you read the plan, including when job tracking sees Build start, when connecting to an existing job and when the user sends "Resume Build progress dashboard". Also apply it every time the user asks about Build, its progress or its output, or checks the status of a job whose Build has started: first check whether this job's script is running: the background process you started, or else a running process whose command line contains `ataa_progress_dashboard.py` and this job's ID. If it is not running, start it at once and begin your reply with its message (**Start the Script** step 4), before the step table or any other status. If you already started the script for this job and it is still running, do not start a second one; post its link again (**Start the Script** step 4).

Start the script before anything else Build needs from you. After posting its link (**Start the Script** step 4), continue with the flow that applies: while Build prepares the requirements, offer Build tracking ([mainframe-job-tracking](mainframe-job-tracking.md) → Build Tracking); when its scope task is waiting for input, run the scope Q&A ([mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md)).

## Start the Script

1. Find the script's full path. It ships with this skill as `scripts/ataa_progress_dashboard.py`, next to `SKILL.md`, with `ataa_progress_dashboard.template.html` beside it. Use its absolute path.

2. Start it as a background process that keeps running after the command returns, with the workspace root as the working directory, using this single command with the script path, workspace ID, job ID and workspace root filled in:

   ```
   uv run --quiet --no-project --with mcp==2.3.0 python <script path> --workspace-id <workspaceId> --job-id <jobId> --output-dir <workspace root>
   ```

   If `get_status` shows `sigv4.source` as `auto-detected from AWS_PROFILE=<profile>`, add `--aws-profile <profile>` at the end of the command, so the script signs in with the same AWS profile. On Windows, run the same command in PowerShell.
3. After about 10 seconds, confirm the process is still running; if it is not, start it once more. Then read the process output: the script's only output line is `Dashboard: [<html path>](http://127.0.0.1:<port>/)`, a ready-made Markdown link. If that line is not there yet, wait a few seconds and read the output again until it is. Never go on without the link.
4. **CRITICAL: post the link in the chat, then end your turn.** The user sees only your chat text. The link in the process output, the terminal or your thinking is invisible to them, so without this message they cannot open the dashboard. A missing link is a critical and serious user experience failure.

   Your very next output after reading the `Dashboard:` line MUST be this message, before any other tool call. Post it word for word, as plain chat text, never in an artifact, image, file or code block, and never shortened, reworded or merged into another sentence. Replace `<link>` with the Markdown link after `Dashboard:` exactly as printed. Its text is the full path of `ataa_progress_dashboard_<jobId>_<YYYYMMDD_HHMMSS>.html` and its target is the localhost URL, for example `[/Users/jane/project/ataa_progress_dashboard_e393ad03-8474-479d-8fd7-f8ac73c94c2b_20261116_091502.html](http://127.0.0.1:24817/)`, so the user sees the file path and clicking it opens the live dashboard. Never change the path, host or port.

   > Build is in progress. AWS Transform first prepares the build from business requirements and architecture style. You can click \<link\> to follow it live on the progress dashboard.
   >
   > Note: If you close your IDE or get disconnected from the dashboard, send "Resume Build progress dashboard" to resume monitoring its progress.

   When Build has already ended (`SUCCEEDED`, `FAILED` or `STOPPED`), check the background script status to ensure it's running, post this message instead, word for word, with the same `<link>`:

   > Build has finished. You can click \<link\> to see its final progress on the dashboard.

   In a reply that also reports the job's status, either message is the first thing in the reply, before the step table or any other status text.

   Then continue with the Build tracking offer or the scope Q&A if **When to Start** calls for one. Otherwise end your turn: make no more tool calls. The script keeps the dashboard updated and stops by itself (**What the Script Does**).

## Sign-in Expired

The script reloads the saved AWS Transform sign-in after every failed read, so a new sign-in resumes the dashboard on its own.

1. Tell the user right away: "The dashboard paused because your AWS Transform sign-in expired. To resume it, paste a new session cookie here: in your browser, open the AWS Transform web app, then DevTools (F12) → Application → Cookies → `aws-transform-session`, and copy its Value." If the sign-in uses SSO instead of a cookie (`get_status`), ask the user to sign in again with SSO ([auth](auth.md)).
2. When the user pastes the cookie, call `configure` with `authMode` = `"cookie"`, `origin` = the AWS Transform web app URL already in use (from `get_status`; ask only if it is unknown) and `sessionCookie` = the pasted value. Never repeat the cookie in the chat.
3. If `configure` fails, tell the user the cookie was not accepted and ask for a fresh one.
4. If it succeeds: when the script is still running, it picks up the new sign-in within about a minute; when it has stopped and the Build step is not `NOT_STARTED`, start it again (**Start the Script** step 2). Confirm that it is running, post the message from **Start the Script** step 4, and end your turn.

## What the Script Does

- Reads the progress file that Build keeps up to date in the job's S3 bucket, `transform-output/<jobId>/build/ataa_progress.json`. It uses the AWS Transform MCP tools the same way you download the generated specs: the `reimagine` connector from `list_resources resource="connectors"`, then `get_resource resource="asset"`. Until Build writes the file, the page shows the starting state. The job ID shown comes from `--job-id`. It shows two sections: **Preparing the build**, with two steps, and **Build**, with three phases: Planner, Code Generation and Validation, including review rework and validation rework. When Build plans one component at a time, the Planner shows how many components are planned, stays in progress until every component has its first plan, and runs at the same time as Code Generation. While it plans, it notes how many tasks it added to the plan since the previous refresh. If the Planner ends before every component has a plan, it shows the planned components as complete and notes how many it dropped.
- Starts its own AWS Transform MCP server, always with the same command, `uvx awslabs.aws-transform-mcp-server@latest`, in the environment the script runs in, with `AWS_PROFILE` set from `--aws-profile` when given. It uses the same saved sign-in as your AWS Transform MCP server, or the AWS credentials of that profile, and makes every read as an MCP tool call to it (`load_instructions`, `list_resources`, `get_resource`). After a failed read it restarts that server, which loads the latest saved sign-in.
- Under **Preparing the build**, shows two steps in the same format as the phases, from the requirements-to-spec timing that Build writes to the progress file:
  - **Step 1 · Define Architecture**: pending, then in progress, then waiting for the user's answers to the architecture style questions, then completed once the answers are submitted.
  - **Step 2 · Define Technical Specification**: pending until the answers are submitted, then in progress, then completed.
- The status pill shows **Pending** until the first step starts, **Preparing** while a step runs, and **Awaiting user input** while the architecture style questions are unanswered.
- Shows **Total Time** under the job ID: the time since Build started (`build_start_time`), including the preparation steps.
- Shows Active Workers as the same running-task count as the Code Generation "tasks running" line, both from `task_progress`.
- Prints one line, `Dashboard: [<html path>](http://127.0.0.1:<port>/)`, then writes nothing more to the terminal, including the MCP server's own log lines.
- Serves the page at that link on this machine only (`127.0.0.1`). The port stays the same for the same job, so a restarted script keeps the link; if that port is taken, it picks a free one. On a remote workspace, the port must be forwarded to the user's machine (for example with the IDE's port forwarding or an SSH tunnel) before the link opens.
- Draws the page from `ataa_progress_dashboard.template.html`, which ships next to the script.
- Checks the Build step and job status on every refresh, every 60 seconds.
- Shows when Build started in the footer ("Start time"), from the `build_start_time` that Build writes to the progress file as soon as it starts, so it stays the same when the script is started again. Until Build has written it, the footer shows "—".
- Shows only the current run of Build. When Build is run again (for example after it failed), the new run replaces the progress file as soon as it starts, so the page starts fresh: no earlier phases, tasks or Total Time. In the first minutes of a rerun, before the new run has started, the page can still show the earlier run.
- When Build completes, the page shows every phase completed, and the script keeps serving it for 2 hours before it stops the server and exits.
- When the step or the job is `FAILED` or `STOPPED`, the page shows **Failed** or **Stopped** on the phase that was running, and the script keeps serving it for 2 hours before it stops the server and exits.
- When it starts after Build has ended, it writes the final page on its first read and serves it for 2 hours.
- While it serves the final page, it still checks the Build step every 60 seconds. When Build runs again (`IN_PROGRESS` or `PENDING_HUMAN_INPUT`), it goes back to live updates at the same link, so the script that is already running follows the new run. The final page does not reload itself, so reload an open page to see the new run.
- Also stops after about 20 minutes of failed reads. The final page shows "Final" and no longer reloads itself.

## Stopping Early

Only if the user asks to stop the dashboard: stop the background process you started.

## Rules

- **The link MUST be in the chat.** Every time you start the script, including when you connect to a job whose Build is already running, post the message from **Start the Script** step 4 before anything else. A link that appears only in a tool result, the terminal or your thinking does not count, because the user cannot see it.
- Only the script reads `ataa_progress.json` and writes the dashboard. Never download that file, never write or edit `ataa_progress_dashboard_<jobId>_<YYYYMMDD_HHMMSS>.html` yourself, and never show progress in the chat as text, an image or an artifact.
- Share the dashboard only as the link the script prints. Never change its host or port, and never start another server for the page.
- Do not delete or move `ataa_progress_dashboard_<jobId>_<YYYYMMDD_HHMMSS>.html` while the script runs.
- Never stop the script because of errors; it reloads the sign-in after a failed read and stops by itself.
- Whenever the user asks about Build or checks a job whose Build has started, the dashboard must be running: check whether its background process is running, and start the script if it is down.
- The script is a background process of this agent session. Ending the session or closing the IDE stops it; start it again with the same command when the user reopens the job, asks about Build or sends "Resume Build progress dashboard", whatever the Build status other than `NOT_STARTED`.
