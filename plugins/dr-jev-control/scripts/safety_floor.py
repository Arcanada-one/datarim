#!/usr/bin/env python3
"""Deterministic destructive-command floor.

This is the only guard in the plugin that is independent of the control plane:
it must hold when Jev is disabled, unreachable, or misconfigured. It is
therefore kept in its own module, evaluated before any config is read, and
matched against a *normalised* command rather than raw text.

Why normalisation. The original patterns matched literal spellings, which made
the floor porous in exactly the ways an operator (or an agent) would trip over
by accident: `rm -fr /` and `rm -r -f /` are the same command as `rm -rf /` but
missed; `rm -rf /*` missed because the pattern required whitespace after the
slash; `git push -f` missed while the *safer* `--force-with-lease` was blocked
by a substring match on `--force`. Matching on a parsed argv closes that class
instead of playing whack-a-mole with spellings.

The floor is intentionally narrow. It blocks a small set of
catastrophic-and-irreversible commands, not everything risky -- graded risk is
the advisory layer's job. A false block here is recoverable (the operator
rephrases); a missed `rm -rf /` is not.
"""
from __future__ import annotations

import os
import posixpath
import re
import shlex

#: Roots whose recursive deletion is treated as catastrophic.
_PROTECTED_ROOTS = ("/", "/*", "/.", "/usr", "/etc", "/var", "/bin", "/sbin",
                    "/lib", "/opt", "/boot", "/dev", "/sys", "/proc", "/home",
                    "/Users", "/System", "/Library", "/Applications")

#: The home directory, in every spelling a shell would accept. Kept separate
#: from _PROTECTED_ROOTS because these are resolved rather than compared
#: literally. Measured gap: `rm -rf ~` and `rm -rf $HOME` passed the floor while
#: `rm -rf /Users` was blocked -- the same irreversible loss for the operator,
#: and the spelling a runaway script is far more likely to produce.
_HOME_SPELLINGS = ("~", "~/", "$HOME", "${HOME}", "$HOME/", "${HOME}/",
                   "~/*", "$HOME/*", "${HOME}/*")


def _is_home_target(target):
    """Whether a target names the home directory itself (not a path inside it)."""
    t = target.strip()
    if t in _HOME_SPELLINGS:
        return True
    home = os.path.expanduser("~").rstrip("/")
    # Compare literally as well: an already-expanded $HOME arrives as a path.
    if home and t.rstrip("/").rstrip("*").rstrip("/") == home:
        return True
    return False


def _split(command):
    """Best-effort argv split; falls back to whitespace on unbalanced quotes."""
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def _strip_wrappers(argv):
    """Drop leading sudo/env-style wrappers so the real command is inspected."""
    out = list(argv)
    while out:
        head = out[0].rsplit("/", 1)[-1]
        if head in ("sudo", "doas", "command", "nice", "nohup", "time", "eval", "exec"):
            out = out[1:]
            value_flags = {'-u', '-g', '-h', '-p', '-C', '-T', '-r', '-n'} if head in ('sudo', 'doas') else {'-n'} if head == 'nice' else set()
            # sudo -n means non-interactive and takes no value.
            if head == 'sudo':
                value_flags.discard('-n')
            while out and out[0].startswith('-'):
                token = out[0]
                out = out[2:] if token in value_flags else out[1:]
                if token == '--':
                    break
            continue
        if head == "env":
            out = out[1:]
            while out:
                if out[0] in ('-u', '--unset', '-C', '--chdir'):
                    out = out[2:]
                elif out[0].startswith('-') or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", out[0]):
                    out = out[1:]
                else:
                    break
            continue
        break
    return out


def _flags(argv):
    """Expand clustered short flags and collect long flags.

    `-rf` -> {"r","f"}, so `-rf`, `-fr` and `-r -f` all look the same.
    """
    short, long = set(), set()
    for tok in argv[1:]:
        if tok == "--":
            break
        if tok.startswith("--"):
            long.add(tok[2:].split("=", 1)[0])
        elif tok.startswith("-") and len(tok) > 1:
            short.update(tok[1:])
    return short, long


def _operands(argv):
    return [t for t in argv[1:] if not t.startswith("-")]


def _is_catastrophic_rm(argv):
    short, long = _flags(argv)
    recursive = bool(short & {"r", "R"}) or "recursive" in long
    if not recursive:
        return False
    for target in _operands(argv):
        if target.startswith('/'):
            target = posixpath.normpath(target)
        t = target.rstrip("/") or "/"
        if target in _PROTECTED_ROOTS or t in _PROTECTED_ROOTS:
            return True
        if _is_home_target(target):
            return True
        # `/ *`-style globs and a bare root with a trailing glob.
        if re.fullmatch(r"/\*+", target) or re.fullmatch(r"/[A-Za-z]*/?\*+", target):
            return True
    return False


#: Block devices whose overwrite destroys every file on them at once. Matched as
#: a resolved path so `/dev/sda`, `/dev/sda1` and `/dev/nvme0n1p2` are all seen,
#: while a regular file under a different path is not.
_BLOCK_DEVICE = re.compile(
    r"^/dev/(sd[a-z]+\d*|hd[a-z]+\d*|vd[a-z]+\d*|xvd[a-z]+\d*"
    r"|nvme\d+n\d+(p\d+)?|mmcblk\d+(p\d+)?|disk\d+(s\d+)?)$")


def _is_raw_device_write(argv):
    """`dd` whose output operand is a whole disk or partition.

    Reading FROM a device is how a backup is taken and stays allowed; only the
    write side is catastrophic. `of=` is the only way dd names its target, so
    the operand is matched rather than the presence of a device anywhere.
    """
    for token in argv[1:]:
        if token.startswith("of="):
            return bool(_BLOCK_DEVICE.match(posixpath.normpath(token[3:])))
    return False


def _is_filesystem_format(argv, name):
    """`mkfs`/`mkfs.<type>` targeting a block device.

    Formatting a loop file or an image is ordinary work; formatting the device
    discards the filesystem and everything in it with no file-level recovery.
    """
    if name != "mkfs" and not name.startswith("mkfs."):
        return False
    skip_next = False
    for token in argv[1:]:
        if skip_next:
            skip_next = False
            continue
        if token in ("-t", "-T", "-b", "-i", "-L", "-U", "-m", "-O"):
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        if _BLOCK_DEVICE.match(posixpath.normpath(token)):
            return True
    return False


def _is_force_push(argv):
    if len(argv) < 2 or argv[1] != "push":
        return False
    short, long = _flags(argv)
    # Lease/include flags do not cancel an explicit --force or forced refspec.
    return "force" in long or "f" in short or any(t.startswith('+') for t in argv[2:])


def _git_subcommand(argv):
    index = 1
    with_value = {'-C', '-c', '--git-dir', '--work-tree', '--namespace', '--config-env'}
    while index < len(argv) and argv[index].startswith('-'):
        token = argv[index]
        index += 2 if token in with_value else 1
    return [argv[0], *argv[index:]]


def _is_hard_reset(argv):
    if len(argv) < 2 or argv[1] != "reset":
        return False
    _, long = _flags(argv)
    return "hard" in long


#: SQL is matched textually: it arrives as a query string, not as argv.
_SQL_DROP = re.compile(r"\bDROP\s+(DATABASE|SCHEMA)\b", re.I)


#: Per-segment cap on what is handed to shlex.split, which is quadratic in
#: input length. Measured: 1 MB took 6.4 s and 2 MB took 25 s, so the host's
#: hook timeout (9 s) fired first and the floor never returned a verdict -- the
#: guard was bypassable purely by payload size. Applied per segment rather than
#: to the whole command so a destructive stage after a large one is still seen.
_MAX_SEGMENT_CHARS = 16384


def _segments(command):
    """Linear scan: shell separators inside quotes belong to that argv item."""
    start, quote, escaped = 0, None, False
    for index, char in enumerate(command):
        if escaped:
            escaped = False
            continue
        if char == '\\' and quote != "'":
            escaped = True
        elif quote:
            if char == quote:
                quote = None
        elif char in ('"', "'"):
            quote = char
        elif char in ';|&\n':
            yield command[start:index]
            start = index+1
    yield command[start:]


def destructive_reason(command, _depth=0):
    """Return why `command` is blocked, or None if it is allowed.

    Every command is checked as a whole and per pipeline/`&&` segment, so a
    destructive stage hidden after `cd / && ...` is still caught.
    """
    if not command or not isinstance(command, str):
        return None
    if _SQL_DROP.search(command):
        return "SQL DROP DATABASE/SCHEMA"

    for segment in _segments(command):
        if len(segment) > _MAX_SEGMENT_CHARS:
            # Keep BOTH ends. The command name and flags live at the head, but
            # the target operand lives at the tail -- a head-only truncation let
            # `rm -rf <100k repeated flags> /` through, because the `/` fell off
            # the end. Verified as a real miss before this was split in two.
            half = _MAX_SEGMENT_CHARS // 2
            segment = segment[:half] + " " + segment[-half:]
        argv = _strip_wrappers(_split(segment))
        if not argv:
            continue
        name = argv[0].rsplit("/", 1)[-1]
        if name in ('bash', 'sh', 'zsh', 'dash', 'ksh'):
            for index, arg in enumerate(argv[1:], 1):
                if arg.startswith('-') and not arg.startswith('--') and 'c' in arg[1:] and index+1 < len(argv):
                    if _depth >= 4:
                        return 'nested shell exceeds deterministic inspection depth'
                    nested = destructive_reason(argv[index+1], _depth+1)
                    if nested:
                        return nested
                    break
        if name == "rm" and _is_catastrophic_rm(argv):
            return "recursive delete of a protected path"
        if name == "dd" and _is_raw_device_write(argv):
            return "raw write to a block device"
        if _is_filesystem_format(argv, name):
            return "filesystem format of a block device"
        if name == "git":
            argv = _git_subcommand(argv)
            if _is_force_push(argv):
                return "git force push"
            if _is_hard_reset(argv):
                return "git reset --hard"
    return None
