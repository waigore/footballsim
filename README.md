# The Manchester Derby

A broadcast-style, top-down 2D football match simulator built in Godot 4.7.
Manchester United host Manchester City at Old Trafford. Every player is an
individual agent driven by EA SPORTS FC 26 attributes; the ball is simulated in
3D (x, y, height, spin) even though the view is top-down, so lofted passes and
shots carry real depth.

## Run

```bash
godot --path .            # or open project.godot in Godot 4.7 and press F5
```

The match starts in **Highlights** mode: the engine fast-simulates between
moments of danger, rewinds seven seconds, and plays the build-up live.

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
| N | Toggle player names |
| C | Toggle Wide / Follow camera |
| Mouse wheel | Zoom |
| Hover player | Tooltip: name, club, position, shirt number, FC 26 attributes |
| Click player | Pin them: full-match movement trail, every involvement, live stat line |

## What is simulated

* **22 agents** with pace, acceleration, stamina, dribbling, passing, shooting,
  tackling, physicality and aerial ability mapped from FC 26 ratings
  (`scripts/sim/attributes.gd`).
* **Ball physics** – rolling friction, air drag, gravity, bounce, swerve, height.
  Lobbed passes and shots have real flight times; the view lifts the ball off its
  shadow and scales it with height.
* **Full Laws of the Game** – kick-off, throw-ins, goal kicks, corners, direct
  free kicks, penalties, offside at the moment of the pass, fouls, yellow/red
  cards (second yellow and DOGSO), substitutions, half-time with ends swapped,
  stoppage time, full time.
* **Goalkeepers** – positioning on the arc, sweeping, dives, catch/parry model,
  distribution by style.
* **Team shape** – formations, zonal defending, man-marking, pressing triggers,
  offside-line discipline, through-balls, crosses, switches, dribble carries.
* **Match story** – commentary ticker, xG, shots/on target, possession, corners,
  fouls, cards, a live player card and a full-time summary.

## Playing modes

* **Full** – 90 minutes plus stoppage, played at 1× pace (speed controls available).
* **Highlights** – the controller keeps a rolling 18-second snapshot buffer. When
  the engine reports a shot, goal, penalty or red card it rewinds ~7 seconds,
  replays the build-up live, then fast-simulates again. Skip ends the clip.

## Data

Squad ratings and attributes are EA SPORTS FC 26 club ratings (OVR / PAC / SHO /
PAS / DRI / DEF / PHY) for both clubs, from OVRBase's FC 26 club pages
(retrieved November 2026). Goalkeeper DIV/HAN/KIC/REF/SPD are not published in
that table and are assigned from the keeper's OVR and role. Line-ups are the
strongest XI in a 4-2-3-1; benches are real squad members and are used for
substitutions in the second half.

## Project layout

```
scripts/data/teams.gd        squads, formations, styles, club colours
scripts/sim/attributes.gd    FC 26 attribute -> simulation mapping
scripts/sim/match_engine.gd  physics, rules, restarts, events, snapshots
scripts/sim/match_ai.gd      team shape, pressing, marking, on-ball decisions
scripts/view/pitch_view.gd   Old Trafford: stands, crowd, pitch, goals
scripts/view/actor_layer.gd  players, ball, shadows, trails
scripts/ui/hud.gd            broadcast overlay, tooltips, player card
scripts/main.gd              playback controller, highlight rewind, camera, audio
tools/sim_test.gd            headless 90-minute match harness
```

Headless balance check:

```bash
godot --headless --path . --script tools/sim_test.gd -- 5 1000
```

It prints score, shots, xG, possession, passing accuracy, fouls, offsides,
corners, saves and cards per match, plus season averages.

## Audio

`audio/` ships procedurally generated crowd ambience, whistle, kick, goal roar
and a near-miss "ooh" (`tools/make_audio.py` regenerates them).
