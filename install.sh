#!/usr/bin/env bash
# Datarim Framework Installer
# Installs agents, skills, commands, and templates into $CLAUDE_DIR (~/.claude).
#
# Operating model (v1.17.0, TUNE-0033):
#   Default mode is SYMLINK — the four scope directories in $CLAUDE_DIR
#   (agents/skills/commands/templates) become symlinks to $SCRIPT_DIR/<scope>/.
#   This makes the repo the runtime: edits land in git tracking immediately
#   and curation/drift detection are no-ops by definition. Use --copy to
#   preserve the legacy v1.16 behaviour (real file copies).
#
# Contract (TUNE-0004 aligned with PRD-datarim-sdlc-framework §4 — copy mode):
#   - Install scopes (distributed to runtime): agents, skills, commands, templates.
#   - Installed scopes (whole-dir symlink under default mode): agents/, skills/,
#     commands/, templates/, scripts/ (since v1.20.0 TUNE-0077), tests/ (since
#     v1.20.0 TUNE-0077). Repo-only: validate.sh (single root file).
#   - Content types copied: .md .sh .json .yaml .yml. Unknown extensions are
#     logged (WARN) and skipped — never silently dropped.
#   - .sh files receive +x after copy.
#   - --force is guarded: on a live $CLAUDE_DIR it requires interactive "yes"
#     confirmation or --yes / $DATARIM_INSTALL_YES and always creates a
#     timestamped backup under $CLAUDE_DIR/backups/force-<ISO>/ with a
#     SUCCESS marker written only after a complete copy.
#
# Local overlay (v1.17.0): $CLAUDE_DIR/local/{skills,agents,commands,templates}/
# is created (empty + .gitignore) for user-private skills/agents that override
# framework files of the same name. Loader policy: local wins, validate.sh WARN.
#
# Usage:
#   ./install.sh                 # symlink mode (default, repo == runtime)
#   ./install.sh --copy          # legacy copy mode (real files)
#   ./install.sh --force         # force re-install (copy mode only)
#   ./install.sh --force --yes   # overwrite without prompt (CI / scripted)
#   ./install.sh --help          # print usage and exit
#
# Environment:
#   CLAUDE_DIR                target runtime dir (default: $HOME/.claude)
#   DATARIM_INSTALL_YES=1     same as --yes (for CI / migration auto-consent)
#
# Test hooks (not user-facing, used by bats suite):
#   DATARIM_FORCE_UNAME       override `uname -s` (e.g. MINGW64_NT-10) to
#                             exercise the Windows copy-fallback path
#   DATARIM_MIGRATION_CHOICE  pre-answer the c|k|a migration prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR-$HOME/.claude}"
DATARIM_INSTALL_YES="${DATARIM_INSTALL_YES:-}"
DATARIM_FORCE_UNAME="${DATARIM_FORCE_UNAME:-}"
DATARIM_MIGRATION_CHOICE="${DATARIM_MIGRATION_CHOICE:-}"

# Install scopes — must match scripts/check-drift.sh SCOPES (AC-3).
# v1.20.0 (TUNE-0077): scripts and tests added — uniform whole-directory symlink
# semantics. Eliminates drift between canonical Datarim repo and ~/.claude/
# runtime (a 730-LoC rogue datarim-doctor.sh placed directly into ~/.claude/
# scripts/ destroyed 30 task entries on aether/local-env 2026-04-30). With
# dir-symlink, ~/.claude/scripts/datarim-doctor.sh is the canonical file by
# inode — no possibility of divergence. Symmetric with skills/agents pattern.
# Note: 'dev-tools' is intentionally NOT in this list — see
# code/datarim/dev-tools/README.md (developer-only tooling, not shipped
# to consumers; TUNE-0091).
INSTALL_SCOPES=(agents skills commands templates scripts tests)

# v1.17.0: local/ overlay scope dirs (TUNE-0033). Local overlay applies only to
# user-extensible scopes (skills/agents/commands/templates) — scripts/tests are
# framework-internal and not extended via local/.
LOCAL_SCOPES=(skills agents commands templates)

# Content-type whitelist. Extending this list is a deliberate act: review the
# repo for new content, decide what deploys, update here and in docs.
INSTALL_EXTENSIONS=(md sh json yaml yml)

FORCE=false
FORCE_COPY=false           # v1.17.0: --copy flag → forces copy mode
ASSUME_YES=false
INSTALL_MODE="symlink"     # set by detect_install_mode in main
COPIED=0
LINKED=0
SKIPPED=0

# TUNE-0114 Phase 2: multi-runtime fanout + project mode
FANOUT_CLAUDE=false
FANOUT_CODEX=false
PROJECT_DIR=''
DRY_RUN=false
LOCKFILE=''

print_usage() {
    cat <<'USAGE'
Datarim Framework Installer

Usage:
  install.sh --with-claude          Install for Claude runtime (symlink default)
  install.sh --with-codex           Install for Codex runtime
  install.sh --project DIR          Project-local copy install (no symlinks)
  install.sh --with-claude --with-codex  Multi-runtime install
  install.sh --dry-run              Show planned mutations without applying
  install.sh --copy                 Legacy copy mode (real files instead of symlinks)
  install.sh --force                Legacy force re-install (copy mode only — no-op on symlinks)
  install.sh --force --yes          Overwrite without prompt (CI / scripted)
  install.sh --help                 Show this message

Environment:
  CLAUDE_DIR                        Target directory (default: $HOME/.claude)
  DATARIM_INSTALL_YES=1             Equivalent to --yes (also auto-converts copy → symlink)

Migration:
  Existing copy-mode installs upgrade to symlinks via interactive prompt
  ([c]onvert / [k]eep / [a]bort). With --yes the choice defaults to [c].
USAGE
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)     FORCE=true; shift ;;
            --copy)      FORCE_COPY=true; shift ;;
            --yes|-y)    ASSUME_YES=true; shift ;;
            --with-claude) FANOUT_CLAUDE=true; shift ;;
            --with-codex)  FANOUT_CODEX=true; shift ;;
            --project)
                if [ $# -lt 2 ]; then
                    echo "ERROR: --project requires an argument" >&2
                    exit 2
                fi
                PROJECT_DIR="$2"; shift 2
                ;;
            --dry-run)   DRY_RUN=true; shift ;;
            --help|-h)   print_usage; exit 0 ;;
            *)
                echo "ERROR: unknown argument: $1" >&2
                print_usage >&2
                exit 2
                ;;
        esac
    done
}

# --- Platform detection ----------------------------------------------------

# Read uname -s (with DATARIM_FORCE_UNAME test hook).
get_uname() {
    if [ -n "$DATARIM_FORCE_UNAME" ]; then
        echo "$DATARIM_FORCE_UNAME"
        return
    fi
    uname -s 2>/dev/null || echo "unknown"
}

# Determine install mode. Returns "symlink" or "copy" on stdout.
# Decision order:
#   1. --copy flag → copy.
#   2. Windows shells (MINGW*, MSYS*, CYGWIN*) → copy (silent fallback).
#   3. Runtime probe: ln -s succeeds → symlink, else copy.
detect_install_mode() {
    if [ "$FORCE_COPY" = true ]; then
        echo "copy"; return
    fi
    case "$(get_uname)" in
        MINGW*|MSYS*|CYGWIN*)
            echo "copy"; return
            ;;
    esac
    local probe="${TMPDIR:-/tmp}/datarim-symlink-probe-$$"
    mkdir -p "$probe"
    if ln -s /etc/hosts "$probe/link" 2>/dev/null && [ -L "$probe/link" ]; then
        rm -rf "$probe"
        echo "symlink"
    else
        rm -rf "$probe"
        echo "copy"
    fi
}

# Inspect $CLAUDE_DIR scopes and report topology:
#   none     all 4 scopes absent
#   symlink  all 4 scopes are symlinks
#   copy     all 4 scopes are real directories
#   mixed    some symlinks + some real dirs (abort signal)
detect_existing_topology() {
    local scope present_count=0 symlink_count=0 dir_count=0
    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -L "$CLAUDE_DIR/$scope" ]; then
            symlink_count=$((symlink_count + 1))
            present_count=$((present_count + 1))
        elif [ -d "$CLAUDE_DIR/$scope" ]; then
            dir_count=$((dir_count + 1))
            present_count=$((present_count + 1))
        fi
    done
    if [ "$present_count" -eq 0 ]; then echo "none"; return; fi
    if [ "$symlink_count" -gt 0 ] && [ "$dir_count" -gt 0 ]; then
        echo "mixed"; return
    fi
    if [ "$symlink_count" -gt 0 ]; then echo "symlink"; return; fi
    echo "copy"
}

# --- Safety helpers ---------------------------------------------------------

is_live_system() {
    local scope
    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -d "$CLAUDE_DIR/$scope" ] && [ -n "$(ls -A "$CLAUDE_DIR/$scope" 2>/dev/null)" ]; then
            return 0
        fi
    done
    return 1
}

assert_claude_dir_safe() {
    # Reject catastrophic targets. The installer never uses `rm -rf`, so even
    # if this guard somehow passed a bad value the damage is bounded to copy/
    # mkdir operations — but fail-closed is the rule.
    if [ -z "$CLAUDE_DIR" ] || [ "$CLAUDE_DIR" = "/" ] || [ "$CLAUDE_DIR" = "$HOME" ]; then
        echo "ERROR: CLAUDE_DIR is unsafe: '$CLAUDE_DIR'" >&2
        echo "       Must be a dedicated directory (e.g. \$HOME/.claude), not /, empty, or \$HOME itself." >&2
        exit 2
    fi
}

force_safety_guard() {
    assert_claude_dir_safe

    # v1.17.0 (TUNE-0033 AC-5): under existing symlink topology --force is a
    # semantic no-op — the runtime IS the repo. Bail out before any backup.
    local s already_symlinked=true
    for s in "${INSTALL_SCOPES[@]}"; do
        if [ ! -L "$CLAUDE_DIR/$s" ]; then
            already_symlinked=false; break
        fi
    done
    if [ "$already_symlinked" = true ] && [ "$INSTALL_MODE" = "symlink" ]; then
        echo "Already symlinked to $SCRIPT_DIR — nothing to update."
        echo "Run 'cd $SCRIPT_DIR && git pull' or './update.sh' to fetch upstream changes."
        exit 0
    fi

    # Symlink-mode + existing real-copy: migration_prompt creates its own
    # migrate-<ts> backup atomically via mv. Skip the legacy create_backup
    # path so we don't double-backup; consent is collected in migration_prompt.
    if [ "$INSTALL_MODE" = "symlink" ]; then
        return 0
    fi

    if ! is_live_system; then
        return 0  # fresh target — --force is safe, no backup needed.
    fi

    echo "WARNING: --force on a live system will overwrite $CLAUDE_DIR"
    echo "         TUNE-0003 incident: --force previously destroyed 9 runtime evolutions."
    echo ""

    if [ "$ASSUME_YES" = true ] || [ -n "$DATARIM_INSTALL_YES" ]; then
        echo "Auto-consent via --yes / DATARIM_INSTALL_YES."
    else
        if [ ! -t 0 ]; then
            echo "ERROR: non-TTY environment — refuse to prompt without --yes." >&2
            echo "       Re-run with --yes (or DATARIM_INSTALL_YES=1) if this is intentional." >&2
            exit 1
        fi
        printf "Type 'yes' to proceed (anything else aborts): "
        read -r confirm
        confirm="${confirm%$'\r'}"
        if [ "$confirm" != "yes" ]; then
            echo "Aborted by user."
            exit 1
        fi
    fi

    create_backup
}

create_backup() {
    local ts backup_dir scope
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    backup_dir="$CLAUDE_DIR/backups/force-$ts"
    mkdir -p "$backup_dir"

    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -d "$CLAUDE_DIR/$scope" ]; then
            cp -R "$CLAUDE_DIR/$scope" "$backup_dir/"
        fi
    done

    # Marker is written last — its presence signals a complete backup. Tests
    # and operators can rely on SUCCESS to distinguish a partial copy from a
    # usable snapshot.
    {
        echo "backup_created_at=$ts"
        echo "source=$CLAUDE_DIR"
        echo "scopes=${INSTALL_SCOPES[*]}"
    } > "$backup_dir/SUCCESS"

    echo "Backup created: $backup_dir"
    echo ""
}

# --- Copy logic -------------------------------------------------------------

has_allowed_extension() {
    local name="$1" ext allowed
    # Skip dotfiles and files with no extension.
    case "$name" in
        .*)       return 1 ;;
        *.*)      ext="${name##*.}" ;;
        *)        return 1 ;;
    esac
    for allowed in "${INSTALL_EXTENSIONS[@]}"; do
        if [ "$ext" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}

copy_scope_tree() {
    local src_dir="$1"
    local dst_dir="$2"
    local depth="${3:-0}"
    local count=0
    local entry bname

    mkdir -p "$dst_dir"

    for entry in "$src_dir"/*; do
        [ -e "$entry" ] || continue
        bname="$(basename "$entry")"

        # Paranoia: basename should never contain /, refuse if it does.
        case "$bname" in
            */*) echo "  SKIP (unsafe name): $bname" >&2; continue ;;
        esac

        if [ -d "$entry" ]; then
            echo "  DIR:  ${bname}/"
            copy_scope_tree "$entry" "$dst_dir/$bname" $((depth + 1))
            count=$((count + 1))
            continue
        fi

        if ! has_allowed_extension "$bname"; then
            case "$bname" in
                .*) : ;;  # silently ignore dotfiles (.DS_Store, editor temps)
                *)  echo "  WARN (unknown extension, skipped): $bname" ;;
            esac
            continue
        fi

        if [ "$FORCE" = false ] && [ -f "$dst_dir/$bname" ]; then
            echo "  SKIP (exists): $bname"
            SKIPPED=$((SKIPPED + 1))
        else
            cp "$entry" "$dst_dir/$bname"
            case "$bname" in
                *.sh) chmod +x "$dst_dir/$bname" 2>/dev/null || true ;;
            esac
            echo "  COPY: $bname"
            COPIED=$((COPIED + 1))
        fi
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ] && [ "$depth" -eq 0 ]; then
        echo "  (no files found in $src_dir)"
    fi
}

# --- v1.17.0 symlink + local overlay ----------------------------------------

# Create one symlink per scope: $CLAUDE_DIR/<scope> → $SCRIPT_DIR/<scope>.
# Idempotent: if the link already points at the right target, no-op.
# Refuses to overwrite a real directory without explicit migration consent.
link_scope_tree() {
    local src_dir="$1"   # absolute path to $SCRIPT_DIR/<scope>
    local dst_dir="$2"   # absolute path to $CLAUDE_DIR/<scope>
    local parent dst_name existing
    parent="$(dirname "$dst_dir")"
    dst_name="$(basename "$dst_dir")"
    mkdir -p "$parent"

    if [ -L "$dst_dir" ]; then
        existing="$(cd -P "$dst_dir" 2>/dev/null && pwd || echo "")"
        if [ "$existing" = "$src_dir" ]; then
            echo "  LINK (already): $dst_name → $src_dir"
            return
        fi
        rm "$dst_dir"
    elif [ -e "$dst_dir" ]; then
        echo "  ERROR: $dst_dir exists as a real directory; refuse to overwrite without migration." >&2
        exit 1
    fi

    ln -s "$src_dir" "$dst_dir"
    echo "  LINK: $dst_name → $src_dir"
    LINKED=$((LINKED + 1))
}

# Create $CLAUDE_DIR/local/{skills,agents,commands,templates}/ + .gitignore
# + README.md. Idempotent. Files are created via direct cat (NOT
# copy_scope_tree) because the dotfile filter rejects .gitignore by design.
setup_local_overlay() {
    local local_root="$CLAUDE_DIR/local"
    mkdir -p "$local_root"
    local scope
    for scope in "${LOCAL_SCOPES[@]}"; do
        mkdir -p "$local_root/$scope"
    done
    if [ ! -f "$local_root/.gitignore" ]; then
        cat > "$local_root/.gitignore" <<'GI'
# Datarim local overlay — entire directory is user-private.
# Loader order (validate.sh): local/<scope>/foo.md overrides <scope>/foo.md.
*
!.gitignore
!README.md
GI
    fi
    if [ ! -f "$local_root/README.md" ]; then
        cat > "$local_root/README.md" <<'MD'
# Datarim Local Overlay

This directory holds personal additions and overrides for the four scopes:
`local/skills/`, `local/agents/`, `local/commands/`, `local/templates/`.

Files here override framework files of the same name. Convention: prefix
filenames with your namespace (e.g. `local/skills/my-company-style.md`)
to avoid accidental overrides.

Document any deliberate override here so future-you can tell what was intended.
MD
    fi
}

# Move existing copy-mode scopes into a backup directory, write a SUCCESS
# marker (with scopes_migrated field — see creative-TUNE-0033-migration-ux),
# then return so the caller can create symlinks. mv is atomic per scope:
# if a power-cut interrupts mid-loop the marker absence signals partial.
migrate_to_symlinks() {
    local ts backup scope
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    backup="$CLAUDE_DIR/backups/migrate-$ts"
    mkdir -p "$backup"
    for scope in "${INSTALL_SCOPES[@]}"; do
        if [ -e "$CLAUDE_DIR/$scope" ] && [ ! -L "$CLAUDE_DIR/$scope" ]; then
            mv "$CLAUDE_DIR/$scope" "$backup/$scope"
        fi
    done
    cat > "$backup/SUCCESS" <<MARKER
migrated_at=$ts
source=$CLAUDE_DIR
scopes_migrated=$(IFS=,; echo "${INSTALL_SCOPES[*]}")
script_dir=$SCRIPT_DIR
MARKER
    echo "Backup: $backup"
}

# Show 3-option migration prompt to upgrading copy-mode users. Side effects:
#   c → migrate_to_symlinks (caller continues to symlink creation)
#   k → set INSTALL_MODE=copy globally (caller falls through to copy branch)
#   a → exit 1
# Auto-consent paths (logged distinctly per security recommendation):
#   ASSUME_YES (--yes)            → c
#   DATARIM_INSTALL_YES (env)     → c
#   DATARIM_MIGRATION_CHOICE      → c|k|a (test hook)
# Non-TTY without any auto-consent → exit 1 with explicit error.
migration_prompt() {
    cat <<EOF
v1.17.0 introduces symlink-default install mode (TUNE-0033).

Found existing real-copy installation in $CLAUDE_DIR/.

Options:
  [c] Convert to symlinks (recommended)
       Existing files moved to \$CLAUDE_DIR/backups/migrate-<ts>/
       Future updates run via 'git pull' inside the repo — no copy step.

  [k] Keep copy mode permanently
       Re-run install.sh --copy from now on.
       (Suitable for Windows / FAT filesystems / restricted shells.)

  [a] Abort
       No changes made. Re-run when ready.

EOF
    if [ "$ASSUME_YES" = true ]; then
        echo "AUTO-CONSENT (--yes flag) — proceeding to convert." >&2
        migrate_to_symlinks
        return
    fi
    if [ -n "$DATARIM_INSTALL_YES" ]; then
        echo "AUTO-CONSENT (DATARIM_INSTALL_YES env) — proceeding to convert." >&2
        migrate_to_symlinks
        return
    fi
    if [ -n "$DATARIM_MIGRATION_CHOICE" ]; then
        echo "AUTO-CONSENT (DATARIM_MIGRATION_CHOICE=$DATARIM_MIGRATION_CHOICE) — test hook." >&2
        case "$DATARIM_MIGRATION_CHOICE" in
            c|C) migrate_to_symlinks; return ;;
            k|K) INSTALL_MODE=copy; echo "Keeping copy mode." >&2; return ;;
            a|A) echo "Aborted." >&2; exit 1 ;;
            *)   echo "Invalid DATARIM_MIGRATION_CHOICE: $DATARIM_MIGRATION_CHOICE" >&2; exit 1 ;;
        esac
    fi
    if [ ! -t 0 ]; then
        echo "ERROR: non-TTY environment — refuse to prompt without --yes." >&2
        echo "       Re-run with --yes (or DATARIM_INSTALL_YES=1) to auto-convert," >&2
        echo "       or with --copy to keep copy mode." >&2
        exit 1
    fi
    printf "Choice [c/k/a]: "
    read -r choice
    choice="${choice%$'\r'}"
    case "$choice" in
        c|C) migrate_to_symlinks ;;
        k|K) INSTALL_MODE=copy; echo "Keeping copy mode." ;;
        a|A) echo "Aborted."; exit 1 ;;
        *)   echo "Invalid choice: $choice" >&2; exit 1 ;;
    esac
}

# --- TUNE-0114 Phase 2 additions -------------------------------------------

validate_project_dir() {
    local path="$1"
    if [[ "$path" =~ ^/(etc|usr|bin|sbin|System)(/|$) ]]; then
        echo "ERROR: project dir is unsafe: $path" >&2
        exit 3
    fi
    if ! mkdir -p "$path" 2>/dev/null; then
        echo "ERROR: cannot create project dir: $path" >&2
        exit 3
    fi
}

dry_or_run() {
    local description="$1"
    shift
    if [ "$DRY_RUN" = true ]; then
        echo "DRY: $description"
    else
        "$@"
    fi
}

acquire_lock() {
    local target_dir="$1"
    mkdir -p "$target_dir"
    LOCKFILE="$target_dir/.install.lock"
    if ! ( set -C; echo $$ > "$LOCKFILE" ) 2>/dev/null; then
        echo "ERROR: lockfile busy: $LOCKFILE" >&2
        exit 4
    fi
    trap 'rm -f "$LOCKFILE"' EXIT INT TERM
}

release_lock() {
    if [ -n "$LOCKFILE" ]; then
        rm -f "$LOCKFILE"
        LOCKFILE=''
    fi
    trap - EXIT INT TERM
}

fanout_runtime() {
    local runtime_name="$1"
    # claude: respect external CLAUDE_DIR (test fixtures, custom installs).
    # codex: derive ~/.codex (introduce CODEX_DIR env hook if needed).
    if [ "$runtime_name" = "claude" ]; then
        # `=` (no colon): unset CLAUDE_DIR gets default; empty stays empty so
        # assert_claude_dir_safe can reject it (T12b contract).
        : "${CLAUDE_DIR=$HOME/.claude}"
    else
        CLAUDE_DIR="${CODEX_DIR-$HOME/.$runtime_name}"
    fi
    # Validate target safety BEFORE acquiring lockfile — the lockfile path
    # depends on CLAUDE_DIR; if CLAUDE_DIR is /, /, $HOME, or empty we must
    # reject *before* writing files anywhere (T11/T12/T12b contract).
    assert_claude_dir_safe

    echo "Target:  $CLAUDE_DIR"
    case "$INSTALL_MODE" in
        symlink)
            echo "Mode:    symlink (default — repo is runtime)"
            ;;
        copy)
            if [ "$FORCE_COPY" = true ]; then
                echo "Mode:    copy (--copy)"
            else
                echo "Mode:    copy (auto-detected: symlinks not available)"
            fi
            ;;
    esac
    if [ "$FORCE" = true ]; then
        echo "Force:   on"
    fi
    echo ""

    acquire_lock "$CLAUDE_DIR"

    if [ "$DRY_RUN" = true ]; then
        echo "DRY: mkdir -p $CLAUDE_DIR"
        local scope
        for scope in "${INSTALL_SCOPES[@]}"; do
            echo "DRY: ln -sfn $SCRIPT_DIR/$scope $CLAUDE_DIR/$scope"
        done
        echo "DRY: setup_local_overlay $CLAUDE_DIR/local"
        echo ""
        release_lock
        return
    fi

    if [ "$FORCE" = true ]; then
        force_safety_guard
    fi
    # assert_claude_dir_safe already called above (pre-lockfile gate)

    if [ "$INSTALL_MODE" = "symlink" ]; then
        local topology
        topology=$(detect_existing_topology)
        case "$topology" in
            copy)
                migration_prompt
                ;;
            mixed)
                echo "ERROR: mixed topology in $CLAUDE_DIR (some symlinks + some real dirs)." >&2
                echo "       Please clean up manually before re-running install.sh." >&2
                exit 1
                ;;
            symlink|none)
                : ;;
        esac
    fi

    # migration_prompt may have flipped INSTALL_MODE to copy (user picked [k]).
    if [ "$INSTALL_MODE" = "symlink" ]; then
        for scope in "${INSTALL_SCOPES[@]}"; do
            link_scope_tree "$SCRIPT_DIR/$scope" "$CLAUDE_DIR/$scope"
        done
    else
        for scope in "${INSTALL_SCOPES[@]}"; do
            mkdir -p "$CLAUDE_DIR/$scope"
        done
        for scope in "${INSTALL_SCOPES[@]}"; do
            echo "Installing $scope..."
            copy_scope_tree "$SCRIPT_DIR/$scope" "$CLAUDE_DIR/$scope"
            echo ""
        done
    fi

    setup_local_overlay

    echo "================================="
    echo "Done! Linked: $LINKED, Copied: $COPIED, Skipped: $SKIPPED"
    echo "Local overlay: $CLAUDE_DIR/local/{skills,agents,commands,templates}/  (gitignored)"
    echo ""
    echo "Next steps:"
    echo "  1. Copy CLAUDE.md to your project root:"
    echo "     cp $SCRIPT_DIR/CLAUDE.md /path/to/your/project/"
    echo ""
    echo "  2. Customize the project-specific section at the bottom of CLAUDE.md"
    echo ""
    echo "  3. Start Claude Code and run: /dr-init <task description>"
    echo ""

    if [ "$SKIPPED" -gt 0 ] && [ "$FORCE" = false ] && [ "$INSTALL_MODE" = "copy" ]; then
        echo "Note: $SKIPPED file(s) were skipped because they already exist."
        echo "      Use --force to overwrite (safe: a backup is taken automatically"
        echo "      on live systems): ./install.sh --copy --force"
        echo ""
    fi

    release_lock
}

project_install() {
    validate_project_dir "$PROJECT_DIR"
    local datarim_dir="$PROJECT_DIR/.datarim"
    acquire_lock "$datarim_dir"
    if [ "$DRY_RUN" = true ]; then
        echo "DRY: mkdir -p $datarim_dir"
        local scope
        for scope in "${INSTALL_SCOPES[@]}"; do
            echo "DRY: cp -R $SCRIPT_DIR/$scope $datarim_dir/$scope"
        done
        echo "DRY: cp $SCRIPT_DIR/CLAUDE.md $datarim_dir/CLAUDE.md"
        echo "DRY: AGENTS.md symlink TBD Phase 3"
        release_lock
        return
    fi
    mkdir -p "$datarim_dir"
    for scope in "${INSTALL_SCOPES[@]}"; do
        cp -R "$SCRIPT_DIR/$scope" "$datarim_dir/"
    done
    cp "$SCRIPT_DIR/CLAUDE.md" "$datarim_dir/CLAUDE.md"
    # AGENTS.md symlink TBD Phase 3
    release_lock
}

# --- Main -------------------------------------------------------------------

parse_args "$@"

# Backwards-compat: legacy flags without explicit --with-claude imply claude
if [ "$FANOUT_CLAUDE" = false ] && [ "$FANOUT_CODEX" = false ] && [ -z "$PROJECT_DIR" ]; then
    if [ "$FORCE" = true ] || [ "$FORCE_COPY" = true ] || [ "$ASSUME_YES" = true ]; then
        FANOUT_CLAUDE=true
        echo "WARN: implicit --with-claude for legacy flags (deprecated: use --with-claude)" >&2
    else
        print_usage
        exit 0
    fi
fi

INSTALL_MODE=$(detect_install_mode)

VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
echo "Datarim Framework Installer v$VERSION"
echo "================================="
echo ""
echo "Source:  $SCRIPT_DIR"
echo ""

if [ -n "$PROJECT_DIR" ]; then
    echo "Target:  $PROJECT_DIR/.datarim"
    echo "Mode:    project copy"
    echo ""
    project_install
fi

if [ "$FANOUT_CLAUDE" = true ]; then
    fanout_runtime claude
fi

if [ "$FANOUT_CODEX" = true ]; then
    fanout_runtime codex
fi