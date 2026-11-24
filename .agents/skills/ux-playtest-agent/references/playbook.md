# Desktop interaction playbook

## Launch

Use [`launch-game`](../../launch-game/SKILL.md) — do not `godot &` from the agent shell.

```bash
tools/launch_game.sh                  # or --restart / --clear-cache when needed
tools/launch_game.sh -- --home=ARS --away=LIV   # optional direct fixture
```

Cold start normally opens the main menu (Start Sim · Settings · Quit).

## Drive the window (Linux)

Prefer `xdotool` against the Godot window for this project path:

```bash
# Focus the game window (title often includes Godot / project name)
WID=$(xdotool search --name "Godot" | tail -1)
xdotool windowactivate --sync "$WID"
xdotool key --window "$WID" space          # pause / resume
xdotool key --window "$WID" 4              # speed ×8
xdotool key --window "$WID" h              # highlights ↔ full match
xdotool key --window "$WID" t              # fixture picker
xdotool key --window "$WID" m              # main menu
xdotool mousemove --window "$WID" X Y click 1
```

Controls (from product README): Space pause; 1–4 speed; H mode; S skip; R restart;
T teams; M menu; Esc quit confirm; N names; C camera; wheel zoom; hover tooltip;
click pin player.

## Screenshots

Capture the live window to a temp PNG, then **Read** the image to judge UX:

```bash
OUT=/tmp/ux-playtest-$(date +%Y%m%d)-$RANDOM.png
# ImageMagick
import -window "$WID" "$OUT"
# or: gnome-screenshot -w -f "$OUT"
```

Copy keepers into the wiki clone under `evidence/images/` before push.

## Short video (when motion matters)

No in-engine video flag. For timing / animation / scroll bugs only, record a short
clip (≤20s) with `ffmpeg` x11grab (or host equivalent), commit under
`evidence/images/`, and link from the run page. Prefer stills when a frame shows
the defect.

## Do not

- Rely only on headless `tools/sim_round.gd` — that is not a UX playtest.
- Use `--shots=` / DevCapture as the primary path (poses are fine as a supplement,
  not a substitute for interactive play).
- Kill the game unless restarting for a stuck state or finishing the session.
