class_name GoalVignetteCast
extends RefCounted

## Who is in an AUTO clip and where they start: one seeded Body per player, the
## sides in the attacking frame, and the report's own men on the ball and at the
## strike. Formation slots are laid out here too, since the AI reads them as the
## home a body returns to.

const L := GoalVignette.L
const W := GoalVignette.W
const CENTRE := GoalVignette.CENTRE

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
		if d < GoalVignette.NEAR:
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

## Fill `sim.bodies` and the sim's own slots: shooter, carrier, keeper, the ball
## at the carrier's feet and the seeded run, pass and strike clocks.
static func dress(sim: GoalVignette.Sim, sides: Dictionary, goal: Dictionary,
		scoring_home: bool) -> void:
	var attack_xi: Array = sides.get("home" if scoring_home else "away", [])
	var defend_xi: Array = sides.get("away" if scoring_home else "home", [])
	var attack_at := 0 if scoring_home else attack_xi.size()
	var defend_at := attack_xi.size() if scoring_home else 0
	var rng := sim.rng
	sim.bodies.resize(attack_xi.size() + defend_xi.size())
	# The chance is building: one side pushes up, the other drops toward goal.
	for i in range(attack_xi.size()):
		var b := Body.new()
		b.base = formation(str(attack_xi[i].get("role", "")), i, attack_xi.size())
		b.pos = b.base + Vector2(6.0 + rng.randf() * 3.0, rng.randf_range(-2.0, 2.0))
		b.speed = 6.9 + rng.randf() * 1.1
		b.acc = 5.4 + rng.randf() * 1.2
		sim.bodies[attack_at + i] = b
	for i in range(defend_xi.size()):
		var d := Body.new()
		d.attack = false
		d.base = GoalVignette.mirror(formation(str(defend_xi[i].get("role", "")), i,
			defend_xi.size()))
		d.pos = d.base + Vector2(-3.0 - rng.randf() * 2.0, rng.randf_range(-2.0, 2.0))
		d.speed = 7.0 + rng.randf() * 1.0
		d.acc = 5.4 + rng.randf() * 1.2
		d.keeper = str(defend_xi[i].get("role", "")) == "GK"
		d.delay = 0.14 + rng.randf() * 0.18
		if d.keeper:
			d.speed = 3.0 + rng.randf() * 0.5
			d.pos = Vector2(L - 3.0, CENTRE + rng.randf_range(-1.5, 1.5))
			sim.keeper = defend_at + i
		sim.bodies[defend_at + i] = d
	var scorer := str(goal.get("player_id", ""))
	sim.shooter = attack_at + maxi(find(attack_xi, scorer), 0)
	sim.carrier = attack_at + passer(attack_xi, str(goal.get("assist_id", "")), scorer)
	# Seeded decisions: the run, the pass, the strike, the corner.
	sim.meet = Vector2(78.0 + rng.randf() * 5.0, CENTRE + rng.randf_range(-8.0, 8.0))
	sim.carry_to = Vector2(70.0 + rng.randf() * 4.0, lerpf(CENTRE, sim.meet.y, 0.55))
	sim.strike_from = Vector2(minf(sim.meet.x + 6.0, L - 17.0),
		sim.meet.y + rng.randf_range(-2.0, 2.0))
	sim.pass_at = 2.3 + rng.randf() * 0.6
	sim.strike_at = 5.0 + rng.randf() * 0.7
	# The carrier opens with the ball at his feet, in his own half of the
	# attacking picture: the report's assist is the man on the ball.
	var c: Body = sim.bodies[sim.carrier]
	c.pos = Vector2(62.0 + rng.randf() * 5.0, CENTRE + rng.randf_range(-7.0, 7.0))
	c.base = c.pos
	sim.ball = Vector3(c.pos.x, c.pos.y, 0.11)
	sim.owner = sim.carrier

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
