#!/usr/bin/env bash
# next-free-id.sh — Deterministic task-ID selection with auto-bump on collision.
#
# Usage:
#   next-free-id.sh <PREFIX> <DATARIM_ROOT>
#
# Returns (stdout):  the next free ID in the form PREFIX-NNNN
# On collision:      auto-bumps to next free, emits a warning to stderr
# Exit codes:        0 = OK; 1 = usage/validation error (incl. a ledger-less
#                    root — see the fail-closed guard below), or 4-digit space
#                    exhausted
#
# <DATARIM_ROOT> is the WORKSPACE root — the PARENT of datarim/ — never the
# datarim/ directory itself. A root carrying neither datarim/tasks.md nor
# datarim/backlog.md fails CLOSED instead of emitting PREFIX-0001.
#
# ─────────────────────────────────────────────────────────────────────────────
# ARCHITECTURE — two jobs, opposite biases, computed from DIFFERENT scans.
#
# This script answers two questions that look alike and are not:
#
#   1. CEILING — "how high has anyone counted?"  -> max + 1
#      Bias: STRICT. Only *structural* positions count, i.e. positions whose
#      form is fixed by the schema rather than by an author's prose: FILENAMES
#      under documentation/archive and datarim/, and line-leading index rows
#      (`- {ID} ...`) in tasks.md / backlog.md. A number lifted from free prose
#      or from an unconstrained name must never move the watermark.
#      Cost of a false positive: the allocator walks out of the 4-digit space
#      the entire framework assumes and silently forks the numbering.
#
#   2. COLLISION PROBE — "is THIS id free?"  -> is_claimed()
#      Bias: PERMISSIVE. Every surface counts, prose included, plus the
#      host-global surfaces a file scan cannot see: live tmux session names and
#      git worktree / branch names.
#      Cost of a false positive: one wasted ID.
#      Cost of a false negative: two agents holding the same ID.
#
# The ceiling errs LOW and the probe corrects it. The probe errs HIGH and
# nothing corrects it — so the probe must never be tightened. That asymmetry is
# the whole design; anchoring tracks the cost of being wrong, not the caller.
#
# (The same reasoning gives commands/dr-init.md Step 4 its *anchored* probe:
# that one drives a STOP and a 3-way operator prompt, so a false positive costs
# an operator interrupt and anchoring is correct there. Different cost, same
# rule.)
#
# Security: S1 strict mode, regex-validate prefix arg, quote all expansions,
# no eval, read-only probes only.

set -euo pipefail

# The framework's ID space is exactly four digits — archive globs, the dr-init
# Step-4 probe and the public-surface regexes are all fixed at four. A 5-digit
# ID is not merely ugly: it is INVISIBLE to those surfaces, so an allocator
# that emits one cannot see it on the next call and hands it out forever.
# Exhaustion therefore fails loudly rather than overflowing.
MAX_ID_NUM=9999

# ── reservation store (TUNE-0285 race-window hardening) ──────────────────────
#
# The three claim surfaces above only become visible once a session has written
# an artifact. Between ID selection and that first write there is a workspace-
# shared TOCTOU window (reflection-TUNE-0280 § 1): two parallel `/dr-init`
# sessions can both select the same free ID. To close it we ATOMICALLY reserve
# the selected ID via a `mkdir` mutex under `datarim/.id-reservations/{ID}`
# BEFORE this helper returns, so the reservation spans the whole
# helper → agent → first-write sequence. `mkdir` is atomic on every POSIX
# filesystem (incl. macOS APFS): of two concurrent sessions computing the same
# candidate, exactly one `mkdir` wins; the loser bumps.
#
# Reversibility (a hard requirement of the task):
#   1. TTL self-expiry — a marker older than DATARIM_ID_RESERVATION_TTL seconds
#      (default 1800 / 30 min) is STALE and reclaimable, so a crashed session
#      never permanently burns an ID.
#   2. Explicit release — `next-free-id.sh --release <ID> <DATARIM_ROOT>`.
#   3. Manual — `rm -rf datarim/.id-reservations/<ID>`.
#   4. Idempotent GC of stale markers runs at the start of every selection.
# The marker is advisory: once the real artifact claims the ID on a canonical
# surface, a lingering marker is harmless (the surface already blocks reuse).

RESERVATION_SUBDIR="datarim/.id-reservations"

# Test-only, opt-in diagnostic trace. Production behavior is unchanged unless
# the focused R01 test explicitly sets _D5_TUNE0285_TRACE=1 and passes FD 9.
_D5_TRACE_ENABLED=0
if [[ "${_D5_TUNE0285_TRACE:-}" == "1" ]]; then
    _D5_TRACE_ENABLED=1
fi
_D5_TRACE_SEQUENCE=0
_D5_TRACE_EVENTS=0
_D5_TRACE_EVENT_LIMIT=64
_D5_TRACE_CUTOFF=0
_D5_TRACE_START_NS=""
_D5_TRACE_NOW_NS="unknown"
_D5_TRACE_ROOT=""
_D5_TRACE_STORE=""
_D5_TRACE_ROOT_DEVINO="unknown"
_D5_TRACE_STORE_DEVINO="unknown"

_d5_trace_can_emit() {
    [[ "${_D5_TRACE_ENABLED:-0}" == "1" && "${_D5_TRACE_CUTOFF:-0}" == "0" ]] \
        && (( _D5_TRACE_EVENTS < _D5_TRACE_EVENT_LIMIT ))
}

# Soft sampling cutoff for trace-only probes. The monotonic-clock process used
# to check the boundary is itself in-flight work and may exceed five seconds;
# after it returns, no later probe is scheduled once the cutoff has elapsed.
_d5_trace_check_time() {
    _d5_trace_can_emit || return 1
    local now
    if ! now="$(perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
        -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000000000' 2>/dev/null)" \
        || ! [[ "$now" =~ ^[0-9]+$ ]]; then
        _D5_TRACE_CUTOFF=1
        _D5_TRACE_NOW_NS="unknown"
        return 1
    fi
    if [[ -z "$_D5_TRACE_START_NS" ]]; then
        _D5_TRACE_START_NS="$now"
    elif (( now - _D5_TRACE_START_NS >= 5000000000 )); then
        _D5_TRACE_CUTOFF=1
        _D5_TRACE_NOW_NS="unknown"
        return 1
    fi
    _D5_TRACE_NOW_NS="$now"
    return 0
}

_d5_trace_identity() {
    _D5_TRACE_IDENTITY_RESULT="unknown"
    _d5_trace_can_emit || return 0
    local path="$1" identity
    _d5_trace_check_time || return 0
    if identity="$(stat -Lc '%d:%i' -- "$path" 2>/dev/null)"; then
        :
    else
        if _d5_trace_check_time; then
            if identity="$(stat -f '%d:%i' "$path" 2>/dev/null)"; then
                :
            else
                identity="unknown"
            fi
        else
            identity="unknown"
        fi
    fi
    [[ "$identity" =~ ^[0-9]+:[0-9]+$ ]] && _D5_TRACE_IDENTITY_RESULT="$identity"
    return 0
}

_d5_trace_event() {
    _d5_trace_can_emit || return 0
    local event="$1" candidate="${2:-unknown}" marker_devino="unknown"
    local epoch="${3:-unknown}" age="${4:-unknown}" ttl="${5:-unknown}"
    local operation_rc="${6:-unknown}" decision="${7:-none}" marker line mono_ns

    case "$event" in
        reserve_dir_create|gc_age|gc_remove|gc_remove_result|claim_probe|candidate_probe|mkdir_attempt|initial_mkdir|stale_age|stale_predicate|reclaim_decision|reclaim_remove|reclaim_remove_result|reclaim_mkdir|stamp_epoch|stamp_pid|publish_marker|stdout_attempt|release_remove|release_remove_result)
            ;;
        *) event="unknown" ;;
    esac
    if [[ ! "$candidate" =~ ^TUNE-[0-9]{4}$ ]]; then candidate="unknown"; fi
    if [[ ! "$epoch" =~ ^[0-9]+$ ]]; then epoch="unknown"; fi
    if [[ ! "$age" =~ ^-?[0-9]+$ ]]; then age="unknown"; fi
    if [[ ! "$ttl" =~ ^[0-9]+$ ]]; then ttl="unknown"; fi
    if [[ ! "$operation_rc" =~ ^[0-9]+$ ]]; then operation_rc="unknown"; fi
    case "$decision" in
        none|created|fresh|stale|absent|lost|claimed_names|claimed_live|claimed_tasks|claimed_backlog|claimed_init_lock|claimed_reservation|unclaimed|published|attempt|failed|released|succeeded|unknown)
            ;;
        *) decision="unknown" ;;
    esac

    if [[ "$candidate" != "unknown" ]]; then
        marker="${_D5_TRACE_STORE}/${candidate}"
        _d5_trace_check_time || return 0
        if [[ -d "$marker" ]]; then
            _d5_trace_identity "$marker"
            marker_devino="$_D5_TRACE_IDENTITY_RESULT"
        fi
    fi
    # The time-check clock call is the final diagnostic-only probe for this
    # event and supplies its timestamp. It may itself run beyond the soft cap.
    _d5_trace_check_time || return 0
    mono_ns="$_D5_TRACE_NOW_NS"
    _D5_TRACE_SEQUENCE=$((_D5_TRACE_SEQUENCE + 1))
    _D5_TRACE_EVENTS=$((_D5_TRACE_EVENTS + 1))
    printf -v line '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' \
        "$_D5_TRACE_SEQUENCE" "$$" "$event" "$candidate" \
        "$_D5_TRACE_ROOT_DEVINO" "$_D5_TRACE_STORE_DEVINO" "$marker_devino" \
        "$epoch" "$age" "$ttl" "$operation_rc" "$decision" "$mono_ns"
    if (( ${#line} + 1 > 512 )); then return 0; fi
    if printf '%s\n' "$line" 2>/dev/null >&9; then :; else :; fi
    return 0
}

# --release mode: `next-free-id.sh --release <ID> <DATARIM_ROOT>`
if [[ "${1:-}" == "--release" ]]; then
    if [[ $# -lt 3 ]]; then
        echo "Usage: next-free-id.sh --release <ID> <DATARIM_ROOT>" >&2
        exit 1
    fi
    REL_ID="$2"
    REL_ROOT="$3"
    # Strict-validate the ID before any filesystem op (Security S1 — no traversal)
    if ! [[ "$REL_ID" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4,}$ ]]; then
        echo "ERROR: invalid ID '${REL_ID}' for --release — expected PREFIX-NNNN" >&2
        exit 1
    fi
    if [[ ! -d "$REL_ROOT" ]]; then
        echo "ERROR: DATARIM_ROOT '${REL_ROOT}' does not exist or is not a directory" >&2
        exit 1
    fi
    if [[ "$_D5_TRACE_ENABLED" == "1" ]]; then
        _D5_TRACE_ROOT="$REL_ROOT"
        _D5_TRACE_STORE="${REL_ROOT}/${RESERVATION_SUBDIR}"
        if _d5_trace_can_emit; then
            _d5_trace_identity "$REL_ROOT"
            _D5_TRACE_ROOT_DEVINO="$_D5_TRACE_IDENTITY_RESULT"
            _d5_trace_identity "$_D5_TRACE_STORE"
            _D5_TRACE_STORE_DEVINO="$_D5_TRACE_IDENTITY_RESULT"
            _d5_trace_event release_remove "$REL_ID" unknown unknown unknown unknown attempt
        fi
        if _d5_trace_can_emit; then
            if rm -rf "${REL_ROOT:?}/${RESERVATION_SUBDIR}/${REL_ID:?}" 2>/dev/null; then
                _D5_TRACE_RELEASE_RC=0
                _D5_TRACE_RELEASE_DECISION=succeeded
            else
                _D5_TRACE_RELEASE_RC=$?
                _D5_TRACE_RELEASE_DECISION=unknown
            fi
            if _d5_trace_can_emit; then
                _d5_trace_event release_remove_result "$REL_ID" unknown unknown unknown "$_D5_TRACE_RELEASE_RC" "$_D5_TRACE_RELEASE_DECISION"
            fi
        else
            rm -rf "${REL_ROOT:?}/${RESERVATION_SUBDIR}/${REL_ID:?}" 2>/dev/null || true
        fi
    else
        rm -rf "${REL_ROOT:?}/${RESERVATION_SUBDIR}/${REL_ID:?}" 2>/dev/null || true
    fi
    exit 0
fi

# ── argument validation ──────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    echo "Usage: next-free-id.sh <PREFIX> <DATARIM_ROOT>" >&2
    exit 1
fi

PREFIX="$1"
DATARIM_ROOT="$2"
if [[ "$_D5_TRACE_ENABLED" == "1" ]]; then
    _D5_TRACE_ROOT="$DATARIM_ROOT"
    _D5_TRACE_STORE="${DATARIM_ROOT}/${RESERVATION_SUBDIR}"
fi

# Regex-validate prefix: starts uppercase, then 1–9 uppercase letters/digits (Security S1)
if ! [[ "$PREFIX" =~ ^[A-Z][A-Z0-9]{1,9}$ ]]; then
    echo "ERROR: invalid prefix '${PREFIX}' — must start with an uppercase letter and contain 2–10 uppercase letters/digits" >&2
    exit 1
fi

if [[ ! -d "$DATARIM_ROOT" ]]; then
    echo "ERROR: DATARIM_ROOT '${DATARIM_ROOT}' does not exist or is not a directory" >&2
    exit 1
fi

# ── ledger-presence guard (fail CLOSED on a ledger-less root) ────────────────
#
# DATARIM_ROOT is the WORKSPACE root — the PARENT of datarim/ — so the ledgers
# live at ${DATARIM_ROOT}/datarim/{tasks.md,backlog.md}. A root that carries
# neither file cannot answer "how high has anyone counted?": the ceiling scan
# sees nothing and the allocator would emit a plausible-looking ${PREFIX}-0001
# with exit 0 — an ID that may already be claimed hundreds of times over in the
# workspace the caller MEANT to point at. That silent-and-maximally-destructive
# shape is worse than any loud failure, so a ledger-less root is a usage error.
#
# The most tempting misuse is handing over the datarim/ directory itself (the
# parameter name invites it), so that shape gets its own diagnostic.
if [[ ! -f "${DATARIM_ROOT}/datarim/tasks.md" && ! -f "${DATARIM_ROOT}/datarim/backlog.md" ]]; then
    echo "ERROR: no task ledger found under '${DATARIM_ROOT}/datarim/'" >&2
    echo "       Expected layout: DATARIM_ROOT is the WORKSPACE ROOT (the parent of datarim/)," >&2
    echo "       carrying datarim/tasks.md and/or datarim/backlog.md." >&2
    if [[ -f "${DATARIM_ROOT}/tasks.md" || -f "${DATARIM_ROOT}/backlog.md" ]]; then
        echo "       Hint: '${DATARIM_ROOT}' looks like the datarim/ directory itself —" >&2
        echo "       pass its PARENT directory instead." >&2
    fi
    echo "       Refusing to allocate against a ledger-less root: the result would be a" >&2
    echo "       plausible ${PREFIX}-0001 that ignores every existing claim." >&2
    exit 1
fi

# ── reservation config + helpers (TUNE-0285) ─────────────────────────────────

RESERVE_DIR="${DATARIM_ROOT}/${RESERVATION_SUBDIR}"

# TTL after which an untouched reservation is considered stale (crashed session)
RESERVATION_TTL="${DATARIM_ID_RESERVATION_TTL:-1800}"
if ! [[ "$RESERVATION_TTL" =~ ^[0-9]+$ ]]; then
    RESERVATION_TTL=1800
else
    # TTL is decimal seconds. Pin the radix so accepted leading-zero spellings
    # such as 08 and 09 do not trigger Bash's octal parsing in later arithmetic.
    RESERVATION_TTL=$((10#$RESERVATION_TTL))
fi

# Age of a reservation marker in seconds. A missing/unreadable epoch is treated
# as age 0 (fresh) — this protects the narrow window where a concurrent winner
# has mkdir'd the marker but not yet written its epoch; such a marker is never
# auto-stolen (it clears via TTL once its epoch lands, or via --release).
_reservation_age() {
    local marker="$1" now epoch
    now="$(date +%s)"
    epoch="$(cat "${marker}/epoch" 2>/dev/null)" || epoch=""
    if ! [[ "$epoch" =~ ^[0-9]+$ ]]; then
        if [[ "${2:-}" == "trace" ]]; then
            printf '0\tunknown\n'
        else
            echo 0
        fi
        return 0
    fi
    if [[ "${2:-}" == "trace" ]]; then
        printf '%s\t%s\n' "$(( now - epoch ))" "$epoch"
    else
        echo $(( now - epoch ))
    fi
}

# A reservation is "fresh" (counts as claimed) when its marker exists and its
# age is within the TTL.
_reservation_is_fresh() {
    local id="$1"
    local marker="${RESERVE_DIR}/${id}"
    if _d5_trace_can_emit; then
        local age_info age epoch predicate_rc decision
        if [[ ! -d "$marker" ]]; then
            _d5_trace_event stale_predicate "$id" unknown unknown "$RESERVATION_TTL" 1 absent
            return 1
        fi
        age_info="$(_reservation_age "$marker" trace)"
        age="${age_info%%$'\t'*}"
        epoch="${age_info#*$'\t'}"
        if (( age <= RESERVATION_TTL )); then
            predicate_rc=0
            decision="fresh"
        else
            predicate_rc=1
            decision="stale"
        fi
        if _d5_trace_can_emit; then
            _d5_trace_event stale_age "$id" "$epoch" "$age" "$RESERVATION_TTL" unknown "$decision"
        fi
        if _d5_trace_can_emit; then
            _d5_trace_event stale_predicate "$id" "$epoch" "$age" "$RESERVATION_TTL" "$predicate_rc" "$decision"
        fi
        return "$predicate_rc"
    fi
    [[ -d "$marker" ]] || return 1
    (( $(_reservation_age "$marker") <= RESERVATION_TTL ))
}

# Idempotent sweep: reclaim (rmdir) any reservation older than the TTL.
_reservation_gc() {
    [[ -d "$RESERVE_DIR" ]] || return 0
    local marker
    for marker in "$RESERVE_DIR"/*/; do
        [[ -d "$marker" ]] || continue
        if _d5_trace_can_emit; then
            local id age_info age epoch
            id="${marker%/}"
            id="${id##*/}"
            age_info="$(_reservation_age "$marker" trace)"
            age="${age_info%%$'\t'*}"
            epoch="${age_info#*$'\t'}"
            if (( age > RESERVATION_TTL )); then
                if _d5_trace_can_emit; then
                    _d5_trace_event gc_age "$id" "$epoch" "$age" "$RESERVATION_TTL" unknown stale
                fi
                if _d5_trace_can_emit; then
                    _d5_trace_event gc_remove "$id" "$epoch" "$age" "$RESERVATION_TTL" unknown attempt
                fi
                if _d5_trace_can_emit; then
                    if rm -rf "$marker" 2>/dev/null; then
                        _D5_TRACE_GC_RM_RC=0
                        _D5_TRACE_GC_RM_DECISION=succeeded
                    else
                        _D5_TRACE_GC_RM_RC=$?
                        _D5_TRACE_GC_RM_DECISION=unknown
                    fi
                    if _d5_trace_can_emit; then
                        _d5_trace_event gc_remove_result "$id" "$epoch" "$age" "$RESERVATION_TTL" "$_D5_TRACE_GC_RM_RC" "$_D5_TRACE_GC_RM_DECISION"
                    fi
                else
                    rm -rf "$marker" 2>/dev/null || true
                fi
            else
                if _d5_trace_can_emit; then
                    _d5_trace_event gc_age "$id" "$epoch" "$age" "$RESERVATION_TTL" unknown fresh
                fi
            fi
        elif (( $(_reservation_age "$marker") > RESERVATION_TTL )); then
            rm -rf "$marker" 2>/dev/null || true
        fi
    done
}

# Atomically reserve an ID. Returns 0 on success (marker created + stamped),
# 1 when a FRESH reservation already holds it (lost the race → caller bumps).
# A stale marker is reclaimed and re-taken.
_reservation_try() {
    local id="$1"
    local marker="${RESERVE_DIR}/${id}"
    local initial_mkdir_rc reclaim_mkdir_rc
    if _d5_trace_can_emit; then
        _d5_trace_event mkdir_attempt "$id" unknown unknown "$RESERVATION_TTL" unknown attempt
    fi
    if mkdir "$marker" 2>/dev/null; then
        if _d5_trace_can_emit; then
            _d5_trace_event initial_mkdir "$id" unknown unknown "$RESERVATION_TTL" 0 created
        fi
        if _d5_trace_can_emit; then
            if date +%s > "${marker}/epoch" 2>/dev/null; then
                _D5_TRACE_EPOCH_RC=0
            else
                _D5_TRACE_EPOCH_RC=$?
            fi
            if _d5_trace_can_emit; then
                _d5_trace_event stamp_epoch "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_EPOCH_RC" attempt
            fi
        else
            date +%s > "${marker}/epoch" 2>/dev/null || true
        fi
        if _d5_trace_can_emit; then
            if echo "$$" > "${marker}/pid" 2>/dev/null; then
                _D5_TRACE_PID_RC=0
            else
                # shellcheck disable=SC2320 # Preserve the suppressed echo status for the trace.
                _D5_TRACE_PID_RC=$?
            fi
            if _d5_trace_can_emit; then
                _d5_trace_event stamp_pid "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_PID_RC" attempt
            fi
        else
            echo "$$" > "${marker}/pid" 2>/dev/null || true
        fi
        if _d5_trace_can_emit; then
            if (( _D5_TRACE_EPOCH_RC == 0 && _D5_TRACE_PID_RC == 0 )); then
                _D5_TRACE_PUBLISH_RC=0
                _D5_TRACE_PUBLISH_DECISION=published
            else
                _D5_TRACE_PUBLISH_RC=unknown
                _D5_TRACE_PUBLISH_DECISION=unknown
            fi
            _d5_trace_event publish_marker "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_PUBLISH_RC" "$_D5_TRACE_PUBLISH_DECISION"
        fi
        return 0
    else
        initial_mkdir_rc=$?
        if _d5_trace_can_emit; then
            _d5_trace_event initial_mkdir "$id" unknown unknown "$RESERVATION_TTL" "$initial_mkdir_rc" unknown
        fi
    fi

    # Marker already exists — reclaim only if stale, else we lost the race.
    if _d5_trace_can_emit; then
        if _reservation_is_fresh "$id"; then
            if _d5_trace_can_emit; then
                _d5_trace_event reclaim_decision "$id" unknown unknown "$RESERVATION_TTL" 0 fresh
            fi
            return 1
        fi
        if _d5_trace_can_emit; then
            _d5_trace_event reclaim_decision "$id" unknown unknown "$RESERVATION_TTL" 1 unknown
        fi
        if _d5_trace_can_emit; then
            _d5_trace_event reclaim_remove "$id" unknown unknown "$RESERVATION_TTL" unknown attempt
        fi
        if _d5_trace_can_emit; then
            if rm -rf "$marker" 2>/dev/null; then
                _D5_TRACE_RECLAIM_RM_RC=0
                _D5_TRACE_RECLAIM_RM_DECISION=succeeded
            else
                _D5_TRACE_RECLAIM_RM_RC=$?
                _D5_TRACE_RECLAIM_RM_DECISION=unknown
            fi
            if _d5_trace_can_emit; then
                _d5_trace_event reclaim_remove_result "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_RECLAIM_RM_RC" "$_D5_TRACE_RECLAIM_RM_DECISION"
            fi
        else
            rm -rf "$marker" 2>/dev/null || true
        fi
        if _d5_trace_can_emit; then
            _d5_trace_event mkdir_attempt "$id" unknown unknown "$RESERVATION_TTL" unknown attempt
        fi
        if mkdir "$marker" 2>/dev/null; then
            if _d5_trace_can_emit; then
                _d5_trace_event reclaim_mkdir "$id" unknown unknown "$RESERVATION_TTL" 0 created
            fi
            if _d5_trace_can_emit; then
                if date +%s > "${marker}/epoch" 2>/dev/null; then
                    _D5_TRACE_EPOCH_RC=0
                else
                    _D5_TRACE_EPOCH_RC=$?
                fi
                if _d5_trace_can_emit; then
                    _d5_trace_event stamp_epoch "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_EPOCH_RC" attempt
                fi
            else
                date +%s > "${marker}/epoch" 2>/dev/null || true
            fi
            if _d5_trace_can_emit; then
                if echo "$$" > "${marker}/pid" 2>/dev/null; then
                    _D5_TRACE_PID_RC=0
                else
                    # shellcheck disable=SC2320 # Preserve the suppressed echo status for the trace.
                    _D5_TRACE_PID_RC=$?
                fi
                if _d5_trace_can_emit; then
                    _d5_trace_event stamp_pid "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_PID_RC" attempt
                fi
            else
                echo "$$" > "${marker}/pid" 2>/dev/null || true
            fi
            if _d5_trace_can_emit; then
                if (( _D5_TRACE_EPOCH_RC == 0 && _D5_TRACE_PID_RC == 0 )); then
                    _D5_TRACE_PUBLISH_RC=0
                    _D5_TRACE_PUBLISH_DECISION=published
                else
                    _D5_TRACE_PUBLISH_RC=unknown
                    _D5_TRACE_PUBLISH_DECISION=unknown
                fi
                _d5_trace_event publish_marker "$id" unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_PUBLISH_RC" "$_D5_TRACE_PUBLISH_DECISION"
            fi
            return 0
        else
            reclaim_mkdir_rc=$?
            if _d5_trace_can_emit; then
                _d5_trace_event reclaim_mkdir "$id" unknown unknown "$RESERVATION_TTL" "$reclaim_mkdir_rc" unknown
            fi
        fi
    else
        if ! _reservation_is_fresh "$id"; then
            rm -rf "$marker" 2>/dev/null || true
            if mkdir "$marker" 2>/dev/null; then
                date +%s > "${marker}/epoch" 2>/dev/null || true
                echo "$$" > "${marker}/pid" 2>/dev/null || true
                return 0
            fi
        fi
    fi
    return 1
}

# ── reservation GC runs BEFORE the surface scan ──────────────────────────────
# Reservation markers live under datarim/ and are therefore picked up by the
# name sweep below. Sweeping stale ones first keeps an abandoned marker from
# inflating the ceiling; a FRESH one is a real claim and should raise it.

if [[ "$_D5_TRACE_ENABLED" == "1" ]]; then
    if _d5_trace_can_emit; then
        if mkdir -p "$RESERVE_DIR" 2>/dev/null; then
            _D5_TRACE_RESERVE_DIR_RC=0
            _D5_TRACE_RESERVE_DIR_DECISION=succeeded
        else
            _D5_TRACE_RESERVE_DIR_RC=$?
            _D5_TRACE_RESERVE_DIR_DECISION=unknown
        fi
        if _d5_trace_can_emit; then
            _d5_trace_identity "$DATARIM_ROOT"
            _D5_TRACE_ROOT_DEVINO="$_D5_TRACE_IDENTITY_RESULT"
            _d5_trace_identity "$RESERVE_DIR"
            _D5_TRACE_STORE_DEVINO="$_D5_TRACE_IDENTITY_RESULT"
            _d5_trace_event reserve_dir_create unknown unknown unknown "$RESERVATION_TTL" "$_D5_TRACE_RESERVE_DIR_RC" "$_D5_TRACE_RESERVE_DIR_DECISION"
        fi
    else
        mkdir -p "$RESERVE_DIR" 2>/dev/null || true
    fi
else
    mkdir -p "$RESERVE_DIR" 2>/dev/null || true
fi
_reservation_gc

TASKS_FILE="${DATARIM_ROOT}/datarim/tasks.md"
BACKLOG_FILE="${DATARIM_ROOT}/datarim/backlog.md"
ARCHIVE_DIR="${DATARIM_ROOT}/documentation/archive"
DATARIM_DIR="${DATARIM_ROOT}/datarim"

WORKDIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORKDIR}'" EXIT

NAMES_FILE="${WORKDIR}/names"     # filename claim surface (structural)
ROWS_FILE="${WORKDIR}/rows"       # line-leading index rows (structural)
LIVE_FILE="${WORKDIR}/live"       # tmux / git names (probe-only)
: > "$NAMES_FILE"
: > "$ROWS_FILE"
: > "$LIVE_FILE"

# ── token extraction ─────────────────────────────────────────────────────────
#
# Reads text on stdin, writes the numeric part of every well-formed
# `PREFIX-NNNN` token to stdout, one per line.
#
# Both boundaries are enforced:
#   left  — the prefix must not be the tail of a longer word (`XPREFIX-0001`);
#   right — the digit run is captured GREEDILY and then required to be exactly
#           four long, so `PREFIX-10000` yields nothing at all.
#
# The greedy-then-filter shape is the load-bearing part. A plain
# `grep -o "PREFIX-[0-9]\{4\}"` matches the *first four* digits of a 5-digit
# literal, reporting `PREFIX-1000` for `PREFIX-10000` — a number nobody ever
# claimed. That is how a documentation fixture reached the live watermark.
extract_nums() {
    grep -oE "(^|[^A-Za-z0-9])${PREFIX}-[0-9]+" 2>/dev/null \
        | grep -oE '[0-9]+$' 2>/dev/null \
        | grep -xE '[0-9]{4}' 2>/dev/null || true
}

# ── surface 1 (ceiling + probe): FILENAMES ───────────────────────────────────
#
# A filename carrying an ID is a structural claim: `archive-{ID}.md`,
# `{ID}-task-description.md`, `PRD-{ID}.md`, `plan-{ID}.md`, `{ID}.mode`,
# `{ID}.snapshot.md`. Bodies are deliberately NOT read — archived documents
# cite illustrative IDs in their prose, and a content-grep scoops those up.
#
# Reading datarim/ as a whole (not an enumerated list of subdirectories) is
# intentional: an epic decomposition that writes task-description files but no
# tasks.md rows used to be completely invisible, which produced a 12-ID
# collision window in the field.
for dir in "$ARCHIVE_DIR" "$DATARIM_DIR"; do
    [[ -d "$dir" ]] || continue
    find "$dir" 2>/dev/null | sed 's|.*/||' >> "$NAMES_FILE" || true
done

# ── surface 2 (ceiling + probe): line-leading index rows ─────────────────────
#
# The thin one-liner schema puts a claim at the start of its own line:
#   `- {ID} · status · P{n} · L{n} · description`
# Everything after the first token is an author's prose and may legitimately
# cite any ID at all — supersession notes, renumber history, worked examples,
# test-fixture literals. Anchoring to `^- {ID}` is what separates the two.
for f in "$TASKS_FILE" "$BACKLOG_FILE"; do
    [[ -f "$f" ]] || continue
    grep -oE "^[-*+][[:space:]]+${PREFIX}-[0-9]+" "$f" 2>/dev/null >> "$ROWS_FILE" || true
done

# ── surface 3 (PROBE ONLY): live host claims ─────────────────────────────────
#
# A batch-spawned orchestrator reserves its ID in the tmux SESSION NAME
# (`dr-<space>-<TASK-ID>`) and in its worktree/branch name minutes before any
# file records the claim. A file-only allocator hands the same ID to the next
# caller, which is how two agents ended up on one ID and a live session was
# killed as a presumed leftover.
#
# These names are free-form: stale (a session may still carry a pre-renumber
# name), abbreviated, or typo'd. That makes a hit good enough to REFUSE an ID
# and not good enough to define the watermark — so they feed is_claimed() and
# never MAX_NUM. Trusting them for the ceiling would rebuild the fixture-poison
# defect on a new surface.
#
# Test seam: when DATARIM_ID_TMUX_SESSIONS / DATARIM_ID_GIT_REFS are set — even
# to empty — the supplied newline-separated list replaces the live probe, so a
# spec is hermetic on a host running dozens of unrelated sessions.
if [[ -n "${DATARIM_ID_TMUX_SESSIONS+set}" ]]; then
    printf '%s\n' "$DATARIM_ID_TMUX_SESSIONS" >> "$LIVE_FILE"
elif command -v tmux >/dev/null 2>&1; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null >> "$LIVE_FILE" || true
fi

if [[ -n "${DATARIM_ID_GIT_REFS+set}" ]]; then
    printf '%s\n' "$DATARIM_ID_GIT_REFS" >> "$LIVE_FILE"
elif command -v git >/dev/null 2>&1; then
    git -C "$DATARIM_ROOT" worktree list --porcelain 2>/dev/null >> "$LIVE_FILE" || true
    git -C "$DATARIM_ROOT" branch -a --format='%(refname:short)' 2>/dev/null >> "$LIVE_FILE" || true
fi

# ── surface 3b (PROBE ONLY): task FILENAMES inside every worktree ────────────
#
# Surface 1 sweeps datarim/ and documentation/archive/ — but only under
# DATARIM_ROOT, i.e. the checkout the caller happens to be standing in. A
# sibling worktree that already wrote `datarim/tasks/{ID}-task-description.md`
# is invisible to it, and that is not hypothetical: two consecutive IDs were
# handed out while exactly those files sat in sibling checkouts, with zero
# presence in tasks.md, backlog.md, the archive or any commit.
#
# Filenames only, never bodies — same rule as surface 1, and for the same
# reason: task documents cite illustrative IDs in prose.
#
# PROBE ONLY. A foreign checkout may sit on a stale branch, a reverted
# experiment or a fixture tree, so a hit is good enough to REFUSE an ID and not
# good enough to define the watermark. Feeding it to MAX_NUM would rebuild the
# fixture-poison defect on a new surface.
#
# Test seam: DATARIM_ID_WORKTREE_PATHS (newline-separated) replaces the live
# `git worktree list`, so a spec is hermetic on a host with dozens of trees.
_scan_worktree_task_names() {
    local wt="$1"
    [[ -n "$wt" && -d "$wt" ]] || return 0
    find "$wt/datarim/tasks" -maxdepth 1 2>/dev/null | sed 's|.*/||' >> "$LIVE_FILE" || true
}

if [[ -n "${DATARIM_ID_WORKTREE_PATHS+set}" ]]; then
    while IFS= read -r _wt; do
        _scan_worktree_task_names "$_wt"
    done <<< "$DATARIM_ID_WORKTREE_PATHS"
elif command -v git >/dev/null 2>&1; then
    while IFS= read -r _wt; do
        _scan_worktree_task_names "$_wt"
    done < <(git -C "$DATARIM_ROOT" worktree list --porcelain 2>/dev/null \
             | awk '/^worktree /{print substr($0, 10)}')
fi

# ── surface 3c (PROBE ONLY): commit subjects on EVERY ref ────────────────────
#
# A claim can exist as nothing but a commit on a branch that is not checked
# out. `git branch -a` above catches the case where the ID is in the branch
# NAME; it says nothing about a conventional-commit subject like
# `feat(PREFIX-NNNN): ...` on an otherwise unremarkable branch name.
#
# PROBE ONLY, emphatically. Commit subjects are free prose and routinely cite
# IDs they do not claim — a renumber commit names both the old and the new ID.
# Refusing both is the conservative and correct outcome for a mutex: the cost
# is skipping an ID, which is recoverable, against handing out a live one,
# which is not.
#
# Test seam: DATARIM_ID_GIT_LOG (newline-separated subjects) replaces the live
# `git log`.
if [[ -n "${DATARIM_ID_GIT_LOG+set}" ]]; then
    printf '%s\n' "$DATARIM_ID_GIT_LOG" >> "$LIVE_FILE"
elif command -v git >/dev/null 2>&1; then
    git -C "$DATARIM_ROOT" log --all --format='%s' 2>/dev/null >> "$LIVE_FILE" || true
fi

# ── surface 4 (ceiling + probe): in-flight init-lock markers ─────────────────
#
# `datarim/.locks/<ID>.init-lock` is the mkdir-based atomic claim a concurrent
# /dr-init takes between choosing an ID and writing its first artefact. That is
# the narrowest race window in the system, and nothing in surfaces 1–3 can see
# it. Any present marker counts — conservatively, because a stale one only
# skips an ID and is never reused. See dr-init-id-lock.sh.
#
# The generic datarim/ name sweep above already collects these markers (they
# are directories under datarim/). The explicit block stays anyway: a
# safety-critical guarantee should not rest on being an incidental side effect
# of a broader glob, where a later narrowing of that glob would silently drop
# it.
LOCK_DIR="${DATARIM_ROOT}/datarim/.locks"
if [[ -d "$LOCK_DIR" ]]; then
    for _m in "$LOCK_DIR/${PREFIX}-"[0-9][0-9][0-9][0-9].init-lock; do
        [[ -d "$_m" ]] || continue
        printf '%s\n' "${_m##*/}" >> "$NAMES_FILE"
    done
fi

# ── compute the ceiling ──────────────────────────────────────────────────────

MAX_NUM=0
while IFS= read -r num; do
    # Force base-10. A bare `(( 0058 ))` is parsed as OCTAL, so any zero-padded
    # digit >= 8 (0058, 0079, 0090) errors and is silently skipped, corrupting
    # the max. `10#` pins base-10 for any number of leading zeros.
    if (( 10#$num > MAX_NUM )); then
        MAX_NUM=$(( 10#$num ))
    fi
done < <(cat "$NAMES_FILE" "$ROWS_FILE" | extract_nums)

# ── collision probe ──────────────────────────────────────────────────────────
#
# Maximally inclusive by design — see the header. Substring matching, no
# anchors, case-insensitive against the name surfaces (branch names are
# lowercase by convention; the ID they carry is not).

is_claimed() {
    local id="$1"

    # Structural surfaces, matched loosely here on purpose.
    if grep -qiF -- "$id" "$NAMES_FILE" 2>/dev/null; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_names; fi
        return 0
    fi
    if grep -qiF -- "$id" "$LIVE_FILE" 2>/dev/null; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_live; fi
        return 0
    fi

    # Full text of the index files: a prose-only mention ("renumbered from
    # {ID}") is still somebody's claim. It must not lift the ceiling, and it
    # must not be handed out either.
    if [[ -f "$TASKS_FILE" ]] && grep -qF -- "$id" "$TASKS_FILE" 2>/dev/null; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_tasks; fi
        return 0
    fi
    if [[ -f "$BACKLOG_FILE" ]] && grep -qF -- "$id" "$BACKLOG_FILE" 2>/dev/null; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_backlog; fi
        return 0
    fi

    # An in-flight init-lock marker is an atomic claim by a concurrent session
    # that has not yet written tasks.md.
    if [[ -d "${DATARIM_ROOT}/datarim/.locks/${id}.init-lock" ]]; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_init_lock; fi
        return 0
    fi

    # A FRESH reservation marker held by a parallel session in its read->write
    # window counts as claimed.
    if _reservation_is_fresh "$id"; then
        if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 0 claimed_reservation; fi
        return 0
    fi

    if _d5_trace_can_emit; then _d5_trace_event claim_probe "$id" unknown unknown "$RESERVATION_TTL" 1 unclaimed; fi

    return 1
}

# ── candidate = max + 1, then atomic select-and-reserve ──────────────────────

CANDIDATE=$(( MAX_NUM + 1 ))

exhausted() {
    echo "ERROR: ${PREFIX} has exhausted the 4-digit ID space (${PREFIX}-${MAX_ID_NUM})." >&2
    echo "       Refusing to emit an out-of-range ID — the archive, dr-init probe and" >&2
    echo "       public-surface surfaces are all fixed at four digits and would not see it." >&2
    exit 1
}

if (( CANDIDATE > MAX_ID_NUM )); then
    exhausted
fi

# GC ran above. Walk candidates: skip any claimed on a real surface OR by a
# fresh reservation, and atomically reserve the first free one. The mkdir mutex
# inside _reservation_try is the true guarantee — a candidate that slips past
# is_claimed but loses the concurrent mkdir causes a bump, so two simultaneous
# sessions can never emit the same ID.

CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
warned=0
_bump() {
    CANDIDATE=$(( CANDIDATE + 1 ))
    if (( CANDIDATE > MAX_ID_NUM )); then
        exhausted
    fi
    CANDIDATE_ID="$(printf '%s-%04d' "$PREFIX" "$CANDIDATE")"
}

while : ; do
    if is_claimed "$CANDIDATE_ID"; then
        if _d5_trace_can_emit; then _d5_trace_event candidate_probe "$CANDIDATE_ID" unknown unknown "$RESERVATION_TTL" 0 lost; fi
        if (( warned == 0 )); then
            echo "WARNING: ID ${CANDIDATE_ID} already claimed (parallel-session race) — auto-bumping to next free ID" >&2
            warned=1
        fi
        _bump
        continue
    fi
    if _d5_trace_can_emit; then _d5_trace_event candidate_probe "$CANDIDATE_ID" unknown unknown "$RESERVATION_TTL" 0 unclaimed; fi
    if _reservation_try "$CANDIDATE_ID"; then
        break
    fi
    # Lost the atomic mkdir race to a parallel session — bump.
    if (( warned == 0 )); then
        echo "WARNING: ID ${CANDIDATE_ID} reserved by a parallel session — auto-bumping to next free ID" >&2
        warned=1
    fi
    _bump
done

# ── defensive invariant ──────────────────────────────────────────────────────
# The emitted wording is a contract surface consumed by /dr-init and /dr-quick.
# Bind it to the state it claims: exactly four digits, and genuinely unclaimed.
if ! [[ "$CANDIDATE_ID" =~ ^${PREFIX}-[0-9]{4}$ ]]; then
    echo "ERROR: internal invariant violated: emitted ID '${CANDIDATE_ID}' is not ${PREFIX}-NNNN" >&2
    exit 2
fi

# ── emit the chosen ID ────────────────────────────────────────────────────────

if _d5_trace_can_emit; then _d5_trace_event stdout_attempt "$CANDIDATE_ID" unknown unknown "$RESERVATION_TTL" unknown attempt; fi
printf '%s\n' "$CANDIDATE_ID"
