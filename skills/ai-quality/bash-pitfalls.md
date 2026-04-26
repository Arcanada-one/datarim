---
name: bash-pitfalls
description: Recurring bash/shell traps that pass review and break in prod. Load when writing or reviewing any .sh, especially regex-heavy ops scripts.
---

# Bash Pitfalls — Quick Reference

Source incidents: DEV-1174 Phase 8 Step 1 (BUG #1, BUG #2 — both High, both regex/grep traps caught only by post-implementation QA, both 1-line fixable).

## The Five Traps

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

## Mandatory Workflow Rule for /dr-do

When implementing or modifying any `.sh` file:

1. Run `shellcheck -S warning <file>` before declaring the work complete. If `shellcheck` is not installed, install via `brew install shellcheck` / `apt install shellcheck` — it's not optional for ops scripts.
2. Re-read every `grep` / `sed` / `awk` you wrote with one question: "what does the regex engine actually see after shell expansion?"
3. For any whole-token / whole-word match against shell-quoted user data, prefer `awk` token comparison (`$N == d`) over regex word-boundary alternation — it's shorter, clearer, and meta-safe.
4. For any password / secret on the `mysql` / `mysqldump` / `psql` / `redis-cli` command line, use `--defaults-extra-file=` (or stdin) — never `-p"$pass"`.

## Why this fragment exists

DEV-1174 Phase 8 Step 1 shipped two High-severity bugs to QA, both of which are textbook regex/grep traps and both of which would have been caught by either (a) a 5-second mental "what does the regex engine see?" check, or (b) shellcheck with extended pattern checks. The fix in both cases was to abandon the regex and use `awk` token-equality. This fragment encodes the lesson so future ops-script work doesn't repeat it.