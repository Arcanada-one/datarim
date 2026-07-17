#!/usr/bin/env bash
# rename-task-prefix.sh — repeatable, safe project-task-prefix rename.
#
# PURPOSE
#   A project's task prefix sometimes changes (e.g. a project is renamed, or a
#   prefix collision is resolved). Every `OLD-<NNNN>` task ID must become
#   `NEW-<NNNN>` across the tree — in file BODIES and in file NAMES — while a
#   caller-supplied exclude list keeps intentionally-frozen historical IDs as-is
#   (e.g. references frozen in archived task records per the ecosystem's
#   history-agnostic rule). Doing this ad hoc with a bare `sed` is error-prone:
#   it rewrites substrings inside longer prefixes (`NEPTUNE-0001`), misses file
#   renames, and leaves no verification that the rename actually completed.
#
#   This tool wraps the operation into three phases:
#     1. anchored classify + body rewrite — a word-boundary-anchored classifier
#        (portable `\b`, via python3) matches ONLY whole `OLD-<digits>` IDs, skips
#        excluded IDs, and rewrites the rest to `NEW-<digits>`.
#     2. file renames — files whose basename carries a non-excluded `OLD-<digits>`
#        are renamed to the `NEW-` form.
#     3. verification sweep (V-AC) — after the rewrite, any residual non-excluded
#        `OLD-<digits>` occurrence is reported; in --apply mode a residual makes
#        the script exit non-zero, so "rename complete" is a verifiable claim.
#
#   DRY-RUN by default. Nothing is mutated until --apply is passed.
#
# USAGE
#   rename-task-prefix.sh --old OLD --new NEW [--root DIR]
#       [--exclude ID]... [--exclude-file FILE] [--apply] [--quiet]
#     --old OLD          source prefix (uppercase, e.g. TUNE). Required.
#     --new NEW          target prefix (uppercase, e.g. DATA). Required.
#     --root DIR         tree to operate on (default: cwd). `.git/` is skipped.
#     --exclude ID       full task ID to leave untouched (e.g. TUNE-0161).
#                        Repeatable.
#     --exclude-file F   file of exclude IDs, one per line (# comments allowed).
#     --apply            perform the rename (default is dry-run report only).
#     --quiet            machine-terse output (counts only).
#
# EXIT CODES
#   0  dry-run rendered, or --apply completed with no residual OLD IDs
#   1  --apply left residual non-excluded OLD IDs (verification sweep failed)
#   2  usage error / bad prefix / unreadable exclude file / python3 missing
#
# Conventions: strict mode; explicit regex validation of every prefix/ID; the
# python core is a QUOTED heredoc (no shell interpolation into the program) and
# receives all data via argv + one env var (no eval, no shell=True).
set -euo pipefail

SCRIPT_NAME="rename-task-prefix.sh"
VERSION="1.0.0"

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

die() { echo "ERROR: $*" >&2; exit 2; }

# --- Argument parsing -------------------------------------------------------
old="" new="" root="." apply=0 quiet=0
excludes=""     # newline-separated, assembled below
exclude_file=""

add_exclude() { excludes="${excludes}$1"$'\n'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --old)          shift; [ $# -gt 0 ] || usage; old="$1" ;;
        --new)          shift; [ $# -gt 0 ] || usage; new="$1" ;;
        --root)         shift; [ $# -gt 0 ] || usage; root="$1" ;;
        --exclude)      shift; [ $# -gt 0 ] || usage; add_exclude "$1" ;;
        --exclude-file) shift; [ $# -gt 0 ] || usage; exclude_file="$1" ;;
        --apply)        apply=1 ;;
        --quiet)        quiet=1 ;;
        --version)      echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
        -h|--help)      usage ;;
        *)              echo "ERROR: unknown flag '$1'" >&2; usage ;;
    esac
    shift
done

# --- Validation -------------------------------------------------------------
[ -n "$old" ] && [ -n "$new" ] || die "--old and --new are both required"
printf '%s' "$old" | grep -qE '^[A-Z][A-Z0-9]*$' || die "bad --old prefix '$old' (want ^[A-Z][A-Z0-9]*\$)"
printf '%s' "$new" | grep -qE '^[A-Z][A-Z0-9]*$' || die "bad --new prefix '$new' (want ^[A-Z][A-Z0-9]*\$)"
[ "$old" != "$new" ] || die "--old and --new are identical ('$old')"
[ -d "$root" ] || die "--root is not a directory: $root"
command -v python3 >/dev/null 2>&1 || die "python3 is required but not found on PATH"

if [ -n "$exclude_file" ]; then
    [ -r "$exclude_file" ] || die "cannot read --exclude-file: $exclude_file"
    while IFS= read -r line; do
        line="${line%%#*}"
        line="$(printf '%s' "$line" | tr -d '[:space:]')"
        [ -n "$line" ] && add_exclude "$line"
    done < "$exclude_file"
fi

# Validate every exclude ID shape (PREFIX-NNNN...).
if [ -n "$excludes" ]; then
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        printf '%s' "$id" | grep -qE '^[A-Z][A-Z0-9]*-[0-9]+$' \
            || die "bad --exclude ID '$id' (want ^[A-Z][A-Z0-9]*-[0-9]+\$)"
    done <<EOF
$excludes
EOF
fi

mode="dry-run"; [ "$apply" -eq 1 ] && mode="apply"

# --- Core: anchored classify + rewrite + rename + sweep (python3) ------------
# Data passed only via argv (mode/old/new/root/quiet) and the RTP_EXCLUDES env
# var (newline-separated). The heredoc is single-quoted: the program below is
# never expanded by the shell.
RTP_EXCLUDES="$excludes" python3 - "$mode" "$old" "$new" "$root" "$quiet" <<'PYEOF'
import os
import re
import sys

mode, old, new, root, quiet_s = sys.argv[1:6]
quiet = quiet_s == "1"
excludes = {
    line.strip()
    for line in os.environ.get("RTP_EXCLUDES", "").splitlines()
    if line.strip()
}

# Anchored: a whole OLD-<digits> token, not a substring of a longer prefix
# (\b before OLD blocks NEPTUNE-, \b after digits blocks -00012 tails).
token = re.compile(r"\b" + re.escape(old) + r"-([0-9]+)\b")

SKIP_DIRS = {".git", ".hg", ".svn", "node_modules", "__pycache__"}
apply = mode == "apply"

body_changed = []          # (path, n_rewrites)
renamed = []               # (old_path, new_path)
residual = {}              # id -> count  (non-excluded OLD ids still present)
excluded_hits = 0          # occurrences intentionally left as-is

def is_probably_text(path):
    try:
        with open(path, "rb") as fh:
            chunk = fh.read(4096)
    except OSError:
        return False
    return b"\x00" not in chunk

def replace(match):
    tid = match.group(0)
    if tid in excludes:
        return tid
    return new + "-" + match.group(1)

# --- Phase 1: body rewrite -------------------------------------------------
file_list = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    for fn in filenames:
        file_list.append(os.path.join(dirpath, fn))

for path in file_list:
    if not is_probably_text(path):
        continue
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        continue

    n_target = 0
    n_excluded = 0
    for m in token.finditer(text):
        if m.group(0) in excludes:
            n_excluded += 1
        else:
            n_target += 1
    excluded_hits += n_excluded
    if n_target:
        body_changed.append((path, n_target))
        if apply:
            new_text = token.sub(replace, text)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(new_text)

# --- Phase 2: file renames -------------------------------------------------
# Longest paths first so a nested file is renamed before its parent dir would be.
rename_plan = []
for path in sorted(file_list, key=len, reverse=True):
    base = os.path.basename(path)

    def rename_base(m):
        return m.group(0) if m.group(0) in excludes else new + "-" + m.group(1)

    # Only rename when a NON-excluded OLD id is in the basename.
    has_target = any(m.group(0) not in excludes for m in token.finditer(base))
    if not has_target:
        continue
    new_base = token.sub(rename_base, base)
    new_path = os.path.join(os.path.dirname(path), new_base)
    rename_plan.append((path, new_path))

for src, dst in rename_plan:
    renamed.append((src, dst))
    if apply:
        if os.path.exists(dst):
            print("ERROR: rename target already exists: %s" % dst, file=sys.stderr)
            sys.exit(2)
        os.rename(src, dst)

# --- Phase 3: verification sweep (V-AC) ------------------------------------
# Only meaningful AFTER a rewrite: re-scan for any residual non-excluded OLD id
# in a file BODY, a file NAME, or a DIRECTORY name. A directory name is out of
# rewrite scope (dirs are not renamed) — surfacing it as residual tells the
# operator to rename it by hand and re-run. In dry-run nothing was mutated, so
# the sweep is skipped (the plan above already lists every pending change).
if apply:
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for d in dirnames:
            for m in token.finditer(d):
                if m.group(0) not in excludes:
                    residual[m.group(0)] = residual.get(m.group(0), 0) + 1
        for fn in filenames:
            path = os.path.join(dirpath, fn)
            blobs = [fn]
            if is_probably_text(path):
                try:
                    with open(path, "r", encoding="utf-8") as fh:
                        blobs.append(fh.read())
                except (OSError, UnicodeDecodeError):
                    pass
            for blob in blobs:
                for m in token.finditer(blob):
                    if m.group(0) not in excludes:
                        residual[m.group(0)] = residual.get(m.group(0), 0) + 1

# --- Report ----------------------------------------------------------------
n_bodies = len(body_changed)
n_renames = len(renamed)
n_residual = sum(residual.values())

if quiet:
    print("mode=%s bodies=%d renames=%d excluded_hits=%d residual=%d"
          % (mode, n_bodies, n_renames, excluded_hits, n_residual))
else:
    verb = "would change" if not apply else "changed"
    print("== rename-task-prefix: %s-%s -> %s-  (%s) ==" % (old, "NNNN", new, mode))
    print("-- bodies (%s %d file(s)) --" % (verb, n_bodies))
    for path, n in body_changed:
        print("  %s  (%d occurrence(s))" % (path, n))
    verb_r = "would rename" if not apply else "renamed"
    print("-- file renames (%s %d) --" % (verb_r, n_renames))
    for src, dst in renamed:
        print("  %s -> %s" % (src, dst))
    if excludes:
        print("-- excluded IDs left untouched: %d occurrence(s) across %d id(s) --"
              % (excluded_hits, len(excludes)))
    if apply:
        print("-- verification sweep: %d residual non-excluded %s- id(s) --"
              % (n_residual, old))
        for tid, n in sorted(residual.items()):
            print("  RESIDUAL %s x%d  (body/name/dir still carries the old prefix)"
                  % (tid, n))
    else:
        print("-- verification sweep: skipped (runs after --apply) --")

# In apply mode a residual means the rename did not fully complete.
if apply and n_residual > 0:
    sys.exit(1)
sys.exit(0)
PYEOF
