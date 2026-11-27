#!/usr/bin/env python3
"""Fail if scripts/, tests/, or playtests/ .gd files contain comments.

Banned forms (outside string / raw-string literals): #, ##, //, /* */.
tools/ and YAML are out of scope. See AGENTS.md.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCOPE_DIRS = ("scripts", "tests", "playtests")
# Coverage tooling markers only (docs/testing.md). Not documentation comments.
ALLOWED_HASH_LINES = frozenset(
    {
        "# gd-tools: no cover start",
        "# gd-tools: no cover end",
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


def find_comments(text: str) -> list[tuple[int, int, str]]:
    """Return (line, col, kind) for each comment start outside strings."""
    hits: list[tuple[int, int, str]] = []
    i = 0
    n = len(text)
    line = 1
    col = 1
    in_block = False

    def advance(ch: str) -> None:
        nonlocal line, col
        if ch == "\n":
            line += 1
            col = 1
        else:
            col += 1

    while i < n:
        ch = text[i]

        if in_block:
            if ch == "*" and i + 1 < n and text[i + 1] == "/":
                advance("*")
                advance("/")
                i += 2
                in_block = False
                continue
            advance(ch)
            i += 1
            continue

        if ch in "\"'":
            quote = ch
            # Triple quotes
            if i + 2 < n and text[i : i + 3] == quote * 3:
                advance(quote)
                advance(quote)
                advance(quote)
                i += 3
                while i < n:
                    if text[i] == "\\" and i + 1 < n:
                        advance(text[i])
                        advance(text[i + 1])
                        i += 2
                        continue
                    if i + 2 < n and text[i : i + 3] == quote * 3:
                        advance(quote)
                        advance(quote)
                        advance(quote)
                        i += 3
                        break
                    advance(text[i])
                    i += 1
                continue
            advance(ch)
            i += 1
            while i < n:
                c = text[i]
                if c == "\\" and i + 1 < n:
                    advance(c)
                    advance(text[i + 1])
                    i += 2
                    continue
                advance(c)
                i += 1
                if c == quote:
                    break
            continue

        if ch == "#":
            whole = _line_at(text, i).strip()
            if whole in ALLOWED_HASH_LINES:
                while i < n and text[i] != "\n":
                    advance(text[i])
                    i += 1
                continue
            kind = "##" if i + 1 < n and text[i + 1] == "#" else "#"
            hits.append((line, col, kind))
            while i < n and text[i] != "\n":
                advance(text[i])
                i += 1
            continue

        if ch == "/" and i + 1 < n:
            nxt = text[i + 1]
            if nxt == "/":
                # res:// / user:// style paths are not comments
                prev = text[i - 1] if i > 0 else ""
                if prev != ":":
                    hits.append((line, col, "//"))
                    while i < n and text[i] != "\n":
                        advance(text[i])
                        i += 1
                    continue
            elif nxt == "*":
                hits.append((line, col, "/*"))
                advance("/")
                advance("*")
                i += 2
                in_block = True
                continue

        advance(ch)
        i += 1

    return hits


def main() -> int:
    failures: list[str] = []
    scanned = 0
    for path in iter_gd():
        scanned += 1
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for line, col, kind in find_comments(text):
            failures.append(f"{rel}:{line}:{col}: comment form `{kind}`")

    if failures:
        print("Comment ban failures:", file=sys.stderr)
        for line in failures[:200]:
            print(f"  {line}", file=sys.stderr)
        if len(failures) > 200:
            print(f"  … and {len(failures) - 200} more", file=sys.stderr)
        print(
            f"\n{len(failures)} comment(s) in {scanned} .gd file(s) under "
            f"{', '.join(SCOPE_DIRS)}. Remove them (wiki is SoT).",
            file=sys.stderr,
        )
        return 1

    print(f"All {scanned} in-scope .gd files are comment-free.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
