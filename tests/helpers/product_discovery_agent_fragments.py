#!/usr/bin/env python3
"""Exercise the product-discovery profile gate against disposable projects."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


REPO_ROOT = Path(__file__).resolve().parents[2]
PLUGIN = REPO_ROOT / "plugins/product-discovery"
PLUGIN_TOOL = REPO_ROOT / "scripts/dr-plugin.sh"
PROFILE_GATE = REPO_ROOT / "dev-tools/read-product-profile.sh"
TASK = "TASK-1234"
FRAGMENTS = (
    Path("skills/product-discovery/hypothesis-validation/researcher.product-discovery.md"),
    Path("skills/product-discovery/decision-record/strategist.product-discovery.md"),
)


class MissingFragment(Exception):
    pass


def project_fixture() -> tuple[tempfile.TemporaryDirectory[str], Path, Path]:
    fixture = tempfile.TemporaryDirectory(prefix="product-discovery-")
    root = Path(fixture.name) / "workspace"
    runtime = root / ".datarim-runtime/local"
    (root / "datarim/tasks").mkdir(parents=True)
    (root / ".datarim-runtime").mkdir(parents=True, exist_ok=True)
    (root / ".datarim-runtime/installation.json").write_text(
        json.dumps({"schema": 1, "project": str(root), "contexts": []}) + "\n",
        encoding="utf-8",
    )
    (root / "datarim/tasks" / f"{TASK}-task-description.md").write_text(
        "## Requirements\nSynthetic test input.\n", encoding="utf-8"
    )
    return fixture, root, runtime


def enable_plugin(root: Path) -> None:
    env = os.environ.copy()
    env.update(
        HOME=str(root / ".home"),
        TMPDIR=str(root / ".tmp"),
        DR_PLUGIN_WORKSPACE=str(root),
    )
    (root / ".home").mkdir()
    (root / ".tmp").mkdir()
    subprocess.run(
        [str(PLUGIN_TOOL), "enable", str(PLUGIN)],
        check=True,
        cwd=REPO_ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def select_profile(root: Path) -> None:
    (root / "datarim/tasks" / f"{TASK}-task-description.md").write_text(
        "## Profile\nprofile: product-discovery\n", encoding="utf-8"
    )


def profile_state(root: Path, runtime: Path) -> str:
    return subprocess.run(
        [str(PROFILE_GATE), "--root", str(root), "--task", TASK, "--runtime", str(runtime)],
        check=True,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    ).stdout.strip()


def load_fragment(root: Path, runtime: Path, relative: Path) -> str | None:
    if profile_state(root, runtime) != "profile_active":
        return None
    path = runtime / relative
    if not path.is_file() or not os.access(path, os.R_OK):
        raise MissingFragment(str(path))
    content = path.read_bytes()
    return f"loaded {path} sha256:{hashlib.sha256(content).hexdigest()}"


def enabled_selected() -> None:
    fixture, root, runtime = project_fixture()
    try:
        enable_plugin(root)
        select_profile(root)
        assert profile_state(root, runtime) == "profile_active"
        receipts = [load_fragment(root, runtime, rel) for rel in FRAGMENTS]
        assert all(receipt is not None and "sha256:" in receipt for receipt in receipts)
        for receipt in receipts:
            print(receipt)
    finally:
        fixture.cleanup()


def selected_disabled() -> None:
    fixture, root, runtime = project_fixture()
    try:
        select_profile(root)
        assert profile_state(root, runtime) == "profile_unavailable"
        assert load_fragment(root, runtime, FRAGMENTS[0]) is None
        assert not (runtime / FRAGMENTS[0]).exists()
    finally:
        fixture.cleanup()


def enabled_profile_off() -> None:
    fixture, root, runtime = project_fixture()
    try:
        enable_plugin(root)
        assert profile_state(root, runtime) == "profile_not_selected"
        assert load_fragment(root, runtime, FRAGMENTS[0]) is None
        assert (runtime / FRAGMENTS[0]).is_file()
    finally:
        fixture.cleanup()


def missing_fragment() -> None:
    fixture, root, runtime = project_fixture()
    try:
        enable_plugin(root)
        select_profile(root)
        missing = runtime / FRAGMENTS[0]
        missing.unlink()
        try:
            load_fragment(root, runtime, FRAGMENTS[0])
        except MissingFragment as exc:
            assert str(exc) == str(missing)
            print(f"required product-discovery fragment missing: {exc}")
            return
        raise AssertionError("missing selected fragment did not fail")
    finally:
        fixture.cleanup()


def prompt_gates() -> None:
    expected = {
        REPO_ROOT / "agents/researcher.md": (
            "${DATARIM_RUNTIME:?}/local/skills/product-discovery/"
            "hypothesis-validation/researcher.product-discovery.md"
        ),
        REPO_ROOT / "agents/strategist.md": (
            "${DATARIM_RUNTIME:?}/local/skills/product-discovery/"
            "decision-record/strategist.product-discovery.md"
        ),
    }
    for path, reference in expected.items():
        lines = path.read_text(encoding="utf-8").splitlines()
        active = False
        inside = []
        outside = []
        for line in lines:
            if line.strip() == "### Product discovery profile gate":
                active = True
                continue
            if active and line.startswith("### "):
                active = False
            if reference in line:
                (inside if active else outside).append(line)
        assert len(inside) == 1 and not outside, f"profile gate mismatch: {path}"
    print("gated references verified")


CASES = {
    "enabled-selected": enabled_selected,
    "selected-disabled": selected_disabled,
    "enabled-profile-off": enabled_profile_off,
    "missing-fragment": missing_fragment,
    "prompt-gates": prompt_gates,
}


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in CASES:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} {{{','.join(CASES)}}}")
    CASES[sys.argv[1]]()
