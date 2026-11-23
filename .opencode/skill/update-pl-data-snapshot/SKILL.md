---
name: update-pl-data-snapshot
description: |-
  Refresh the Premier League seed snapshot from exactly one source (ESPN
  preferred, Sofifa otherwise), bump db_version, rebuild the SQLite seed and
  verify it. Use when the league table, fixtures, player identity or real-world
  season figures need updating, or when a new season starts.
---

# Update the PL data snapshot (facade)

Canonical instructions: [`.agents/skills/update-pl-data-snapshot/SKILL.md`](../../../.agents/skills/update-pl-data-snapshot/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
