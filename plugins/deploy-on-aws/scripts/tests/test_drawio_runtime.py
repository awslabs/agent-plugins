"""Regression tests for the deploy-on-aws draw.io runtime."""

from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import defusedxml.ElementTree as ET


LIB_DIR = Path(__file__).resolve().parents[1] / "lib"
MISSING = object()
FIXTURE = """\
<mxfile host="Electron">
  <diagram name="Page-1">
    <mxGraphModel>
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="svc" parent="1" vertex="1"
          style="rounded=1;fillColor=#000000;strokeColor=#000000;fontColor=#000000;">
          <mxGeometry x="10" y="10" width="120" height="120" as="geometry" />
        </mxCell>
        <mxCell id="lambda" parent="svc" vertex="1"
          style="shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.lambda;fillColor=#000000;">
          <mxGeometry x="36" y="24" width="48" height="48" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
"""


def load_module(module_name: str, file_name: str):
    spec = importlib.util.spec_from_file_location(module_name, LIB_DIR / file_name)
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load test module: {file_name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise
    return module


class DrawioRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.defusedxml_exports = {
            name: getattr(ET, name, MISSING)
            for name in ("Element", "ElementTree", "indent")
        }
        cls.xml_format = load_module("_xml_format", "_xml_format.py")
        cls.post_process = load_module(
            "post_process_drawio_runtime_test", "post_process_drawio.py"
        )

    @classmethod
    def tearDownClass(cls) -> None:
        for module_name in (
            "post_process_drawio_runtime_test",
            "fix_step_badges",
            "fix_nesting",
            "fix_icon_colors",
            "_xml_format",
        ):
            sys.modules.pop(module_name, None)

    def write_fixture(self, directory: str) -> Path:
        path = Path(directory) / "fixture.drawio"
        path.write_text(FIXTURE, encoding="utf-8")
        return path

    def test_imports_do_not_patch_defusedxml_exports(self) -> None:
        for name, expected in self.defusedxml_exports.items():
            self.assertIs(getattr(ET, name, MISSING), expected)

    def test_parser_free_indenter_preserves_parseable_xml(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_fixture(directory)
            tree = ET.parse(path)

            self.xml_format.indent_tree(tree)
            tree.write(path, encoding="unicode", xml_declaration=False)

            rendered = path.read_text(encoding="utf-8")
            self.assertIn("\n  <diagram", rendered)
            self.assertEqual(ET.parse(path).getroot().tag, "mxfile")

    def test_individual_fixer_writes_with_parser_free_indentation(self) -> None:
        fixer = sys.modules["fix_icon_colors"]
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_fixture(directory)

            with (
                mock.patch.object(sys, "argv", ["fix_icon_colors.py", str(path)]),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                fixer.main()

            rendered = path.read_text(encoding="utf-8")
            self.assertIn("fillColor=#ED7100", rendered)
            self.assertIn("\n  <diagram", rendered)
            self.assertEqual(ET.parse(path).getroot().tag, "mxfile")

    def test_unified_pipeline_dry_run_is_non_mutating(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_fixture(directory)
            original = path.read_bytes()

            with (
                mock.patch.object(
                    sys,
                    "argv",
                    ["post_process_drawio.py", "--dry-run", str(path)],
                ),
                contextlib.redirect_stdout(io.StringIO()),
            ):
                self.post_process.main()

            self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
