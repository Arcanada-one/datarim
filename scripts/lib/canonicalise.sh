# shellcheck shell=bash
# canonicalise.sh — shared lexical path canonicalisation library.
#
# Provides:
#   canonicalise_path <path>  — collapses './' and resolves '../' against prior
#                               component. No I/O (parent dirs need not exist).
#                               Preserves leading '/' for absolute inputs.
#                               Used for path-traversal detection.
#
# Source: extracted from scripts/check-doc-refs.sh (TUNE-0054) for reuse by
# scripts/datarim-doctor.sh (TUNE-0071) — closes TUNE-0054 reflection
# Proposal A2 (N=2 spawn-trigger met).
#
# Style: POSIX-compatible bash; no external commands.

canonicalise_path() {
    local input="$1"
    local lead=""
    case "$input" in
        /*) lead="/" ;;
    esac
    # IFS is `local` — scoped to this function, restored on return. Path-component
    # split is the intended operation, not tampering. Subshells/external commands
    # are not invoked while IFS is altered.
    local IFS='/'  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
    # shellcheck disable=SC2206
    local parts=( $input )
    local out=()
    local seg
    for seg in "${parts[@]}"; do
        case "$seg" in
            ''|'.') ;;
            '..')
                if [ "${#out[@]}" -gt 0 ] && [ "${out[$((${#out[@]}-1))]}" != ".." ]; then
                    unset 'out[${#out[@]}-1]'
                    out=("${out[@]}")
                elif [ -z "$lead" ]; then
                    out+=("..")
                fi
                ;;
            *) out+=("$seg") ;;
        esac
    done
    if [ "${#out[@]}" -eq 0 ]; then
        printf '%s' "${lead:-.}"
    else
        # Reassign within still-local IFS scope; controls "${out[*]}" join only.
        IFS=/  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
        printf '%s%s' "$lead" "${out[*]}"
    fi
}
