from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest



SPEC = importlib.util.spec_from_file_location(
    "delivery_report", Path(__file__).resolve().parents[1] / "dev-tools/delivery-report.py"
)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DeliveryReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.datarim = self.root / "datarim"
        (self.datarim / "qa").mkdir(parents=True)
        self.source = self.datarim / "qa/report.md"
        self.source.write_text("working copy\n")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_publish_and_check_configured_report(self) -> None:
        (self.datarim / "config.yaml").write_text("delivery:\n  reports: reports/{task_id}\n")
        status, target = module.run(self.root, "EXA-0001", self.source, "publish")
        self.assertEqual(status, "verified")
        self.assertEqual(target, self.root / "reports/EXA-0001/report.md")
        self.assertEqual(module.run(self.root, "EXA-0001", self.source, "check"), ("verified", target))
        self.source.write_text("new result\n")
        with self.assertRaisesRegex(ValueError, "differs"):
            module.run(self.root, "EXA-0001", self.source, "check")

    def test_unconfigured_is_advisory_and_escape_refused(self) -> None:
        self.assertEqual(module.run(self.root, "EXA-0001", self.source, "publish"),
                         ("advisory_unconfigured", None))
        (self.datarim / "config.yaml").write_text("delivery:\n  reports: ../outside/{task_id}\n")
        with self.assertRaisesRegex(ValueError, "inside"):
            module.run(self.root, "EXA-0001", self.source, "publish")

    def test_symlink_destination_refused(self) -> None:
        (self.datarim / "config.yaml").write_text("delivery:\n  reports: reports/{task_id}\n")
        (self.root / "reports").symlink_to(self.root / "elsewhere")
        with self.assertRaisesRegex(ValueError, "symlink"):
            module.run(self.root, "EXA-0001", self.source, "publish")

    def test_empty_configured_path_is_error(self) -> None:
        (self.datarim / "config.yaml").write_text("delivery:\n  reports:\n")
        with self.assertRaisesRegex(ValueError, "supports only"):
            module.run(self.root, "EXA-0001", self.source, "publish")


if __name__ == "__main__":
    unittest.main()
