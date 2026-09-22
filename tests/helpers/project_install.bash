setup_project_fixture() {
    PRODUCT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$HOME" "$PROJECT"
}

install_project() {
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" "$@"
}
