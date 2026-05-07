# Changelog

All notable changes to the Datarim framework are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- _(TUNE-0114)_ Multi-runtime install (`install.sh --with-claude` / `--with-codex` / `--project`)
- _(TUNE-0114)_ `AGENTS.md` symlink → `CLAUDE.md` for Codex CLI compatibility
- _(TUNE-0114)_ 14 superpowers skills absorbed (4 verbatim + 8 intent-layer rewrite + 2 merge)
- _(TUNE-0114)_ Per-skill `runtime:` + AAL frontmatter
- _(TUNE-0114)_ `dev-tools/measure-skill-token-cost.sh` — token budget regression gate

### Changed
- _(TUNE-0114)_ `install.sh` rewritten as flag-based multi-runtime installer with shim creation, collision backup, and `--project` copy mode

## [1.24.0] — 2026-05-07

### Added
- _(TUNE-0109)_ Secure-by-default Network Exposure Gate (tiered model, reusable CI workflow)

## [1.23.0] — 2026-05-04

Baseline reference for TUNE-0114 token-cost regression measurements.
