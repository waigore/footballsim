# THE MANCHESTER DERBY — Match Simulator

A broadcast-style, top-down 2D football match simulator built in Godot 4.

## Design brief (locked)

- **Genre**: sports simulation / match viewer (not playable football — you watch, you don't control).
- **Core verb**: *watch* — hover, click, rewind, fast-forward, skip.
- **Win/lose**: none for the viewer; the teams play a real 90 minutes and the scoreboard decides.
- **Session length**: Full match (~90 min at 1x, ~4 min at 24x sim) or Highlights mode (~5-8 min).
- **Mood**: Sky Sports / Monday Night Football broadcast. Calm, premium, data-rich.
- **Art direction**: top-down pitch seen from the main stand; deep Old Trafford green, chalk-white
  markings, red and sky-blue discs, soft shadow depth cues for ball height.
- **Simulation**: 22 individual agents with EA FC 26 attribute-driven technique, a 3D ball
  (x, y, z + spin), full Laws of the Game (offsides included), referee, cards, set pieces.
- **Camera**: full-pitch wide by default, click-to-zoom dynamic follow as an option.

## Controls

| Key | Action |
| --- | --- |
| Space | Pause / resume |
| 1 2 3 4 | Speed x1 / x2 / x4 / x8 (x24 in Highlights fast-sim) |
| H | Toggle Full Match / Highlights |
| S | Skip current highlight (Highlights) or jump to next event (Full) |
| R | Restart match |
| N | Toggle player names |
| C | Toggle camera Wide / Follow |
| Mouse wheel | Zoom |
| Hover player | Tooltip: name, team, position, shirt, attributes |
| Click player | Pin player: full-match movement trail + every involvement |

## Data provenance

Squad ratings are EA SPORTS FC 26 club ratings (OVR / PAC / SHO / PAS / DRI / DEF / PHY) for
Manchester United and Manchester City, retrieved from OVRBase's FC 26 club pages (Nov 2026).
Goalkeeper sub-ratings (DIV/HAN/KIC/REF/SPD) are not published in that table and are assigned
from the keeper's OVR and role. Lineups are the strongest available XI in a 4-2-3-1; benches are
real squad members. Attribute→simulation mappings live in `scripts/sim/attributes.gd`.
