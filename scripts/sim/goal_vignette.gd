class_name GoalVignette
extends RefCounted

## AUTO report clips: a bounded physics simulation of one chance.
##
## Bodies steer with an acceleration and a top speed; the ball is dribbled,
## passed and struck with the engine's own gravity, drag, bounce and swerve; the
## keeper dives on a seeded reaction delay. Only the decisions come from the
## seed — the run, the pass, the aim, the corner — so no two goals share a shape,
## and the chance always finishes with the report's own scorer and assist: the
## strike is aimed at the goal mouth and solved against the very flight it is
## then flown through, and a planned strike is never intercepted (the engine's
## `planned_goal` rule). World space is the attacking frame; an away goal is
## mirrored once at sampling, like the engine's own direction switch.

const L := 105.0
const W := 68.0
const CENTRE := W * 0.5
const POST := 3.66
const BAR := 2.44
const LENGTH := 10.0
## Two sim ticks per stored pose, so a pack is exactly twelve poses a second.
const DT := 1.0 / 24.0
## Sub-steps of the free ball inside one tick; the shot solver uses the same.
const SUB := 16
const GRAVITY := 9.81
const NEAR := 1.7

## One body: steering mirrors the engine's — a desired velocity, capped by pace.
class Body:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var target := Vector2.ZERO
	var base := Vector2.ZERO
	var attack := true
	var keeper := false
	var speed := 7.2
	var acc := 6.0
	var delay := 0.0

	func steer(dt: float) -> void:
		var to := target - pos
		var d := to.length()
		var cap := speed
		if d < NEAR:
			cap = minf(speed, d * 2.4)
		var want := Vector2.ZERO
		if d > 0.05:
			want = to / d * cap
		var dv := want - vel
		var max_dv := acc * dt
		if dv.length() > max_dv:
			dv = dv.normalized() * max_dv
		vel += dv
		pos += vel * dt
		pos.x = clampf(pos.x, -2.0, L + 2.0)
		pos.y = clampf(pos.y, 1.0, W - 1.0)

class Sim:
	var rng := RandomNumberGenerator.new()
	var bodies: Array = []
	var carrier := 0
	var shooter := 0
	var keeper := 0
	var mirror := false
	var ball := Vector3.ZERO
	var bvel := Vector3.ZERO
	var spin := 0.0
	var owner := 0
	var pass_at := 2.3
	var strike_at := 5.0
	var carry_to := Vector2.ZERO
	var meet := Vector2.ZERO
	var strike_from := Vector2.ZERO
	var goal_at := 6.0
	var dive_y := 0.0
	var react_at := 99.0
	var shot := false
	var scored := false
	var score_before: Array = [0, 0]
	var score_after: Array = [0, 0]
	var minute := 1
	var t := 0.0
	var frames: Array = []

	func _init(sides: Dictionary, goal: Dictionary, count: int, seed: int,
			scoring_home: bool) -> void:
		rng.seed = seed
		mirror = not scoring_home
		minute = int(goal.get("minute", 1))
		var score: Array = goal.get("score_after", [0, 0])
		score_before = [int(score[0]), int(score[1])]
		score_after = score_before.duplicate()
		var side := 0 if scoring_home else 1
		score_before[side] = maxi(int(score_before[side]) - 1, 0)
		bodies.resize(count)
		var attack_xi: Array = sides.get("home" if scoring_home else "away", [])
		var defend_xi: Array = sides.get("away" if scoring_home else "home", [])
		var attack_at := 0 if scoring_home else attack_xi.size()
		var defend_at := attack_xi.size() if scoring_home else 0
		# The chance is building: one side pushes up, the other drops toward goal.
		for i in range(attack_xi.size()):
			var b := Body.new()
			b.base = GoalVignette.formation(str(attack_xi[i].get("role", "")), i,
				attack_xi.size())
			b.pos = b.base + Vector2(6.0 + rng.randf() * 3.0, rng.randf_range(-2.0, 2.0))
			b.speed = 6.9 + rng.randf() * 1.1
			b.acc = 5.4 + rng.randf() * 1.2
			bodies[attack_at + i] = b
		for i in range(defend_xi.size()):
			var d := Body.new()
			d.attack = false
			d.base = GoalVignette.mirror(GoalVignette.formation(
				str(defend_xi[i].get("role", "")), i, defend_xi.size()))
			d.pos = d.base + Vector2(-3.0 - rng.randf() * 2.0, rng.randf_range(-2.0, 2.0))
			d.speed = 7.0 + rng.randf() * 1.0
			d.acc = 5.4 + rng.randf() * 1.2
			d.keeper = str(defend_xi[i].get("role", "")) == "GK"
			d.delay = 0.14 + rng.randf() * 0.18
			if d.keeper:
				d.speed = 3.0 + rng.randf() * 0.5
				d.pos = Vector2(L - 3.0, CENTRE + rng.randf_range(-1.5, 1.5))
				keeper = defend_at + i
			bodies[defend_at + i] = d
		shooter = attack_at + maxi(GoalVignette.find(attack_xi, str(goal.get("player_id", ""))), 0)
		carrier = attack_at + GoalVignette.passer(attack_xi,
			str(goal.get("assist_id", "")), str(goal.get("player_id", "")))
		# Seeded decisions: the run, the pass, the strike, the corner.
		meet = Vector2(78.0 + rng.randf() * 5.0, CENTRE + rng.randf_range(-8.0, 8.0))
		carry_to = Vector2(70.0 + rng.randf() * 4.0, lerpf(CENTRE, meet.y, 0.55))
		strike_from = Vector2(minf(meet.x + 6.0, L - 17.0), meet.y + rng.randf_range(-2.0, 2.0))
		pass_at = 2.3 + rng.randf() * 0.6
		strike_at = 5.0 + rng.randf() * 0.7
		# The carrier opens with the ball at his feet, in his own half of the
		# attacking picture: the report's assist is the man on the ball.
		var c: Body = bodies[carrier]
		c.pos = Vector2(62.0 + rng.randf() * 5.0, CENTRE + rng.randf_range(-7.0, 7.0))
		c.base = c.pos
		ball = Vector3(c.pos.x, c.pos.y, 0.11)
		owner = carrier

	func run() -> void:
		for i in range(int(round(LENGTH / DT)) + 1):
			if i > 0:
				_tick(DT)
			if i % 2 == 0:
				_sample()

	func _tick(dt: float) -> void:
		t += dt
		_decide()
		for b in bodies:
			(b as Body).steer(dt)
		if not shot:
			if owner == carrier and t >= pass_at:
				_pass()
			var reach := t >= pass_at and ball.z < 1.7 and \
				Vector2(ball.x, ball.y).distance_to(bodies[shooter].pos) < NEAR
			if not shot and owner < 0 and reach:
				owner = shooter
			# The strike is a decision with a deadline, never a hope: a finisher
			# takes the chance he has and never lets the ball run into the net.
			if not shot and (ball.x > L - 8.0 or t >= strike_at + 0.5 or \
					(owner == shooter and t >= strike_at)):
				_strike()
		_ball_step(dt)

	func _decide() -> void:
		var pushing := t >= pass_at
		var spot := Vector2(ball.x, ball.y)
		for i in range(bodies.size()):
			var b: Body = bodies[i]
			if b.keeper:
				var line := ball.y
				if shot:
					line = dive_y if t >= react_at else CENTRE
				b.target = Vector2(L - 3.0, clampf(line, CENTRE - POST, CENTRE + POST))
			elif scored:
				# The finish is in: the scorer veers to the corner, the rest follow.
				if i == shooter:
					b.target = Vector2(88.0, 6.0 if b.pos.y < CENTRE else W - 6.0)
				elif b.attack:
					b.target = bodies[shooter].pos + Vector2(-2.4, 1.4 if i % 2 == 0 else -1.4)
				else:
					b.target = _defend_goal(b, spot, false)
			elif shot:
				b.target = b.pos + b.vel * 0.05
			elif i == carrier:
				b.target = carry_to
			elif i == shooter:
				# He runs for the through-ball, then takes it into the box.
				b.target = strike_from if owner == shooter else Vector2(ball.x, ball.y)
			elif b.attack:
				b.target = Vector2(clampf(b.base.x + (6.0 if not pushing else 14.0), 6.0, L - 20.0),
					clampf(lerpf(b.base.y, spot.y, 0.22), 3.0, W - 3.0))
			else:
				b.target = _defend_goal(b, spot, pushing)

	## The defending shape: drop toward their own goal and screen the ball's lane.
	func _defend_goal(b: Body, spot: Vector2, pushing: bool) -> Vector2:
		return Vector2(minf(b.base.x + (2.0 if not pushing else 6.0), L - 11.0),
			clampf(lerpf(b.base.y, spot.y, 0.3), 3.0, W - 3.0))

	func _ball_step(dt: float) -> void:
		if owner >= 0:
			var b: Body = bodies[owner]
			var lead := 0.55 + 0.18 * sin(t * 9.0 + float(owner))
			var ahead := b.vel.normalized() * lead + b.vel * 0.045
			var target := Vector3(b.pos.x + ahead.x, b.pos.y + ahead.y, 0.11)
			ball = ball.lerp(target, clampf(dt * 16.0, 0.0, 1.0))
			bvel = Vector3(b.vel.x, b.vel.y, 0.0)
			return
		var step := dt / float(SUB)
		var start := ball
		for i in range(SUB):
			_free(step)
		_net(start)

	## Gravity, swerve, drag and the bounce — the engine's own constants.
	func _free(dt: float) -> void:
		if ball.z > 0.0 or bvel.z > 0.0:
			bvel.z -= GRAVITY * dt
			if absf(spin) > 0.01:
				var perp := Vector2(-bvel.y, bvel.x).normalized()
				bvel.x += perp.x * spin * 0.35 * dt
				bvel.y += perp.y * spin * 0.35 * dt
			bvel.x *= 1.0 - 0.055 * dt
			bvel.y *= 1.0 - 0.055 * dt
			ball += bvel * dt
			if ball.z <= 0.0:
				ball.z = 0.0
				if bvel.z < -0.6:
					bvel.z = -bvel.z * 0.48
					bvel.x *= 0.88
					bvel.y *= 0.88
				else:
					bvel.z = 0.0
			return
		bvel.z = 0.0
		var sp := Vector2(bvel.x, bvel.y).length()
		if sp > 0.01:
			var ns := maxf(0.0, sp - (0.95 + 0.055 * sp) * dt)
			bvel.x = bvel.x / sp * ns
			bvel.y = bvel.y / sp * ns
		else:
			bvel.x = 0.0
			bvel.y = 0.0
		spin *= 1.0 - 2.2 * dt
		ball += bvel * dt

	func _net(start: Vector3) -> void:
		if not scored and start.x < L and ball.x >= L:
			# The goalmouth is judged where the flight actually crossed the line.
			var k := (L - start.x) / maxf(ball.x - start.x, 0.0001)
			var y := lerpf(start.y, ball.y, k)
			scored = absf(y - CENTRE) < POST and lerpf(start.z, ball.z, k) < BAR
			if scored:
				goal_at = t
		if scored:
			ball.x = minf(ball.x, L - 0.2)
			ball.y = clampf(ball.y, CENTRE - POST + 0.2, CENTRE + POST - 0.2)
			bvel *= 0.55
		elif ball.x >= L:
			ball.x = L
			bvel.x = -absf(bvel.x) * 0.3

	func _pass() -> void:
		owner = -1
		var runner: Body = bodies[shooter]
		var flat := runner.pos + runner.vel * 0.55 - Vector2(ball.x, ball.y)
		var flight := clampf(flat.length() / 10.0, 0.35, 1.0)
		bvel = Vector3(flat.x / flight, flat.y / flight,
			(0.11 - ball.z) / flight + 0.5 * GRAVITY * flight)
		spin = rng.randf_range(-0.35, 0.35)

	## The finish: aim away from the keeper, then fly the solved velocity.
	func _strike() -> void:
		shot = true
		owner = -1
		var side := 1.0 if float(bodies[keeper].pos.y) < CENTRE - 0.3 else -1.0
		if absf(float(bodies[keeper].pos.y) - CENTRE) <= 0.3:
			side = -1.0 if rng.randf() < 0.5 else 1.0
		var aim := Vector3(L, clampf(CENTRE + side * (2.3 + rng.randf() * 1.1),
			CENTRE - POST + 0.35, CENTRE + POST - 0.35), 0.5 + rng.randf() * 1.5)
		spin = rng.randf_range(-1.6, 1.6)
		dive_y = aim.y
		react_at = t + bodies[keeper].delay
		bvel = _solve_shot(ball, aim, 19.0 + rng.randf() * 6.0)

	## Solve the strike: fly the velocity, then bend the aim by what it missed by.
	func _solve_shot(from: Vector3, aim: Vector3, speed: float) -> Vector3:
		var flat := Vector2(aim.x - from.x, aim.y - from.y)
		var flight := maxf(flat.length(), 1.0) / speed
		var v := Vector3(flat.x / flight, flat.y / flight,
			(aim.z - from.z) / flight + 0.5 * GRAVITY * flight)
		for attempt in range(5):
			var hit := _fly(from, v)
			var y: float = float(hit.get("y", aim.y))
			var z: float = float(hit.get("z", aim.z))
			if Vector2(y - aim.y, z - aim.z).length() < 0.05:
				return v
			v.y -= (y - aim.y) / flight
			v.z -= (z - aim.z) / flight
		return v

	## One flight through the ball's own integrator, stopped at the goal line.
	func _fly(from: Vector3, v0: Vector3) -> Dictionary:
		var p := from
		var v := v0
		var step := DT / float(SUB)
		for i in range(SUB * 240):
			v.z -= GRAVITY * step
			if absf(spin) > 0.01:
				var perp := Vector2(-v.y, v.x).normalized()
				v.x += perp.x * spin * 0.35 * step
				v.y += perp.y * spin * 0.35 * step
			v.x *= 1.0 - 0.055 * step
			v.y *= 1.0 - 0.055 * step
			p += v * step
			if p.x >= L:
				return {"hit": true, "y": p.y, "z": p.z}
		return {"hit": false, "y": p.y, "z": p.z}

	func _sample() -> void:
		var flat := PackedFloat32Array()
		flat.resize(bodies.size() * 2)
		for i in range(bodies.size()):
			var p: Vector2 = bodies[i].pos
			flat[i * 2] = snappedf(p.x if not mirror else L - p.x, 0.01)
			flat[i * 2 + 1] = snappedf(p.y, 0.01)
		var shown: Array = score_after if scored else score_before
		var bx := L - ball.x if mirror else ball.x
		frames.append({
			"t": snappedf(t, 0.01),
			# The clip's clock meets the report's minute exactly at the finish.
			"c": snappedf(float(minute) * 60.0 - goal_at + t, 0.01),
			"s": [int(shown[0]), int(shown[1])],
			"g": 1 if scored else 0,
			"b": [snappedf(bx, 0.01), snappedf(ball.y, 0.01), snappedf(ball.z, 0.01)],
			"p": flat,
		})

## The pack's poses for one goal: home XI first, then the away XI, in key order.
static func build(goal: Dictionary, sides: Dictionary, seed: int) -> Dictionary:
	var home := str(goal.get("home", ""))
	var keys: Array = []
	for p in sides.get("home", []):
		keys.append(str(p.get("id", "")))
	for p in sides.get("away", []):
		keys.append(str(p.get("id", "")))
	var sim := Sim.new(sides, goal, keys.size(), seed, str(goal.get("club_id", home)) == home)
	sim.run()
	return {"keys": keys, "frames": sim.frames}

## Formation slot in the attacking frame: keepers deep, the front line in the box.
static func formation(role: String, index: int, total: int) -> Vector2:
	var line := 3
	if role == "GK":
		line = 0
	elif role in ["RB", "LB", "RCB", "LCB", "CB"]:
		line = 1
	elif role in ["RDM", "LDM", "CDM", "CM", "LM", "RM"]:
		line = 2
	var xs: PackedFloat32Array = [4.0, 20.0, 36.0, 54.0]
	var spread: PackedFloat32Array = [6.0, 42.0, 44.0, 26.0]
	var per := maxi(total - 1, 1)
	var y := CENTRE + (float(index) / float(per) - 0.5) * float(spread[line])
	return Vector2(float(xs[line]), clampf(y, 3.0, W - 3.0))

## The mirror across the halfway line: the defending shape in the attacking frame.
static func mirror(p: Vector2) -> Vector2:
	return Vector2(L - p.x, p.y)

## The XI slot holding a player id; -1 when he is not in it.
static func find(xi: Array, player_id: String) -> int:
	if player_id == "":
		return -1
	for i in range(xi.size()):
		if str(xi[i].get("id", "")) == player_id:
			return i
	return -1

## The final ball's man: the recorded assist, else the most advanced teammate.
static func passer(xi: Array, assist_id: String, scorer_id: String) -> int:
	var found := find(xi, assist_id)
	if found >= 0:
		return found
	var best := -1
	var best_x := -1.0
	for i in range(xi.size()):
		if str(xi[i].get("id", "")) == scorer_id:
			continue
		var role := str(xi[i].get("role", ""))
		if role == "GK":
			continue
		var x := formation(role, i, xi.size()).x
		if x > best_x:
			best_x = x
			best = i
	return maxi(best, 0)
