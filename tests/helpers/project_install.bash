setup_project_fixture() {
    PRODUCT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$HOME" "$PROJECT"
}

install_project() {
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" "$@"
}

# The token from a refusal's "Rerun with the user's answers: ... --answers <TOKEN> <flags>" line.
answers_token() {
    printf '%s\n' "$1" | sed -n 's/.*--answers \([0-9a-f][0-9a-f]*\) <flags>.*/\1/p' | tail -n 1
}

# A scripted install the way CI does it: run once; on a refusal that printed
# a token, rerun with the same answers and that token.
install_answered() {
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" "$@"
    if [ "$status" -eq 2 ]; then
        token="$(answers_token "$output")"
        if [ -n "$token" ]; then
            run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" --answers "$token" "$@"
        fi
    fi
}
