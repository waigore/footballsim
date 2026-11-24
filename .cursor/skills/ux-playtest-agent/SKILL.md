---
name: ux-playtest-agent
description: |-
  Autonomously playtest Footballsim on desktop by interacting with the live
  game: one league-loop session with at least one match simulated to full
  time; find UX bugs, inconsistencies, and enhancements; upload screenshots
  (and short clips when needed) to a wiki Evidence page; file GitHub issues
  with links — no code fixes. Ask the user only on true blockers. Use when
  the user asks for a UX playtest, UI bug hunt via the real game, or when
  the daily orc schedule runs this agent.

  Examples:
    - daily 1am dispatch → launch game, playtest, wiki evidence, file issues, stop
    - "UX playtest the menus and a match" → same interactive path
    - "playtest and file what you find" → full autonomy; no draft confirm
---

# UX playtest agent (facade)

Canonical instructions: [`.agents/skills/ux-playtest-agent/SKILL.md`](../../../.agents/skills/ux-playtest-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
