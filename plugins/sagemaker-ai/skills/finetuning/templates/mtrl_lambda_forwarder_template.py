"""Lambda forwarder template for MTRL custom-agent environments.

This module is a starting point for users who want to use a custom agent
environment (EKS, Fargate, ECS, an HTTP service, an SQS-backed worker, ...)
as the rollout target for `MultiTurnRLTrainer`. The SageMaker MTRL service
sends rollout requests to this Lambda; the Lambda forwards them to your
agent platform and returns the agent's response.

Usage:
    1. Set the AGENT_ENDPOINT and AGENT_API_KEY environment variables on
       the Lambda function (prefer AWS Secrets Manager for the API key).
    2. Customise `_call_agent` so it speaks your platform's request /
       response shape.
    3. Customise `_handle_agent_error` if your platform surfaces error
       codes or response shapes that need translating to the four
       supported `errorType` values: ``ValidationError``, ``Throttling``,
       ``InternalServerError``, ``AccessDenied``.
    4. Deploy via `CustomAgentLambda.create(source="<path-to-this-file>", ...)`
       or by uploading directly to AWS Lambda and passing the function
       ARN as `agent_env=` to `MultiTurnRLTrainer`.

If your agent environment does not expose a public HTTP endpoint, replace
the body of ``_call_agent`` with an SQS ``send_message`` call to enqueue
the request, and have your agent poll the queue for work.

This template is adapted from Section 5 of
``v3-examples/model-customization-examples/mtrl_finetuning_example_notebook_v3_prod.ipynb``
in ``sagemaker-python-sdk-staging`` (master-mtrl-trainer branch).
"""

import json
import logging
import os
import re
import urllib.error
import urllib.request

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

AGENT_ENDPOINT = os.environ.get("AGENT_ENDPOINT", "")
AGENT_API_KEY = os.environ.get("AGENT_API_KEY", "")

_SAFE_ID = re.compile(r"^[\w\-.]+$")


# ---------------------------------------------------------------------------
# CUSTOMISE THIS — translate the rollout request to your platform's API.
# ---------------------------------------------------------------------------
def _call_agent(prompt: str, inference_params: dict) -> dict:
    """Forward the prompt to your agent platform and return its response.

    Replace the body below with your platform's request format. The
    SageMaker MTRL service does not require any specific response shape;
    it only checks for an error envelope (see ``_handle_agent_error``).
    """
    payload = json.dumps({
        "prompt": prompt,
        "inferenceParams": inference_params,
    }).encode()

    req = urllib.request.Request(
        AGENT_ENDPOINT,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {AGENT_API_KEY}",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=120) as resp:  # noqa: S310 - HTTPS endpoint expected
        return json.loads(resp.read())


# ---------------------------------------------------------------------------
# Validation — no changes needed.
# ---------------------------------------------------------------------------
def _validate(event: dict) -> dict:
    body = json.loads(event["body"]) if isinstance(event.get("body"), str) else event

    prompt = body.get("prompt")
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError("'prompt' is required and must be a non-empty string")

    meta = body.get("metadata")
    if not isinstance(meta, dict):
        raise ValueError("'metadata' is required")
    for key in ("jobId", "experimentId", "rolloutId"):
        val = meta.get(key)
        if not isinstance(val, str) or not _SAFE_ID.match(val):
            raise ValueError(f"metadata.{key} must match [a-zA-Z0-9_\\-.]")

    params = body.get("inferenceParams") or {}
    if not isinstance(params, dict):
        raise ValueError("'inferenceParams' must be an object")

    return {
        "prompt": prompt.strip(),
        "metadata": {k: meta[k] for k in ("jobId", "experimentId", "rolloutId")},
        "inferenceParams": params,
    }


# ---------------------------------------------------------------------------
# CUSTOMISE THIS — handle errors thrown from your agent environment.
# Supported errorType values: ValidationError, Throttling,
# InternalServerError, AccessDenied.
# ---------------------------------------------------------------------------
def _handle_agent_error(exc: Exception) -> dict:
    logger.exception("Agent environment error")
    if isinstance(exc, urllib.error.HTTPError):
        code = exc.code
        if code == 403:
            return {"errorType": "AccessDenied", "error": "Agent denied access"}
        if code == 429:
            return {"errorType": "Throttling", "error": "Agent rate limit exceeded"}
        if 400 <= code < 500:
            return {"errorType": "ValidationError", "error": str(exc)}
        return {"errorType": "InternalServerError", "error": str(exc)}
    return {"errorType": "InternalServerError", "error": str(exc)}


def lambda_handler(event, context):
    """AWS Lambda entrypoint.

    The SageMaker MTRL service invokes this handler for every rollout. On
    success the handler returns an empty dict (``{}``); on failure it
    returns one of the four error envelopes described in
    ``_handle_agent_error``.
    """
    try:
        body = _validate(event)
    except ValueError as exc:
        logger.warning("Validation error: %s", exc)
        return {"errorType": "ValidationError", "error": str(exc)}

    try:
        _call_agent(body["prompt"], body["inferenceParams"])
        logger.info("Rollout %s completed", body["metadata"]["rolloutId"])
        return {}
    except Exception as exc:  # noqa: BLE001 - intentionally broad; handler reshapes
        return _handle_agent_error(exc)
