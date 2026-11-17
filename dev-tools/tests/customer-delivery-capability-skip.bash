# Shared helpers for visible customer-delivery capability skips.
# Sourced by functional and mutation bats suites.

customer_delivery_passwordless_sudo_available() {
    command -v sudo >/dev/null 2>&1 || return 1
    sudo -n /usr/bin/true 2>/dev/null
}

# Record one capability skip for job summary + aggregate inventory.
# Line format (stable): customer-delivery-capability-skip <name> <reason>
customer_delivery_record_capability_skip() {
    local name="${1:?capability skip name required}"
    local reason="${2:?capability skip reason required}"
    local line
    line="customer-delivery-capability-skip ${name} ${reason}"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        printf '%s\n' "$line" >>"$GITHUB_STEP_SUMMARY"
    fi
    if [[ -n "${CUSTOMER_DELIVERY_SKIP_LOG:-}" ]]; then
        mkdir -p "$(dirname -- "$CUSTOMER_DELIVERY_SKIP_LOG")" 2>/dev/null || true
        printf '%s\n' "$line" >>"$CUSTOMER_DELIVERY_SKIP_LOG"
    fi
    printf '%s\n' "$line"
}
