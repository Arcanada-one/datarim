#!/usr/bin/env python3
"""Live Jev supervisor: dynamic model/effort routing during a Claude Code session.

Why a supervisor process and not a hook: no hook output field can change the
session model. Verified on Claude Code 2.1.278 -- the `PreModelSwitch` hook is
reactive (it may allow/deny a switch that was already requested) and every other
hook event only returns `additionalContext` / `permissionDecision`. The one
channel that *initiates* a switch is a `control_request` on stdin, available when
Claude runs with `--input-format stream-json --output-format stream-json`. Its
recognized source is documented in the binary as
"sdk: headless set_model (SDK, Remote Control, IDE)". So whoever owns that pipe
owns dynamic routing; a hook cannot, at any timeout budget.

Flow:

    task --> Jev (initial route) --> claude --model <tier> (stream-json)
                                       |
                                  turn/phase boundary
                                       |
                              Jev (re-route, batched)
                                       |
                         SwitchGate (hysteresis + re-cache economics)
                                       |
                    control_request set_model / set_max_thinking_tokens

Fail-open throughout: any Jev or transport failure leaves the session running on
its current tier. A routing control plane that can halt the work it is routing
is worse than no control plane.
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import components  # noqa: E402
import runtimes  # noqa: E402
from ledger import log_event  # noqa: E402
from live_policy import SwitchGate, clamp_to_mode  # noqa: E402
from route import load_cfg, route  # noqa: E402


class _SupervisorStop(Exception):
    """Internal: abandon the supervision loop with stop_reason already set."""

# Thinking budgets per requested effort. Effort is the cheap lever: it changes
# the reasoning budget without necessarily invalidating the whole prompt cache
# the way a model switch does, so the policy prefers it for smaller corrections.
EFFORT_TOKENS = {"low": 4000, "medium": 10000, "high": 24000, "xhigh": 48000}

# Silence between stream-json frames that means the child is wedged. This only
# covers inter-frame silence -- a chatty-but-stuck agent resets it on every
# frame, which is why `--max-seconds` exists as the wall-clock cap on the run.
IDLE_TIMEOUT_S = 1800


class ClaudeSession:
    """Owns the stream-json pipes and the control_request/response handshake."""

    def __init__(self, model, extra_args=None, cwd=None, claude_bin=None):
        cmd = [claude_bin or os.environ.get("CLAUDE_BIN", "claude"),
               "-p", "--input-format", "stream-json",
               "--output-format", "stream-json", "--verbose",
               "--model", model]
        cmd += list(extra_args or [])
        self.cmd = cmd
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1, cwd=cwd,
        )
        self.events = queue.Queue()
        # rid -> {"event": Event, "resp": dict|None}. The waiter creates the slot
        # before sending and removes it when done.
        self._ctrl = {}
        # Responses whose rid we have issued but whose waiter has not yet parked
        # (the child can answer faster than the main thread reaches the wait) or
        # whose waiter already timed out. Bounded, so a stream of unmatched
        # responses cannot grow without limit.
        self._ctrl_early = {}
        self._ctrl_lock = threading.Lock()
        self._stdin_lock = threading.Lock()
        self._n = 0
        self._stderr = []
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    # -- plumbing ---------------------------------------------------------
    def _read_stdout(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get("type") == "control_response":
                rid = (ev.get("response") or {}).get("request_id")
                with self._ctrl_lock:
                    slot = self._ctrl.get(rid)
                    if slot is not None:
                        slot["resp"] = ev["response"]
                        slot["event"].set()
                    elif rid:
                        # No slot yet: either the child answered before the
                        # waiter parked, or the waiter already timed out. Park
                        # it so a fast response is not misread as a timeout.
                        # Bounded (FIFO-evicted) so an unmatched stream cannot
                        # grow without limit.
                        self._ctrl_early[rid] = ev["response"]
                        while len(self._ctrl_early) > 32:
                            self._ctrl_early.pop(next(iter(self._ctrl_early)))
                continue
            self.events.put(ev)
        self.events.put({"type": "__eof__"})

    def _read_stderr(self):
        for line in self.proc.stderr:
            with self._ctrl_lock:
                self._stderr.append(line.rstrip())
                del self._stderr[:-50]

    def stderr_tail(self, n=10):
        """Last stderr lines. This is where auth, bad-model and crash output
        lands, so it is surfaced in the ledger rather than silently discarded --
        otherwise a fail-open path is undiagnosable after the fact."""
        with self._ctrl_lock:
            return list(self._stderr[-n:])

    def _send(self, obj):
        if self.proc.poll() is not None:
            raise BrokenPipeError("claude process has exited")
        with self._stdin_lock:
            self.proc.stdin.write(json.dumps(obj, ensure_ascii=False) + "\n")
            self.proc.stdin.flush()

    # -- API --------------------------------------------------------------
    def ask(self, text):
        """Send a user turn. Returns False instead of raising on a dead child."""
        try:
            self._send({"type": "user", "message": {"role": "user",
                                                    "content": [{"type": "text", "text": text}]}})
            return True
        except (BrokenPipeError, OSError, ValueError):
            return False

    def control(self, subtype, timeout=20.0, **fields):
        """Issue a control_request and wait for its matching response.

        Returns (ok, response). Never raises on refusal -- a refused switch is a
        normal outcome the caller records and continues from. A `timeout` result
        means the outcome is UNKNOWN, not "unchanged": the switch may still land
        afterwards, so callers must not assume the old state still holds.
        """
        slot = {"event": threading.Event(), "resp": None}
        with self._ctrl_lock:
            self._n += 1
            rid = f"drjev-{self._n}"
            self._ctrl[rid] = slot
            # A response for this rid may already be parked if the child (or a
            # test harness) answered before we got here.
            early = self._ctrl_early.pop(rid, None)
            if early is not None:
                slot["resp"] = early
                slot["event"].set()
        try:
            self._send({"type": "control_request", "request_id": rid,
                        "request": {"subtype": subtype, **fields}})
        except (BrokenPipeError, OSError, ValueError) as e:
            with self._ctrl_lock:
                self._ctrl.pop(rid, None)
                self._ctrl_early.pop(rid, None)
            return False, {"subtype": "error", "error": str(e)}

        got = slot["event"].wait(timeout)
        with self._ctrl_lock:
            self._ctrl.pop(rid, None)
            resp = slot["resp"]
            if resp is None:
                # The reader may have parked it before we reached the wait.
                resp = self._ctrl_early.pop(rid, None)
            else:
                self._ctrl_early.pop(rid, None)
        if resp is None:
            return False, {"subtype": "timeout"}
        return resp.get("subtype") == "success", resp

    def set_model(self, model):
        return self.control("set_model", model=model)

    def set_thinking(self, tokens):
        return self.control("set_max_thinking_tokens", max_thinking_tokens=int(tokens))

    def close(self):
        try:
            if self.proc.stdin and not self.proc.stdin.closed:
                self.proc.stdin.close()
        except OSError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        # Reader threads iterate to EOF but leave the pipes open; close them so
        # no descriptor outlives the session.
        for stream in (self.proc.stdout, self.proc.stderr):
            try:
                if stream is not None and not stream.closed:
                    stream.close()
            except OSError:
                pass


class TurnObserver:
    """Accumulates one assistant turn's activity into a re-routing signal.

    The supervisor cannot read the agent's mind, so it infers the current phase
    from which tools ran. This is a heuristic and is labelled as such in the
    ledger: the whole point of recording predicted-vs-actual is to find out how
    wrong it is.
    """

    PHASE_BY_TOOL = {
        "Read": "investigate", "Grep": "investigate", "Glob": "investigate",
        "Edit": "implement", "Write": "implement", "MultiEdit": "implement",
        "NotebookEdit": "implement",
        "Task": "delegate",
    }

    def __init__(self):
        # Monotone across turns: this is the proxy for "how much prompt cache a
        # switch would throw away", so it must never go backwards. A per-turn
        # figure would, because usage reports swing between cache_read-heavy and
        # cache_creation-heavy turns -- and a decreasing counter makes the
        # gate's `tokens_seen - last_switch_tokens` delta negative, which blocks
        # every later switch for the rest of the session.
        self.context_tokens = 0
        self.reset()

    def reset(self):
        self.tools = []
        self.texts = []
        self.model = None

    @property
    def tokens(self):
        return self.context_tokens

    # -- runtime-neutral accumulation -------------------------------------
    def add_text(self, text):
        if text:
            self.texts.append(text)

    def add_tool(self, name):
        self.tools.append(name or "?")

    def add_usage(self, tokens):
        """Record a context-size sample. Monotone: see __init__."""
        try:
            self.context_tokens = max(self.context_tokens, int(tokens))
        except (TypeError, ValueError):
            pass

    def note(self, ev):
        """Accept a raw Claude Code stream-json frame.

        Retained because the Claude adapter's own tests drive the observer with
        real frames; the supervisor itself now feeds normalised events through
        add_text/add_tool/add_usage so a second runtime needs no special case.
        """
        if ev.get("type") != "assistant":
            return
        msg = ev.get("message", {}) or {}
        self.model = msg.get("model") or self.model
        u = msg.get("usage", {}) or {}
        # The live context size is what the request actually re-sent or read
        # back: prompt tokens plus whatever came from (or went into) cache.
        turn_total = 0
        for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
            try:
                turn_total += int(u.get(k) or 0)
            except (TypeError, ValueError):
                continue
        self.add_usage(turn_total)
        for block in msg.get("content", []) or []:
            if block.get("type") == "text" and block.get("text"):
                self.add_text(block["text"])
            elif block.get("type") == "tool_use":
                self.add_tool(block.get("name", "?"))

    def phase(self):
        """Dominant phase of the turn, by tool mix, with a bash-aware fallback."""
        if not self.tools:
            return "reason"
        counts = {}
        for name in self.tools:
            if name == "Bash":
                continue
            p = self.PHASE_BY_TOOL.get(name)
            if p:
                counts[p] = counts.get(p, 0) + 1
        if not counts:
            # Bash-only turns are ambiguous: tests, builds and greps all live
            # there. Treat as verification, the most common bash-only case.
            return "verify" if "Bash" in self.tools else "reason"
        return max(counts.items(), key=lambda kv: kv[1])[0]

    def digest(self, limit=2400, *, tool_limit=40):
        """Bounded summary of the turn, for the reroute question body.

        Both parts are capped. The tool list used to be joined unclamped while
        only the text was truncated, so the POST body grew linearly in tool-call
        count -- 5000 tool events measured at 32 KB of digest. Jev needs to know
        *what kind* of work is happening, and a deduplicated head plus a count
        carries that as well as an exhaustive list.
        """
        seen, uniq = set(), []
        for t in self.tools:
            if t not in seen:
                seen.add(t)
                uniq.append(t)
        shown = uniq[:tool_limit]
        tools = ", ".join(shown) or "none"
        if len(uniq) > len(shown):
            tools += f" (+{len(uniq) - len(shown)} more kinds)"
        if len(self.tools) > len(uniq):
            tools += f" · {len(self.tools)} calls total"
        body = "\n".join(self.texts)[-limit:]
        return f"Tools used this turn: {tools}\nAgent output:\n{body}"


def reroute_questions(cfg):
    """Questions for a mid-task re-route.

    Deliberately NOT the same set as the initial route: at this point the task
    text is old news and what matters is the trajectory -- is the agent stuck,
    did the work change character, does it now need more or less capability.

    Component probes are deliberately absent. A re-route cannot load a skill
    into a session that is already running (there is no control_request for
    that), so asking which components apply would pay tokens for an answer
    nothing can act on. Component selection stays a start-of-task decision.
    """
    q = {
        "needed_tier": {
            "type": "choice",
            "instructions": (
                "Based on what the agent has just been doing, which Claude model tier should handle the NEXT "
                "step of this work? Judge the work in front of the agent now, not the original request. "
                "Prefer haiku for mechanical or bounded follow-through, sonnet for normal engineering, "
                "opus only when the next step is genuinely difficult, ambiguous, architectural, or high-stakes."
            ),
            "criteria": {
                "haiku": "Mechanical, bounded follow-through (formatting, repetitive edits, simple checks)",
                "sonnet": "Normal engineering requiring meaningful reasoning",
                "opus": "Genuinely difficult, ambiguous, architectural, or high-stakes reasoning",
            },
        },
        "is_stuck": {
            "type": "noul",
            "instructions": (
                "Does the agent appear stuck, looping, repeatedly failing at the same thing, or contradicting "
                "itself -- such that more reasoning capability would plausibly change the outcome?"
            ),
        },
        "work_simplified": {
            "type": "noul",
            "instructions": (
                "Has the hard part been resolved, so that what remains is mechanical follow-through "
                "(applying a known fix, writing obvious tests, updating docs)?"
            ),
        },
        "needs_more_thinking": {
            "type": "noul",
            "instructions": "Would a substantially larger internal reasoning budget plausibly improve the next step?",
        },
    }
    return q


def decide(answers, gate, observer, *, turn, now, cfg, token_hysteresis=True):
    """Turn re-route answers into a switch verdict plus an effort proposal.

    `token_hysteresis=False` is for a runtime that reports no per-turn token
    usage (Codex). The context-growth guard is then skipped rather than fed a
    fabricated number: a zero-growth reading would block every switch forever,
    and inventing a value would put a guess into a cost control. The time-based
    and count-based guards still apply.
    """
    from jev_client import JevError  # noqa: F401  (documents the failure domain)

    tier_ans = answers.get("needed_tier", {}) or {}
    proposed = tier_ans.get("choice") or gate.tier
    try:
        conf = float(tier_ans.get("confidence", 0.0))
    except (TypeError, ValueError):
        conf = 0.0

    stuck = _noul(answers, "is_stuck")
    simplified = _noul(answers, "work_simplified")

    # Corroborating signals are applied DIRECTIONALLY. "Stuck" is evidence for
    # more capability and "simplified" is evidence for less, so each may only
    # reinforce a move in its own direction. Letting either boost confidence for
    # whatever tier was proposed would defeat the escalate/de-escalate asymmetry
    # the policy is built on -- e.g. "the hard part is done" (0.90) would push a
    # weakly-proposed escalation to opus straight past the 0.75 bar.
    from live_policy import rank
    going_up = rank(proposed) > rank(gate.tier)
    going_down = rank(proposed) < rank(gate.tier)

    reason_bits = []
    if going_up and stuck >= 0.7:
        conf = max(conf, stuck)
        reason_bits.append(f"stuck={stuck:.2f}")
    if going_down and simplified >= 0.7:
        conf = max(conf, simplified)
        reason_bits.append(f"simplified={simplified:.2f}")
    reason_bits.append(f"phase={observer.phase()}")

    verdict = gate.evaluate(proposed, conf, turn=turn, now=now,
                            tokens_seen=observer.tokens, reason=" ".join(reason_bits),
                            token_hysteresis=token_hysteresis)

    effort = None
    if gate.cfg["effort_switching"]:
        if _noul(answers, "needs_more_thinking") >= 0.75:
            effort = "high"
        elif simplified >= 0.8:
            effort = "low"
    return verdict, effort


def _noul(answers, key):
    a = answers.get(key)
    if not isinstance(a, dict):
        return 0.0
    try:
        return float(a.get("noul", 0.0))
    except (TypeError, ValueError):
        return 0.0


def render_summary(decision, *, live=False, runtime=None):
    """Compact operator-facing Jev Decision Summary."""
    a = decision.get("answers", {}) or {}
    sel = decision.get("selection", {}) or {}
    prof = decision.get("profile", {}) or {}

    def num(k):
        v = a.get(k, {})
        try:
            return f"{float(v.get('noul', 0)) * 100:.0f}%"
        except (TypeError, ValueError):
            return "n/a"

    cx = a.get("complexity", {}) or {}
    score = cx.get("score")
    lines = [
        "─" * 52,
        "Datarim × Jev" + ("  — live routing" if live else ""),
        "─" * 52,
        f"  Mode          {decision.get('mode', 'balanced')}",
    ]
    if runtime:
        lines.append(f"  Runtime       {runtime}")
    lines += [
        f"  Model         {decision.get('model', 'sonnet')}",
        f"  Complexity    {score if score is not None else 'n/a'} / 4",
        f"  System-2      {num('needs_system2')}",
        f"  Risk          {num('production_risk')}",
        f"  Validation    {num('needs_validation')}",
        f"  Parallel      {num('parallelizable')}",
        f"  Budget        fan-out {prof.get('max_agents', '?')} | context {prof.get('context_budget', '?')}",
    ]
    def fmt_scored(items):
        """Render name/score pairs, tolerating a malformed or older-schema entry.

        The summary is cosmetic and runs before Claude is launched, so a schema
        surprise here must degrade to a partial line, never abort the run.
        """
        out = []
        for x in items or []:
            if not isinstance(x, dict):
                out.append(str(x))
                continue
            name = x.get("name", "?")
            try:
                out.append(f"{name} {float(x.get('score')):.2f}")
            except (TypeError, ValueError):
                out.append(str(name))
        return ", ".join(out)

    skills = (sel.get("skills") or {})
    if skills.get("apply"):
        lines.append("  Skills        " + fmt_scored(skills["apply"]))
    else:
        lines.append("  Skills        none above threshold")
    if skills.get("mention"):
        lines.append("  (considered)  " + fmt_scored(skills["mention"][:3]))
    for kind, label in (("agents", "Agent"), ("commands", "Command")):
        s = sel.get(kind) or {}
        if s.get("choice") and s["choice"] != "none":
            mark = "" if s.get("applied") else "  (low confidence, advisory only)"
            try:
                conf = f"{float(s.get('confidence')):.2f}"
            except (TypeError, ValueError):
                conf = "n/a"
            lines.append(f"  {label:<13} {s['choice']} {conf}{mark}")
    u = decision.get("usage", {}) or {}
    if u:
        lines.append(f"  Jev usage     in {u.get('input_tokens', 0):,} / out {u.get('output_tokens', 0):,} tokens")
    lines.append("─" * 52)
    return "\n".join(lines)


def _looks_done(text, marker):
    """Whether the agent signalled completion.

    Deliberately literal: the marker is an explicit token the operator asks the
    agent to emit. Inferring completion from prose is unreliable, and guessing
    wrong either truncates real work or loops forever -- so an absent marker
    plus an exhausted turn budget is what actually stops the loop.
    """
    if not marker:
        return False
    return marker.lower() in (text or "").lower()


def run(task, *, mode, cfg, extra_args, quiet, explain, max_turns,
        continue_prompt=None, done_marker="TASK_COMPLETE", max_seconds=0,
        runtime="claude"):
    """Drive one supervised session end to end, on either agent runtime."""
    t0 = time.time()
    try:
        decision = route(task, cfg, mode)
    except Exception as e:  # fail open to the configured default tier
        decision = {"ok": False, "error": str(e),
                    "model": cfg["routing"].get("default_model", "sonnet"),
                    "mode": mode, "answers": {}, "selection": {}}

    tier = clamp_to_mode(decision.get("model", "sonnet"), mode, cfg)
    rt = runtimes.build(runtime, tier, extra_args=extra_args, cwd=os.getcwd())

    if not quiet:
        # The summary is cosmetic; a malformed or older-schema selection block
        # must not abort a run before the agent has even started.
        try:
            print(render_summary(decision, live=True, runtime=runtime), flush=True)
        except Exception:
            print(json.dumps(decision.get("selection", {}), ensure_ascii=False), flush=True)
        if explain:
            print(json.dumps(decision, ensure_ascii=False, indent=2), flush=True)
        print(f"Starting {runtime} on {tier}...\n", flush=True)

    session_id = None
    gate = SwitchGate(cfg, mode, tier, now=t0)
    obs = TurnObserver()

    actual = {"tools": [], "phases": [], "switches": [], "turns": 0}
    turn = 0
    # Deliberately NOT "completed": every ordinary exit assigns its own reason,
    # so a default of "completed" would be reachable only by an uncaught
    # exception or a Ctrl-C -- i.e. the single most reassuring token in the
    # vocabulary would mark exactly the aborted and crashed runs. An analyst
    # filtering the ledger for successful sessions would select the failures.
    stop_reason = "aborted"
    # Everything after the runtime object exists goes inside the try, so a child
    # that dies immediately (bad model, bad passthrough arg) is still reaped and
    # still produces a ledger record.
    try:
        if not rt.start(task):
            stop_reason = "startup_failed"
            raise _SupervisorStop()
        deadline = (t0 + max_seconds) if max_seconds else None
        while True:
            if deadline and time.time() > deadline:
                stop_reason = "max_seconds"
                break

            ended = False
            for ev in rt.events(IDLE_TIMEOUT_S):
                # Checked per frame, not only per turn: IDLE_TIMEOUT_S measures
                # inter-frame silence, which a productive agent resets on every
                # frame, so a single chatty turn could overrun --max-seconds
                # without bound. The flag advertises a wall-clock cap on the
                # whole run, so it has to hold inside a turn too.
                if deadline and time.time() > deadline:
                    stop_reason = "max_seconds"
                    ended = True
                    break
                kind = ev["kind"]
                if kind == "idle":
                    stop_reason = "idle_timeout"
                    ended = True
                    break
                if kind == "eof":
                    stop_reason = "child_exited"
                    ended = True
                    break
                if kind == "session":
                    session_id = ev["id"] or session_id
                elif kind == "text":
                    obs.add_text(ev["text"])
                    if not quiet:
                        print(ev["text"], flush=True)
                elif kind == "tool":
                    obs.add_tool(ev["name"])
                    if not quiet:
                        print(f"  · {ev['name']}", flush=True)
                elif kind == "usage":
                    obs.add_usage(ev["tokens"])
                elif kind == "error":
                    if not quiet:
                        print(f"[{runtime}] {ev['message']}", flush=True)
                    actual.setdefault("errors", []).append(ev["message"][:300])
                elif kind == "turn_end":
                    if not quiet and ev.get("cost_usd") is not None:
                        print(f"\n[turn complete · ${ev['cost_usd']:.4f}]", flush=True)
                    break
            if ended:
                break

            turn += 1
            actual["turns"] = turn
            actual["tools"].extend(obs.tools)
            phase = obs.phase()
            prev = actual["phases"][-1] if actual["phases"] else None
            actual["phases"].append(phase)
            last_text = "\n".join(obs.texts)[-4000:]

            if max_turns and turn >= max_turns:
                stop_reason = "max_turns"
                break

            if gate.should_reroute(turn, phase_changed=(phase != prev)):
                gate.note_reroute(turn)
                verdict = _reroute(rt, gate, obs, cfg, turn, quiet)
                if verdict:
                    actual["switches"].append(verdict)
            obs.reset()
            # A deferred switch only becomes real when another turn actually
            # runs. Anything still pending when the loop exits below is
            # downgraded in the teardown so the ledger never claims a switch
            # that no process ever saw.

            # Continuation: the supervisor keeps driving until the agent declares
            # completion, because a single-turn session gives dynamic routing
            # nothing to route. `continue_prompt` is the operator's own
            # follow-through instruction; without it this is a one-shot run.
            if not continue_prompt:
                stop_reason = "one_shot"
                break
            if _looks_done(last_text, done_marker):
                stop_reason = "done_marker"
                break
            if not rt.send_turn(continue_prompt):
                stop_reason = "write_failed"
                break
            # The next turn has started, so any deferred switch recorded above
            # is now genuinely in force.
            for sw in actual["switches"]:
                if sw.get("deferred") and not sw.get("took_effect"):
                    sw["took_effect"] = True
    except _SupervisorStop:
        pass  # reason already recorded in stop_reason
    except KeyboardInterrupt:
        stop_reason = "interrupted"
        raise
    except Exception as exc:
        # Name the failure in the record instead of letting it inherit the
        # default. The exception still propagates -- the operator gets the
        # traceback -- but the telemetry says what happened.
        stop_reason = "supervisor_error"
        actual.setdefault("errors", []).append(f"{type(exc).__name__}: {exc}"[:300])
        raise
    finally:
        # A deferred switch that no subsequent turn ever ran is not a switch.
        # Downgrading it keeps the predicted-vs-actual dataset honest -- it is
        # the evidence base for the next architecture revision, so an
        # over-counted switch there is worse than a missing one.
        # `final_tier` must be derived from the corrected switch list, not read
        # off the gate: gate.commit() advances gate.tier when the switch is
        # admitted, so a switch downgraded here would otherwise leave the same
        # JSON object asserting both "never took effect" and a final_tier no
        # process was ever invoked with.
        final_tier = tier
        for sw in actual["switches"]:
            if sw.get("deferred") and not sw.get("took_effect"):
                sw["applied"] = False
                sw["never_took_effect"] = True
            if sw.get("applied"):
                final_tier = sw.get("to", final_tier)
        if final_tier != gate.tier:
            # Not an error: the gate legitimately tracks an admitted switch that
            # the teardown then downgraded. Recorded so the divergence is
            # visible in the data rather than silently reconciled.
            actual["gate_tier_at_exit"] = gate.tier
        # Close first, then collect: the exit code only exists once the child
        # has been reaped, so reading diagnostics beforehand records None.
        rt.close()
        diag = rt.diagnostics()
        log_event(cfg, "live_session", task, {
            "runtime": runtime,
            "mode": mode, "session_id": session_id,
            "stop_reason": stop_reason,
            "exit_code": diag.get("exit_code"),
            "stderr_tail": diag.get("stderr_tail") or [],
            "predicted": {
                "model": decision.get("model"),
                "skills": [x["name"] for x in ((decision.get("selection", {}).get("skills") or {}).get("apply") or [])],
                "agent": (decision.get("selection", {}).get("agents") or {}).get("choice"),
                "command": (decision.get("selection", {}).get("commands") or {}).get("choice"),
            },
            "actual": actual,
            "final_tier": final_tier,
            "duration_s": round(time.time() - t0, 1),
        })
    return 0


def _reroute(rt, gate, obs, cfg, turn, quiet):
    """Ask Jev about the trajectory and apply whatever the gate admits."""
    from jev_client import evaluate
    from route import kill_switch_reason

    # Belt and braces: the gate already refuses to reroute when live routing is
    # disabled, but this is the only place in the supervisor that reaches the
    # network, so it checks the switch itself rather than trusting call order.
    off = kill_switch_reason()
    if off is not None or not cfg.get("routing", {}).get("enabled", True):
        return None

    try:
        res = evaluate(obs.digest(), reroute_questions(cfg), cfg)
    except Exception as e:
        log_event(cfg, "live_reroute_failed", obs.digest(), {"turn": turn, "error": str(e)})
        return None
    answers = res.get("answers", {}) or {}
    verdict, effort = decide(answers, gate, obs, turn=turn, now=time.time(), cfg=cfg,
                             token_hysteresis=rt.reports_usage)

    if verdict.get("switch"):
        ok, resp = rt.apply_tier(verdict["to"])
        verdict["applied"] = bool(ok)
        verdict["deferred"] = not rt.in_process_switch
        if ok:
            gate.commit(verdict, now=time.time(), tokens_seen=obs.tokens)
        else:
            verdict["transport_error"] = resp.get("subtype") or resp.get("reason")
            if resp.get("subtype") == "timeout":
                # UNKNOWN outcome, not "unchanged": the runtime may still apply
                # the switch after our deadline. Treating it as a no-op would
                # leave the gate tracking a tier the session is not on, which
                # poisons every later escalate/de-escalate comparison.
                # Committing is the safe side -- a redundant re-apply of the
                # intended tier is idempotent, a desynchronised gate is not.
                gate.commit(verdict, now=time.time(), tokens_seen=obs.tokens)
                verdict["tier_uncertain"] = True
                # The gate has moved and a session switch has been spent, so the
                # switch IS in force as far as all later policy is concerned.
                # Leaving applied=False here contradicted that: it routed the
                # operator message to the "refused by transport" arm while the
                # session was on the new tier, and made the timeout wording
                # below unreachable.
                verdict["applied"] = True

    if effort:
        ok_effort, _ = rt.apply_effort(effort)
        verdict["effort"] = effort if ok_effort else None

    # Wording is emitted only after every state change for this reroute is
    # settled, so the operator is never told "holding" on a turn that also
    # changed the reasoning budget (project AGENTS.md, Defensive Invariants).
    if not quiet:
        if verdict.get("applied"):
            # Wording must match what actually happened. A deferred switch (Codex)
            # has changed no running process yet, so it is never announced in the
            # past tense -- project AGENTS.md, Defensive Invariants.
            arrow = "→" if not verdict.get("deferred") else "⇢"
            when = "" if not verdict.get("deferred") else " — takes effect next turn"
            suffix = " (confirmation timed out; assuming applied)" if verdict.get("tier_uncertain") else ""
            note = f" · effort {verdict['effort']}" if verdict.get("effort") else ""
            print(f"\n[jev] {verdict['from']} {arrow} {verdict['to']} ({verdict['reason']}){when}{suffix}{note}\n", flush=True)
        elif verdict.get("switch"):
            print(f"\n[jev] switch to {verdict['to']} refused by transport ({verdict.get('transport_error')})\n", flush=True)
        elif verdict.get("effort"):
            print(f"\n[jev] holding {gate.tier}, effort → {verdict['effort']} ({verdict.get('blocked_by')})\n", flush=True)
        elif verdict.get("blocked_by") not in (None, "already_on_tier"):
            print(f"\n[jev] holding {gate.tier} ({verdict['blocked_by']})\n", flush=True)

    log_event(cfg, "live_reroute", obs.digest(), {"turn": turn, "verdict": verdict,
                                                  "phase": obs.phase(), "usage": res.get("usage", {})})
    return verdict


def _echo(ev):
    """Human-readable passthrough of the stream-json frames."""
    t = ev.get("type")
    if t == "assistant":
        for b in (ev.get("message", {}) or {}).get("content", []) or []:
            if b.get("type") == "text" and b.get("text"):
                print(b["text"], flush=True)
            elif b.get("type") == "tool_use":
                print(f"  · {b.get('name')}", flush=True)
    elif t == "result":
        cost = ev.get("total_cost_usd")
        if cost is not None:
            print(f"\n[turn complete · ${cost:.4f}]", flush=True)


def main():
    ap = argparse.ArgumentParser(prog="dr-jev-live",
                                 description="Supervised Claude Code session with dynamic Jev routing")
    ap.add_argument("task", nargs="?")
    ap.add_argument("--mode", choices=["economy", "balanced", "quality"], default=None)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--explain", action="store_true")
    ap.add_argument("--max-turns", type=int, default=0,
                    help="stop after N supervised turns (0 = no limit)")
    ap.add_argument("--continue-prompt", default=None,
                    help="follow-through instruction sent after each turn, enabling "
                         "multi-turn supervision (without it the session is one-shot)")
    ap.add_argument("--done-marker", default="TASK_COMPLETE",
                    help="token the agent emits to end a supervised multi-turn run")
    ap.add_argument("--max-seconds", type=float, default=0,
                    help="wall-clock cap on the whole supervised run (0 = no cap)")
    ap.add_argument("--runtime", choices=sorted(runtimes.REGISTRY), default=None,
                    help="agent CLI to supervise (default: claude, or DATARIM_JEV_RUNTIME)")
    # Everything after `--` belongs to Claude, not to us. argparse would
    # otherwise reject a pass-through flag such as --permission-mode as unknown.
    argv = sys.argv[1:]
    passthrough = []
    if "--" in argv:
        i = argv.index("--")
        argv, passthrough = argv[:i], argv[i + 1:]
    args = ap.parse_args(argv)
    args.claude_args = passthrough

    if not args.task:
        print("task required", file=sys.stderr)
        return 2
    cfg = load_cfg()
    mode = args.mode or os.environ.get("DATARIM_JEV_MODE") or cfg["routing"].get("default_mode", "balanced")
    runtime = (args.runtime or os.environ.get("DATARIM_JEV_RUNTIME")
               or cfg.get("live", {}).get("default_runtime") or "claude")
    if runtime not in runtimes.REGISTRY:
        print(f"unknown runtime: {runtime} (known: {', '.join(sorted(runtimes.REGISTRY))})", file=sys.stderr)
        return 2
    if not runtimes.available(runtime):
        print(f"{runtime} CLI not found on PATH; install it or pass --runtime", file=sys.stderr)
        return 2
    return run(args.task, mode=mode, cfg=cfg, extra_args=args.claude_args,
               quiet=args.quiet, explain=args.explain, max_turns=args.max_turns,
               continue_prompt=args.continue_prompt, done_marker=args.done_marker,
               max_seconds=args.max_seconds, runtime=runtime)


if __name__ == "__main__":
    raise SystemExit(main())
