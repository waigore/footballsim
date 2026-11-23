extends "res://scripts/sim/match_engine_presentation.gd"

## Individual ball actions: control, passing, shooting, headers, keeper handling.

func _try_control(p, d: float) -> void:
	var speed = ball.vel.length()
	var q = Attrs.first_touch_quality(p)
	var pressure = pressure_on(p)
	var chance := clampf(0.80 + q * 0.26 - speed * 0.006 - pressure * 0.09, 0.42, 0.99)
	if p.offside_flag:
		_offside(p)
		return
	if rng.randf() > chance:
		if verbose:
			_vlog("MISCONTROL %s (speed %.1f chance %.2f)" % [p.name, speed, chance])
		# heavy touch: ball squirts away
		var ang = rng.randf_range(-1.2, 1.2)
		ball.vel = (p.facing.rotated(ang) * rng.randf_range(2.0, 5.0))
		ball.last_touch_id = p.id
		ball.last_touch_team = p.team
		p.cooldown = 0.25
		return
	_claim_ball(p)
	if speed > 11.0 and p.team == possession_team:
		p.stats["touches"] += 1

func _claim_ball(p) -> void:
	# Pass completion for the passer.
	if ball.assist_id >= 0 and ball.last_touch_team == p.team and p.id != ball.assist_id:
		var passer = by_id.get(ball.assist_id, null)
		if passer != null:
			passer.stats["passes_ok"] += 1
			stats[p.team]["passes_ok"] += 1
	# An opponent taking the ball ends the assist window.
	if p.team != ball.last_touch_team:
		ball.assist_id = -1
		ball.shot_team = -1
	ball.owner_id = p.id
	ball.pos = p.pos + p.facing * 0.45
	ball.pos.x = clampf(ball.pos.x, 0.35, L - 0.35)
	ball.pos.y = clampf(ball.pos.y, 0.35, W - 0.35)
	ball.vel = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	ball.spin = 0.0
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.planned_goal = false
	p.has_ball = true
	p.action_t = maxf(p.action_t, 0.14)
	p.stats["touches"] += 1
	if verbose:
		_vlog("CLAIM %s at (%.1f,%.1f)" % [p.name, p.pos.x, p.pos.y])
	if possession_team != p.team:
		possession_team = p.team
		possession_loose = false
	# Offside is judged at the pass, not carried forward: a touch by anyone
	# resets the phase, so stale flags must not convict a later receiver.
	for q in players:
		q.offside_flag = false
	if p.mark_id >= 0:
		p.mark_id = -1

func _gk_claim(gk, d: float) -> void:
	var speed = ball.vel.length()
	var handle = Attrs.gk_handling(gk)
	var catch_chance = clampf(0.55 + handle * 0.5 - speed * 0.018, 0.25, 0.98)
	var was_shot: bool = ball.shot_team == 1 - gk.team and clock - ball.shot_time < 4.0 and not ball.shot_saved
	gk.cooldown = 0.4
	if rng.randf() < catch_chance:
		ball.owner_id = gk.id
		ball.pos = gk.pos + Vector2(teams[gk.team]["dir"], 0.0) * 0.35
		ball.pos.x = clampf(ball.pos.x, 0.45, L - 0.45)
		ball.pos.y = clampf(ball.pos.y, 0.45, W - 0.45)
		gk.facing = Vector2(teams[gk.team]["dir"], 0.0)
		ball.vel = Vector2.ZERO
		ball.z = 0.0
		ball.vz = 0.0
		ball.last_touch_id = gk.id
		ball.last_touch_team = gk.team
		ball.shot_team = -1
		ball.assist_id = -1
		gk.has_ball = true
		ball.last_touch_time = clock
		if was_shot:
			ball.shot_saved = true
			gk.stats["saves"] += 1
			stats[gk.team]["saves"] += 1
			_emit("save", Commentary.save(rng, gk.name, _shot_credit(gk), "hold", ball.shot_xg), gk.team, gk)
			_flash(0.8)
		gk.action_t = 0.8
		gk.state = "gk_hold"
	else:
		# parry: pushed wide of the frame, never back into the six-yard box
		var away = Vector2(teams[gk.team]["dir"], 0.85 * (1.0 if ball.pos.y < W * 0.5 else -1.0)).normalized()
		away = away.rotated(rng.randf_range(-0.35, 0.35))
		ball.vel = away.rotated(rng.randf_range(-0.5, 0.5)) * rng.randf_range(6.0, 11.0)
		ball.vz = 1.6
		ball.z = 0.2
		ball.owner_id = -1
		ball.shot_team = -1
		if was_shot:
			ball.shot_saved = true
			gk.stats["saves"] += 1
			stats[gk.team]["saves"] += 1
			_emit("save", Commentary.save(rng, gk.name, _shot_credit(gk), "parry", ball.shot_xg), gk.team, gk)
			_flash(0.8)

func _header(p) -> void:
	var to_goal = target_goal_pos(p.team) - p.pos
	var dir: Vector2 = to_goal.normalized()
	var attacking = false
	if ball.last_touch_team == p.team or ball.last_touch_team == -1:
		attacking = true
	p.jump_t = 0.45
	p.cooldown = 0.7
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	if p.team == possession_team or attacking:
		# Header at goal if facing it, otherwise cushion to a teammate.
		if to_goal.length() < 18.0 and absf(to_goal.x) > absf(to_goal.y) * 0.3:
			var aim = Vector2(to_goal.x, clampf(to_goal.y, -2.6, 2.6))
			ball.vel = aim.normalized() * rng.randf_range(9.0, 15.0)
			ball.vz = 1.2
			ball.z = maxf(ball.z, 1.7)
			_emit("header", Commentary.shot(rng, p.name, to_goal.length(), 0.18, pressure_on(p), "header"), p.team, p)
			_stats_shot(p, 0.18, "header")
			stats[p.team]["xg"] += 0.18
		else:
			var mate = _best_outlet(p)
			var tp: Vector2 = mate.pos if mate != null else p.pos + Vector2(teams[p.team]["dir"] * 8.0, 0.0)
			ball.vel = (tp - ball.pos).normalized() * 9.0
			ball.vz = 1.0
	else:
		# Defensive clearance
		var away = Vector2(teams[p.team]["dir"] * 24.0, rng.randf_range(-14.0, 14.0))
		ball.vel = away.normalized() * rng.randf_range(10.0, 16.0)
		ball.vz = 5.5
		ball.z = maxf(ball.z, 1.8)
		_emit("clearance", Commentary.clearance(rng, p.name, true), p.team, p)
		ball_kicked.emit(0.5)

func _best_outlet(p):
	var best = null
	var bs = -1e9
	for q in teammates_of(p):
		if q.is_gk:
			continue
		var d: float = p.pos.distance_to(q.pos)
		var adv: float = attacking_x(p.team, q.pos) - attacking_x(p.team, p.pos)
		var s = -absf(d - 14.0) * 0.2 + adv * 0.08 + rng.randf_range(0.0, 2.0)
		if s > bs:
			bs = s
			best = q
	return best

# ----------------------------------------------------------------- actions --

func pass_ball(p, target_point: Vector2, lofted: bool = false, receiver = null, kind: String = "pass") -> void:
	if p == null:
		return
	var dist: float = p.pos.distance_to(target_point)
	var pressure = pressure_on(p)
	var live: Dictionary = style_of(p.team)
	var sigma = Attrs.pass_sigma_deg(p, dist, pressure) / home_factor(p)
	if kind == "cross":
		sigma *= 1.15 - float(live["crossing"]) * 0.30
	var aim = target_point
	if lofted:
		var land_sigma: float = dist * tan(deg_to_rad(sigma)) * 0.8
		aim += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * land_sigma
		var apex = clampf(dist * 0.16, 3.0, 9.0)
		ball.vz = sqrt(2.0 * 9.81 * apex)
		var flight = 2.0 * ball.vz / 9.81
		var horiz: float = p.pos.distance_to(aim) / maxf(flight, 0.25)
		horiz = clampf(horiz, 6.0, 26.0)
		ball.vel = (aim - p.pos).normalized() * horiz
		ball.z = 0.25
		ball.spin = rng.randf_range(-0.8, 0.8)
	else:
		var ang_err = deg_to_rad(rng.randf_range(-sigma, sigma))
		var dir: Vector2 = (aim - p.pos).normalized().rotated(ang_err)
		var sp: float = Attrs.pass_speed_for(p, dist) * (0.88 + float(live["tempo"]) * 0.24) * (1.0 + rng.randf_range(-0.06, 0.06))
		ball.vel = dir * sp
		ball.z = 0.0
		ball.vz = 0.0
		ball.spin = rng.randf_range(-0.3, 0.3)
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.last_touch_time = clock
	ball.last_kick_id = p.id
	ball.assist_id = p.id
	ball.assist_time = clock
	ball.shot_team = -1
	ball.planned_goal = false
	p.has_ball = false
	p.cooldown = 0.22
	p.state = "pass"
	p.stats["passes"] += 1
	stats[p.team]["passes"] += 1
	possession_team = p.team
	_mark_offside_at_pass(p)
	# Tell the intended receiver to attack the ball.
	if receiver == null:
		receiver = _nearest_teammate_to(aim, p.team, false, p.id)
	if receiver != null:
		receiver.run_to = aim
		receiver.run_until = clock + 2.6
	if verbose:
		_vlog("PASS %s -> %s aim=(%.1f,%.1f) dist=%.1f loft=%s kind=%s" % [p.name, receiver.name if receiver != null else "-", aim.x, aim.y, dist, str(lofted), kind])
	if kind == "cross":
		_add_involvement(p, "cross", "Cross into the box", p.pos)
		_emit("cross", Commentary.cross(rng, p.name), p.team, p)
	elif kind == "through":
		_add_involvement(p, "pass", "Through ball", p.pos)
	else:
		_add_involvement(p, "pass", "Pass %dm" % int(dist), p.pos)

func shoot_ball(p, aim_y: float, aim_z: float, power: float = 1.0, kind: String = "shot") -> void:
	var goal: Vector2 = target_goal_pos(p.team)
	var dist: float = p.pos.distance_to(goal)
	var pressure = pressure_on(p)
	var sigma = Attrs.shot_sigma_deg(p, dist, pressure) / home_factor(p)
	if kind == "penalty":
		sigma *= 0.30
		# Finishing: keepers stop most on-target efforts; only the best chances beat them.
	var gkk = _gk_of(1 - p.team)
	var xg_est: float = expected_goals(p.pos, aim_y, p.team)
	var aim = Vector2(goal.x, goal.y + aim_y)
	var ang = atan2(aim.y - p.pos.y, aim.x - p.pos.x) + deg_to_rad(rng.randf_range(-sigma, sigma))
	var speed = Attrs.shot_speed(p, power) * rng.randf_range(0.94, 1.06)
	var dir = Vector2(cos(ang), sin(ang))
	# Only shots that were already on target get smothered by the keeper;
	# wild efforts stay wild, which keeps the on-target stats honest.
	var tg0: float = (goal.x - p.pos.x) / maxf(absf(dir.x), 0.05) * signf(goal.x - p.pos.x)
	var y_cross: float = p.pos.y + dir.y * absf(tg0)
	var on_target: bool = tg0 > 0.0 and absf(y_cross - goal.y) < GOAL_W * 0.5 and aim_z < GOAL_H
	# Finishing: an on-target shot scores with p = xG / (share of shots that are
	# on target), so a match's goals track its expected goals. Everything else
	# the keeper gets to is steered onto him, which keeps the save honest.
	ball.planned_goal = false
	if kind != "penalty" and rng.randf() < clampf(FINISH_EFFICIENCY * xg_est, 0.02, 0.92):
		# This chance is converted: put it inside a post, so a goal is always a
		# shot that beat the keeper and the goal-line save cannot veto it. The
		# conversion rate is then exactly xG, independent of shot accuracy.
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var ty: float = goal.y + side * minf(GOAL_W * 0.5 - 0.12, rng.randf_range(2.1, 3.45))
		ang = atan2(ty - p.pos.y, goal.x - p.pos.x)
		dir = Vector2(cos(ang), sin(ang))
		on_target = true
		ball.planned_goal = true
	elif on_target and gkk != null:
		# A chance that will not be converted is smothered: aim it at the keeper.
		ang = atan2(gkk.pos.y - p.pos.y, goal.x - p.pos.x)
		dir = Vector2(cos(ang), sin(ang))
		speed *= 0.97
	var flight: float = maxf(0.12, dist / maxf(speed, 1.0))
	var zt = clampf(aim_z + rng.randf_range(-0.35, 0.35), 0.12, 2.6)
	ball.vz = (zt - 0.11) / flight + 0.5 * 9.81 * flight
	ball.vz = clampf(ball.vz, -1.0, 9.0)
	ball.vel = dir * speed
	ball.z = 0.11
	ball.spin = rng.randf_range(-1.6, 1.6)
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.last_kick_id = p.id
	ball.shot_team = p.team
	ball.shot_time = clock
	ball.shot_saved = false
	ball.assist_id = -1
	# Record whether this one was on target (projected to the goal plane).
	var tg: float = (goal.x - p.pos.x) / maxf(absf(dir.x * speed), 0.1) * signf(goal.x - p.pos.x)
	if tg > 0.0:
		var y_at: float = p.pos.y + dir.y * speed * tg
		var z_at: float = 0.11 + ball.vz * tg - 4.905 * tg * tg
		if absf(y_at - goal.y) < GOAL_W * 0.5 and z_at < GOAL_H and z_at > -0.1:
			p.stats["on_target"] += 1
			stats[p.team]["on_target"] += 1
	p.has_ball = false
	p.cooldown = 0.45
	p.state = "shoot"
	p.action_t = 0.4
	var xg = expected_goals(p.pos, aim_y, p.team)
	ball.shot_xg = xg
	shot_buckets[int(dist / 5)] = shot_buckets.get(int(dist / 5), 0) + 1
	_stats_shot(p, xg, kind)
	_add_involvement(p, "shot", "Shot (%.2f xG)" % xg, p.pos)
	stats[p.team]["xg"] += xg
	if xg > 0.28:
		stats[p.team]["big_chances"] += 1
	_emit("shot", Commentary.shot(rng, p.name, dist, xg, pressure, kind), p.team, p, {"xg": xg})
	var near_def := 0
	var min_def := 99.0
	var goal_side_def := 0
	var gpos: Vector2 = target_goal_pos(p.team)
	for q in players:
		if q.team == p.team or q.sent_off or q.is_gk:
			continue
		var dd: float = q.pos.distance_to(p.pos)
		if dd < 8.0:
			near_def += 1
		min_def = minf(min_def, dd)
		if q.pos.distance_to(gpos) < p.pos.distance_to(gpos) - 0.5:
			goal_side_def += 1
	var _gkdbg = _gk_of(1 - p.team)
	ball_kicked.emit(1.0)
	if verbose:
		_vlog("SHOT %s dist=%.1f role=%s near_def=%d mindef=%.1f goalside=%d gkdist_goal=%.1f press=%.2f" % [p.name, dist, p.role, near_def, min_def, goal_side_def, _gkdbg.pos.distance_to(gpos) if _gkdbg else -1, pressure])
	_flash(0.7)
	brain.on_shot(p)

func _stats_shot(p, xg: float, kind: String) -> void:
	p.stats["shots"] += 1
	stats[p.team]["shots"] += 1

func expected_goals(pos: Vector2, aim_y: float, team: int) -> float:
	var goal: Vector2 = target_goal_pos(team)
	var d: float = pos.distance_to(goal)
	var ang: float = opponent_goal_angle_for(pos, goal)
	var xg: float = exp(-0.125 * d) * (0.22 + ang * 0.55)
	xg *= 1.0 - clampf((absf(aim_y) - 1.0) * 0.06, 0.0, 0.25)
	# Scaled to the Poisson model's level: the raw positional model was ~40%
	# more generous than real football, so a dominant side read 3.5 xG.
	return clampf(xg * XG_SCALE, 0.006, 0.86)

func opponent_goal_angle_for(pos: Vector2, goal: Vector2) -> float:
	var dx = absf(goal.x - pos.x)
	var half = GOAL_W * 0.5
	return clampf(atan2(half, maxf(dx, 0.4)) / 0.9, 0.0, 1.0)

func clear_ball(p, point: Vector2) -> void:
	var dist: float = p.pos.distance_to(point)
	ball.vz = sqrt(2.0 * 9.81 * clampf(dist * 0.22, 4.0, 11.0))
	var flight = 2.0 * ball.vz / 9.81
	ball.vel = (point - p.pos).normalized() * clampf(dist / maxf(flight, 0.2), 8.0, 28.0)
	ball.z = 0.2
	ball.owner_id = -1
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.planned_goal = false
	p.has_ball = false
	p.cooldown = 0.35
	p.state = "clear"
	_emit("clearance", Commentary.clearance(rng, p.name, false), p.team, p)
	_add_involvement(p, "clearance", "Clearance", p.pos)
	ball_kicked.emit(0.7)

# ------------------------------------------------------------------- rules --

## Would a pass to this team-mate catch him offside right now? The AI uses this
## to avoid passes the referee would flag.
func would_be_offside(receiver) -> bool:
	var t: int = receiver.team
	var ax_ball: float = attacking_x(t, ball.pos)
	var xs := offside_xs(t)
	if xs.size() < 2:
		return false
	var line: float = xs[1]
	var ax: float = attacking_x(t, receiver.pos)
	return ax > ax_ball + 0.35 and ax > L * 0.5 and ax > line + 0.45

func _mark_offside_at_pass(p) -> void:
	if phase != "play":
		return
	var t: int = p.team
	var ax_ball: float = attacking_x(t, ball.pos)
	var defenders := offside_xs(t)
	if defenders.size() < 2:
		return
	var line: float = defenders[1]
	for q in players:
		if q.team != t or q.id == p.id or q.sent_off or q.is_gk:
			continue
		var ax = attacking_x(t, q.pos)
		q.offside_flag = (ax > ax_ball + 0.35 and ax > L * 0.5 and ax > line + 0.45)
		if q.offside_flag:
			q.run_until = 0.0
