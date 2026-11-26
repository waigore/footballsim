class_name MatchContact
extends RefCounted

## How hard a side goes into a challenge: the club's own `aggression` bar read
## into the tackle.
##
## Aggression is the one style bar the seed ships per club (0.48–0.62) and the
## club page draws that was read by nothing, so every side committed to the same
## challenges. It leans both halves of a duel, the same way `crossing` leans both
## halves of a cross: an aggressive side wins a little more of the same
## challenge and gives away a little more of it when it misses. A bar that only
## raised the wins would be a free upgrade rather than a style.
##
## Pure reads over the live style, in the units `_attempt_tackle` already works
## in, so the rule is pinned directly and the duel loop keeps no branch per bar.

## The league's neutral value: the shipped clubs' own mean aggression (0.5346
## across the 172-club seed), so the league's aggregate tackle and foul rates are
## unchanged and only the spread *within* the league is what this bar now buys.
## Every shipped club's own bar still leans the duel by its distance from the
## mean.
const NEUTRAL := 0.535

## Spread of the two halves across the bar. Fitted on the staged duel sweep
## (`tools/aggression_sweep.gd`), not to a seed: at these slopes the shipped
## 0.48–0.62 band is worth ~2.5 points of challenge wins and ~18% more fouls on
## the ones it misses — enough to tell the league's own sides apart, and short of
## turning the bar into a second home advantage (the venue's own nudge is ±0.02).
const TACKLE_SPAN := 0.16
const FOUL_SPAN := 1.20

## How far a side's aggression leans a challenge in its favour, added to the
## tackle chance. Zero at the neutral value.
static func tackle_bonus(style: Dictionary) -> float:
	return (bar(style) - NEUTRAL) * TACKLE_SPAN

## The multiplier a side's aggression puts on a lost challenge becoming a foul.
## One at the neutral value.
static func foul_multiplier(style: Dictionary) -> float:
	return 1.0 + (bar(style) - NEUTRAL) * FOUL_SPAN

## The club's aggression bar, clamped: a style that omits it is the neutral
## side, never a side that never challenges.
static func bar(style: Dictionary) -> float:
	return clampf(float(style.get("aggression", NEUTRAL)), 0.0, 1.0)
