"""Auto-select the evaluation type from a training job's tags.

This module implements the deterministic helper referenced as
**Property 9 (MTRL Evaluation auto-selection)** in
``.kiro/specs/mtrl-finetuning-skill/design.md``. It encodes the rule
required by:

* **R7.2** — When the model under evaluation was trained with the MTRL
  technique, the Model_Evaluation Skill SHALL select MTRL Evaluation
  automatically and confirm the choice with the user before generating
  cells.
* **R10.4** — The Planning Skill SHALL recommend ``MTRLEvaluator``-based
  model evaluation when the plan's training step is MTRL, rather than
  recommending LLM-as-Judge or Custom Scorer.

The helper inspects a SageMaker training job's tags and decides whether
the job was produced by an MTRL run. If so, the
``model-evaluation`` skill (and the ``planning`` skill, transitively)
defaults the evaluation type to the literal string
``"MTRL Evaluation"``. The user still confirms before any cells are
generated — this helper only computes the **default**.

Returning ``None`` is a deliberate "no signal" answer: the caller falls
back to its existing logic (typically prompting the user to choose
between LLM-as-Judge and Custom Scorer). The helper is intentionally
**conservative**: it requires both an MTRL-shaped value *and* a
training-shaped key so that an unrelated tag like
``description=mtrl-related-experiment`` does not trigger a false
positive.

This module is pure: no I/O, no network or AWS calls, no logging, and
stdlib-only.
"""

from __future__ import annotations

from typing import Iterator, Mapping

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

#: The string returned when the helper detects an MTRL training job.
MTRL_EVAL_TYPE: str = "MTRL Evaluation"

#: Substring (case-insensitive) that must appear in a tag value.
_MTRL_VALUE_TOKEN: str = "mtrl"

#: Substrings that mark the tag key as training-related.
_TRAINING_KEY_TOKENS: tuple[str, ...] = ("recipe", "technique")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _iter_tag_pairs(tags: object) -> Iterator[tuple[str, str]]:
    """Yield ``(key, value)`` string pairs from either tag shape.

    The SageMaker SDK exposes training-job tags in two shapes that we
    must accept transparently:

    1. A mapping like ``{"key": "value", ...}`` (dict-shaped).
    2. A list of single-tag dicts like
       ``[{"Key": "key", "Value": "value"}, ...]`` (list-shaped, the
       boto3 / Coral wire shape).

    This helper normalises both into an iterator of string pairs.
    Non-string keys / values, malformed entries, or unrecognised tag
    shapes are silently skipped.
    """
    if tags is None:
        return

    # Dict / mapping shape.
    if isinstance(tags, Mapping):
        for key, value in tags.items():
            if isinstance(key, str) and isinstance(value, str):
                yield key, value
        return

    # List-of-dicts shape (the boto3 ``Tags=[{Key,Value}, ...]`` form).
    if isinstance(tags, (str, bytes)):
        return

    try:
        iterator = iter(tags)  # type: ignore[arg-type]
    except TypeError:
        return

    for entry in iterator:
        if not isinstance(entry, Mapping):
            continue
        key = entry.get("Key")
        if not isinstance(key, str):
            key = entry.get("key")
        value = entry.get("Value")
        if not isinstance(value, str):
            value = entry.get("value")
        if isinstance(key, str) and isinstance(value, str):
            yield key, value


def _is_mtrl_signal(key: str, value: str) -> bool:
    """Return ``True`` iff ``(key, value)`` indicates MTRL.

    The detection rule is intentionally narrow:

    * The value must contain the substring ``"mtrl"`` (case-insensitive).
    * The key must contain at least one of the training-shaped tokens
      (``"recipe"`` or ``"technique"``, case-insensitive).

    Both halves are required to avoid false positives on unrelated
    tags whose value happens to mention MTRL.
    """
    key_lower = key.lower()
    value_lower = value.lower()

    if _MTRL_VALUE_TOKEN not in value_lower:
        return False

    return any(token in key_lower for token in _TRAINING_KEY_TOKENS)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def auto_select_eval_type(training_job_tags: dict | list) -> str | None:
    """Auto-select the evaluation type from a training job's tags.

    The helper inspects ``training_job_tags`` and returns the literal
    string ``"MTRL Evaluation"`` when the tags clearly indicate an MTRL
    training run. Otherwise it returns ``None``, signalling to the
    caller that no auto-selection was made and the existing
    LLM-as-Judge / Custom Scorer prompt flow should run.

    Detection rule (Property 9, conservative):

    * Any tag whose **value** contains the substring ``"mtrl"``
      (case-insensitive) **and** whose **key** contains at least one
      of ``"recipe"`` or ``"technique"`` (case-insensitive).

    Args:
        training_job_tags: The tag collection attached to a SageMaker
            training job. Accepted shapes:

            * A ``dict`` mapping tag key to tag value.
            * A ``list`` of single-tag dicts (the boto3 wire shape):
              ``[{"Key": "...", "Value": "..."}, ...]``.

            ``None``, empty containers, malformed entries, or any other
            shape are treated as "no signal" and yield ``None``.

    Returns:
        ``"MTRL Evaluation"`` when at least one tag matches the
        detection rule; ``None`` otherwise.

    Examples:
        >>> auto_select_eval_type(
        ...     {"sagemaker:training_recipe": "finetuning_mtrl_grpo"}
        ... )
        'MTRL Evaluation'

        >>> auto_select_eval_type([
        ...     {"Key": "sagemaker-studio:hyperparameters:training_recipe",
        ...      "Value": "finetuning_mtrl_central"},
        ... ])
        'MTRL Evaluation'

        >>> auto_select_eval_type(
        ...     {"sagemaker:training_recipe": "finetuning_sft_v2"}
        ... ) is None
        True

        >>> auto_select_eval_type({"description": "mtrl-experiment"}) is None
        True

        >>> auto_select_eval_type(None) is None
        True
    """
    for key, value in _iter_tag_pairs(training_job_tags):
        if _is_mtrl_signal(key, value):
            return MTRL_EVAL_TYPE

    return None
