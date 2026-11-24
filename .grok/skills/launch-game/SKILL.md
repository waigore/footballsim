---
name: launch-game
description: |-
  Launch The Manchester Derby (Footballsim) on desktop via tools/launch_game.sh
  so the process stays alive after the agent shell exits. Use when the user asks
  to run/launch/play the game, clear cache and run, or restart the desktop build.
  Do not background godot directly from the Shell tool.

  Examples:
    - "run the game" → tools/launch_game.sh
    - "clear cache and run" → tools/launch_game.sh --clear-cache
    - "restart the game" → tools/launch_game.sh --restart
    - "run ARS vs LIV" → tools/launch_game.sh -- --home=ARS --away=LIV
---

# Launch game (facade)

Canonical instructions: [`.agents/skills/launch-game/SKILL.md`](../../../.agents/skills/launch-game/SKILL.md).

Read that file and its `references/` as needed, then run the workflow there. Do not invent a parallel process.
