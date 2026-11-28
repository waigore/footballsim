#!/usr/bin/env python3
"""Enforce P3 architecture + cheap static P1 bars. See docs/rubric.md."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SOFT_MAX_LINES = 400
SOFT_MAX_METHODS = 25
HARD_MAX_LINES = 650
HARD_MAX_METHODS = 45
MAX_SIZE_ALLOWLIST_ENTRIES = 5
REACH_IN_DEPTH = 3

ALLOWED_GD_PREFIXES = (
    "scripts/",
    "scenes/",
    "ui/",
    "autoload/",
    "tests/",
    "playtests/",
    "tools/",
    "addons/",
)

SIZE_ALLOWLIST_PATH = ROOT / "tools" / "arch_size_allowlist.txt"
SIM_PACKAGES_PATH = ROOT / "tools" / "arch_sim_packages.toml"
AUTOLOAD_ALLOWLIST_PATH = ROOT / "tools" / "arch_autoload_allowlist.txt"
AUTOLOAD_CONSUMERS_PATH = ROOT / "tools" / "arch_autoload_consumers.txt"
UI_ICONS_PATH = ROOT / "tools" / "arch_ui_icons.txt"
PROJECT_GODOT = ROOT / "project.godot"

# Presentation / scene paths sim+data must not load (RUB-P3-03).
LOAD_RES_RE = re.compile(r"""(?:preload|load)\s*\(\s*["'](res://[^"']+)["']""")
EXTENDS_RES_RE = re.compile(r"""(?m)^extends\s+["'](res://[^"']+)["']""")
FUNC_SIG_RE = re.compile(
    r"(?ms)^(static\s+)?func\s+(\w+)\s*\((.*?)\)\s*(?:->\s*[^:\n]+)?\s*:"
)

# Layer of a res:// or repo-relative path for dependency bans.
_LAYER_PREFIXES = (
    ("scripts/sim/", "sim"),
    ("scripts/data/", "data"),
    ("scripts/ui/", "ui"),
    ("scripts/view/", "view"),
    ("scripts/platform/", "platform"),
    ("scripts/audio/", "audio"),
    ("autoload/", "autoload"),
    ("scenes/", "scenes"),
    ("ui/", "ui_scenes"),
)
# src_layer -> forbidden target layers (presentation must not flow into core).
LAYER_FORBIDDEN: dict[str, frozenset[str]] = {
    "sim": frozenset(
        {"ui", "view", "scenes", "ui_scenes", "autoload", "audio", "platform"}
    ),
    "data": frozenset(
        {"ui", "view", "scenes", "ui_scenes", "autoload", "platform"}
    ),
    "view": frozenset({"ui"}),
}
CORE_PURE_DIRS = (
    ROOT / "scripts" / "sim",
    ROOT / "scripts" / "data",
    ROOT / "scripts" / "rules",
)
CORE_OK_EXTENDS = frozenset({"RefCounted", "Object", "Resource"})
CORE_PURE_PATH_PREFIXES = ("scripts/sim/", "scripts/data/", "scripts/rules/")

# REQ-P1-01 / RUB-P1-01 — 2D primary; no 3D core loops.
FORBIDDEN_3D_EXTENDS = frozenset(
    {
        "Node3D",
        "Camera3D",
        "MeshInstance3D",
        "Sprite3D",
        "AnimatedSprite3D",
        "GPUParticles3D",
        "CPUParticles3D",
        "CSGCombiner3D",
        "CSGBox3D",
        "CSGSphere3D",
        "CSGCylinder3D",
        "CSGMesh3D",
        "CharacterBody3D",
        "RigidBody3D",
        "StaticBody3D",
        "AnimatableBody3D",
        "Area3D",
        "CollisionShape3D",
        "CollisionPolygon3D",
        "Light3D",
        "DirectionalLight3D",
        "OmniLight3D",
        "SpotLight3D",
        "GeometryInstance3D",
        "Label3D",
        "Decal",
        "VoxelGI",
    }
)
SCENE_3D_TYPE_RE = re.compile(
    r'\btype="('
    + "|".join(sorted(FORBIDDEN_3D_EXTENDS, key=len, reverse=True))
    + r')"'
)
MESH_SUFFIXES = frozenset({".glb", ".gltf", ".fbx"})
# REQ-P1-08 — no project default icon as player-facing chrome.
DEFAULT_ICON_RE = re.compile(r"res://icon\.(?:svg|png)\b")
PANEL_ICON_RE = re.compile(r'"icon"\s*:\s*"([a-z0-9_]+)"')
LEAGUE_PANEL_GD = ROOT / "scripts" / "ui" / "league_panel.gd"
DATE_OVERLAY_GD = ROOT / "scripts" / "ui" / "date_overlay.gd"
# REQ-P1-05 — Godot hover-only APIs (tooltips / mouse_entered) gate nothing critical.
HOVER_ONLY_API_RE = re.compile(
    r"""(?x)
    \.connect\s*\(\s*["']mouse_(?:entered|exited)["']
    | \bmouse_(?:entered|exited)\.connect\b
    | \b(?:MOUSE_ENTERED|MOUSE_EXITED)\b
    | \.tooltip_text\s*=
    | \bset_tooltip(?:_string)?\s*\(
    | \bhint_tooltip\b
    """
)

FUNC_RE = re.compile(r"(?m)^(static\s+)?func\s+")
EXTENDS_RE = re.compile(r"(?m)^extends\s+(\S+)")
GET_NODE_RE = re.compile(
    r"""get_node\s*\(\s*(?:["']([^"']+)["']|([A-Za-z_][\w.]*))"""
)
DOLLAR_PATH_RE = re.compile(r"(?<![\w$])\$([A-Za-z_][\w/]*)")
PERCENT_RE = re.compile(r"(?<![\w%])%[A-Za-z_]\w*")
PLATFORM_API_RE = re.compile(
    r"\b(?:OS\.get_name|OS\.get_distribution_name|DisplayServer\.get_name)\s*\("
)
NODEISH_EXTENDS = frozenset(
    {
        "Node",
        "Node2D",
        "Node3D",
        "Control",
        "CanvasItem",
        "CanvasLayer",
        "Viewport",
        "Window",
        "AcceptDialog",
        "ConfirmationDialog",
        "FileDialog",
        "Popup",
        "PopupPanel",
        "PopupMenu",
        "TabContainer",
        "Panel",
        "PanelContainer",
        "Container",
        "BoxContainer",
        "HBoxContainer",
        "VBoxContainer",
        "GridContainer",
        "MarginContainer",
        "ScrollContainer",
        "SubViewport",
        "SubViewportContainer",
        "Camera2D",
        "Camera3D",
        "Sprite2D",
        "AnimatedSprite2D",
        "Label",
        "RichTextLabel",
        "Button",
        "TextureRect",
        "ColorRect",
        "ItemList",
        "Tree",
        "LineEdit",
        "TextEdit",
        "SpinBox",
        "Slider",
        "ProgressBar",
        "Timer",
        "AnimationPlayer",
        "AudioStreamPlayer",
        "AudioStreamPlayer2D",
        "CharacterBody2D",
        "RigidBody2D",
        "StaticBody2D",
        "Area2D",
        "CollisionShape2D",
        "TileMap",
        "TileMapLayer",
    }
)
def _script_layer(rel_or_res: str) -> str | None:
    path = rel_or_res.replace("res://", "")
    for prefix, name in _LAYER_PREFIXES:
        if path.startswith(prefix):
            return name
    return None


def _core_extends_ok(base: str) -> bool:
    if base in CORE_OK_EXTENDS:
        return True
    if base in NODEISH_EXTENDS or base in FORBIDDEN_3D_EXTENDS:
        return False
    if len(base) >= 2 and base[0] in "\"'" and base[-1] == base[0]:
        inner = base[1:-1]
        if inner.startswith("res://"):
            rel = inner[len("res://") :]
            return any(rel.startswith(p) for p in CORE_PURE_PATH_PREFIXES)
        return False
    # Bare class_name of a peer RefCounted type — reject known Node-ish only.
    if re.match(r"^[A-Za-z_]\w*$", base):
        return True
    return False


def _strip_comments_and_strings(text: str) -> str:
    """Rough strip so string literals do not trigger reach-in / API scans."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"' and text[i : i + 3] == '"""':
            end = text.find('"""', i + 3)
            out.append(" ")
            i = n if end < 0 else end + 3
            continue
        if ch == "'" and text[i : i + 3] == "'''":
            end = text.find("'''", i + 3)
            out.append(" ")
            i = n if end < 0 else end + 3
            continue
        if ch in "\"'":
            quote = ch
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        if ch == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def _path_depth(node_path: str) -> int:
    cleaned = node_path.strip().strip("/")
    if not cleaned:
        return 0
    # Ignore leading '.' / '..' segments for depth of named nodes.
    parts = [p for p in cleaned.split("/") if p and p not in (".", "..")]
    return len(parts)


def parse_size_allowlist(text: str) -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"\s+", line)
        if len(parts) != 3:
            raise ValueError(f"bad size allowlist line: {raw!r}")
        path, max_lines, max_methods = parts
        result[path] = (int(max_lines), int(max_methods))
    return result


def load_size_allowlist() -> dict[str, tuple[int, int]]:
    if not SIZE_ALLOWLIST_PATH.is_file():
        return {}
    return parse_size_allowlist(SIZE_ALLOWLIST_PATH.read_text(encoding="utf-8"))


def load_size_allowlist_at_ref(base_ref: str) -> dict[str, tuple[int, int]] | None:
    """Baseline allowlist at base_ref, or None if unavailable."""
    rel = SIZE_ALLOWLIST_PATH.relative_to(ROOT).as_posix()
    try:
        out = subprocess.check_output(
            ["git", "show", f"{base_ref}:{rel}"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    try:
        return parse_size_allowlist(out)
    except ValueError:
        return None


def check_size_allowlist_policy(
    failures: list[str],
    allowlist: dict[str, tuple[int, int]],
    base_ref: str,
) -> None:
    rel = SIZE_ALLOWLIST_PATH.relative_to(ROOT).as_posix()
    if len(allowlist) > MAX_SIZE_ALLOWLIST_ENTRIES:
        failures.append(
            f"{rel}:1: RUB-P3-01 size allowlist has {len(allowlist)} entries "
            f"(max {MAX_SIZE_ALLOWLIST_ENTRIES}); split oversized scripts "
            f"instead of growing the list"
        )
    baseline = load_size_allowlist_at_ref(base_ref)
    if baseline is None:
        return
    for path, (lines, methods) in allowlist.items():
        if path not in baseline:
            continue
        prev_lines, prev_methods = baseline[path]
        if lines > prev_lines or methods > prev_methods:
            failures.append(
                f"{rel}:1: RUB-P3-01 ratchet raised for {path} "
                f"({prev_lines}/{prev_methods} → {lines}/{methods}); "
                f"only shrink or remove — split the file instead"
            )


def load_autoload_allowlist() -> set[str]:
    names: set[str] = set()
    if not AUTOLOAD_ALLOWLIST_PATH.is_file():
        return names
    for raw in AUTOLOAD_ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        names.add(line.split()[0])
    return names


def parse_project_autoloads() -> list[tuple[str, int]]:
    """Return (name, line_no) for each [autoload] entry."""
    if not PROJECT_GODOT.is_file():
        return []
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    lines = text.splitlines()
    in_section = False
    found: list[tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == "[autoload]"
            continue
        if not in_section or not stripped or stripped.startswith(";"):
            continue
        if "=" not in stripped:
            continue
        name = stripped.split("=", 1)[0].strip()
        if name:
            found.append((name, i))
    return found


def iter_script_gd() -> list[Path]:
    return sorted((ROOT / "scripts").rglob("*.gd"))


def check_layout(failures: list[str]) -> None:
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if any(rel.startswith(prefix) for prefix in ALLOWED_GD_PREFIXES):
            continue
        # Ignore editor/generated and hill fixtures (frozen planners for eval).
        if rel.startswith(".godot/") or rel.startswith(".autolab/"):
            continue
        failures.append(
            f"{rel}:1: RUB-P3-01 game .gd must live under "
            f"{', '.join(ALLOWED_GD_PREFIXES)}"
        )


def check_size(failures: list[str], allowlist: dict[str, tuple[int, int]]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        lines = len(text.splitlines())
        methods = len(FUNC_RE.findall(text))
        max_lines, max_methods = allowlist.get(rel, (SOFT_MAX_LINES, SOFT_MAX_METHODS))

        if lines > HARD_MAX_LINES or methods > HARD_MAX_METHODS:
            failures.append(
                f"{rel}:1: RUB-P3-01 exceeds hard ceiling "
                f"({lines} lines / {methods} methods; max "
                f"{HARD_MAX_LINES}/{HARD_MAX_METHODS})"
            )
            continue

        if lines > max_lines or methods > max_methods:
            kind = "allowlist ratchet" if rel in allowlist else "soft max"
            failures.append(
                f"{rel}:1: RUB-P3-01 exceeds {kind} "
                f"({lines} lines / {methods} methods; max {max_lines}/{max_methods})"
            )


def check_reach_ins(failures: list[str]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        # Keep original for line numbers; scan a comment-stripped copy carefully.
        # For get_node string args we need the original string content.
        for match in GET_NODE_RE.finditer(raw):
            node_path = match.group(1)
            if node_path is None:
                continue  # NodePath variable — skip
            # Skip if this match sits inside a comment roughly.
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix:
                continue
            depth = _path_depth(node_path)
            if depth >= REACH_IN_DEPTH:
                line = _line_of(raw, match.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-02 deep get_node "
                    f"(depth {depth} ≥ {REACH_IN_DEPTH}): {node_path!r}"
                )

        scanned = _strip_comments_and_strings(raw)
        # Map indexes approximately by scanning original with same regex on raw
        # for $ paths — use raw but ignore comments via line prefix check.
        for match in DOLLAR_PATH_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix:
                continue
            # Skip if inside a string (simple: odd quotes before on line).
            if prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            node_path = match.group(1)
            depth = _path_depth(node_path)
            if depth >= REACH_IN_DEPTH:
                line = _line_of(raw, match.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-02 deep $ reach-in "
                    f"(depth {depth} ≥ {REACH_IN_DEPTH}): ${node_path}"
                )
        _ = scanned  # reserved for future tighter scans


def check_autoloads(failures: list[str], allowlist: set[str]) -> None:
    for name, line in parse_project_autoloads():
        if name not in allowlist:
            failures.append(
                f"project.godot:{line}: RUB-P3-02 undeclared autoload {name!r} "
                f"(add to tools/arch_autoload_allowlist.txt only if cross-cutting)"
            )


def check_core_purity(failures: list[str]) -> None:
    """RUB-P3-03: sim/data/rules stay RefCounted-ish; no scene tree reach-ins."""
    paths: list[Path] = []
    for root in CORE_PURE_DIRS:
        if root.is_dir():
            paths.extend(sorted(root.rglob("*.gd")))
    for path in paths:
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        ext = EXTENDS_RE.search(raw)
        if not ext:
            failures.append(f"{rel}:1: RUB-P3-03 missing extends")
        else:
            base = ext.group(1)
            if not _core_extends_ok(base):
                line = _line_of(raw, ext.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-03 sim/data/rules must extend "
                    f"RefCounted/Object/Resource (or pure peer), not {base}"
                )

        for match in GET_NODE_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 sim/data/rules must not call get_node"
            )

        for match in DOLLAR_PATH_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix or prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 sim/data/rules must not use $ node paths"
            )

        for match in PERCENT_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix or prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            name = match.group(0)[1:]  # drop '%'
            # Skip printf-style specs (%s, %d, %02d) and modulo leftovers.
            if len(name) <= 1 or name[0].islower():
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 sim/data/rules must not use "
                f"% unique node names"
            )


def check_layer_imports(failures: list[str]) -> None:
    """RUB-P3-03: ban upward preload/load/extends from core into presentation."""
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        src = _script_layer(rel)
        if src is None or src not in LAYER_FORBIDDEN:
            continue
        forbidden = LAYER_FORBIDDEN[src]
        raw = path.read_text(encoding="utf-8")
        for match in LOAD_RES_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            target = match.group(1)
            tlayer = _script_layer(target)
            if tlayer is None or tlayer not in forbidden:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 layer ban {src} must not load "
                f"{tlayer} ({target})"
            )
        for match in EXTENDS_RES_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            target = match.group(1)
            tlayer = _script_layer(target)
            if tlayer is None or tlayer not in forbidden:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 layer ban {src} must not extend "
                f"{tlayer} ({target})"
            )


def load_sim_packages() -> dict:
    """Load tools/arch_sim_packages.toml (packages, edges, ratchets)."""
    if not SIM_PACKAGES_PATH.is_file():
        raise ValueError(f"missing {SIM_PACKAGES_PATH.name}")
    with SIM_PACKAGES_PATH.open("rb") as fh:
        data = tomllib.load(fh)
    packages = data.get("packages") or {}
    edges = data.get("allowed_edges") or {}
    root = (data.get("root_allowlist") or {}).get("entries") or []
    edge_allow = (data.get("edge_allowlist") or {}).get("entries") or []
    if not isinstance(packages, dict) or not packages:
        raise ValueError("arch_sim_packages.toml: [packages] is empty")
    return {
        "packages": {str(k): str(v) for k, v in packages.items()},
        "edges": {str(k): [str(x) for x in (v or [])] for k, v in edges.items()},
        "root_allowlist": [str(x) for x in root],
        "edge_allowlist": [str(x) for x in edge_allow],
    }


SIM_CLASS_RE = re.compile(r"(?m)^class_name\s+(\w+)")
SIM_EXTENDS_TARGET_RE = re.compile(
    r"""(?m)^extends\s+["'](res://scripts/sim/[^"']+)["']"""
)


def _sim_package_of(rel: str, prefixes: dict[str, str]) -> str | None:
    """Return the package name whose prefix owns this sim path, else None."""
    for pkg, prefix in prefixes.items():
        if rel.startswith(prefix):
            return pkg
    return None


def _sim_edges(
    prefixes: dict[str, str],
) -> tuple[dict[str, list[tuple[str, str]]], dict[str, list[str]]]:
    """Return (edges, class_to_pkg).

    edges[src_pkg] -> list of (dst_pkg, detail) for every path/symbol edge the
    sim tree actually has. A package never points at itself.
    """
    sim_root = ROOT / "scripts" / "sim"
    files = sorted(sim_root.rglob("*.gd"))
    class_to_pkg: dict[str, str] = {}
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        pkg = _sim_package_of(rel, prefixes)
        m = SIM_CLASS_RE.search(path.read_text(encoding="utf-8"))
        if m and pkg is not None:
            class_to_pkg[m.group(1)] = pkg
    edges: dict[str, list[tuple[str, str]]] = {}
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        src = _sim_package_of(rel, prefixes)
        if src is None:
            continue
        raw = path.read_text(encoding="utf-8")
        for match in LOAD_RES_RE.finditer(raw):
            target = match.group(1).replace("res://", "")
            dst = _sim_package_of(target, prefixes)
            if dst is not None and dst != src:
                edges.setdefault(src, []).append((dst, f"load {target}"))
        for match in SIM_EXTENDS_TARGET_RE.finditer(raw):
            target = match.group(1).replace("res://", "")
            dst = _sim_package_of(target, prefixes)
            if dst is not None and dst != src:
                edges.setdefault(src, []).append((dst, f"extends {target}"))
        scanned = _strip_comments_and_strings(raw)
        for cls, dst in class_to_pkg.items():
            if dst == src:
                continue
            if re.search(rf"\b{re.escape(cls)}\b", scanned):
                edges.setdefault(src, []).append((dst, f"class_name {cls}"))
    return edges, class_to_pkg


def _would_cycle(edges: dict[str, list[tuple[str, str]]]) -> list[str]:
    """Return cycle descriptions found in the src->dst package graph."""
    graph: dict[str, set[str]] = {}
    for src, items in edges.items():
        for dst, _detail in items:
            graph.setdefault(src, set()).add(dst)
    cycles: list[str] = []
    state: dict[str, int] = {}

    def visit(node: str, stack: list[str]) -> None:
        state[node] = 1
        stack.append(node)
        for nxt in sorted(graph.get(node, ())):
            if state.get(nxt, 0) == 1:
                i = stack.index(nxt)
                cycles.append(" -> ".join(stack[i:] + [nxt]))
            elif state.get(nxt, 0) == 0:
                visit(nxt, stack)
        stack.pop()
        state[node] = 2

    for node in sorted(graph):
        if state.get(node, 0) == 0:
            visit(node, [])
    return cycles


def check_sim_packages(failures: list[str], manifest: dict) -> None:
    """RUB-P3-01/REQ-P3-01: sim placement + one-way package edges (#527)."""
    prefixes: dict[str, str] = manifest["packages"]
    allowed: dict[str, list[str]] = manifest["edges"]
    root_allow = manifest["root_allowlist"]
    edge_allow = set(manifest["edge_allowlist"])

    sim_root = ROOT / "scripts" / "sim"
    if not sim_root.is_dir():
        return

    # 1. Placement: every sim .gd maps to exactly one declared package.
    for path in sorted(sim_root.rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        if _sim_package_of(rel, prefixes) is not None:
            continue
        if rel in root_allow:
            continue
        failures.append(
            f"{rel}:1: RUB-P3-01 sim script lives outside a declared package "
            f"(move it under one of {sorted(prefixes)} or shrink-only "
            f"root_allowlist in tools/arch_sim_packages.toml)"
        )

    edges, _class_to_pkg = _sim_edges(prefixes)

    # 2. Weight any declared-but-unlisted edge by package + target.
    for src, items in edges.items():
        src_allowed = allowed.get(src, [])
        for dst, detail in items:
            if dst in src_allowed:
                continue
            key = f"{src}->{dst}"
            if key in edge_allow:
                continue
            failures.append(
                f"scripts/sim/{src}/:1: RUB-P3-01 illegal sim edge "
                f"{src} -> {dst} ({detail}); allow it in [allowed_edges] next "
                f"to a one-way DAG, or shrink-only edge_allowlist"
            )

    # 3. The declared DAG itself must be acyclic.
    declared: dict[str, list[tuple[str, str]]] = {
        src: [(dst, "declared") for dst in dsts]
        for src, dsts in allowed.items()
    }
    for src, dsts in declared.items():
        for dst, _d in dsts:
            if src in allowed.get(dst, []):
                failures.append(
                    f"tools/arch_sim_packages.toml:1: RUB-P3-01 declared edges "
                    f"are two-way: {src} -> {dst} and {dst} -> {src}"
                )

    # 4. Ratchets shrink-only vs base_ref.
    total_ratchet = len(root_allow) + len(edge_allow)
    max_ratchet = 5
    if total_ratchet > max_ratchet:
        failures.append(
            f"tools/arch_sim_packages.toml:1: RUB-P3-01 sim allowlists hold "
            f"{total_ratchet} entries (max {max_ratchet}); finish the move "
            f"instead of growing the ratchet"
        )


def check_sim_packages_ratchet(failures: list[str], manifest: dict, base_ref: str) -> None:
    """Shrink-only: the ratchet at HEAD must not exceed the base's."""
    rel = SIM_PACKAGES_PATH.relative_to(ROOT).as_posix()
    text = _git_show_text(base_ref, rel)
    if text is None:
        return
    try:
        base = tomllib.loads(text)
    except tomllib.TOMLDecodeError:
        return
    base_root = set((base.get("root_allowlist") or {}).get("entries") or [])
    base_edge = set((base.get("edge_allowlist") or {}).get("entries") or [])
    for entry in manifest["root_allowlist"]:
        if entry not in base_root:
            failures.append(
                f"{rel}:1: RUB-P3-01 root_allowlist grew ({entry!r} not at "
                f"{base_ref}); the ratchet is shrink-only"
            )
    for entry in manifest["edge_allowlist"]:
        if entry not in base_edge:
            failures.append(
                f"{rel}:1: RUB-P3-01 edge_allowlist grew ({entry!r} not at "
                f"{base_ref}); the ratchet is shrink-only"
            )


def load_autoload_consumers() -> dict[str, list[str]]:
    """Map autoload name -> list of allowed consumer path prefixes/globs."""
    result: dict[str, list[str]] = {}
    if not AUTOLOAD_CONSUMERS_PATH.is_file():
        return result
    for raw in AUTOLOAD_CONSUMERS_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"\s+", line, maxsplit=1)
        if len(parts) != 2:
            raise ValueError(
                f"bad autoload consumers line: {raw!r} "
                f"(want: Name<path-prefix>)"
            )
        name, prefix = parts
        result.setdefault(name, []).append(prefix)
    return result


def _path_allowed_for_autoload(rel: str, allowed: list[str]) -> bool:
    for entry in allowed:
        if entry.endswith(".gd"):
            if rel == entry:
                return True
        elif rel.startswith(entry):
            return True
    return False


def check_autoload_usage(
    failures: list[str],
    consumers: dict[str, list[str]],
) -> None:
    """RUB-P3-02: autoload identifiers only from declared consumer paths."""
    autoloads = parse_project_autoloads()
    if not autoloads:
        return
    # Own script path per autoload name from project.godot.
    own_script: dict[str, str] = {}
    if PROJECT_GODOT.is_file():
        text = PROJECT_GODOT.read_text(encoding="utf-8")
        in_section = False
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                in_section = stripped == "[autoload]"
                continue
            if not in_section or "=" not in stripped:
                continue
            name, rhs = stripped.split("=", 1)
            name = name.strip()
            m = re.search(r"res://[^\s\"']+", rhs)
            if name and m:
                own_script[name] = m.group(0).replace("res://", "")

    names = [n for n, _ in autoloads]
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        scanned = _strip_comments_and_strings(raw)
        for name in names:
            allowed = list(consumers.get(name, []))
            own = own_script.get(name, "")
            if own:
                allowed.append(own)
            allowed.append("tests/")
            if _path_allowed_for_autoload(rel, allowed):
                continue
            for match in re.finditer(rf"\b{re.escape(name)}\s*\.", scanned):
                line = _line_of(raw, min(match.start(), len(raw) - 1))
                failures.append(
                    f"{rel}:{line}: RUB-P3-02 autoload {name!r} used outside "
                    f"consumers (tools/arch_autoload_consumers.txt)"
                )


def _untyped_params(text: str) -> set[tuple[str, str]]:
    """Return (func_name, param_name) for parameters lacking a `: Type`."""
    found: set[tuple[str, str]] = set()
    for match in FUNC_SIG_RE.finditer(text):
        func_name = match.group(2)
        params = match.group(3).strip()
        if not params:
            continue
        depth = 0
        current: list[str] = []
        parts: list[str] = []
        for ch in params:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth = max(0, depth - 1)
            if ch == "," and depth == 0:
                parts.append("".join(current))
                current = []
                continue
            current.append(ch)
        if current:
            parts.append("".join(current))
        for part in parts:
            part = part.strip()
            if not part:
                continue
            # Drop default value.
            head = part.split("=", 1)[0].strip()
            # Typed if `: Type` present before optional default was stripped.
            if ":" in head:
                continue
            pname = head.split()[-1] if head else ""
            if not pname or not re.match(r"^_?[A-Za-z]\w*$", pname):
                continue
            found.add((func_name, pname))
    return found


def _git_show_text(base_ref: str, rel: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "show", f"{base_ref}:{rel}"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def _git_renames(base_ref: str) -> dict[str, str]:
    """Map new path -> old path for files renamed vs base_ref (follow moves)."""
    renames: dict[str, str] = {}
    for cmd in (
        ["git", "diff", "--name-status", "-M", "--diff-filter=R", f"{base_ref}...HEAD"],
        ["git", "diff", "--name-status", "-M", "--diff-filter=R", base_ref],
        ["git", "diff", "--name-status", "-M", "--diff-filter=R", "HEAD"],
    ):
        try:
            out = subprocess.check_output(
                cmd, cwd=ROOT, text=True, stderr=subprocess.DEVNULL
            )
        except subprocess.CalledProcessError:
            continue
        for line in out.splitlines():
            parts = line.split("\t")
            if len(parts) >= 3 and parts[0].startswith("R"):
                renames[parts[2].strip()] = parts[1].strip()
    return renames


def _base_text_for(base_ref: str, rel: str, renames: dict[str, str]) -> str | None:
    text = _git_show_text(base_ref, rel)
    if text is not None:
        return text
    old = renames.get(rel)
    if old is not None:
        return _git_show_text(base_ref, old)
    return None


def check_typed_diff(failures: list[str], base_ref: str) -> None:
    """RUB-P3-01: no new untyped func params on changed scripts/** .gd files."""
    changed = _git_changed_paths(base_ref)
    if not changed:
        return
    renames = _git_renames(base_ref)
    for rel in sorted(changed):
        if not rel.startswith("scripts/") or not rel.endswith(".gd"):
            continue
        path = ROOT / rel
        if not path.is_file():
            continue
        head_text = path.read_text(encoding="utf-8")
        head_unt = _untyped_params(head_text)
        base_text = _base_text_for(base_ref, rel, renames)
        base_unt = _untyped_params(base_text) if base_text is not None else set()
        new_unt = sorted(head_unt - base_unt)
        for func_name, pname in new_unt:
            failures.append(
                f"{rel}:1: RUB-P3-01 new untyped param {func_name}({pname}) "
                f"vs {base_ref} (add a type annotation)"
            )


def check_platform(failures: list[str]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("scripts/platform/"):
            continue
        raw = path.read_text(encoding="utf-8")
        for match in PLATFORM_API_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-05 platform API must live under "
                f"scripts/platform/** ({match.group(0)})"
            )


def _iter_scene_tscn() -> list[Path]:
    paths: list[Path] = []
    for prefix in ("scenes", "ui"):
        root = ROOT / prefix
        if root.is_dir():
            paths.extend(sorted(root.rglob("*.tscn")))
    return paths


def check_no_3d_core(failures: list[str]) -> None:
    """REQ-P1-01 / RUB-P1-01: no 3D nodes, scenes, or mesh assets in game paths."""
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        ext = EXTENDS_RE.search(raw)
        if ext and ext.group(1) in FORBIDDEN_3D_EXTENDS:
            line = _line_of(raw, ext.start())
            failures.append(
                f"{rel}:{line}: RUB-P1-01 3D extends {ext.group(1)} "
                f"(2D primary; no 3D core loops)"
            )

    for path in _iter_scene_tscn():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        for match in SCENE_3D_TYPE_RE.finditer(raw):
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P1-01 3D scene node type={match.group(1)!r} "
                f"(2D primary; no 3D core loops)"
            )

    skip_parts = {".godot", "addons", ".autolab"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in MESH_SUFFIXES:
            continue
        if any(part in skip_parts for part in path.parts):
            continue
        rel = path.relative_to(ROOT).as_posix()
        failures.append(
            f"{rel}:1: RUB-P1-01 3D mesh asset {path.suffix.lower()} "
            f"(2D primary; no 3D core loops)"
        )


def load_required_ui_icons() -> list[str]:
    if not UI_ICONS_PATH.is_file():
        return []
    icons: list[str] = []
    for raw in UI_ICONS_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        icons.append(line.split()[0])
    return icons


def check_ui_icons(failures: list[str]) -> None:
    """REQ-P1-08 / RUB-P1-08: required icons present; no default project icon."""
    rel_list = UI_ICONS_PATH.relative_to(ROOT).as_posix()
    required = load_required_ui_icons()
    if not required:
        failures.append(
            f"{rel_list}:1: RUB-P1-08 missing required UI icon list "
            f"(tools/arch_ui_icons.txt)"
        )
        return

    basenames: set[str] = set()
    for rel in required:
        path = ROOT / rel
        stem = Path(rel).stem
        basenames.add(stem)
        if not path.is_file():
            failures.append(f"{rel}:1: RUB-P1-08 missing required UI icon")
            continue
        if path.stat().st_size == 0:
            failures.append(f"{rel}:1: RUB-P1-08 UI icon file is empty")

    if LEAGUE_PANEL_GD.is_file():
        panel_rel = LEAGUE_PANEL_GD.relative_to(ROOT).as_posix()
        raw = LEAGUE_PANEL_GD.read_text(encoding="utf-8")
        for match in PANEL_ICON_RE.finditer(raw):
            name = match.group(1)
            line = _line_of(raw, match.start())
            if name not in basenames:
                failures.append(
                    f"{panel_rel}:{line}: RUB-P1-08 panel icon {name!r} "
                    f"not listed in {rel_list}"
                )
            icon_rel = f"assets/ui/league/{name}.png"
            if not (ROOT / icon_rel).is_file():
                failures.append(
                    f"{panel_rel}:{line}: RUB-P1-08 panel icon file missing "
                    f"({icon_rel})"
                )

    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        for match in DEFAULT_ICON_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P1-08 must not use project default icon "
                f"as UI chrome ({match.group(0)})"
            )


def check_no_hover_only_ux(failures: list[str]) -> None:
    """REQ-P1-05 / RUB-P1-05: no hover-only critical UX APIs in game UI."""
    scan_roots = (
        ROOT / "scripts",
        ROOT / "scenes",
        ROOT / "ui",
        ROOT / "autoload",
    )
    for root in scan_roots:
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.suffix not in {".gd", ".tscn"}:
                continue
            rel = path.relative_to(ROOT).as_posix()
            raw = path.read_text(encoding="utf-8")
            for match in HOVER_ONLY_API_RE.finditer(raw):
                line_start = raw.rfind("\n", 0, match.start()) + 1
                if "#" in raw[line_start : match.start()]:
                    continue
                # .tscn comments use ';' — still flag real property lines.
                line = _line_of(raw, match.start())
                failures.append(
                    f"{rel}:{line}: RUB-P1-05 hover-only API "
                    f"{match.group(0)!r} (critical UX needs tap/click path)"
                )

    if not DATE_OVERLAY_GD.is_file():
        return
    rel = DATE_OVERLAY_GD.relative_to(ROOT).as_posix()
    raw = DATE_OVERLAY_GD.read_text(encoding="utf-8")
    # Weekday reveal is the one shipped hover hint: touch must arm via hold.
    if "func showing" not in raw:
        failures.append(
            f"{rel}:1: RUB-P1-05 DateOverlay.showing() missing "
            f"(touch must reveal on hold, not hover-only)"
        )
        return
    showing = raw.split("func showing", 1)[1].split("\nfunc ", 1)[0]
    if "touch" not in showing or "holding" not in showing:
        failures.append(
            f"{rel}:1: RUB-P1-05 DateOverlay.showing() must arm on touch "
            f"via holding (no hover-only weekday reveal)"
        )


def _git_changed_paths(base_ref: str) -> set[str]:
    cmds = [
        ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base_ref}...HEAD"],
        ["git", "diff", "--name-only", "--diff-filter=ACMR", base_ref],
    ]
    # Also include unstaged/staged local changes when comparing to base.
    local = ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"]
    paths: set[str] = set()
    for cmd in cmds:
        try:
            out = subprocess.check_output(cmd, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        for line in out.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
        if paths:
            break
    try:
        out = subprocess.check_output(local, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
    except subprocess.CalledProcessError:
        pass
    return paths


def resolve_base_ref(cli_base: str | None) -> str:
    if cli_base:
        return cli_base
    env_base = os.environ.get("GITHUB_BASE_REF", "").strip()
    if env_base:
        return f"origin/{env_base}"
    return "origin/main"


def check_rules_tests_pairing(failures: list[str], base_ref: str) -> None:
    changed = _git_changed_paths(base_ref)
    if not changed:
        # First push / empty diff — nothing to pair.
        return
    core_changed = any(
        (
            p.startswith("scripts/rules/")
            or p.startswith("scripts/sim/")
        )
        and p.endswith(".gd")
        for p in changed
    )
    tests_changed = any(p.startswith("tests/") for p in changed)
    if core_changed and not tests_changed:
        failures.append(
            f"scripts/sim/:1: RUB-P3-04 scripts/sim/** (or rules) changed vs "
            f"{base_ref} without any tests/** change"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-rules-tests",
        action="store_true",
        default=os.environ.get("ARCH_LINT_RULES_DIFF", "") == "1",
        help="Fail if scripts/sim/** (or rules) changes without tests/** (CI).",
    )
    parser.add_argument(
        "--base-ref",
        default=None,
        help="Git ref for pairing/typed diff (default: GITHUB_BASE_REF or origin/main).",
    )
    args = parser.parse_args(argv)

    failures: list[str] = []
    try:
        size_allowlist = load_size_allowlist()
        autoload_allowlist = load_autoload_allowlist()
        autoload_consumers = load_autoload_consumers()
        sim_packages = load_sim_packages()
    except ValueError as exc:
        print(f"Allowlist error: {exc}", file=sys.stderr)
        return 2

    base_ref = resolve_base_ref(args.base_ref)
    check_layout(failures)
    check_size_allowlist_policy(failures, size_allowlist, base_ref)
    check_size(failures, size_allowlist)
    check_reach_ins(failures)
    check_autoloads(failures, autoload_allowlist)
    check_autoload_usage(failures, autoload_consumers)
    check_core_purity(failures)
    check_layer_imports(failures)
    check_sim_packages(failures, sim_packages)
    check_sim_packages_ratchet(failures, sim_packages, base_ref)
    check_platform(failures)
    check_no_3d_core(failures)
    check_ui_icons(failures)
    check_no_hover_only_ux(failures)
    check_typed_diff(failures, base_ref)
    if args.require_rules_tests:
        check_rules_tests_pairing(failures, base_ref)

    if failures:
        print("Architecture lint failures:", file=sys.stderr)
        for line in sorted(failures):
            print(f"  {line}", file=sys.stderr)
        print(
            "\nSee docs/rubric.md (RUB-P3-*, RUB-P1-01/05/08) and "
            "docs/requirements.md.",
            file=sys.stderr,
        )
        return 1

    print("arch-lint OK (RUB-P3-01…05, RUB-P1-01/05/08).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
