#!/usr/bin/env python3
"""Fail if tools/ holds leftover issue evidence, probes, or proto-tests.

Banned basenames under tools/** (theme shots, sweeps, CI/skill scripts OK):
  issueN_*.gd, checkN_*.gd, probe.gd / probeN.gd / probe_*.gd,
  test_*.gd, (tmp|scratch|debug)_*.gd

Real suites live in tests/. See AGENTS.md / docs/pull-requests.md.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"

BANNED: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^issue\d+_.+\.gd$"), "issue evidence / probe"),
    (re.compile(r"^check\d+_.+\.gd$"), "issue check script"),
    (re.compile(r"^probe\.gd$"), "numbered probe"),
    (re.compile(r"^probe\d+\.gd$"), "numbered probe"),
    (re.compile(r"^probe_.+\.gd$"), "named probe"),
    (re.compile(r"^test_.+\.gd$"), "proto-test (use tests/)"),
    (re.compile(r"^(tmp|scratch|debug)_.+\.gd$"), "scratch script"),
]


def iter_gd() -> list[Path]:
    if not TOOLS.is_dir():
        return []
    return sorted(p for p in TOOLS.rglob("*.gd") if p.is_file())


def banned_reason(name: str) -> str | None:
    for pattern, reason in BANNED:
        if pattern.match(name):
            return reason
    return None


def main() -> int:
    hits: list[str] = []
    scanned = 0
    for path in iter_gd():
        scanned += 1
        reason = banned_reason(path.name)
        if reason is None:
            continue
        rel = path.relative_to(ROOT)
        hits.append(f"{rel}: {reason}")

    if hits:
        print("Tools hygiene failures:", file=sys.stderr)
        for line in hits:
            print(f"  {line}", file=sys.stderr)
        print(
            f"\n{len(hits)} leftover script(s) under tools/. "
            "Delete them, or promote suites to tests/ and theme shots "
            "without issueN_/probe_/test_ prefixes.",
            file=sys.stderr,
        )
        return 1

    print(f"All {scanned} tools/**/*.gd filenames are clean.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
