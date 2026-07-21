#!/usr/bin/env bats
# datarim-doctor-nonascii-scope-all.bats
# Regression: `datarim-doctor.sh --scope=all` must not crash on non-ASCII
# operator files or a wiki/_raw_ file with multibyte content.
#
# Two original failure modes (both platform-specific):
#   (1) BSD `tr` under a UTF-8 locale aborts with "tr: Illegal byte sequence"
#       when `head -c 300` splits a multibyte UTF-8 codepoint mid-character.
#   (2) bash 3.2 under `set -u` raises "unbound variable" on an empty-array
#       expansion `"${tok_array[@]}"` (basename with no ASCII alnum token).
#
# PLATFORM NOTE: neither reproduces on GNU coreutils `tr` (>=8) or bash (>=4.4),
# so on a modern Linux CI host the behavioural exit-0/1 assertion is a smoke
# test that passes both before and after the fix — it is the real guard only on
# macOS bash-3.2 / BSD tr. The two mechanism-assertion tests below verify the
# fix is structurally present (LC_ALL=C on both tr pipelines + ${tok_array[@]:-}
# guard) and therefore catch a regression on ANY platform.

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks" "$TMPROOT/wiki/_raw_"
}

teardown() {
    rm -rf "$TMPROOT"
}

@test "scope=all: non-ASCII operator file + wiki/_raw_ multibyte content → no crash (exit 0/1)" {
    # Non-ASCII operator file (exercises the non-wiki scan passes).
    printf '# Активный контекст\n- Датарим проверка\n' > "$TMPROOT/datarim/activeContext.md"

    # wiki/_raw_ file whose byte-300 boundary splits a 2-byte Cyrillic codepoint:
    # 285 ASCII 'a' then a Cyrillic run, so head -c 300 cuts mid-character.
    { printf 'a%.0s' $(seq 1 285); printf 'Пример многобайтового содержимого рядом с границей\n'; } \
        > "$TMPROOT/wiki/_raw_/topic-note.md"

    # wiki/_raw_ file with an all-non-ASCII basename → empty token array path.
    printf 'english body that will not match the cyrillic basename\n' \
        > "$TMPROOT/wiki/_raw_/Заметка.md"

    run env LC_ALL=en_US.UTF-8 "$DOCTOR" --root="$TMPROOT/datarim" --scope=all
    # A clean diagnostic exit (0 compliant / 1 findings) — never a crash.
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" != *"Illegal byte sequence"* ]]
    [[ "$output" != *"unbound variable"* ]]
}

@test "mechanism: both tr pipelines in the wiki/_raw_ scanner run byte-mode (LC_ALL=C)" {
    # NB: exact-string grep — intentionally tight so a dropped LC_ALL=C fails
    # here on any host. A semantically-equivalent refactor (function-scope
    # `export LC_ALL=C`, reordered tr stages, extracted helper) would also fail
    # this and must be paired with an update to these assertions.
    # Case-fold of the basename stem and of the first 300 content bytes.
    run grep -F "printf '%s' \"\$stem\" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c '[:alnum:]' ' '" "$DOCTOR"
    [ "$status" -eq 0 ]
    run grep -F "head -c 300 \"\$f\" 2>/dev/null | LC_ALL=C tr '[:upper:]' '[:lower:]'" "$DOCTOR"
    [ "$status" -eq 0 ]
}

@test "mechanism: tok_array expansion is guarded with the :- default (empty-array safe under set -u)" {
    run grep -F '"${tok_array[@]:-}"' "$DOCTOR"
    [ "$status" -eq 0 ]
}
