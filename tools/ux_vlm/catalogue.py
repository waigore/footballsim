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

# Screen kinds drive the CTA rule. Flow screens (the path to a match or a
# season) must name their primary door; browse and overlay screens must not.
SCREEN_KINDS = ("flow", "browse", "overlay")
CTA_SIDES = ("left", "center", "right")


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
    validate_screens(screens, screens_path)
    return rubrics, screens, shared


def validate_screens(screens: list[dict[str, Any]], path: Path) -> None:
    """Fail closed on a catalogue that cannot enforce the CTA map.

    A flow screen without `primary_cta` would silently fall back to the soft
    "obvious primary door" wording that let a hub ship without CONTINUE.
    """
    seen: set[str] = set()
    for screen in screens:
        sid = str(screen.get("id") or "").strip()
        if not sid:
            raise ValueError(f"{path}: a screen has no id")
        if sid in seen:
            raise ValueError(f"{path}: duplicate screen id {sid!r}")
        seen.add(sid)
        kind = str(screen.get("kind") or "").strip().lower()
        if kind not in SCREEN_KINDS:
            raise ValueError(
                f"{path}: screen {sid!r} has kind {kind!r}; "
                f"expected one of {', '.join(SCREEN_KINDS)}"
            )
        cta = screen.get("primary_cta")
        if cta is None:
            if kind == "flow":
                raise ValueError(
                    f"{path}: flow screen {sid!r} must declare primary_cta "
                    "(labels: [<door label>], optional side: right)"
                )
            continue
        if kind != "flow":
            raise ValueError(
                f"{path}: only flow screens declare primary_cta "
                f"({sid!r} is {kind})"
            )
        if not isinstance(cta, dict):
            raise ValueError(f"{path}: screen {sid!r} primary_cta must be a mapping")
        labels = cta.get("labels")
        if not isinstance(labels, list) or not labels:
            raise ValueError(f"{path}: screen {sid!r} primary_cta needs labels")
        for label in labels:
            if not str(label).strip():
                raise ValueError(f"{path}: screen {sid!r} has an empty CTA label")
        side = str(cta.get("side") or "").strip().lower()
        if side and side not in CTA_SIDES:
            raise ValueError(
                f"{path}: screen {sid!r} primary_cta side {side!r}; "
                f"expected one of {', '.join(CTA_SIDES)}"
            )


def cta_labels(screen: dict[str, Any]) -> list[str]:
    """Required primary-CTA labels for a screen (empty when it has none)."""
    cta = screen.get("primary_cta") or {}
    return [str(label).strip() for label in (cta.get("labels") or [])]


def cta_side(screen: dict[str, Any]) -> str:
    """Required side for the primary CTA ('', 'left', 'center', or 'right')."""
    cta = screen.get("primary_cta") or {}
    return str(cta.get("side") or "").strip().lower()


def normalise_label(text: str) -> str:
    """Upper-case, punctuation-free form so 'Kick Off' matches 'KICK OFF'."""
    return " ".join(re.sub(r"[^A-Z0-9]+", " ", str(text).upper()).split())


def label_seen(label: str, seen_text: str) -> bool:
    """True when `label` appears as whole words inside `seen_text`."""
    wanted = normalise_label(label)
    if not wanted:
        return False
    return f" {wanted} " in f" {normalise_label(seen_text)} "


def cta_requirement(screen: dict[str, Any]) -> str:
    """One plain-English line naming what the grader must see for this screen."""
    sid = str(screen.get("id") or "screen")
    title = str(screen.get("title") or sid)
    kind = str(screen.get("kind") or "").strip().lower()
    if kind == "flow":
        labels = cta_labels(screen)
        pretty = " or ".join(f"'{label}'" for label in labels)
        side = cta_side(screen)
        where = (
            f" and positioned on the {side}-hand side of the screen" if side else ""
        )
        return (
            f'This screen is {sid} ("{title}"), a flow screen. Required primary '
            f"CTA: one clear, legible control labelled {pretty}{where}. Fail the "
            "cta rubric if that exact label is missing, cut off, unreadable, or "
            "too weak to spot; another door does not stand in for it."
        )
    if kind == "browse":
        return (
            f'This screen is {sid} ("{title}"), a browse screen. BACK (or an '
            "equally clear leave/dismiss door) is an acceptable primary action; "
            "do not require CONTINUE."
        )
    return (
        f'This screen is {sid} ("{title}"), an overlay. Do not require a '
        "CONTINUE door; judge only whether the live chrome reads clearly."
    )


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
