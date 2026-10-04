#!/usr/bin/env python3
"""Idempotently register the Datarim MCP server in a Codex config.toml.

Direct file surgery (NOT `codex mcp add`, which needs codex present and
round-trips the file through Codex's serialiser — stripping comments,
reordering keys, clobbering sibling tables). We excise any existing
`[mcp_servers.datarim]` region (header + dotted descendants + one preceding
blank line) and append a fixed canonical block at EOF, preserving every other
byte. A second run is byte-identical (TUNE-0301 V-AC-8).

The canonical block uses an INLINE `env` table so the whole server config is a
single contiguous block with no subtable header — which makes the excise rule
("from the header to the next non-datarim table header") unambiguous.

Usage:
    register-codex-mcp.py --config PATH --command ABS_CMD --root ABS_ROOT
                          [--server-name datarim]

Exit codes: 0 ok · 2 bad args · 3 refused (config.toml malformed).
"""
import argparse
import os
import re
import shutil
import sys
import tempfile

try:
    import tomllib
except ModuleNotFoundError:  # python < 3.11
    tomllib = None

HEADER_RE = re.compile(r"^\[\s*mcp_servers\.%s\s*\](\s*#.*)?$")
DESC_RE = re.compile(r"^\[\s*mcp_servers\.%s\.")


def toml_str(value: str) -> str:
    """Minimal TOML basic-string escaping for a filesystem path."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def canonical_block(name: str, command: str, root: str) -> str:
    return (
        f"[mcp_servers.{name}]\n"
        f'command = "{toml_str(command)}"\n'
        f"args = []\n"
        f'env = {{ DATARIM_ROOT = "{toml_str(root)}" }}'
    )


def excise_region(text: str, name: str) -> str:
    """Remove every [mcp_servers.<name>] region (+ dotted descendants) and any
    blank lines immediately preceding each removed region."""
    header_re = re.compile(HEADER_RE.pattern % re.escape(name))
    desc_re = re.compile(DESC_RE.pattern % re.escape(name))
    lines = text.split("\n")
    out: list[str] = []
    i, n = 0, len(lines)
    while i < n:
        stripped = lines[i].strip()
        if header_re.match(stripped):
            while out and out[-1].strip() == "":
                out.pop()
            i += 1
            while i < n:
                s = lines[i].strip()
                if s.startswith("[") and not header_re.match(s) and not desc_re.match(s):
                    break
                i += 1
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


def build(text: str, name: str, command: str, root: str) -> str:
    remaining = excise_region(text, name).rstrip("\n")
    block = canonical_block(name, command, root)
    if remaining.strip():
        return remaining + "\n\n" + block + "\n"
    return block + "\n"


def validate(path: str, name: str, command: str, root: str) -> None:
    if tomllib is None:
        return  # cannot validate on <3.11; block is a fixed literal anyway
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    srv = data["mcp_servers"][name]
    assert srv["command"] == command, "command mismatch after write"
    assert srv["env"]["DATARIM_ROOT"] == root, "DATARIM_ROOT mismatch after write"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--command", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--server-name", default="datarim")
    args = ap.parse_args()

    name = args.server_name
    config = args.config

    original = ""
    if os.path.exists(config):
        original = open(config, "r", encoding="utf-8").read()
        # Refuse to touch a malformed config — we cannot reliably locate blocks.
        if tomllib is not None:
            try:
                tomllib.loads(original)
            except tomllib.TOMLDecodeError as exc:
                sys.stderr.write(f"register-codex-mcp: {config} is not valid TOML "
                                 f"({exc}); refusing to edit — fix it manually.\n")
                return 3

    result = build(original, name, args.command, args.root)

    if result == original:
        return 0  # already registered, byte-identical — nothing to do

    os.makedirs(os.path.dirname(os.path.abspath(config)) or ".", exist_ok=True)
    d = os.path.dirname(os.path.abspath(config))
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".config.toml.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(result)
        validate(tmp, name, args.command, args.root)
        if os.path.exists(config):
            shutil.copymode(config, tmp)
        os.replace(tmp, config)
    except Exception as exc:  # noqa: BLE001 — fail closed, leave original intact
        try:
            os.unlink(tmp)
        except OSError:
            pass
        sys.stderr.write(f"register-codex-mcp: write failed ({exc}); original untouched.\n")
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
