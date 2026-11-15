#!/usr/bin/env python3
"""CI gate: AI-surface PRs must ship a signed ai-bench report ≥ baseline.

Bootstrap: if the ai-bench hill tree is missing, exit 0 with a note.
When `.autolab/hills/ai-bench` exists, enforce report ≥ baseline (same contract
as Empires of the Sea). Extend this script when the hill is added.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HILL = ROOT / ".autolab" / "hills" / "ai-bench"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default="origin/main",
        help="Git base ref (reserved for when the hill exists).",
    )
    parser.parse_args()

    if not HILL.is_dir():
        print(
            "ai-bench hill not present — check no-op until "
            ".autolab/hills/ai-bench is scaffolded."
        )
        return 0

    print(
        "ai-bench hill present but full verify not ported yet; "
        "fail closed until check_ai_bench_report is completed.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
