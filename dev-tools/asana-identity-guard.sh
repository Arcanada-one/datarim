#!/usr/bin/env bash
# asana-identity-guard.sh — PreToolUse(Bash) hook.
#
# PURPOSE: hard-block any Asana WRITE (comment / completion / create / edit /
# delete) that is authenticated with anyone other than Pavel Valentov.
#
# Asana attributes every write to the token owner. For the Aether project all
# Asana writes MUST act as Pavel Valentov (gid 1209356095801027), using the PAT
# at ~/.claude/projects/-Users-ug-code-aether-local-env/.secrets/asana-pavel-pat.
#
# The recurring failure (≥20×): the agent grabs the Yuval Korin token found in
# config/local/content-generator/.env (or a server-side /var/aether/.env, or the
# aio-py-scripts mapping) and posts comments / closes subtasks as Yuval — which
# pollutes the audit trail of Pavel's epic and cannot be cleanly deleted by Pavel.
#
# Canonical rule: memory feedback_asana_act_as_pavel.
#
# Contract: read the PreToolUse JSON on stdin, inspect tool_input.command. If it
# is an Asana WRITE that references a non-Pavel token source, emit
# permissionDecision=deny with a corrective message. Read-only GETs and writes
# that clearly load the Pavel PAT file are allowed. Fail-OPEN on any internal
# error (never block unrelated Bash work).

# NOTE: deliberately NOT `set -e`/`pipefail` — this guard uses `grep -q` and a
# globbing `ls` as boolean probes, all of which legitimately return non-zero when
# they don't match. Under `set -e`/`pipefail` a non-matching probe (e.g. `ls` of
# the Pavel-PAT glob on a host that lacks the secret) aborts the script before it
# can emit the deny verdict — that bug let the VM fail OPEN. Keep only `set -u`.
set -u

payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# Extract the command field (prefer jq, fall back to python3).
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
fi
if [ -z "$cmd" ] && command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$payload" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)"
fi
[ -n "$cmd" ] || exit 0

# ---------------------------------------------------------------------------
# GitLab identity guard (operator directive 2026-07-10): all Aether GitLab
# writes MUST act as Pavel Valentov too — never a non-Pavel token pulled from a
# server-side *.env. Symmetric to the Asana rule below. Runs FIRST; if it does
# not apply, fall through to the Asana logic.
# Pavel GitLab identity: username 'valentov', id 26119184.
gl_touch=0
printf '%s' "$cmd" | grep -qiE 'gitlab\.com/api/|(^|[^[:alnum:]_])glab([[:space:]]|$)' && gl_touch=1
if [ "$gl_touch" -eq 1 ]; then
  gl_write=0
  printf '%s' "$cmd" | grep -qiE -- '-X[[:space:]]*(POST|PUT|DELETE)|--request[[:space:]]*(POST|PUT|DELETE)|--data|--data-raw|[[:space:]]-d[[:space:]]' && gl_write=1
  # glab mutating subcommands (mr create/merge/close, issue create, note, etc.)
  printf '%s' "$cmd" | grep -qiE 'glab[[:space:]]+(mr|issue|release|snippet|api)[[:space:]]+(create|update|merge|close|reopen|delete|note|approve|revoke)|glab[[:space:]]+api[[:space:]].*(-X[[:space:]]*(POST|PUT|DELETE)|--method[[:space:]]*(POST|PUT|DELETE))' && gl_write=1
  # python requests / urllib mutating verb against gitlab
  printf '%s' "$cmd" | grep -qiE 'requests\.(post|put|delete)|method[[:space:]]*=[[:space:]]*.{0,2}(POST|PUT|DELETE)' && printf '%s' "$cmd" | grep -qiE 'gitlab\.com' && gl_write=1
  if [ "$gl_write" -eq 1 ]; then
    gl_bad=0; gl_reason=""
    # Non-Pavel GitLab token sources: any server-side / local *.env, the reviewer
    # code-review.env, or a bare GITLAB_API_TOKEN/GITLAB_TOKEN pulled from such a file.
    if printf '%s' "$cmd" | grep -qiE 'content-generator/\.env|facebook-api/\.env|config/local/[^[:space:]]*\.env|server-config/[^[:space:]]*\.env|/var/aether/\.env|code-review\.env'; then
      gl_bad=1; gl_reason="reads a GITLAB token from a server-side/local *.env (may not be Pavel Valentov's)"
    fi
    # Sanctioned Pavel path: the .secrets/gitlab-token file (Pavel by contract) or
    # the settings.json MCP token. If the command loads the Pavel gitlab-token file
    # and does NOT pull from a *.env, allow.
    gl_pavel=0
    printf '%s' "$cmd" | grep -qE '\.secrets/gitlab-token|~/\.gitlab-token|HOME/\.gitlab-token' && gl_pavel=1
    if [ "$gl_bad" -eq 1 ] || { [ "$gl_pavel" -eq 0 ] && printf '%s' "$cmd" | grep -qiE 'PRIVATE-TOKEN|Bearer|--token|GITLAB_API_TOKEN|GITLAB_TOKEN' && printf '%s' "$cmd" | grep -qiE 'code-review\.env|config/local|/var/aether'; }; then
      [ -n "$gl_reason" ] || gl_reason="GitLab write not proven to use Pavel Valentov's token"
      gl_pat="$(ls "$HOME"/.claude/projects/*/.secrets/gitlab-token 2>/dev/null | head -1 || true)"
      [ -n "$gl_pat" ] || gl_pat="\$HOME/.claude/projects/<aether-project>/.secrets/gitlab-token (Pavel's) or ~/.gitlab-token"
      gmsg="BLOCKED GitLab write: $gl_reason. All Aether GitLab writes MUST act as Pavel Valentov (username 'valentov', id 26119184). Load Pavel's token from $gl_pat and NEVER a GITLAB token from a server-side/local *.env (code-review.env etc.). Operator directive 2026-07-10."
      if command -v jq >/dev/null 2>&1; then
        jq -nc --arg m "$gmsg" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'
      else
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(printf '%s' "$gmsg" | sed 's/"/\\"/g')"
      fi
      exit 0
    fi
  fi
fi

# Only care about commands that touch the Asana API.
printf '%s' "$cmd" | grep -qiE 'app\.asana\.com|/api/1\.0/' || exit 0

# Is this a WRITE? POST/PUT/DELETE verb, a data body, or a write endpoint.
is_write=0
printf '%s' "$cmd" | grep -qiE -- '-X[[:space:]]*(POST|PUT|DELETE)|--request[[:space:]]*(POST|PUT|DELETE)' && is_write=1
printf '%s' "$cmd" | grep -qiE -- '--data|--data-urlencode|--data-raw|[[:space:]]-d[[:space:]]' && is_write=1
# /stories and /subtasks are the comment/subtask endpoints. Creating one is
# POST /tasks/<id>/stories|subtasks and ALWAYS carries a mutating verb or a data
# body — both already detected above. So we do NOT treat a bare /stories|/subtasks
# URL as a write by itself: a read (GET /stories/<id>, GET /tasks/<id>/stories list)
# has neither a mutating verb nor a body and must stay allowed. This avoids denying
# legitimate comment reads while still catching every real create/delete (which the
# verb/-d checks above flag). DELETE /stories/<id> is caught by the -X DELETE check.
:
# python urllib / requests with an explicit mutating verb
printf '%s' "$cmd" | grep -qiE 'method[[:space:]]*=[[:space:]]*.{0,2}(POST|PUT|DELETE)|requests\.(post|put|delete)' && is_write=1
[ "$is_write" -eq 1 ] || exit 0

# Non-Pavel token sources / identities. Any of these in an Asana write = deny.
#  - the Yuval token lives in content-generator / facebook-api / */local/*.env
#  - ASANA_ACCESS_TOKEN / ASANA_API_TOKEN are Yuval's by convention
#  - server-side /var/aether/.env on the reviewer host is Yuval's
#  - Yuval user gids
yuval=0
reason=""
if printf '%s' "$cmd" | grep -qiE 'content-generator/\.env|facebook-api/\.env|config/local/[^[:space:]]*\.env|server-config/[^[:space:]]*\.env|/var/aether/\.env|account_domain_mapping'; then
  yuval=1; reason="reads ASANA token from a *.env that holds Yuval Korin's PAT"
fi
if printf '%s' "$cmd" | grep -qiE 'ASANA_ACCESS_TOKEN|ASANA_API_TOKEN'; then
  yuval=1; reason="${reason:+$reason; }uses ASANA_ACCESS_TOKEN/ASANA_API_TOKEN (Yuval's token by convention)"
fi
if printf '%s' "$cmd" | grep -qE '1133784839965440|1209318609526444'; then
  yuval=1; reason="${reason:+$reason; }references a Yuval Korin user gid"
fi

# Explicit Pavel-PAT load is the sanctioned path — allow it even if the command
# also greps an env file (e.g. to read OTHER, non-token values), UNLESS the only
# token actually piped to Authorization is the Yuval env one. We keep this simple
# and safe: if the command loads the Pavel PAT file AND does NOT pipe a *.env
# ASANA token into Authorization, allow.
loads_pavel=0
printf '%s' "$cmd" | grep -qE '\.secrets/asana-pavel-pat' && loads_pavel=1

if [ "$loads_pavel" -eq 1 ] && [ "$yuval" -eq 0 ]; then
  exit 0
fi

if [ "$yuval" -eq 1 ] || [ "$loads_pavel" -eq 0 ]; then
  if [ "$yuval" -eq 0 ]; then
    reason="no Pavel PAT loaded (.secrets/asana-pavel-pat) — cannot verify the author is Pavel Valentov"
  fi
  # Resolve the Pavel-PAT path on whichever host this runs (Mac or VM) so the
  # remediation message points at the real file.
  pat_path="$(ls "$HOME"/.claude/projects/*/.secrets/asana-pavel-pat 2>/dev/null | head -1 || true)"
  [ -n "$pat_path" ] || pat_path="\$HOME/.claude/projects/<aether-project>/.secrets/asana-pavel-pat (MISSING — ask operator to install it on this host)"
  msg="BLOCKED Asana write: $reason. All Aether Asana writes MUST act as Pavel Valentov (gid 1209356095801027). Load the PAT from $pat_path (verify via GET /users/me → expect 'Pavel Valentov 1209356095801027'), and NEVER use ASANA_ACCESS_TOKEN from any *.env (that is Yuval Korin's). See memory feedback_asana_act_as_pavel."
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$(printf '%s' "$msg" | sed 's/"/\\"/g')"
  fi
  exit 0
fi

exit 0
