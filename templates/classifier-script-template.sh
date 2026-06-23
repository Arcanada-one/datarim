#!/usr/bin/env bash
# classifier-script-template.sh — reusable template for a deterministic type-signal classifier.
#
# PURPOSE
#   Provides the skeleton for a classifier that reads a message from a file and
#   emits a classification token to stdout. Consumers fill in the STUB sections
#   with domain-specific signal patterns; the priority ordering and plumbing
#   MUST NOT be changed without updating the exit-code table.
#
# WHAT TO FILL IN
#   1. Replace the STUB blocks under "Signal N:" comments with real regexes.
#   2. Update the exit-code table comment to match the tokens you emit.
#   3. Replace the placeholder help text with your actual token descriptions.
#   4. Remove this header block comment and replace it with a project-specific one.
#
# CONTRACT NOTE — PRIORITY ORDERING IS THE CLASSIFIER CONTRACT
#   The order of the signal checks (comment > question > task > ambiguous) defines
#   which signal wins when a message matches multiple patterns. Reordering changes
#   observable behaviour. All consumers MUST preserve the stated priority order or
#   document a deliberate deviation with a signed-off contract note.
#
# USAGE
#   ./classifier-script-template.sh --message-file <path>
#
# INPUT GUARD (S1)
#   --message-file MUST be an existing regular file on the local filesystem.
#   Path traversal sequences ('..'), NUL bytes, and shell-special characters are
#   rejected before the file is opened. No user-supplied content is interpolated
#   into a shell command; all pattern matching goes through 'grep -E'.
#
# EXIT CODES (update this table when you change the token set)
#   0 — decided: one of the four classification tokens was emitted
#             "comment"    — message amends an existing item
#             "question"   — interrogative; no mutation implied
#             "task"       — imperative new-work intent
#             "ambiguous"  — no decisive signal (fail-closed default)
#   2 — usage error: missing --message-file, non-existent file, or rejected path
#
# REQUIREMENTS
#   bash 3.2+ | grep (POSIX + -E) | head | printf   — no yq/jq/python required
#
# SECURITY (Datarim Security Mandate S1)
#   - strict mode: set -euo pipefail
#   - safe IFS: $'\n\t'
#   - all external input validated by regex before use
#   - no eval, no command substitution on user data, no curl|bash patterns
#   - shellcheck -S warning must pass with exit 0

set -euo pipefail
# nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering -- canonical strict-mode IFS, not derived from input
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Internal utilities
# ---------------------------------------------------------------------------

die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

MESSAGE_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --message-file)
      [ $# -ge 2 ] || die "--message-file requires an argument"
      MESSAGE_FILE="$2"
      shift 2
      ;;
    --help|-h)
      cat >&2 <<'HELP'
Usage: classifier-script-template.sh --message-file <path>

Classifies a message and prints one of:
  comment     amends an existing tracked item
  question    interrogative, read-only intent
  task        imperative new-work intent
  ambiguous   no decisive signal (fail-closed default)

Exit 0 on any decision (including 'ambiguous'), exit 2 on usage error.
HELP
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# S1 input guard: validate --message-file before opening
# ---------------------------------------------------------------------------
# Rules enforced here:
#   1. Argument is required.
#   2. Path must resolve to an existing regular file (-f).
#   3. No path traversal: reject any path that contains the sequence '..'.
#   4. Only printable ASCII, forward-slash, dot, hyphen, underscore, and tilde
#      are permitted in the path. This blocks NUL bytes, shell metacharacters,
#      newlines, and any non-ASCII that could confuse downstream tooling.
#      Adjust the regex if your deployment allows a broader safe set.
# ---------------------------------------------------------------------------

[ -n "$MESSAGE_FILE" ] || die "--message-file is required"

PATH_SAFE_RE='^[a-zA-Z0-9_./ ~-]+$'
case "$MESSAGE_FILE" in
  *..*)
    die "path traversal rejected: $MESSAGE_FILE"
    ;;
esac
printf '%s' "$MESSAGE_FILE" | grep -qE "$PATH_SAFE_RE" \
  || die "unsafe characters in path: $MESSAGE_FILE"
[ -f "$MESSAGE_FILE" ] || die "file not found: $MESSAGE_FILE"

# ---------------------------------------------------------------------------
# Read message body
# Trimmed to first 2048 bytes — sufficient for signal detection and prevents
# runaway reads on accidentally large inputs.
# ---------------------------------------------------------------------------

MSG="$(head -c 2048 "$MESSAGE_FILE")"

# ---------------------------------------------------------------------------
# Helper: case-insensitive substring / regex match against the message body.
#
# Usage: msg_matches <ERE-pattern>
# Returns: 0 if the pattern matches anywhere in $MSG, 1 otherwise.
#
# Notes:
#   - Pattern is an Extended Regular Expression passed to 'grep -iE'.
#   - The function is intentionally narrow: pattern is a fixed argument
#     supplied by the script author, never derived from user input.
#   - Do NOT call msg_matches with a pattern constructed from $MSG or any
#     other user-controlled string — that would introduce a regex-injection
#     risk. For user-supplied patterns, validate against an allowlist first.
# ---------------------------------------------------------------------------

msg_matches() {
  printf '%s' "$MSG" | grep -iqE "$1"
}

# ===========================================================================
# PRIORITY-ORDERED SIGNAL TABLE
#
# MANDATORY: the order below is the classifier contract. Every signal that
# matches earlier in the list wins over later signals. Reordering is a
# behaviour change, not a cosmetic refactor. Document any deviation.
#
# Priority:
#   1. comment    (strongest — explicit existing-item reference detected)
#   2. question   (interrogative with no imperative override)
#   3. task       (imperative new-work with recognisable prefix)
#   4. ambiguous  (fail-closed default — no decisive signal)
#
# How to add a new signal:
#   Insert a numbered block ABOVE the "ambiguous" fallthrough.
#   Update the exit-code table in the header comment.
#   Add a corresponding test case in your test suite.
# ===========================================================================

# ---------------------------------------------------------------------------
# Signal 1: COMMENT
# STUB: fill in patterns that indicate the message amends an existing item.
#
# Typical shape: message contains both
#   (a) a reference token for an existing tracked item, AND
#   (b) a comment-intent lead phrase.
#
# Replace EXISTING_ITEM_RE with the regex that matches your item IDs.
# Replace COMMENT_INTENT_RE with phrases that signal amendment intent.
# The extracted hint (e.g. item ID) is emitted as a tab-separated suffix.
# ---------------------------------------------------------------------------

# STUB: replace with the regex for your tracked-item reference format.
EXISTING_ITEM_RE='[A-Z]{2,10}-[0-9]{4}'

# STUB: replace with comment-intent lead phrases relevant to your domain.
COMMENT_INTENT_RE='comment|amend|amendment|on [A-Z]{2,10}-[0-9]{4}'

has_existing_item=0
EXTRACTED_ITEM_ID=""
if printf '%s' "$MSG" | grep -oqE "$EXISTING_ITEM_RE"; then
  has_existing_item=1
  EXTRACTED_ITEM_ID="$(printf '%s' "$MSG" | grep -oE "$EXISTING_ITEM_RE" | head -1)"
fi

if [ "$has_existing_item" -eq 1 ] && msg_matches "$COMMENT_INTENT_RE"; then
  printf 'comment\t%s\n' "$EXTRACTED_ITEM_ID"
  exit 0
fi

# ---------------------------------------------------------------------------
# Signal 2: QUESTION
# STUB: fill in patterns that indicate interrogative / read-only intent.
#
# Typical shape: message has an interrogative lead OR a terminal '?',
# AND does NOT have a strong imperative lead (which would win as Signal 3).
# ---------------------------------------------------------------------------

# STUB: replace with interrogative lead phrases relevant to your domain.
QUESTION_LEAD_RE='what is|what.?s|where is|how (do|does|is|are)|when (is|will)'

# STUB: replace with imperative lead phrases that override question detection.
IMPERATIVE_LEAD_RE='add |create |build |implement |fix |update '

INTERROGATIVE_TERMINAL='\?[[:space:]]*$'

has_question=0
if msg_matches "$QUESTION_LEAD_RE" || \
   printf '%s' "$MSG" | grep -qE "$INTERROGATIVE_TERMINAL"; then
  has_question=1
fi

has_imperative=0
if msg_matches "$IMPERATIVE_LEAD_RE"; then
  has_imperative=1
fi

if [ "$has_question" -eq 1 ] && [ "$has_imperative" -eq 0 ]; then
  printf 'question\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Signal 3: TASK
# STUB: fill in patterns that indicate imperative new-work intent.
#
# Typical shape: message has BOTH
#   (a) an imperative lead phrase (overlaps with Signal 2's override), AND
#   (b) a recognisable domain prefix or category token.
# AND does NOT already reference an existing tracked item (those are Signal 1).
# ---------------------------------------------------------------------------

# STUB: replace with the regex for recognisable prefix / category tokens.
PREFIX_TOKEN_RE='[[:space:]][A-Z]{2,10}[[:space:]:]|^[A-Z]{2,10}[[:space:]:]'

has_prefix_token=0
EXTRACTED_PREFIX=""
if printf '%s' "$MSG" | grep -oqE "$PREFIX_TOKEN_RE"; then
  has_prefix_token=1
  EXTRACTED_PREFIX="$(printf '%s' "$MSG" \
    | grep -oE "$PREFIX_TOKEN_RE" | head -1 \
    | sed 's/[[:space:]:]//g')"
fi

if [ "$has_imperative" -eq 1 ] && [ "$has_prefix_token" -eq 1 ] && \
   [ "$has_existing_item" -eq 0 ]; then
  printf 'task\t%s\n' "$EXTRACTED_PREFIX"
  exit 0
fi

# ---------------------------------------------------------------------------
# Signal 4: AMBIGUOUS — fail-closed default
# No further STUB needed. This is the fallthrough when no signal above fired.
# Downstream consumers MUST handle this token via a clarification round or
# routing step; never treat 'ambiguous' as an error.
# ---------------------------------------------------------------------------

printf 'ambiguous\n'
exit 0
