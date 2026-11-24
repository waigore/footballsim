class_name PitchQueries
extends RefCounted

## Geometry queries over live match state: reach times, the offside line, the
## defensive line and passing lanes. Kept out of MatchAI so the brain stays
## inside the size budget.

## How far ahead the ball's path is predicted, in seconds, and how coarsely.
const REACH_HORIZON := 3.6
const REACH_STEP := 0.12
## Reach time when the ball cannot be met inside the horizon.
const UNREACHABLE := 9.0

var e = null

func _init(engine) -> void:
	e = engine

## The ball's predicted path over the next `REACH_HORIZON` seconds: its position
## at each `REACH_STEP`, with the time at that sample. A side asking "who gets
## there first" is asking 22 questions about one path, so the walk is built once
## and shared. Same arithmetic and same sample points as the per-player walk it
## replaces, so every answer is unchanged.
func ball_trajectory() -> Dictionary:
	var pts := PackedVector2Array()
	var times := PackedFloat64Array()
	var bp: Vector2 = e.ball.pos
	var bv: Vector2 = e.ball.vel
	var t := 0.0
	while t < REACH_HORIZON:
		pts.append(bp)
		times.append(t)
		bp += bv * REACH_STEP
		var dec: float = 0.95 + 0.055 * bv.length()
		bv = bv.move_toward(Vector2.ZERO, dec * REACH_STEP)
		t += REACH_STEP
	return {"points": pts, "times": times}

## How soon this player meets the ball on a path already built by
## `ball_trajectory`; `UNREACHABLE` when they never do inside the horizon.
func reach_time_on(p, path: Dictionary) -> float:
	var pts: PackedVector2Array = path["points"]
	var times: PackedFloat64Array = path["times"]
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	for i in pts.size():
		if p.pos.distance_to(pts[i]) <= spd * times[i] + 1.35:
			return times[i]
	return UNREACHABLE

## Where on the path this player meets it — the presser's aim point.
func intercept_on(p, path: Dictionary) -> Vector2:
	var pts: PackedVector2Array = path["points"]
	var times: PackedFloat64Array = path["times"]
	var spd: float = Attrs.max_speed(p) * (0.72 + 0.28 * p.stamina)
	var last: Vector2 = e.ball.pos if pts.is_empty() else pts[pts.size() - 1]
	for i in pts.size():
		if p.pos.distance_to(pts[i]) <= spd * times[i] + 1.35:
			return pts[i]
	return last

func ball_reach_time(p) -> float:
	return reach_time_on(p, ball_trajectory())

func intercept_point(p) -> Vector2:
	return intercept_on(p, ball_trajectory())

func offside_line(t: int) -> float:
	# Attacking-x of the second-last defender of the opposing team.
	var xs: Array = e.offside_xs(t)
	if xs.size() < 2:
		return e.L * 0.85
	return xs[1]

## World position of the deepest outfield defender (for line discipline). Read
## once per side and shared by that side's backs in `MatchAI._update_shapes`.
func defensive_line(t: int) -> Vector2:
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
