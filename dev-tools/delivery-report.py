#!/usr/bin/env python3
"""Publish and verify a task report at a project-configured shared path."""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


TASK_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def report_directory(root: Path, task_id: str) -> Path | None:
    if not TASK_ID.fullmatch(task_id):
        raise ValueError("invalid task id")
    config = root / "datarim/config.yaml"
    if not config.exists():
        return None
    if config.is_symlink():
        raise ValueError("config.yaml must not be a symlink")
    # This intentionally accepts only a simple scalar under delivery. Complex
    # YAML needs an explicit schema rather than an optional runtime dependency.
    section = False
    template = None
    for raw in config.read_text(encoding="utf-8").splitlines():
        line = raw.split(" #", 1)[0].rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith((" ", "\t")):
            section = line == "delivery:"
        elif section and re.match(r"[ \t]+reports:", line):
            if template is not None:
                raise ValueError("duplicate delivery.reports")
            template = line.split(":", 1)[1].strip().strip("\"'")
    if template is None:
        return None
    if not template or "{" in template.replace("{task_id}", "") or "}" in template.replace("{task_id}", ""):
        raise ValueError("delivery.reports supports only {task_id}")
    relative = Path(template.replace("{task_id}", task_id))
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("delivery.reports must stay inside the project")
    if relative.parts[0] == "datarim":
        raise ValueError("delivery.reports must be outside private datarim state")
    target = root / relative
    for path in (target, *target.parents):
        if path == root:
            break
        if path.is_symlink():
            raise ValueError("delivery path contains a symlink")
    return target


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_git_visible(root: Path, target: Path) -> None:
    relative = target.relative_to(root).as_posix()
    inside = subprocess.run(["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
                            capture_output=True, text=True)
    if inside.returncode != 0 or inside.stdout.strip() != "true":
        raise ValueError("configured delivery requires a Git worktree")
    ignored = subprocess.run(["git", "-C", str(root), "check-ignore", "--no-index", "--", relative],
                             capture_output=True, text=True)
    if ignored.returncode == 0:
        raise ValueError("configured report target is Git-ignored: " + relative)
    if ignored.returncode != 1:
        raise ValueError("unable to check Git visibility for " + relative)


def run(root: Path, task_id: str, source: Path, action: str) -> tuple[str, Path | None]:
    directory = report_directory(root, task_id)
    if directory is None:
        return "advisory_unconfigured", None
    if not source.is_file() or source.is_symlink() or source.suffix != ".md":
        raise ValueError("source must be an existing regular Markdown report")
    if not source.resolve().is_relative_to(root / "datarim"):
        raise ValueError("source must be a Datarim working report")
    target = directory / source.name
    require_git_visible(root, target)
    if target.is_symlink():
        raise ValueError("report target must not be a symlink")
    if action == "publish":
        directory.mkdir(parents=True, exist_ok=True)
        descriptor, temp = tempfile.mkstemp(prefix=".report-", dir=directory)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(source.read_bytes())
            os.replace(temp, target)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
    if not target.is_file() or digest(target) != digest(source):
        raise ValueError("published report missing or differs from working copy")
    return "verified", target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("publish", "check"))
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--source", type=Path, required=True)
    args = parser.parse_args()
    try:
        root = args.root.resolve(strict=True)
        status, target = run(root, args.task_id, args.source.absolute(), args.action)
    except (OSError, UnicodeError, ValueError) as exc:
        print(f"DELIVERY_ERROR: {exc}", file=sys.stderr)
        return 2
    print(f"{status}:{target or ''}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
