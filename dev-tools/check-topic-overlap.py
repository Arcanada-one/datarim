#!/usr/bin/env python3
"""Topic-overlap advisory for /dr-init Step 2.5b.

Reads a free-form task description (stdin or file) and scans the pending
items in `datarim/backlog.md` for topic overlap based on shared keyword
stems. Output is advisory only: non-blocking, exit-code 0 unless invocation
itself is malformed.

Stack-agnostic: Python 3 stdlib only. No NLP libraries, no embeddings.
RU + EN tokenisation, hand-curated stopword lists, crude suffix stemmer.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent / "data"

TOKEN_RE = re.compile(r"[A-Za-zА-Яа-яЁё][A-Za-zА-Яа-яЁё0-9-]*")
CYRILLIC_RE = re.compile(r"[А-Яа-яЁё]")
PENDING_RE = re.compile(r"^-\s+([A-Z]+-\d+)\s+·\s+(\w+)\s+·.*?·\s+(.*)$")

RU_SUFFIXES = (
    "ированиями", "ированиях", "ированием", "ировании",
    "ированный", "ированная", "ированное", "ированные",
    "ировать", "ировал", "ирован",
    "ование", "ования", "ованию", "ованием", "овании",
    "ение", "ения", "ению", "ением", "ении",
    "ость", "ости", "остью", "остей", "остям", "остях", "остями",
    "ский", "ская", "ское", "ские", "ского", "ской", "ских", "ским", "скими",
    "ный", "ная", "ное", "ные", "ного", "ной", "ных", "ным", "ными",
    "цией", "ции", "цию",
    "ого", "ему", "ому", "ыми", "ими",
    "ая", "ое", "ые", "ый", "ую", "ой", "ей",
    "ам", "ом", "ом", "ев", "ов", "ах", "ям", "ях",
    "ы", "и", "я", "е", "у", "а", "о",
)

EN_SUFFIXES = (
    "izations", "ization", "izing", "ized",
    "ations", "ation", "ating", "ated",
    "ements", "ement", "iness", "ness",
    "ibility", "ability", "ities", "ity",
    "ising", "ised",
    "ings", "ing",
    "tions", "tion", "sions", "sion",
    "ible", "able", "less",
    "ences", "ence", "ances", "ance",
    "ment",
    "ies", "ied", "ier", "iest",
    "ers", "er", "ors", "or",
    "ly", "ed", "es", "s",
)


def load_stopwords(path: Path) -> set[str]:
    out: set[str] = set()
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.add(line.lower())
    return out


def stem(token: str) -> str:
    """Crude language-aware suffix stripper.

    Tries longest matching suffix first. Will not strip below min_root=3.
    """
    t = token.lower()
    suffixes = RU_SUFFIXES if CYRILLIC_RE.search(t) else EN_SUFFIXES
    for suf in suffixes:
        if t.endswith(suf) and len(t) - len(suf) >= 3:
            return t[: -len(suf)]
    return t


def extract_stems(text: str, stopwords: set[str], min_len: int = 4) -> list[str]:
    """Return stem list (order preserved, no dedup) from free-form text.

    Filters: stopwords (pre-stem AND post-stem), tokens shorter than
    `min_len`, and tokens that look like ticket IDs (e.g. `XXX-1234`).
    """
    out: list[str] = []
    for raw in TOKEN_RE.findall(text):
        if "-" in raw and re.fullmatch(r"[A-Z]+-\d+", raw):
            continue
        low = raw.lower()
        if len(low) < min_len:
            continue
        if low in stopwords:
            continue
        s = stem(low)
        if len(s) < 3:
            continue
        if s in stopwords:
            continue
        out.append(s)
    return out


def parse_backlog(
    path: Path, allowed_statuses: tuple[str, ...] = ("pending",)
) -> list[tuple[str, str]]:
    """Return [(task_id, raw_title_text), …] for matching backlog lines."""
    out: list[tuple[str, str]] = []
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = PENDING_RE.match(line)
        if not m:
            continue
        task_id, status, rest = m.group(1), m.group(2).lower(), m.group(3)
        if status not in allowed_statuses:
            continue
        # rest still contains `P? · L? · <title>` — strip leading priority+complexity
        rest = re.sub(r"^P\d+\s+·\s+L\d+\s+·\s+", "", rest)
        out.append((task_id, rest))
    return out


def find_overlap(
    task_text: str,
    backlog: list[tuple[str, str]],
    stopwords: set[str],
    top_n: int,
    min_overlap: int,
) -> list[dict]:
    """Return overlap matches sorted by stem-overlap count desc."""
    task_stems_all = extract_stems(task_text, stopwords)
    if not task_stems_all:
        return []
    counts = Counter(task_stems_all)
    top_stems = [s for s, _ in counts.most_common(top_n)]
    top_set = set(top_stems)
    matches: list[dict] = []
    for task_id, title in backlog:
        item_stems = set(extract_stems(title, stopwords))
        shared = sorted(top_set & item_stems)
        if len(shared) >= min_overlap:
            matches.append(
                {
                    "task_id": task_id,
                    "title": title.strip(),
                    "matched": shared,
                    "overlap_count": len(shared),
                }
            )
    matches.sort(key=lambda m: (-m["overlap_count"], m["task_id"]))
    return matches


def _format_text(matches: list[dict]) -> str:
    lines = []
    for m in matches:
        lines.append(f"- {m['task_id']} — matched: {', '.join(m['matched'])}")
    return "\n".join(lines)


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="check-topic-overlap",
        description=(
            "Advisory topic-overlap detector for /dr-init Step 2.5b. "
            "Reads task description, scans pending backlog items, emits "
            "matches when ≥min-overlap top-N stems coincide. Exit 0 always."
        ),
    )
    p.add_argument("--task-description", required=True,
                   help="Path to task description file, or '-' for stdin.")
    p.add_argument("--backlog", required=True, help="Path to datarim/backlog.md.")
    p.add_argument("--top-n", type=int, default=5)
    p.add_argument("--min-overlap", type=int, default=2)
    p.add_argument("--include-status", default="pending",
                   help="Comma-separated statuses to scan (default: pending).")
    p.add_argument("--format", choices=("text", "json"), default="text",
                   help="Output format. JSON is structured; text is operator-readable.")
    p.add_argument("--stopwords-en", default=str(DATA_DIR / "stopwords-en.txt"))
    p.add_argument("--stopwords-ru", default=str(DATA_DIR / "stopwords-ru.txt"))
    return p


def _read_task_text(arg: str) -> str | None:
    if arg == "-":
        return sys.stdin.read()
    td_path = Path(arg)
    if not td_path.is_file():
        return None
    return td_path.read_text(encoding="utf-8")


def main() -> None:
    args = _build_parser().parse_args()

    task_text = _read_task_text(args.task_description)
    if task_text is None:
        return  # missing description file — silent exit 0

    stopwords = load_stopwords(Path(args.stopwords_en)) | load_stopwords(
        Path(args.stopwords_ru)
    )
    statuses = tuple(s.strip() for s in args.include_status.split(",") if s.strip())
    backlog = parse_backlog(Path(args.backlog), allowed_statuses=statuses)
    if not backlog:
        return  # silent exit 0

    matches = find_overlap(
        task_text, backlog, stopwords, args.top_n, args.min_overlap
    )
    if not matches:
        return  # silent exit 0

    if args.format == "json":
        print(json.dumps(matches, ensure_ascii=False, indent=2))
    else:
        print(_format_text(matches))


if __name__ == "__main__":
    main()
