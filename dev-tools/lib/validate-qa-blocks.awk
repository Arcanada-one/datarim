# validate-qa-blocks.awk — Q&A round-trip block validator.
#
# Extracted from check-init-task-presence.sh validate_qa_blocks() so the bash
# wrapper stays under the ai-quality per-function line threshold; the awk
# program is one cohesive unit and lives in its own file.
#
# Invocation: awk -f validate-qa-blocks.awk -v FILE="<path>" "<path>"
#
# Walks the file looking for Q&A block headings of the form
#   ### <ISO> — Q&A by /dr-<stage> (round <N>)
# For each block (delimited by the next `### ` heading or EOF) it asserts:
#   1. All five mandatory subheadings present (Question, Answer, Decided by,
#      Summary, Conflict with existing wish).
#   2. `Decided by:` value in {operator, agent}.
#   3. When `Decided by: agent` — `Decision rationale:` subheading present
#      and its body has >= 50 non-whitespace characters.
#
# Emits one line per finding on stdout; empty output = clean. The caller
# routes the lines to stderr and counts them.
function trim(s) {
    sub(/^[ \t\r\n]+/, "", s)
    sub(/[ \t\r\n]+$/, "", s)
    return s
}
function reset_block() {
    in_block = 1
    cur_heading = $0
    has_question = 0
    has_answer = 0
    has_decided_by = 0
    decided_by_val = ""
    has_summary = 0
    has_conflict = 0
    has_rationale = 0
    rationale_chars = 0
    in_rationale_body = 0
}
function emit_findings() {
    if (!in_block) return
    if (!has_question) {
        printf("ERROR: %s: Q&A block %q missing **Question (verbatim, asked by …):** subheading\n",
            FILE, cur_heading)
    }
    if (!has_answer) {
        printf("ERROR: %s: Q&A block %q missing **Answer (verbatim, by …):** subheading\n",
            FILE, cur_heading)
    }
    if (!has_decided_by) {
        printf("ERROR: %s: Q&A block %q missing **Decided by:** subheading\n",
            FILE, cur_heading)
    } else if (decided_by_val != "operator" && decided_by_val != "agent") {
        printf("ERROR: %s: Q&A block %q has invalid Decided by value %q (must be operator or agent)\n",
            FILE, cur_heading, decided_by_val)
    }
    if (!has_summary) {
        printf("ERROR: %s: Q&A block %q missing **Summary (how it changes initial conditions):** subheading\n",
            FILE, cur_heading)
    }
    if (!has_conflict) {
        printf("ERROR: %s: Q&A block %q missing **Conflict with existing wish:** subheading\n",
            FILE, cur_heading)
    }
    if (decided_by_val == "agent") {
        if (!has_rationale) {
            printf("ERROR: %s: Q&A block %q with Decided by: agent missing **Decision rationale:** subheading\n",
                FILE, cur_heading)
        } else if (rationale_chars < 50) {
            printf("ERROR: %s: Q&A block %q Decision rationale has %d non-whitespace characters; minimum is 50\n",
                FILE, cur_heading, rationale_chars)
        }
    }
}
BEGIN {
    in_block = 0
}
# Detect a Q&A block heading.
/^### .+ — Q&A by \/dr-[a-z-]+ \(round [0-9]+\)$/ {
    emit_findings()
    reset_block()
    next
}
# Any other `### ` heading closes the current block.
/^### / {
    emit_findings()
    in_block = 0
    in_rationale_body = 0
    next
}
in_block {
    line = $0
    stripped = line
    sub(/^[ \t]+/, "", stripped)
    if (stripped ~ /^\*\*Question \(verbatim/) {
        has_question = 1
        in_rationale_body = 0
        next
    }
    if (stripped ~ /^\*\*Answer \(verbatim/) {
        has_answer = 1
        in_rationale_body = 0
        next
    }
    if (stripped ~ /^\*\*Decided by:\*\*/) {
        has_decided_by = 1
        value = stripped
        sub(/^\*\*Decided by:\*\*[ \t]*/, "", value)
        decided_by_val = trim(value)
        in_rationale_body = 0
        next
    }
    if (stripped ~ /^\*\*Decision rationale:\*\*/) {
        has_rationale = 1
        in_rationale_body = 1
        inline = stripped
        sub(/^\*\*Decision rationale:\*\*[ \t]*/, "", inline)
        gsub(/[ \t]/, "", inline)
        rationale_chars += length(inline)
        next
    }
    if (stripped ~ /^\*\*Summary \(how it changes/) {
        has_summary = 1
        in_rationale_body = 0
        next
    }
    if (stripped ~ /^\*\*Conflict with existing wish:\*\*/) {
        has_conflict = 1
        in_rationale_body = 0
        next
    }
    # While inside the rationale body, accumulate non-whitespace chars
    # until a blank line or the next bold-prefixed subheading line.
    if (in_rationale_body) {
        if (stripped ~ /^\*\*/) {
            in_rationale_body = 0
        } else if (stripped == "") {
            # Empty line — body continues but no chars to count.
        } else {
            chars = stripped
            gsub(/[ \t]/, "", chars)
            rationale_chars += length(chars)
        }
    }
}
END {
    emit_findings()
}
