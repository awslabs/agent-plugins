#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import contextlib
import http.server
import json
import os
import re
import sys
import threading
import time
import zlib
from dataclasses import dataclass
from datetime import datetime, timezone
from html import escape
from pathlib import Path

from mcp import ClientSession, StdioServerParameters, stdio_client

PROGRESS_FILE_KEY = "transform-output/{job_id}/build/ataa_progress.json"
DASHBOARD_FILE_NAME = "ataa_progress_dashboard_{job_id}_{started:%Y%m%d_%H%M%S}.html"
JOB_OUTPUT_CONNECTOR_TYPE = "reimagine"
FILE_NOT_FOUND_API_STATUS = 404
FILE_NOT_FOUND_GET_STATUSES = frozenset({"403", "404"})
PRESIGNED_GET_CLIENT_ERROR = re.compile(r"^Client error '(\d{3}) ")
METRICS = (
    "run_completion",
    "task_progress",
    "build_start_time",
    "requirements_to_strategy",
    "architecture_style_hitl",
    "strategy_to_spec",
    "planning_progress",
    "planner_decomposition_completion",
    "phase_times",
    "validation_rework",
)
MCP_SERVER_COMMAND = "uvx"
MCP_SERVER_PACKAGE = "awslabs.aws-transform-mcp-server@latest"
TOOL_CALL_TIMEOUT_SECONDS = 120
BUILD_STEP_NAMES = frozenset({"build"})
RUNNING_STEP_STATUSES = frozenset({"IN_PROGRESS", "PENDING_HUMAN_INPUT"})
POLL_SECONDS = 60
RELOAD_SECONDS = 60
MAX_CONSECUTIVE_FAILURES = 20
TEMPLATE = Path(__file__).with_name("ataa_progress_dashboard.template.html").read_text(encoding="utf-8")
REFRESH_TAG = f'<meta http-equiv="refresh" content="{RELOAD_SECONDS}" />'
HOST = "127.0.0.1"
DASHBOARD_PORTS = range(20000, 30000)
FINAL_PAGE_GRACE_SECONDS = 2 * 60 * 60
FAILED_READS_GRACE_SECONDS = 2 * RELOAD_SECONDS
ENDED_STATES = ("failed", "stopped")

EXIT_OK = 0
EXIT_FAILED = 1

STAGE_RANK = {
    "starting": 0,
    "planning": 1,
    "code_generation": 2,
    "validation": 3,
    "validation_rework": 3,
    "completed": 4,
}
PHASE_STATUSES = {
    "starting": ("pending", "pending", "pending"),
    "planning": ("in-progress", "pending", "pending"),
    "code_generation": ("done", "in-progress", "pending"),
    "validation": ("done", "done", "in-progress"),
    "validation_rework": ("done", "done", "rework"),
    "completed": ("done", "done", "done"),
}
PLANNER_TEXT = {
    "pending": "Waiting for the planner to start",
    "in-progress": "Decomposing the spec into transformation tasks…",
    "done": "Task decomposition complete",
    "failed": "Build failed during planning",
    "stopped": "Build stopped during planning",
}
VALIDATION_TEXT = {
    "pending": "Starts when code generation completes",
    "in-progress": "Validating the generated code against the acceptance criteria…",
    "rework": "Found issue in generated code, reworking to fix.",
    "done": "Validation passed",
    "failed": "Build failed during validation",
    "stopped": "Build stopped during validation",
}
STATUS_LABEL = {"done": "Completed", "in-progress": "In progress", "pending": "Pending", "rework": "Reworking",
                "waiting": "Awaiting user input", "failed": "Failed", "stopped": "Stopped"}
PREPARING_LABEL = "Preparing"
REQUIREMENTS_TO_STRATEGY_TEXT = {
    "pending": "Waiting for Build to start analyzing the requirements",
    "in-progress": "Analyzing your business requirements and drafting an architecture strategy…",
    "waiting": "Please complete the required inputs in AWS Transform or your coding agent",
    "done": "Architecture strategy confirmed",
    "failed": "Build failed while drafting the architecture strategy",
    "stopped": "Build stopped while drafting the architecture strategy",
}
STRATEGY_TO_SPEC_TEXT = {
    "pending": "Starts after the architecture strategy is confirmed",
    "in-progress": "Generating the technical specification from the confirmed strategy…",
    "done": "Technical specification ready",
    "failed": "Build failed while generating the technical specification",
    "stopped": "Build stopped while generating the technical specification",
}


@dataclass(frozen=True)
class Snapshot:
    latest: dict
    completion_published_at: datetime | None

    def metric(self, name):
        """Return the current values of a metric from the progress file, or an empty dict."""
        return self.latest.get(name) or {}


def parse_time(value):
    """Turn an API timestamp (datetime, epoch number or ISO text) into an aware datetime."""
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        seconds = value / 1000 if value > 1e12 else value
        return datetime.fromtimestamp(seconds, tz=timezone.utc)
    text = str(value).replace(" ", "").replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def build_snapshot(document):
    """Build a Snapshot from the progress file: each metric's current values and when the run completed."""
    latest = {name: document.get(name) for name in METRICS if isinstance(document.get(name), dict)}
    completion = latest.get("run_completion") or {}
    completed_at = parse_time(completion.get("completed_at")) if is_true(completion, "complete") else None
    return Snapshot(latest, completed_at)


def is_true(value, key):
    """Return True only when the metric value has the key set to boolean true."""
    return isinstance(value, dict) and value.get(key) is True


def count_or_none(value, key):
    """Return a non-negative integer field of a metric value, or None while it is not published."""
    number = value.get(key) if isinstance(value, dict) else None
    return number if isinstance(number, int) and not isinstance(number, bool) and number >= 0 else None


def count(value, key):
    """Return a non-negative integer field of a metric value, or 0."""
    number = count_or_none(value, key)
    return 0 if number is None else number


def phase_time(snapshot, phase, edge):
    """Return a phase's started_at or ended_at time from the phase_times metric."""
    phases = snapshot.metric("phase_times")
    entry = phases.get(phase) if isinstance(phases, dict) else None
    return parse_time(entry.get(edge)) if isinstance(entry, dict) else None


def stage_of(snapshot):
    """Pick the run stage, checking the most advanced stage first."""
    if is_true(snapshot.metric("run_completion"), "complete"):
        return "completed"
    if is_true(snapshot.metric("validation_rework"), "reworking"):
        return "validation_rework"
    if phase_time(snapshot, "validation", "started_at"):
        return "validation"
    if is_true(snapshot.metric("planner_decomposition_completion"), "complete"):
        return "code_generation"
    if phase_time(snapshot, "planner", "started_at"):
        return "planning"
    return "starting"


def workflow_time(snapshot, metric_name, edge):
    """Return a requirements-to-spec workflow's started_at or ended_at time."""
    return parse_time(snapshot.metric(metric_name).get(edge))


def requirements_to_strategy_status(snapshot):
    """Return the architecture strategy step's status: pending, in-progress, waiting on the customer, or done."""
    if workflow_time(snapshot, "requirements_to_strategy", "started_at") is None:
        return "pending"
    if workflow_time(snapshot, "requirements_to_strategy", "ended_at") is None:
        return "in-progress"
    return "done" if is_true(snapshot.metric("architecture_style_hitl"), "complete") else "waiting"


def shows_prep(snapshot, stage, step_status, ended):
    """Show the requirements-to-spec banners once they ran, or while Build may still be about to run them."""
    if workflow_time(snapshot, "requirements_to_strategy", "started_at"):
        return True
    return stage == "starting" and not ended and step_status != "PENDING_HUMAN_INPUT"


def strategy_to_spec_status(requirements_status, snapshot):
    """Return the technical-spec banner's status: pending until the strategy is confirmed, then running or done."""
    if requirements_status != "done":
        return "pending"
    return "done" if workflow_time(snapshot, "strategy_to_spec", "ended_at") else "in-progress"


def ended_prep_statuses(requirements_status, strategy_status, end):
    """Attribute a failed or stopped build to whichever banner was still running."""
    if requirements_status != "done":
        return end, "pending"
    return "done", (strategy_status if strategy_status == "done" else end)


def end_state(step_status, job_status):
    """Map the Build step status, then the job status, to completed, failed or stopped; None while it runs."""
    for status, completed in ((step_status, "SUCCEEDED"), (job_status, "COMPLETED")):
        if status == completed:
            return "completed"
        if status in ("FAILED", "STOPPED"):
            return status.lower()
    return None


def ended_phase_statuses(statuses, end):
    """Mark the phases that were running, or else the first one not done, as failed or stopped."""
    statuses = list(statuses)
    running = [i for i, status in enumerate(statuses) if status in ("in-progress", "rework")]
    if not running:
        running = [next((i for i, status in enumerate(statuses) if status == "pending"), len(statuses) - 1)]
    for index in running:
        statuses[index] = end
    return tuple(statuses)


def planning_counts(snapshot):
    """Return a sequential planner's (planned, total) components, or None when Build plans everything at once."""
    progress = snapshot.metric("planning_progress")
    total = count_or_none(progress, "total")
    if not total:
        return None
    return min(count(progress, "planned"), total), total


def dropped_label(count):
    """Say how many components the Planner ended without planning."""
    return f"Planner dropped {count} {'component' if count == 1 else 'components'}"


def run_phase_statuses(stage, snapshot, planning):
    """Return the three phase statuses; a sequential planner keeps planning until every component has a plan."""
    statuses = list(PHASE_STATUSES[stage])
    if (planning is not None and stage in ("planning", "code_generation")
            and phase_time(snapshot, "planner", "ended_at") is None):
        statuses[0] = "in-progress"
    return tuple(statuses)


def advance(previous, current):
    """Keep the stage from moving backwards between refreshes."""
    if previous is None or STAGE_RANK[current] >= STAGE_RANK[previous]:
        return current
    return previous


def phase_spans(snapshot):
    """Return each phase's (start, end) times, filling gaps from the neighbouring phase."""
    planner_start = phase_time(snapshot, "planner", "started_at")
    planner_end = phase_time(snapshot, "planner", "ended_at")
    code_start = phase_time(snapshot, "code_generation", "started_at") or planner_end
    code_end = phase_time(snapshot, "code_generation", "ended_at")
    validation_start = phase_time(snapshot, "validation", "started_at")
    validation_end = phase_time(snapshot, "validation", "ended_at") or snapshot.completion_published_at
    return {
        "planner": (planner_start, planner_end or code_start),
        "code_generation": (code_start, code_end or validation_start),
        "validation": (validation_start, validation_end),
    }


def prep_spans(snapshot):
    """Return the two requirements-to-spec banners' (start, end) times, strategy's start filling the gap."""
    requirements_start = workflow_time(snapshot, "requirements_to_strategy", "started_at")
    strategy_start = workflow_time(snapshot, "strategy_to_spec", "started_at")
    strategy_end = workflow_time(snapshot, "strategy_to_spec", "ended_at")
    return {
        "requirements_to_strategy": (requirements_start, strategy_start),
        "strategy_to_spec": (strategy_start, strategy_end),
    }


def format_duration(seconds):
    """Format seconds as <1m, 12m or 1h 05m."""
    minutes = int(max(seconds, 0) // 60)
    if minutes < 1:
        return "<1m"
    if minutes < 60:
        return f"{minutes}m"
    return f"{minutes // 60}h {minutes % 60:02d}m"


def elapsed(start, end, now):
    """Format the time from start to end (or now), or — when there is no start."""
    if start is None:
        return "—"
    return format_duration(((end or now) - start).total_seconds())


def phase_timer(status, span, now):
    """Format a phase timer: — while pending, frozen when done, running otherwise."""
    start, end = span
    if status == "pending":
        return "—"
    if status == "done":
        return elapsed(start, end, now) if end else "—"
    return elapsed(start, None, now)


def code_generation_counts(snapshot, status):
    """Return Phase 2's (completed, total, pct): live while it runs, fixed at 100% of its final total once done."""
    progress = snapshot.metric("task_progress")
    if status == "done":
        frozen = count_or_none(progress, "code_generation_total")
        total = count(progress, "total") if frozen is None else frozen
        return total, total, 100
    completed, total = count(progress, "completed"), count(progress, "total")
    completed = min(completed, total) if total else completed
    return completed, total, round(completed * 100 / total) if total else 0


def rework_added_tasks(snapshot, validation_status, code_total):
    """Return how many tasks rework added after code generation, once validation has started."""
    if validation_status == "pending":
        return 0
    return max(count(snapshot.metric("task_progress"), "total") - code_total, 0)


def tasks_label(number):
    """Return '1 task' or 'N tasks'."""
    return f"{number} {'task' if number == 1 else 'tasks'}"


def fill(template, values):
    """Replace each {{name}} placeholder in the template with its value."""
    page = template
    for name, value in values.items():
        page = page.replace("{{" + name + "}}", str(value))
    return page


def build_start(snapshot):
    """Return when Build started, from the progress file's build_start_time, or None until Build has written it."""
    return parse_time(snapshot.metric("build_start_time").get("started_at"))


def build_start_label(snapshot):
    """Return when Build started as a footer label, or — until Build has written it."""
    started = build_start(snapshot)
    return time_label(started) if started else "—"


def overall_state(stage, ended, end, requirements_status, strategy_status, step_status):
    """Return the status pill's (status, text): Preparing only while a preparation step runs."""
    preparing = stage == "starting" and not ended
    if preparing and (requirements_status == "waiting" or step_status == "PENDING_HUMAN_INPUT"):
        return "waiting", STATUS_LABEL["waiting"]
    if ended:
        return end, STATUS_LABEL[end]
    if stage == "completed":
        return "done", STATUS_LABEL["done"]
    if preparing and requirements_status == "pending":
        return "pending", STATUS_LABEL["pending"]
    if preparing and "in-progress" in (requirements_status, strategy_status):
        return "in-progress", PREPARING_LABEL
    return "in-progress", STATUS_LABEL["in-progress"]


def render_page(snapshot, stage, now, updated_label, job_id, live, end=None, step_status=None, tasks_added=0):
    """Fill the dashboard template with the snapshot's values for this stage, and a failed or stopped end."""
    ended = end in ENDED_STATES
    prep_shown = shows_prep(snapshot, stage, step_status, ended)
    requirements_status = requirements_to_strategy_status(snapshot)
    strategy_status = strategy_to_spec_status(requirements_status, snapshot)
    if stage == "starting" and ended and prep_shown:
        requirements_status, strategy_status = ended_prep_statuses(requirements_status, strategy_status, end)
    prep = prep_spans(snapshot)
    planning = planning_counts(snapshot)
    statuses = run_phase_statuses(stage, snapshot, planning)
    planner, code, validation = ended_phase_statuses(statuses, end) if ended else statuses
    planned, components = planning or (0, 0)
    dropped = components - planned if planner == "done" else 0
    if dropped:
        components = planned
    spans = phase_spans(snapshot)
    progress = snapshot.metric("task_progress")
    completed, total, pct = code_generation_counts(snapshot, code)
    running, reworking = count(progress, "running"), count(progress, "reworking")
    added = rework_added_tasks(snapshot, validation, total)
    finished = stage == "completed"
    overall, overall_text = overall_state(stage, ended, end, requirements_status, strategy_status, step_status)
    return fill(TEMPLATE, {
        "refresh": REFRESH_TAG if live else "",
        "job_id": escape(job_id),
        "overall_status": overall,
        "overall_text": overall_text,
        "prep_hidden": "" if prep_shown else "hidden",
        "requirements_status": requirements_status,
        "requirements_label": STATUS_LABEL[requirements_status],
        "requirements_timer": phase_timer(requirements_status, prep["requirements_to_strategy"], now),
        "requirements_text": REQUIREMENTS_TO_STRATEGY_TEXT[requirements_status],
        "strategy_status": strategy_status,
        "strategy_label": STATUS_LABEL[strategy_status],
        "strategy_timer": phase_timer(strategy_status, prep["strategy_to_spec"], now),
        "strategy_text": STRATEGY_TO_SPEC_TEXT[strategy_status],
        "tasks_completed": count(progress, "completed"),
        "tasks_total": count(progress, "total"),
        "active_workers": running,
        "total_time": elapsed(build_start(snapshot), spans["validation"][1] if finished else None, now),
        "planner_status": planner,
        "planner_label": STATUS_LABEL[planner],
        "planner_timer": phase_timer(planner, spans["planner"], now),
        "planner_text": PLANNER_TEXT[planner],
        "planner_line_hidden": "hidden" if planning else "",
        "planner_progress_hidden": "" if planning else "hidden",
        "planner_planned": planned,
        "planner_components": components,
        "planner_pct": round(planned * 100 / components) if components else 0,
        "parallel_hidden": "" if planning and planner == "in-progress" and code == "in-progress" else "hidden",
        "planner_added_hidden": "" if planning and planner == "in-progress" and tasks_added > 0 else "hidden",
        "planner_added_label": f"Planner added {tasks_label(tasks_added)} to the plan",
        "planner_dropped_hidden": "" if dropped else "hidden",
        "planner_dropped_label": dropped_label(dropped),
        "code_status": code,
        "code_label": STATUS_LABEL[code],
        "code_timer": phase_timer(code, spans["code_generation"], now),
        "code_completed": completed,
        "code_total": total,
        "code_pct": pct,
        "code_width": pct,
        "code_remaining": max(total - completed, 0),
        "now_hidden": "" if code == "in-progress" and running > 0 else "hidden",
        "running_label": f"{tasks_label(running)} running",
        "rework_hidden": "" if reworking > 0 else "hidden",
        "reworking_label": f"· {tasks_label(reworking)} reworking",
        "validation_status": validation,
        "validation_label": STATUS_LABEL[validation],
        "validation_timer": phase_timer(validation, spans["validation"], now),
        "validation_text": VALIDATION_TEXT[validation],
        "rework_added_hidden": "" if added and not finished else "hidden",
        "rework_added_label": f"Rework added {tasks_label(added)} · {count(progress, 'total')} tasks in total",
        "started_at": escape(build_start_label(snapshot)),
        "freshness": "Live" if live else "Final",
        "updated_at": escape(updated_label),
    })


def write_atomically(path, text):
    """Write the page to a temp file and swap it in, so the preview never sees half a page."""
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_name(path.name + ".tmp")
    staging.write_text(text, encoding="utf-8")
    os.replace(staging, path)


def mcp_server_parameters(aws_profile):
    """Return how to start the AWS Transform MCP server: always the same uvx command, in this script's environment."""
    env = dict(os.environ)
    if aws_profile:
        env["AWS_PROFILE"] = aws_profile
    return StdioServerParameters(command=MCP_SERVER_COMMAND, args=[MCP_SERVER_PACKAGE], env=env)


class ToolCallFailed(Exception):
    def __init__(self, error):
        """Keep the error object of a failed MCP tool call."""
        super().__init__(error.get("message") or error.get("code") or "MCP tool call failed")
        self.error = error


def tool_data(result):
    """Return the data of a successful AWS Transform MCP tool result, or raise ToolCallFailed with its error."""
    if result.is_error:
        message = " ".join(getattr(item, "text", "") for item in result.content)
        raise ToolCallFailed({"code": "TOOL_ERROR", "message": message})
    envelope = (result.structured_content or {}).get("result") or json.loads(result.content[0].text)
    payload = json.loads(envelope["content"][0]["text"])
    if envelope.get("isError") or not payload.get("success"):
        raise ToolCallFailed(payload.get("error") or {})
    return payload.get("data")


def is_missing_file(error):
    """Return True when a download failed only because Build has not written the progress file yet."""
    status = error.get("httpStatus")
    if status is not None:
        return status == FILE_NOT_FOUND_API_STATUS
    failed_get = PRESIGNED_GET_CLIENT_ERROR.match(str(error.get("message") or ""))
    return bool(failed_get) and failed_get.group(1) in FILE_NOT_FOUND_GET_STATUSES


class TransformClient:
    def __init__(self, workspace_id, job_id, server):
        """Remember the job every tool call is scoped to and how to start the AWS Transform MCP server."""
        self.job_id = job_id
        self.scope = {"workspaceId": workspace_id, "jobId": job_id}
        self._server = server
        self._session = None
        self._session_stack = None
        self._connector_id = None
        self.step_status = None

    async def connect(self):
        """Start a fresh MCP server, which loads the saved sign-in, and open the job; retried after a failed read."""
        await self.close()
        stack = contextlib.AsyncExitStack()
        try:
            read, write = await stack.enter_async_context(stdio_client(self._server))
            session = await stack.enter_async_context(
                ClientSession(read, write, read_timeout_seconds=TOOL_CALL_TIMEOUT_SECONDS))
            await session.initialize()
        except Exception:
            with contextlib.suppress(Exception):
                await stack.aclose()
            return
        self._session, self._session_stack = session, stack
        with contextlib.suppress(Exception):
            await self._call("load_instructions", **self.scope)

    async def close(self):
        """Stop the MCP server if one is running."""
        stack, self._session, self._session_stack = self._session_stack, None, None
        if stack is not None:
            with contextlib.suppress(Exception):
                await stack.aclose()

    async def snapshot(self):
        """Download the Build progress file into a Snapshot; a file Build has not written yet is None."""
        connector_id = await self._job_output_connector_id()
        try:
            download = await self._call("get_resource", resource="asset", connectorId=connector_id,
                                        assetKey=PROGRESS_FILE_KEY.format(job_id=self.job_id), **self.scope)
        except ToolCallFailed as failure:
            if is_missing_file(failure.error):
                return None
            raise
        return build_snapshot(json.loads(download["content"]))

    async def build_state(self):
        """Return completed, failed or stopped once the Build step or the job has ended, else None."""
        try:
            plan = await self._call("get_resource", resource="plan", **self.scope)
            job = await self._call("get_resource", resource="job", **self.scope)
        except Exception:
            return None
        steps = (plan.get("planSteps") or {}).get("steps") or []
        step = next((step for step in steps
                     if str(step.get("stepName", "")).strip().lower() in BUILD_STEP_NAMES), {})
        job_status = (job.get("statusDetails") or {}).get("status")
        self.step_status = step.get("status")
        return end_state(self.step_status, job_status)

    async def _job_output_connector_id(self):
        """Find the workspace's reimagine connector, the one Build writes the progress file through, and remember it."""
        if self._connector_id is None:
            listed = await self._call("list_resources", resource="connectors", workspaceId=self.scope["workspaceId"])
            connector = next((item for item in listed.get("items") or []
                              if JOB_OUTPUT_CONNECTOR_TYPE in str(item.get("connectorType", "")).lower()), None)
            if connector is None:
                raise LookupError(f"no {JOB_OUTPUT_CONNECTOR_TYPE} connector in the workspace")
            self._connector_id = connector["connectorId"]
        return self._connector_id

    async def _call(self, tool, **arguments):
        """Call one AWS Transform MCP tool, the way the agent does, and return its data."""
        if self._session is None:
            raise ConnectionError("the AWS Transform MCP server is not running")
        return tool_data(await self._session.call_tool(tool, arguments))


def time_label(moment):
    """Return a time's local HH:MM:SS label for the page footer."""
    return f"{moment.astimezone():%H:%M:%S}"


def refresh_time():
    """Return now (UTC) and its local HH:MM:SS label for the page footer."""
    now = datetime.now(timezone.utc)
    return now, time_label(now)


def write_starting_page(output, job_id):
    """Write the starting dashboard so the file exists before the first successful read."""
    write_atomically(output, render_page(build_snapshot({}), "starting", *refresh_time(), job_id, True))


async def run(api, output, sleep=asyncio.sleep):
    """Refresh the dashboard every POLL_SECONDS until Build ends; return how it ended, or None if reads kept failing."""
    await api.connect()
    failures, stage, build_start, previous_total = 0, None, None, None
    while True:
        try:
            end = await api.build_state()
            snapshot = await api.snapshot() or build_snapshot({})
            started = snapshot.metric("build_start_time").get("started_at")
            if started and started != build_start:
                stage, build_start, previous_total = None, started, None
            stage = advance(stage, stage_of(snapshot))
            if end is None and api.step_status not in RUNNING_STEP_STATUSES:
                end = "completed" if stage == "completed" else end
            stage = "completed" if end == "completed" else stage
            total = count(snapshot.metric("task_progress"), "total")
            added = total - previous_total if previous_total is not None else 0
            previous_total = total
            write_atomically(output, render_page(snapshot, stage, *refresh_time(), api.job_id, end is None, end,
                                                 api.step_status, tasks_added=added))
            failures = 0
            if end:
                return end
        except Exception:
            failures += 1
            if not output.exists():
                write_starting_page(output, api.job_id)
            if failures >= MAX_CONSECUTIVE_FAILURES:
                return None
            await api.connect()
        await sleep(POLL_SECONDS)


async def build_runs_again(api, sleep=asyncio.sleep):
    """Check the Build step every POLL_SECONDS while the final page is served; True as soon as Build runs again."""
    for _ in range(FINAL_PAGE_GRACE_SECONDS // POLL_SECONDS):
        await sleep(POLL_SECONDS)
        api.step_status = None
        if await api.build_state() is None and api.step_status in RUNNING_STEP_STATUSES:
            return True
        if api.step_status is None:
            await api.connect()
    return False


async def follow_build(api, output, sleep=asyncio.sleep):
    """Keep the dashboard updated until Build ends and through the final page's grace, live again for a rerun; then stop the MCP server."""
    try:
        while True:
            end = await run(api, output, sleep)
            if end is None or not await build_runs_again(api, sleep):
                return end
    finally:
        await api.close()


def job_port(job_id):
    """Pick the same localhost port for the same job, so a restarted script keeps the dashboard link."""
    return DASHBOARD_PORTS[zlib.crc32(job_id.encode("utf-8")) % len(DASHBOARD_PORTS)]


def page_handler(output):
    """Build a request handler that serves only the dashboard page."""
    class DashboardPage(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            """Send the dashboard page as it is on disk now, so every reload shows the latest refresh."""
            if self.path.split("?")[0] not in ("/", f"/{output.name}"):
                self.send_error(404)
                return
            try:
                body = output.read_bytes()
            except OSError:
                self.send_error(503, "The dashboard is starting; reload in a few seconds.")
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return DashboardPage


def start_server(output, job_id):
    """Serve the dashboard on localhost from a background thread, on the job's port or else any free port."""
    handler = page_handler(output)
    try:
        server = http.server.ThreadingHTTPServer((HOST, job_port(job_id)), handler)
    except OSError:
        server = http.server.ThreadingHTTPServer((HOST, 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def stop_server(server, grace_seconds):
    """Keep serving long enough for open browser tabs to load the final page, then stop the server."""
    time.sleep(grace_seconds)
    server.shutdown()
    server.server_close()


def parse_args(argv):
    """Parse --workspace-id, --job-id, --output-dir and the optional --aws-profile."""
    parser = argparse.ArgumentParser(description="Keep ataa_progress_dashboard_<job id>_<start time>.html up to date while Build runs.")
    parser.add_argument("--workspace-id", required=True)
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--output-dir", required=True, help="workspace root, where ataa_progress_dashboard_<job id>_<start time>.html is written")
    parser.add_argument("--aws-profile", help="AWS profile the MCP server signs in with, from get_status sigv4.source AWS_PROFILE=<profile>")
    return parser.parse_args(argv)


def silence_output():
    """Send everything written to stdout and stderr, including the MCP server's logs, to the null device."""
    devnull = os.open(os.devnull, os.O_WRONLY)
    for stream in (sys.stdout, sys.stderr):
        stream.flush()
        os.dup2(devnull, stream.fileno())


def main(argv):
    """Serve the dashboard and keep it updated until Build ends and its final page has been served, then stop serving it."""
    args = parse_args(argv)
    output = Path(args.output_dir).expanduser().resolve() / DASHBOARD_FILE_NAME.format(
        job_id=args.job_id, started=datetime.now().astimezone())
    write_starting_page(output, args.job_id)
    server = start_server(output, args.job_id)
    print(f"Dashboard: [{output}](http://{HOST}:{server.server_port}/)", flush=True)
    silence_output()
    api = TransformClient(args.workspace_id, args.job_id, mcp_server_parameters(args.aws_profile))
    end = asyncio.run(follow_build(api, output))
    stop_server(server, 0 if end else FAILED_READS_GRACE_SECONDS)
    return EXIT_OK if end else EXIT_FAILED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
