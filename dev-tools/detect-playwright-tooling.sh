#!/usr/bin/env bash
# detect-playwright-tooling.sh — F4 Playwright resolution chain.
#
# Resolves the browser-automation tool that `/dr-qa` should use when a task
# touches frontend files. Resolution chain (first match wins):
#
#   1. Override:    DATARIM_PLAYWRIGHT={playwright-cli|playwright-mcp|env-browser|none}
#   2. CLI:         `playwright` on PATH (probed with `--version`)
#   3. MCP:         DATARIM_PLAYWRIGHT_MCP_AVAILABLE=1 OR `playwright-mcp` on PATH
#   4. env-browser: $BROWSER / $PLAYWRIGHT_BROWSER_PATH / $CHROME_PATH points
#                   at an executable file, with a path-traversal guard
#   5. none
#
# Headed mode is orthogonal to detection:
#
#   --headed         lenient — emit a finding and fall through to headless
#                    when $DISPLAY is unset (CI without X server).
#   --headed-strict  fail-fast — exit 2 when $DISPLAY is unset.
#   default          headless.
#
# Output:
#
#   default      stdout = one of {playwright-cli, playwright-mcp,
#                                  env-browser, none}, exit 0
#   --require    stdout = same; exit 1 when the result is 'none'
#   --json       stdout = single-line JSON
#                  {"tool":"<t>","headed":"<headless|headed>",
#                   "display":<bool>,"finding":"<optional>"}
#
# Exit codes:
#
#   0   resolved (or `none` without --require)
#   1   --require + `none`
#   2   usage error / invalid override / --headed-strict with no DISPLAY
#
# Test mock contract:
#
#   When DATARIM_TEST_MOCK=1, PATH is replaced by DATARIM_TEST_MOCK_PATH so the
#   bats suite can stub `playwright` / `playwright-mcp` deterministically
#   without touching the host environment. Production callers MUST NOT set
#   DATARIM_TEST_MOCK.
#
# Canonical contract: skills/playwright-qa.md § Resolution Chain.

set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="detect-playwright-tooling.sh"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME [--require] [--headed | --headed-strict] [--json]
  $SCRIPT_NAME --help | --version

Options:
  --require         Treat 'none' as failure (exit 1).
  --headed          Lenient headed mode — finding + fall through when no DISPLAY.
  --headed-strict   Strict headed mode — exit 2 when no DISPLAY.
  --json            Emit single-line JSON instead of plain stdout.
  --help            Show this help and exit 0.
  --version         Print version and exit 0.

Resolved tool (stdout, default mode):
  playwright-cli | playwright-mcp | env-browser | none

Exit codes:
  0   resolved (or 'none' without --require)
  1   --require set and result is 'none'
  2   usage error / invalid override / --headed-strict + no DISPLAY
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
REQUIRE=0
HEADED_MODE="default"   # default | headed | headed-strict
JSON_OUT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --require)        REQUIRE=1 ;;
        --headed)         HEADED_MODE="headed" ;;
        --headed-strict)  HEADED_MODE="headed-strict" ;;
        --json)           JSON_OUT=1 ;;
        --help|-h)        usage; exit 0 ;;
        --version)        echo "$SCRIPT_NAME $VERSION"; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Test-mock guard — prepend stub PATH while keeping /usr/bin:/bin so that
# stubs with `#!/usr/bin/env bash` shebangs can still launch the interpreter.
# ---------------------------------------------------------------------------
if [ "${DATARIM_TEST_MOCK:-0}" = "1" ]; then
    if [ -z "${DATARIM_TEST_MOCK_PATH:-}" ]; then
        echo "ERROR: DATARIM_TEST_MOCK=1 requires DATARIM_TEST_MOCK_PATH" >&2
        exit 2
    fi
    export PATH="$DATARIM_TEST_MOCK_PATH:/usr/bin:/bin"
fi

# ---------------------------------------------------------------------------
# Override validation — must happen BEFORE resolve_tool() is run inside `$(...)`,
# otherwise `exit 2` from inside the command substitution only exits the
# subshell and the script continues with an empty TOOL.
# ---------------------------------------------------------------------------
if [ -n "${DATARIM_PLAYWRIGHT:-}" ]; then
    case "$DATARIM_PLAYWRIGHT" in
        playwright-cli|playwright-mcp|env-browser|none) ;;
        *)
            echo "ERROR: invalid DATARIM_PLAYWRIGHT='$DATARIM_PLAYWRIGHT' (expected one of: playwright-cli, playwright-mcp, env-browser, none)" >&2
            exit 2
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Resolution chain
# ---------------------------------------------------------------------------

PROBE_TIMEOUT=3

# probe_cmd <name>   exit 0 if `name --version` returns within PROBE_TIMEOUT
probe_cmd() {
    local name="$1"
    command -v "$name" >/dev/null 2>&1 || return 1
    # Fall back to direct invocation when `timeout` is absent (BSD without coreutils).
    if command -v timeout >/dev/null 2>&1; then
        timeout "$PROBE_TIMEOUT" "$name" --version >/dev/null 2>&1
    else
        "$name" --version >/dev/null 2>&1
    fi
}

# probe_path_exec <path>  exit 0 if path is a regular executable file with no
# `..` traversal segment and `--version` returns within PROBE_TIMEOUT.
probe_path_exec() {
    local p="$1"
    [ -z "$p" ] && return 1
    case "$p" in
        *..*) return 1 ;;   # reject path-traversal candidates
    esac
    [ -f "$p" ] && [ -x "$p" ] || return 1
    if command -v timeout >/dev/null 2>&1; then
        timeout "$PROBE_TIMEOUT" "$p" --version >/dev/null 2>&1
    else
        "$p" --version >/dev/null 2>&1
    fi
}

resolve_tool() {
    # 1. Explicit override. Validation happens upfront (see § Override
    # validation below) so an invalid value cannot reach this branch.
    local override="${DATARIM_PLAYWRIGHT:-}"
    if [ -n "$override" ]; then
        echo "$override"
        return
    fi
    # 2. CLI.
    if probe_cmd playwright; then
        echo "playwright-cli"
        return
    fi
    # 3. MCP.
    if [ "${DATARIM_PLAYWRIGHT_MCP_AVAILABLE:-0}" = "1" ] \
        || command -v playwright-mcp >/dev/null 2>&1; then
        echo "playwright-mcp"
        return
    fi
    # 4. env-browser.
    local candidate
    for candidate in "${BROWSER:-}" "${PLAYWRIGHT_BROWSER_PATH:-}" "${CHROME_PATH:-}"; do
        if probe_path_exec "$candidate"; then
            echo "env-browser"
            return
        fi
    done
    # 5. none.
    echo "none"
}

TOOL="$(resolve_tool)"

# ---------------------------------------------------------------------------
# Headed-mode resolution (orthogonal to TOOL)
# ---------------------------------------------------------------------------
DISPLAY_PRESENT="false"
[ -n "${DISPLAY:-}" ] && DISPLAY_PRESENT="true"

HEADED_RESOLVED="headless"
FINDING=""

case "$HEADED_MODE" in
    default)
        HEADED_RESOLVED="headless"
        ;;
    headed)
        if [ "$DISPLAY_PRESENT" = "true" ]; then
            HEADED_RESOLVED="headed"
        else
            HEADED_RESOLVED="headless"
            FINDING="headed-requested-but-no-display"
        fi
        ;;
    headed-strict)
        if [ "$DISPLAY_PRESENT" = "true" ]; then
            HEADED_RESOLVED="headed"
        else
            echo "ERROR: --headed-strict requested but DISPLAY is not set" >&2
            exit 2
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# Output + exit code
# ---------------------------------------------------------------------------
if [ "$JSON_OUT" -eq 1 ]; then
    if [ -n "$FINDING" ]; then
        printf '{"tool":"%s","headed":"%s","display":%s,"finding":"%s"}\n' \
            "$TOOL" "$HEADED_RESOLVED" "$DISPLAY_PRESENT" "$FINDING"
    else
        printf '{"tool":"%s","headed":"%s","display":%s}\n' \
            "$TOOL" "$HEADED_RESOLVED" "$DISPLAY_PRESENT"
    fi
else
    echo "$TOOL"
fi

if [ "$TOOL" = "none" ] && [ "$REQUIRE" -eq 1 ]; then
    exit 1
fi
exit 0
