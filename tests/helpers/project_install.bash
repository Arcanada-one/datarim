setup_project_fixture() {
    PRODUCT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    PROJECT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$HOME" "$PROJECT"
    # Scripted fresh installs use the CI escape hatch; tests of the answers
    # token unset it.
    export DATARIM_INSTALL_NONINTERACTIVE=1
}

install_project() {
    run sh "$PRODUCT_ROOT/install.sh" --project "$PROJECT" "$@"
}
