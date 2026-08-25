#!/usr/bin/python3
"""Exercise the exact wrapper SIGCHLD drain slice in an isolated process."""

from __future__ import annotations

import os
from pathlib import Path
import signal
import sys
import textwrap
import time


START_ANCHOR = (
    "    if signal.SIGCHLD in signal.sigpending():  "
    "# SECURITY_RULE:wrapper_sigchld_pending_drain\n"
)
END_ANCHOR = (
    "    signal.pthread_sigmask(\n"
    "        signal.SIG_UNBLOCK, {signal.SIGCHLD}\n"
    "    )  # SECURITY_RULE:wrapper_sigchld_unblock\n"
)


def load_exact_slice(path: Path):
    try:
        source = path.read_text(encoding="utf-8")
        if source.count(START_ANCHOR) != 1 or source.count(END_ANCHOR) != 1:
            raise ValueError("anchor")
        start = source.index(START_ANCHOR)
        end = source.index(END_ANCHOR, start)
        exact_slice = textwrap.dedent(source[start:end])
        return compile(exact_slice, f"{path}:wrapper_sigchld_pending_drain", "exec")
    except (OSError, UnicodeError, ValueError, SyntaxError):
        return None


def reap_owned_child(child):
    if child is None:
        return None, True
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            observed, _ = os.waitpid(child, os.WNOHANG)
        except ChildProcessError:
            return None, True
        if observed == child:
            return None, True
        time.sleep(0.01)
    try:
        os.kill(child, signal.SIGKILL)
        os.waitpid(child, 0)
    except (ChildProcessError, ProcessLookupError):
        pass
    return None, True


def main() -> int:
    if len(sys.argv) != 2:
        print("HARNESS_INVALID:wrapper_sigchld_drain_anchor")
        return 2
    compiled_slice = load_exact_slice(Path(sys.argv[1]))
    if compiled_slice is None:
        print("HARNESS_INVALID:wrapper_sigchld_drain_anchor")
        return 2

    child = None
    previous_handler = signal.getsignal(signal.SIGCHLD)
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
    result = "HARNESS_INVALID:wrapper_sigchld_drain_fixture"
    status = 2
    try:
        signal.signal(signal.SIGCHLD, lambda _signum, _frame: None)
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGCHLD})
        if os.environ.get("CUSTOMER_DELIVERY_DRAIN_PROBE_FORCE_FIXTURE_FAILURE") == "1":
            raise OSError("forced fixture failure")
        child = os.fork()
        if child == 0:
            os._exit(0)
        deadline = time.monotonic() + 2
        while signal.SIGCHLD not in signal.sigpending():
            if time.monotonic() >= deadline:
                raise TimeoutError("SIGCHLD fixture did not become pending")
            time.sleep(0.01)
        try:
            exec(compiled_slice, {"signal": signal})
        except RuntimeError as error:
            if str(error) != "SIGCHLD remained pending":
                raise
            result = "wrapper_sigchld_pending_not_drained"
            status = 1
        else:
            if signal.SIGCHLD in signal.sigpending():
                raise RuntimeError("probe accepted a pending SIGCHLD")
            result = "PROBE_OK"
            status = 0
    except Exception:
        result = "HARNESS_INVALID:wrapper_sigchld_drain_fixture"
        status = 2
    finally:
        cleanup_failed = False
        try:
            child, _ = reap_owned_child(child)
            if os.environ.get("CUSTOMER_DELIVERY_DRAIN_PROBE_FORCE_CLEANUP_FAILURE") == "1":
                raise OSError("forced cleanup failure")
        except BaseException:
            cleanup_failed = True
            if child is not None:
                try:
                    child, _ = reap_owned_child(child)
                except BaseException:
                    cleanup_failed = True
        try:
            signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGCHLD})
            if signal.SIGCHLD in signal.sigpending():
                signal.sigwait({signal.SIGCHLD})
        except BaseException:
            cleanup_failed = True
        try:
            signal.signal(signal.SIGCHLD, previous_handler)
        except BaseException:
            cleanup_failed = True
        try:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)
        except BaseException:
            cleanup_failed = True
        if cleanup_failed:
            result = "HARNESS_INVALID:wrapper_sigchld_drain_cleanup"
            status = 2

    print(result)
    return status


if __name__ == "__main__":
    raise SystemExit(main())
