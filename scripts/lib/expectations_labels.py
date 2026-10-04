"""Normalize known historical presentation labels, never requirement prose.

New expectations use canonical ASCII keys. This read-only compatibility layer
is shared by the structural validator and the spec-graph collector so a label
cannot be accepted by one and silently discarded by the other.
"""

import re
import sys


LABELS = {
    "Expectations": ("Expectations", "Operator expectations", "\u041e\u0436\u0438\u0434\u0430\u043d\u0438\u044f"),
    "status_history": ("status_history", "Status history", "\u0418\u0441\u0442\u043e\u0440\u0438\u044f \u0441\u0442\u0430\u0442\u0443\u0441\u043e\u0432"),
    "current_status": ("current_status", "Current status", "\u0422\u0435\u043a\u0443\u0449\u0438\u0439 \u0441\u0442\u0430\u0442\u0443\u0441"),
    "success_criterion": ("success_criterion", "How to verify (success criterion)", "\u041a\u0430\u043a \u043f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c (success criterion)"),
    "linked_ac": ("linked_ac", "Related AC from PRD", "\u0421\u0432\u044f\u0437\u0430\u043d\u043d\u044b\u0439 AC \u0438\u0437 PRD"),
}


def normalize_line(line):
    """Replace only exact known labels at their schema-defined positions."""
    for canonical, aliases in LABELS.items():
        if canonical == "Expectations":
            pattern = r"^( {0,3}##[ \t]+)(" + "|".join(map(re.escape, aliases)) + r")([ \t]*(?:#+[ \t]*)?)$"
        elif canonical in {"status_history", "current_status"}:
            pattern = r"^(\s*-\s*####[ \t]+)(" + "|".join(map(re.escape, aliases)) + r")([ \t]*(?:#+[ \t]*)?)$"
        else:
            pattern = r"^(\s*-\s*)(" + "|".join(map(re.escape, aliases)) + r")(:.*)$"
        match = re.match(pattern, line.rstrip("\n"))
        if match:
            suffix = "\n" if line.endswith("\n") else ""
            return match.group(1) + canonical + match.group(3) + suffix
    return line


def main():
    with open(sys.argv[1], encoding="utf-8") as source:
        for line in source:
            sys.stdout.write(normalize_line(line))


if __name__ == "__main__":
    main()
