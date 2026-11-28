#!/usr/bin/env python3
"""Regenerate UiChrome's palette constants from the Theme (RUB-P3-06).

The Theme (`ui/themes/footballsim.tres`) is the visual source of truth. Canvas
code that predates the Controls migration (`hud`, `pitch`, the surviving chrome
helpers) cannot read a resource at parse time, so its constants are generated
from the Theme here and checked in. Editing a colour means editing the Theme and
running this tool; `--check` fails when the two disagree.

    python tools/make_ui_palette.py
    python tools/make_ui_palette.py --check
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "ui" / "themes" / "footballsim.tres"
CHROME = ROOT / "scripts" / "ui" / "ui_chrome.gd"

CONSTS = {
    "bg": "C_BG",
    "panel": "C_PANEL",
    "panel_light": "C_PANEL_LIGHT",
    "border": "C_BORDER",
    "text": "C_TEXT",
    "dim": "C_DIM",
    "soft": "C_SOFT",
    "gold": "C_GOLD",
    "live": "C_LIVE",
    "danger": "C_DANGER",
}

COLOR_RE = re.compile(
    r"(?m)^Colors/colors/([a-z_]+)\s*=\s*Color\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)(?:,\s*([\d.]+))?\s*\)"
)
CONST_RE = re.compile(r"(?m)^const (C_[A-Z_]+)\s*:=\s*Color\([^)]*\)$")


def read_theme_colors() -> dict[str, tuple[str, ...]]:
    if not THEME.is_file():
        raise SystemExit(f"missing theme: {THEME.relative_to(ROOT)}")
    colors: dict[str, tuple[str, ...]] = {}
    for match in COLOR_RE.finditer(THEME.read_text(encoding="utf-8")):
        name, r, g, b, a = match.groups()
        colors[name] = (r, g, b, a if a is not None else "1")
    return colors


def gd_color(values: tuple[str, ...]) -> str:
    parts = [str(float(v)) for v in values]
    if float(parts[3]) >= 1.0:
        parts = parts[:3]
    return "Color(%s)" % ", ".join(parts)


def expected_block() -> str:
    colors = read_theme_colors()
    lines = []
    for name, const in CONSTS.items():
        if name not in colors:
            raise SystemExit(f"the Theme has no colour {name!r}")
        lines.append(f"const {const} := {gd_color(colors[name])}")
    return "\n".join(lines)


def current_block(text: str) -> tuple[int, int, str]:
    matches = list(CONST_RE.finditer(text))
    if not matches:
        raise SystemExit("ui_chrome.gd carries no palette constants")
    first, last = matches[0], matches[-1]
    return first.start(), last.end(), text[first.start() : last.end()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the file is stale.")
    args = parser.parse_args(argv)

    text = CHROME.read_text(encoding="utf-8")
    start, end, found = current_block(text)
    want = expected_block()
    if args.check:
        if found == want:
            print("ui palette OK (ui_chrome.gd matches the Theme).")
            return 0
        print(
            "ui palette is stale: ui_chrome.gd does not match ui/themes/footballsim.tres.\n"
            "Run: python tools/make_ui_palette.py",
            file=sys.stderr,
        )
        return 1
    if found == want:
        print("ui palette already current.")
        return 0
    CHROME.write_text(text[:start] + want + text[end:], encoding="utf-8")
    print(f"wrote {CHROME.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
