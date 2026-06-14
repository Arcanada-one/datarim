---
name: bash-pitfalls
description: Recurring bash/shell traps that pass review and break in prod. Load when writing or reviewing any .sh, especially regex-heavy ops scripts.
---

# Bash Pitfalls — Quick Reference

Source incidents: a prior incident Phase 8 Step 1 (BUG #1, BUG #2 — both High, both regex/grep traps caught only by post-implementation QA, both 1-line fixable); a prior phase Round 1 (cutover smoke shape — Trap 6).

## The Six Traps

### 1. `grep -F` makes EVERY meta character literal

```bash
# nosec-extract
# WRONG — `^` is treated as a literal caret, never matches line-start.
grep -Fq "^${d} " "$file"

# RIGHT — drop -F if you need the anchor, or tokenise:
awk -v d="$d" '$1 == d { found=1; exit } END { exit !found }' "$file"
```

`-F` (`--fixed-strings`) disables ALL regex interpretation: `^`, `$`, `.`, `*`, `[…]`, `(…)`. If your pattern needs anchoring or character classes, do NOT combine with `-F`. Common false-fix: author adds `-F` for safety against shell-meta in `${var}`, silently destroying their own anchor.

### 2. Boundary-alternation regex `(^|[[:space:]])X` — fails on the typical case

```bash
# nosec-extract
# WRONG — fails for the most common single-token line `server_name example.com;`.
grep -E "^[[:space:]]*server_name[[:space:]].*(^|[[:space:]])${d}([[:space:]]|;|$)"

# RIGHT — tokenise the directive, compare each token literally.
awk -v d="$d" '
    /^[[:space:]]*server_name[[:space:]]/ {
        for (i=2; i<=NF; i++) {
            tok=$i; sub(/;.*$/, "", tok)
            if (tok == d) { print FILENAME; next }
        }
    }
' "$dir"/*.conf
```

The `(^|[[:space:]])` boundary doesn't behave like `\b`: `^` matches only the very start of input, NOT after a previously-consumed token. Almost every "match domain anywhere in `server_name`" regex written this way silently fails the single-domain layout.

### 3. `${var}` interpolated into `sed`/`grep` is **regex**, not literal

```bash
# nosec-extract
# WRONG — `.` in $d matches any char; `example.com` ALSO matches `examplexcom`.
sed -i "s|root /var/www/${d}|root /data/www/${d}|g" "$cfg"
grep -q "root[[:space:]]\\+/var/www/${d}" "$cfg"

# RIGHT — validate $d strictly upstream (charset whitelist), AND prefer
#         awk literal comparison or escape the dot:
awk -v d="$d" 'tolower($2) == "/var/www/" d'
# or:
sed -i "s|root /var/www/${d//./\\.}|root /data/www/${d//./\\.}|g" "$cfg"
```

Strict input validation (e.g. domain charset `[a-z0-9.-]+\.[a-z]{2,}`) reduces exploitability but doesn't prevent benign collisions. For whole-token matching, awk `==` is unambiguous.

### 4. `mysql … -p"$pass"` exposes the password to `ps`

```bash
# nosec-extract
# WRONG — visible in `ps -ef` to every user on a multi-tenant box.
mysqldump -h"$h" -u"$user" -p"$pass" "$db"

# RIGHT — short-lived defaults file, chmod 0600:
local cnf=$(mktemp)
chmod 0600 "$cnf"
printf '[client]\nuser=%s\npassword=%s\nhost=%s\n' "$user" "$pass" "$h" > "$cnf"
mysqldump --defaults-extra-file="$cnf" "$db"
rm -f "$cnf"
```

Pattern reused throughout `tools/scripts/restore-site.sh` in the Aether repo. Also: never `echo "$pass"` into a pipeline visible by `set -x`.

### 5. `set -e` does NOT propagate through pipelines

```bash
# WRONG — if mysqldump fails, the script keeps going because `mysql` succeeded.
set -e
mysqldump … | mysql …

# RIGHT — explicit pipefail in the local scope, or check $PIPESTATUS:
set -o pipefail
mysqldump … | mysql …
set +o pipefail
# OR
mysqldump … | mysql …
[[ ${PIPESTATUS[0]} -eq 0 ]] || die "dump failed"
```

`pipefail` is per-shell-option, not per-command. Always set it explicitly around critical pipelines.

### 6. Single-status smoke is too narrow for cutover regressions

```bash
# nosec-extract
# WRONG — only HTTP code; misses content / length / redirect-target shifts.
post=$(curl -sw '%{http_code}\n' -o /dev/null -H "Host: $d" "$url")

# RIGHT — capture the response shape as a tuple, diff pre/post.
fmt='%{http_code} %{content_type} %{size_download} %{redirect_url}'
pre=$(curl -sw  "$fmt" -o /dev/null -H "Host: $d" "$url")
post=$(curl -sw "$fmt" -o /dev/null -H "Host: $d" "$url")
[ "$pre" = "$post" ] || rollback
```

For any cutover / migration / config-flip smoke gate, capture the full tuple `(http_code, content_type, size_download, redirect_url)` and diff pre/post. Status-code-only smoke misses semantic regressions where:

- 301 → 301 with different `Location` (host renamed, path relocated);
- 302 → 200 with empty body (route fell through);
- 200 → 200 with `Content-Length` changed by 90% (page rendered, content broken).

Stack-neutral; works for any HTTP backend. Tuple comparison is the cheapest way to harden auto-rollback triggers against false-PASS — in a prior phase Step 2 the pre/post tuple diff caught Round 1's 301 → 500 within a second of `systemctl reload`.

## Mandatory Workflow Rule for /dr-do

When implementing or modifying any `.sh` file:

1. Run `shellcheck -S warning <file>` before declaring the work complete. If `shellcheck` is not installed, install via `brew install shellcheck` / `apt install shellcheck` — it's not optional for ops scripts.
2. Re-read every `grep` / `sed` / `awk` you wrote with one question: "what does the regex engine actually see after shell expansion?"
3. For any whole-token / whole-word match against shell-quoted user data, prefer `awk` token comparison (`$N == d`) over regex word-boundary alternation — it's shorter, clearer, and meta-safe.
4. For any password / secret on the `mysql` / `mysqldump` / `psql` / `redis-cli` command line, use `--defaults-extra-file=` (or stdin) — never `-p"$pass"`.

## Pitfall: Pipe-induced exit-code blindness during verification

### Trap

```bash
# WRONG — `$?` is tail's exit (=0), not the script's. Failing scripts pass.
./build.sh 2>&1 | tail -5
echo "rc=$?"   # always 0 even if build.sh exited 133
```

### Right

```bash
# Capture exit code BEFORE piping to formatters:
./build.sh > /tmp/out 2>&1; rc=$?
tail -5 /tmp/out
[ "$rc" -eq 0 ] || exit 1

# OR use pipefail when assertion needs the source command's exit:
set -o pipefail
./build.sh 2>&1 | tail -5
echo "rc=$?"   # now reflects build.sh exit (or tail's if tail fails)

# OR PIPESTATUS for fine-grained control:
./build.sh 2>&1 | tail -5
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
```

### Why this matters in practice

a prior phase verification: `bash scripts/stack-agnostic-gate.sh ~/.claude/{skills,...}/ 2>&1 | tail` reported «PASS clean», but the actual gate script exited 133 (SIGTRAP, kernel-killed) silently. The `tail -1` returned exit 0, so `$?` was 0. I observed «PASS clean» as the last printed line and concluded success. Real state: 11 leaky files in runtime, gate dying mid-scan. Latent bug for ~24 hours; surfaced only when the gate was run without the tail-pipe wrapper.

**Rule:** any verification step that asserts on exit code MUST capture the source command's exit BEFORE piping. The pipe is a formatter, not a result-bearer. Reinforce especially during /dr-do verification and /dr-qa Layer 4.

## Pitfall: Heredoc IS stdin

A heredoc replaces the command's stdin entirely. Writing `interpreter - <<'EOF' ... EOF` and then trying to read piped input from inside the heredoc body does NOT see the pipe — heredoc content already replaced stdin.

### Trap

```bash
# nosec-extract
echo "$payload" | python3 - <<'PY'
import sys
data = sys.stdin.read()  # gets the heredoc body, NOT "$payload"
PY
```

The pipe is silently ignored. Tests built around this pattern can pass for the wrong reason — the script processes the heredoc text as if it were the input.

### Right

Pass payload via environment variable, read with `os.environ`:

```bash
# nosec-extract
PAYLOAD="$payload" python3 -c '
import os
data = os.environ["PAYLOAD"]
'
```

Or use a here-string for stdin alongside an inline `-c` script (no heredoc):

```bash
# nosec-extract
python3 -c 'import sys; data = sys.stdin.read()' <<<"$payload"
```

### Why this matters in practice

prior incident — initial `post-deploy-verify.sh` evaluator used the heredoc-with-stdin shadow pattern. Tests appeared to pass because the script processed the heredoc body (a leftover `data = sys.stdin.read()` line plus the JSON parsing template) — not the captured PROD snapshot. Caught only when fixture content was actually inspected against parser output.

**Rule:** any inline interpreter that needs caller-supplied data should receive it through an environment variable or a here-string, not through a heredoc-and-pipe combination. The heredoc body is the script source — it cannot also be the input stream.

## Pitfall: `date +%s%N` is GNU-only — silent breakage on macOS / BSD

### Trap

```bash
# WRONG — works on Linux (GNU coreutils), prints literal "%N" on macOS BSD date.
now_ms=$(date +%s%N)
echo "${now_ms:0:-6}"   # garbage on mac: e.g. "1715000000%N" -> empty
```

`date +%N` is a GNU-only format token. macOS / FreeBSD `date(1)` prints it
verbatim, so the timestamp silently becomes wrong. No exit error, no warning —
just a non-numeric trailing `%N` that downstream arithmetic discards or
mangles. Cross-platform shell scripts that need millisecond precision MUST NOT
rely on `date +%s%N`.

### Right

```bash
# Portable millisecond clock: prefer bash 5's $EPOCHREALTIME, fall back to
# perl (present on macOS by default and on every Ubuntu base image).
now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local r="$EPOCHREALTIME"
    local sec="${r%.*}"
    local frac="${r#*.}"
    frac="${frac:0:3}"
    while [[ ${#frac} -lt 3 ]]; do frac="${frac}0"; done
    echo "$(( 10#$sec * 1000 + 10#$frac ))"
  else
    perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'
  fi
}
```

Bash 5 exposes `$EPOCHREALTIME` as `<seconds>.<fractional>` — fast (no fork),
no external dependency. Bash 3.2 / 4 paths fall back to perl, which is on
every supported runner and the macOS base install. Avoid the temptation to
require GNU coreutils — most dev hosts in this ecosystem are macOS.

### Why this matters in practice

An earlier orchestrator plan §5.4 originally specified `date +%s%N` for the security-floor
cooldown clock. The first smoke run on the mac dev box produced timestamps
ending in literal `%N`, breaking the cooldown arithmetic without any error.
The fix above was applied during `/dr-do` and is now the canonical recipe.

## Pitfall: `awk` `sub()` does NOT support capture groups — that's `sed`-only

### Trap

```bash
# WRONG — awk's sub()/gsub() do not interpret `\1` as a backreference.
# It just substitutes the literal two characters "\" and "1".
echo 'foo: "bar"' | awk '/^foo:/ { sub(/"(.*)"/, "\\1"); print }'
# Prints:  foo: \1            (NOT  foo: bar)
```

`awk`'s `sub()` and `gsub()` accept an ERE pattern but the replacement string
treats `\1..\9` as literal text — there are no capture groups. The behaviour
is silently wrong: no syntax error, just the wrong substitution. People hit
this every time they translate a working `sed s/(.*)/\1/` into awk «because
awk feels cleaner here».

### Right

Use `match()` + `substr()` for capture-equivalent extraction inside awk:

```bash
echo 'foo: "bar"' | awk '
  /^foo:/ {
    if (match($0, /"[^"]*"/)) {
      print substr($0, RSTART + 1, RLENGTH - 2)
    }
  }
'
# Prints:  bar
```

Or stay in `sed` / `perl` for backreference-heavy replacements:

```bash
echo 'foo: "bar"' | sed -E 's/^foo: "(.*)"$/\1/'
```

### Why this matters in practice

An earlier orchestrator plan §5.5 used `awk '... sub(/^"(.*)"$/, "\\1") ...'` for stripping
quotes around YAML scalar values. First smoke test produced `\1` literal in
the output instead of the quoted contents. Replaced with `match()` +
`substr()` and the fixture cleared.

## Why this fragment exists

a prior phase shipped two High-severity bugs to QA, both of which are textbook regex/grep traps and both of which would have been caught by either (a) a 5-second mental "what does the regex engine see?" check, or (b) shellcheck with extended pattern checks. The fix in both cases was to abandon the regex and use `awk` token-equality. This fragment encodes the lesson so future ops-script work doesn't repeat it.

The pipe-blindness pitfall above was added in prior reflection after the same operator (me) violated the existing «check exit code carefully» rule during a prior incident final validation — concrete example with task IDs is more memorable than abstract warning.

The heredoc-IS-stdin pitfall was added in prior reflection after the same shadow caused tests to pass on incorrect data flow in `post-deploy-verify.sh`. Concrete recovery recipe (env-var pass-through) included so future inline-interpreter work doesn't repeat it.
## Pitfall: top-level `source` of a missing lib in bats aborts the file as `1..0`

### Trap

```bash
# nosec-extract
# WRONG — at bats file top-level. If the lib is missing/not-yet-created, bats
# aborts the ENTIRE file at load time and reports `1..0` with exit code 0 — a
# false green that looks like "no tests ran" but passes any gate that only
# checks the exit code.
. "$BATS_TEST_DIRNAME/../scripts/lib/schema-regex.sh"

@test "T1 …" { … }
```

A TDD-red run that should fail (the lib does not exist yet) instead reports rc=0,
because the failed top-level `source` kills test registration before any `@test`
runs. The honest red is masked.

### Right

```bash
# nosec-extract
# Source the lib INSIDE setup() (runs before each test). A missing file then
# fails the individual tests (real red), not the file load.
setup() {
    TMPROOT="$(mktemp -d)"
    # shellcheck source=../scripts/lib/schema-regex.sh
    . "$SCHEMA_REGEX_LIB"
}
```

### Why this matters in practice

A prior task extracted a sourced schema-regex fragment and wrote the TDD-red
tests first. The first red run reported rc=0 / `1..0` (false green) because the
top-level `source` of the not-yet-created fragment aborted the file. Moving the
source into `setup()` produced the honest all-red, then all-green after the
fragment landed.

**Rule:** never `source` an optional / about-to-be-created dependency at a bats
file's top level. Put it in `setup()` (or guard it) so a missing dependency
fails tests visibly instead of silently zeroing the test count.

## Pitfall: `shellcheck` without `-x` flags every constant in a sourced lib as SC2034

### Trap

A `lib/*.sh` that only defines constants for consumers to `source` looks entirely
unused to `shellcheck` when it is linted in isolation (no `-x` to follow sources):

```text
SC2034 (warning): ONELINER_RE appears unused. Verify use (or export if used externally).
```

CI typically runs `shellcheck -S warning <file>` per file without `-x`, so a
constants-only library fails the required `shellcheck` check even though every
constant is used by a consumer that sources the file.

### Right

```bash
# nosec-extract
# shellcheck shell=bash
# shellcheck disable=SC2034  # constants are sourced by <consumer>.sh; shellcheck cannot see the consumers.
ONELINER_RE='…'
SCHEMA_TASKS_RE='…'
```

A file-level `# shellcheck disable=SC2034` near the top is the canonical fix for a
sourced constants/regex library. Pair it with `# shellcheck shell=bash` so the
linter treats the no-shebang fragment as a bash library.

### Why this matters in practice

A prior task's sourced regex-constant library (four constants) failed
`shellcheck -S warning` on all four with SC2034 until the file-level disable was
added. The CI `shellcheck` job runs without `-x`, so the disable is load-bearing,
not cosmetic.

## Pitfall: `test && cmd` as the LAST line of a function under `set -e` returns 1 on a false test

### Trap

```bash
# nosec-extract
# WRONG — when $role is empty (a VALID path), the test fails, the && short-circuits,
# and the function's exit status IS that failed test → rc 1. Under `set -e` the
# CALLER then aborts, even though doing nothing was the intended behaviour.
spawn() {
  new_session "$@"
  [ -n "$role" ] && inject_role "$role"   # <- last statement; rc 1 when role empty
}
```

### Right

```bash
# nosec-extract
spawn() {
  new_session "$@"
  if [ -n "$role" ]; then
    inject_role "$role"
  fi
}
# or, if you must keep the one-liner, neutralise the false branch:
#   [ -n "$role" ] && inject_role "$role" || true
```

A function's exit status is the status of its last executed command. A trailing
`test && cmd` evaluates to the test's status whenever the test is false — so an
optional action expressed as a one-liner silently turns "nothing to do" into a
failure the caller propagates. Use a full `if … fi` (or append `|| true`) for any
conditional whose false branch is a legitimate no-op.

### Why this matters in practice

A prior task wired an optional injection as `[ -n "$role" ] && _inject … ` on the
last line of the spawn function. Every test that called spawn WITHOUT the optional
argument failed under `set -euo pipefail` — the valid no-op path returned 1. The
whole suite went red until the line became a full `if`. Caught only by regression,
not by review.

## Pitfall: `${2:-default}` coerces an explicit empty-string argument back to the default

### Trap

```bash
# nosec-extract
# WRONG — a helper meant to support "no extension" as a distinct case:
make_file() {
    local ext="${2:-.md}"   # ${2:-X} substitutes X when $2 is unset OR empty
    [ -n "$ext" ] && mv "$f" "$f$ext"
    ...
}
make_file 360000 ""         # caller intends "no extension" → ext silently becomes .md
```

The colon form `${var:-default}` treats an explicit empty string `""` the same as
*unset* and substitutes the default. A caller passing `""` to mean "deliberately
empty" gets the default instead — the empty intent is lost silently.

### Right

```bash
# nosec-extract
make_file() {
    local ext="${2-.md}"    # ${2-X} substitutes X ONLY when $2 is UNSET; "" is honoured
    [ -n "$ext" ] && { mv "$f" "$f$ext"; f="$f$ext"; }
    ...
}
make_file 360000 ""         # ext="" → no extension, as intended
make_file 360000            # $2 unset → ext=".md" default
```

Drop the colon (`${var-default}`) whenever an empty value is a meaningful case
distinct from "argument omitted". Same rule applies to `${var:=default}` vs
`${var=default}` and `${var:+alt}` vs `${var+alt}`.

### Why this matters in practice

A test helper used `${2:-.md}` and a passthrough case called it with `""` to build
an extension-less fixture. The fixture silently became a `.md` file, so the gate
under test (which keys on extension) fired on it — and the test reported a defect in
the gate when the bug was the helper's parameter expansion. One character (`:`) cost
a probe cycle to disambiguate "is this a real gate bug or a test artefact?".
