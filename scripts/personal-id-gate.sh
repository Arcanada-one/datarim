#!/usr/bin/env bash
#
# scripts/personal-id-gate.sh — Personal-identifier hygiene gate.
#
# Scans the shipped framework surface for personal names, handles, hostnames,
# Vault paths, and numeric GIDs that MUST NOT appear in public artefacts.
#
# Engine: perl -CSD (UTF-8-safe, BSD-compatible; never grep -P).
# Inline fence: lines between <!-- gate:example-only --> and
# <!-- /gate:example-only --> are excluded from scanning (teaching/counter-
# example content).
#
# Exit codes:
#   0  — clean (no findings)
#   1  — findings detected
#   2  — usage / file-not-found error
#
# Usage:
#   personal-id-gate.sh [--regex FILE] [--paths PATH...] [--whitelist FILE]
#                       [--report] [--check]
#   personal-id-gate.sh --help
#
# --regex FILE      Pattern file (default: dev-tools/personal-id-forbidden.regex)
# --paths PATH...   Files or dirs to scan (default: shipped surface dirs)
# --whitelist FILE  One glob/path prefix per line; matched paths are skipped
# --report          Print verbose findings to stdout
# --check           Exit 0/1 (implied; explicit alias for scripting clarity)
#
# Shipped surface default paths (relative to script's parent dir):
#   cli skills agents commands templates scripts dev-tools CLAUDE.md README.md docs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_REGEX="${FRAMEWORK_ROOT}/dev-tools/personal-id-forbidden.regex"
DEFAULT_PATHS=(
    cli skills agents commands templates scripts dev-tools
    CLAUDE.md README.md docs
)

regex_file="$DEFAULT_REGEX"
paths=()
whitelist_file=""
report=0

usage() {
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --regex)
            shift; [ $# -gt 0 ] || usage
            regex_file="$1"; shift
            ;;
        --paths)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                paths+=("$1"); shift
            done
            ;;
        --whitelist)
            shift; [ $# -gt 0 ] || usage
            whitelist_file="$1"; shift
            ;;
        --report) report=1; shift ;;
        --check)  shift ;;   # implied default — explicit alias
        --help|-h) usage ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [ ! -f "$regex_file" ]; then
    echo "ERROR: regex file not found: $regex_file" >&2
    exit 2
fi

# Resolve paths relative to framework root when running from elsewhere.
if [ ${#paths[@]} -eq 0 ]; then
    paths=("${DEFAULT_PATHS[@]}")
fi

abs_paths=()
for p in "${paths[@]}"; do
    if [ -e "$p" ]; then
        abs_paths+=("$p")
    elif [ -e "${FRAMEWORK_ROOT}/${p}" ]; then
        abs_paths+=("${FRAMEWORK_ROOT}/${p}")
    fi
    # silently skip missing paths (consumer may not have all defaults)
done

if [ ${#abs_paths[@]} -eq 0 ]; then
    [ "$report" -eq 1 ] && echo "no paths to scan (all defaults absent)"
    exit 0
fi

# Load patterns (drop comments + blank lines).
patterns=()
while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|'#'*) continue ;; esac
    patterns+=("$_line")
done < "$regex_file"

if [ ${#patterns[@]} -eq 0 ]; then
    echo "ERROR: regex file has no active patterns: $regex_file" >&2
    exit 2
fi

# Built-in whitelist: the regex definition file and the gate script itself
# must not be scanned — they are the pattern source, not content under policy.
# Store both absolute and relative (basename) forms for path-agnostic matching.
_regex_basename="${regex_file##*/}"
_self_basename="${0##*/}"
whitelist_paths=("$regex_file" "$0" "$_regex_basename" "$_self_basename"
    "personal-id-forbidden.regex" "personal-id-gate.sh"
    "dev-tools/personal-id-forbidden.regex" "scripts/personal-id-gate.sh")

# Load additional whitelist paths (one prefix per line, # comments ok).
if [ -n "$whitelist_file" ] && [ -f "$whitelist_file" ]; then
    while IFS= read -r _wl || [ -n "$_wl" ]; do
        case "$_wl" in ''|'#'*) continue ;; esac
        whitelist_paths+=("$_wl")
    done < "$whitelist_file"
fi

# Check if a file path matches any whitelist entry (prefix or substring match).
# Uses ${arr[@]+"${arr[@]}"} guard for bash 3.2 compat (empty array + set -u).
_is_whitelisted() {
    local fp="$1" wl
    for wl in ${whitelist_paths[@]+"${whitelist_paths[@]}"}; do
        case "$fp" in
            "$wl"*) return 0 ;;
        esac
        # Also match if the whitelist entry is contained in the path.
        case "$fp" in
            *"$wl"*) return 0 ;;
        esac
    done
    return 1
}

# Write a temp Perl scanner script. This avoids shell-interpolation of regex
# special chars (*,[,{,|) into a -e string, which breaks on patterns like
# ASANA_[A-Z_]*PAT. The scanner reads patterns from a file at runtime.
_PERL_SCANNER="$(mktemp /tmp/pid-gate-scanner.XXXXXX.pl)"
trap 'rm -f "$_PERL_SCANNER"' EXIT

cat > "$_PERL_SCANNER" << 'PERL_SCANNER'
use strict;
use warnings;

my ($regex_file, @scan_files) = @ARGV;

# Load patterns from regex file (skip blank lines and # comments).
open(my $rfh, '<:encoding(UTF-8)', $regex_file)
    or die "Cannot open regex file: $regex_file: $!\n";
my @patterns;
while (<$rfh>) {
    chomp;
    next if /^\s*$/ || /^\s*#/;
    push @patterns, $_;
}
close $rfh;

exit 0 unless @patterns;

# Build combined alternation regex (case-insensitive).
my $combined = join('|', @patterns);
my $re = qr/$combined/i;

for my $file (@scan_files) {
    open(my $fh, '<:encoding(UTF-8)', $file) or next;
    my $in_fence = 0;
    while (<$fh>) {
        if (/<!--\s*gate:example-only\s*-->/) { $in_fence = 1; next; }
        if (/<!--\s*\/gate:example-only\s*-->/) { $in_fence = 0; next; }
        next if $in_fence;
        if (/$re/) {
            chomp(my $line = $_);
            print "$file:$.:$line\n";
        }
    }
    close $fh;
}
PERL_SCANNER

findings=0
finding_log=""

# Collect all scannable files from abs_paths.
while IFS= read -r -d '' _file; do
    # Skip .git internals and build artefacts.
    case "$_file" in
        */.git/*|*/node_modules/*|*/dist/*|*/build/*|*/__pycache__/*) continue ;;
    esac

    # Skip whitelisted paths.
    _is_whitelisted "$_file" && continue

    # Skip known binary extensions for speed.
    case "$_file" in
        *.png|*.jpg|*.jpeg|*.gif|*.ico|*.woff|*.ttf|*.eot|*.woff2) continue ;;
        *.zip|*.tar|*.gz|*.bz2|*.xz|*.7z) continue ;;
    esac

    _matches=$(perl -CSD "$_PERL_SCANNER" "$regex_file" "$_file" 2>/dev/null || true)

    if [ -n "$_matches" ]; then
        count=$(printf '%s\n' "$_matches" | wc -l | tr -d ' ')
        findings=$((findings + count))
        if [ "$report" -eq 1 ]; then
            finding_log+="${_matches}"$'\n'
        fi
    fi
done < <(find ${abs_paths[@]+"${abs_paths[@]}"} -type f -print0 2>/dev/null)

if [ "$findings" -gt 0 ]; then
    if [ "$report" -eq 1 ]; then
        printf '%s' "$finding_log"
    fi
    echo "FAIL: ${findings} personal-identifier reference(s) found in shipped surface" >&2
    exit 1
fi

[ "$report" -eq 1 ] && echo "PASS: clean (${#abs_paths[@]} path(s) scanned, ${#patterns[@]} pattern(s))"
exit 0
