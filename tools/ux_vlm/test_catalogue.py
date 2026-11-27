#!/usr/bin/env python3
"""Unit checks for catalogue mapping, the CTA map, and PR screenshot parsing."""

from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from catalogue import (  # noqa: E402
    cta_requirement,
    is_ui_path,
    load_catalogue,
    parse_ux_screenshot_table,
    screens_for_paths,
)
from check_screens import build_prompt, enforce_cta  # noqa: E402


def _assert(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def _screen(screens: list[dict], screen_id: str) -> dict:
    for screen in screens:
        if screen["id"] == screen_id:
            return screen
    raise AssertionError(f"{screen_id} missing from catalogue")


def _cta(*, label: str = "", side: str = "", passed: bool = True) -> list[dict]:
    row: dict = {"rubric_id": "cta", "pass": passed, "reason": f"saw {label}"}
    if label:
        row["cta_label"] = label
    if side:
        row["cta_side"] = side
    return [row]


def _rejects(screens: list[dict]) -> bool:
    try:
        load_catalogue(screens_path=_write_screens(screens))
    except ValueError:
        return True
    return False


def _write_screens(screens: list[dict]) -> Path:
    import yaml

    doc = {"version": 1, "screens": screens}
    handle = tempfile.NamedTemporaryFile(
        "w", suffix=".yaml", delete=False, encoding="utf-8"
    )
    with handle:
        yaml.safe_dump(doc, handle)
    return Path(handle.name)


def _check_cta_map(screens: list[dict]) -> None:
    for screen in screens:
        kind = screen["kind"]
        cta = screen.get("primary_cta")
        if kind == "flow":
            _assert(bool(cta and cta.get("labels")), f"{screen['id']}: flow needs CTA")
        else:
            _assert(cta is None, f"{screen['id']}: {kind} must not declare primary_cta")

    hub = _screen(screens, "league-hub")
    _assert(hub["primary_cta"]["labels"] == ["CONTINUE"], "hub requires CONTINUE")
    _assert(hub["primary_cta"].get("side") == "right", "hub CONTINUE is top-right")

    picker = _screen(screens, "fixture-picker")
    _assert(picker["primary_cta"]["labels"] == ["KICK OFF"], "picker needs KICK OFF")

    pre = _screen(screens, "pre-match")
    _assert(
        set(pre["primary_cta"]["labels"]) == {"KICK OFF", "CONTINUE"},
        "pre-match accepts KICK OFF or CONTINUE",
    )
    _assert(
        _screen(screens, "main-menu")["primary_cta"]["labels"] == ["START SIM"],
        "menu needs START SIM",
    )
    _assert(
        "QUIT" in _screen(screens, "quit-confirm")["primary_cta"]["labels"],
        "quit confirm names its live door",
    )
    _assert(_screen(screens, "match-hud")["kind"] == "overlay", "HUD is an overlay")
    hidden = _screen(screens, "match-hud-hidden")
    _assert(hidden["kind"] == "overlay", "the hidden HUD is an overlay")
    _assert(
        "scripts/ui/hud.gd" in hidden["scripts"],
        "the hidden HUD must grade when the overlay changes",
    )
    for browse in ("settings", "league-table", "league-calendar", "encyclopedia"):
        _assert(_screen(screens, browse)["kind"] == "browse", f"{browse} is browse")


def _check_cta_requirement(screens: list[dict]) -> None:
    hub = cta_requirement(_screen(screens, "league-hub"))
    _assert("CONTINUE" in hub and "right-hand side" in hub, hub)
    _assert("flow screen" in hub, hub)

    browse = cta_requirement(_screen(screens, "settings"))
    _assert("BACK" in browse and "do not require CONTINUE" in browse, browse)

    overlay = cta_requirement(_screen(screens, "match-hud"))
    _assert("overlay" in overlay and "Do not require" in overlay, overlay)

    rubrics, _, _ = load_catalogue()
    prompt = build_prompt(rubrics, _screen(screens, "league-hub"))
    _assert("Required primary CTA" in prompt, prompt[:400])
    _assert("'CONTINUE'" in prompt, "prompt names the hub's label")
    _assert('"cta_label"' in prompt, "prompt asks for the read label")
    plain = build_prompt(rubrics)
    _assert("Required primary CTA" not in plain, "no screen, no CTA demand")


def _check_cta_parse(screens: list[dict]) -> None:
    """grade_image parses the label the grader reports (row or top level)."""
    import check_screens as cs

    rubrics, _, _ = load_catalogue()
    image = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    image.write(b"not really a png")
    image.close()

    def fake_chat(reply: dict):
        def chat(messages: list[dict], timeout: float = 45.0) -> str:
            return json.dumps(reply)

        return chat

    rows = [
        {"rubric_id": r["id"], "pass": True, "reason": "clear door"} for r in rubrics
    ]
    top_level = {"results": rows, "cta_label": "CONTINUE", "cta_side": "right"}
    cs._chat = fake_chat(top_level)
    hub = _screen(screens, "league-hub")
    results = cs.grade_image(image.name, rubrics, screen=hub)
    cta = next(r for r in results if r["rubric_id"] == "cta")
    _assert(cta["pass"], f"top-level cta_label must satisfy the hub: {cta}")
    _assert(cta["cta_label"] == "CONTINUE", str(cta))

    for row in rows:
        if row["rubric_id"] == "cta":
            row.update({"cta_label": "BACK", "cta_side": "left"})
    cs._chat = fake_chat({"results": rows})
    results = cs.grade_image(image.name, rubrics, screen=hub)
    cta = next(r for r in results if r["rubric_id"] == "cta")
    _assert(not cta["pass"], "a lenient pass on BACK must be forced to fail")

    Path(image.name).unlink(missing_ok=True)


def _check_cta_enforcement(screens: list[dict]) -> None:
    hub = _screen(screens, "league-hub")
    ok, = enforce_cta(hub, _cta(label="CONTINUE", side="right"))
    _assert(ok["pass"], f"CONTINUE top-right passes: {ok}")

    weak, = enforce_cta(hub, _cta(label="BACK", side="left"))
    _assert(not weak["pass"], "hub must not pass on BACK")
    _assert("CONTINUE" in weak["reason"], weak["reason"])

    silent, = enforce_cta(hub, _cta(passed=True, label=""))
    _assert(not silent["pass"], "unreadable CTA fails closed")

    wrong_side, = enforce_cta(hub, _cta(label="CONTINUE", side="left"))
    _assert(not wrong_side["pass"], "CONTINUE must sit on the right")
    _assert("right" in wrong_side["reason"], wrong_side["reason"])

    grader_fail, = enforce_cta(hub, _cta(label="CONTINUE", passed=False))
    _assert(not grader_fail["pass"], "grader fail is kept")

    pre = _screen(screens, "pre-match")
    either, = enforce_cta(pre, _cta(label="KICK OFF", side="right"))
    _assert(either["pass"], "pre-match accepts KICK OFF")

    browse, = enforce_cta(_screen(screens, "settings"), _cta(label="BACK"))
    _assert(browse["pass"], "browse screens keep BACK")


def _check_validation() -> None:
    _assert(
        _rejects([{"id": "x", "kind": "flow", "baseline_url": "u"}]),
        "flow screen without primary_cta must be rejected",
    )
    _assert(
        _rejects(
            [{"id": "x", "kind": "browse", "primary_cta": {"labels": ["BACK"]}}]
        ),
        "browse screen must not declare primary_cta",
    )
    _assert(
        _rejects([{"id": "x", "kind": "mystery"}]),
        "unknown kind must be rejected",
    )
    _assert(
        _rejects(
            [{"id": "x", "kind": "flow", "primary_cta": {"labels": ["GO"], "side": "up"}}]
        ),
        "unknown side must be rejected",
    )
    _assert(
        _rejects([{"id": "x", "kind": "flow", "primary_cta": {"labels": []}}]),
        "empty labels must be rejected",
    )


def main() -> int:
    rubrics, screens, shared = load_catalogue()
    _assert(len(rubrics) >= 6, "expected ≥6 rubrics")
    _assert(
        any(r["id"] == "pitch-action" for r in rubrics),
        "the pitch-action rubric is missing",
    )
    _assert(len(screens) <= 11, "catalogue must stay ≤11 for PR budget")
    ids = {str(s["id"]) for s in screens}
    _assert("main-menu" in ids, "main-menu missing")
    _check_cta_map(screens)
    _check_cta_requirement(screens)
    _check_cta_enforcement(screens)
    _check_cta_parse(screens)
    _check_validation()

    _assert(is_ui_path("scripts/ui/menu_screen.gd"), "menu script is UI")
    _assert(is_ui_path("fonts/Inter-Regular.ttf"), "font is UI")
    _assert(not is_ui_path("scripts/sim/match.gd"), "sim is not UI")

    menu = screens_for_paths(
        ["scripts/ui/menu_screen.gd"], screens, shared
    )
    _assert([s["id"] for s in menu] == ["main-menu"], f"menu map: {menu}")

    hub = screens_for_paths(["scripts/ui/league_sheet.gd"], screens, shared)
    _assert([s["id"] for s in hub] == ["league-hub"], f"hub sheet map: {hub}")

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
