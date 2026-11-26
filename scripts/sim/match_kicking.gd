class_name MatchKicking
extends RefCounted

## The keeper's own boot: the club's KICKING bar (one of the five keeper bars the
## player page draws) read into the long ball he strikes — how far up the pitch
## it travels, and how truly it lands.
##
## KICKING is the one keeper rating with no rule: `Attrs` already maps DIVING
## (dive reach), HANDLING (catch chance), REFLEXES (reaction and reach) and
## SPEED (movement cap), and the seed ships a per-keeper KICKING value beside
## them, but nothing under `scripts/sim/` read it — so every keeper put a 60 m
## punt exactly where he aimed it, from the weakest boot in the league to the
## strongest.
##
## Unlike the club's style bars (wiki Live tactics), this is an *ability*, not a
## style: it is read monotonically like every other attribute in `Attrs` — a
## better boot cannot be a trade, because the bar it improves is the same ball.
## The neutral is the shipped keepers' own mean, so the league's mean keeper
## strikes exactly the ball the engine always struck (wiki Match AI: a seed
## reproduces its football), and the clubs' own spread does the leaning.
##
## Pure reads over the keeper's five bars, in the units `clear_ball` already
## works in, so the rule is pinned directly and the restart lane keeps no branch
## per rating.

## The shipped starting keepers' mean KICKING (64.75 across the 172 clubs). At
## the mean the punt carries exactly the distance the engine always asked for,
## so the league's mean keeper is bit-identical; `SCATTER_PER_POINT` is zero here
## too, which is what keeps a default match's RNG stream untouched.
const NEUTRAL := 64.75

## Metres of travel per point of the bar. Fitted to the shipped band, not to a
## seed: at this slope the 49–79 starters' spread is worth ~13.5 m across a ~59 m
## goal kick — the weakest boot drops it 7 m short of the engine's own target and
## the strongest puts it 6 m beyond it (`tools/kicking_sweep.gd` measures it).
const REACH_PER_POINT := 0.45

## Metres of landing error per point the bar sits *under* the mean. A boot at or
## above the league's mean lands the ball on its line — that is the strike the
## shipped engine already gave every keeper — and a weaker one sprays it, so a
## weak kicker loses both halves of the same ball rather than only one.
## Fitted on the same sweep: the weakest starting keeper (49) lands an average
## ~1.2 m — up to 2.5 m — off a 59 m ball, and the cap keeps a rating far below
## the seed from turning a goal kick into a shank.
const SCATTER_PER_POINT := 0.16
const SCATTER_CAP := 8.0

## The keeper's own KICKING as a 0–100 rating. A keeper shipped without the bars
## (a bare fixture, a squad written before the field existed) reads the league's
## neutral boot, never a keeper who cannot kick.
static func kick_of(bars: Dictionary) -> float:
	return clampf(float(bars.get("kic", NEUTRAL)), 0.0, 100.0)

## The point a keeper's long ball is actually aimed at: the target the engine
## asks for, pushed out by a strong boot and pulled in by a weak one, along the
## same line. Pure, so the reach half is read in one place.
static func aim_point(bars: Dictionary, from: Vector2, aim: Vector2) -> Vector2:
	var d: float = from.distance_to(aim)
	if d < 0.5:
		return aim
	var travel: float = maxf(9.0, d + (kick_of(bars) - NEUTRAL) * REACH_PER_POINT)
	return from + (aim - from) / d * travel

## How far off that line the ball lands, in metres. Zero for a boot at or above
## the league's mean — the shipped engine already struck those balls true.
static func scatter(bars: Dictionary) -> float:
	return clampf((NEUTRAL - kick_of(bars)) * SCATTER_PER_POINT, 0.0, SCATTER_CAP)

## Where the ball finally lands: the reach-adjusted aim, offset by the boot's
## scatter. `side` and `depth` are the caller's own random draws in −1…1, so the
## module stays pure and a seed still reproduces its matches. The engine must not
## draw them when `scatter` is zero, or a true boot would move the RNG stream.
static func landing(bars: Dictionary, from: Vector2, aim: Vector2, side: float, depth: float) -> Vector2:
	return aim_point(bars, from, aim) + Vector2(side, depth) * scatter(bars)
