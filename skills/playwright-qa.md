---
name: playwright-qa
description: Browser-based QA contract for frontend-touching tasks — resolution chain CLI→MCP→env-browser, headed/headless modes, artifact layout under datarim/qa/.
runtime: [claude, codex]
current_aal: 1
target_aal: 2
---

# Playwright QA — Browser-Based Frontend Verification

When a task changes files that affect the rendered UI, `/dr-qa` runs a real
browser pass against the project's local dev surface (or a static fixture)
and captures evidence. This skill defines the contract: when the pass
fires, which tool gets used, how the run is isolated from concurrent
agents, and where artifacts land.

The skill is **opt-in by detection**: tasks that do not touch frontend
files never trigger a Playwright pass. Missing tooling is a finding, not
a block — the operator's pipeline keeps moving.

## Frontend touch detection

A task is considered «frontend-touching» when the changed-files set
contains at least one entry matching:

- `*.html`, `*.htm`
- `*.css`, `*.scss`, `*.sass`, `*.less`
- `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`
- `*.php` whose body matches an HTML-markup heuristic
  (`grep -qE '<(html|body|div|section|form|main|nav|header|footer|button|input)\b' <file>`)

Detection runs on `git diff --name-only <base>...HEAD` against the
canonical base (`main` for most repos, configurable via
`DATARIM_FRONTEND_BASE` env var, default `origin/main`). Renamed and
deleted entries are ignored — Playwright runs only against present
markup.

## Resolution chain

`dev-tools/detect-playwright-tooling.sh` resolves the tool to use:

1. **Override** — `DATARIM_PLAYWRIGHT` env var, one of
   `playwright-cli | playwright-mcp | env-browser | none`. Operator escape
   hatch; bypasses probing entirely.
2. **CLI** — `playwright` binary on `PATH`, probed with `--version`. First
   preference for determinism and version pinning.
3. **MCP** — `DATARIM_PLAYWRIGHT_MCP_AVAILABLE=1` env var, or a
   `playwright-mcp` binary on `PATH`. Used when the runtime exposes
   Playwright as a Claude/Codex MCP server.
4. **env-browser** — `BROWSER`, `PLAYWRIGHT_BROWSER_PATH`, or
   `CHROME_PATH` env var points at an executable file. Each candidate is
   path-traversal guarded (no `..` segments) and tested with a
   3-second `--version` probe.
5. **none** — chain exhausted. `/dr-qa` records a finding
   («playwright-tooling-missing») and continues to the next layer; the
   step does not fail the QA verdict on its own.

Exit codes: `0` resolved (including `none`), `1` only when invoked with
`--require` and the result is `none`, `2` on usage error / invalid
override / strict-headed without a display.

## Headed mode

Headed mode is orthogonal to detection and is requested by:

- CLI flag: `/dr-qa --headed` or `/dr-qa --headed-strict`
- Init-task frontmatter key: `qa_browser_mode: headed` (lenient) or
  `qa_browser_mode: headed-strict` (fail-fast)

Three states:

| Request | `$DISPLAY` present | Result |
|---------|--------------------|--------|
| default (neither flag nor key) | n/a | headless |
| `headed` (lenient) | yes | headed |
| `headed` (lenient) | no | headless + finding `headed-requested-but-no-display` |
| `headed-strict` | yes | headed |
| `headed-strict` | no | **exit 2** — pass aborts, BLOCKED finding |

The lenient mode is the right default for CI/server contexts; strict mode
is for operator-driven local runs where a visible browser is a hard
requirement.

## Artifact layout

```
datarim/qa/playwright-{ID}/
├── run-<ISO-timestamp>/    # one directory per pass, UTC YYYYMMDDTHHMMSSZ
│   ├── screenshot.png      # final viewport, full page when supported
│   ├── trace.zip           # Playwright trace bundle (CLI/MCP only)
│   ├── run.log             # combined stdout + stderr, one line per event
│   └── summary.md          # short report: tool, headed mode, exit code,
│                           # findings, target URL, viewport
├── latest -> run-<ISO>/    # symlink to most recent run; falls back to
│                           # a regular copy on filesystems without symlinks
└── .lock                   # flock target — see § Concurrency below
```

`{ID}` is the task ID. The per-run subdirectory keeps history bounded by
the operator (manual purge or scheduled cleanup outside this skill's
scope); `latest` provides a stable path for downstream readers.

`summary.md` follows the shape:

```markdown
# Playwright run — <ISO-timestamp>

- Task: <ID>
- Tool: <playwright-cli | playwright-mcp | env-browser | none>
- Headed mode: <headless | headed>
- Display available: <true | false>
- Target URL: <url or "static fixture: <path>">
- Viewport: <WxH>
- Exit code: <int>
- Findings:
  - <one bullet per finding, or "None">
```

## Concurrency

Concurrent agents running `/dr-qa` on the same task MUST serialise on a
per-task lock to avoid trampling each other's runs. The runner acquires
`datarim/qa/playwright-{ID}/.lock` via `flock --timeout 30` (or a
`mkdir`-based atomic fallback on systems without `flock`). The lock
covers the entire pass — resolution, browser invocation, artifact write,
`latest` swap, lock release.

A lock-acquire timeout is treated as a finding
(«playwright-lock-timeout»), not a block — the operator may inspect the
in-flight run via `latest/`.

## Outputs consumed by `/dr-qa`

The QA report (`datarim/qa/qa-report-{ID}.md`) cites the resolved tool,
headed mode, exit code, and the path to the run directory. Failure or
absent tooling appears as a finding under the Code Quality layer
(playwright sub-step), never as a separate FAIL routing branch — the
existence of a finding is the signal; the operator decides whether to
treat it as blocking.

## Cross-references

- `skills/frontend-ui.md` § Visual Verification — pre-existing UI checks
  that complement the browser pass.
- `skills/cta-format.md` — when the operator wants a re-run, the CTA
  points at the per-task lock file path so re-entry is unambiguous.
- `dev-tools/detect-playwright-tooling.sh` — single source of truth for
  the resolution chain; this skill is its operator-facing contract.

## When NOT to apply

- Backend-only tasks (API, infra, DB) — no frontend touch detected.
- Tasks that only modify content text inside HTML files without changing
  structure — detection still triggers, but the run is a no-op smoke pass
  by design; operators may suppress with frontmatter
  `qa_browser_mode: skip`.
- Research / docs / archive-only tasks — no executable surface.
