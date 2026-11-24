# Mainframe Build Scope

> **Last Updated:** 2026-11-19

## Table of Contents

- [When to Start](#when-to-start)
- [Step 1 — Announce](#step-1--announce)
- [Step 2 — Download the Questionnaire](#step-2--download-the-questionnaire)
- [Step 3 — Read the Questionnaire](#step-3--read-the-questionnaire)
- [Step 4 — Ask the Questions](#step-4--ask-the-questions)
- [Step 5 — Write the Completed Scope](#step-5--write-the-completed-scope)
- [Step 6 — Confirm the Upload](#step-6--confirm-the-upload)
- [Step 7 — Upload](#step-7--upload)
- [Step 8 — Confirm the Submit](#step-8--confirm-the-submit)
- [Step 9 — Submit](#step-9--submit)
- [Resume](#resume)
- [After Submitting](#after-submitting)

Completes the scope that a mainframe job's **Build** step waits for, as a question-and-answer in the chat. You download the job's architecture style questionnaire, ask one opening question (accept all recommendations, or choose them yourself), ask the questionnaire's questions one at a time only if the user chooses them, and write the completed scope. Then you ask two separate questions, in this order: whether to upload the completed scope, and, after the upload, whether to submit its S3 URI to the Build scope task. The user never edits the questionnaire or types an S3 URI.

## When to Start

Start this flow without asking the user when both of these are true:

- The plan step **Build** is `PENDING_HUMAN_INPUT`.
- Its task **"Specify build inputs"** is waiting for input (`AWAITING_HUMAN_INPUT` or `IN_PROGRESS`).

Build raises only this one input task. If its title differs, treat the Build step's single input-needed task as the scope task.

If the Build progress dashboard is not running yet, start it and post its link first ([mainframe-build-progress](mainframe-build-progress.md)).

Before starting, read the task with `get_resource resource="task"` and note its `taskId`. If its content shows an error from an earlier submission (for example an `errorAlert`), the submitted scope was rejected. Follow After Submitting → Rejected instead of starting the flow.

Never present the task's input box, and never ask the user for an S3 URI. This flow replaces [tools](tools.md) → HITL Tasks steps 3–6 for this task. Steps 7–8, which show the payload, confirm and submit, are covered by Step 8 and Step 9 below.

## Step 1 — Announce

Post one first-person line, for example: "Build needs a few scope decisions from you. I'm downloading the architecture style questionnaire to your workspace."

## Step 2 — Download the Questionnaire

The questionnaire is always at the same place in the job's bucket, so you build its path yourself. Do not look for its location in the scope task, the job messages or the job chat.

1. **Find the job's connector ID.**
   - Find this job's completed "Connect to AWS account" task with `list_resources resource="tasks" workspaceId="<workspaceId>" jobId="<jobId>"` (no `taskStatus` filter).
   - Read it with `get_resource resource="task"`. Its submitted content is `{"connectorId": "<id>", "connectorType": "mainframe_modernization|reimagine|1"}`. Use that `connectorId`.
   - If the workspace has only one connector of type `mainframe_modernization|reimagine|1`, `list_resources resource="connectors" workspaceId="<workspaceId>"` is enough; use its `connectorId`.
2. **Get the bucket from the connector.** Call `get_resource resource="connector" workspaceId="<workspaceId>" connectorId="<connectorId>"`. Take the bucket name from `configuration.s3BucketArn`: for example, `arn:aws:s3:::amzn-s3-demo-bucket` → `amzn-s3-demo-bucket`. `list_resources resource="connectors"` does not return the bucket.
3. **Add the job's folder.** The job's path is always `s3://<bucket>/transform-output/<jobId>/`, so the architecture style questionnaire is `s3://<bucket>/transform-output/<jobId>/build/architecture-style-questionnaire.md`.
4. **Choose the scope folder:** `<job name>/build-scope/` in the workspace root, where `<job name>` is the job's `jobName`.
5. If the scope folder already has an `architecture-style-questionnaire-complete-<YYYYMMDD_HHMMSS>.md`, go to Resume. Otherwise, if `<scope folder>/architecture-style-questionnaire.md` already exists for this job, reuse it and go to Step 3 (Read the Questionnaire). This happens when an earlier Q&A was interrupted.
6. Otherwise, download the questionnaire as a connector-backed asset:

   ```
   get_resource resource="asset" workspaceId="<workspaceId>" jobId="<jobId>" connectorId="<connectorId>" assetKey="transform-output/<jobId>/build/architecture-style-questionnaire.md" savePath="<workspace root>/<scope folder>/architecture-style-questionnaire.md"
   ```

   Do not use `resource="artifact"`. Do not use the AWS CLI or the user's AWS credentials.

If the download fails or the file is missing, stop:

- Tell the user: "I couldn't download the architecture style questionnaire from `s3://<bucket>/transform-output/<jobId>/build/architecture-style-questionnaire.md`.", followed by the error message.
- Leave the task open.
- Do not retry and do not fall back to asking for an S3 URI.

## Step 3 — Read the Questionnaire

Read `architecture-style-questionnaire.md` completely. Never edit it. It has two parts, in this order in the file:

- **Part A** (`## Part A: Architecture`): first the question **"Architecture styles"**, then, for each bounded context, an online style question if it has online work and a batch style question if it has batch work.
- **Part B** (`## Part B: Application`): the application questions, for example Java version and build tool.

For each question, record:

- the question text, as written;
- its choices, as written;
- which choice is marked **(default)** or **(recommended)**;
- any context the questionnaire gives for a choice.

Every question with choices is single-select. A question without choices (a blank to fill in, for example the base Java package) is never asked; it stays as written, which keeps its default.

If you can't find any question with choices, stop and report that the questionnaire has no scope questions. Do not tell the user how many questions there are.

## Step 4 — Ask the Questions

Follow this flow exactly, in questionnaire order.

### 4.1 Opening Question

Ask the user, word for word, with only these options:

- **Question:** "AWS Transform grouped the requirements into bounded contexts and recommends an architecture style and application setup for the online work and the batch work of each business function."
- **Options:**
  1. **"Accept all recommendations"** — "Accept all AWS Transform recommended architecture styles and application setup."
  2. **"Choose them yourself"** — "Choose each bounded context's architecture style and application setup yourself."

The opening question answers the questionnaire's question **"Architecture styles"**, so never ask that question:

- **"Accept all recommendations"** answers it with "Accept the recommended style for every bounded context".
- **"Choose them yourself"** answers it with "Choose the style for each bounded context in the questions below".

Then:

- **"Accept all recommendations"**: ask nothing else; go to Step 5.
- **"Choose them yourself"**: continue with 4.2.

### 4.2 Remaining Questions

Ask one question at a time, in questionnaire order: every remaining question with choices, after "Architecture styles".

For each question:

- **Question:** the question text, as written. Never add a number, a count or a position (for example "Question 3 of 12" or "3/12").
- **Options:** each choice of the question, split into:
  - **Label:** the choice text before its first `:` or `—` (whichever comes first), with the **(default)** or **(recommended)** marker as plain text, for example `Java 17 (default)` or `Microservice (recommended)`. A choice without `:` or `—` is its label in full.
  - **Description:** the text after that `:` or `—`, followed by the choice's indented lines, if there are any. Otherwise no description.

### Rules

- Never show "Part A", "Part B", their headings or their introductions in the chat.
- Keep each choice's **(default)** or **(recommended)** marker in its label. It is the questionnaire's wording, not your recommendation.
- If you cannot present selectable options, post the same question and options as a numbered list, then wait for the user's choice.
- Use the questionnaire's wording. Do not reword, reorder, merge, add or drop choices. Never add "Other", "Skip", "Default" or "Recommended" options.
- Only the listed choices are accepted. If the user types an answer or asks for a choice that isn't listed, say "Only the listed choices are supported for this question." and ask the same question again.
- Do not recommend a choice, judge the answers, or check answers against each other.
- Keep the answers in the chat. Write no files until the flow reaches Step 5.
- If the chat ends before the last answer, the Q&A starts again from the Opening Question next time, using the same `architecture-style-questionnaire.md`.

## Step 5 — Write the Completed Scope

When the flow reaches this step, build the file name from the current time, `architecture-style-questionnaire-complete-<YYYYMMDD_HHMMSS>.md`, and write `<scope folder>/<file name>`. Do not show a summary of the answers.

The file is `architecture-style-questionnaire.md`, in its own order, with one change: in each question's list of choices, only the chosen choice is kept.

- Keep the chosen choice's line exactly as written, at the same position and indentation. If the choices are checkboxes (`- [ ] <choice>`), tick the chosen one (`- [x] <choice>`).
- Delete the other choice lines of that question.
- "Accept all recommendations": every question's chosen choice is its **(recommended)** or **(default)** one; for "Architecture styles" it is "Accept the recommended style for every bounded context".
- "Choose them yourself": "Architecture styles" is "Choose the style for each bounded context in the questions below"; every other question is the user's answer.
- Questions without choices stay as written.
- Change nothing else. Headings, their numbering, instructions, context lines, defaults markers and blank lines stay exactly as they are in the questionnaire.

## Step 6 — Confirm the Upload

Ask the upload question and the submit question (Step 8) as two separate questions, in order. Never merge them into one question, and never offer "Upload and submit".

Ask the user, word for word, with only these options (`<local path>` is `<workspace root>/<scope folder>/<file name>`):

- **Question:** "The completed scope is saved at `<local path>`. Please check it first. Do you want to upload it?"
- **Options:**
  - **"Upload"** — continue with Step 7.
  - **"Not now"** — leave the task open and stop.

Do not show the S3 URI or the task payload in this step, and do not ask about submitting.

## Step 7 — Upload

Run these calls one at a time, in this order. Each call starts only after the previous one has returned. Use exactly the values below. Do not change, add or drop any parameter.

| Value                      | Source                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `<workspaceId>`, `<jobId>` | The job                                                                                                            |
| `<connectorId>`            | Step 2                                                                                                             |
| `<bucket>`                 | Step 2                                                                                                             |
| `<file name>`              | Step 5 (`architecture-style-questionnaire-complete-<YYYYMMDD_HHMMSS>.md`)                                          |
| `<local path>`             | `<workspace root>/<scope folder>/<file name>`                                                                      |
| `<S3 URI>`                 | `s3://<bucket>/transform-output/<jobId>/User Uploads/<file name>`. The connector upload always writes to this key. |

Upload the file as it is on disk, including any edits the user made while checking it.

### 7.1 Upload

```
upload_artifact workspaceId="<workspaceId>" jobId="<jobId>" content="<local path>" fileName="<file name>" fileType="MARKDOWN" categoryType="CUSTOMER_INPUT" connectorId="<connectorId>"
```

- `fileName` is the bare file name, exactly `<file name>`. Never add a folder, a `/`, an `s3://` prefix or `..`.
- The service always writes the file to `transform-output/<jobId>/User Uploads/<fileName>`. No `fileName` value can place it anywhere else.

Expected result: `{"uploaded": true, "fileName": "<file name>", "connectorId": "<connectorId>"}`.

If the result is anything else, stop:

- Tell the user: "I couldn't upload the completed scope.", followed by the error message.
- Leave the task open. Do not retry, and do not run 7.2, Step 8 or Step 9.

### 7.2 Verify

```
list_resources resource="artifacts" workspaceId="<workspaceId>" jobId="<jobId>" pathPrefix="transform-output/<jobId>/User Uploads/"
```

Expected result: `assets` contains an entry with:

- `assetKey` = `transform-output/<jobId>/User Uploads/<file name>`
- `sizeInBytes` = the size of `<local path>`

If no entry matches both values, stop:

- Tell the user: "The upload reported success, but `<S3 URI>` is not in the bucket."
- Leave the task open. Do not run Step 8 or Step 9.

## Step 8 — Confirm the Submit

Ask only after 7.2 found the uploaded file. Ask the user, word for word, with only these options:

- **Question:** "The completed scope is uploaded to `<S3 URI>`. Do you want to submit this path to the Build scope task "Specify build inputs"? Task payload: `{"scopeUri": "<S3 URI>"}`"
- **Options:**
  - **"Submit"** — continue with Step 9.
  - **"Not now"** — leave the task open and stop. The file stays uploaded.

## Step 9 — Submit

```
complete_task workspaceId="<workspaceId>" jobId="<jobId>" taskId="<taskId>" content={"scopeUri": "<S3 URI>"}
```

Expected result: `"status": "SUBMITTED"`.

Post one line: "Submitted your Build scope: `<S3 URI>`."

Then continue with After Submitting.

## Resume

If the user later asks to upload or submit the scope, take the newest `architecture-style-questionnaire-complete-<YYYYMMDD_HHMMSS>.md` in the scope folder and run the 7.2 check for it. Not found in `User Uploads/`: continue from Step 6. Found: continue from Step 8.

## After Submitting

Build checks the scope before it starts.

- **Accepted:** the Build step moves to `IN_PROGRESS`. If Build tracking was on ([mainframe-job-tracking](mainframe-job-tracking.md) → Build Tracking), post exactly "Your answers are submitted. Build is now transforming the code, and job tracking has ended." Job tracking ends. The Build progress dashboard keeps running from when Build started; if it is not running (for example after the IDE was restarted), start it and post its link ([mainframe-build-progress](mainframe-build-progress.md)).
- **Rejected:** the task opens again with an error. Stop:
  - Show the error to the user, and say that the task is open again.
  - Do not edit the scope, upload it again, or resubmit.

When the flow stops in Step 2, Step 3, Step 6, Step 7 or Step 8, or after a rejection, job tracking stops too. Say "Tracking stopped. Say 'track my job' to resume." When tracking resumes and the task is still waiting for input, apply When to Start again.
