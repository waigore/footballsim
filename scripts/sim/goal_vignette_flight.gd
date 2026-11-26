class_name GoalVignetteFlight
extends RefCounted

## The ball's own physics for an AUTO clip (#162): the engine's own gravity, drag,
## bounce and swerve, the pass and the strike that aim it, and the net that judges
## whether the flight crossed the line. State stays on the sim — these are the
## ball's verbs, so the build-up, the strike and the sampling all read one ball.

const L := GoalVignette.L
const CENTRE := GoalVignette.CENTRE
const POST := GoalVignette.POST
const BAR := GoalVignette.BAR
const DT := GoalVignette.DT
const SUB := GoalVignette.SUB
const GRAVITY := GoalVignette.GRAVITY
## How far a flight from the strike point is searched before giving up on the line.
const SEARCH := SUB * 240

## Carry the ball at the owner's feet: a little ahead of his run, bobbling.
static func carry(sim: GoalVignette.Sim, dt: float) -> void:
	var b: GoalVignetteCast.Body = sim.bodies[sim.owner]
	var lead := 0.55 + 0.18 * sin(sim.t * 9.0 + float(sim.owner))
	var ahead := b.vel.normalized() * lead + b.vel * 0.045
	var target := Vector3(b.pos.x + ahead.x, b.pos.y + ahead.y, 0.11)
	sim.ball = sim.ball.lerp(target, clampf(dt * 16.0, 0.0, 1.0))
	sim.bvel = Vector3(b.vel.x, b.vel.y, 0.0)

## One tick of a free ball: sub-stepped physics, then the line is judged.
static func step(sim: GoalVignette.Sim, dt: float) -> void:
	var step_dt := dt / float(SUB)
	var start := sim.ball
	for i in range(SUB):
		integrate(sim, step_dt)
	judge_net(sim, start)

## Gravity, swerve, drag and the bounce — the engine's own constants.
static func integrate(sim: GoalVignette.Sim, dt: float) -> void:
	if sim.ball.z > 0.0 or sim.bvel.z > 0.0:
		sim.bvel.z -= GRAVITY * dt
		if absf(sim.spin) > 0.01:
			var perp := Vector2(-sim.bvel.y, sim.bvel.x).normalized()
			sim.bvel.x += perp.x * sim.spin * 0.35 * dt
			sim.bvel.y += perp.y * sim.spin * 0.35 * dt
		sim.bvel.x *= 1.0 - 0.055 * dt
		sim.bvel.y *= 1.0 - 0.055 * dt
		sim.ball += sim.bvel * dt
		if sim.ball.z <= 0.0:
			sim.ball.z = 0.0
			if sim.bvel.z < -0.6:
				sim.bvel.z = -sim.bvel.z * 0.48
				sim.bvel.x *= 0.88
				sim.bvel.y *= 0.88
			else:
				sim.bvel.z = 0.0
		return
	sim.bvel.z = 0.0
	var sp := Vector2(sim.bvel.x, sim.bvel.y).length()
	if sp > 0.01:
		var ns := maxf(0.0, sp - (0.95 + 0.055 * sp) * dt)
		sim.bvel.x = sim.bvel.x / sp * ns
		sim.bvel.y = sim.bvel.y / sp * ns
	else:
		sim.bvel.x = 0.0
		sim.bvel.y = 0.0
	sim.spin *= 1.0 - 2.2 * dt
	sim.ball += sim.bvel * dt

## The goalmouth is judged where the flight actually crossed the line, not at
## whatever pose the tick happened to land on; a miss rebounds off the frame.
static func judge_net(sim: GoalVignette.Sim, start: Vector3) -> void:
	if not sim.scored and start.x < L and sim.ball.x >= L:
		var k := (L - start.x) / maxf(sim.ball.x - start.x, 0.0001)
		var y := lerpf(start.y, sim.ball.y, k)
		sim.scored = absf(y - CENTRE) < POST and lerpf(start.z, sim.ball.z, k) < BAR
		if sim.scored:
			sim.goal_at = sim.t
	if sim.scored:
		sim.ball.x = minf(sim.ball.x, L - 0.2)
		sim.ball.y = clampf(sim.ball.y, CENTRE - POST + 0.2, CENTRE + POST - 0.2)
		sim.bvel *= 0.55
	elif sim.ball.x >= L:
		sim.ball.x = L
		sim.bvel.x = -absf(sim.bvel.x) * 0.3

## The through-ball: released flat to where the runner will be, with a seeded bend.
static func through_ball(sim: GoalVignette.Sim) -> void:
	sim.owner = -1
	var runner: GoalVignetteCast.Body = sim.bodies[sim.shooter] as GoalVignetteCast.Body
	var flat := runner.pos + runner.vel * 0.55 - Vector2(sim.ball.x, sim.ball.y)
	var flight := clampf(flat.length() / 10.0, 0.35, 1.0)
	sim.bvel = Vector3(flat.x / flight, flat.y / flight,
		(0.11 - sim.ball.z) / flight + 0.5 * GRAVITY * flight)
	sim.spin = sim.rng.randf_range(-0.35, 0.35)

## The finish: aim away from the keeper, then fly the solved velocity. The keeper
## only starts his dive once the ball is struck, after his own reaction delay.
static func strike(sim: GoalVignette.Sim) -> void:
	sim.shot = true
	sim.owner = -1
	var keeper_y := float(sim.bodies[sim.keeper].pos.y)
	var side := 1.0 if keeper_y < CENTRE - 0.3 else -1.0
	if absf(keeper_y - CENTRE) <= 0.3:
		side = -1.0 if sim.rng.randf() < 0.5 else 1.0
	var aim := Vector3(L, clampf(CENTRE + side * (2.3 + sim.rng.randf() * 1.1),
		CENTRE - POST + 0.35, CENTRE + POST - 0.35), 0.5 + sim.rng.randf() * 1.5)
	sim.spin = sim.rng.randf_range(-1.6, 1.6)
	sim.dive_y = aim.y
	sim.react_at = sim.t + sim.bodies[sim.keeper].delay
	sim.bvel = solve_shot(sim, sim.ball, aim, 19.0 + sim.rng.randf() * 6.0)

## Solve the strike: fly the velocity, then bend the aim by what it missed by.
static func solve_shot(sim: GoalVignette.Sim, from: Vector3, aim: Vector3,
		speed: float) -> Vector3:
	var flat := Vector2(aim.x - from.x, aim.y - from.y)
	var flight := maxf(flat.length(), 1.0) / speed
	var v := Vector3(flat.x / flight, flat.y / flight,
		(aim.z - from.z) / flight + 0.5 * GRAVITY * flight)
	for attempt in range(5):
		var hit := fly(sim, from, v)
		var y: float = float(hit.get("y", aim.y))
		var z: float = float(hit.get("z", aim.z))
		if Vector2(y - aim.y, z - aim.z).length() < 0.05:
			return v
		v.y -= (y - aim.y) / flight
		v.z -= (z - aim.z) / flight
	return v

## One flight through the ball's own integrator, stopped at the goal line.
static func fly(sim: GoalVignette.Sim, from: Vector3, v0: Vector3) -> Dictionary:
	var p := from
	var v := v0
	var step_dt := DT / float(SUB)
	for i in range(SEARCH):
		v.z -= GRAVITY * step_dt
		if absf(sim.spin) > 0.01:
			var perp := Vector2(-v.y, v.x).normalized()
			v.x += perp.x * sim.spin * 0.35 * step_dt
			v.y += perp.y * sim.spin * 0.35 * step_dt
		v.x *= 1.0 - 0.055 * step_dt
		v.y *= 1.0 - 0.055 * step_dt
		p += v * step_dt
		if p.x >= L:
			return {"hit": true, "y": p.y, "z": p.z}
	return {"hit": false, "y": p.y, "z": p.z}
