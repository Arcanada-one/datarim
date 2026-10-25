#!/usr/bin/env python3
"""Resolve autonomous finalization across project, user, and task settings."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys


MODES = {"off", "on_request", "always"}
TASK_ID = re.compile(r"^[A-Z][A-Z0-9]{1,9}-[0-9]{4,5}$")


def config_mode(path: Path) -> str | None:
    if not path.exists():
        return None
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"unsafe config path: {path}")
    section = None
    found = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith(" "):
            match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_-]*):(?:\s*#.*)?", line)
            section = match.group(1) if match else None
            continue
        if section == "autonomy":
            match = re.fullmatch(r"  finalize:\s*(off|on_request|always)(?:\s*#.*)?", line)
            if line.lstrip().startswith("finalize:") and not match:
                raise ValueError(f"invalid autonomy.finalize in {path}")
            if match:
                found.append(match.group(1))
    if len(found) > 1:
        raise ValueError(f"duplicate autonomy.finalize in {path}")
    return found[0] if found else None


def task_requested(root: Path, task_id: str | None) -> bool:
    if task_id is None:
        return False
    if not TASK_ID.fullmatch(task_id):
        raise ValueError("invalid task identifier")
    path = root / "datarim/tasks" / f"{task_id}-init-task.md"
    if not path.exists():
        return False
    if path.is_symlink() or not path.is_file():
        raise ValueError("unsafe init-task path")
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        return False
    frontmatter = text.split("---", 2)[1]
    values = re.findall(r"^finalize_requested:\s*(true|false)\s*$", frontmatter, re.MULTILINE)
    if len(values) > 1:
        raise ValueError("duplicate finalize_requested")
    return values == ["true"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--task-id")
    args = parser.parse_args()
    root = args.root.resolve()
    if not (root / "datarim").is_dir():
        parser.error("root requires a datarim directory")
    user_base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    try:
        project = config_mode(root / "datarim/config.yaml")
        user = config_mode(user_base / "datarim/config.yaml")
        requested = task_requested(root, args.task_id)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"FINALIZE_MODE_ERROR: {exc}", file=sys.stderr)
        return 2
    if project is not None:
        mode, source = project, "project"
    elif user is not None:
        mode, source = user, "user"
    else:
        mode, source = "off", "default"
    run = mode == "always" or mode == "on_request" and requested
    print(json.dumps({"mode": mode, "source": source, "task_requested": requested, "run": run}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
