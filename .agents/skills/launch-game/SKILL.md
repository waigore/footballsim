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

# Launch game

Desktop playtest launcher. One job: start Godot so it **keeps running**.

## Do this

```bash
tools/launch_game.sh                  # launch; leave any existing instance alone
tools/launch_game.sh --restart        # quit this project’s instance, then launch
tools/launch_game.sh --clear-cache    # wipe userdata + .godot, reimport, restart
tools/launch_game.sh -- --home=ARS --away=LIV
```

Script resolves the repo root, prefers `/Applications/Godot.app` + `open -na` (LaunchServices detach), reimports when `.godot` is missing, verifies the process is still alive, prints `pid=…`.

## Never

- `godot --path . &` / `nohup` without the script — agent Shell exit kills those jobs; the window “dies” with an empty log and no crash report.
- `pkill` / kill the running game unless the user asked to restart, clear-cache, or stop it.
- Match `footballsim` loosely (hits `footballsim_all` worktrees). The script matches `--path <repo>` as an exact path token.

## Report

Say launched (or restarted) and the printed `pid`. On failure, show the script’s stderr / log tail. Do not keep polling or stop the game after a successful launch.
