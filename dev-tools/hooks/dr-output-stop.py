#!/usr/bin/env python3
"""
dr-output-stop — Claude Code Stop hook with two validators:

1. Stage Header validator (TUNE-0262 enforcement) — first non-empty line of
   the assistant response MUST match `**{TASK-ID} · {title}**` when the last
   user prompt invoked a task-scoped `/dr-*` command.

2. Human-Summary contract validator (TUNE-0262 Proposal 6) — when the user
   invoked `/dr-archive`, `/dr-compliance`, or `/dr-qa`, the response MUST
   contain the canonical `## Отчёт оператору` / `## Operator summary`
   section with self-identifier preamble and exactly four canonical
   sub-headings in order.

Contract sources (canonical):
- skills/cta-format/SKILL.md § Stage Header + § Exception List
- skills/human-summary/SKILL.md § Output contract + § Self-identifier preamble
                          + § Sub-section order is fixed and exhaustive

Fail-soft by design — any internal error → exit 0 (allow). Rationale: text
contract is already triple-hardened (TUNE-0262 Phase 1+2+3); this hook is
the final defensive layer, not a security gate.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Iterable

STAGE_HEADER_EXCEPTIONS = frozenset({"/dr-help", "/dr-status", "/dr-doctor"})
# Commands whose Stage Header legitimately appears after the TASK-ID is determined
# (not as line 1 of the response) — the skip predicate below handles them.
_DEFERRED_HEADER_CMDS = frozenset({"/dr-init", "/dr-quick"})
HUMAN_SUMMARY_TRIGGERS = frozenset({"/dr-archive", "/dr-compliance", "/dr-qa"})

HEADER_RE = re.compile(r"^\*\*[A-Z]{2,10}-\d{4} · .+\*\*$")
DR_CMD_RE = re.compile(r"(?<![A-Za-z])/dr-[a-z][a-z0-9-]*")
TASK_ID_ANY_RE = re.compile(r"\*\*[A-Z]{2,10}-\d{4}\b")

HS_SECTION_RE = re.compile(
    r"^##\s+(?:Отчёт оператору|Operator summary)\s*$", re.MULTILINE
)
HS_NEXT_H2_RE = re.compile(r"^##\s+\S", re.MULTILINE)
HS_BOLD_LINE_RE = re.compile(r"^\*\*[^*\n]+\*\*$")
HS_SUBHEADINGS = (
    "**Что было сделано / What was done**",
    "**Что получилось / What worked**",
    "**Что не получилось / осталось открытым / What didn't work or is still open**",
    "**Что дальше / What's next**",
)

TRANSCRIPT_SIZE_CAP = 50 * 1024 * 1024
SECTION_SIZE_CAP = 50 * 1024


def _extract_text(content) -> str:
    """Flatten message.content into plain text, tolerant of CC shape variation."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "text" and isinstance(block.get("text"), str):
                    parts.append(block["text"])
                elif isinstance(block.get("content"), str):
                    parts.append(block["content"])
        return "\n".join(parts)
    return ""


def parse_transcript(path: pathlib.Path) -> tuple[str, str]:
    """Return (last_user_text, last_assistant_text) from JSONL transcript.

    Tolerates partial-write races (skips lines that fail to parse).
    Returns ("", "") if the file is unreadable or empty — fail-soft.
    """
    last_user = ""
    last_assistant = ""
    try:
        if path.stat().st_size > TRANSCRIPT_SIZE_CAP:
            return ("", "")
    except OSError:
        return ("", "")
    try:
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                rec_type = rec.get("type")
                msg = rec.get("message") or {}
                content = msg.get("content") if isinstance(msg, dict) else None
                text = _extract_text(content)
                if not text:
                    continue
                if rec_type == "user":
                    last_user = text
                    last_assistant = ""
                elif rec_type == "assistant":
                    last_assistant = text
    except OSError:
        return ("", "")
    return (last_user, last_assistant)


def detect_dr_command(user_text: str) -> str | None:
    """Return the first /dr-* command in the first 400 chars, else None."""
    if not user_text:
        return None
    m = DR_CMD_RE.search(user_text[:400])
    return m.group(0) if m else None


def _first_non_empty_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.rstrip()
    return ""


def header_present(assistant_text: str) -> bool:
    """First non-empty line matches HEADER_RE."""
    return bool(HEADER_RE.match(_first_non_empty_line(assistant_text)))


def _strip_code_fences(text: str) -> str:
    """Remove fenced code blocks so H2 inside them is not treated as section break."""
    out_lines = []
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out_lines.append("")
            continue
        out_lines.append("" if in_fence else line)
    return "\n".join(out_lines)


def extract_operator_summary_section(assistant_text: str) -> str | None:
    """Slice text from HS_SECTION_RE match to next H2 or EOF. None if absent."""
    sanitised = _strip_code_fences(assistant_text)
    m = HS_SECTION_RE.search(sanitised)
    if not m:
        return None
    start = m.end()
    next_h2 = HS_NEXT_H2_RE.search(sanitised, pos=start)
    end = next_h2.start() if next_h2 else len(sanitised)
    section = sanitised[start:end]
    if len(section) > SECTION_SIZE_CAP:
        section = section[:SECTION_SIZE_CAP]
    return section


def validate_human_summary(section_text: str) -> list[str]:
    """Return finding-codes; [] = pass."""
    findings: list[str] = []
    lines = section_text.splitlines()

    preamble = ""
    for line in lines:
        if line.strip():
            preamble = line.strip()
            break
    if not HEADER_RE.match(preamble):
        findings.append("missing_preamble")

    found_positions: dict[str, int] = {}
    extra_bold_lines: list[str] = []
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not HS_BOLD_LINE_RE.match(stripped):
            continue
        if HEADER_RE.match(stripped):
            continue  # self-identifier preamble — counted above
        if stripped in HS_SUBHEADINGS:
            found_positions.setdefault(stripped, idx)
        else:
            extra_bold_lines.append(stripped)

    for i, sub in enumerate(HS_SUBHEADINGS, start=1):
        if sub not in found_positions:
            findings.append(f"missing_subheading_{i}")

    if extra_bold_lines:
        findings.append("fifth_subheading")

    if all(sub in found_positions for sub in HS_SUBHEADINGS):
        order = [found_positions[sub] for sub in HS_SUBHEADINGS]
        if order != sorted(order):
            findings.append("wrong_order")

    return findings


def _emit_block(reason: str) -> None:
    sys.stdout.write(json.dumps({"decision": "block", "reason": reason}))
    sys.stdout.flush()


def _validate_path(path_str: str) -> pathlib.Path | None:
    try:
        p = pathlib.Path(path_str).expanduser()
    except (OSError, RuntimeError):
        return None
    if any(part == ".." for part in p.parts):
        return None
    try:
        p_abs = p.absolute()
    except OSError:
        return None
    claude_home = (pathlib.Path.home() / ".claude").absolute()
    try:
        p_abs.relative_to(claude_home)
    except ValueError:
        return None
    if not p_abs.is_file():
        return None
    return p_abs


def _check_stage_header(user_cmd: str, assistant: str, stop_hook_active: bool) -> bool:
    """Return True if a block JSON was emitted (caller MUST stop)."""
    skip = user_cmd in STAGE_HEADER_EXCEPTIONS or (
        user_cmd in _DEFERRED_HEADER_CMDS and not TASK_ID_ANY_RE.search(assistant)
    )
    if skip or header_present(assistant):
        return False
    if not stop_hook_active:
        _emit_block(
            "Stage Header missing per skills/cta-format/SKILL.md § Stage Header. "
            "Prepend **{TASK-ID} · {title}** as the first line of the response."
        )
        return True
    sys.stderr.write(
        "dr-output: advisory — Stage Header still missing after block "
        "(retry budget exhausted)\n"
    )
    return False


def _check_human_summary(user_cmd: str, assistant: str, stop_hook_active: bool) -> bool:
    """Return True if a block JSON was emitted."""
    if user_cmd not in HUMAN_SUMMARY_TRIGGERS:
        return False
    section = extract_operator_summary_section(assistant)
    findings = ["missing_section"] if section is None else validate_human_summary(section)
    if not findings:
        return False
    reason = (
        "human-summary contract violations: "
        + ", ".join(findings)
        + " — see skills/human-summary/SKILL.md § Output contract."
    )
    if not stop_hook_active:
        _emit_block(reason)
        return True
    sys.stderr.write("dr-output: advisory — " + reason + " (retry budget exhausted)\n")
    return False


def _run(payload: dict) -> int:
    transcript_path = payload.get("transcript_path")
    stop_hook_active = bool(payload.get("stop_hook_active", False))
    if not isinstance(transcript_path, str):
        return 0
    path = _validate_path(transcript_path)
    if path is None:
        return 0
    last_user, last_assistant = parse_transcript(path)
    if not last_assistant:
        return 0
    user_cmd = detect_dr_command(last_user)
    if user_cmd is None:
        return 0
    if _check_stage_header(user_cmd, last_assistant, stop_hook_active):
        return 0
    _check_human_summary(user_cmd, last_assistant, stop_hook_active)
    return 0


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1] if __doc__ else "")
    parser.add_argument("--stdin", action="store_true", help="Read CC hook JSON from stdin (default).")
    parser.add_argument("--self-test", action="store_true", help="Run internal self-test cases.")
    args = parser.parse_args(list(argv) if argv is not None else None)

    if args.self_test:
        return _self_test()

    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return 0
        payload = json.loads(raw)
    except (json.JSONDecodeError, OSError):
        return 0
    try:
        return _run(payload if isinstance(payload, dict) else {})
    except Exception:  # noqa: BLE001 — fail-soft by contract (T-5)
        return 0


def _selftest_cases() -> list[tuple[str, bool]]:
    valid_header = "**TUNE-0264 · Sample title**\n\nBody text."
    valid_full = (
        "## Отчёт оператору\n\n**TUNE-0264 · Sample**\n\n"
        + "\n\n".join(HS_SUBHEADINGS) + "\n"
    )
    valid_section = extract_operator_summary_section(valid_full)
    missing_2nd = "**TUNE-0264 · Sample**\n\n" + "\n\n".join(
        [HS_SUBHEADINGS[0], HS_SUBHEADINGS[2], HS_SUBHEADINGS[3]]
    )
    fifth = "**TUNE-0264 · Sample**\n\n" + "\n\n".join(HS_SUBHEADINGS) + "\n\n**Артефакты задачи**"
    reordered = "**TUNE-0264 · Sample**\n\n" + "\n\n".join(
        [HS_SUBHEADINGS[1], HS_SUBHEADINGS[0], HS_SUBHEADINGS[2], HS_SUBHEADINGS[3]]
    )
    return [
        ("header_present(valid)", header_present(valid_header)),
        ("header_present(late)=False", not header_present("no header\n\n**TUNE-0264 · late**")),
        ("detect_dr_command basic", detect_dr_command("/dr-do TUNE-0264") == "/dr-do"),
        ("detect_dr_command none", detect_dr_command("plain text") is None),
        ("detect_dr_command word-boundary", detect_dr_command("Run/dr-do") is None),
        ("extract valid", valid_section is not None and not validate_human_summary(valid_section)),
        ("missing_subheading_2", "missing_subheading_2" in validate_human_summary(missing_2nd)),
        ("fifth_subheading", "fifth_subheading" in validate_human_summary(fifth)),
        ("wrong_order", "wrong_order" in validate_human_summary(reordered)),
        ("missing_preamble", "missing_preamble" in validate_human_summary("\n\n".join(HS_SUBHEADINGS))),
    ]


def _self_test() -> int:
    cases = _selftest_cases()
    failures = [name for name, ok in cases if not ok]
    if extract_operator_summary_section("plain text without section") is not None:
        failures.append("extract returned non-None on missing section")
    if failures:
        for f in failures:
            sys.stderr.write(f"FAIL: {f}\n")
        return 1
    sys.stdout.write(f"self-test: {len(cases)}/{len(cases)} PASS\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
