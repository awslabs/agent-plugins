"""Recommend a SageMaker instance type from a model's parameter count.

This module implements the deterministic helper referenced as
**Property 11 (SageMaker instance recommendation parity)** in
``.kiro/specs/mtrl-finetuning-skill/design.md``. It encodes the rule
required by:

* **R8.4** — When the user selects SageMaker endpoint deployment for an
  MTRL model, the Model_Deployment Skill SHALL recommend an instance type
  based on model size, **consistent with the existing OSS instance
  recommendations**.

The table reused below is the one documented in the OSS LoRA pathway at
``agent-plugins/plugins/sagemaker-ai/skills/model-deployment/references/deploy-oss-sagemaker.md``
("Step 2: Determine Instance Type"):

* Small models (<3B):    ``ml.g5.2xlarge``  (1 GPU, ~24GB)
* Medium models (<10B):  ``ml.g5.12xlarge`` (4 GPUs, ~96GB)
* Large models (>10B):   ``ml.g6e.48xlarge`` (8 GPUs, ~1TB)

Property 11 is stated as: for any model size bucket
B ∈ {<3B, <10B, ≥10B}, the recommended SageMaker instance type for an
MTRL deployment in that bucket equals the recommended instance type for
an OSS LoRA deployment in the same bucket. To make the buckets cover the
real line without gaps (the OSS doc reads "<3B / <10B / >10B", which
leaves an ambiguous point at exactly 10B), this helper treats the upper
bucket as **≥10B** rather than strict ``>10B``. This is a deliberate
deviation from the OSS doc wording — the bucket *labels* in Property 11
already use ``≥10B`` and the boundary value 10.0 must map to the large
instance to keep the partition complete.

This module is pure: no I/O, no network or AWS calls, no logging, and
stdlib-only.
"""

from __future__ import annotations

from numbers import Real

# ---------------------------------------------------------------------------
# Bucket boundaries (in billions of parameters).
# ---------------------------------------------------------------------------

#: Upper boundary (exclusive) of the small bucket: any model strictly
#: smaller than 3B parameters maps to :data:`SMALL_INSTANCE`.
SMALL_BUCKET_MAX_B: float = 3.0

#: Upper boundary (exclusive) of the medium bucket: any model in
#: ``[3B, 10B)`` maps to :data:`MEDIUM_INSTANCE`. Model sizes at or
#: above this value map to :data:`LARGE_INSTANCE`.
MEDIUM_BUCKET_MAX_B: float = 10.0

# ---------------------------------------------------------------------------
# Recommended instance types (verbatim from the OSS LoRA reference doc).
# ---------------------------------------------------------------------------

#: SageMaker instance for ``<3B`` models — 1 GPU, ~24GB.
SMALL_INSTANCE: str = "ml.g5.2xlarge"

#: SageMaker instance for ``[3B, 10B)`` models — 4 GPUs, ~96GB.
MEDIUM_INSTANCE: str = "ml.g5.12xlarge"

#: SageMaker instance for ``≥10B`` models — 8 GPUs, ~1TB.
LARGE_INSTANCE: str = "ml.g6e.48xlarge"


def recommend_instance_type(model_size_b: float) -> str:
    """Return the recommended SageMaker instance type for a model size.

    The recommendation follows the OSS LoRA table reused by the MTRL
    deployment pathway (Property 11 in the design document):

    * ``model_size_b < 3``   → :data:`SMALL_INSTANCE`  (``ml.g5.2xlarge``)
    * ``3 ≤ model_size_b < 10`` → :data:`MEDIUM_INSTANCE` (``ml.g5.12xlarge``)
    * ``model_size_b ≥ 10``  → :data:`LARGE_INSTANCE`  (``ml.g6e.48xlarge``)

    ``model_size_b`` is the model size **in billions of parameters**, so
    a 7B model is passed as ``7.0`` and a 70B model as ``70.0``. Booleans
    are explicitly rejected even though Python's numeric tower would
    otherwise let them through, because passing ``True`` or ``False``
    here is almost always a type error at the call site.

    Args:
        model_size_b: Model size in billions of parameters. Must be a
            non-negative real number (``int`` or ``float``).

    Returns:
        One of :data:`SMALL_INSTANCE`, :data:`MEDIUM_INSTANCE`, or
        :data:`LARGE_INSTANCE`.

    Raises:
        ValueError: If ``model_size_b`` is ``None``, not a real number,
            a boolean, ``NaN``, or strictly negative. The message lists
            the supported input shape so the caller can surface it
            verbatim.

    Examples:
        Small bucket — strictly below 3B:

        >>> recommend_instance_type(0.5)
        'ml.g5.2xlarge'
        >>> recommend_instance_type(2.999)
        'ml.g5.2xlarge'

        Medium bucket — 3B (inclusive) up to 10B (exclusive):

        >>> recommend_instance_type(3.0)
        'ml.g5.12xlarge'
        >>> recommend_instance_type(7.0)
        'ml.g5.12xlarge'
        >>> recommend_instance_type(9.999)
        'ml.g5.12xlarge'

        Large bucket — 10B and above:

        >>> recommend_instance_type(10.0)
        'ml.g6e.48xlarge'
        >>> recommend_instance_type(70.0)
        'ml.g6e.48xlarge'

        Integer inputs are accepted (a 7B model can be passed as ``7``):

        >>> recommend_instance_type(7)
        'ml.g5.12xlarge'

        Zero is treated as a very small model:

        >>> recommend_instance_type(0)
        'ml.g5.2xlarge'

        Invalid inputs raise ``ValueError``:

        >>> recommend_instance_type(-1.0)
        Traceback (most recent call last):
            ...
        ValueError: model_size_b must be a non-negative real number (got -1.0)
        >>> recommend_instance_type(None)
        Traceback (most recent call last):
            ...
        ValueError: model_size_b must be a non-negative real number (got None)
        >>> recommend_instance_type("7B")
        Traceback (most recent call last):
            ...
        ValueError: model_size_b must be a non-negative real number (got '7B')
        >>> recommend_instance_type(True)
        Traceback (most recent call last):
            ...
        ValueError: model_size_b must be a non-negative real number (got True)
    """
    # Reject booleans up front. ``bool`` is a subclass of ``int``, so a
    # naive ``isinstance(..., Real)`` check would let ``True``/``False``
    # through and silently route them to the small-bucket branch.
    # Passing a boolean here is almost always a type error at the call
    # site, so fail fast with a clear message.
    if isinstance(model_size_b, bool):
        raise ValueError(
            f"model_size_b must be a non-negative real number "
            f"(got {model_size_b!r})"
        )

    # Reject anything that isn't a real number (covers ``None``, strings,
    # complex numbers, arbitrary objects). ``numbers.Real`` matches
    # ``int`` and ``float`` (and ``Fraction``, ``Decimal`` is *not*
    # ``Real`` — that's fine, callers in this plugin only pass int/float).
    if not isinstance(model_size_b, Real):
        raise ValueError(
            f"model_size_b must be a non-negative real number "
            f"(got {model_size_b!r})"
        )

    # Reject NaN explicitly: ``float('nan') < 3.0`` is ``False``, so a
    # NaN input would fall through to the large bucket and silently
    # recommend the most expensive instance. Surface the bug instead.
    # ``x != x`` is the canonical NaN check that works without importing
    # ``math`` and remains correct for non-float ``Real`` subclasses.
    if model_size_b != model_size_b:
        raise ValueError(
            f"model_size_b must be a non-negative real number "
            f"(got {model_size_b!r})"
        )

    if model_size_b < 0:
        raise ValueError(
            f"model_size_b must be a non-negative real number "
            f"(got {model_size_b!r})"
        )

    if model_size_b < SMALL_BUCKET_MAX_B:
        return SMALL_INSTANCE

    if model_size_b < MEDIUM_BUCKET_MAX_B:
        return MEDIUM_INSTANCE

    return LARGE_INSTANCE
