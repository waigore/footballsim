#!/usr/bin/env python3
"""Strip comments from scripts/, tests/, playtests/ .gd files (one-shot).

Keeps `# gd-tools: no cover start|end` markers. Replaces other comments with
blanks (collapsed to at most one blank line) so most files keep stable line
numbers for the patch-coverage gate. A short allowlist of files is then
compacted (no blank lines) because blank leftovers break gd-tools coverage
injection on those scripts.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCOPE_DIRS = ("scripts", "tests", "playtests")
ALLOWED_HASH_LINES = frozenset(
    {
        "# gd-tools: no cover start",
        "# gd-tools: no cover end",
    }
)
# Compact only where a trailing-comment strip would leave an uninstrumentable
# file (blank leftovers → inject error 43) and thus fail the patch gate.
COMPACT_REL_PATHS = frozenset(
    {
        "scripts/sim/match_engine/match_engine_actions.gd",
    }
)


def iter_gd() -> list[Path]:
    files: list[Path] = []
    for name in SCOPE_DIRS:
        root = ROOT / name
        if not root.is_dir():
            continue
        files.extend(sorted(root.rglob("*.gd")))
    return files


def _line_at(text: str, i: int) -> str:
    start = i
    while start > 0 and text[start - 1] != "\n":
        start -= 1
    end = i
    while end < len(text) and text[end] != "\n":
        end += 1
    return text[start:end]


def strip_comments(text: str) -> str:
    out: list[str] = []
    i = 0
    n = len(text)
    in_block = False
    line_has_code = False

    while i < n:
        ch = text[i]

        if in_block:
            if ch == "*" and i + 1 < n and text[i + 1] == "/":
                i += 2
                in_block = False
                continue
            if ch == "\n":
                out.append("\n")
                line_has_code = False
            i += 1
            continue

        if ch in "\"'":
            quote = ch
            if i + 2 < n and text[i : i + 3] == quote * 3:
                out.append(quote * 3)
                i += 3
                while i < n:
                    if text[i] == "\\" and i + 1 < n:
                        out.append(text[i])
                        out.append(text[i + 1])
                        i += 2
                        continue
                    if i + 2 < n and text[i : i + 3] == quote * 3:
                        out.append(quote * 3)
                        i += 3
                        break
                    out.append(text[i])
                    i += 1
                line_has_code = True
                continue
            out.append(ch)
            i += 1
            while i < n:
                c = text[i]
                if c == "\\" and i + 1 < n:
                    out.append(c)
                    out.append(text[i + 1])
                    i += 2
                    continue
                out.append(c)
                i += 1
                if c == quote:
                    break
            line_has_code = True
            continue

        if ch == "#":
            whole = _line_at(text, i).strip()
            if whole in ALLOWED_HASH_LINES and not line_has_code:
                while i < n and text[i] != "\n":
                    out.append(text[i])
                    i += 1
                continue
            while i < n and text[i] != "\n":
                i += 1
            if line_has_code:
                while out and out[-1] in " \t":
                    out.pop()
            else:
                while out and out[-1] in " \t":
                    out.pop()
            continue

        if ch == "/" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "/":
                prev = text[i - 1] if i > 0 else ""
                if prev != ":":
                    while i < n and text[i] != "\n":
                        i += 1
                    if line_has_code:
                        while out and out[-1] in " \t":
                            out.pop()
                    else:
                        while out and out[-1] in " \t":
                            out.pop()
                    continue
            elif nxt == "*":
                i += 2
                in_block = True
                continue

        if ch == "\n":
            out.append("\n")
            line_has_code = False
            i += 1
            continue

        if ch not in " \t":
            line_has_code = True
        out.append(ch)
        i += 1

    result = "".join(out)
    cleaned: list[str] = []
    blank_run = 0
    for line in result.splitlines(keepends=True):
        if line.strip() == "":
            blank_run += 1
            if blank_run <= 2:
                cleaned.append("\n")
        else:
            blank_run = 0
            cleaned.append(line)
    result = "".join(cleaned)
    if text.endswith("\n") and not result.endswith("\n"):
        result += "\n"
    return result


def compact_blanks(text: str) -> str:
    return re.sub(r"\n{2,}", "\n", text)


def main() -> int:
    changed = 0
    for path in iter_gd():
        original = path.read_text(encoding="utf-8")
        stripped = strip_comments(original)
        rel = path.relative_to(ROOT).as_posix()
        if rel in COMPACT_REL_PATHS:
            stripped = compact_blanks(stripped)
        if stripped != original:
            path.write_text(stripped, encoding="utf-8")
            changed += 1
            print(f"stripped {rel}")
    print(f"Updated {changed} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
