#!/usr/bin/env bats
#
# Regression: fresh scaffolding MUST NOT create or describe abolished operational
# files — `backlog-archive.md` (retired v1.19.1) and `progress.md` (abolished v1.19.0).
#
# Both files are abolished in the canonical schema:
#   - `progress.md` — abolished v1.19.0; `/dr-doctor --fix` deletes it. Per-task
#     progress notes live in `tasks/{TASK-ID}-task-description.md` § Implementation
#     Notes or in the archive doc.
#   - `backlog-archive.md` — retired v1.19.1; completed/cancelled prose lives in
#     `documentation/archive/{area|cancelled}/archive-{ID}.md`, and `backlog.md`
#     carries only live items.
#
# Before this guard, `/dr-init` first-time creation, the project-init scaffold
# tree, the getting-started visual, the dr-help backlog description, AND the
# canonical `datarim-system/path-and-storage.md` § Core Files list still presented
# these abolished files as live — so a freshly scaffolded project was born with
# files `/dr-doctor --fix` immediately migrated away, a contradiction between the
# scaffolding/doctrine surface and the canonical abolition.
#
# Scaffolding is LLM-driven markdown, not an executable script, so the contract is
# enforced by grepping the shipped instruction surface: the create-step, the
# scaffold-tree visuals, the help/getting-started docs, and the canonical Core
# Files list must no longer present these files as created/live. Legitimate
# abolition doctrine (the `/dr-doctor … abolish progress.md` description) and the
# backward-compat `git status … progress.md "(those that exist)"` hygiene probe
# are NOT scaffolding and stay.
#
# If any of these fail, the scaffolding/doctrine surface has drifted back to
# seeding an abolished file — restore the abolition before merging.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
COMMANDS_DIR="${REPO_ROOT}/commands"
SKILLS_DIR="${REPO_ROOT}/skills"
TEMPLATES_DIR="${REPO_ROOT}/templates"
# docs/ was migrated to documentation/ (Diátaxis split) — getting-started lives
# under the tutorials category. Resolve it explicitly and fail loudly if absent,
# so a future re-migration can't silently turn a missing-file grep into a pass.
GETTING_STARTED="${REPO_ROOT}/documentation/tutorials/getting-started.md"

setup() {
    [ -f "${GETTING_STARTED}" ] || {
        echo "FIXTURE MISSING: ${GETTING_STARTED} (getting-started moved?)" >&2
        return 1
    }
}

# ---------- backlog-archive.md (retired v1.19.1) ----------

@test "dr-init.md first-time creation does not seed backlog-archive.md" {
    run grep -F "backlog-archive" "${COMMANDS_DIR}/dr-init.md"
    [ "$status" -ne 0 ]
}

@test "project-init/SKILL.md scaffold tree does not list backlog-archive.md" {
    run grep -F "backlog-archive" "${SKILLS_DIR}/project-init/SKILL.md"
    [ "$status" -ne 0 ]
}

@test "the abolished backlog-archive-template.md no longer exists" {
    [ ! -e "${TEMPLATES_DIR}/backlog-archive-template.md" ]
}

@test "no shipped template references the deleted backlog-archive-template.md" {
    run grep -rF "backlog-archive-template" "${TEMPLATES_DIR}"
    [ "$status" -ne 0 ]
}

@test "dr-help.md does not describe backlog-archive.md as a live backlog file" {
    run grep -F "backlog-archive" "${COMMANDS_DIR}/dr-help.md"
    [ "$status" -ne 0 ]
}

@test "getting-started.md scaffold tree does not list backlog-archive.md" {
    run grep -F "backlog-archive" "${GETTING_STARTED}"
    [ "$status" -ne 0 ]
}

@test "datarim-system/path-and-storage.md Core Files does not list backlog-archive.md" {
    run grep -F "backlog-archive" "${SKILLS_DIR}/datarim-system/path-and-storage.md"
    [ "$status" -ne 0 ]
}

# ---------- progress.md (abolished v1.19.0) ----------

@test "project-init/SKILL.md scaffold tree does not list progress.md" {
    run grep -F "progress.md" "${SKILLS_DIR}/project-init/SKILL.md"
    [ "$status" -ne 0 ]
}

@test "getting-started.md scaffold tree does not list progress.md as a created file" {
    # The /dr-doctor "abolish progress.md" doctrine line is legitimate and stays;
    # what must be absent is the scaffold-tree entry presenting it as a created file.
    run grep -F "# Overall progress" "${GETTING_STARTED}"
    [ "$status" -ne 0 ]
}

@test "datarim-system/path-and-storage.md Core Files does not list progress.md as live" {
    # Core Files is the canonical live-file list; the abolition note lives in
    # datarim-system/SKILL.md § progress.md, not here.
    run grep -F "progress.md\` — overall progress" "${SKILLS_DIR}/datarim-system/path-and-storage.md"
    [ "$status" -ne 0 ]
}
