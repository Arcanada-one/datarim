#!/bin/bash
# Datarim Framework Installer
# Installs agents, skills, commands, and templates to ~/.claude/
#
# Usage:
#   ./install.sh          # Merge mode (skip existing files)
#   ./install.sh --force  # Overwrite existing files

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
FORCE=false
COPIED=0
SKIPPED=0

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE=true
fi

VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
echo "Datarim Framework Installer v$VERSION"
echo "================================="
echo ""
echo "Source:  $SCRIPT_DIR"
echo "Target:  $CLAUDE_DIR"
echo "Mode:    $([ "$FORCE" = true ] && echo "force (overwrite)" || echo "merge (skip existing)")"
echo ""

# Create target directories
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/templates"

# Copy function with merge/force logic
copy_files() {
    local src_dir="$1"
    local dst_dir="$2"
    local category="$3"

    local count=0
    for f in "$src_dir"/*.md; do
        [ -f "$f" ] || continue
        local basename
        basename=$(basename "$f")

        if [ "$FORCE" = false ] && [ -f "$dst_dir/$basename" ]; then
            echo "  SKIP (exists): $basename"
            SKIPPED=$((SKIPPED + 1))
        else
            cp "$f" "$dst_dir/$basename"
            echo "  COPY: $basename"
            COPIED=$((COPIED + 1))
        fi
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        echo "  (no files found in $src_dir)"
    fi
}

# Install each component
echo "Installing agents..."
copy_files "$SCRIPT_DIR/agents" "$CLAUDE_DIR/agents" "agents"
echo ""

echo "Installing skills..."
copy_files "$SCRIPT_DIR/skills" "$CLAUDE_DIR/skills" "skills"
echo ""

echo "Installing commands..."
copy_files "$SCRIPT_DIR/commands" "$CLAUDE_DIR/commands" "commands"
echo ""

echo "Installing templates..."
copy_files "$SCRIPT_DIR/templates" "$CLAUDE_DIR/templates" "templates"
echo ""

# Summary
echo "================================="
echo "Done! Copied: $COPIED, Skipped: $SKIPPED"
echo ""
echo "Next steps:"
echo "  1. Copy CLAUDE.md to your project root:"
echo "     cp $SCRIPT_DIR/CLAUDE.md /path/to/your/project/"
echo ""
echo "  2. Customize the project-specific section at the bottom of CLAUDE.md"
echo ""
echo "  3. Start Claude Code and run: /dr-init <task description>"
echo ""

if [ "$SKIPPED" -gt 0 ] && [ "$FORCE" = false ]; then
    echo "Note: $SKIPPED file(s) were skipped because they already exist."
    echo "      Use --force to overwrite: ./install.sh --force"
    echo ""
fi
