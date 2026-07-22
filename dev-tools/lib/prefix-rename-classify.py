#!/usr/bin/env python3
"""prefix-rename-classify.py -- anchored task-prefix rename classifier (TUNE-0368).

Pure, offline, deterministic. Given OLD/NEW task prefixes, a file scope, and
literal exclude/include anchors plus collision numbers, classify every
``OLD-NNNN`` token as RENAME or KEEP and optionally apply the rewrite in place.

No third-party imports. Every anchor and prefix is treated as a LITERAL string;
only the token itself is matched by a fixed ``\\bOLD-\\d{4}\\b`` regex. This
avoids the MAINT-0005 failure mode where perl inline-regex broke on UTF-8
middle-dot and slash-bearing inputs (``architecture/ADR``): substring anchors
are compared with ``in``, never compiled as regex.

Classification, per line, for each ``OLD-NNNN`` token on it:
  1. If any exclude-anchor is a substring of the line -> KEEP (whole line
     protected; a homograph such as an Architecture Decision Record).
  2. Else if NNNN is in the collision set -> RENAME only when at least one
     include-anchor is a substring of the line; otherwise KEEP.
  3. Else (unambiguous task number) -> RENAME.

Modes:
  --dry-run  emit the RENAME/KEEP plan; write nothing; exit 0.
  --apply    rewrite RENAME tokens in place; print a summary; exit 0.
  --verify   assert no RENAME-classified OLD residue remains; exit non-zero
             and report file:line on any breach.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys


def parse_args(argv):
    p = argparse.ArgumentParser(
        prog="prefix-rename-classify.py",
        description="Anchored task-prefix rename classifier.",
    )
    p.add_argument("--old", required=True, help="OLD task prefix, e.g. ADR")
    p.add_argument("--new", required=True, help="NEW task prefix, e.g. ADSR")
    p.add_argument("--path", action="append", default=[], metavar="P",
                   help="file or directory to scan (repeatable)")
    p.add_argument("--exclude-anchor", action="append", default=[], metavar="S",
                   help="line containing literal S is never renamed (repeatable)")
    p.add_argument("--include-anchor", action="append", default=[], metavar="S",
                   help="collision number renames only on a line matching S "
                        "(repeatable)")
    p.add_argument("--collision-number", action="append", default=[],
                   metavar="NNNN",
                   help="4-digit number shared with a homograph (repeatable)")
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_const", dest="mode",
                      const="dry-run")
    mode.add_argument("--apply", action="store_const", dest="mode",
                      const="apply")
    mode.add_argument("--verify", action="store_const", dest="mode",
                      const="verify")
    p.add_argument("--json", action="store_true",
                   help="emit machine-readable JSON (dry-run/verify)")
    return p.parse_args(argv)


def iter_files(paths):
    """Yield text-file paths under the given files/dirs, skipping .git + binary."""
    for p in paths:
        if os.path.isfile(p):
            yield p
        elif os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = [d for d in dirs if d != ".git"]
                for f in sorted(files):
                    yield os.path.join(root, f)


def _looks_binary(path):
    try:
        with open(path, "rb") as fh:
            return b"\x00" in fh.read(4096)
    except OSError:
        return True


def decide(line, num, exclude, include, collisions):
    """Return 'KEEP' or 'RENAME' for one OLD-NNNN token on `line`."""
    if any(a in line for a in exclude):
        return "KEEP"
    if num in collisions:
        if include and any(a in line for a in include):
            return "RENAME"
        return "KEEP"
    return "RENAME"


def rewrite_line(line, token_re, new, exclude, include, collisions):
    """Return (new_line, rename_count) applying RENAME verdicts on `line`."""
    if any(a in line for a in exclude):
        return line, 0

    def repl(m):
        num = m.group(1)
        if num in collisions and not (include and any(a in line for a in include)):
            return m.group(0)
        return "%s-%s" % (new, num)

    return token_re.subn(repl, line)


def scan(args):
    """Walk the scope; return (plan, files_seen). plan = list of dicts."""
    token_re = re.compile(r"\b" + re.escape(args.old) + r"-(\d{4})\b")
    collisions = set(args.collision_number)
    plan = []
    files_seen = []
    for path in iter_files(args.path):
        if _looks_binary(path):
            continue
        files_seen.append(path)
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError):
            continue
        for lineno, line in enumerate(lines, start=1):
            for m in token_re.finditer(line):
                num = m.group(1)
                verdict = decide(line, num, args.exclude_anchor,
                                 args.include_anchor, collisions)
                plan.append({
                    "file": path, "line": lineno,
                    "token": m.group(0), "verdict": verdict,
                })
    return plan, files_seen


def apply_rewrite(args):
    """Rewrite RENAME tokens in place. Return total rename count."""
    token_re = re.compile(r"\b" + re.escape(args.old) + r"-(\d{4})\b")
    collisions = set(args.collision_number)
    total = 0
    for path in iter_files(args.path):
        if _looks_binary(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                lines = fh.readlines()
        except (OSError, UnicodeDecodeError):
            continue
        out = []
        changed = 0
        for line in lines:
            new_line, n = rewrite_line(line, token_re, args.new,
                                       args.exclude_anchor,
                                       args.include_anchor, collisions)
            out.append(new_line)
            changed += n
        if changed:
            with open(path, "w", encoding="utf-8") as fh:
                fh.writelines(out)
            total += changed
    return total


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)

    if args.mode == "apply":
        total = apply_rewrite(args)
        print("apply: %d token(s) renamed %s-NNNN -> %s-NNNN"
              % (total, args.old, args.new))
        return 0

    plan, _ = scan(args)
    residue = [e for e in plan if e["verdict"] == "RENAME"]

    if args.mode == "verify":
        if residue:
            if args.json:
                print(json.dumps({"ok": False, "residue": residue}))
            else:
                print("VERIFY FAIL: %d unrenamed OLD token(s):" % len(residue),
                      file=sys.stderr)
                for e in residue:
                    print("  %s:%d: %s" % (e["file"], e["line"], e["token"]),
                          file=sys.stderr)
            return 1
        if args.json:
            print(json.dumps({"ok": True, "residue": []}))
        else:
            print("VERIFY OK: no unrenamed %s-NNNN residue" % args.old)
        return 0

    # dry-run
    if args.json:
        print(json.dumps({"plan": plan}))
    else:
        renames = sum(1 for e in plan if e["verdict"] == "RENAME")
        keeps = len(plan) - renames
        for e in plan:
            print("%s  %s:%d  %s" % (e["verdict"], e["file"], e["line"],
                                     e["token"]))
        print("plan: %d RENAME, %d KEEP" % (renames, keeps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
