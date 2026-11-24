class_name PitchQueries
extends RefCounted

## Geometry queries over live match state: reach times, the offside line and
## passing lanes. Kept out of MatchAI so the brain stays inside the size budget.

var e = null

func _init(engine) -> void:
	e = engine

func ball_reach_time(p) -> float:
	var bp: Vector2 = e.ball.pos
	var bv: Vector2 = e.ball.vel
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	var t := 0.0
	while t < 3.6:
		if p.pos.distance_to(bp) <= spd * t + 1.35:
			return t
		bp += bv * 0.12
		var dec: float = 0.95 + 0.055 * bv.length()
		bv = bv.move_toward(Vector2.ZERO, dec * 0.12)
		t += 0.12
	return 9.0

func intercept_point(p) -> Vector2:
	var bp: Vector2 = e.ball.pos
	var bv: Vector2 = e.ball.vel
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	var t := 0.0
	var last := bp
	while t < 3.6:
		last = bp
		if p.pos.distance_to(bp) <= spd * t + 1.35:
			return bp
		bp += bv * 0.12
		var dec: float = 0.95 + 0.055 * bv.length()
		bv = bv.move_toward(Vector2.ZERO, dec * 0.12)
		t += 0.12
	return last

func offside_line(t: int) -> float:
	# Attacking-x of the second-last defender of the opposing team.
	var xs: Array = e.offside_xs(t)
	if xs.size() < 2:
		return e.L * 0.85
	return xs[1]

func defensive_line(t: int) -> Vector2:
	# World position of the deepest outfield defender (for line discipline).
	var best = null
	var bx = 1e9
	for p in e.players:
		if p.team != t or p.sent_off or p.is_gk:
			continue
		if not Attrs.is_defender(p.role):
			continue
		var ax = e.attacking_x(t, p.pos)
		if ax < bx:
			bx = ax
			best = p
	if best == null:
		return e.to_world(t, Vector2(0.18, 0.5))
	return best.pos

# -------------------------------------------------------------- goalkeeper --

func lane_risk(from: Vector2, to: Vector2, team: int) -> float:
	var seg = to - from
	var dist = seg.length()
	if dist < 0.01:
		return 0.0
	var dir = seg / dist
	var risk = 0.0
	for q in e.players:
		if q.team == team or q.sent_off:
			continue
		var rel: Vector2 = q.pos - from
		var along: float = rel.dot(dir)
		if along < 0.4 or along > dist:
			continue
		var perp: float = absf(rel.cross(dir))
		if perp < 2.6:
			risk += (1.0 - perp / 2.6) * (1.0 - along / (dist + 1.0) * 0.35)
	return clampf(risk, 0.0, 2.0)

func space_ahead(p) -> float:
	var dir: Vector2 = (e.target_goal_pos(p.team) - p.pos).normalized()
	var best = 18.0
	for q in e.players:
		if q.team == p.team or q.sent_off:
			continue
		var rel: Vector2 = q.pos - p.pos
		var along: float = rel.dot(dir)
		if along <= 0.0 or along > 20.0:
			continue
		var perp: float = absf(rel.cross(dir))
		if perp < 5.0:
			best = minf(best, along)
	return best

func space_behind(team: int, q) -> float:
	var line = offside_line(team)
	return maxf(0.0, line - e.attacking_x(team, q.pos))
