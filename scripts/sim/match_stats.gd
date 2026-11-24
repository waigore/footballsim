class_name MatchStats
extends RefCounted

## The readings a match summary carries beside the score: the frame a shot
## struck, the pass a defender cut out, the momentum a side is carrying. Pure
## functions over plain values, so the geometry and the memory are testable
## without playing a match.
##
## Established by DR-20261125-01 (wiki match / open-play).

## Contact band around a post or the bar, in metres: the goal frame's tube
## (~6 cm) plus the ball (~11 cm), so a ball whose centre crosses the goal
## plane within this distance of the frame strikes it instead of passing it.
const FRAME_R := 0.17

## How long a pass stays an interception opportunity: a ball won from an
## opponent who kicked it is a read of their pass; one that has been loose for
## longer is a scramble, and a scramble is not an interception.
const INTERCEPTION_WINDOW := 3.0

## A pass still travelling this fast has not been collected and lost again: the
## claim is a read of the pass in flight. The engine calls a ball below this
## "loose and slow" for possession, so the two readings agree.
const INTERCEPTION_SPEED := 6.0

## Momentum is an exponential memory of pressure: half the weight of an event
## is gone after this many seconds of play, so a side that stops threatening
## decays back toward nothing.
const MOMENTUM_HALF_LIFE := 90.0

## Pressure at which a side reads as fully on top (0.63 of the way up the bar).
## Measured on full matches: raw pressure runs 0.05–0.20 in a normal spell with
## spikes when a side piles chances up, so this keeps a bar off its stops and
## still lets a big spell read as a big spell (DR-20261125-01).
const MOMENTUM_SCALE := 0.12

## Share of the chances the finishing roll priced out that are struck at the
## frame instead of at the keeper: a shot that beats the keeper and hits the
## post. Real football puts roughly one shot a match into the woodwork; the
## engine's priced-out on-target chances are the pool it can come from.
const WOODWORK_P := 0.18

## What an event is worth to the side that produced it. A goal is the biggest
## swing; a shot (the bigger the chance, the more it is worth — see `bump`) is
## the steady beat. Kinds not listed move nothing.
const MOMENTUM_WEIGHT := {
	"goal": 0.60,
	"save": 0.16,
	"block": 0.10,
	"shot": 0.12,
	"header": 0.12,
	"cross": 0.03,
	"corner": 0.05,
}

## Events that credit the side that did *not* produce them: a save or a block is
## the defending side reacting to pressure, so it is pressure for the attacker.
const MOMENTUM_INVERTED := ["save", "block"]

## Where a travelling ball crosses the goal plane, as (y, z). A tick can carry
## the ball past the plane by up to a third of a metre, so the reading undoes
## that overshoot instead of judging the point after it.
static func goal_plane_point(pos: Vector2, vel: Vector2, z: float, vz: float,
		line_x: float) -> Vector2:
	var vx: float = absf(vel.x)
	if vx < 0.001:
		return Vector2(pos.y, z)
	var back: float = clampf(absf(pos.x - line_x) / vx, 0.0, 0.05)
	return Vector2(pos.y - vel.y * back, z - vz * back)

## Which part of the frame the crossing point struck, if any: "post", "bar" or
## "". Balls inside the goal mouth are goals and never reach this reading.
static func frame_hit(goal_y: float, goal_w: float, goal_h: float, y: float,
		z: float) -> String:
	var dy: float = absf(y - goal_y)
	if absf(dy - goal_w * 0.5) <= FRAME_R and z <= goal_h + FRAME_R:
		return "post"
	if absf(z - goal_h) <= FRAME_R and dy <= goal_w * 0.5 + FRAME_R:
		return "bar"
	return ""

## Decay a side's momentum carries across one step of play.
static func decay(dt: float) -> float:
	return pow(0.5, maxf(dt, 0.0) / MOMENTUM_HALF_LIFE)

## Add what an event is worth to the pressure array (per side, in place). A
## shot is worth more the better the chance was: a big chance is a big swing.
static func bump(pressure: Array, team: int, kind: String, xg: float = 0.0) -> void:
	if team < 0 or team > 1 or pressure.size() < 2:
		return
	var w: float = float(MOMENTUM_WEIGHT.get(kind, 0.0))
	if w <= 0.0:
		return
	if kind in MOMENTUM_INVERTED:
		team = 1 - team
	if kind in ["shot", "header"]:
		w *= 0.5 + clampf(xg, 0.0, 0.8)
	pressure[team] = float(pressure[team]) + w

## Each side's momentum, 0..1, saturating as its pressure builds. Read
## independently — a side can be flat (0) while the other is on top, and both
## read low in a quiet spell, which is what a broadcast momentum meter shows.
static func momentum_level(pressure: Array) -> Vector2:
	if pressure.size() < 2:
		return Vector2.ZERO
	var home: float = 1.0 - exp(-maxf(float(pressure[0]), 0.0) / MOMENTUM_SCALE)
	var away: float = 1.0 - exp(-maxf(float(pressure[1]), 0.0) / MOMENTUM_SCALE)
	return Vector2(snappedf(home, 0.01), snappedf(away, 0.01))
