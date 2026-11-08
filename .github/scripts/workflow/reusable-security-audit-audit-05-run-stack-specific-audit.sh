#!/usr/bin/env bash
set -euo pipefail
case "$STACK" in
  typescript_pnpm)
    echo "::group::typescript_pnpm audit"
    # Provision pnpm WITHOUT a privileged global write. `corepack enable`
    # (no args) writes shims into the node bin dir (often root-owned
    # /usr/bin) -> EACCES on runners where the runner user lacks that
    # write (e.g. arca-devs). Pin the shim dir to a runner-writable path
    # so the job is deterministic across runner variance.
    mkdir -p "$RUNNER_TEMP/corepack-bin"
    corepack enable --install-directory "$RUNNER_TEMP/corepack-bin"
    export PATH="$RUNNER_TEMP/corepack-bin:$PATH"
    pnpm install --frozen-lockfile --ignore-scripts
    pnpm audit --audit-level="$AUDIT_LEVEL" --prod
    echo "::endgroup::"
    ;;
  rust_cargo)
    echo "::group::rust_cargo audit"
    cargo install --locked cargo-audit cargo-deny
    cargo audit --deny warnings
    cargo deny check advisories licenses
    echo "::endgroup::"
    ;;
  python)
    echo "::group::python audit"
    # INFRA-0365: was `python`, which is absent on every runner host
    # (only python3 is installed) — this profile could never have run.
    python3 -m pip install --disable-pip-version-check 'pip-audit==2.10.1'
    pip-audit -s osv --strict
    echo "::endgroup::"
    ;;
  framework)
    echo "::group::framework audit"
    if [ -f package.json ] || [ -f Cargo.toml ] || [ -f requirements.txt ] || [ -f pyproject.toml ]; then
      echo "framework profile selected but stack manifest detected — choose a stack profile"
      exit 1
    fi
    echo "no runtime manifests — shellcheck sweep only"
    # INFRA-0365: this was wrapped in `if command -v shellcheck`, so on
    # a runner without shellcheck the gate audited NOTHING and reported
    # success. shellcheck is now provisioned and asserted above, so the
    # sweep always runs.
    find . -type f -name '*.sh' -not -path './.datarim/*' \
      -print0 | xargs -0 -r shellcheck -S warning
    ;;
  *)
    echo "ERROR: unknown stack profile: $STACK" >&2
    exit 1
    ;;
esac
