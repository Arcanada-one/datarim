#!/usr/bin/env bash
# reusable-security-audit job body: clone Datarim gate scripts then run audit steps.
set -euo pipefail
DATARIM_REF="${DATARIM_REF:-main}"
STACK="${STACK:?STACK required}"
AUDIT_LEVEL="${AUDIT_LEVEL:-}"
ACCEPTED_RISK_PATH="${ACCEPTED_RISK_PATH:-}"

rm -rf .datarim
git clone https://github.com/Arcanada-one/datarim.git .datarim
git -C .datarim checkout --force "$DATARIM_REF"

# --- step ---
bash ./.datarim/dev-tools/check-security-policy.sh --check --repo .


# --- step ---
if [ -f "$ACCEPTED_RISK_PATH" ]; then
  bash ./.datarim/dev-tools/check-security-policy.sh \
    --validate-yaml "$ACCEPTED_RISK_PATH"
else
  echo "accepted-risk.yml not present at $ACCEPTED_RISK_PATH — skipping schema validation"
fi


# --- step ---
if command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck already present: $(command -v shellcheck)"
  exit 0
fi
ver="v0.10.0"
curl -sSfL "https://github.com/koalaman/shellcheck/releases/download/${ver}/shellcheck-${ver}.linux.x86_64.tar.xz" \
  | tar -xJ -C "$RUNNER_TEMP" "shellcheck-${ver}/shellcheck" --strip-components=1
chmod +x "$RUNNER_TEMP/shellcheck"
echo "$RUNNER_TEMP" >> "$GITHUB_PATH"
echo "shellcheck ${ver} provisioned to RUNNER_TEMP"


# --- step ---
case "$STACK" in
  typescript_pnpm) required="node corepack" ;;
  rust_cargo)      required="cargo" ;;
  python)          required="python3" ;;
  framework)       required="shellcheck" ;;
  *) echo "ERROR: unknown stack profile: $STACK" >&2; exit 1 ;;
esac
missing=""
for bin in $required; do
  command -v "$bin" >/dev/null 2>&1 || missing="$missing $bin"
done
if [ -n "$missing" ]; then
  echo "ERROR: stack '$STACK' requires:$missing" >&2
  echo "       runner '${RUNNER_NAME:-unknown}' does not provide them, and the" >&2
  echo "       provisioning step above did not supply them either." >&2
  echo "       This gate must never pass without actually auditing." >&2
  exit 1
fi
echo "toolchain OK for '$STACK' on runner '${RUNNER_NAME:-unknown}':$(for b in $required; do printf ' %s=%s' "$b" "$(command -v "$b")"; done)"


# --- step ---
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


# --- step ---
echo "audit complete"

