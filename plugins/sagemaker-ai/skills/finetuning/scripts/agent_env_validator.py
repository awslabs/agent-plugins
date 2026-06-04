"""Validate user-supplied AGENT_ENV values for the MTRL finetuning flow.

This module implements the deterministic validator referenced as
**Property 6** in
``.kiro/specs/mtrl-finetuning-skill/design.md`` and required by clause
**R5.7** of the same spec's ``requirements.md``:

    IF the user provides an agent environment value that does not match any
    supported pattern (AgentCore ARN, runtime ID, Lambda ARN), THEN THE
    Finetuning Skill SHALL surface an error explaining the supported
    formats.

The helper recognises three string shapes:

* **AgentCore ARN** — ``arn:aws:bedrock-agentcore:<region>:<account>:runtime/<id>``
* **Lambda ARN** — ``arn:aws:lambda:<region>:<account>:function:<name>``
* **Runtime ID** — a bare identifier such as ``my-runtime_01`` (no ``arn:`` prefix)

A ``CustomAgentLambda`` Python object is *not* validated here; it is handled
by the SKILL prose because it is not a string and reaches the trainer SDK
unchanged. This module is pure: no I/O, no network or AWS calls, no logging,
and stdlib-only (``re``).
"""

from __future__ import annotations

import re

# ---------------------------------------------------------------------------
# Regex patterns (anchored, compiled once at import time).
# Kept as module-level constants so tests and other helpers can reuse them.
# ---------------------------------------------------------------------------

#: Bedrock AgentCore runtime ARN.
AGENTCORE_ARN_PATTERN: re.Pattern[str] = re.compile(
    r"^arn:aws:bedrock-agentcore:[^:]+:\d+:runtime/.+$"
)

#: AWS Lambda function ARN.
LAMBDA_ARN_PATTERN: re.Pattern[str] = re.compile(
    r"^arn:aws:lambda:[^:]+:\d+:function:.+$"
)

#: Runtime ID — alphanumeric start, then alphanumerics, underscores, or
#: hyphens. Must be at least two characters and must NOT begin with the
#: literal ``arn:`` prefix (that disambiguates it from malformed ARNs).
RUNTIME_ID_PATTERN: re.Pattern[str] = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]+$")


_SUPPORTED_FORMATS_MESSAGE = (
    "Invalid AGENT_ENV value. Supported formats are:\n"
    "  - Bedrock AgentCore ARN: "
    "arn:aws:bedrock-agentcore:<region>:<account>:runtime/<id>\n"
    "  - AWS Lambda ARN: "
    "arn:aws:lambda:<region>:<account>:function:<name>\n"
    "  - Runtime ID: alphanumeric identifier with optional '-' or '_' "
    "(no 'arn:' prefix)"
)


def validate_agent_env(value: str) -> tuple[bool, str]:
    """Validate an AGENT_ENV string against the three supported formats.

    Args:
        value: The candidate AGENT_ENV string supplied by the user. Must be
            a ``str``; non-strings (including ``None``) are treated as
            invalid input.

    Returns:
        A ``(is_valid, message)`` tuple.

        * On success, ``is_valid`` is ``True`` and ``message`` is one of
          ``"agentcore_arn"``, ``"lambda_arn"``, or ``"runtime_id"`` —
          a short label identifying which format matched. Callers that
          only care about validity can ignore it.
        * On failure, ``is_valid`` is ``False`` and ``message`` is a
          human-readable error listing the supported formats (suitable for
          surfacing to the user verbatim).

    Examples:
        >>> ok, label = validate_agent_env(
        ...     "arn:aws:bedrock-agentcore:us-west-2:123456789012:runtime/my-rt"
        ... )
        >>> ok, label
        (True, 'agentcore_arn')

        >>> ok, label = validate_agent_env(
        ...     "arn:aws:lambda:us-east-1:123456789012:function:my-fn"
        ... )
        >>> ok, label
        (True, 'lambda_arn')

        >>> ok, label = validate_agent_env("my-runtime_01")
        >>> ok, label
        (True, 'runtime_id')

        >>> ok, _ = validate_agent_env("not a real value")
        >>> ok
        False

        >>> ok, _ = validate_agent_env("arn:aws:s3:::my-bucket")
        >>> ok
        False
    """
    # Defensive type check: this helper is documented as taking ``str``,
    # but be explicit so test harnesses that pass ``None`` or other types
    # get a deterministic failure rather than a TypeError from ``re``.
    if not isinstance(value, str):
        return False, _SUPPORTED_FORMATS_MESSAGE

    if AGENTCORE_ARN_PATTERN.match(value):
        return True, "agentcore_arn"

    if LAMBDA_ARN_PATTERN.match(value):
        return True, "lambda_arn"

    # Runtime ID must NOT start with ``arn:`` — that prefix is reserved for
    # ARN shapes and a malformed ARN should not silently masquerade as an
    # identifier.
    if not value.startswith("arn:") and RUNTIME_ID_PATTERN.match(value):
        return True, "runtime_id"

    return False, _SUPPORTED_FORMATS_MESSAGE
