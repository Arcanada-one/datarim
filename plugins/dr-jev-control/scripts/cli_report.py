#!/usr/bin/env python3
"""`jev stats` (and the last-decision) renderers."""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ledger import last_decision, stats  # noqa: E402
from route import load_cfg  # noqa: E402


def _bar(label, value, width=20):
    try:
        v = max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return f"  {label:<22} n/a"
    filled = int(round(v * width))
    return f"  {label:<22} {'█' * filled}{'·' * (width - filled)} {v * 100:>5.1f}%"


def render_last(cfg, as_json=False):
    rec = last_decision(cfg)
    if not rec:
        return ("No Jev decisions recorded yet. Run a task through `jevclaude`, `jevcodex` or `jevcursor` "
                "(or `jev --agent=<client>`) first.")
    if as_json:
        return json.dumps(rec, ensure_ascii=False, indent=2)

    d = rec.get("data", {}) or {}
    a = d.get("answers", {}) or {}
    sel = d.get("selection", {}) or {}
    age = time.time() - float(rec.get("ts", 0) or 0)
    lines = [
        "Last Jev decision",
        f"  recorded      {age / 60:.0f} min ago  ({rec.get('event')})",
        f"  mode          {d.get('mode', '?')}",
        f"  model         {d.get('model', '?')}",
    ]
    cx = (a.get("complexity") or {}).get("score")
    if cx is not None:
        lines.append(f"  complexity    {cx} / 4")
    lines.append("")
    for key, label in (("needs_system2", "System-2 reasoning"),
                       ("production_risk", "Production risk"),
                       ("needs_validation", "Validation needed"),
                       ("parallelizable", "Parallelizable")):
        v = (a.get(key) or {}).get("noul")
        lines.append(_bar(label, v))

    sk = sel.get("skills") or {}
    if sk.get("ranked"):
        lines.append("")
        lines.append("Skills (per-candidate applicability)")
        for x in sk["ranked"][:6]:
            mark = " ← applied" if any(y["name"] == x["name"] for y in sk.get("apply", [])) else ""
            lines.append(_bar(x["name"][:22], x["score"]) + mark)

    for kind, label in (("agents", "Agent"), ("commands", "Command"), ("templates", "Template")):
        s = sel.get(kind) or {}
        probs = s.get("probabilities") or {}
        if not probs:
            continue
        lines.append("")
        state = "applied" if s.get("applied") else "advisory only (below threshold)"
        lines.append(f"{label} — {s.get('choice', 'none')} · {state}")
        for name, p in sorted(probs.items(), key=lambda kv: -float(kv[1] or 0))[:4]:
            lines.append(_bar(str(name)[:22], p))

    sw = d.get("actual", {}).get("switches") if isinstance(d.get("actual"), dict) else None
    if sw:
        lines.append("")
        lines.append("Live switches")
        for s in sw:
            lines.append(f"  {s.get('from')} → {s.get('to')}  ({s.get('reason', '')})")
    return "\n".join(lines)


def render_stats(cfg, as_json=False):
    s = stats(cfg)
    if as_json:
        return json.dumps(s, ensure_ascii=False, indent=2)
    lines = [
        "Jev accumulated statistics",
        f"  routes            {s['routes']}",
        f"  live sessions     {s['live_sessions']}",
        f"  mid-task reroutes {s['reroutes']}",
    ]
    if s["model_mix"]:
        lines.append("  model mix         " + ", ".join(f"{k} ×{v}" for k, v in sorted(s["model_mix"].items())))
    if s["confidence"]:
        lines.append("")
        lines.append("Decisiveness by axis (mean top confidence → how often it was applied)")
        lines.append("  counted only where Jev named a component; refusals shown separately")
        for kind, slot in sorted(s["confidence"].items()):
            n = slot["n"]
            refused = slot.get("refused", 0)
            # "no candidate named" is a real, informative outcome -- reporting it
            # beside n keeps a near-empty axis from reading as a calibrated one.
            tail = f"  (n={n}" + (f", refused {refused}" if refused else "") + ")"
            if not n:
                lines.append(f"  {kind:<12} no component ever named{tail}")
                continue
            lines.append(
                f"  {kind:<12} conf {slot['mean_confidence']:.2f} → applied "
                f"{slot['applied_rate'] * 100:.0f}%{tail}")
    if s["switches"]["applied"] or s["switches"]["blocked"]:
        lines.append("")
        lines.append("Live switching")
        lines.append(f"  applied           {s['switches']['applied']}")
        for k, v in sorted(s["switches"]["blocked"].items(), key=lambda kv: -kv[1]):
            lines.append(f"  blocked: {k:<18} {v}")
    if s["phases"]:
        lines.append("")
        lines.append("Observed phases at reroute time")
        for k, v in sorted(s["phases"].items(), key=lambda kv: -kv[1]):
            lines.append(f"  {k:<18} {v}")
    if s.get("stop_reasons"):
        lines.append("")
        lines.append("How supervised runs ended")
        for k, v in sorted(s["stop_reasons"].items(), key=lambda kv: -kv[1]):
            lines.append(f"  {k:<18} {v}")
    dv = s["divergence"]
    if dv["samples"]:
        lines.append("")
        lines.append("Predicted vs actual")
        lines.append(f"  sessions sampled  {dv['samples']}")
        lines.append(f"  work broader than the prediction  {dv['work_broader_than_prediction']}")
        lines.append("  (a high count here is the signal that one-shot routing under-describes the task)")
        if dv["sessions_with_no_tool_use"]:
            lines.append(f"  sessions with no tool use        {dv['sessions_with_no_tool_use']}")
    else:
        lines.append("")
        lines.append("No live sessions recorded yet — run `jevclaude --live \"<task>\"` (or `jevcodex` / `jevcursor`) "
                     "to collect predicted-vs-actual data.")
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: cli_report.py {last|stats} [--json]", file=sys.stderr)
        return 2
    cmd = args[0]
    as_json = "--json" in args[1:]
    cfg = load_cfg()
    if cmd == "last":
        print(render_last(cfg, as_json))
    elif cmd == "stats":
        print(render_stats(cfg, as_json))
    else:
        print(f"unknown report: {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
