#!/usr/bin/env python3
"""Fail-closed Auto-only policy and stream-json model observation for Cursor.

Operator rule (2026-10-22): every Datarim Cursor launch must pass ``--model auto``.
An unset model used to fall through to the client default (observed as a named
expensive model such as ``grok-4.7-high-fast``).

Policy:
- Missing / empty requested model → default to ``auto`` (still passed explicitly).
- ``auto`` (any case) → allowed.
- Any other model → refused with a clear error unless
  ``DATARIM_CURSOR_ALLOW_NON_AUTO=1`` (explicit escape hatch, off by default).

Observation (``cursor-agent -p --output-format stream-json``):
- First ``system``/``init`` event carries ``model`` (actual).
- Terminal ``result`` may carry ``usage`` and ``session_id``.
- ``--output-format json`` has no model field; launchers that need observation
  must use stream-json.

Alert policy choice (documented): under ``--model auto``, ``init.model`` may
report either ``Auto`` or a resolved display name (e.g. ``Claude 4 Sonnet``).
A resolved display name alone is NOT a violation. Warn when:

1. the init line is missing, or
2. ``init.model`` looks like a CLI model id (slug with version/hyphens, not a
   human display label) and is not Auto — that indicates a named model was
   served, or
3. a non-Auto model was requested (escape hatch) and the actual init model
   clearly disagrees.

Log lines are one JSON object per run (no prompt text, no secrets). A
``service_tier`` requested/actual pair is reserved for a follow-up task.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Iterable, Mapping, Optional

AUTO_MODEL = "auto"
ALLOW_NON_AUTO_ENV = "DATARIM_CURSOR_ALLOW_NON_AUTO"
LOG_ENV = "DATARIM_CURSOR_MODEL_LOG"
ALERT_PREFIX = "CURSOR_MODEL_ALERT:"
LOG_PREFIX = "CURSOR_MODEL_RUN:"

# CLI model ids look like "grok-4.7-high-fast", "claude-opus-4-7", "gpt-5.4".
# Display names under Auto look like "Claude 4 Sonnet" / "Auto".
_CLI_MODEL_ID = re.compile(
    r"^[a-z0-9]+(?:[._-][a-z0-9]+)+$",
    re.IGNORECASE,
)


class CursorModelRefused(ValueError):
    """Raised when a Cursor launch would use a non-Auto model without the hatch."""


def is_auto_model(name: Optional[str]) -> bool:
    return bool(name) and str(name).strip().lower() == AUTO_MODEL


def allow_non_auto() -> bool:
    return os.environ.get(ALLOW_NON_AUTO_ENV, "").strip().lower() in (
        "1", "true", "yes", "on",
    )


def looks_like_named_cli_model(name: Optional[str]) -> bool:
    """True when *name* looks like a pinned CLI model id, not Auto or a label."""
    if not name or is_auto_model(name):
        return False
    text = str(name).strip()
    if " " in text:
        # Human display labels from init.model under Auto (e.g. "Claude 4 Sonnet").
        return False
    return bool(_CLI_MODEL_ID.match(text))


def resolve_launch_model(requested: Optional[str] = None) -> str:
    """Return the model flag value to pass to cursor-agent.

    Defaults missing/empty to ``auto``. Refuses named models unless the escape
    hatch env var is set.
    """
    if requested is None or str(requested).strip() == "":
        return AUTO_MODEL
    text = str(requested).strip()
    if is_auto_model(text):
        return AUTO_MODEL
    if allow_non_auto():
        return text
    raise CursorModelRefused(
        f"Cursor model '{text}' refused: only Auto is allowed "
        f"(pass --model auto, or unset the model to default to auto). "
        f"Escape hatch: set {ALLOW_NON_AUTO_ENV}=1 to permit a named model."
    )


def model_argv(requested: Optional[str] = None) -> list[str]:
    """Return ``['--model', <resolved>]`` or raise :class:`CursorModelRefused`."""
    return ["--model", resolve_launch_model(requested)]


def _usage_from_result(data: Mapping[str, Any]) -> Optional[dict[str, Any]]:
    usage = data.get("usage")
    if not isinstance(usage, Mapping):
        return None
    # Keep only scalar token counters; never copy prompt/result text fields.
    out: dict[str, Any] = {}
    for key, value in usage.items():
        if not isinstance(key, str):
            continue
        if key.lower() in ("prompt", "result", "text", "content", "message"):
            continue
        if isinstance(value, bool) or value is None:
            continue
        if isinstance(value, (int, float)):
            out[key] = value
        elif isinstance(value, str) and value.isdigit():
            out[key] = int(value)
    return out or None


def observe_stream_json(
    lines: Iterable[str],
    *,
    requested_model: str,
) -> dict[str, Any]:
    """Parse NDJSON stream-json events into a run observation record."""
    actual_model: Optional[str] = None
    session_id: Optional[str] = None
    usage: Optional[dict[str, Any]] = None
    init_seen = False

    for raw in lines:
        if raw is None:
            continue
        line = raw.strip() if isinstance(raw, str) else str(raw).strip()
        if not line.startswith("{"):
            continue
        try:
            data = json.loads(line)
        except (ValueError, TypeError):
            continue
        if not isinstance(data, dict):
            continue
        kind = data.get("type")
        subtype = data.get("subtype")
        if kind == "system" and subtype == "init":
            init_seen = True
            model = data.get("model")
            if isinstance(model, str) and model.strip():
                actual_model = model.strip()
            sid = data.get("session_id")
            if isinstance(sid, str) and sid.strip():
                session_id = sid.strip()
        elif kind == "result":
            sid = data.get("session_id")
            if isinstance(sid, str) and sid.strip():
                session_id = sid.strip()
            usage = _usage_from_result(data)

    alerts = evaluate_alerts(
        requested_model=requested_model,
        actual_model=actual_model,
        init_seen=init_seen,
    )
    return build_run_record(
        requested_model=requested_model,
        actual_model=actual_model,
        session_id=session_id,
        usage=usage,
        init_seen=init_seen,
        alerts=alerts,
    )


def evaluate_alerts(
    *,
    requested_model: str,
    actual_model: Optional[str],
    init_seen: bool,
) -> list[str]:
    alerts: list[str] = []
    if not init_seen or actual_model is None:
        alerts.append(
            "missing stream-json system/init model field; "
            "cannot verify which model Cursor served"
        )
        return alerts
    if looks_like_named_cli_model(actual_model):
        if is_auto_model(requested_model):
            alerts.append(
                f"actual model '{actual_model}' looks like a named CLI model "
                f"while requested model was Auto"
            )
        elif str(actual_model).strip().lower() != str(requested_model).strip().lower():
            alerts.append(
                f"model mismatch: requested '{requested_model}' "
                f"but init.model was '{actual_model}'"
            )
    elif (
        not is_auto_model(requested_model)
        and looks_like_named_cli_model(requested_model)
        and str(actual_model).strip().lower() != str(requested_model).strip().lower()
        and not is_auto_model(actual_model)
        and " " not in str(actual_model)
    ):
        alerts.append(
            f"model mismatch: requested '{requested_model}' "
            f"but init.model was '{actual_model}'"
        )
    return alerts


def build_run_record(
    *,
    requested_model: str,
    actual_model: Optional[str],
    session_id: Optional[str],
    usage: Optional[Mapping[str, Any]],
    init_seen: bool,
    alerts: Optional[list[str]] = None,
) -> dict[str, Any]:
    """Structured per-run record. ``service_tier`` keys reserved for follow-up."""
    return {
        "event": "cursor_model_run",
        "requested_model": requested_model,
        "actual_model": actual_model,
        "session_id": session_id,
        "usage": dict(usage) if usage else None,
        "init_seen": bool(init_seen),
        "alerts": list(alerts or []),
        # Follow-up: populate when Cursor exposes service tier in stream-json.
        "requested_service_tier": None,
        "actual_service_tier": None,
    }


def emit_alerts(alerts: Iterable[str], *, stream=None) -> None:
    out = stream if stream is not None else sys.stderr
    for message in alerts:
        print(f"{ALERT_PREFIX} {message}", file=out)


def emit_run_log(record: Mapping[str, Any], *, stream=None) -> None:
    """Write one structured log line (stderr + optional file)."""
    line = json.dumps(record, sort_keys=True, separators=(",", ":"))
    out = stream if stream is not None else sys.stderr
    print(f"{LOG_PREFIX} {line}", file=out)
    log_path = os.environ.get(LOG_ENV, "").strip()
    if not log_path:
        return
    try:
        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(
            f"{ALERT_PREFIX} failed to append {LOG_ENV} log: {type(exc).__name__}",
            file=out,
        )


def observe_and_emit(
    lines: Iterable[str],
    *,
    requested_model: str,
    stream=None,
) -> dict[str, Any]:
    record = observe_stream_json(lines, requested_model=requested_model)
    emit_run_log(record, stream=stream)
    emit_alerts(record.get("alerts") or [], stream=stream)
    return record


def extract_result_text(lines: Iterable[str]) -> str:
    """Return the terminal result text from a stream-json NDJSON transcript."""
    text = ""
    for raw in lines:
        line = raw.strip() if isinstance(raw, str) else str(raw).strip()
        if not line.startswith("{"):
            continue
        try:
            data = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(data, dict) and data.get("type") == "result":
            result = data.get("result")
            if isinstance(result, str):
                text = result
    return text


def _cli(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_resolve = sub.add_parser("resolve", help="Resolve/guard a requested model")
    p_resolve.add_argument("model", nargs="?", default="")
    p_resolve.add_argument(
        "--json", action="store_true", help="Emit {\"model\": ...} on stdout"
    )

    p_observe = sub.add_parser(
        "observe", help="Observe a recorded stream-json transcript on stdin"
    )
    p_observe.add_argument("--requested", default=AUTO_MODEL)
    p_observe.add_argument(
        "--emit-result",
        action="store_true",
        help="Also print the terminal result text after the log line",
    )

    p_argv = sub.add_parser("model-argv", help="Print --model <resolved> as two lines")
    p_argv.add_argument("model", nargs="?", default="")

    args = parser.parse_args(argv)

    if args.cmd == "resolve":
        try:
            model = resolve_launch_model(args.model or None)
        except CursorModelRefused as exc:
            print(str(exc), file=sys.stderr)
            return 2
        if args.json:
            print(json.dumps({"model": model}))
        else:
            print(model)
        return 0

    if args.cmd == "model-argv":
        try:
            for part in model_argv(args.model or None):
                print(part)
        except CursorModelRefused as exc:
            print(str(exc), file=sys.stderr)
            return 2
        return 0

    if args.cmd == "observe":
        raw_lines = sys.stdin.read().splitlines()
        try:
            requested = resolve_launch_model(args.requested)
        except CursorModelRefused as exc:
            print(str(exc), file=sys.stderr)
            return 2
        record = observe_and_emit(raw_lines, requested_model=requested)
        if args.emit_result:
            print(extract_result_text(raw_lines))
        return 1 if record.get("alerts") else 0

    return 2


if __name__ == "__main__":
    raise SystemExit(_cli())
