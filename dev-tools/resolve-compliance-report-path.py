#!/usr/bin/env python3
"""Reserve the exact output path for one compliance report invocation."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import tempfile


TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _reserve(path: Path) -> bool:
    try:
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    try:
        os.fchmod(descriptor, 0o600)
    finally:
        os.close(descriptor)
    return True


def reserve_report_path(root: Path, task_id: str) -> tuple[str, Path]:
    if not TASK_ID_RE.fullmatch(task_id):
        raise ValueError("task id contains unsupported filename characters")

    reports_dir = root / "datarim" / "reports"
    if reports_dir.is_symlink():
        raise OSError("reports directory must not be a symlink")
    if reports_dir.is_dir():
        stem = f"compliance-report-{task_id}"
        version = 1
        while True:
            suffix = "" if version == 1 else f"-v{version}"
            candidate = reports_dir / f"{stem}{suffix}.md"
            if _reserve(candidate):
                return "file", candidate
            version += 1

    private_dir = Path(tempfile.mkdtemp(prefix="datarim-compliance-report-"))
    try:
        os.chmod(private_dir, 0o700)
        candidate = private_dir / "report.md"
        if not _reserve(candidate):
            raise FileExistsError("private report path already exists")
    except Exception:
        private_dir.rmdir()
        raise
    return "chat", candidate


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--task-id", required=True)
    args = parser.parse_args()
    try:
        destination, report_path = reserve_report_path(args.root.resolve(), args.task_id)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if "\n" in str(report_path):
        parser.error("report path cannot contain a newline")
    print(f"{destination}:{report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
