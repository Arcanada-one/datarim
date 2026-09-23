#!/usr/bin/env python3
"""Multi-component selection for the Jev control plane.

The TypeSafe System-One API has no multi-select question type (`multichoice`,
`multi`, `multiselect` and `tags` all return HTTP 400 -- verified 2026-09-21), so
"which skills apply" cannot be asked directly. It is modelled instead as one
`noul` question per shortlisted candidate. This is cheap because the API
evaluates the questions of a single request in parallel: measured 1 question
~1.07s vs 8 questions ~1.18s, i.e. latency is flat in question count while cost
scales with tokens. One batched request is therefore vastly preferable to N
sequential ones.

A single `choice` question is retained alongside the per-candidate probes for
kinds where exactly one answer is meaningful (agent, command, template): the
`choice` answer already carries the full `probabilities` distribution, so the
caller gets calibration data for free.
"""
from __future__ import annotations

# Kinds where several components can legitimately apply at once. A task that is
# simultaneously debugging + testing + review is the normal case, and forcing a
# single pick was the main source of low-confidence routing decisions.
MULTI_KINDS = ("skills",)


def _defaults(cfg):
    sel = (cfg.get("routing", {}) or {}).get("component_selection", {}) or {}
    return {
        "multi_select_max": int(sel.get("multi_select_max", 4)),
        "apply_threshold": float(sel.get("apply_threshold", 0.70)),
        "mention_threshold": float(sel.get("mention_threshold", 0.45)),
        "candidate_probe_limit": int(sel.get("candidate_probe_limit", 8)),
    }


def probe_key(kind, name):
    """Question key for a per-candidate applicability probe.

    The name is embedded so the answer can be mapped back without keeping a
    side table, and `|` is used because it cannot occur in a component name.
    """
    return f"probe:{kind}|{name}"


def build_probes(kind, candidates, cfg):
    """One `noul` question per candidate, capped by candidate_probe_limit."""
    d = _defaults(cfg)
    out = {}
    for c in candidates[: d["candidate_probe_limit"]]:
        desc = (c.get("description") or c.get("path") or "").strip()
        out[probe_key(kind, c["name"])] = {
            "type": "noul",
            "instructions": (
                f"Would the Datarim {kind[:-1]} '{c['name']}' materially help with this task? "
                f"Its purpose: {desc[:240]}. Answer for THIS component only, independently of any other."
            ),
            "criteria": {"true": "Materially useful for this task", "false": "Not materially useful"},
        }
    return out


def _probe_scores(kind, candidates, answers):
    scores = []
    for c in candidates:
        a = answers.get(probe_key(kind, c["name"]))
        if not isinstance(a, dict):
            continue
        v = a.get("noul")
        if v is None:
            continue
        try:
            raw = float(v)
        except (TypeError, ValueError):
            continue
        if not 0.0 <= raw <= 1.0:
            continue  # a probability outside [0,1] is a malformed answer
        # The full-precision value decides; the rounded one is only for display.
        # Rounding first let 0.6996 become 0.7 and clear a 0.70 gate the model's
        # own answer was below.
        scores.append({"name": c["name"], "score": round(raw, 3), "_raw": raw})
    scores.sort(key=lambda x: (-x["_raw"], x["name"]))
    return scores


def _score_of(x):
    """Full-precision score for threshold comparisons."""
    return x.get("_raw", x["score"])


def _public(x):
    """The candidate as it is recorded; the raw score is an internal detail."""
    return {k: v for k, v in x.items() if k != "_raw"}


def resolve(kind, candidates, answers, cfg):
    """Turn raw probe answers into an apply/mention/rejected split.

    Returns a dict with:
      apply    -- components at or above apply_threshold, capped at multi_select_max
      mention  -- components between mention_threshold and apply_threshold
      ranked   -- every scored candidate, highest first (for --explain)
      applied_by -- "threshold" or "none"

    A low-confidence decision deliberately yields an empty `apply` list rather
    than the best-of-a-bad-field: an unhelpful component that is *loaded* costs
    context and misdirects the agent, so silence is the cheaper failure.
    """
    d = _defaults(cfg)
    ranked = _probe_scores(kind, candidates, answers)
    qualified = [x for x in ranked if _score_of(x) >= d["apply_threshold"]]
    apply = qualified[: d["multi_select_max"]]
    # A candidate that cleared the threshold but lost to the cap used to fall out
    # of `apply` and `mention` both, so it vanished from the prediction record
    # entirely. That biases the campaign's headline metric: the divergence test
    # compares observed phases against len(predicted skills), so the same session
    # is flagged "work broader than prediction" at cap 4 and not at cap 6.
    capped = qualified[d["multi_select_max"]:]
    mention = capped + [
        x for x in ranked
        if d["mention_threshold"] <= _score_of(x) < d["apply_threshold"]
    ]
    out = {
        "apply": [_public(x) for x in apply],
        "mention": [_public(x) for x in mention],
        "ranked": [_public(x) for x in ranked],
        # Name the real cause: "threshold" when the gate decided, "cap" when the
        # operator's multi_select_max did.
        "applied_by": ("cap" if capped else "threshold") if apply else "none",
    }
    if capped:
        out["capped_out"] = [x["name"] for x in capped]
    return out


def single_choice(answer, cfg, *, threshold=None):
    """Gate a single `choice` answer behind its own confidence.

    `choice` answers carry `confidence` plus a full `probabilities` map. A pick
    below threshold is reported but NOT presented to the agent as a decision --
    the historical ledger shows skill/command picks landing at 0.36-0.64
    confidence, which is too weak to be worth spending context on.
    """
    d = _defaults(cfg)
    th = d["apply_threshold"] if threshold is None else float(threshold)
    if not isinstance(answer, dict):
        return {"choice": "none", "confidence": 0.0, "applied": False, "probabilities": {}}
    choice = answer.get("choice", "none")
    try:
        raw = float(answer.get("confidence", 0.0))
    except (TypeError, ValueError):
        raw = 0.0
    probs = answer.get("probabilities") or {}
    # Compare at full precision, report rounded: rounding first let 0.6996 clear
    # a 0.70 gate.
    applied = bool(choice and choice != "none" and raw >= th)
    return {"choice": choice, "confidence": round(raw, 3), "applied": applied,
            "probabilities": probs}
