#!/usr/bin/env bash
# doc-fanout-lint.sh — N-way consumer-surface drift detector
#
# Detects asymmetric drift between a canonical artefact directory
# (e.g. commands/dr-*.md) and N consumer surfaces (CLAUDE.md mention,
# README.md mention, docs/ table row, sister-site PHP file existence,
# count fields).
#
# Driven by .doc-fanout.yml v1 (block-style YAML, depth <=3).
#
# Three rule kinds:
#   grep_in_file    — pattern (with {name}) must appear in `file`
#   file_must_exist — `path` (with {name}) must resolve to existing file
#   count_match     — len(glob) must equal first capture group of pattern
#                     in consumer_file
#
# Exit codes:
#   0  clean (no errors; warnings ok unless --strict)
#   1  errors found (or warnings with --strict)
#   2  usage / config / path-traversal / fatal parse error
#
# Security: S1 hardened. No eval, no curl|bash, regex-validated config-
# sourced strings, grep -F for literal patterns, path-traversal guard.

set -u

print_usage() {
    cat >&2 <<'EOF'
Usage:
  doc-fanout-lint.sh [options]

Options:
  --root <DIR>            Tree under which artefacts/consumers resolve.
                          Default: $PWD.
  --config <PATH>         Explicit config. Else: $DOC_FANOUT_CONFIG
                          → <root>/.doc-fanout.yml → $PWD/.doc-fanout.yml.
  --baseline <PATH>       Explicit ignore file. Else: <root>/.docfanoutignore.
  --no-baseline           Paranoid mode (no baseline applied).
  --allow-cross-root      Permit consumer paths outside --root.
  --strict                severity:warning -> exit 1.
  --compact               One-line `path:line: message [rule-code]` output.
  --verbose               Multi-line output with remediation note.
  --quiet                 Suppress OK summary.
  -h | --help             This help.

Exit codes:
  0  clean
  1  errors found (or warnings with --strict)
  2  usage / config / path-traversal / fatal parse error
EOF
}

ROOT="$PWD"
CONFIG=""
BASELINE_OVERRIDE=""
NO_BASELINE=0
ALLOW_CROSS_ROOT=0
STRICT=0
FMT="default"
QUIET=0

while [ $# -gt 0 ]; do
    case "$1" in
        --root)              ROOT="${2:-}"; shift 2 ;;
        --config)            CONFIG="${2:-}"; shift 2 ;;
        --baseline)          BASELINE_OVERRIDE="${2:-}"; shift 2 ;;
        --no-baseline)       NO_BASELINE=1; shift ;;
        --allow-cross-root)  ALLOW_CROSS_ROOT=1; shift ;;
        --strict)            STRICT=1; shift ;;
        --compact)           FMT="compact"; shift ;;
        --verbose)           FMT="verbose"; shift ;;
        --quiet)              QUIET=1; shift ;;
        -h|--help)           print_usage; exit 0 ;;
        *)                   echo "Error: unknown arg: $1" >&2; print_usage; exit 2 ;;
    esac
done

if [ ! -d "$ROOT" ]; then
    echo "Error: --root '$ROOT' is not a directory" >&2
    exit 2
fi

ROOT_ABS="$(cd "$ROOT" && pwd -P)"

# --- Config discovery ---------------------------------------------------------
if [ -z "$CONFIG" ]; then
    if [ -n "${DOC_FANOUT_CONFIG:-}" ]; then
        CONFIG="$DOC_FANOUT_CONFIG"
    elif [ -f "$ROOT_ABS/.doc-fanout.yml" ]; then
        CONFIG="$ROOT_ABS/.doc-fanout.yml"
    elif [ -f "$PWD/.doc-fanout.yml" ]; then
        CONFIG="$PWD/.doc-fanout.yml"
    else
        echo "Error: no config found; pass --config or set DOC_FANOUT_CONFIG" >&2
        exit 2
    fi
fi

if [ ! -f "$CONFIG" ]; then
    echo "Error: config '$CONFIG' not found" >&2
    exit 2
fi

# Hard caps (T3 mitigation)
CFG_SIZE=$(wc -c < "$CONFIG" | tr -d ' ')
if [ "$CFG_SIZE" -gt 262144 ]; then
    echo "Error: config exceeds 256KB cap" >&2
    exit 2
fi

# --- Baseline -----------------------------------------------------------------
if [ "$NO_BASELINE" -eq 1 ]; then
    BASELINE=""
elif [ -n "$BASELINE_OVERRIDE" ]; then
    BASELINE="$BASELINE_OVERRIDE"
else
    BASELINE="$ROOT_ABS/.docfanoutignore"
fi

BASELINE_PATTERNS=()
if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            ''|'#'*) continue ;;
            *)       BASELINE_PATTERNS+=("$_line") ;;
        esac
    done < "$BASELINE"
fi

matches_baseline() {
    local rel="$1" pat
    for pat in "${BASELINE_PATTERNS[@]+"${BASELINE_PATTERNS[@]}"}"; do
        # shellcheck disable=SC2053,SC2254
        case "$rel" in
            $pat) return 0 ;;
        esac
    done
    return 1
}

# --- Canonicaliser (sourced from scripts/lib/canonicalise.sh) -----------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
CANON_LIB="$SCRIPT_DIR/../scripts/lib/canonicalise.sh"
if [ ! -f "$CANON_LIB" ]; then
    echo "Error: canonicalise.sh missing at $CANON_LIB" >&2
    exit 2
fi
# shellcheck source=../scripts/lib/canonicalise.sh
. "$CANON_LIB"

# --- AWK YAML parser (block-style, depth <=3, no flow) ------------------------
AWK_YAML='
BEGIN { section=""; art_idx=-1; con_idx=-1; cnt_idx=-1; in_cons=0 }

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function strip_quotes(s,    f, l) {
    if (length(s) >= 2) {
        f = substr(s, 1, 1); l = substr(s, length(s), 1);
        if ((f == "\"" && l == "\"") || (f == "'\''" && l == "'\''"))
            return substr(s, 2, length(s) - 2);
    }
    return s;
}
function emit(prefix, k, v) { print prefix "\t" k "\t" v }

# Skip blank/comment
/^[ \t]*$/ { next }
/^[ \t]*#/ { next }

{
    # Compute indent (spaces only; tabs disallowed)
    if (match($0, /^\t/)) {
        printf("PARSE_ERR: tabs in indent at line %d\n", NR) > "/dev/stderr";
        exit 2;
    }
    indent = 0;
    while (substr($0, indent+1, 1) == " ") indent++;
    raw = substr($0, indent+1);
    # Length cap (T3)
    if (length(raw) > 8192) {
        printf("PARSE_ERR: line %d exceeds 8KB\n", NR) > "/dev/stderr";
        exit 2;
    }
}

# ROOT
indent == 0 && raw ~ /^version:/ {
    v = trim(substr(raw, index(raw, ":") + 1));
    print "V\t" strip_quotes(v);
    section = "";
    next;
}
indent == 0 && raw ~ /^artifacts:/ {
    section = "artifacts"; art_idx = -1; in_cons = 0; next;
}
indent == 0 && raw ~ /^counts:/ {
    section = "counts"; cnt_idx = -1; next;
}
indent == 0 {
    printf("PARSE_ERR: unknown root key at line %d: %s\n", NR, raw) > "/dev/stderr";
    exit 2;
}

# ARTIFACTS section
section == "artifacts" && raw ~ /^- / && indent == 2 {
    art_idx++; con_idx = -1; in_cons = 0;
    kv = substr(raw, 3);
    cp = index(kv, ":");
    if (cp > 0) {
        k = trim(substr(kv, 1, cp - 1));
        v = trim(substr(kv, cp + 1));
        emit("A\t" art_idx, k, strip_quotes(v));
    }
    next;
}
section == "artifacts" && indent == 4 && art_idx >= 0 {
    if (raw ~ /^consumers:/) { in_cons = 1; next; }
    in_cons = 0;
    cp = index(raw, ":");
    if (cp > 0) {
        k = trim(substr(raw, 1, cp - 1));
        v = trim(substr(raw, cp + 1));
        emit("A\t" art_idx, k, strip_quotes(v));
    }
    next;
}
section == "artifacts" && in_cons && raw ~ /^- / && indent == 6 {
    con_idx++;
    kv = substr(raw, 3);
    cp = index(kv, ":");
    if (cp > 0) {
        k = trim(substr(kv, 1, cp - 1));
        v = trim(substr(kv, cp + 1));
        emit("C\t" art_idx "\t" con_idx, k, strip_quotes(v));
    }
    next;
}
section == "artifacts" && in_cons && indent == 8 && con_idx >= 0 {
    cp = index(raw, ":");
    if (cp > 0) {
        k = trim(substr(raw, 1, cp - 1));
        v = trim(substr(raw, cp + 1));
        emit("C\t" art_idx "\t" con_idx, k, strip_quotes(v));
    }
    next;
}

# COUNTS section
section == "counts" && raw ~ /^- / && indent == 2 {
    cnt_idx++;
    kv = substr(raw, 3);
    cp = index(kv, ":");
    if (cp > 0) {
        k = trim(substr(kv, 1, cp - 1));
        v = trim(substr(kv, cp + 1));
        emit("N\t" cnt_idx, k, strip_quotes(v));
    }
    next;
}
section == "counts" && indent == 4 && cnt_idx >= 0 {
    cp = index(raw, ":");
    if (cp > 0) {
        k = trim(substr(raw, 1, cp - 1));
        v = trim(substr(raw, cp + 1));
        emit("N\t" cnt_idx, k, strip_quotes(v));
    }
    next;
}
'

PARSED="$(LC_ALL=C awk "$AWK_YAML" "$CONFIG")"
PARSE_RC=$?
if [ "$PARSE_RC" -ne 0 ]; then
    exit 2
fi

# --- Verify version + extract values ------------------------------------------
VERSION="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="V"{print $2; exit}')"
if [ -z "$VERSION" ]; then
    echo "Error: config missing 'version:' key" >&2
    exit 2
fi
if [ "$VERSION" != "1" ]; then
    echo "Error: unsupported config version '$VERSION' (expected 1)" >&2
    exit 2
fi

# Sanity: at least one of artifacts/counts present
HAS_ART="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="A"{print "y"; exit}')"
HAS_CNT="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="N"{print "y"; exit}')"
if [ -z "$HAS_ART" ] && [ -z "$HAS_CNT" ]; then
    echo "Error: config has no 'artifacts:' or 'counts:' rules" >&2
    exit 2
fi

# Helper: extract a field for an entity
# get_field A|N art_idx [con_idx] field
get_a() {  # get_a art_idx field
    printf '%s\n' "$PARSED" | awk -F'\t' -v a="$1" -v f="$2" \
        '$1=="A" && $2==a && $3==f{print $4; exit}'
}
get_c() {  # get_c art_idx con_idx field
    printf '%s\n' "$PARSED" | awk -F'\t' -v a="$1" -v ci="$2" -v f="$3" \
        '$1=="C" && $2==a && $3==ci && $4==f{print $5; exit}'
}
get_n() {  # get_n cnt_idx field
    printf '%s\n' "$PARSED" | awk -F'\t' -v n="$1" -v f="$2" \
        '$1=="N" && $2==n && $3==f{print $4; exit}'
}

# Index iterators
ART_IDXS="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="A"{print $2}' | sort -un)"
CNT_IDXS="$(printf '%s\n' "$PARSED" | awk -F'\t' '$1=="N"{print $2}' | sort -un)"

# --- Validators (S1) ----------------------------------------------------------
NAME_RE='^[a-zA-Z0-9._-]+$'
GREP_PATTERN_RE='^[a-zA-Z0-9/_.{}-]+$'
PATH_PATTERN_RE='^[a-zA-Z0-9./_{}-]+$'
COUNT_PATTERN_RE='^[]a-zA-Z0-9./_ +()[\\-]+$'

valid_name_transform() {
    case "$1" in
        basename|basename_no_ext|literal) return 0 ;;
        *) return 1 ;;
    esac
}

valid_severity() {
    case "$1" in error|warning) return 0 ;; *) return 1 ;; esac
}

# --- Output sink --------------------------------------------------------------
ERR_COUNT=0
WARN_COUNT=0
VIOL_COUNT=0
ART_TOUCHED=""

emit_violation() {
    # emit_violation severity rule_code artefact surface_id surface_target message [line]
    local sev="$1" rc="$2" art="$3" surf="$4" tgt="$5" msg="$6" ln="${7:-}"
    if matches_baseline "$art|$rc|$surf"; then
        return 0
    fi
    if [ "$sev" = "error" ]; then
        ERR_COUNT=$((ERR_COUNT + 1))
    else
        WARN_COUNT=$((WARN_COUNT + 1))
    fi
    VIOL_COUNT=$((VIOL_COUNT + 1))
    case "$ART_TOUCHED" in
        *"|$art|"*) ;;
        *) ART_TOUCHED="$ART_TOUCHED|$art|" ;;
    esac
    case "$FMT" in
        compact)
            if [ -n "$ln" ]; then
                printf '%s:%s: %s [%s]\n' "$tgt" "$ln" "$msg" "$rc"
            else
                printf '%s: %s -> %s: %s [%s]\n' \
                    "$(echo "$sev" | tr '[:lower:]' '[:upper:]')" "$art" "$tgt" "$msg" "$rc"
            fi
            ;;
        verbose)
            printf '%s[%s]: %s\n  surface: %s (%s)\n  note:    %s\n\n' \
                "$sev" "$rc" "$art" "$surf" "$tgt" "$msg"
            ;;
        *)
            local label
            if [ "$sev" = "error" ]; then label="ERR"; else label="WARN"; fi
            printf '%s %s -> %s: %s [%s]\n' "$label" "$art" "$tgt" "$msg" "$rc"
            ;;
    esac
}

# --- Pattern substitution -----------------------------------------------------
substitute_name() {
    # substitute_name template name → echoes substituted string
    local tpl="$1" name="$2"
    # name already validated against NAME_RE before call
    printf '%s' "${tpl//\{name\}/$name}"
}

# --- Glob expansion (relative to ROOT_ABS) ------------------------------------
expand_glob() {
    # expand_glob pattern → newline-separated absolute paths
    local pat="$1"
    # shellcheck disable=SC2086
    (cd "$ROOT_ABS" && shopt -s nullglob && \
        for f in $pat; do printf '%s\n' "$ROOT_ABS/$f"; done)
}

# --- Resolve cross-root path safely -------------------------------------------
resolve_target_path() {
    # echoes absolute path; returns 0 if safe, 1 if traversal smell, 2 if outside root and no allow
    local raw="$1" cross_root="$2"
    # Forbid ".." in non-cross-root paths (smell)
    if [ "$cross_root" != "true" ]; then
        case "$raw" in
            *..*) return 1 ;;
        esac
    fi
    local abs
    if [ "${raw:0:1}" = "/" ]; then
        abs="$raw"
    else
        abs="$(canonicalise_path "$ROOT_ABS/$raw")"
    fi
    case "$abs" in
        "$ROOT_ABS"|"$ROOT_ABS"/*)
            printf '%s' "$abs"; return 0 ;;
        *)
            if [ "$cross_root" = "true" ] && [ "$ALLOW_CROSS_ROOT" -eq 1 ]; then
                # Validate charset of resolved absolute path
                case "$abs" in
                    *[!a-zA-Z0-9./_-]*) return 1 ;;
                esac
                printf '%s' "$abs"; return 0
            fi
            return 2
            ;;
    esac
}

# --- Process artefacts --------------------------------------------------------
for AI in $ART_IDXS; do
    GLOB="$(get_a "$AI" glob)"
    NAME_TR="$(get_a "$AI" name_transform)"
    if [ -z "$GLOB" ] || [ -z "$NAME_TR" ]; then
        echo "Error: artefact $AI missing glob or name_transform" >&2
        exit 2
    fi
    if ! valid_name_transform "$NAME_TR"; then
        echo "Error: artefact $AI invalid name_transform '$NAME_TR'" >&2
        exit 2
    fi

    # Enumerate consumers for this artefact
    CON_IDXS="$(printf '%s\n' "$PARSED" | awk -F'\t' -v a="$AI" '$1=="C" && $2==a{print $3}' | sort -un)"
    if [ -z "$CON_IDXS" ]; then continue; fi

    # Expand glob
    PATHS="$(expand_glob "$GLOB")"
    if [ -z "$PATHS" ]; then continue; fi

    while IFS= read -r ABS_PATH; do
        [ -z "$ABS_PATH" ] && continue
        REL_PATH="${ABS_PATH#"$ROOT_ABS"/}"
        BN="$(basename "$ABS_PATH")"
        case "$NAME_TR" in
            basename)         NAME="$BN" ;;
            basename_no_ext)  NAME="${BN%.*}" ;;
            literal)          NAME="$GLOB" ;;
        esac
        # S1: validate derived name
        if ! [[ "$NAME" =~ $NAME_RE ]]; then
            echo "Error: derived name '$NAME' fails validator" >&2
            exit 2
        fi

        for CI in $CON_IDXS; do
            KIND="$(get_c "$AI" "$CI" kind)"
            ID="$(get_c "$AI" "$CI" id)"
            SEV="$(get_c "$AI" "$CI" severity)"
            CROSS="$(get_c "$AI" "$CI" cross_root)"
            [ -z "$SEV" ] && SEV="error"
            valid_severity "$SEV" || { echo "Error: bad severity '$SEV'" >&2; exit 2; }

            case "$KIND" in
                grep_in_file)
                    PAT_TPL="$(get_c "$AI" "$CI" pattern)"
                    FILE="$(get_c "$AI" "$CI" file)"
                    if [ -z "$PAT_TPL" ] || [ -z "$FILE" ]; then
                        echo "Error: grep_in_file consumer $AI/$CI missing pattern/file" >&2
                        exit 2
                    fi
                    if ! [[ "$PAT_TPL" =~ $GREP_PATTERN_RE ]]; then
                        echo "Error: grep pattern '$PAT_TPL' fails validator" >&2
                        exit 2
                    fi
                    PAT="$(substitute_name "$PAT_TPL" "$NAME")"
                    FILE_ABS="$ROOT_ABS/$FILE"
                    if [ ! -f "$FILE_ABS" ]; then
                        emit_violation "$SEV" grep-missing "$REL_PATH" "$ID" "$FILE" \
                            "consumer file does not exist"
                        continue
                    fi
                    if ! grep -F -q -- "$PAT" "$FILE_ABS"; then
                        emit_violation "$SEV" grep-missing "$REL_PATH" "$ID" "$FILE" \
                            "pattern '$PAT' not found"
                    fi
                    ;;
                file_must_exist)
                    PATH_TPL="$(get_c "$AI" "$CI" path)"
                    if [ -z "$PATH_TPL" ]; then
                        echo "Error: file_must_exist consumer $AI/$CI missing path" >&2
                        exit 2
                    fi
                    if ! [[ "$PATH_TPL" =~ $PATH_PATTERN_RE ]]; then
                        echo "Error: path pattern '$PATH_TPL' fails validator" >&2
                        exit 2
                    fi
                    P_RESOLVED="$(substitute_name "$PATH_TPL" "$NAME")"
                    RESOLVED_ABS="$(resolve_target_path "$P_RESOLVED" "${CROSS:-false}")"
                    RC=$?
                    if [ "$RC" -eq 1 ]; then
                        echo "Error: path traversal smell in '$P_RESOLVED'" >&2
                        exit 2
                    fi
                    if [ "$RC" -eq 2 ]; then
                        echo "Error: cross-root path requires --allow-cross-root: $P_RESOLVED" >&2
                        exit 2
                    fi
                    if [ ! -e "$RESOLVED_ABS" ]; then
                        emit_violation "$SEV" file-missing "$REL_PATH" "$ID" "$P_RESOLVED" \
                            "file does not exist"
                    fi
                    ;;
                *)
                    echo "Error: unknown consumer kind '$KIND' at $AI/$CI" >&2
                    exit 2
                    ;;
            esac
        done
    done <<< "$PATHS"
done

# --- Process count rules ------------------------------------------------------
for NI in $CNT_IDXS; do
    SRC_GLOB="$(get_n "$NI" source_glob)"
    CONS_FILE="$(get_n "$NI" consumer_file)"
    PAT="$(get_n "$NI" pattern)"
    SEV="$(get_n "$NI" severity)"
    ID="$(get_n "$NI" id)"
    [ -z "$SEV" ] && SEV="error"
    if [ -z "$SRC_GLOB" ] || [ -z "$CONS_FILE" ] || [ -z "$PAT" ]; then
        echo "Error: count rule $NI missing source_glob/consumer_file/pattern" >&2
        exit 2
    fi
    if ! [[ "$PAT" =~ $COUNT_PATTERN_RE ]]; then
        echo "Error: count pattern '$PAT' fails validator" >&2
        exit 2
    fi
    PATHS="$(expand_glob "$SRC_GLOB")"
    if [ -z "$PATHS" ]; then
        EXPECTED=0
    else
        EXPECTED="$(printf '%s\n' "$PATHS" | wc -l | tr -d ' ')"
    fi
    CONS_ABS="$ROOT_ABS/$CONS_FILE"
    if [ ! -f "$CONS_ABS" ]; then
        emit_violation "$SEV" count-mismatch "$SRC_GLOB" "$ID" "$CONS_FILE" \
            "consumer file missing"
        continue
    fi
    # Find first match, extract first capture group
    MATCH_LINE="$(grep -n -E -- "$PAT" "$CONS_ABS" | head -1)"
    if [ -z "$MATCH_LINE" ]; then
        emit_violation "$SEV" count-mismatch "$SRC_GLOB" "$ID" "$CONS_FILE" \
            "expected $EXPECTED, pattern not found"
        continue
    fi
    LN="${MATCH_LINE%%:*}"
    REST="${MATCH_LINE#*:}"
    FOUND="$(printf '%s' "$REST" | grep -oE -- "$PAT" | head -1 | grep -oE '[0-9]+' | head -1)"
    if [ -z "$FOUND" ]; then
        emit_violation "$SEV" count-mismatch "$SRC_GLOB" "$ID" "$CONS_FILE" \
            "expected $EXPECTED, capture group not extractable"
        continue
    fi
    if [ "$FOUND" != "$EXPECTED" ]; then
        emit_violation "$SEV" count-mismatch "$SRC_GLOB" "$ID" "$CONS_FILE" \
            "count expected $EXPECTED, found $FOUND" "$LN"
    fi
done

# --- Summary + exit -----------------------------------------------------------
ART_COUNT="$(printf '%s' "$ART_TOUCHED" | tr '|' '\n' | grep -c .)"
[ -z "$ART_COUNT" ] && ART_COUNT=0

if [ "$VIOL_COUNT" -gt 0 ]; then
    if [ "$QUIET" -ne 1 ]; then
        echo "SUMMARY: $ERR_COUNT errors, $WARN_COUNT warnings ($VIOL_COUNT violations across $ART_COUNT artefacts)" >&2
    fi
fi

if [ "$ERR_COUNT" -gt 0 ]; then
    exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$WARN_COUNT" -gt 0 ]; then
    exit 1
fi
if [ "$QUIET" -ne 1 ] && [ "$VIOL_COUNT" -eq 0 ]; then
    echo "OK: doc-fanout clean" >&2
fi
exit 0
