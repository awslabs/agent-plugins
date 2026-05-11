"""Tests for plugins/databases-on-aws/skills/dsql/mcp/tools/safe_query.py.

Run with pytest: `pytest tools/evals/databases-on-aws/dsql/scripts/test_safe_query.py`
Or directly:    `python tools/evals/databases-on-aws/dsql/scripts/test_safe_query.py`

Covers build()'s core invariants (rejects raw strings, rejects
template/kwargs mismatch), the regex() single-quote guard, plus an
adversarial injection corpus for each validator.
"""

import re
import sys
from pathlib import Path

SAFE_QUERY_DIR = (
    Path(__file__).resolve().parent.parent.parent.parent.parent.parent
    / "plugins" / "databases-on-aws" / "skills" / "dsql" / "mcp" / "tools"
)
sys.path.insert(0, str(SAFE_QUERY_DIR))

try:
    import pytest
except ImportError:
    # Allow the __main__ fallback runner to work without pytest installed.
    # @pytest.mark.parametrize becomes a no-op decorator; fixtures aren't used.
    class _PytestShim:
        class mark:
            @staticmethod
            def parametrize(*_args, **_kwargs):
                return lambda fn: fn

        class raises:
            def __init__(self, exc):
                self.exc = exc

            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                if exc_type is None:
                    raise AssertionError(f"expected {self.exc.__name__}, no exception raised")
                return issubclass(exc_type, self.exc)

    pytest = _PytestShim()

from safe_query import (  # noqa: E402
    INT,
    TENANT_SLUG,
    UUID,
    Safe,
    UnsafeSQLError,
    allow,
    build,
    ident,
    integer,
    keyword,
    literal,
    regex,
)


TENANT_INJECTIONS = [
    "abc' OR 1=1 --",
    "abc' OR tenant_id IS NOT NULL --",
    "abc' OR tenant_id > '' --",
    "abc' UNION SELECT * FROM users --",
    "abc' AND EXISTS (SELECT 1 FROM users) --",
    "abc'; DROP TABLE entities; --",
    "abc') OR 1=1 --",
    "abc\x00ignored",
    "abc\nmultiline",
    "ABC",  # TENANT_SLUG is lowercase-only
    "abc def",
    "a" * 65,
    "",
]

UUID_INJECTIONS = [
    "not-a-uuid",
    "'; DROP TABLE t; --",
    "00000000-0000-0000-0000-000000000000 OR 1=1",
    "00000000-0000-0000-0000",
    "00000000-0000-0000-0000-000000000000-extra",
]

IDENT_INJECTIONS = [
    'entities" OR 1=1 --',
    "entities; DROP TABLE",
    "1entities",  # leading digit
    "entities-table",  # hyphen
    "",
    "a" * 64,  # over length
    "entities.users",  # qualified names not supported
]

INT_INJECTIONS = [
    "1; DROP",
    "1 OR 1=1",
    "1.5",
    "",
    "abc",
    True,
    False,
    None,
]


@pytest.mark.parametrize("payload", TENANT_INJECTIONS)
def test_tenant_slug_rejects_injection(payload):
    with pytest.raises(UnsafeSQLError):
        regex(payload, TENANT_SLUG)


@pytest.mark.parametrize("payload", UUID_INJECTIONS)
def test_uuid_rejects_injection(payload):
    with pytest.raises(UnsafeSQLError):
        regex(payload, UUID)


@pytest.mark.parametrize("payload", IDENT_INJECTIONS)
def test_ident_rejects_injection(payload):
    with pytest.raises(UnsafeSQLError):
        ident(payload)


@pytest.mark.parametrize("payload", INT_INJECTIONS)
def test_integer_rejects_injection(payload):
    with pytest.raises(UnsafeSQLError):
        integer(payload)


@pytest.mark.parametrize("payload", ["x' OR 1=1 --", "it's", "'"])
def test_regex_rejects_embedded_single_quote(payload):
    """regex() must reject values containing ' even if the pattern matches.

    Built-in patterns (TENANT_SLUG, UUID) already forbid ', but callers can
    supply their own patterns. A permissive pattern that admits ' would
    otherwise produce a SQL-injection literal.
    """
    permissive = re.compile(r".+")
    with pytest.raises(UnsafeSQLError):
        regex(payload, permissive)


def test_regex_rejects_null_byte():
    """regex() must reject values containing a null byte (defense-in-depth)."""
    permissive = re.compile(r".+", re.DOTALL)
    with pytest.raises(UnsafeSQLError):
        regex("abc\x00tail", permissive)


def test_allow_rejects_outside_set():
    with pytest.raises(UnsafeSQLError):
        allow("evil", {"ok"})
    with pytest.raises(UnsafeSQLError):
        allow("", {"ok"})


def test_allow_escapes_embedded_quote():
    """allow() belt-and-braces escaping handles quotes in the allowlist."""
    assert str(allow("it's", {"it's"})) == "'it''s'"  # nosec B101 - test assertion


def test_keyword_rejects_outside_set():
    with pytest.raises(UnsafeSQLError):
        keyword("DROP", {"ASC", "DESC"})


def test_build_rejects_raw_strings():
    """build() must never accept a raw string — the core invariant."""
    with pytest.raises(UnsafeSQLError):
        build("SELECT {x}", x="anything")
    with pytest.raises(UnsafeSQLError):
        build("SELECT {x}", x=123)
    with pytest.raises(UnsafeSQLError):
        build("SELECT {x}", x=None)
    with pytest.raises(UnsafeSQLError):
        build("SELECT {x}", x=["list"])


def test_build_rejects_extra_keys():
    """build() must reject kwargs not present in the template."""
    with pytest.raises(UnsafeSQLError):
        build(
            "SELECT * FROM {tbl} WHERE id = {eid}",
            tbl=ident("entities"),
            eid=regex("acme", TENANT_SLUG),
            tid=regex("extra", TENANT_SLUG),
        )


def test_build_rejects_missing_keys():
    """build() must reject templates with placeholders not covered by kwargs."""
    with pytest.raises(UnsafeSQLError):
        build(
            "SELECT * FROM {tbl} WHERE id = {eid} AND tenant_id = {tid}",
            tbl=ident("entities"),
            eid=regex("acme", TENANT_SLUG),
        )


def test_build_rejects_complete_mismatch():
    """build() must reject when keys are entirely wrong."""
    with pytest.raises(UnsafeSQLError):
        build(
            "SELECT {x} FROM {y}",
            a=ident("col"),
            b=ident("tbl"),
        )


def test_build_rejects_extra_keys_no_placeholders():
    """A template with no placeholders plus kwargs = silently dropped filter."""
    with pytest.raises(UnsafeSQLError):
        build("SELECT * FROM entities", tid=regex("acme", TENANT_SLUG))


def test_build_mismatch_error_names_keys():
    """Error message must report which keys are missing and which are extra."""
    try:
        build(
            "SELECT {x} FROM {y}",
            x=ident("col"),
            z=ident("extra"),
        )
        raise RuntimeError("expected UnsafeSQLError")
    except UnsafeSQLError as e:
        msg = str(e)
        assert "y" in msg, "missing key 'y' not named in error"  # nosec B101 - test assertion
        assert "z" in msg, "extra key 'z' not named in error"  # nosec B101 - test assertion


@pytest.mark.parametrize("payload", ["abc\\", "a\\b"])
def test_regex_rejects_backslash(payload):
    """regex() must reject values containing backslash (defense-in-depth)."""
    permissive = re.compile(r".+")
    with pytest.raises(UnsafeSQLError):
        regex(payload, permissive)


def test_regex_permissive_pattern_accepts_clean_value():
    """regex() must still accept values without quotes under a permissive pattern."""
    permissive = re.compile(r".+")
    result = regex("hello-world", permissive)
    assert isinstance(result, Safe)  # nosec B101 - test assertion
    assert str(result) == "'hello-world'"  # nosec B101 - test assertion


@pytest.mark.parametrize("template", ["SELECT {x!r}", "SELECT {x!s}", "SELECT {x!a}"])
def test_build_rejects_format_conversion(template):
    """build() must reject !r, !s, !a conversions that corrupt Safe values."""
    with pytest.raises(UnsafeSQLError):
        build(template, x=ident("col"))


@pytest.mark.parametrize("template", ["SELECT {x:>30}", "SELECT {x:.5}"])
def test_build_rejects_format_spec(template):
    """build() must reject format specs that pad/transform Safe values."""
    with pytest.raises(UnsafeSQLError):
        build(template, x=ident("col"))


def test_build_rejects_positional_placeholders():
    """build() must reject {} and {0} — only named placeholders allowed."""
    with pytest.raises(UnsafeSQLError):
        build("SELECT {}", x=ident("col"))
    with pytest.raises(UnsafeSQLError):
        build("SELECT {0}", x=ident("col"))
    with pytest.raises(UnsafeSQLError):
        build("SELECT {0} FROM {1}")


def test_build_duplicate_placeholder():
    """Same placeholder used twice in a template must work (e.g. subquery + outer)."""
    sql = build(
        "SELECT {x} FROM {y} WHERE {x} = 1",
        x=ident("col"),
        y=ident("tbl"),
    )
    assert sql == 'SELECT "col" FROM "tbl" WHERE "col" = 1'  # nosec B101 - test assertion


def test_build_accepts_safe_values():
    sql = build(
        "SELECT * FROM {t} WHERE tenant_id = {tid} AND id = {i}",
        t=ident("entities"),
        tid=regex("acme", TENANT_SLUG),
        i=integer(42),
    )
    assert sql == 'SELECT * FROM "entities" WHERE tenant_id = \'acme\' AND id = 42'  # nosec B101 - test assertion


def test_literal_dollar_quotes_dangerous_input():
    payload = "o'reilly; DROP TABLE t; --"
    out = str(literal(payload))
    assert out.startswith("$dq_")  # nosec B101 - test assertion
    assert payload in out  # nosec B101 - test assertion
    # The tag itself must not appear inside the payload, or it would terminate
    # the dollar-quoted literal early.
    tag = out.split("$", 2)[1]
    assert f"${tag}$" not in payload  # nosec B101 - test assertion


def test_literal_rejects_non_string():
    with pytest.raises(UnsafeSQLError):
        literal(123)
    with pytest.raises(UnsafeSQLError):
        literal(None)


def test_literal_tag_exhaustion(monkeypatch):
    """literal() must raise UnsafeSQLError when all 8 tag attempts collide."""
    import safe_query as sq
    monkeypatch.setattr(sq.secrets, "token_hex", lambda _: "deadbeef")
    with pytest.raises(UnsafeSQLError):
        sq.literal("$dq_deadbeef$injected$dq_deadbeef$")


def test_literal_tag_retry_on_partial_collision(monkeypatch):
    """literal() must retry when the first tag collides, succeeding on a later attempt."""
    import safe_query as sq
    calls = iter(["deadbeef", "deadbeef", "cafecafe"])
    monkeypatch.setattr(sq.secrets, "token_hex", lambda _: next(calls))
    out = str(sq.literal("$dq_deadbeef$injected$dq_deadbeef$"))
    assert "$dq_cafecafe$" in out  # nosec B101 - test assertion
    assert "$dq_deadbeef$injected$dq_deadbeef$" in out  # nosec B101 - test assertion


def test_literal_dollar_quote_collision():
    """literal() must handle input containing a $dq_...$ pattern safely."""
    payload = "$dq_deadbeef$injected$dq_deadbeef$"
    out = str(literal(payload))
    assert out.startswith("$dq_")  # nosec B101 - test assertion
    assert payload in out  # nosec B101 - test assertion
    tag = out.split("$", 2)[1]
    assert f"${tag}$" not in payload  # nosec B101 - test assertion


def test_build_rejects_non_string_template():
    """build() must raise UnsafeSQLError for non-string templates."""
    with pytest.raises(UnsafeSQLError):
        build(None)
    with pytest.raises(UnsafeSQLError):
        build(123)
    with pytest.raises(UnsafeSQLError):
        build(["SELECT 1"])


def test_safe_value_cannot_be_forged_from_plain_string():
    """The only route to a Safe value is a validator."""
    assert not isinstance("raw", Safe)  # nosec B101 - test assertion
    assert isinstance(allow("x", {"x"}), Safe)  # nosec B101 - test assertion
    assert isinstance(regex("abc", re.compile("abc")), Safe)  # nosec B101 - test assertion


def test_full_insert_never_emits_bare_dangerous_chars():
    """End-to-end: a realistic multi-tenant insert with a hostile name."""
    sql = build(
        "INSERT INTO {tbl} (entity_id, tenant_id, name, priority) "
        "VALUES ({eid}, {tid}, {name}, {p})",
        tbl=ident("entities"),
        eid=regex("a1b2c3d4-e5f6-7890-abcd-ef0123456789", UUID),
        tid=regex("tenant-1", TENANT_SLUG),
        name=literal("Acme Corp; DROP TABLE t; --"),
        p=integer(5),
    )
    assert "$dq_" in sql  # nosec B101 - test assertion
    assert sql.count("'") == 4  # nosec B101 - test assertion
    assert "'Acme Corp; DROP" not in sql  # nosec B101 - test assertion


if __name__ == "__main__":
    # Fallback runner for environments without pytest.
    import traceback

    tests = [
        (name, fn)
        for name, fn in globals().items()
        if name.startswith("test_") and callable(fn)
    ]
    parametrized = {
        "test_tenant_slug_rejects_injection": TENANT_INJECTIONS,
        "test_uuid_rejects_injection": UUID_INJECTIONS,
        "test_ident_rejects_injection": IDENT_INJECTIONS,
        "test_integer_rejects_injection": INT_INJECTIONS,
        "test_regex_rejects_embedded_single_quote": ["x' OR 1=1 --", "it's", "'"],
        "test_regex_rejects_backslash": ["abc\\", "a\\b"],
        "test_build_rejects_format_conversion": [
            "SELECT {x!r}", "SELECT {x!s}", "SELECT {x!a}",
        ],
        "test_build_rejects_format_spec": ["SELECT {x:>30}", "SELECT {x:.5}"],
    }

    # Tests requiring pytest fixtures (monkeypatch) — skip in fallback runner
    skip_in_fallback = {"test_literal_tag_exhaustion", "test_literal_tag_retry_on_partial_collision"}

    passed = failed = 0
    for name, fn in tests:
        if name in skip_in_fallback:
            print(f"SKIP  {name} (requires pytest fixtures)")
            continue
        if name in parametrized:
            for payload in parametrized[name]:
                try:
                    fn(payload)
                    passed += 1
                except Exception:
                    failed += 1
                    print(f"FAIL  {name}({payload!r})")
                    traceback.print_exc()
        else:
            try:
                fn()
                passed += 1
                print(f"PASS  {name}")
            except Exception:
                failed += 1
                print(f"FAIL  {name}")
                traceback.print_exc()

    print()
    print(f"{passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
