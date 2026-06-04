"""Select the correct Bedrock deploy kwarg name for a JumpStart model id.

This module implements the deterministic helper referenced as
**Property 10 (Bedrock deployment Nova vs non-Nova selector)** in
``.kiro/specs/mtrl-finetuning-skill/design.md``. It encodes the rule
required by:

* **R8.5** — When the user selects Bedrock deployment for an MTRL model,
  the Model_Deployment Skill SHALL generate cells using
  ``BedrockModelBuilder`` and call ``bedrock_builder.deploy(...)`` with
  the appropriate ``custom_model_name`` (Nova) or ``imported_model_name``
  (non-Nova) parameter.

The helper is consumed by the ``model-deployment`` skill when it
materialises ``scripts/deploy-mtrl-bedrock.py`` — specifically when it
fills the ``[DEPLOY_KWARG_NAME]`` placeholder in Cell 4. The selection
rule is a simple prefix check on the JumpStart model id:

* ``nova-*`` → ``"custom_model_name"`` (Nova-family models register as
  Bedrock *custom* models because they share the Bedrock Nova model
  family).
* every other id → ``"imported_model_name"`` (open-weights / community
  models register as Bedrock *imported* models).

This module is pure: no I/O, no network or AWS calls, no logging, and
stdlib-only.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

#: Prefix that marks a Nova-family JumpStart base model. The id
#: convention used across this plugin places the family vendor first
#: (e.g. ``nova-pro``, ``nova-lite``, ``nova-micro``), so a simple
#: ``startswith`` check is sufficient and matches the design's wording
#: in Property 10 ("id starts with ``nova-``").
NOVA_PREFIX: str = "nova-"

#: Kwarg name accepted by ``BedrockModelBuilder.deploy(...)`` for
#: Nova-family models.
CUSTOM_MODEL_NAME_KWARG: str = "custom_model_name"

#: Kwarg name accepted by ``BedrockModelBuilder.deploy(...)`` for every
#: other model id. This is the safer default when the input cannot be
#: classified (e.g. non-string input), because the Nova path is a
#: narrower category and mis-routing a non-Nova model to
#: ``custom_model_name`` would surface a Bedrock validation error,
#: whereas the imported-model path is the catch-all for all other
#: open-weights deployments.
IMPORTED_MODEL_NAME_KWARG: str = "imported_model_name"


def select_bedrock_deploy_kwarg(jumpstart_model_id: str) -> str:
    """Return the Bedrock deploy kwarg name for a JumpStart model id.

    The selection is governed by a single rule (Property 10 in the
    design document):

    * If ``jumpstart_model_id`` is a string starting with ``nova-``,
      return ``"custom_model_name"``.
    * Otherwise, return ``"imported_model_name"``.

    Non-string input (``None``, integers, objects) is treated as
    non-Nova and routed to ``"imported_model_name"``. This is the
    safer default because Nova is the narrower category — if the
    caller hands us a value we cannot classify, we fall back to the
    catch-all import path rather than silently selecting the
    custom-model path.

    Args:
        jumpstart_model_id: The JumpStart base model id (e.g.
            ``"nova-pro"``, ``"openai-gpt-oss-20b"``,
            ``"meta-llama-3-8b"``). Must be a ``str``; non-strings are
            treated defensively as non-Nova.

    Returns:
        Either ``"custom_model_name"`` or ``"imported_model_name"``.
        The returned string is the kwarg name the caller must use when
        invoking ``BedrockModelBuilder.deploy(...)``.

    Examples:
        Nova-family models route to ``custom_model_name``:

        >>> select_bedrock_deploy_kwarg("nova-pro")
        'custom_model_name'
        >>> select_bedrock_deploy_kwarg("nova-lite")
        'custom_model_name'
        >>> select_bedrock_deploy_kwarg("nova-micro")
        'custom_model_name'

        Every other id routes to ``imported_model_name``:

        >>> select_bedrock_deploy_kwarg("openai-gpt-oss-20b")
        'imported_model_name'
        >>> select_bedrock_deploy_kwarg("meta-llama-3-8b")
        'imported_model_name'
        >>> select_bedrock_deploy_kwarg("mistral-7b")
        'imported_model_name'

        The match is case-sensitive — only the lowercase ``nova-``
        prefix triggers the Nova path:

        >>> select_bedrock_deploy_kwarg("Nova-Pro")
        'imported_model_name'

        Non-string input falls back to the safer default:

        >>> select_bedrock_deploy_kwarg(None)
        'imported_model_name'
        >>> select_bedrock_deploy_kwarg("")
        'imported_model_name'
    """
    # Defensive type check: callers are documented to pass strings, but
    # a non-string ``jumpstart_model_id`` would crash inside
    # ``startswith``. Treat non-strings as non-Nova and route to the
    # imported-model path; this is the most conservative behaviour
    # because Nova is the narrower category.
    if isinstance(jumpstart_model_id, str) and jumpstart_model_id.startswith(
        NOVA_PREFIX
    ):
        return CUSTOM_MODEL_NAME_KWARG

    return IMPORTED_MODEL_NAME_KWARG
