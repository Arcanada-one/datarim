#!/bin/bash
# Deploy a static website to server
# Usage: ./deploy.sh <domain> [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER="root@SERVER_IP"
SSH_KEY="$HOME/.ssh/id_ed25519"

# Map domain to server webroot (when they differ)
resolve_webroot() {
    case "$1" in
        # example.com) echo "example" ;;
        *) echo "$1" ;;
    esac
}

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <domain> [--dry-run]"
    echo ""
    echo "Available sites:"
    for d in "$SCRIPT_DIR"/*/; do
        [ -d "$d" ] && echo "  $(basename "$d")"
    done
    exit 1
fi

DOMAIN="$1"
DRY_RUN=""
[ "${2:-}" = "--dry-run" ] && DRY_RUN="--dry-run"

SOURCE_DIR="$SCRIPT_DIR/$DOMAIN"
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Directory $SOURCE_DIR not found"
    exit 1
fi

REMOTE_DIR=$(resolve_webroot "$DOMAIN")

echo "Deploying $DOMAIN -> $SERVER:/var/www/$REMOTE_DIR/"
rsync -avz --delete $DRY_RUN \
    --exclude='.DS_Store' \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='*.py' \
    --exclude='__pycache__' \
    -e "ssh -i $SSH_KEY" \
    "$SOURCE_DIR/" "$SERVER:/var/www/$REMOTE_DIR/"

echo "Done: $DOMAIN deployed"