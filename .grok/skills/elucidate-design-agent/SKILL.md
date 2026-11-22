---
name: elucidate-design-agent
description: |-
  Autonomously analyze Footballsim wiki (Simulation rules + AI) for unclear,
  contradictory, or underspecified statements; write a precise P5-first design
  (other pillars accounted for); file one GitHub issue per theme with the
  question label only — no wiki edits, no code, no PR. Ask the user only on
  true blockers. Use when the user asks to elucidate design, clarify wiki gaps,
  resolve rules/AI ambiguity, P5 design climb, or run the elucidate-design agent.

  Examples:
    - no target → judge related wiki gaps; file question issue; stop
    - cited theme → that theme only; batch related gaps; file issue
    - cross-page ambiguity → propose one design; file question issue
---

# Elucidate design agent (facade)

Canonical instructions: [`.agents/skills/elucidate-design-agent/SKILL.md`](../../../.agents/skills/elucidate-design-agent/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
