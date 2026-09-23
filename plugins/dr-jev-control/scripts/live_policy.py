#!/usr/bin/env python3
"""Switch policy for the live (dynamic) Jev supervisor.

Pure decision logic, no I/O: the supervisor owns the transport, this module owns
the question "is switching worth it right now?". Kept separate so the policy can
be unit-tested without a live Claude session or a live Jev API.

The governing economics: a model switch invalidates the prompt cache. Measured on
Claude Code 2.1.278 (2026-09-21) -- the turn before a switch read 30775 tokens
from cache; the first turn after it read 0 and re-created 27614. So every switch
re-pays the whole conversation as cache-creation tokens. A naive "ask Jev after
every step" loop therefore spends more than it saves, which is why switching is
gated on phase boundaries plus hysteresis rather than on every turn.

Asymmetry is deliberate: escalating (the agent is stuck and the cheap model is
burning turns) is cheaper to get wrong than de-escalating (the expensive model
was needed and we downgraded mid-problem), so de-escalation carries the higher
confidence bar and escalation is allowed to act first.
"""
from __future__ import annotations

TIERS = ("haiku", "sonnet", "opus")


def _cfg(cfg):
    live = cfg.get("live", {}) or {}
    return {
        "enabled": bool(live.get("enabled", True)),
        "escalate_threshold": float(live.get("escalate_threshold", 0.75)),
        "deescalate_threshold": float(live.get("deescalate_threshold", 0.85)),
        "min_tokens_between_switches": int(live.get("min_tokens_between_switches", 25000)),
        "min_seconds_between_switches": float(live.get("min_seconds_between_switches", 90)),
        "max_switches_per_session": int(live.get("max_switches_per_session", 6)),
        "turns_between_reroutes": int(live.get("turns_between_reroutes", 2)),
        "effort_switching": bool(live.get("effort_switching", True)),
        "model_ceiling": live.get("model_ceiling", {}) or {},
        "model_floor": live.get("model_floor", {}) or {},
    }


def rank(tier):
    """Order a tier name. Unknown names fall back to sonnet's position.

    The fallback keeps the gate's arithmetic total, but it is *only* safe for
    ordering: it silently maps `"Opus"`, `""` and even a foreign model name onto
    the middle tier. Never let a rank() fallback decide what gets *sent* to a
    runtime -- use canonical_tier() for that.
    """
    try:
        return TIERS.index(tier)
    except ValueError:
        return TIERS.index("sonnet")


def canonical_tier(tier, default="sonnet"):
    """Map a tier name onto an exact member of TIERS, or the default.

    Case-insensitive because the failure this prevents was observed: Claude Code
    answers `control_response: success` to `set_model("Haiku")` while staying on
    the model it was already running, so an operator typo in `model_floor`
    produced a ledger entry for a switch that never happened.
    """
    if isinstance(tier, str):
        t = tier.strip().lower()
        if t in TIERS:
            return t
    return default


def clamp_to_mode(tier, mode, cfg):
    """Hold a proposed tier inside the mode's declared envelope.

    The mode is operator policy; Jev advises inside it and never outside it.
    This mirrors the startup guardrails in route.py so a live switch cannot
    reach a tier that the initial routing decision was forbidden to pick.

    Every name that leaves here is canonicalised: the envelope is operator-edited
    JSON, and an unrecognised bound must not be able to smuggle a non-tier string
    through to a runtime's set_model.
    """
    c = _cfg(cfg)
    out = canonical_tier(tier)
    raw_ceiling = c["model_ceiling"].get(mode)
    raw_floor = c["model_floor"].get(mode)
    ceiling = canonical_tier(raw_ceiling, default=None) if raw_ceiling else None
    floor = canonical_tier(raw_floor, default=None) if raw_floor else None
    # A floor above the ceiling is a contradictory envelope. Resolving it by
    # order-of-application would let `economy` reach opus purely because the
    # floor check runs second -- and the README promises a live switch can never
    # leave the mode's envelope. The ceiling is the cost guarantee, so it wins.
    if ceiling and floor and rank(floor) > rank(ceiling):
        floor = ceiling
    if ceiling and rank(out) > rank(ceiling):
        out = ceiling
    if floor and rank(out) < rank(floor):
        out = floor
    return out


class SwitchGate:
    """Tracks session switch state and answers whether a switch may happen now.

    `tokens_seen` is the supervisor's running count of context tokens, used as
    the proxy for "how much cache would a switch throw away".
    """

    def __init__(self, cfg, mode, start_tier, *, now=0.0):
        self.cfg = _cfg(cfg)
        self.raw_cfg = cfg
        self.mode = mode
        self.tier = start_tier
        self.switches = 0
        self.last_switch_at = now
        self.last_switch_tokens = 0
        self.last_reroute_turn = 0
        self.history = []

    # -- reroute pacing ---------------------------------------------------
    def should_reroute(self, turn, *, phase_changed=False):
        """Whether to spend a Jev call at all on this turn boundary.

        A phase change is the signal the whole design is built around, so it
        always earns a call; otherwise reroutes are paced by turn count so a
        long single-phase stretch still gets re-examined occasionally.
        """
        if not self.cfg["enabled"]:
            return False
        if phase_changed:
            return True
        return (turn - self.last_reroute_turn) >= self.cfg["turns_between_reroutes"]

    def note_reroute(self, turn):
        self.last_reroute_turn = turn

    # -- switch admission -------------------------------------------------
    def evaluate(self, proposed_tier, confidence, *, turn, now, tokens_seen, reason="",
                 token_hysteresis=True):
        """Decide whether to move to `proposed_tier`.

        Returns a verdict dict: `{"switch": bool, "to": tier, "reason": str,
        "blocked_by": str|None}`. `blocked_by` names the specific guard so the
        ledger records *why* a proposed escalation did not happen -- a blocked
        switch is data about the policy, not a non-event.
        """
        target = clamp_to_mode(proposed_tier, self.mode, self.raw_cfg)
        verdict = {"switch": False, "from": self.tier, "to": target,
                   "confidence": round(float(confidence), 3), "reason": reason,
                   "blocked_by": None}

        if not self.cfg["enabled"]:
            verdict["blocked_by"] = "live_disabled"
            return verdict
        if target == self.tier:
            verdict["blocked_by"] = "already_on_tier"
            return verdict

        escalating = rank(target) > rank(self.tier)
        need = self.cfg["escalate_threshold"] if escalating else self.cfg["deescalate_threshold"]
        if confidence < need:
            verdict["blocked_by"] = f"below_threshold({need})"
            return verdict

        if self.switches >= self.cfg["max_switches_per_session"]:
            verdict["blocked_by"] = "max_switches"
            return verdict
        if (now - self.last_switch_at) < self.cfg["min_seconds_between_switches"]:
            verdict["blocked_by"] = "min_seconds"
            return verdict
        # `tokens_seen` is contractually monotone (see TurnObserver.context_tokens).
        # Clamp anyway: a non-monotone producer would make this delta negative and
        # silently wedge the gate closed for the rest of the session -- a failure
        # that looks exactly like the policy working correctly in the telemetry.
        if token_hysteresis:
            grown = max(0, tokens_seen - self.last_switch_tokens)
            if grown < self.cfg["min_tokens_between_switches"]:
                # Hysteresis on context growth: switching again before the
                # context has meaningfully moved pays the re-cache cost twice
                # for the same conversation.
                verdict["blocked_by"] = "min_tokens"
                return verdict
        else:
            # Runtime reports no token usage (see decide()'s token_hysteresis).
            # Recorded so the ledger shows which guard was unavailable rather
            # than implying all guards passed.
            verdict["token_hysteresis"] = "unavailable"

        verdict["switch"] = True
        return verdict

    def commit(self, verdict, *, now, tokens_seen):
        """Record an applied switch. Only call after the transport confirmed it."""
        if not verdict.get("switch"):
            return
        self.tier = verdict["to"]
        self.switches += 1
        self.last_switch_at = now
        self.last_switch_tokens = tokens_seen
        self.history.append({k: verdict[k] for k in ("from", "to", "confidence", "reason")})
