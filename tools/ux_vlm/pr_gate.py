#!/usr/bin/env python3
"""PR gate: map UI diffs → screens, require ## UX screenshots, run check_screens.

Exit 0 (no-op) when no UI paths changed.
Exit 1 when UI changed without complete screenshot links, >10 screens, or VLM fail.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from catalogue import (  # noqa: E402
    DEFAULT_RUBRICS,
    DEFAULT_SCREENS,
    is_ui_path,
    load_catalogue,
    parse_ux_screenshot_table,
    screens_for_paths,
)
from check_screens import MAX_PR_IMAGES, run_items  # noqa: E402


def _changed_files(base_ref: str) -> list[str]:
    cmd = ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base_ref}...HEAD"]
    out = subprocess.check_output(cmd, text=True)
    return [line.strip() for line in out.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default="origin/main",
        help="Git base ref for the PR diff (default origin/main)",
    )
    parser.add_argument(
        "--pr-body",
        help="PR body text, or @path / path to a file containing the body",
    )
    parser.add_argument("--rubrics", type=Path, default=DEFAULT_RUBRICS)
    parser.add_argument("--screens", type=Path, default=DEFAULT_SCREENS)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--fail-file", type=Path)
    args = parser.parse_args()

    rubrics, screens, shared = load_catalogue(args.rubrics, args.screens)
    changed = _changed_files(args.base)
    ui_changed = [p for p in changed if is_ui_path(p)]
    if not ui_changed:
        print("No UI paths changed — ux-vlm no-op.")
        return 0

    affected = screens_for_paths(ui_changed, screens, shared)
    print(f"UI paths changed ({len(ui_changed)}):")
    for path in ui_changed:
        print(f"  - {path}")

    if not affected:
        print(
            "ERROR: UI paths changed but none map to the screen catalogue.\n"
            "Add the scripts to tools/ux_vlm/screens.yaml or adjust the diff.",
            file=sys.stderr,
        )
        return 1

    if len(affected) > MAX_PR_IMAGES:
        ids = ", ".join(str(s["id"]) for s in affected)
        print(
            f"ERROR: {len(affected)} affected screens exceeds max {MAX_PR_IMAGES}.\n"
            f"Split the PR. Affected: {ids}",
            file=sys.stderr,
        )
        return 1

    body = ""
    if args.pr_body:
        raw = args.pr_body
        path = Path(raw[1:] if raw.startswith("@") else raw)
        if raw.startswith("@") or path.exists():
            body = path.read_text(encoding="utf-8")
        else:
            body = raw

    table = parse_ux_screenshot_table(body)
    missing: list[str] = []
    items: list[dict[str, str]] = []
    for screen in affected:
        sid = str(screen["id"])
        url = table.get(sid)
        if not url:
            missing.append(sid)
            continue
        items.append({"screen_id": sid, "image_url": url})

    if missing:
        print(
            "ERROR: UI paths changed but the PR body is missing desktop wiki "
            "screenshot URLs for affected screens.\n"
            "Add a section:\n\n"
            "## UX screenshots\n"
            "| screen | url |\n"
            "|--------|-----|\n"
            "| <screen-id> | https://raw.githubusercontent.com/wiki/... |\n\n"
            f"Missing: {', '.join(missing)}",
            file=sys.stderr,
        )
        return 1

    print(f"Running VLM check on {len(items)} screen(s)…")
    return run_items(
        items,
        rubrics,
        screens,
        dry_run=args.dry_run,
        fail_file=args.fail_file,
    )


if __name__ == "__main__":
    raise SystemExit(main())
