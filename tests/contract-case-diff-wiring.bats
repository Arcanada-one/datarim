#!/usr/bin/env bats

# Source-wiring checks for the documented contract-comparison procedure.
# They do not compare contract contents or certify semantic review.

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    COMPLIANCE="$REPO_DIR/skills/compliance/SKILL.md"
    QA="$REPO_DIR/commands/dr-qa.md"
}

@test "compliance step 1 requires complete comparison and semantic accounting" {
    step1=$(awk '/^### 1\. Change Set & PRD\/Task Alignment/{f=1;next} /^### /{f=0} f' "$COMPLIANCE")
    [[ "$step1" == *"full text of every case in both the original and replacement versions"* ]]
    [[ "$step1" == *"name every added, removed, or changed case"* ]]
    [[ "$step1" == *"describe each material semantic difference"* ]]
    [[ "$step1" == *"Preserve both contract versions"* ]]
    [[ "$step1" == *"static wiring tests do not perform the semantic review"* ]]
}

@test "dr-qa applies the same full comparison before the verdict" {
    run grep -F -c 'compare the full text of every' "$QA"
    [ "$output" -ge 1 ]
    qa_text=$(tr '\n' ' ' < "$QA")
    [[ "$qa_text" == *"describe material semantic differences"* ]]
    run grep -F -c 'case-by-case semantic review' "$QA"
    [ "$output" -ge 1 ]
}
