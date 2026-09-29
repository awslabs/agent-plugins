"""Regression tests for Draw.io validator edge-reference handling."""

import importlib.util
import json
from pathlib import Path
import subprocess
import sys


VALIDATOR_PATH = (
    Path(__file__).parents[1] / "scripts" / "lib" / "validate_drawio.py"
)
SPEC = importlib.util.spec_from_file_location("validate_drawio", VALIDATOR_PATH)
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)
HOOK_RUNNER_PATH = Path(__file__).parents[1] / "scripts" / "lib" / "run_drawio_hook.py"


def write_diagram(tmp_path, source_id="user-a", target_id="user-b"):
    diagram = tmp_path / "user-objects.drawio"
    diagram.write_text(
        f"""<mxfile>
  <diagram name="Page-1">
    <mxGraphModel><root>
      <mxCell id="0" />
      <mxCell id="1" parent="0" />
      <UserObject id="user-a" label="Source">
        <mxCell id="mx-a" parent="1" vertex="1">
          <mxGeometry x="0" y="0" width="80" height="40" as="geometry" />
        </mxCell>
      </UserObject>
      <UserObject id="user-b" label="Target">
        <mxCell id="mx-b" parent="1" vertex="1">
          <mxGeometry x="160" y="0" width="80" height="40" as="geometry" />
        </mxCell>
      </UserObject>
      <mxCell id="edge-1" edge="1" source="{source_id}" target="{target_id}" parent="1">
        <mxGeometry relative="1" as="geometry" />
      </mxCell>
    </root></mxGraphModel>
  </diagram>
</mxfile>
""",
        encoding="utf-8",
    )
    return diagram


def test_userobject_wrapper_ids_are_valid_edge_endpoints(tmp_path):
    diagram = write_diagram(tmp_path)

    errors, _warnings = VALIDATOR.validate(diagram)

    assert not any('non-existent source="user-a"' in error for error in errors)
    assert not any('non-existent target="user-b"' in error for error in errors)


def test_unknown_edge_endpoint_still_fails_validation(tmp_path):
    diagram = write_diagram(tmp_path, target_id="missing-user")

    errors, _warnings = VALIDATOR.validate(diagram)

    assert any('non-existent target="missing-user"' in error for error in errors)


def test_hook_runner_returns_json_for_valid_diagram(tmp_path):
    diagram = write_diagram(tmp_path)

    result = subprocess.run(
        [sys.executable, str(HOOK_RUNNER_PATH), str(diagram)],
        check=True,
        capture_output=True,
        text=True,
    )
    response = json.loads(result.stdout)

    assert "VALIDATION PASSED" in response["systemMessage"]
