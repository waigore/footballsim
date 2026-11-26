#!/usr/bin/env python3
"""Unit checks for catalogue mapping and PR screenshot table parsing."""

from __future__ import annotations

import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from catalogue import (  # noqa: E402
    is_ui_path,
    load_catalogue,
    parse_ux_screenshot_table,
    screens_for_paths,
)


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def main() -> int:
    rubrics, screens, shared = load_catalogue()
    _assert(len(rubrics) >= 5, "expected ≥5 rubrics")
    _assert(len(screens) <= 10, "catalogue must stay ≤10 for PR budget")
    ids = {str(s["id"]) for s in screens}
    _assert("main-menu" in ids, "main-menu missing")

    _assert(is_ui_path("scripts/ui/menu_screen.gd"), "menu script is UI")
    _assert(is_ui_path("fonts/Inter-Regular.ttf"), "font is UI")
    _assert(not is_ui_path("scripts/sim/match.gd"), "sim is not UI")

    menu = screens_for_paths(
        ["scripts/ui/menu_screen.gd"], screens, shared
    )
    _assert([s["id"] for s in menu] == ["main-menu"], f"menu map: {menu}")

    all_hit = screens_for_paths(["fonts/Inter-Regular.ttf"], screens, shared)
    _assert(len(all_hit) == len(screens), "fonts should hit all screens")

    none = screens_for_paths(["scripts/sim/foo.gd"], screens, shared)
    _assert(none == [], "non-UI should yield no screens")

    body = """
## Summary
hello

## UX screenshots
| screen | url |
|--------|-----|
| main-menu | https://raw.githubusercontent.com/wiki/waigore/footballsim/evidence/images/a.jpg |
| settings | https://example.com/settings.png |

## Test plan
- [ ] x
"""
    table = parse_ux_screenshot_table(body)
    _assert(table["main-menu"].endswith("a.jpg"), table)
    _assert(table["settings"] == "https://example.com/settings.png", table)
    _assert(parse_ux_screenshot_table("no section") == {}, "empty parse")

    print("test_catalogue: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
