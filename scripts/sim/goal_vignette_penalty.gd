class_name GoalVignettePenalty
extends RefCounted

## A tagged penalty's picture (#171): the taker alone over the ball at the spot,
## the keeper on his line, everyone else held outside the area and behind the
## ball. The sim's ordinary pass is pushed out of reach, so the taker's strike
## at `strike_at` is its next decision; the net still decides whether the ball
## crosses the line, and the clip keeps the report's scorer, minute and score.

const L := 105.0
const W := 68.0
const CENTRE := W * 0.5
## Metres from the goal line to the spot.
const SPOT := 11.0

## Lay the sim out as a spot kick. `sim` is `GoalVignette.Sim`: its bodies,
## carrier, ball and decision clocks are written here rather than branching in
## the build-up code every clip pays for.
static func lay_out(sim, shooter: int, keeper: int, rng: RandomNumberGenerator) -> void:
	sim.carrier = shooter
	sim.pass_at = 1e9
	sim.strike_at = 1.3 + rng.randf() * 0.3
	var spot := Vector2(L - SPOT, CENTRE + rng.randf_range(-0.4, 0.4))
	sim.meet = spot
	sim.carry_to = spot
	sim.strike_from = spot
	var taker = sim.bodies[shooter]
	taker.pos = spot
	taker.base = spot
	sim.ball = Vector3(spot.x, spot.y, 0.11)
	sim.owner = shooter
	# Both sides wait outside the box, spread along the edge so the picture
	# still reads as a match, and the keeper stands on his line.
	for i in range(sim.bodies.size()):
		if i == shooter or i == keeper:
			continue
		var b = sim.bodies[i]
		var lane := 68.0 + rng.randf() * 12.0
		var across := float(i) / float(maxi(sim.bodies.size() - 1, 1)) - 0.5
		b.pos = Vector2(lane, CENTRE + across * 44.0)
		b.base = b.pos
	var gk = sim.bodies[keeper]
	gk.pos = Vector2(L - 1.2, CENTRE)
	gk.base = gk.pos
