#!/usr/bin/env python3
"""Runtime adapters: one supervisor, two agent CLIs.

Claude Code and Codex both let an outside process steer a running task, but by
different mechanisms, and the difference is load-bearing:

- **Claude Code** exposes an in-process control channel. With
  `--input-format stream-json` a `control_request` on stdin (`set_model`,
  `set_max_thinking_tokens`) changes the *live* session. Verified on 2.1.278.
- **Codex** has no such channel. Its lever is resume-chaining: each turn is a
  separate `codex exec` / `codex exec resume <thread_id>` process, and the new
  process may carry a different `-m/--model` or `model_reasoning_effort`.
  Verified on codex-cli 0.153.4 that context survives such a resume (a fact
  stored before an effort change was recalled after it).

So "switch the model" means *reconfigure in place* on Claude and *start the next
turn differently* on Codex. Both are expressed here as `apply_tier()` +
`send_turn()`, and the supervisor does not care which is which.

Each adapter also normalises the two CLIs' very different event streams into the
same small vocabulary the supervisor needs: text, tool names, token counts,
end-of-turn. Anything a runtime cannot report is reported as absent rather than
guessed -- notably Codex emits no per-turn token usage, so its token-growth
hysteresis is disabled rather than fed a fabricated number.
"""
from __future__ import annotations

import json
import os
import queue
import subprocess
import threading
import time

# ---------------------------------------------------------------------------
# Normalised turn event vocabulary
#   {"kind": "text",      "text": str}
#   {"kind": "tool",      "name": str}
#   {"kind": "usage",     "tokens": int}          # absent on runtimes w/o usage
#   {"kind": "turn_end",  "cost_usd": float|None}
#   {"kind": "session",   "id": str}
#   {"kind": "eof"}
#   {"kind": "error",     "message": str}
# ---------------------------------------------------------------------------


class RuntimeError_(RuntimeError):
    """Raised only for unrecoverable adapter setup problems."""


class BaseRuntime:
    name = "base"
    #: Tier names this runtime understands, cheapest first.
    tiers: tuple = ()
    #: True when a tier change applies to the live session (no turn boundary).
    in_process_switch = False
    #: True when the runtime reports per-turn token usage.
    reports_usage = False

    def start(self, task):
        raise NotImplementedError

    def send_turn(self, text):
        raise NotImplementedError

    def apply_tier(self, tier):
        """Move to `tier`. Returns (ok, detail)."""
        raise NotImplementedError

    def apply_effort(self, effort):
        """Set the reasoning budget. Returns (ok, detail)."""
        return False, {"reason": "unsupported"}

    def events(self, timeout):
        raise NotImplementedError

    def close(self):
        pass

    def diagnostics(self):
        return {}


# ---------------------------------------------------------------------------
# Claude Code
# ---------------------------------------------------------------------------

CLAUDE_EFFORT_TOKENS = {"low": 4000, "medium": 10000, "high": 24000, "xhigh": 48000}


class ClaudeRuntime(BaseRuntime):
    """Claude Code over stream-json, steered with control_requests."""

    name = "claude"
    tiers = ("haiku", "sonnet", "opus")
    in_process_switch = True
    reports_usage = True

    def __init__(self, tier, *, extra_args=None, cwd=None, bin_path=None):
        self.tier = tier
        self.extra_args = list(extra_args or [])
        self.cwd = cwd
        self.bin = bin_path or os.environ.get("CLAUDE_BIN", "claude")
        self.session = None

    def start(self, task):
        from live_supervisor import ClaudeSession  # local import: avoids a cycle
        self.session = ClaudeSession(self.tier, extra_args=self.extra_args,
                                     cwd=self.cwd, claude_bin=self.bin)
        return self.session.ask(task)

    def send_turn(self, text):
        return self.session.ask(text)

    def apply_tier(self, tier):
        # Validated here as well as in the policy, and for a measured reason:
        # Claude Code returns `control_response: success` for set_model("Haiku")
        # while continuing to run the previous model, so an unvalidated name
        # yields a ledger entry for a switch that never occurred. A rejected
        # name ("gpt-6-astra") does surface as an error, but the near-miss
        # spellings are exactly the ones a config typo produces.
        if tier not in self.tiers:
            return False, {"error": f"unknown tier {tier!r} (expected one of {', '.join(self.tiers)})"}
        ok, resp = self.session.set_model(tier)
        if ok:
            self.tier = tier
        return ok, resp

    def apply_effort(self, effort):
        return self.session.set_thinking(CLAUDE_EFFORT_TOKENS.get(effort, 10000))

    def events(self, timeout):
        """Yield normalised events for one turn, ending at turn_end/eof."""
        while True:
            try:
                ev = self.session.events.get(timeout=timeout)
            except queue.Empty:
                yield {"kind": "idle"}
                return
            t = ev.get("type")
            if t == "__eof__":
                yield {"kind": "eof"}
                return
            if ev.get("session_id"):
                yield {"kind": "session", "id": ev["session_id"]}
            if t == "assistant":
                # Every shape here is defensive on purpose. stream-json
                # legitimately emits `"content": "plain string"` for simple
                # messages, and an AttributeError raised out of this generator
                # escapes the supervisor's only handler: the run dies on a parse
                # error while `finally` still writes an apparently healthy
                # session record. The Codex adapter was already tolerant; this
                # one was not.
                msg = ev.get("message")
                if not isinstance(msg, dict):
                    if isinstance(msg, str) and msg:
                        yield {"kind": "text", "text": msg}
                    continue
                u = msg.get("usage")
                if isinstance(u, dict):
                    total = 0
                    for k in ("input_tokens", "cache_creation_input_tokens",
                              "cache_read_input_tokens"):
                        try:
                            total += int(u.get(k) or 0)
                        except (TypeError, ValueError):
                            pass
                    if total:
                        yield {"kind": "usage", "tokens": total}
                content = msg.get("content")
                if isinstance(content, str):
                    if content:
                        yield {"kind": "text", "text": content}
                    continue
                for b in content or []:
                    if not isinstance(b, dict):
                        if isinstance(b, str) and b:
                            yield {"kind": "text", "text": b}
                        continue
                    if b.get("type") == "text" and b.get("text"):
                        yield {"kind": "text", "text": b["text"]}
                    elif b.get("type") == "tool_use":
                        yield {"kind": "tool", "name": b.get("name", "?")}
            elif t == "result":
                yield {"kind": "turn_end", "cost_usd": ev.get("total_cost_usd")}
                return
            elif t == "system" and ev.get("subtype") == "turn_end":
                yield {"kind": "turn_end", "cost_usd": None}
                return

    def close(self):
        if self.session:
            self.session.close()

    def diagnostics(self):
        if not self.session:
            return {}
        return {"exit_code": self.session.proc.returncode,
                "stderr_tail": self.session.stderr_tail()}


# ---------------------------------------------------------------------------
# Codex
# ---------------------------------------------------------------------------

#: Codex tier -> (model override or None, reasoning effort).
#:
#: The model was left None here until 2026-09-22 on the strength of a real
#: measurement -- every id other than the configured default returned HTTP 400
#: on a ChatGPT-auth account -- but the conclusion drawn from it was too wide.
#: What the API rejects is ids that do not exist for the account (`gpt-5.6`,
#: `gpt-6`, and the sample config's own value among them). The ids the server
#: itself advertises are accepted, and it advertises them in a file the client
#: already maintains: ~/.codex/models_cache.json, carrying each model's
#: `supported_reasoning_levels`, `default_reasoning_level` and `visibility`.
#:
#: So the tier table is derived from that cache rather than hardcoded. A static
#: list would go stale the moment the account's catalogue changes, and the CLI
#: performs no client-side validation: an unavailable model or an unsupported
#: effort surfaces only as an HTTP 400 mid-run.
#:
#: Preference order per tier, first available wins. Names are matched against
#: the cache, so an entry absent from this account is skipped rather than
#: attempted. DATARIM_CODEX_MODEL_<TIER> still overrides everything.
CODEX_TIER_PREFERENCES = {
    "haiku": (("gpt-5.6-luna", "gpt-5.5"), "low"),
    "sonnet": (("gpt-5.6-terra", "gpt-5.6-luna"), "medium"),
    "opus": (("gpt-6-astra", "gpt-5.6-sol"), "high"),
}

#: Effort names the server accepts, cheapest first. `minimal` is documented but
#: rejected ("Supported values are: 'none', 'low', 'medium', 'high', 'xhigh',
#: and 'max'"); `none`, `max` and `ultra` work without being documented. Kept
#: here so a tier can be clamped to what a given model actually supports.
CODEX_EFFORT_ORDER = ("none", "low", "medium", "high", "xhigh", "max", "ultra")


def _models_cache(home=None):
    """Models the account can actually run, as the client last saw them.

    Returns {slug: {"efforts": [...], "default": str, "visibility": str}}.
    A missing or unreadable cache yields {} so callers fall back to effort-only
    steering rather than guessing a model that would 400 mid-run.
    """
    import json
    from pathlib import Path
    path = Path(home or Path.home())/'.codex/models_cache.json'
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    models = data.get('models') or data.get('data') or []
    if isinstance(models, dict):
        models = models.get('models', [])
    out = {}
    for entry in models:
        slug = entry.get('slug')
        if not slug:
            continue
        levels = entry.get('supported_reasoning_levels') or []
        efforts = [lv.get('effort') for lv in levels if isinstance(lv, dict) and lv.get('effort')]
        out[slug] = {'efforts': efforts,
                     'default': entry.get('default_reasoning_level'),
                     'visibility': entry.get('visibility')}
    return out


def codex_tier_settings(tier, home=None):
    """(model, effort) for a tier, validated against this account's catalogue.

    The effort is clamped to what the chosen model supports: `gpt-5.5` stops at
    `xhigh`, and the CLI would not complain about `ultra` -- the server would,
    after the run had started.
    """
    preferred, effort = CODEX_TIER_PREFERENCES.get(tier, ((), "medium"))
    cache = _models_cache(home)
    if not cache:
        return None, effort
    for slug in preferred:
        entry = cache.get(slug)
        if not entry:
            continue
        efforts = entry['efforts']
        if efforts and effort not in efforts:
            order = [e for e in CODEX_EFFORT_ORDER if e in efforts]
            wanted = CODEX_EFFORT_ORDER.index(effort)
            below = [e for e in order if CODEX_EFFORT_ORDER.index(e) <= wanted]
            effort = below[-1] if below else (order[0] if order else effort)
        return slug, effort
    return None, effort


#: Back-compat shape for callers that only need the static pair. Derived, so a
#: tier that resolves to a model on this host reports it here too.
CODEX_TIER_MAP = {tier: codex_tier_settings(tier) for tier in CODEX_TIER_PREFERENCES}


class CodexRuntime(BaseRuntime):
    """Codex CLI, steered by resume-chaining each turn with a new tier.

    Every turn is its own `codex exec` process: the first starts a thread, each
    later one resumes it. That is why `in_process_switch` is False -- a tier
    change here cannot interrupt a turn in flight, it takes effect on the next
    one. The supervisor already only switches at turn boundaries, so this costs
    nothing in practice.
    """

    name = "codex"
    tiers = ("haiku", "sonnet", "opus")
    in_process_switch = False
    # `turn.completed` carries a usage block (input/cached_input/cache_write),
    # so context-growth hysteresis works here too -- it just arrives once at
    # end of turn rather than per assistant message as on Claude.
    reports_usage = True

    def __init__(self, tier, *, extra_args=None, cwd=None, bin_path=None):
        self.tier = tier
        self.extra_args = list(extra_args or [])
        self.cwd = cwd
        self.bin = bin_path or os.environ.get("CODEX_BIN", "codex")
        self.thread_id = None
        self.proc = None
        self._q = None
        self._stderr = []
        self._lock = threading.Lock()
        self._last_rc = None
        self._threads = []
        self._generation = 0
        # Per-instance effort overrides. Deliberately NOT written back into the
        # module-level CODEX_TIER_MAP: that is shared state, so a one-off
        # override there would leak into every other runtime instance in the
        # process (and between tests) and would never be restored.
        self._effort_override = {}

    # -- tier resolution --------------------------------------------------
    def _tier_settings(self, tier):
        model, effort = CODEX_TIER_MAP.get(tier, (None, "medium"))
        effort = self._effort_override.get(tier, effort)
        override = os.environ.get(f"DATARIM_CODEX_MODEL_{tier.upper()}")
        if override:
            model = override
        return model, effort

    def _outside_git(self):
        """Codex refuses to run outside a git repo without an explicit flag."""
        try:
            return subprocess.run(["git", "rev-parse", "--is-inside-work-tree"],
                                  cwd=self.cwd, capture_output=True,
                                  timeout=5).returncode != 0
        except (OSError, subprocess.SubprocessError):
            return True  # assume the flag is needed rather than fail to start

    def _argv(self, text, *, resume):
        model, effort = self._tier_settings(self.tier)
        argv = [self.bin, "exec"]
        if resume and self.thread_id:
            argv += ["resume", self.thread_id]
        argv += ["--json"]
        if self._outside_git():
            argv += ["--skip-git-repo-check"]
        if model:
            argv += ["-m", model]
        if effort:
            argv += ["-c", f"model_reasoning_effort={effort}"]
        argv += self.extra_args
        argv.append(text)
        return argv

    # -- process lifecycle ------------------------------------------------
    def _reap(self):
        """Retire the previous turn's process and reader threads.

        Each Codex turn is its own process, so without this a supervised N-turn
        run accumulates N un-waited children and 2N reader threads. Worse, an
        orphaned reader still holds a reference to the OLD queue and would write
        `turn_end` into it (invisible to the current turn) and overwrite
        `_last_rc`, so the ledger's exit code could come from an earlier turn.
        """
        proc, self.proc = self.proc, None
        threads, self._threads = self._threads, []
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
        if proc is not None:
            self._last_rc = proc.returncode
        for t in threads:
            t.join(timeout=5)
        # Close the pipes explicitly. The reader threads iterate to EOF and
        # leave the file objects open; with one process per turn those
        # descriptors accumulate for the whole run (surfaced as ResourceWarning
        # under the test suite, and as an fd leak in a long supervised session).
        if proc is not None:
            for stream in (proc.stdout, proc.stderr, proc.stdin):
                try:
                    if stream is not None and not stream.closed:
                        stream.close()
                except OSError:
                    pass

    def _spawn(self, text, *, resume):
        self._reap()
        self._generation += 1
        gen = self._generation
        q = queue.Queue()
        self._q = q
        argv = self._argv(text, resume=resume)
        try:
            self.proc = subprocess.Popen(
                argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, bufsize=1, cwd=self.cwd,
            )
        except (OSError, ValueError) as e:
            q.put({"kind": "error", "message": f"cannot start codex: {e}"})
            q.put({"kind": "eof"})
            return False
        self._threads = [
            threading.Thread(target=self._read_stdout, args=(self.proc, q, gen), daemon=True),
            threading.Thread(target=self._read_stderr, args=(self.proc,), daemon=True),
        ]
        for t in self._threads:
            t.start()
        return True

    def _read_stdout(self, proc, q, gen):
        for line in proc.stdout:
            line = line.strip()
            if not line.startswith("{"):
                continue  # codex prints human preamble lines too
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            for ev in self._translate(d, gen):
                q.put(ev)
        proc.wait()
        with self._lock:
            # Only the current turn's reader may publish the exit code; a
            # straggler from a previous turn must not overwrite it.
            if gen == self._generation:
                self._last_rc = proc.returncode
        # A nonzero exit is NOT a completed turn. Reporting turn_end regardless
        # made a crash-looping child indistinguishable from a working one: the
        # supervisor counted a turn, paid for a Jev reroute on an empty digest,
        # and resumed a thread whose process kept dying until max_turns -- while
        # the ledger recorded N healthy turns alongside a nonzero exit_code.
        if proc.returncode:
            q.put({"kind": "error",
                   "message": f"codex exited {proc.returncode} without completing the turn"})
            q.put({"kind": "eof"})
            return
        q.put({"kind": "turn_end", "cost_usd": None})

    def _read_stderr(self, proc):
        for line in proc.stderr:
            with self._lock:
                self._stderr.append(line.rstrip())
                del self._stderr[:-50]

    def _translate(self, d, gen=None):
        """Map one Codex JSONL frame onto the normalised vocabulary.

        `gen` guards the one piece of instance state written here: a straggling
        reader from a previous turn must not overwrite the thread id.
        """
        t = d.get("type")
        if t == "thread.started" and d.get("thread_id"):
            if gen is None or gen == self._generation:
                self.thread_id = d["thread_id"]
            return [{"kind": "session", "id": d["thread_id"]}]
        if t in ("error", "turn.failed"):
            msg = d.get("message") or (d.get("error") or {}).get("message") or "codex error"
            return [{"kind": "error", "message": str(msg)[:500]}]
        if t == "turn.completed":
            u = d.get("usage", {}) or {}
            total = 0
            for k in ("input_tokens", "cached_input_tokens", "cache_write_input_tokens"):
                try:
                    total += int(u.get(k) or 0)
                except (TypeError, ValueError):
                    pass
            return [{"kind": "usage", "tokens": total}] if total else []
        if t == "item.completed":
            it = d.get("item", {}) or {}
            k = it.get("type")
            if k == "agent_message" and it.get("text"):
                return [{"kind": "text", "text": it["text"]}]
            if k == "command_execution":
                return [{"kind": "tool", "name": "Bash"}]
            if k == "file_change":
                # One tool event per changed path keeps the phase heuristic's
                # tool-mix counting comparable with Claude's per-edit events.
                n = len(it.get("changes") or []) or 1
                return [{"kind": "tool", "name": "Edit"} for _ in range(n)]
            if k == "error":
                return [{"kind": "error", "message": str(it.get("message"))[:500]}]
        return []

    # -- BaseRuntime ------------------------------------------------------
    def start(self, task):
        return self._spawn(task, resume=False)

    def send_turn(self, text):
        """Resume the thread for another turn. Fails closed without a thread id.

        Without `thread_id` a resume would silently become a fresh `codex exec`
        -- a new thread with none of the conversation. The supervisor would see
        a successful turn and report a normal multi-turn run while every turn
        actually restarted the task from scratch. Losing the run loudly is far
        better than continuing to spend money on work that cannot accumulate.
        """
        if not self.thread_id:
            self._note_error("cannot continue: Codex never reported a thread id "
                             "(startup or auth failure) -- refusing to restart the task "
                             "as a new thread")
            return False
        # Each Codex turn is a fresh process resuming the same thread; this is
        # also where a pending tier change takes effect.
        return self._spawn(text, resume=True)

    def _note_error(self, message):
        """Record an adapter-level error where diagnostics() will surface it."""
        with self._lock:
            self._stderr.append(f"[dr-jev] {message}")
            del self._stderr[:-50]

    def apply_tier(self, tier):
        """Record the tier for the next turn. Cannot affect a turn in flight."""
        if tier not in self.tiers:
            return False, {"reason": "unknown_tier"}
        self.tier = tier
        model, effort = self._tier_settings(tier)
        return True, {"subtype": "deferred_to_next_turn", "model": model, "effort": effort}

    def apply_effort(self, effort):
        """Override the effort for this instance's current tier, next turn on."""
        if effort not in ("low", "medium", "high"):
            return False, {"reason": "unsupported_effort"}
        self._effort_override[self.tier] = effort
        return True, {"subtype": "deferred_to_next_turn", "effort": effort}

    def events(self, timeout):
        q = self._q
        if q is None:
            # Nothing was ever spawned. Report it rather than raising an
            # AttributeError out of the supervisor's event loop.
            yield {"kind": "error", "message": "codex runtime not started"}
            yield {"kind": "eof"}
            return
        while True:
            try:
                ev = q.get(timeout=timeout)
            except queue.Empty:
                yield {"kind": "idle"}
                return
            yield ev
            if ev["kind"] in ("turn_end", "eof"):
                return

    def close(self):
        self._reap()

    def diagnostics(self):
        with self._lock:
            tail = list(self._stderr[-10:])
            rc = self._last_rc
        return {"exit_code": rc, "stderr_tail": tail, "thread_id": self.thread_id}


# ---------------------------------------------------------------------------

class CursorRuntime(CodexRuntime):
    """Cursor print/stream-json turns, resuming the exact reported session."""
    name = 'cursor'
    reports_usage = False

    def __init__(self, tier, **kwargs):
        import shutil
        kwargs.setdefault('bin_path', os.environ.get('CURSOR_BIN') or shutil.which('cursor-agent') or 'agent')
        super().__init__(tier, **kwargs)
        self._result_seen = False
        self._result_ok = False

    def _tier_settings(self, tier):
        return os.environ.get('DATARIM_CURSOR_MODEL_'+tier.upper()), None

    def _argv(self, text, *, resume):
        self._result_seen = self._result_ok = False
        args = [self.bin, '--print', '--output-format', 'stream-json']
        if resume:
            if not self.thread_id:
                raise RuntimeError_('Cursor did not report a session ID')
            args += ['--resume', self.thread_id]
        model, _ = self._tier_settings(self.tier)
        if model:
            args += ['--model', model]
        return args + self.extra_args + [text]

    def _translate(self, data, gen=None):
        if not isinstance(data, dict):
            return []
        events = []
        session = data.get('session_id')
        if isinstance(session, str) and session and (gen is None or gen == self._generation):
            if self.thread_id and self.thread_id != session:
                return [{'kind': 'error', 'message': 'Cursor changed session identity'}]
            self.thread_id = session
            events.append({'kind': 'session', 'id': session})
        kind = data.get('type')
        if kind == 'assistant':
            message = data.get('message')
            if isinstance(message, dict):
                content = message.get('content', [])
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'text':
                            events.append({'kind': 'text', 'text': str(block.get('text', ''))})
        elif kind == 'tool_call' and data.get('subtype') == 'started':
            call = data.get('tool_call')
            if isinstance(call, dict):
                events.extend({'kind': 'tool', 'name': name} for name in call)
        elif kind == 'result':
            self._result_seen = True
            self._result_ok = data.get('is_error') is False and data.get('subtype') == 'success'
            if not self._result_ok:
                events.append({'kind': 'error', 'message': 'Cursor result reported failure'})
        return events

    def _read_stdout(self, proc, q, gen):
        # Do not count a successful exit without the documented terminal result.
        for line in proc.stdout:
            try:
                data = json.loads(line)
            except (ValueError, TypeError):
                continue
            for event in self._translate(data, gen):
                q.put(event)
        proc.wait()
        self._last_rc = proc.returncode
        if proc.returncode or not self._result_seen or not self._result_ok:
            q.put({'kind': 'error', 'message': 'Cursor exited without a successful terminal result'})
            q.put({'kind': 'eof'})
        else:
            q.put({'kind': 'turn_end', 'cost_usd': None})

    def apply_tier(self, tier):
        if tier not in self.tiers or not self._tier_settings(tier)[0]:
            return False, {'reason': 'cursor_model_mapping_missing'}
        return super().apply_tier(tier)

    def apply_effort(self, effort):
        return False, {'reason': 'cursor_effort_not_supported'}


REGISTRY = {"claude": ClaudeRuntime, "codex": CodexRuntime, "cursor": CursorRuntime}


def available(name):
    """Whether the runtime's CLI is actually installed."""
    import shutil
    binary = {"claude": os.environ.get("CLAUDE_BIN", "claude"),
              "codex": os.environ.get("CODEX_BIN", "codex"),
              "cursor": os.environ.get("CURSOR_BIN") or shutil.which('cursor-agent') or 'agent'}.get(name)
    return bool(binary and shutil.which(binary))


def build(name, tier, **kw):
    cls = REGISTRY.get(name)
    if cls is None:
        raise RuntimeError_(f"unknown runtime: {name}")
    return cls(tier, **kw)
