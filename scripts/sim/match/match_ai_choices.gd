class_name MatchAIPlanning
extends RefCounted


var e = null
var pq = null
var decide_cd = {}
var last_shot := [-10.0, -10.0]
var pass_chain = [[], []]
var chain_team = -1
var last_progress := [-1.0, -1.0]
var last_progress_clock := [0.0, 0.0]


const CROSS_PULL_BASE := -0.72
const CROSS_PULL_SPAN := 2.0


static func cross_pull(style: Dictionary) -> float:
	return CROSS_PULL_BASE + clampf(float(style.get("crossing", 0.5)), 0.0, 1.0) * CROSS_PULL_SPAN

func _init(brain) -> void:
	e = brain.e
	pq = brain.pq


func reset_state() -> void:
	pass_chain = [[], []]
	chain_team = -1
	last_shot = [-10.0, -10.0]
	decide_cd.clear()

func update(dt: float) -> void:
	var owner = e.ball_owner()
	if owner == null:
		return
	if owner.is_gk:
		_gk_distribute(owner)
	else:
		decide(owner)

func _gk_distribute(gk) -> void:
	if gk.action_t > 0.0:
		return
	gk.action_t = 0.5
	var style: Dictionary = e.style_of(gk.team)
	var press: float = e.pressure_on(gk)
	if style["possession"] > 0.58 and press < 0.9 and e.rng.randf() < 0.62:
		var mate = e._best_short_outlet(gk.team, gk)
		if mate != null:
			e.pass_ball(gk, mate.pos + Vector2(e.teams[gk.team]["dir"] * 2.0, 0.0), false, mate)
			gk.state = "gk"
			return
	e.keeper_clear(gk, Vector2(e.L * 0.5 + e.teams[gk.team]["dir"] * 10.0, 34.0 + e.rng.randf_range(-18.0, 18.0)))

func decide(p) -> void:
	if not _due(p):
		return
	var pressure: float = e.pressure_on(p)
	var goal: Vector2 = e.target_goal_pos(p.team)
	var dist: float = p.pos.distance_to(goal)
	var angle: float = e.opponent_goal_angle(p)
	var style: Dictionary = e.style_of(p.team)
	var own_third: bool = e.attacking_x(p.team, p.pos) < e.L * 0.34
	var final_third: bool = e.attacking_x(p.team, p.pos) > e.L * 0.66

	if _try_shot(p, dist, angle, pressure, final_third):
			return
	if _try_long_shot(p, dist, pressure, angle):
		return
	var best = _best_pass(p, style)
	var drib_score: float = _dribble_score(p, dist, pressure, style, own_third)
	var clear_score: float = _clear_score(p, pressure, own_third)

	if clear_score > drib_score and clear_score > best["score"]:
		var aim: Vector2 = Vector2(e.L * 0.5 + e.teams[p.team]["dir"] * 14.0, clampf(34.0 + e.rng.randf_range(-18.0, 18.0), 8.0, e.W - 8.0))
		e.clear_ball(p, aim)
		return
	if best["mate"] != null and best["score"] > drib_score and best["score"] > 0.40:
		if e.verbose:
			e._vlog("  decide-pass %s score=%.2f vs dribble %.2f (%s %.0fm)" % [best["mate"].name, best["score"], drib_score, best["kind"], p.pos.distance_to(best["mate"].pos)])
		_remember_pass(p)
		e.pass_ball(p, best["point"], best["loft"], best["mate"], best["kind"])
		return
	_dribble(p, goal, pressure)


func _due(p) -> bool:
	if p.action_t > 0.0:
		return false
	var cd: float = decide_cd.get(p.id, 0.0)
	if e.clock < cd:
		return false
	var pressure: float = e.pressure_on(p)
	var deep_attack: bool = e.attacking_x(p.team, p.pos) > e.L * 0.62
	decide_cd[p.id] = e.clock + ((0.30 if deep_attack else 0.55) + pressure * 0.12 + e.rng.randf_range(0.0, 0.12))
	return true

func _try_shot(p, dist: float, angle: float, pressure: float, final_third: bool) -> bool:
	if not (dist < 27.0 and angle > 0.04 and p.cooldown <= 0.0 and p.attr["sho"] >= 40.0 and e.clock - last_shot[p.team] > 5.0):
		return false
	var goal: Vector2 = e.target_goal_pos(p.team)
	var blocked: float = _blocked_lanes(p, goal)
	var shoot_score: float = (p.attr["sho"] / 100.0) * 1.05 + angle * 1.55 - dist * 0.048 - pressure * 0.32 - blocked * 0.80
	if dist < 17.0:
		shoot_score += 0.45
	if dist < 11.0:
		shoot_score += 0.55
	if p.attr["sho"] < 55.0:
		shoot_score -= 0.30
	if final_third and e.rng.randf() < 0.05:
		shoot_score += 0.35

	var to_goal: Vector2 = (goal - p.pos).normalized()
	var facing_goal: float = p.facing.dot(to_goal)
	if dist < 12.5 and blocked < 0.10 and facing_goal > 0.25 and e.rng.randf() < 0.14:
		_finish(p, dist)
		return true
	if shoot_score > 1.90 + pressure * 0.18:
		_finish(p, dist)
		return true
	return false


func _blocked_lanes(p, goal: Vector2) -> float:
	var blocked: float = 0.0
	var to_goal: Vector2 = (goal - p.pos).normalized()
	for q in e.players:
		if q.team == p.team or q.is_gk or q.sent_off:
			continue
		var rel: Vector2 = q.pos - p.pos
		var along: float = rel.dot(to_goal)
		if along > 0.7 and along < 16.0:
			var perp: float = absf(rel.cross(to_goal))
			if perp < 1.6:
				blocked += (1.0 - perp / 1.6) * (1.0 - along / 20.0)
	return blocked


func _try_long_shot(p, dist: float, pressure: float, angle: float) -> bool:
	if not (dist >= 19.0 and dist < 30.0 and pressure < 0.55 and angle > 0.10 and p.cooldown <= 0.0):
		return false
	if p.attr["sho"] > 68.0 and e.rng.randf() < 0.010:
		var lside: float = 1.0 if e.rng.randf() < 0.5 else -1.0
		e.shoot_ball(p, lside * e.rng.randf_range(1.8, 3.0), e.rng.randf_range(0.4, 1.8), 1.0)
		return true
	return false


func _best_pass(p, style: Dictionary) -> Dictionary:
	var best = null
	var best_s := -1e9
	var best_point: Vector2 = Vector2.ZERO
	var best_kind := "pass"
	var best_loft := false
	var goal: Vector2 = e.target_goal_pos(p.team)
	for q in e.teammates_of(p):
		if q.is_gk and p.pos.distance_to(goal) > 34.0:
			continue
		var d: float = p.pos.distance_to(q.pos)
		if d < 2.6 or d > 48.0:
			continue


		if e.would_be_offside(q) and e.rng.randf() < 0.55 + float(p.attr["pas"]) * 0.004:
			continue
		var flight: float = d / 14.0
		var lead: Vector2 = q.vel * clampf(flight, 0.15, 1.1)
		var pt: Vector2 = q.pos + lead
		var lane: float = pq.lane_risk(p.pos, pt, p.team)
		var open: float = minf(10.0, e.nearest_opponent_dist(q.pos, p.team))
		var prog: float = (e.attacking_x(p.team, q.pos) - e.attacking_x(p.team, p.pos)) / 38.0
		var dpen: float = maxf(0.0, d - 12.0) * 0.045
		var s: float = -lane * 2.40 + open * 0.26 + prog * (0.55 + style["directness"] * 0.35) - dpen
		if d < 16.0:
			s += 0.20
		s += e.push_of(q) * 0.18
		if prog < -0.25:
			s -= 0.35
		if d > 34.0:
			s -= 0.25
		if absf(q.pos.y - p.pos.y) > 26.0 and open > 7.0 and d < 42.0:
			s += 0.38

		if prog > 0.18 and e.push_of(q) > 0.6 and d < 24.0:
			var space_behind: float = pq.space_behind(p.team, q)
			if space_behind > 4.0:
				var thru: Vector2 = q.pos + Vector2(e.teams[p.team]["dir"] * clampf(space_behind * 0.5, 4.0, 9.0), q.vel.y * 0.15)
				var tlane: float = pq.lane_risk(p.pos, thru, p.team)
				var ts: float = s + 0.20 - tlane * 1.2
				if ts > best_s:
					best_s = ts
					best = q
					best_point = thru
					best_kind = "through"
					best_loft = false


		var wide: bool = absf(p.pos.y - 34.0) > 18.0
		var in_box: bool = e.attacking_x(p.team, q.pos) > e.L - 18.0 and absf(q.pos.y - 34.0) < 13.0
		if wide and in_box and d > 11.0 and d < 32.0:
			var cross_pt: Vector2 = q.pos + Vector2(e.teams[p.team]["dir"] * 2.2, 0.0)
			var cs: float = s + cross_pull(style)
			if cs > best_s:
				best_s = cs
				best = q
				best_point = cross_pt
				best_kind = "cross"
				best_loft = true
		if s > best_s:
			best_s = s
			best = q
			best_point = pt
			best_kind = "pass"
			best_loft = d > 30.0 or lane > 0.75
	return {"mate": best, "score": best_s, "point": best_point, "kind": best_kind, "loft": best_loft}

func _dribble_score(p, dist: float, pressure: float, style: Dictionary, own_third: bool) -> float:
	var space: float = pq.space_ahead(p)
	var score: float = (p.attr["dri"] / 100.0) * 1.18 + minf(space, 14.0) * 0.085 - pressure * 0.58
	score += _urgency(p.team) * 0.55
	if dist < 16.0:
		score -= 0.45
	score += (1.0 - style["directness"]) * 0.10
	if own_third and pressure > 1.0:
		score -= 0.55
	return score

func _clear_score(p, pressure: float, own_third: bool) -> float:
	var score := -0.15
	if own_third and pressure > 0.55 and p.role != "ST":
		score = 0.95 + pressure * 0.55
	if e.attacking_x(p.team, p.pos) < e.L * 0.13:
		score += 0.55
	return score

func _remember_pass(p) -> void:
	if chain_team != p.team:
		chain_team = p.team
		pass_chain[p.team] = []
	pass_chain[p.team].append(p.id)
	if pass_chain[p.team].size() > 3:
		pass_chain[p.team].pop_front()


func _dribble(p, goal: Vector2, pressure: float) -> void:
	var dirv: Vector2 = (goal - p.pos).normalized()
	var near = null
	var nd: float = 1e9
	for q in e.players:
		if q.team == p.team or q.sent_off:
			continue
		var dq: float = p.pos.distance_to(q.pos)
		if dq < nd:
			nd = dq
			near = q
	if near != null and nd < 9.0:
		var away: Vector2 = (p.pos - near.pos).normalized()
		var w: float = clampf(1.0 - nd / 9.0, 0.0, 1.0)
		dirv = (dirv * (1.0 - w * 0.55) + away * (w * 0.65)).normalized()

	if p.role in ["RW", "LW"] and absf(p.pos.y - 34.0) > 16.0:
		dirv = (dirv + Vector2(0, signf(p.pos.y - 34.0)) * 0.15).normalized()
	p.target = p.pos + dirv * 9.0
	p.speed_scale = 1.0
	p.state = "dribble"

	if pressure > 1.0 and e.rng.randf() < 0.012:
		var loose_dir: Vector2 = dirv.rotated(e.rng.randf_range(-0.8, 0.8))
		e.ball.owner_id = -1
		e.ball.vel = loose_dir * e.rng.randf_range(2.0, 4.5)
		e.ball.last_touch_id = p.id
		e.ball.last_touch_team = p.team
		p.has_ball = false


func _urgency(t: int) -> float:
	var ball_ax: float = e.attacking_x(t, e.ball.pos)
	if last_progress[t] < 0.0:
		last_progress[t] = ball_ax
		last_progress_clock[t] = e.clock
		return 0.0
	if ball_ax > last_progress[t] + 9.0:
		last_progress[t] = ball_ax
		last_progress_clock[t] = e.clock
		return 0.0
	if ball_ax < last_progress[t] - 14.0:
		last_progress[t] = ball_ax
		last_progress_clock[t] = e.clock
		return 0.0
	var stale: float = e.clock - last_progress_clock[t]
	return clampf((stale - 5.0) / 8.0, 0.0, 1.0)

func _finish(p, dist: float) -> void:
	last_shot[p.team] = e.clock
	var gk = e._gk_of(1 - p.team)
	var gk_y: float = 34.0 if gk == null else gk.pos.y
	var side: float = 1.0 if gk_y >= 34.0 else -1.0
	var aim_y: float = 0.0
	var roll: float = e.rng.randf()
	if roll < 0.45:
		aim_y = side * e.rng.randf_range(2.4, 3.3)
	elif roll < 0.70:
		aim_y = -side * e.rng.randf_range(2.2, 3.2)
	else:
		aim_y = e.rng.randf_range(-1.2, 1.2)
	var aim_z: float = e.rng.randf_range(0.25, 1.5) if dist > 12.0 else e.rng.randf_range(0.2, 1.1)
	var power: float = clampf(0.88 + dist * 0.005, 0.85, 1.06)
	e.shoot_ball(p, aim_y, aim_z, power)
