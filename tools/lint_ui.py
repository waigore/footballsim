#!/usr/bin/env python3
"""Guard the Controls-first chrome (RUB-P3-06, DR-20261128-37).

Fails a pull request for:

  canvas   — a new game script that paints or keeps a manual hit-rect registry
             outside the HUD/pitch allowlist;
  palette  — a new palette colour or font fork in UI code (the Theme owns them);
  hitrect  — a new manual hit-rect / layout-item registry outside the allowlist;
  reactive — a UI script that holds a live season without naming the bus or its
             change signals.

Comparison is against the base ref, so the canvas chrome the Controls migration
has not converted yet still passes while new painted chrome cannot land. The
canvas-points total is printed against the fixed ceiling in
`tools/arch_ui_budget.txt`; the ceiling is enforced once the migration clears
the allowlist, and raising it is a Design Record change, never a ratchet.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

UI_ROOTS = ("scripts/ui/", "scripts/view/", "ui/")
ALLOWLIST = (
    "scripts/ui/hud",
    "scripts/ui/pre_match_pitch.gd",
    "scripts/view/pitch_",
    "scripts/view/actor_layer.gd",
)
PALETTE_MIRROR = "scripts/ui/ui_chrome.gd"
BUDGET_PATH = ROOT / "tools" / "arch_ui_budget.txt"

PALETTE_RE = re.compile(r"(?m)^const\s+[A-Z][A-Z0-9_]*\s*(?::\s*Color\s*)?:?=\s*Color\(")
FONT_LOAD_RE = re.compile(r'load\(\s*"res://fonts/')
HITRECT_RE = re.compile(
    r"(?m)^\s*func\s+button_rects\s*\("
    r"|\badd_button\s*\("
    r"|\bbuttons\s*:\s*Array\b"
)
SEASON_MEMBER_RE = re.compile(r"(?m)^var\s+\w+\s*:\s*LeagueSeason\b")
REACTIVE_RE = re.compile(r"state_changed|UiBus|match_recorded")

DRAW_RE = re.compile(
    r"\bdraw_(?:rect|string|string_outline|style_box|line|circle|arc|polygon|"
    r"polyline|texture|texture_rect|multiline|multiline_string|colored_polygon|"
    r"primitive|set_transform|dashed_line|char)\b"
)
DRAW_FN_RE = re.compile(r"(?m)^func _draw\(")


def is_ui_path(rel: str) -> bool:
    return any(rel.startswith(prefix) for prefix in UI_ROOTS)


def is_allowed(rel: str) -> bool:
    return any(rel.startswith(prefix) for prefix in ALLOWLIST)


def resolve_base(cli: str | None) -> str:
    if cli:
        return cli
    env = os.environ.get("GITHUB_BASE_REF", "").strip()
    if env:
        return f"origin/{env}"
    return "origin/main"


def git(*args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", *args], cwd=ROOT, text=True, stderr=subprocess.DEVNULL
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def changed_paths(base: str) -> set[str]:
    paths: set[str] = set()
    for cmd in (
        ["diff", "--name-only", "--diff-filter=ACMR", f"{base}...HEAD"],
        ["diff", "--name-only", "--diff-filter=ACMR", base],
    ):
        out = git(*cmd)
        if out:
            paths.update(line.strip() for line in out.splitlines() if line.strip())
            break
    out = git("diff", "--name-only", "--diff-filter=ACMR", "HEAD")
    paths.update(line.strip() for line in out.splitlines() if line.strip())
    return paths


def added_files(base: str) -> set[str]:
    paths: set[str] = set()
    for cmd in (
        ["diff", "--name-only", "--diff-filter=A", f"{base}...HEAD"],
        ["diff", "--cached", "--name-only", "--diff-filter=A", base],
        ["ls-files", "--others", "--exclude-standard"],
    ):
        out = git(*cmd)
        paths.update(line.strip() for line in out.splitlines() if line.strip())
    return paths


def added_lines(base: str, rel: str) -> list[tuple[int, str]]:
    out = git("diff", "-U0", f"{base}...HEAD", "--", rel)
    if not out:
        out = git("diff", "-U0", base, "--", rel)
    added: list[tuple[int, str]] = []
    line_no = 0
    for line in out.splitlines():
        hunk = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
        if hunk:
            line_no = int(hunk.group(1))
            continue
        if line.startswith("+") and not line.startswith("+++"):
            added.append((line_no, line[1:]))
            line_no += 1
        elif line.startswith("-") and not line.startswith("---"):
            continue
        else:
            line_no += 1
    return added


def canvas_points(text: str) -> int:
    return (
        len(DRAW_RE.findall(text))
        + len(DRAW_FN_RE.findall(text))
        + len(re.findall(r"\b(?:func\s+button_rects|add_button)\s*\(", text))
    )


def load_budget() -> tuple[int, list[str]]:
    if not BUDGET_PATH.is_file():
        return -1, []
    ceiling = -1
    allow: list[str] = []
    for raw in BUDGET_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("budget"):
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                ceiling = int(parts[1])
            continue
        allow.append(line.split()[0])
    return ceiling, allow


def check_new_canvas(failures: list[str], added: set[str]) -> None:
    for rel in sorted(added):
        if not rel.endswith(".gd") or not is_ui_path(rel) or is_allowed(rel):
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        points = canvas_points(path.read_text(encoding="utf-8"))
        if points <= 0:
            continue
        failures.append(
            f"{rel}:1: RUB-P3-06 new painted chrome ({points} canvas points) outside the "
            f"HUD/pitch allowlist — build a Control tree from ui/components instead"
        )


def check_forks(failures: list[str], rel: str, base: str) -> None:
    if rel == PALETTE_MIRROR:
        return
    for line_no, text in added_lines(base, rel):
        if PALETTE_RE.search(text):
            failures.append(
                f"{rel}:{line_no}: RUB-P3-06 palette fork — colours live in the Theme "
                f"(ui/themes/footballsim.tres); read them through UiTheme"
            )
        elif FONT_LOAD_RE.search(text):
            failures.append(
                f"{rel}:{line_no}: RUB-P3-06 font fork — fonts live in the Theme; "
                f"read them through UiTheme.fonts()"
            )
        elif HITRECT_RE.search(text):
            failures.append(
                f"{rel}:{line_no}: RUB-P3-06 manual hit-rect registry outside the "
                f"HUD/pitch allowlist — use a Control"
            )


def check_reactive(failures: list[str]) -> None:
    root = ROOT / "scripts" / "ui"
    if not root.is_dir():
        return
    for path in sorted(root.rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        if not SEASON_MEMBER_RE.search(text):
            continue
        if REACTIVE_RE.search(text):
            continue
        failures.append(
            f"{rel}:1: RUB-P3-06 a view that holds a season must subscribe to "
            f"state_changed (or the UiBus) instead of pulling on refresh"
        )


def report_canvas() -> None:
    ceiling, _ = load_budget()
    total = 0
    outside = 0
    for prefix in ("scripts/ui/", "scripts/view/", "ui/"):
        root = ROOT / prefix
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.gd")):
            rel = path.relative_to(ROOT).as_posix()
            points = canvas_points(path.read_text(encoding="utf-8"))
            total += points
            if points and not is_allowed(rel):
                outside += points
    note = f"fixed ceiling {ceiling}" if ceiling >= 0 else "no ceiling recorded"
    print(f"canvas points: {total} (outside allowlist: {outside}; {note})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-ref", default=None, help="Git ref to diff (default origin/main).")
    args = parser.parse_args(argv)

    base = resolve_base(args.base_ref)
    failures: list[str] = []

    report_canvas()
    added = added_files(base)
    check_new_canvas(failures, added)
    for rel in sorted(changed_paths(base)):
        if not rel.endswith(".gd") or not is_ui_path(rel) or is_allowed(rel):
            continue
        if rel in added:
            continue
        check_forks(failures, rel, base)
    check_reactive(failures)

    if failures:
        print("UI architecture lint failures:", file=sys.stderr)
        for line in sorted(failures):
            print(f"  {line}", file=sys.stderr)
        print(
            "\nSee docs/rubric.md (RUB-P3-06) and the wiki DR-20261128-37.",
            file=sys.stderr,
        )
        return 1

    print("ui-lint OK (RUB-P3-06: canvas, palette, fonts, hit-rects, reactive views).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
