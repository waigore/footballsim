---
name: calibrate-poisson-model
description: |-
  Run the Poisson calibration loop with the repo's own tools: audit λ, sample
  seasons against the last-10 PL scoring envelope, accept a candidate only when
  the scoring bands **and** the pre-tune home/draw/away mix both pass, then land
  the constants with tests. Use when AUTO seasons overscore or blow out, when a
  scoreline question is really a λ question, or when the envelope data or the
  model constants need a change.
---

# Calibrate the Poisson model (facade)

Canonical instructions: [`.agents/skills/calibrate-poisson-model/SKILL.md`](../../../.agents/skills/calibrate-poisson-model/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
