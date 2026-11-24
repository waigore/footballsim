# Football Sim

A broadcast-style, top-down 2D football simulator in Godot 4.7. Every player is an
individual agent driven by EA SPORTS FC 26 attributes; the ball is simulated in 3D
(x, y, height, spin), so lofted passes and shots carry real depth. Cold start opens
the main menu (Start Sim · Settings · Quit); the default fixture is Manchester
United v Manchester City and any of the 20 Premier League clubs can play.

## Run

```bash
godot --path .            # or open project.godot in Godot 4.7 and press F5
godot --path . -- --home=ARS --away=LIV   # start a specific fixture
```

The match starts in **Highlights** mode: the engine fast-simulates between dangers,
rewinds seven seconds, and plays the build-up live.

```bash
godot --path . -- --shots=5,20,45 --quit=50   # capture PNGs to shots/ (debug)
godot --path . -- --focus=8                    # open with a player pinned
```

## Controls

| Key | Action |
| --- | --- |
| Space | Pause / resume |
| 1 / 2 / 3 / 4 | Speed ×1 / ×2 / ×4 / ×8 |
| H | Toggle Highlights / Full match |
| S | Skip the current highlight (or jump 10s in Full) |
| R | Restart with a new seed |
| T | Change teams (fixture picker) |
| M | Back to the main menu |
| Esc | Confirm before quitting |
| N | Toggle player names |
| C | Toggle Wide / Follow camera |
| Mouse wheel | Zoom |
| Hover player | Tooltip: name, club, position, number, FC 26 attributes |
| Click player | Pin: full-match trail, involvements, live stat line |

## What is simulated

* **22 agents** with pace, acceleration, stamina, dribbling, passing, shooting,
  tackling, physicality and aerial ability mapped from FC 26 ratings.
* **Ball physics** – friction, air drag, gravity, bounce, swerve, height.
* **Full Laws of the Game** – kick-off, throw-ins, goal kicks, corners, free
  kicks, penalties, offside at the moment of the pass, fouls, yellow/red cards
  (second yellow and DOGSO), substitutions, half-time with ends swapped,
  stoppage time, full time.
* **Goalkeepers** – arc positioning, sweeping, dives, catch/parry, distribution.
* **Team shape** – formations, zonal defending, man-marking, pressing, offside
  line, through-balls, crosses, switches, dribble carries.
* **Home advantage** – a tunable 5% edge (set `home_advantage` to 0 for neutral).
* **Match story** – commentary, xG, shots, possession, corners, fouls, cards,
  live player card and full-time summary.

## Playing modes

* **Full** – 90 minutes plus stoppage at 1× (speed controls available).
* **Highlights** – an 18-second rolling snapshot buffer; shots, goals, penalties,
  corners and red cards rewind ~7 seconds, replay live, then fast-simulate again.

## Data

Squad ratings are EA SPORTS FC 26 (OVR / PAC / SHO / PAS / DRI / DEF / PHY) for
all 20 Premier League clubs from OVRBase club pages or estimated 2025-26 squads;
keepers' DIV/HAN/KIC/REF/SPD derive from OVR and role. Line-ups are the strongest
XI in a 4-2-3-1.

## Project layout

```
scripts/data/teams*.gd       squads, formations, styles, club colours
scripts/sim/attributes.gd    FC 26 attribute -> simulation mapping
scripts/sim/match_engine.gd  physics, rules, restarts, events, snapshots
scripts/sim/match_ai.gd      team shape, pressing, marking, on-ball decisions
scripts/view/pitch_view.gd   Old Trafford: stands, crowd, pitch, goals
scripts/view/actor_layer.gd  players, ball, shadows, trails
scripts/ui/hud.gd            broadcast overlay, tooltips, player card
scripts/ui/app_shell.gd      main menu, settings, quit confirm, menu music
scripts/main.gd              playback controller, highlight rewind, camera, audio
tools/sim_test.gd            headless 90-minute match harness
tools/sim_round.gd           full 20-club Premier League round simulator
```

```bash
godot --headless --path . --script tools/sim_test.gd -- 5 1000
godot --headless --path . --script tools/sim_round.gd -- 1 5000
```

## Audio

`audio/` ships procedural crowd ambience, whistle, kick, goal roar and a
near-miss "ooh" (`tools/make_audio.py` regenerates them), plus a ~2:40 looping
techno menu theme (`audio/menu_theme.ogg`, ElevenLabs Music) that plays on the
menu and settings only. Settings saves menu-music volume in
`user://prefs.cfg`; `--clear-cache` wipes it.
