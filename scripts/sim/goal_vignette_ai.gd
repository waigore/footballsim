class_name GoalVignetteAI
extends RefCounted

## Where every body is heading on each tick of an AUTO clip: the carrier drives,
## the striker runs the through-ball then takes it into the box, the rest push up
## behind the chance, the defenders drop and screen the lane, the keeper holds his
## line until the strike and then dives, and after the finish the scorer veers to
## the corner. Steering itself lives on the body (`GoalVignetteCast.Body`).

const W := GoalVignette.W
const L := GoalVignette.L
const CENTRE := GoalVignette.CENTRE
const POST := GoalVignette.POST

## Point every body at his next spot for this tick.
static func decide(sim: GoalVignette.Sim) -> void:
	var pushing := sim.t >= sim.pass_at
	var spot := Vector2(sim.ball.x, sim.ball.y)
	for i in range(sim.bodies.size()):
		var b: GoalVignetteCast.Body = sim.bodies[i]
		if b.keeper:
			var line := sim.ball.y
			if sim.shot:
				line = sim.dive_y if sim.t >= sim.react_at else CENTRE
			b.target = Vector2(L - 3.0, clampf(line, CENTRE - POST, CENTRE + POST))
		elif sim.scored:
			# The finish is in: the scorer veers to the corner, the rest follow.
			if i == sim.shooter:
				b.target = Vector2(88.0, 6.0 if b.pos.y < CENTRE else W - 6.0)
			elif b.attack:
				b.target = sim.bodies[sim.shooter].pos + Vector2(-2.4,
					1.4 if i % 2 == 0 else -1.4)
			else:
				b.target = defend_goal(b, spot, false)
		elif sim.shot:
			b.target = b.pos + b.vel * 0.05
		elif i == sim.carrier:
			b.target = sim.carry_to
		elif i == sim.shooter:
			# He runs for the through-ball, then takes it into the box.
			b.target = sim.strike_from if sim.owner == sim.shooter \
				else Vector2(sim.ball.x, sim.ball.y)
		elif b.attack:
			b.target = Vector2(clampf(b.base.x + (6.0 if not pushing else 14.0), 6.0, L - 20.0),
				clampf(lerpf(b.base.y, spot.y, 0.22), 3.0, W - 3.0))
		else:
			b.target = defend_goal(b, spot, pushing)

## The defending shape: drop toward their own goal and screen the ball's lane.
static func defend_goal(b: GoalVignetteCast.Body, spot: Vector2, pushing: bool) -> Vector2:
	return Vector2(minf(b.base.x + (2.0 if not pushing else 6.0), L - 11.0),
		clampf(lerpf(b.base.y, spot.y, 0.3), 3.0, W - 3.0))
