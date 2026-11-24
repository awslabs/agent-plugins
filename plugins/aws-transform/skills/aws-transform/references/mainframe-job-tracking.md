# Mainframe Job Tracking

> **Last Updated:** 2026-11-19

## Table of Contents

- [Offer Tracking](#offer-tracking)
- [Snapshot](#snapshot)
- [Watch Loop](#watch-loop)
- [Build Tracking](#build-tracking)
- [Never Stop for These Reasons](#never-stop-for-these-reasons)
- [Interruptions](#interruptions)
- [Rules](#rules)

Automatic job tracking for **mainframe jobs only**. With the user's consent, watch the job quietly and notify the user only when its status changes or their input is needed. This replaces the user typing "check status".

Tracking ends when the job status is `COMPLETED`, `FAILED` or `STOPPED`, or when the Build step reaches `IN_PROGRESS`. At that point you start the Build progress dashboard ([mainframe-build-progress](mainframe-build-progress.md)) and offer Build tracking (Build Tracking below), which brings the user Build's architecture style questions. Every plan step showing `SUCCEEDED` is not the end while the job is still running: the orchestrator can still ask a question in the job chat, and if the user's answer adds a plan step, keep tracking it without asking again whether to track.

## Offer Tracking

Offer once per job:

- right after the plan is approved and the job starts executing ([mainframe](mainframe.md) → New job, step 6), and
- when the user connects to an existing mainframe job that is still running. If Build is preparing the requirements (Build Tracking below), offer Build tracking instead.

**Question:** "Your job is running. Do you want me to track it automatically? I'll watch it and tell you as soon as its status changes or your input is needed. Tracking runs in this chat; it stops if you send me an unrelated message."

**Options:**

- **"Yes, track it"** — start the watch loop below.
- **"No, I'll ask for status"** — do not track. Use the reactive model in [mainframe](mainframe.md) → Checking Progress.

Ask this question only once per job. After "Yes, track it", never ask again whether to continue tracking.

If the user later asks to "track my job" or "resume tracking", start the watch loop without asking again.

## Snapshot

Each poll reads only these (never call `send_message`, and never call `get_job_status` without `detailed=true`; both post into the job chat):

- `get_resource` `resource="job"` — the job status.
- `list_resources` `resource="plan"` — each step's name and status.
- `list_resources` `resource="tasks"` three times, with `taskStatus` = `AWAITING_HUMAN_INPUT`, then `IN_PROGRESS`, then `AWAITING_APPROVAL` — input the user must give. All three statuses mean the task is waiting for the user ([tools](tools.md) → HITL Tasks). An input task can show `IN_PROGRESS` instead of `AWAITING_HUMAN_INPUT` (for example Build's "Specify build inputs"), so never skip the `IN_PROGRESS` read. A task is new if its `taskId` is not in the previous snapshot. The optional "Add collaborators" task is never input-needed: leave it out of every snapshot ([mainframe](mainframe.md) → Add Collaborators).
- If the job status is `AWAITING_HUMAN_INPUT` or a plan step is `PENDING_HUMAN_INPUT`, but the three reads above found no input-needed task, read `list_resources` `resource="tasks"` once more without `taskStatus`, and treat every task that is not `CLOSED`, `CLOSED_PENDING_NEXT_TASK`, `SUBMITTED`, `CANCELLED` or `DELIVERED` (other than progress dashboard tasks and the optional "Add collaborators" task) as input-needed.
- `list_resources` `resource="messages"` — orchestrator questions (messages with a non-null `interactions` array, or a yes/no question the orchestrator asks in the job chat). A question is new only if its `messageId` is not in the previous snapshot; do not get the current time for this.

The snapshot is: the job status, every plan step's status, the IDs of input-needed tasks, and the IDs of the messages read, with any new orchestrator question.

## Watch Loop

1. **Baseline.** Take a snapshot and post the current status once, for example:
   > Step 4 of 5 · Generate requirements · IN_PROGRESS · no input needed

   If the baseline already has an input-needed task or an unanswered orchestrator question, request it now, as in the input row of step 4.
2. **Wait.** Call `adaptive_poll` with `seconds=60`. The user's "yes" is the approval for every `adaptive_poll` call in this loop; do not ask again. Put the next call to make in `follow_up`.
3. **Poll.** Take a new snapshot and compare it with the last one.
   - **No change**, however many polls in a row: post nothing. Go to step 2.
   - **Changed:** notify the user (step 4).
4. **Notify.** Post what changed in one line. When a plan step reaches `IN_PROGRESS` for the first time, start the update with "Now working on step N of M · \<step name\>". Show this once per step: never repeat it on later polls, including when the step returns to `IN_PROGRESS` after waiting for input. The baseline in step 1 counts as the first time for the step that is current then. Then apply the first rule that matches:

   | Change                                                 | Action                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
   | ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | The job status is `COMPLETED`, `FAILED` or `STOPPED`   | Stop tracking. Post a final summary of every step and its status, then continue with [mainframe](mainframe.md).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
   | The Build step reached `IN_PROGRESS`                   | Stop tracking. Post the update. Start the Build progress dashboard and post its link ([mainframe-build-progress](mainframe-build-progress.md)). If Build is preparing the requirements, offer Build tracking (Build Tracking below). Otherwise say that job tracking has ended, then continue with [mainframe](mainframe.md) → After Generate requirements.                                                                                                                                                                                                                                                                                                                                                                   |
   | An input-needed task or orchestrator question appeared | Request the input now. Present it under the existing rules ([tools](tools.md) → HITL Tasks, or [mainframe](mainframe.md) → After Generate requirements) and wait. For Build's scope task ("Specify build inputs"), first start the Build progress dashboard and post its link if it is not running yet ([mainframe-build-progress](mainframe-build-progress.md)), then run the scope Q&A in [mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md) instead. Never answer for the user. After their answer is submitted, take a new snapshot as the baseline without posting it, then go to step 2. If the answer adds a plan step, keep tracking it; never ask again whether to track. |
   | Anything else                                          | Go to step 2.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

## Build Tracking

Build first prepares the requirements. Only then does it raise its scope task ("Specify build inputs") with the architecture style questions, and it waits for the user's answers. Build tracking watches the job until that task appears, so the user can answer it as soon as it is ready.

Build is **preparing the requirements** when the plan step Build is `IN_PROGRESS` and its scope task has not been submitted yet: `list_resources resource="tasks"` without `taskStatus` has no "Specify build inputs" task, or that task is still waiting for input. Once the task is `SUBMITTED` or `CLOSED`, Build is transforming the code.

If the worklogs (`list_resources resource="worklogs"`) show "AWS Transform started Build" while the plan step Build still shows `NOT_STARTED`, treat the Build step as `IN_PROGRESS`.

### Offer

Offer once per job, when Build is preparing the requirements:

- when job tracking ends because Build reached `IN_PROGRESS` (Watch Loop, step 4), and
- when the user connects to an existing job in that state.

**Question:** "Build has started. AWS Transform first prepares your requirements. Then it asks you a few architecture style questions that decide how the generated code is structured, and it needs your answers to continue. Do you want me to track the job and bring you the questions as soon as they're ready?"

**Options:**

- **"Yes, track it"** — "I'll watch the job and bring you the architecture style questions as soon as they're ready." Start the Build tracking loop below.
- **"No, I'll check status myself"** — "Say 'check status' any time to see whether Build needs your input." Post exactly "OK. Say 'check status' any time to see whether Build needs your input." and end your turn.

Job tracking stays stopped whatever the answer; never resume it on your own. The Build progress dashboard keeps running whatever the answer: start it before this offer if it is not running yet ([mainframe-build-progress](mainframe-build-progress.md)).

If the user later asks to "track my job" while Build is preparing the requirements, start the Build tracking loop without asking again.

### Loop

Run the Watch Loop above with these changes:

1. **Baseline.** Post exactly "Tracking Build. I'll tell you when the architecture style questions are ready." instead of the status line. If the scope task is already waiting for input, run the scope Q&A now.
2. **Notify.** Use this table instead of the one in step 4:

   | Change                                                                                           | Action                                                                                                                                         |
   | ------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
   | The job status is `COMPLETED`, `FAILED` or `STOPPED`, or the Build step is `FAILED` or `STOPPED` | Stop tracking. Post a final summary of every step and its status, then continue with [mainframe](mainframe.md).                                |
   | Build's scope task is waiting for input                                                          | Run the scope Q&A in [mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md). Never answer for the user. |
   | Anything else                                                                                    | Go to step 2.                                                                                                                                  |

Never Stop for These Reasons and Interruptions apply to Build tracking unchanged.

### End

Build tracking ends when the scope Q&A submits the user's answers to the scope task ([mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md) → Step 9). This end applies to Build tracking only. Take no more snapshots, and continue with [mainframe-build-architecture-style-question](mainframe-build-architecture-style-question.md) → After Submitting.

## Never Stop for These Reasons

Tracking MUST NOT stop, pause or end the turn for any reason other than the end conditions in step 4 (for Build tracking, Build Tracking → End) and the **Interruptions** below. Never end your turn between polls: ending the turn stops tracking. These are NOT reasons to stop, and you MUST keep the watch loop running through them:

- **A long-running step.** A step can stay `IN_PROGRESS` for a long time (Extract business logic, Generate requirements and Build often do). Long runs are expected, not a problem to solve.
- **Many polls with no change.** Checking an unchanged step every minute is the job of tracking, not waste.
- **Saving effort, tokens or credits.** Never decide on your own that polling costs too much or is not worth it.
- **Nothing is waiting on the user right now.** That is the normal state between changes.
- **The user can resume later.** Never stop because the user could say "track my job" again.
- **The chat or turn has gone on for a long time.**

## Interruptions

These pause tracking before an end condition is reached. Say "Tracking stopped. Say 'track my job' to resume."

- The user sends a new message that is not an answer to input you requested: stop, then handle the message. An answer to requested input does not stop tracking.
- A poll fails 3 times in a row, or authentication fails: stop and explain. For authentication, follow [auth](auth.md).
- Tracking only runs inside this chat. Closing the IDE or starting a new chat ends it.

## Rules

- While tracking is on, present-tense status is fine ("Your job is on step 4"), because each poll fetches fresh data. Once tracking stops, follow [workflow](workflow.md) → Freshness: no promises of proactive updates.
- Never claim to track in the background or after the chat ends.
- Track only the job the user agreed to. Ask again before tracking another job.
