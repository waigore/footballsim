#!/usr/bin/env python3
"""Load UX VLM rubrics/screens and map changed paths → screen ids."""

from __future__ import annotations

import fnmatch
import re
from pathlib import Path
from typing import Any

import yaml

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUBRICS = Path(__file__).resolve().parent / "rubrics.yaml"
DEFAULT_SCREENS = Path(__file__).resolve().parent / "screens.yaml"

UI_PATH_PREFIXES = (
    "scenes/",
    "ui/",
    "scripts/ui/",
    "assets/ui/",
    "fonts/",
)

_SCREENSHOT_SECTION = re.compile(
    r"^##\s+UX screenshots\s*$", re.IGNORECASE | re.MULTILINE
)
_TABLE_ROW = re.compile(
    r"^\|\s*([^|]+?)\s*\|\s*(https?://[^|\s]+)\s*\|\s*$", re.MULTILINE
)


def load_yaml(path: Path) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a mapping at the root")
    return data


def load_catalogue(
    rubrics_path: Path = DEFAULT_RUBRICS,
    screens_path: Path = DEFAULT_SCREENS,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[str]]:
    rubrics_doc = load_yaml(rubrics_path)
    screens_doc = load_yaml(screens_path)
    rubrics = list(rubrics_doc.get("rubrics") or [])
    screens = list(screens_doc.get("screens") or [])
    shared = [str(p) for p in (screens_doc.get("shared_paths") or [])]
    if not rubrics:
        raise ValueError(f"{rubrics_path}: no rubrics")
    if not screens:
        raise ValueError(f"{screens_path}: no screens")
    return rubrics, screens, shared


def is_ui_path(path: str) -> bool:
    norm = path.replace("\\", "/").lstrip("./")
    return any(norm == p[:-1] or norm.startswith(p) for p in UI_PATH_PREFIXES)


def _match_glob(path: str, pattern: str) -> bool:
    norm = path.replace("\\", "/").lstrip("./")
    pat = pattern.replace("\\", "/")
    if "**" in pat:
        # fnmatch does not treat ** as recursive; approximate.
        parts = pat.split("**/")
        if len(parts) == 2 and parts[0] == "":
            return fnmatch.fnmatch(norm, parts[1]) or f"/{parts[1]}" in f"/{norm}"
        if len(parts) == 2:
            prefix, rest = parts
            if not norm.startswith(prefix):
                return False
            remainder = norm[len(prefix) :]
            return fnmatch.fnmatch(remainder, rest) or fnmatch.fnmatch(
                remainder, "*/" + rest
            )
    return fnmatch.fnmatch(norm, pat)


def screens_for_paths(
    changed_paths: list[str],
    screens: list[dict[str, Any]],
    shared_paths: list[str],
) -> list[dict[str, Any]]:
    """Return unique catalogue screens affected by changed paths."""
    ui_paths = [p for p in changed_paths if is_ui_path(p)]
    if not ui_paths:
        return []

    hit_shared = any(
        _match_glob(p, pat) for p in ui_paths for pat in shared_paths
    )
    if hit_shared:
        return list(screens)

    script_to_screens: dict[str, list[dict[str, Any]]] = {}
    for screen in screens:
        for script in screen.get("scripts") or []:
            script_to_screens.setdefault(str(script), []).append(screen)

    found: dict[str, dict[str, Any]] = {}
    for path in ui_paths:
        norm = path.replace("\\", "/").lstrip("./")
        for screen in script_to_screens.get(norm, []):
            found[str(screen["id"])] = screen
        # Also match when a UI script path changes under scripts/ui/
        if norm.startswith("scripts/ui/"):
            for script, bucket in script_to_screens.items():
                if norm == script or norm.endswith("/" + script):
                    for screen in bucket:
                        found[str(screen["id"])] = screen

    # Unmapped UI script under scripts/ui/ still counts as UI change with no
    # screen — callers treat empty + ui_paths as a contract failure.
    return list(found.values())


def parse_ux_screenshot_table(body: str) -> dict[str, str]:
    """Parse `## UX screenshots` markdown table → {screen_id: url}."""
    if not body:
        return {}
    match = _SCREENSHOT_SECTION.search(body)
    if not match:
        return {}
    rest = body[match.end() :]
    next_heading = re.search(r"^##\s+", rest, re.MULTILINE)
    section = rest[: next_heading.start()] if next_heading else rest
    out: dict[str, str] = {}
    for row in _TABLE_ROW.finditer(section):
        screen = row.group(1).strip().strip("`")
        url = row.group(2).strip()
        if screen.lower() in {"screen", "--------", "---"}:
            continue
        if screen.startswith("-"):
            continue
        out[screen] = url
    return out


def screen_by_id(
    screens: list[dict[str, Any]], screen_id: str
) -> dict[str, Any] | None:
    for screen in screens:
        if str(screen.get("id")) == screen_id:
            return screen
    return None


def format_failure_scripts(screen: dict[str, Any]) -> str:
    scripts = screen.get("scripts") or []
    return ", ".join(str(s) for s in scripts) if scripts else "(no scripts)"
