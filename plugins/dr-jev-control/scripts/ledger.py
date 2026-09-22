#!/usr/bin/env python3
"""Append-only telemetry ledger plus the predicted-vs-actual readers.

The ledger is the point of the whole exercise: the next version's architecture
should be derived from the gap between what Jev decided before the task and what
the session actually needed, not from guesswork. `dr-jev stats` reads it back.

Prompt text is hashed, never stored, unless telemetry.store_prompt_text is on --
task text routinely contains paths, hostnames and occasionally secrets, and this
file is long-lived.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from pathlib import Path
from project_state import state_dir

# Redaction floor applied to every recorded free-text field. Cheap, and a ledger
# is exactly the kind of long-lived artefact where a leaked token outlives the
# session that produced it.
#
# Measured, not assumed: an earlier revision of this pattern redacted 24 of 34
# realistic credential formats. The misses were all character-class errors in
# alternatives that were *meant* to cover the vendor -- `gh[pousr]_` cannot match
# `github_pat_`, and `sk-` with a mandatory hyphen cannot match Stripe's
# `sk_live_`. The worst was PEM: matching only the `-----BEGIN-----` delimiter
# redacted the label and wrote the key body out verbatim.
_PEM_BLOCK = re.compile(
    r"-----BEGIN[A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END[A-Z0-9 ]*PRIVATE KEY-----|\Z)",
    re.DOTALL,
)

_SECRET = re.compile(
    # Vendor-prefixed tokens. `sk[-_]` because Stripe/Anthropic differ in
    # separator; the trailing class allows `_` because fine-grained tokens
    # (github_pat_, pypi-) embed it.
    r"(sk[-_][A-Za-z0-9_-]{16,}|rk_(?:live|test)_[A-Za-z0-9]{16,}|"
    r"github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|"
    r"glpat-[A-Za-z0-9_-]{16,}|pypi-[A-Za-z0-9_-]{32,}|"
    r"xox[abprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{30,}|npm_[A-Za-z0-9]{30,}|"
    r"hf_[A-Za-z0-9]{30,}|dop_v1_[a-f0-9]{60,}|SG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}|"
    r"AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|"
    # Slack/Discord/Teams incoming webhooks: the URL *is* the credential.
    r"https://hooks\.slack\.com/services/[A-Za-z0-9/_-]+|"
    r"https://discord(?:app)?\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|"
    # Azure storage / service-bus keys.
    r"AccountKey=[A-Za-z0-9+/=]{20,}|SharedAccessKey=[A-Za-z0-9+/=]{20,}|"
    # JWTs (all three segments) and bearer headers.
    r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]+)?|"
    r"(?i:bearer)\s+[A-Za-z0-9._-]{20,}|"
    # Credentials embedded in a URL: scheme://user:secret@host. No length floor
    # on the password -- a 4-character production password is still a secret.
    r"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s:/@]+:[^\s/@]+@|"
    # AWS secret access keys have no prefix to anchor on, so they are matched by
    # shape: exactly 40 chars of the base64 alphabet. A lookahead demands both a
    # `/`/`+` and mixed case somewhere in the run, which excludes the 40-char
    # hex SHA-1 that git commits produce -- those are useful telemetry and were
    # being redacted by a looser version of this rule.
    r"\b(?=[A-Za-z0-9/+]{40}\b)(?=[A-Za-z0-9/+]*[/+A-Z])(?=[A-Za-z0-9/+]*[a-z])"
    r"[A-Za-z0-9/+]{40}\b|"
    # Generic assignments: password=..., api_key: "...", secret_token => ...
    r"(?i:(?:pass(?:wo?rd)?|secret|token|api[_-]?key|access[_-]?key|private[_-]?key|"
    r"auth[_-]?token|client[_-]?secret)"
    r"\s*(?:[:=]+>?|=>)\s*[\"']?[A-Za-z0-9/+_.~-]{8,}))"
)

_MAX_SCRUB_DEPTH = 24


def redact(text):
    if not isinstance(text, str):
        return text
    # PEM first: it spans lines and must be consumed whole, before any
    # single-line alternative can nibble at its header.
    text = _PEM_BLOCK.sub("<redacted-private-key>", text)
    return _SECRET.sub("<redacted>", text)


def _scrub(obj, _depth=0):
    """Redact recursively, over keys as well as values.

    Keys matter: env- and header-shaped payloads routinely carry the credential
    in the key position (`ANTHROPIC_API_KEY=sk-...` as a dict key). Depth is
    capped because an unbounded recursion here would raise into log_event's
    blanket handler and silently discard the whole record.
    """
    if _depth > _MAX_SCRUB_DEPTH:
        return "<redacted-too-deep>"
    if isinstance(obj, str):
        return redact(obj)
    if isinstance(obj, bytes):
        return redact(obj.decode("utf-8", "replace"))
    if isinstance(obj, dict):
        return {redact(k) if isinstance(k, str) else k: _scrub(v, _depth + 1)
                for k, v in obj.items()}
    if isinstance(obj, (list, tuple, set)):
        return [_scrub(v, _depth + 1) for v in obj]
    if isinstance(obj, float) and (obj != obj or obj in (float("inf"), float("-inf"))):
        # NaN/Infinity serialise as bare tokens that are invalid JSON but which
        # Python's own parser accepts, which would make the ledger unportable.
        return None
    if isinstance(obj, (int, bool)) or obj is None:
        return obj
    if isinstance(obj, float):
        return obj
    # Anything else (objects, datetimes) would raise in json.dumps and take the
    # whole record down with it.
    return redact(repr(obj))


def ledger_path(cfg, *, strict=False):
    """Resolve the ledger file for a *config* mapping.

    Writes keep the permissive default so telemetry can never be the reason a
    hook loses a record. Reads pass strict=True, because there the silent
    default turned a caller mistake into plausible output: passing a stats dict
    to `render_stats` (which takes the config and re-reads the ledger) rendered
    a report of the operator's production ledger with no error -- a test in this
    repo did exactly that and asserted against real data.
    """
    if strict and (not isinstance(cfg, dict) or "telemetry" not in cfg):
        raise TypeError(
            "expects a control-plane config with a 'telemetry' key; got "
            f"{type(cfg).__name__} with keys "
            f"{sorted(cfg)[:6] if isinstance(cfg, dict) else '-'}"
        )
    tel = (cfg.get("telemetry") if isinstance(cfg, dict) else None) or {}
    return Path(tel['path']) if tel.get('path') else state_dir() / 'ledger.jsonl'


def log_event(cfg, event, text, data):
    """Append one record. Never raises -- telemetry must not break routing."""
    tel = cfg.get("telemetry", {}) or {}
    if not tel.get("enabled", True):
        return
    try:
        p = ledger_path(cfg)
        p.parent.mkdir(parents=True, exist_ok=True)
        rec = {
            "ts": time.time(),
            "event": event,
            "sha256": hashlib.sha256((text or "").encode()).hexdigest(),
            "data": _scrub(data),
        }
        if tel.get("store_prompt_text", False):
            rec["text"] = redact(text)
        try:
            line = json.dumps(rec, ensure_ascii=False)
        except (TypeError, ValueError) as exc:
            # A single unserialisable value used to discard the entire record
            # silently -- and `route()` logs the raw parsed API response, so this
            # was reachable from live data. A dropped live_session removes a whole
            # predicted-vs-actual sample while stats() reports a smaller,
            # silently biased count. Degrade to a marker instead: a visible
            # placeholder is analysable, a hole is not.
            line = json.dumps({
                "ts": rec["ts"], "event": event, "sha256": rec["sha256"],
                "data": {"unserialisable": True,
                         "error": redact(f"{type(exc).__name__}: {exc}")[:200]},
            }, ensure_ascii=False)
        # O_CREAT with an explicit mode: p.open("a") creates at the umask default
        # (typically 0644) and the chmod landed only *after* the secret-bearing
        # line was already on disk.
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(fd, "a") as f:  # fdopen owns fd; its close covers both
            f.write(line + "\n")
    except Exception:
        pass


def read_events(cfg, *, events=None, limit=None):
    p = ledger_path(cfg, strict=True)
    if not p.exists():
        return []
    out = []
    with p.open() as f:
        for line in f:
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if events and rec.get("event") not in events:
                continue
            out.append(rec)
    return out[-limit:] if limit else out


def last_decision(cfg):
    recs = read_events(cfg, events={"route", "live_session"})
    return recs[-1] if recs else None


def stats(cfg):
    """Aggregate calibration and divergence signals.

    Calibration here is deliberately modest: for `choice` answers we can only
    compare stated confidence against how often that pick was actually applied
    downstream, which is a proxy, not ground truth. The honest reading is
    "how decisive is Jev on this axis", and the divergence section is where the
    real signal about the next architecture lives.
    """
    routes = read_events(cfg, events={"route"})
    lives = read_events(cfg, events={"live_session"})
    rer = read_events(cfg, events={"live_reroute"})

    out = {
        "routes": len(routes),
        "live_sessions": len(lives),
        "reroutes": len(rer),
        "model_mix": {},
        "confidence": {},
        "switches": {"applied": 0, "blocked": {}},
        "divergence": {"sessions_with_no_tool_use": 0, "work_broader_than_prediction": 0, "samples": 0},
        "phases": {},
        "stop_reasons": {},
    }

    for r in routes:
        d = r.get("data", {}) or {}
        out["model_mix"][d.get("model", "?")] = out["model_mix"].get(d.get("model", "?"), 0) + 1
        sel = d.get("selection") or {}
        for kind in ("agents", "commands", "templates"):
            s = sel.get(kind) or {}
            conf = s.get("confidence")
            if conf is None:
                continue
            slot = out["confidence"].setdefault(
                kind, {"n": 0, "sum": 0.0, "applied": 0, "refused": 0})
            # A confident `none` is a confident *refusal*, not a weak
            # recommendation, so it must not land in the same denominator. Mixing
            # them inverts the reading of this whole axis: measured on the real
            # ledger, templates showed "conf 0.80 -> applied 0% (n=33)" when the
            # truth was 32 high-confidence refusals and a single 0.33 pick, and
            # agents/commands under-reported applied_rate by 11-12 points.
            if s.get("choice", "none") == "none":
                slot["refused"] += 1
                continue
            slot["n"] += 1
            slot["sum"] += float(conf)
            slot["applied"] += 1 if s.get("applied") else 0
        sk = (sel.get("skills") or {})
        if sk:
            slot = out["confidence"].setdefault(
                "skills", {"n": 0, "sum": 0.0, "applied": 0, "refused": 0})
            ranked = sk.get("ranked") or []
            if not ranked:
                # No probe answered: absence of data, not a low score. Counting it
                # as 0.0 would drag the mean toward a confidence Jev never stated.
                slot["refused"] += 1
            else:
                top = ranked[0].get("score")
                slot["n"] += 1
                slot["sum"] += float(top or 0.0)
                slot["applied"] += 1 if sk.get("apply") else 0

    for kind, slot in out["confidence"].items():
        slot["mean_confidence"] = round(slot["sum"] / slot["n"], 3) if slot["n"] else 0.0
        slot["applied_rate"] = round(slot["applied"] / slot["n"], 3) if slot["n"] else 0.0
        slot.pop("sum", None)

    for r in rer:
        v = (r.get("data", {}) or {}).get("verdict", {}) or {}
        if v.get("switch") and v.get("applied"):
            out["switches"]["applied"] += 1
        elif v.get("blocked_by"):
            b = v["blocked_by"]
            out["switches"]["blocked"][b] = out["switches"]["blocked"].get(b, 0) + 1
        ph = (r.get("data", {}) or {}).get("phase")
        if ph:
            out["phases"][ph] = out["phases"].get(ph, 0) + 1

    for r in lives:
        d = r.get("data", {}) or {}
        pred = d.get("predicted", {}) or {}
        act = d.get("actual", {}) or {}
        out["divergence"]["samples"] += 1
        pred_skills = set(pred.get("skills") or [])
        if not act.get("tools"):
            out["divergence"]["sessions_with_no_tool_use"] += 1
        # A session whose phase sequence has more distinct phases than the
        # predicted component count is the concrete evidence that one-shot
        # routing under-describes the work.
        if len(set(act.get("phases") or [])) > max(1, len(pred_skills)):
            out["divergence"]["work_broader_than_prediction"] += 1
        sr = d.get("stop_reason")
        if sr:
            out["stop_reasons"][sr] = out["stop_reasons"].get(sr, 0) + 1
    return out
