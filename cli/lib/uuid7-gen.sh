#!/usr/bin/env bash
# cli/lib/uuid7-gen.sh — UUID v7 generator helper.
# Source: TUNE-0271 plan § Decisions D-D (generation chain).
#
# Tries:
#   1) uuidgen -7 (util-linux ≥2.41.1; not available on macOS as of 2026-05).
#   2) python3 uuid.uuid7() (Python ≥3.13; available on operator dev box).
#   3) Pure-bash fallback from /dev/urandom + current Unix ms.
#
# Output: single UUID v7 string on stdout, no trailing newline added beyond
#   the helper's own print.

set -eu

_uuid7_via_uuidgen() {
    uuidgen -7 2>/dev/null
}

_uuid7_via_python() {
    python3 -c 'import uuid; print(uuid.uuid7())' 2>/dev/null
}

_uuid7_via_urandom() {
    # Pure-bash + python3 helper for 64-bit math. Layout per RFC 9562:
    #   48 bits unix-ts-ms | 4 bits version (7) | 12 bits rand_a |
    #   2 bits variant (10) | 62 bits rand_b
    python3 - <<'PY' 2>/dev/null
import os, time
ms = int(time.time() * 1000) & ((1 << 48) - 1)
rand_a = int.from_bytes(os.urandom(2), 'big') & 0x0fff   # 12 bits
rand_b = int.from_bytes(os.urandom(8), 'big') & ((1 << 62) - 1)  # 62 bits
hi = (ms << 16) | (0x7 << 12) | rand_a   # 64 bits
lo = (0b10 << 62) | rand_b               # 64 bits
hex16 = f"{hi:016x}{lo:016x}"
print(f"{hex16[0:8]}-{hex16[8:12]}-{hex16[12:16]}-{hex16[16:20]}-{hex16[20:32]}")
PY
}

generate_uuid7() {
    local id
    id=$(_uuid7_via_uuidgen) || id=""
    [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
    id=$(_uuid7_via_python) || id=""
    [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
    id=$(_uuid7_via_urandom) || id=""
    [ -n "$id" ] && { printf '%s\n' "$id"; return 0; }
    printf '[uuid7-gen] no working UUID v7 generator (need util-linux uuidgen -7 or python3 ≥3.13 or python3 + /dev/urandom)\n' >&2
    return 1
}

# When sourced, expose only the function. When executed, print one UUID.
case "${BASH_SOURCE[0]:-$0}" in
    "$0") generate_uuid7 ;;
esac
