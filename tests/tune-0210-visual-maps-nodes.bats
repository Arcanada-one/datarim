#!/usr/bin/env bats
# tune-0210-visual-maps-nodes.bats — Phase 6 visual maps refresh (F7).
#
# Covers:
#   - skills/visual-maps/pipeline-routing.md carries an Artifact Flow diagram
#     with init-task, expectations, playwright-run nodes.
#   - skills/visual-maps/stage-process-flows.md mentions expectations write in
#     /dr-prd and /dr-plan stages, and Layer 4f playwright-run in /dr-qa.
#   - skills/visual-maps/utility-and-dependencies.md carries the four new
#     skill nodes in the Agent — Skill Dependencies map.
#   - skills/visual-maps.md index mentions the new artefact and skill nodes
#     in its fragment descriptions.
#   - Every touched mermaid block stays under 25 nodes per PRD Q6.

PIPELINE="$BATS_TEST_DIRNAME/../skills/visual-maps/pipeline-routing.md"
STAGES="$BATS_TEST_DIRNAME/../skills/visual-maps/stage-process-flows.md"
DEPS="$BATS_TEST_DIRNAME/../skills/visual-maps/utility-and-dependencies.md"
INDEX="$BATS_TEST_DIRNAME/../skills/visual-maps.md"

# --- Pipeline-routing fragment ---------------------------------------------

@test "V1 pipeline-routing has the Artifact Flow heading" {
    grep -qE '^## Artifact Flow Across the Pipeline' "$PIPELINE"
}

@test "V2 pipeline-routing artifact flow names init-task node" {
    awk '/^## Artifact Flow/{flag=1} flag' "$PIPELINE" | grep -q 'InitTask\[\|init-task'
}

@test "V3 pipeline-routing artifact flow names expectations node" {
    awk '/^## Artifact Flow/{flag=1} flag' "$PIPELINE" | grep -q 'Expect\[\|expectations'
}

@test "V4 pipeline-routing artifact flow names playwright-run node" {
    awk '/^## Artifact Flow/{flag=1} flag' "$PIPELINE" | grep -q 'Playwright\[\|playwright-run'
}

@test "V5 pipeline-routing artifact flow opens a mermaid block" {
    awk '/^## Artifact Flow/{flag=1} flag' "$PIPELINE" | grep -q '```mermaid'
}

# --- Stage-process-flows fragment ------------------------------------------

@test "V6 stage flows: /dr-prd flow writes expectations" {
    awk '/^## \/dr-prd$/{flag=1; next} /^## /{flag=0} flag' "$STAGES" | grep -q 'expectations'
}

@test "V7 stage flows: /dr-plan flow writes expectations" {
    awk '/^## \/dr-plan$/{flag=1; next} /^## /{flag=0} flag' "$STAGES" | grep -q 'expectations'
}

@test "V8 stage flows: /dr-qa flow has Layer 3b expectations verification" {
    awk '/^## \/dr-qa$/{flag=1; next} /^## /{flag=0} flag' "$STAGES" | grep -q 'Layer 3b'
}

@test "V9 stage flows: /dr-qa flow has Layer 4f playwright-run branch" {
    awk '/^## \/dr-qa$/{flag=1; next} /^## /{flag=0} flag' "$STAGES" | grep -qE 'Layer 4f|playwright-run'
}

@test "V10 stage flows: /dr-qa flow ends with HUMAN SUMMARY node" {
    awk '/^## \/dr-qa$/{flag=1; next} /^## /{flag=0} flag' "$STAGES" | grep -q 'HUMAN SUMMARY'
}

# --- Utility-and-dependencies fragment -------------------------------------

@test "V11 dependencies map carries init-task-persistence skill node" {
    grep -q 'init_task\["init-task-persistence"\]' "$DEPS"
}

@test "V12 dependencies map carries expectations-checklist skill node" {
    grep -q 'expect_sk\["expectations-checklist"\]' "$DEPS"
}

@test "V13 dependencies map carries playwright-qa skill node" {
    grep -q 'play_sk\["playwright-qa"\]' "$DEPS"
}

@test "V14 dependencies map carries human-summary skill node" {
    grep -q 'human_sk\["human-summary"\]' "$DEPS"
}

@test "V15 reviewer links to all four new skills" {
    # The reviewer line should reference each of init_task, expect_sk, play_sk, human_sk on one line.
    grep -E '^[[:space:]]*reviewer --> ' "$DEPS" | grep -q 'init_task'
    grep -E '^[[:space:]]*reviewer --> ' "$DEPS" | grep -q 'expect_sk'
    grep -E '^[[:space:]]*reviewer --> ' "$DEPS" | grep -q 'play_sk'
    grep -E '^[[:space:]]*reviewer --> ' "$DEPS" | grep -q 'human_sk'
}

# --- Index file ------------------------------------------------------------

@test "V16 index file mentions the new artefact nodes" {
    grep -q 'init-task' "$INDEX"
    grep -q 'expectations' "$INDEX"
    grep -q 'playwright-run' "$INDEX"
}

@test "V17 index file mentions the new skill nodes" {
    grep -q 'init-task-persistence' "$INDEX"
    grep -q 'expectations-checklist' "$INDEX"
    grep -q 'playwright-qa' "$INDEX"
    grep -q 'human-summary' "$INDEX"
}

# --- Node-count cap (PRD Q6: each NEW diagram < 25 nodes) ------------------
# Pre-existing legacy diagrams (large subgraph-style command/agent maps) are
# grandfathered. This rule applies only to diagrams introduced by Phase 6.

@test "V18 Artifact Flow mermaid block stays under 25 nodes" {
    awk '
        /^## Artifact Flow/ { in_section=1 }
        in_section && /^```mermaid$/ { in_block=1; n=0; next }
        in_section && /^```$/ && in_block {
            if (n > 25) { exit 2 }
            in_block=0
            in_section=0
            next
        }
        in_block {
            while (match($0, /[A-Za-z_][A-Za-z0-9_]*[\[\{\(]/)) {
                n++
                $0 = substr($0, RSTART + RLENGTH)
            }
        }
    ' "$PIPELINE"
}
