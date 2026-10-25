#!/usr/bin/env python3
"""Resolve the workspace-owned evolution target and auto-apply setting."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys


FRAMEWORK_REMOTES = {
    "https://github.com/Arcanada-one/datarim.git",
    "https://github.com/Arcanada-one/datarim",
    "git@github.com:Arcanada-one/datarim.git",
}
FRAMEWORK_MARKERS = ("scripts/project_install.py", "skills/evolution/SKILL.md", "VERSION")


def git_value(root: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def framework_source(root: Path) -> bool:
    top = git_value(root, "rev-parse", "--show-toplevel")
    remote = git_value(root, "remote", "get-url", "origin")
    return bool(
        top == str(root)
        and remote in FRAMEWORK_REMOTES
        and all((root / marker).is_file() for marker in FRAMEWORK_MARKERS)
    )


def auto_apply(root: Path) -> bool:
    config = root / "datarim/config/evolution.yaml"
    if not config.exists():
        return True
    if config.is_symlink() or not config.is_file():
        raise ValueError("evolution config must be a regular file")
    values = []
    for line in config.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped not in ("auto_apply: true", "auto_apply: false"):
            raise ValueError("evolution config accepts only auto_apply: true|false")
        values.append(stripped.endswith("true"))
    if len(values) != 1:
        raise ValueError("evolution config requires exactly one auto_apply setting")
    return values[0]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir() or not (root / "datarim").is_dir():
        parser.error("root must be a workspace with a datarim directory")
    try:
        enabled = auto_apply(root)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"EVOLUTION_ROUTE_ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"scope": "framework" if framework_source(root) else "consumer", "auto_apply": enabled}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
