---
name: bash-pitfalls
description: Recurring bash/shell traps that pass review and break in prod. Load when writing or reviewing any .sh, especially regex-heavy ops scripts.
---

# Bash Pitfalls — Quick Reference

Source incidents: a prior incident Phase 8 Step 1 (BUG #1, BUG #2 — both High, both regex/grep traps caught only by post-implementation QA, both 1-line fixable); a prior phase Round 1 (cutover smoke shape — Trap 6).

## The Six Traps

### 1. `grep -F` makes EVERY meta character literal

```bash
# WRONG — `^` is treated as a literal caret, never matches line-start.
grep -Fq "^${d} " "$file"

# RIGHT — drop -F if you need the anchor, or tokenise:
awk -v d="$d" '$1 == d { found=1; exit } END { exit !found }' "$file"
```

`-F` (`--fixed-strings`) disables ALL regex interpretation: `^`, `$`, `.`, `*`, `[…]`, `(…)`. If your pattern needs anchoring or character classes, do NOT combine with `-F`. Common false-fix: author adds `-F` for safety against shell-meta in `${var}`, silently destroying their own anchor.

### 2. Boundary-alternation regex `(^|[[:space:]])X` — fails on the typical case

```bash
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
echo "$payload" | python3 - <<'PY'
import sys
data = sys.stdin.read()  # gets the heredoc body, NOT "$payload"
PY
```

The pipe is silently ignored. Tests built around this pattern can pass for the wrong reason — the script processes the heredoc text as if it were the input.

### Right

Pass payload via environment variable, read with `os.environ`:

```bash
PAYLOAD="$payload" python3 -c '
import os
data = os.environ["PAYLOAD"]
'
```

Or use a here-string for stdin alongside an inline `-c` script (no heredoc):

```bash
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