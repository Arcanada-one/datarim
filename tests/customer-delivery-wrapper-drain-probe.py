#!/usr/bin/python3
"""Exercise the exact wrapper drain operation and Linux DFL integration."""

from __future__ import annotations

import ast
import os
from pathlib import Path
import signal
import stat
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


SIGWAIT_SLICE = """\
if signal.SIGCHLD in signal.sigpending():
    signal.sigwait({signal.SIGCHLD})
if signal.SIGCHLD in signal.sigpending():
    raise RuntimeError("SIGCHLD remained pending")
"""
PASS_SLICE = """\
if signal.SIGCHLD in signal.sigpending():
    pass
if signal.SIGCHLD in signal.sigpending():
    raise RuntimeError("SIGCHLD remained pending")
"""
ALLOWED_OPERATIONS = {
    ast.dump(ast.parse(SIGWAIT_SLICE), include_attributes=False): "sigwait",
    ast.dump(ast.parse(PASS_SLICE), include_attributes=False): "pass",
}


def read_bounded_regular(path: Path):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 262144:
            raise ValueError("invalid probe source")
        raw = os.read(descriptor, 262145)
        if len(raw) > 262144 or os.read(descriptor, 1):
            raise ValueError("probe source exceeds bound")
        return raw.decode("utf-8")
    finally:
        os.close(descriptor)


def load_exact_operation(path: Path):
    try:
        source = read_bounded_regular(path)
        if source.count(START_ANCHOR) != 1 or source.count(END_ANCHOR) != 1:
            return None, "anchor"
        start = source.index(START_ANCHOR)
        end = source.index(END_ANCHOR, start)
        exact_slice = textwrap.dedent(source[start:end])
        if len(exact_slice.encode("utf-8")) > 1024:
            return None, "operation"
        tree = ast.parse(exact_slice, filename=f"{path}:wrapper_sigchld_pending_drain")
    except (OSError, UnicodeError, ValueError):
        return None, "anchor"
    except SyntaxError:
        return None, "operation"
    operation = ALLOWED_OPERATIONS.get(ast.dump(tree, include_attributes=False))
    if operation is None:
        return None, "operation"
    return operation, None


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
    if (
        len(sys.argv) != 4
        or sys.argv[1] not in {"operation", "linux-dfl"}
        or sys.argv[2] not in {"normal", "force-fixture", "force-cleanup"}
    ):
        print("HARNESS_INVALID:wrapper_sigchld_drain_anchor")
        return 2
    mode = sys.argv[1]
    failure_mode = sys.argv[2]
    if mode == "linux-dfl" and not sys.platform.startswith("linux"):
        print("HARNESS_INVALID:wrapper_sigchld_drain_platform")
        return 2
    operation, load_error = load_exact_operation(Path(sys.argv[3]))
    if load_error is not None:
        print(f"HARNESS_INVALID:wrapper_sigchld_drain_{load_error}")
        return 2

    child = None
    previous_handler = signal.getsignal(signal.SIGCHLD)
    previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, set())
    result = "HARNESS_INVALID:wrapper_sigchld_drain_fixture"
    status = 2
    try:
        if mode == "operation":
            signal.signal(signal.SIGCHLD, lambda _signum, _frame: None)
            child_exit = 0
            pending_failure = "wrapper_sigchld_operation_pending_not_drained"
        else:
            signal.signal(signal.SIGCHLD, signal.SIG_DFL)
            if signal.getsignal(signal.SIGCHLD) is not signal.SIG_DFL:
                raise RuntimeError("SIGCHLD disposition remained non-default")
            child_exit = 37
            pending_failure = "wrapper_sigchld_dfl_pending_not_drained"
        signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGCHLD})
        if failure_mode == "force-fixture":
            raise OSError("forced fixture failure")
        child = os.fork()
        if child == 0:
            os._exit(child_exit)
        deadline = time.monotonic() + 2
        while signal.SIGCHLD not in signal.sigpending():
            if time.monotonic() >= deadline:
                if mode == "linux-dfl":
                    result = "HARNESS_INVALID:wrapper_sigchld_dfl_pending_precondition"
                    status = 2
                    break
                raise TimeoutError("SIGCHLD fixture did not become pending")
            time.sleep(0.01)
        else:
            if operation == "sigwait":
                observed_signal = signal.sigwait({signal.SIGCHLD})
                if observed_signal != signal.SIGCHLD:
                    raise RuntimeError("probe drained an unexpected signal")
            if signal.SIGCHLD in signal.sigpending():
                result = pending_failure
                status = 1
            else:
                result = "PROBE_OK"
                status = 0
        owned_child = child
        observed_child, child_status = os.waitpid(owned_child, 0)
        if observed_child == owned_child:
            child = None
        if observed_child != owned_child or not os.WIFEXITED(child_status):
            raise RuntimeError("probe child ownership was lost")
        if os.WEXITSTATUS(child_status) != child_exit:
            raise RuntimeError("probe child status changed")
    except Exception:
        result = "HARNESS_INVALID:wrapper_sigchld_drain_fixture"
        status = 2
    finally:
        cleanup_failed = False
        try:
            child, _ = reap_owned_child(child)
            if failure_mode == "force-cleanup":
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
