#!/usr/bin/env python3
"""jev.py's --live path actually forwards --max-seconds to live_supervisor.py.

Testing each parser in isolation hides the real defect: jev.py declares
`--max-seconds` as `type=float` and forwards it as `str(value)`, while
live_supervisor.py's own CLI declared it `type=int`. A whole-number value like
150 becomes the *text* "150.0" on the wire, which `int()` rejects -- a bug that
is invisible unless something actually drives the exec chain jev.py builds
(subprocess argv in, `os.execv` into live_supervisor.py, argparse on the far
end), rather than calling each parser with its own native Python type.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
JEV = ROOT / "scripts/jev.py"
FAKE_CODEX = Path(__file__).resolve().parent / "fake_codex.py"


class LiveMaxSecondsSurvivesRealForwarding(unittest.TestCase):
    """Drives the actual jev.py -> live_supervisor.py subprocess chain."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = (Path(self.tmp.name) / "project").resolve()
        self.project.mkdir()
        runtime = self.project / ".datarim-runtime"
        runtime.mkdir()
        # The real dr-jev-control scripts, including the live_supervisor.py
        # under test -- not a stand-in, so a fix has to land in the file this
        # test imports transitively via subprocess.
        (runtime / "plugins").symlink_to(ROOT / "plugins")
        (runtime / "installation.json").write_text(json.dumps({
            "schema": 1, "project": str(self.project), "with_jev": False,
        }))
        # A wrapper script so CODEX_BIN is a single executable, as in real use.
        self.bin = Path(self.tmp.name) / "codex"
        self.bin.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{FAKE_CODEX}" "$@"\n')
        self.bin.chmod(0o755)

    def _run(self):
        env = dict(os.environ, CODEX_BIN=str(self.bin))
        env.pop("DATARIM_JEV_DISABLE", None)
        return subprocess.run(
            [sys.executable, str(JEV), "--agent", "codex", "--live",
             "--max-turns", "1", "--max-seconds", "150",
             "do the thing", "--"],
            cwd=self.project, env=env, capture_output=True, text=True, timeout=30)

    def test_whole_number_max_seconds_is_not_rejected_by_the_supervisor(self):
        result = self._run()
        self.assertNotIn(
            "invalid int value", result.stderr,
            "jev.py forwards --max-seconds as float text (e.g. '150.0'); "
            "live_supervisor.py's CLI must accept that, not reject it via argparse:\n"
            + result.stderr)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
