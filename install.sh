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

# Install scopes — canonical list, asserted by tests/install.bats T34/T35/T36.
# v1.20.0 (TUNE-0077): scripts and tests added — uniform whole-directory symlink
# semantics. Eliminates drift between canonical Datarim repo and ~/.claude/
# runtime (a 730-LoC rogue datarim-doctor.sh placed directly into ~/.claude/
# scripts/ destroyed 30 task entries on aether/local-env 2026-04-30). With
# dir-symlink, ~/.claude/scripts/datarim-doctor.sh is the canonical file by
# inode — no possibility of divergence. Symmetric with skills/agents pattern.
# 'dev-tools' is runtime-required as of v2.15.0 (TUNE-0259). The
# following /dr-* commands invoke scripts from dev-tools/ at runtime:
# dr-init (check-init-task-presence.sh, check-expectations-checklist.sh),
# dr-doctor, dr-archive, dr-verify, dr-qa, dr-plan, dr-compliance,
# dr-design. Operator-facing /dr-* docs invoke these scripts via the
# runtime-prefixed form `${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/<script>`
# so consumer workspaces (cwd != framework repo) find the runtime
# symlink instead of a missing cwd-relative path. The earlier TUNE-0091
# exclusion ("developer-only, not shipped") was retired because runtime
# callers across the /dr-* pipeline outnumber the few maintainer-only
# scripts; the rest stay invisible behind the runtime root anyway.
INSTALL_SCOPES=(agents skills commands templates scripts tests dev-tools)

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
FANOUT_CODEX_UX=true       # TUNE-0297: generate SKILL.md wrappers + AGENTS.override.md; --no-codex-ux opts out
FANOUT_CURSOR=false        # TUNE-0304: Cursor IDE skill mirroring (--with-cursor)
PROJECT_DIR=''
DRY_RUN=false
LOCKFILE=''

print_usage() {
    cat <<'USAGE'
Datarim Framework Installer

Usage:
  install.sh --with-claude          Install for Claude runtime (symlink default)
  install.sh --with-codex           Install for Codex runtime
  install.sh --with-codex --no-codex-ux  Codex install without UX wrappers/manifest
  install.sh --with-cursor          Install for Cursor IDE (flat .md mirror of each SKILL.md;
                                    target: $CURSOR_DIR/skills/ — default ~/.cursor/skills/.
                                    Cursor's skill discovery is not yet officially documented;
                                    this layout is operator-validated — accepted risk per TUNE-0304 R7)
  install.sh --project DIR          Project-local copy install (no symlinks)
  install.sh --with-claude --with-codex  Multi-runtime install
  install.sh --dry-run              Show planned mutations without applying
  install.sh --copy                 Legacy copy mode (real files instead of symlinks)
  install.sh --force                Legacy force re-install (copy mode only — no-op on symlinks)
  install.sh --force --yes          Overwrite without prompt (CI / scripted)
  install.sh --help                 Show this message

Environment:
  CLAUDE_DIR                        Target directory (default: $HOME/.claude)
  CURSOR_DIR                        Cursor target directory (default: $HOME/.cursor)
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
            --with-claude)  FANOUT_CLAUDE=true; shift ;;
            --with-codex)   FANOUT_CODEX=true; shift ;;
            --no-codex-ux)  FANOUT_CODEX_UX=false; shift ;;
            --with-cursor)  FANOUT_CURSOR=true; shift ;;
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
    # Optional $1 = scope to exclude (used under codex + FANOUT_CODEX_UX where
    # skills/ is intentionally a real dir alongside symlinks for the other scopes).
    local exclude_scope="${1:-}"
    local scope present_count=0 symlink_count=0 dir_count=0
    for scope in "${INSTALL_SCOPES[@]}"; do
        [ "$scope" = "$exclude_scope" ] && continue
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
filenames with your namespace (e.g. `local/skills/my-company-style/SKILL.md`)
to avoid accidental overrides.

Document any deliberate override here so future-you can tell what was intended.
MD
    fi
}

# TUNE-0303: symlink ~/.local/bin/coworker-hook-guard → canonical Datarim
# source. Backs up an existing real file once (idempotent — re-runs detect
# the symlink target and skip). Honours DRY_RUN.
setup_coworker_hook_symlink() {
    local src="$SCRIPT_DIR/dev-tools/coworker-hook-guard.sh"
    local dst="$HOME/.local/bin/coworker-hook-guard"
    [ -f "$src" ] || return 0
    if [ "$DRY_RUN" = true ]; then
        echo "DRY: ln -sfn $src $dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    # If target is a regular file (operator's pre-TUNE-0303 hand-written
    # version), back it up exactly once.
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local ts bak
        ts=$(date -u +%Y%m%dT%H%M%SZ)
        bak="$dst.bak-TUNE-0303-$ts"
        mv "$dst" "$bak"
        echo "  BACKUP: $dst → $bak"
    fi
    ln -sfn "$src" "$dst"
    echo "  LINK: coworker-hook-guard → $src"
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

# --- TUNE-0297: Codex UX parity helpers -------------------------------------
#
# Codex CLI 0.130+ enumerates skills only for entries shaped as
# <name>/SKILL.md with valid YAML frontmatter, and exposes slash-commands /
# agents discoverable purely via AGENTS.md instructional text. Datarim source
# layout is flat `.md` files, so we generate adapter wrappers + a Codex-only
# manifest at install time. AGENTS.md (symlink chain to source CLAUDE.md)
# stays byte-stable — the manifest lives in AGENTS.override.md.

# Extract a frontmatter scalar field from a Datarim source `.md`. Echoes the
# trimmed value, or empty string if absent. Stops at the closing `---`.
extract_frontmatter_field() {
    local src="$1" field="$2"
    awk -v field="$field" '
        BEGIN { in_fm = 0; fm_count = 0; collecting = 0; block_indent = 0; out = "" }
        /^---[[:space:]]*$/ {
            fm_count++
            if (fm_count == 1) { in_fm = 1; next }
            if (fm_count == 2) { if (collecting) print out; exit }
        }
        in_fm == 1 && collecting == 1 {
            # Read indented continuation of a block scalar started by `|` or `>`.
            if (match($0, "^[[:space:]]+")) {
                if (block_indent == 0) block_indent = RLENGTH
                line = substr($0, block_indent + 1)
                # > folds newlines into spaces; | preserves but we still want a
                # single-line scalar for the wrapper — collapse uniformly.
                sub(/[[:space:]]+$/, "", line)
                if (out == "") out = line
                else out = out " " line
                next
            }
            # First non-indented line ends the block scalar — emit and stop.
            print out
            exit
        }
        in_fm == 1 {
            if (match($0, "^" field ":[[:space:]]*")) {
                val = substr($0, RLENGTH + 1)
                sub(/[[:space:]]+$/, "", val)
                if (val == "|" || val == ">" || val == "|-" || val == ">-" || val == "|+" || val == ">+") {
                    collecting = 1
                    block_indent = 0
                    next
                }
                # Inline scalar: strip matching outer quotes if both present.
                # Keep the body verbatim — emission re-quotes safely.
                if (val ~ /^".*"$/) val = substr(val, 2, length(val) - 2)
                else if (val ~ /^'\''.*'\''$/) val = substr(val, 2, length(val) - 2)
                print val
                exit
            }
        }
    ' "$src" 2>/dev/null || true
}

# Fallback: first non-empty non-frontmatter paragraph, trimmed to 200 chars.
extract_first_paragraph() {
    local src="$1"
    awk '
        BEGIN { in_fm = 0; fm_count = 0; out = "" }
        /^---[[:space:]]*$/ {
            fm_count++
            if (fm_count == 1) { in_fm = 1; next }
            if (fm_count == 2) { in_fm = 0; next }
        }
        in_fm == 1 { next }
        /^[[:space:]]*$/ { if (out != "") exit; else next }
        /^#/ { next }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (out == "") out = line
            else out = out " " line
        }
        END {
            if (length(out) > 200) out = substr(out, 1, 197) "..."
            print out
        }
    ' "$src" 2>/dev/null || true
}

# Sanitise a YAML scalar so it is safe to inline after `field:`. Collapses
# whitespace; returns the raw text without re-quoting (the caller decides
# inline-vs-quoted-vs-folded). Internal `"` are preserved so the quoter can
# escape them — do not strip here.
yaml_safe_scalar() {
    local raw="$1"
    raw=${raw//$'\n'/ }
    raw=${raw//$'\r'/ }
    printf '%s' "$raw" | tr -s '[:space:]' ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

# Render a scalar safely for a YAML mapping value. Output is always
# double-quoted with backslash + double-quote escaped. Empty/blank values
# fall back to a hardcoded placeholder so the YAML key is never bare.
yaml_quote_scalar() {
    local raw
    raw=$(yaml_safe_scalar "$1")
    if [ -z "$raw" ]; then
        raw="Datarim artefact."
    fi
    # Escape backslashes first, then double-quotes.
    raw=${raw//\\/\\\\}
    raw=${raw//\"/\\\"}
    printf '"%s"' "$raw"
}

# Generate one SKILL.md wrapper for a source skill .md.
#   $1 — source path (absolute, must be a regular file in $SCRIPT_DIR/skills/)
#   $2 — destination SKILL.md path
generate_skill_wrapper() {
    local src="$1" dst="$2"
    local name desc rel
    name=$(extract_frontmatter_field "$src" "name")
    desc=$(extract_frontmatter_field "$src" "description")
    if [ -z "$name" ]; then
        name=$(basename "$src" .md)
        echo "  WARN: $src has no frontmatter 'name:' — falling back to basename '$name'" >&2
    fi
    if [ -z "$desc" ]; then
        desc=$(extract_first_paragraph "$src")
        if [ -z "$desc" ]; then
            desc="Datarim skill (source: $(basename "$src"))."
        fi
    fi
    local name_q desc_q
    name_q=$(yaml_quote_scalar "$name")
    desc_q=$(yaml_quote_scalar "$desc")
    rel="code/datarim/skills/$(basename "$src")"
    mkdir -p "$(dirname "$dst")"
    cat > "$dst" <<WRAP
---
name: $name_q
description: $desc_q
---

This skill is provided by the Datarim framework.

Source: $rel

Read the source file at \`$rel\` for full instructions. This wrapper exists
so that Codex CLI's skill discovery (which expects \`<name>/SKILL.md\`
shape) can index Datarim skills alongside its bundled \`.system/\` skills.
WRAP
}

# Restore Codex bundled `.system/` skills from the TUNE-0296 backup directory.
# Idempotent: cleans `<codex_dir>/skills/.system/` first.
restore_codex_system_skills() {
    local codex_dir="$1"
    local backup=""
    # set +e locally because globbing for the newest backup is best-effort
    # under `set -euo pipefail`: zero matches is normal, not an error.
    if compgen -G "$codex_dir/skills.bundled-backup-TUNE-0296-*" >/dev/null 2>&1; then
        # Pick newest by mtime (BSD/GNU portable: -1 -d -t)
        backup=$(ls -1dt "$codex_dir"/skills.bundled-backup-TUNE-0296-* 2>/dev/null | head -1 || true)
    fi
    if [ -z "$backup" ] || [ ! -d "$backup/.system" ]; then
        echo "  NOTE: no .system/ backup found under $codex_dir/skills.bundled-backup-TUNE-0296-* — skipping restore" >&2
        return 0
    fi
    rm -rf "$codex_dir/skills/.system"
    cp -a "$backup/.system" "$codex_dir/skills/.system"
    echo "  RESTORE: .system/ ← $(basename "$backup")"
}

# Emit a Markdown bullet line for one source artefact.
#   $1 — source .md path
#   $2 — display prefix to apply to the basename (e.g. `/` for commands, '' for skills)
emit_manifest_entry() {
    local src="$1" prefix="$2"
    local name desc base
    base=$(basename "$src" .md)
    name=$(extract_frontmatter_field "$src" "name")
    [ -z "$name" ] && name="$base"
    desc=$(extract_frontmatter_field "$src" "description")
    if [ -z "$desc" ]; then
        desc=$(extract_first_paragraph "$src")
    fi
    desc=$(yaml_safe_scalar "$desc")
    if [ -n "$desc" ]; then
        printf -- '- `%s%s` — %s\n' "$prefix" "$name" "$desc"
    else
        printf -- '- `%s%s`\n' "$prefix" "$name"
    fi
}

# Generate ~/.codex/AGENTS.override.md with commands / skills / agents catalogue.
# Overwrite-by-design — wrappers are ephemeral generated artefacts.
generate_codex_agents_manifest() {
    local src_dir="$1" dst="$2"
    local f
    {
        echo "<!-- AUTO-GENERATED by install.sh fanout_codex_ux (TUNE-0297). DO NOT EDIT MANUALLY. -->"
        echo "<!-- Source: $src_dir/{commands,skills,agents}/ -->"
        echo ""
        # TUNE-0303: prepend MANDATORY delegation block from canonical mandate
        # fragment so codex runtime sees the same rules as Claude (~/.claude/CLAUDE.md
        # § Coworker Delegation). Source: templates/coworker-delegation-fragment.md.
        local _mandate="$src_dir/templates/coworker-delegation-fragment.md"
        if [ -f "$_mandate" ]; then
            echo "## MANDATORY delegation (Codex runtime)"
            echo ""
            cat "$_mandate"
            echo ""
            echo "---"
            echo ""
        fi
        echo "## Available Datarim Commands"
        echo ""
        if [ -d "$src_dir/commands" ]; then
            for f in "$src_dir/commands"/*.md; do
                [ -f "$f" ] || continue
                emit_manifest_entry "$f" "/"
            done
        fi
        echo ""
        echo "## Available Datarim Skills"
        echo ""
        if [ -d "$src_dir/skills" ]; then
            # Flat-layout legacy skills.
            for f in "$src_dir/skills"/*.md; do
                [ -f "$f" ] || continue
                emit_manifest_entry "$f" ""
            done
            # Directory-per-skill layout (TUNE-0304).
            for f in "$src_dir/skills"/*/SKILL.md; do
                [ -f "$f" ] || continue
                emit_manifest_entry "$f" ""
            done
        fi
        echo ""
        echo "## Available Datarim Agents"
        echo ""
        if [ -d "$src_dir/agents" ]; then
            for f in "$src_dir/agents"/*.md; do
                [ -f "$f" ] || continue
                emit_manifest_entry "$f" ""
            done
        fi
        echo ""
        echo "<!-- Regenerate via: install.sh --with-codex. Skip via: --no-codex-ux. -->"
    } > "$dst"
}

# Orchestrator: convert ~/.codex/skills/ from symlink → real dir, regenerate
# SKILL.md wrappers, restore .system/, emit AGENTS.override.md manifest.
fanout_codex_ux() {
    local codex_dir="$1" src_dir="$2"
    if [ "$DRY_RUN" = true ]; then
        echo "DRY: convert $codex_dir/skills symlink → real dir if symlinked"
        echo "DRY: generate SKILL.md wrappers under $codex_dir/skills/<name>/"
        echo "DRY: restore .system/ from $codex_dir/skills.bundled-backup-TUNE-0296-*"
        echo "DRY: write $codex_dir/AGENTS.override.md (commands + skills + agents manifest)"
        return 0
    fi

    # 1. Convert skills/ symlink to real directory (idempotent)
    if [ -L "$codex_dir/skills" ]; then
        rm "$codex_dir/skills"
        mkdir -p "$codex_dir/skills"
    fi
    mkdir -p "$codex_dir/skills"

    # 2. Clean stale wrappers (preserve `.system/`)
    if [ -d "$codex_dir/skills" ]; then
        find "$codex_dir/skills" -mindepth 1 -maxdepth 1 -type d \
            ! -name '.system' -exec rm -rf {} +
    fi

    # 3. Generate wrappers for top-level source skills.
    #    Supports both legacy flat layout (`skills/<name>.md`) and the
    #    directory-per-skill layout (`skills/<name>/SKILL.md`, TUNE-0304).
    local src_skill name
    local generated=0
    for src_skill in "$src_dir/skills"/*.md; do
        [ -f "$src_skill" ] || continue
        name=$(basename "$src_skill" .md)
        generate_skill_wrapper "$src_skill" "$codex_dir/skills/$name/SKILL.md"
        generated=$((generated + 1))
    done
    for src_skill in "$src_dir/skills"/*/SKILL.md; do
        [ -f "$src_skill" ] || continue
        name=$(basename "$(dirname "$src_skill")")
        generate_skill_wrapper "$src_skill" "$codex_dir/skills/$name/SKILL.md"
        generated=$((generated + 1))
    done
    echo "  WRAP: generated $generated SKILL.md adapter(s) under $codex_dir/skills/"

    # 4. Restore .system/ from backup
    restore_codex_system_skills "$codex_dir"

    # 5. Generate AGENTS.override.md
    generate_codex_agents_manifest "$src_dir" "$codex_dir/AGENTS.override.md"
    echo "  MANIFEST: $codex_dir/AGENTS.override.md"
}

# setup_cursor_runtime — TUNE-0304 Phase 4.
#
# Mirrors each migrated `skills/<name>/SKILL.md` from the source repo into
# `$CURSOR_DIR/skills/<name>.md` (flat layout). Cursor's official skill-
# discovery contract is not published as of 2026-Q2 (R7 risk: deferred
# Cursor-runtime smoke; operator validates on real install). Files are
# copies, not symlinks, because Cursor user installs may be on filesystems
# without symlink support (Windows + FAT) and the deferred-validation
# posture argues for the more conservative on-disk shape.
#
# Source layout: $src_dir/skills/<name>/SKILL.md  →
# Target layout: $cursor_dir/skills/<name>.md
#
# Excludes skills/.system/ (Codex bundled, Constraint C3).
setup_cursor_runtime() {
    local cursor_dir="$1" src_dir="$2"
    if [ "$DRY_RUN" = true ]; then
        echo "DRY: mkdir -p $cursor_dir/skills"
        echo "DRY: copy each $src_dir/skills/<name>/SKILL.md → $cursor_dir/skills/<name>.md"
        echo "DRY: cursor support is operator-validated (R7 deferred-validation)"
        return 0
    fi

    mkdir -p "$cursor_dir/skills"
    local skill_md name copied=0
    for skill_md in "$src_dir"/skills/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        name=$(basename "$(dirname "$skill_md")")
        # Skip reserved Codex bundled namespace.
        [ "$name" = ".system" ] && continue
        cp "$skill_md" "$cursor_dir/skills/$name.md"
        copied=$((copied + 1))
    done
    echo "  CURSOR: mirrored $copied skill(s) into $cursor_dir/skills/ (flat .md layout)"
    echo "  NOTE: Cursor skill discovery is operator-validated — R7 (deferred-validation)."

    # Install coworker delegation rule into ~/.cursor/rules/. Cursor reads
    # *.mdc files from rules/ with frontmatter `alwaysApply: true` and
    # auto-loads them. Parity with Claude (~/.claude/CLAUDE.md § Coworker
    # Delegation) and Codex (~/.codex/AGENTS.override.md prepend).
    local cw_rule_src="$src_dir/templates/coworker-delegation.mdc"
    if [ -f "$cw_rule_src" ]; then
        mkdir -p "$cursor_dir/rules"
        cp "$cw_rule_src" "$cursor_dir/rules/coworker-delegation.mdc"
        echo "  CURSOR: installed coworker delegation rule → $cursor_dir/rules/coworker-delegation.mdc"
    else
        echo "  CURSOR: SKIP coworker-delegation.mdc (template missing — non-fatal)"
    fi
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
        if [ "$runtime_name" = "codex" ]; then
            echo "DRY: ln -sfn $SCRIPT_DIR/AGENTS.md $CLAUDE_DIR/AGENTS.md"
            if [ "$FANOUT_CODEX_UX" = true ]; then
                fanout_codex_ux "$CLAUDE_DIR" "$SCRIPT_DIR"
            fi
        fi
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
        local topology topo_exclude=""
        # TUNE-0297: under codex + FANOUT_CODEX_UX skills/ is intentionally a
        # real dir while the other scopes stay symlinks — exclude it from the
        # mixed-topology gate so a re-run does not blow up.
        if [ "$runtime_name" = "codex" ] && [ "$FANOUT_CODEX_UX" = true ]; then
            topo_exclude="skills"
        fi
        topology=$(detect_existing_topology "$topo_exclude")
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
            # TUNE-0297: under codex + FANOUT_CODEX_UX skip the skills/ symlink;
            # fanout_codex_ux will materialise it as a real dir with wrappers.
            if [ "$scope" = "skills" ] && \
               [ "$runtime_name" = "codex" ] && \
               [ "$FANOUT_CODEX_UX" = true ]; then
                continue
            fi
            link_scope_tree "$SCRIPT_DIR/$scope" "$CLAUDE_DIR/$scope"
        done
        # TUNE-0296: Codex CLI reads ~/.codex/AGENTS.md as ecosystem-router entry.
        # Symlink to Datarim source so Codex sees the same router as Claude (via CLAUDE.md chain).
        if [ "$runtime_name" = "codex" ]; then
            ln -sfn "$SCRIPT_DIR/AGENTS.md" "$CLAUDE_DIR/AGENTS.md"
            echo "  LINK: AGENTS.md → $SCRIPT_DIR/AGENTS.md"
            LINKED=$((LINKED + 1))
            if [ "$FANOUT_CODEX_UX" = true ]; then
                fanout_codex_ux "$CLAUDE_DIR" "$SCRIPT_DIR"
            fi
        fi
    else
        for scope in "${INSTALL_SCOPES[@]}"; do
            mkdir -p "$CLAUDE_DIR/$scope"
        done
        for scope in "${INSTALL_SCOPES[@]}"; do
            echo "Installing $scope..."
            copy_scope_tree "$SCRIPT_DIR/$scope" "$CLAUDE_DIR/$scope"
            echo ""
        done
        if [ "$runtime_name" = "codex" ]; then
            cp -f "$SCRIPT_DIR/AGENTS.md" "$CLAUDE_DIR/AGENTS.md"
            echo "  COPY: AGENTS.md → $CLAUDE_DIR/AGENTS.md"
            COPIED=$((COPIED + 1))
            if [ "$FANOUT_CODEX_UX" = true ]; then
                fanout_codex_ux "$CLAUDE_DIR" "$SCRIPT_DIR"
            fi
        fi
    fi

    setup_local_overlay
    # TUNE-0303: link canonical coworker-hook-guard once per fanout call.
    # Idempotent on re-run; runs for both claude and codex fanouts so a
    # codex-only install still gets the hook symlink.
    setup_coworker_hook_symlink

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

if [ "$FANOUT_CURSOR" = true ]; then
    cursor_dir="${CURSOR_DIR-$HOME/.cursor}"
    src_dir="$SCRIPT_DIR"
    echo "Cursor:  $cursor_dir/skills"
    echo "Source:  $src_dir/skills"
    setup_cursor_runtime "$cursor_dir" "$src_dir"
fi