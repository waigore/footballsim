#!/usr/bin/env python3
"""Fail a PR that turns an abbreviation or a club-shaped string into an identity.

The seed mints a permanent club id (`ENG-MUN1`) and a UUID player id; an
abbreviation is display copy. This lint guards the data-access layer in
`scripts/` against three regressions:

1. A club lookup keyed by abbreviation alone (`WHERE abbr =`, `club_by_abbr`).
2. Player identity access that assumes something other than a UUID id, or that
   rebuilds a player id out of a club id.
3. A club id assembled from an abbreviation at runtime.

Reading `club["abbr"]` or selecting `c.abbr AS club_abbr` for display is fine
and never flagged.

Usage:
    python tools/lint_data_ids.py
    python tools/lint_data_ids.py --self-test
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_SCAN_DIRS = ("scripts",)
SKIP_DIRS = {"addons", ".godot", ".gd-tools", ".git"}

CLUB_BY_ABBR = [
    (re.compile(r"WHERE\s+(?:[A-Za-z_]+\.)?abbr\s*="), "a club lookup filtered by abbreviation"),
    (re.compile(r"\b(?:club|team|side|club_id)_by_abbr\b"), "a by-abbreviation club helper"),
    (re.compile(r"\b(?:club|team)_for_abbreviation\b"), "a by-abbreviation club helper"),
]
PLAYER_IDENTITY = [
    (re.compile(r"\bplayer_by_(?!id\b|name\b)\w+"), "a player lookup keyed by something but id/name"),
    (re.compile(r"player_id\s*(?::=|=(?!=))\s*(?!\s*\?)[^\n]*\bclub_id\b"),
     "a player id built from a club id"),
    (re.compile(r"player_id\s*\+\s*[\"']-"), "a player id glued onto a club id"),
    (re.compile(r"[\"']-[^\"']*[\"']\s*%\s*\[\s*club"), "a player id glued onto a club id"),
    (re.compile(r"player_id\.(?:begins_with|substr|split|trim_prefix)\("),
     "a player id parsed as if it embedded its club"),
]
CLUB_ID_FROM_ABBR = [
    (re.compile(r"\babbr\s*\+\s*[\"']-"), "a club id assembled from its abbreviation"),
    (re.compile(r"[\"']-[^\"']*[\"']\s*%\s*\[\s*[^\]]*\babbr\b"), "a club id assembled from its abbreviation"),
]

SAMPLES_BAD = {
    "club_by_abbr": 'var row := PLDatabase.row("SELECT * FROM club WHERE abbr = ?;", [code])\n',
    "club_helper": "static func club_by_abbr(abbr: String) -> Dictionary:\n\treturn {}\n",
    "player_from_club": 'var player_id := "%s-%s" % [club_id, suffix]\n',
    "player_glued": 'var player_id := club_id + "-" + suffix\n',
    "player_parsed": 'var club := player_id.substr(0, 3)\n',
    "player_by_club": "static func player_by_club(club_id: String) -> Dictionary:\n\treturn {}\n",
    "club_from_abbr": 'var club_id := abbr + "-1"\n',
}
SAMPLES_GOOD = {
    "display_read": 'var code := str(club.get("abbr", ""))\n',
    "display_select": 'var sql := "SELECT c.abbr AS club_abbr FROM club c " + "WHERE c.id = ?;"\n',
    "uuid_lookup": 'var row := PLDatabase.row("SELECT * FROM player WHERE id = ?;", [player_id])\n',
    "secondary_find": "func player_by_name(club_id: String, name: String) -> Dictionary:\n\treturn {}\n",
    "minted_id": 'var club_id := ClubIds.mint(country, abbr)\n',
    "sql_both_ids": 'var sql := "WHERE player_id = ? AND club_id = ?;"\n',
}


def _rules(text: str) -> list[tuple[re.Pattern[str], str]]:
    return CLUB_BY_ABBR + PLAYER_IDENTITY + CLUB_ID_FROM_ABBR


def scan_text(text: str) -> list[str]:
    problems: list[str] = []
    for pattern, reason in _rules(text):
        for match in pattern.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            problems.append(f"line {line}: {reason}: {match.group(0).strip()}")
    return problems


def scan_file(path: Path) -> list[str]:
    problems: list[str] = []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return problems
    for problem in scan_text(text):
        problems.append(f"{path.relative_to(ROOT)}: {problem}")
    return problems


def gd_files() -> list[Path]:
    out: list[Path] = []
    for folder in DATA_SCAN_DIRS:
        base = ROOT / folder
        if not base.is_dir():
            continue
        for path in base.rglob("*.gd"):
            if any(part in SKIP_DIRS for part in path.relative_to(ROOT).parts):
                continue
            out.append(path)
    return sorted(out)


def self_test() -> int:
    problems: list[str] = []
    for name, sample in SAMPLES_BAD.items():
        if not scan_text(sample):
            problems.append(f"self-test: the {name} sample was not caught")
    for name, sample in SAMPLES_GOOD.items():
        if scan_text(sample):
            problems.append(f"self-test: the {name} sample was flagged")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"self-test: {len(SAMPLES_BAD)} bad samples caught, {len(SAMPLES_GOOD)} good samples allowed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="prove the rules catch their samples")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    problems: list[str] = []
    for path in gd_files():
        problems.extend(scan_file(path))
    if problems:
        print("\n".join(f"FAIL {problem}" for problem in problems), file=sys.stderr)
        print("Club ids are stable ids and player ids are UUIDs; abbreviations are display-only.",
              file=sys.stderr)
        return 1
    print(f"data ids: OK ({len(gd_files())} scripts)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
