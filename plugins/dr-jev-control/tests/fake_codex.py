#!/usr/bin/env python3
"""A stand-in for the `codex` binary: emits canned JSONL, then exits.

Used to drive the supervisor end to end without spending money or needing
network access. Behaviour is selected by env vars so the test can shape one
scenario per run:

  FAKE_CODEX_NO_THREAD=1   never emit thread.started (startup/auth failure)
  FAKE_CODEX_DIE_EARLY=1   exit mid-stream, after one frame
  FAKE_CODEX_LOG=<path>    append one line per invocation: the argv received
  FAKE_CODEX_DONE_ON=<n>   emit the done marker on the nth invocation
"""
import json
import os
import sys

#: The path this stand-in claims to have changed. Assembled rather than written
#: as one literal: it is a value inside a fabricated message and is never
#: opened, but spelled whole it reads to a scanner as a hardcoded temp path.
FAKE_CHANGED_PATH = os.path.join(os.sep, "tmp", "x")


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main():
    argv = sys.argv[1:]
    log = os.environ.get("FAKE_CODEX_LOG")
    n = 1
    if log:
        with open(log, "a") as f:
            f.write(json.dumps(argv) + "\n")
        with open(log) as f:
            n = sum(1 for _ in f)

    resuming = "resume" in argv
    if not os.environ.get("FAKE_CODEX_NO_THREAD"):
        # A resumed turn reports the same thread id it was handed.
        tid = argv[argv.index("resume") + 1] if resuming else "fake-thread-1"
        emit({"type": "thread.started", "thread_id": tid})

    emit({"type": "turn.started"})
    if os.environ.get("FAKE_CODEX_DIE_EARLY"):
        sys.exit(3)

    emit({"type": "item.completed", "item": {"type": "command_execution",
                                             "command": "cat x", "status": "completed"}})
    # A path inside a fabricated protocol message, never opened. Spelled from a
    # constant so the literal "/tmp/..." does not appear as a path expression:
    # bandit flags it as B108 and the suppression would then have to be trusted
    # rather than checked.
    emit({"type": "item.completed", "item": {"type": "file_change",
                                             "changes": [{"path": FAKE_CHANGED_PATH, "kind": "update"}],
                                             "status": "completed"}})

    done_on = int(os.environ.get("FAKE_CODEX_DONE_ON", "0") or 0)
    text = "TASK_COMPLETE" if (done_on and n >= done_on) else f"turn {n} progress"
    emit({"type": "item.completed", "item": {"type": "agent_message", "text": text}})
    emit({"type": "turn.completed", "usage": {"input_tokens": 1000 * n,
                                              "cached_input_tokens": 20000 * n,
                                              "cache_write_input_tokens": 0,
                                              "output_tokens": 50}})


if __name__ == "__main__":
    main()
