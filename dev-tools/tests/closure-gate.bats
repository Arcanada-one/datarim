#!/usr/bin/env bats
# closure-gate.bats — a task must not be markable `done` while the work it
# claims is absent from canonical `origin/main`.
#
# Derived from the TUNE-0541 sweep, in which 22 backlog entries read `done`
# while every one of them had unmerged content. Each scenario below is a shape
# actually observed in that sweep.

setup() {
  GATE="${BATS_TEST_DIRNAME}/../closure-gate.sh"
  TMP="$(mktemp -d)"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  REPO="$TMP/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name tester
  git -C "$REPO" config commit.gpgsign false

  mkdir -p "$REPO/dev-tools"
  printf 'base\n' > "$REPO/base.txt"
  printf '#!/bin/sh\necho existing\n' > "$REPO/dev-tools/existing.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "base"

  # a stand-in for origin/main that the gate can resolve without a network
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
}

teardown() { rm -rf "$TMP"; }

# advance origin/main by one commit, so the branch is never simply "main"
advance_main() {
  git -C "$REPO" checkout -q main
  printf 'unrelated\n' >> "$REPO/base.txt"
  git -C "$REPO" commit -qam "unrelated main advance"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD
}

# ---------------------------------------------------------------------------
# FAIL shapes — work is genuinely absent from main
# ---------------------------------------------------------------------------

@test "fails when the branch adds a file main lacks (TUNE-0191 shape)" {
  git -C "$REPO" checkout -qb feat
  printf '#!/bin/sh\necho gate\n' > "$REPO/dev-tools/check-frontmatter-mirror.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: add mirror gate"
  advance_main

  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 1 ]
  [[ "$output" == *"check-frontmatter-mirror.sh"* ]]
}

@test "fails when the branch only MODIFIES a file and that content is absent (TUNE-0153/0367/0385 shape)" {
  # the shape the brief misread as landed: --diff-filter=A yields zero
  git -C "$REPO" checkout -qb feat
  printf 'BRAND_HYGIENE_POLICY_MARKER\n' >> "$REPO/dev-tools/existing.sh"
  git -C "$REPO" commit -qam "feat: brand-hygiene policy"
  advance_main

  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 1 ]
  [[ "$output" == *"BRAND_HYGIENE_POLICY_MARKER"* ]]
}

@test "added-file count alone would pass the modify-only shape — the gate must not rely on it" {
  git -C "$REPO" checkout -qb feat
  printf 'BRAND_HYGIENE_POLICY_MARKER\n' >> "$REPO/dev-tools/existing.sh"
  git -C "$REPO" commit -qam "feat: brand-hygiene policy"
  advance_main

  # the naive signal the brief used, asserted red so the fixture stays honest
  added="$(git -C "$REPO" diff --diff-filter=A --name-only origin/main..feat | wc -l)"
  [ "$added" -eq 0 ]

  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 1 ]
}

@test "fails when main merely MENTIONS the task id without carrying the work (TUNE-0321 shape)" {
  git -C "$REPO" checkout -qb feat
  printf 'ECONOMICS_RESILIENCE_MARKER\n' >> "$REPO/dev-tools/existing.sh"
  git -C "$REPO" commit -qam "feat(TUNE-0321): economics resilience"

  # main gains an unrelated commit whose message forward-references the id
  git -C "$REPO" checkout -q main
  printf 'other\n' >> "$REPO/base.txt"
  git -C "$REPO" commit -qam "feat: unrelated work (tracked as TUNE-0321)"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD

  run "$GATE" --root "$REPO" --branch feat --task TUNE-0321
  [ "$status" -eq 1 ]
  [[ "$output" == *"ECONOMICS_RESILIENCE_MARKER"* ]]
}

# ---------------------------------------------------------------------------
# PASS shapes — work IS in main
# ---------------------------------------------------------------------------

@test "passes when the branch was SQUASH-merged (evidence commit unreachable by design)" {
  # The decisive case. Datarim's main requires signed commits and merges via
  # squash, so the branch's own commits are never ancestors of main. A gate
  # asserting ancestry of the evidence sha fails every correctly merged task.
  git -C "$REPO" checkout -qb feat
  printf '#!/bin/sh\necho gate\n' > "$REPO/dev-tools/new-gate.sh"
  printf 'MODIFIED_MARKER\n' >> "$REPO/dev-tools/existing.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: new gate"
  evidence="$(git -C "$REPO" rev-parse HEAD)"

  git -C "$REPO" checkout -q main
  git -C "$REPO" merge --squash feat >/dev/null 2>&1
  git -C "$REPO" commit -qm "feat: new gate (#123)"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD

  # the evidence commit is genuinely NOT an ancestor — the ancestry gate's premise
  run git -C "$REPO" merge-base --is-ancestor "$evidence" origin/main
  [ "$status" -ne 0 ]

  # ...yet the content is present, so closure is legitimate
  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 0 ]
}

@test "passes on a LARGE base tree — no SIGPIPE false positive (regression)" {
  # Regression for a pipefail + `grep -q` defect: `grep -q` exits on first match
  # and closes the pipe, so an upstream `printf`/`awk` dies with SIGPIPE (141)
  # and `set -o pipefail` reports the successful match as a failure. Small
  # fixtures hide it because the whole stream fits in the pipe buffer; the bug
  # only appears once the base tree is big enough to still be writing. Observed
  # against the real repository, where two genuinely-landed gates
  # (check-qa-verdict-blocked.sh, check-archive-sha-chain.sh) were reported absent.
  # The remainder AFTER the matching path must exceed the 64 KB pipe buffer,
  # otherwise the upstream process finishes writing before `grep -q` exits and
  # no SIGPIPE occurs. `zzz/` sorts after `dev-tools/`, and the names are long
  # on purpose: ~3000 paths of ~70 bytes is ~200 KB of post-match output.
  mkdir -p "$REPO/zzz"
  for i in $(seq 1 3000); do
    printf 'filler\n' > "$REPO/zzz/a-rather-long-filler-path-name-component-$i.txt"
  done
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "bulk"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD

  git -C "$REPO" checkout -qb feat
  printf 'CONTENT_V1\n' > "$REPO/dev-tools/landed-gate.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: add gate"

  # the gate lands on main under the same path but with later edits, so the
  # blob differs and the basename branch of the check is what must succeed
  git -C "$REPO" checkout -q main
  printf 'CONTENT_V1\nCONTENT_V2_FOLLOWUP\n' > "$REPO/dev-tools/landed-gate.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: add gate (#1) plus follow-up fix"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD

  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 0 ]
}

@test "passes when the work landed under a RENAMED path" {
  git -C "$REPO" checkout -qb feat
  printf 'RENAMED_CONTENT_MARKER\n' > "$REPO/dev-tools/old-name.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: add tool"

  git -C "$REPO" checkout -q main
  printf 'RENAMED_CONTENT_MARKER\n' > "$REPO/dev-tools/new-name.sh"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "feat: add tool under final name"
  git -C "$REPO" update-ref refs/remotes/origin/main HEAD

  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------

@test "usage error when --branch is absent" {
  run "$GATE" --root "$REPO"
  [ "$status" -eq 2 ]
}

@test "fails closed when origin/main cannot be resolved" {
  git -C "$REPO" checkout -qb feat
  git -C "$REPO" update-ref -d refs/remotes/origin/main
  run "$GATE" --root "$REPO" --branch feat
  [ "$status" -eq 2 ]
  [[ "$output" == *"origin/main"* ]]
}

@test "wiring: CI enumerates this suite, and every route to done invokes the gate" {
  # Measured 2026-07-30: deleting closure-gate.sh AND this suite outright left
  # `bats tests/ (full)` (2492/2492), `bats self-tests`, `doc-refs` and
  # `dr-auto reassert-wiring` all green. A gate nothing runs is a paragraph,
  # not a gate. The assertions below are the anti-decay wiring.
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

  # 1. dev-tools/tests/*.bats is NOT swept by `bats tests/` — the CI job
  #    enumerates files, so an unlisted suite runs nowhere at all.
  WF="$ROOT/.github/workflows/dev-tools-lint.yml"
  [ -f "$WF" ]
  run grep -c 'bats dev-tools/tests/closure-gate.bats' "$WF"
  [ "$status" -eq 0 ]

  # 2. Every command that may flip a task to `done` must invoke the gate first.
  #    `/dr-archive` was wired at birth; `/dr-quick` writes a short archive and
  #    flips `tasks.md` to `done` on its own authority, so an unwired fast-lane
  #    is a complete bypass of the slow lane's gate.
  for cmd in dr-archive dr-quick; do
    DOC="$ROOT/commands/$cmd.md"
    [ -f "$DOC" ]
    run grep -c 'dev-tools/closure-gate.sh' "$DOC"
    [ "$status" -eq 0 ]
  done
}
