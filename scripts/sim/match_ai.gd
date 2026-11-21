class_name MatchAI
extends RefCounted

## Team brains: collective shape, pressing, marking, and on-ball decisions.
## All reads/writes go through the engine `e` (untyped to keep the dependency one-way).

var e = null
var shape_timer = 0.0
var mark_timer = 0.0
var decide_cd = {}
var gk_react_at = [-1.0, -1.0]
var run_cd = {}
var kickoff_lock = 0.0
var pass_chain = [[], []]
var chain_team = -1

func _init(engine) -> void:
	e = engine

func on_kickoff() -> void:
	pass_chain = [[], []]
	chain_team = -1
	decide_cd.clear()
	run_cd.clear()
	gk_react_at = [-1.0, -1.0]
	kickoff_lock = 1.2

func on_restore() -> void:
	pass_chain = [[], []]
	chain_team = -1
	decide_cd.clear()
	run_cd.clear()

func on_shot(shooter) -> void:
	var t: int = 1 - shooter.team
	var gk = e._gk_of(t)
	if gk != null:
		gk_react_at[t] = e.clock + Attrs.gk_reaction(gk) * e.rng.randf_range(0.75, 1.35)

func update(dt: float) -> void:
	if kickoff_lock > 0.0:
		kickoff_lock -= dt
	shape_timer -= dt
	mark_timer -= dt
	if mark_timer <= 0.0:
		_assign_marks()
		mark_timer = 0.45
	if shape_timer <= 0.0:
		_update_shapes()
		shape_timer = 0.11
	var owner = e.ball_owner()
	if owner != null and not owner.is_gk:
		_carrier_decide(owner)
	elif owner != null and owner.is_gk:
		_gk_distribute(owner)

func update_restart(dt: float, restart: Dictionary) -> void:
	if restart.get("type", "") == "penalty":
		return
	shape_timer -= dt
	if shape_timer <= 0.0:
		_update_shapes()
		shape_timer = 0.15
	# The taker is driven by the engine; everyone else holds shape.

# ------------------------------------------------------------------- shape --

func _update_shapes() -> void:
	var bt: int = e.possession_team
	var ball = e.ball
	for p in e.players:
		if p.sent_off or p.celebrate > 0.0:
			continue
		if p.is_gk:
			_gk_shape(p)
			continue
		if e.ball.owner_id == p.id:
			continue
		if p.run_until > e.clock:
			p.target = p.run_to
			p.speed_scale = 1.0
			p.state = "run"
			continue
		var style: Dictionary = e.teams[p.team]["data"]["style"]
		var b: Vector2 = p.base
		var bn: Vector2 = e.to_norm(p.team, ball.pos)
		var attacking: bool = (p.team == bt)
		var tx = 0.0
		var ty = 0.0
		if attacking:
			tx = b.x * 0.90 + 0.115 + (bn.x - 0.5) * 0.16
			ty = 0.5 + (b.y - 0.5) * (0.82 + style["width"] * 0.42)
			tx += Attrs.role_push(p.role) * 0.055
			tx += style["possession"] * 0.03
		else:
			var line: float = style["line"]
			tx = b.x * 0.88 + 0.055 + bn.x * 0.30 - 0.12 - (line - 0.5) * 0.10
			ty = 0.5 + (b.y - 0.5) * 0.78
			# Compact toward the ball side.
			ty -= (bn.y - 0.5) * 0.10
		tx = clampf(tx, 0.035, 0.96)
		ty = clampf(ty, 0.035, 0.965)
		var target: Vector2 = e.to_world(p.team, Vector2(tx, ty))
		if attacking:
			target = _attack_shape(p, target)
		else:
			target = _defence_shape(p, target)
		p.target = target
		p.speed_scale = 0.86 if attacking else 0.94
	_apply_pressing()

func _attack_shape(p, fallback: Vector2) -> Vector2:
	var ball = e.ball
	var ax = e.attacking_x(p.team, ball.pos)
	var my_ax = e.attacking_x(p.team, p.pos)
	var style: Dictionary = e.teams[p.team]["data"]["style"]
	var target = fallback
	# Strikers and wingers attack the space behind once the ball is advanced.
	if Attrs.role_push(p.role) >= 0.7 and ax > e.L * 0.48:
		var line = _offside_line(p.team)
		var run_x = line - e.rng.randf_range(0.4, 2.4)
		if my_ax < run_x:
			var world_y = p.pos.y
			if p.role == "ST":
				world_y = lerpf(world_y, 34.0, 0.35)
			# Convert attacking x back to world x.
			var world_x = e.teams[p.team]["dir"] * 1.0
			var w = Vector2(run_x if e.teams[p.team]["dir"] == 1 else e.L - run_x, world_y)
			target = w
	# Support the carrier: offer a lane 10-16m ahead and to the side.
	var owner = e.ball_owner()
	if owner != null and owner.team == p.team and owner.id != p.id:
		var d = p.pos.distance_to(owner.pos)
		if d < 16.0 and Attrs.role_push(p.role) > 0.2:
			var ahead: Vector2 = target
			ahead.x += e.teams[p.team]["dir"] * 2.0
			target = target.lerp(ahead, 0.25)
	# Wide players hold width when the ball is central.
	if p.role in ["RW", "LW"] and absf(ball.pos.y - 34.0) < 12.0:
		target.y = lerpf(target.y, 8.0 if p.role == "RW" else 60.0, 0.35)
	# Respect the offside line unless the ball is already beyond it.
	if Attrs.role_push(p.role) >= 0.6:
		var line = _offside_line(p.team)
		var cap = line - 0.35
		var tx_att = e.attacking_x(p.team, target)
		var ball_att = e.attacking_x(p.team, ball.pos)
		if tx_att > cap and ball_att < cap:
			var capped = maxf(cap, ball_att) if ball_att > e.L * 0.5 else cap
			target.x = capped if e.teams[p.team]["dir"] == 1 else e.L - capped
	return target

func _defence_shape(p, fallback: Vector2) -> Vector2:
	var own: Vector2 = e.own_goal_pos(p.team)
	var ball = e.ball
	var dist_to_own: float = ball.pos.distance_to(own)
	var target: Vector2 = fallback
	var is_back: bool = Attrs.is_defender(p.role)
	var is_holder: bool = p.role in ["RDM", "LDM", "CDM"]
	# Last-ditch wall: with the ball in our box, the back line forms a screen in front of goal.
	if dist_to_own < 21.0 and is_back:
		var axis_w: Vector2 = (ball.pos - own).normalized()
		if axis_w.length() < 0.1:
			axis_w = Vector2(1, 0)
		var perp_w: Vector2 = Vector2(-axis_w.y, axis_w.x)
		var lat: float = (p.base.y - 0.5) * 2.0
		return own + axis_w * 4.6 + perp_w * (lat * 8.5)
	# Zonal block: when the ball is near our goal, every defender must be goal-side of it.
	if dist_to_own < 34.0 and (is_back or is_holder):
		var to_ball: Vector2 = (ball.pos - own)
		if to_ball.length() < 0.1:
			to_ball = Vector2(1, 0)
		var axis: Vector2 = to_ball.normalized()
		var perp: Vector2 = Vector2(-axis.y, axis.x)
		var lateral: float = (p.base.y - 0.5) * 2.0
		# Back four hold a line 4-7m goal-side of the ball; holders screen in front of it.
		var depth: float = dist_to_own - (4.5 if is_back else 7.5)
		depth = clampf(depth, 1.6, 30.0)
		var spread: float = (8.0 if is_back else 11.0) * lateral
		target = own + axis * depth + perp * spread
	# Man-mark the nearest dangerous opponent.
	var threat = null
	var best := 1e9
	for q in e.players:
		if q.team == p.team or q.sent_off or q.is_gk:
			continue
		var ax: float = e.attacking_x(p.team, q.pos)
		if ax < e.L * 0.45:
			continue
		var dq: float = p.pos.distance_to(q.pos)
		if dq > 16.0:
			continue
		var score: float = dq - ax * 0.12
		if score < best:
			best = score
			threat = q
	if threat != null and (is_back or is_holder or p.role in ["RM", "LM", "CM"]):
		var goal_side: Vector2 = (own - threat.pos).normalized()
		var mark: Vector2 = threat.pos + goal_side * 1.15
		# Only abandon the zone if the mark is still goal-side of the ball.
		if mark.distance_to(own) < dist_to_own + 2.5:
			target = mark
	# Never go ahead of the ball when defending deep.
	if dist_to_own < 26.0 and target.distance_to(own) > dist_to_own + 3.5:
		target = own + (target - own).normalized() * (dist_to_own + 3.5)
	if is_back:
		var defensive_line: Vector2 = _defensive_line(p.team)
		var ax2: float = e.attacking_x(p.team, target)
		var line_ax: float = e.attacking_x(p.team, defensive_line)
		ax2 = clampf(ax2, line_ax - 11.0, line_ax + 1.5)
		target.x = ax2 if e.teams[p.team]["dir"] == 1 else e.L - ax2
	return target

func _apply_pressing() -> void:
	var bt: int = e.possession_team
	# Each team sends its quickest player to the ball, with a second player covering.
	for t in range(2):
		if t == bt and e.ball.owner_id >= 0:
			continue
		var presser = null
		var best_t := 99.0
		var second = null
		var second_t := 99.0
		for p in e.players:
			if p.team != t or p.sent_off or p.is_gk:
				continue
			var rt := _ball_reach_time(p)
			if rt < best_t:
				second_t = best_t
				second = presser
				best_t = rt
				presser = p
			elif rt < second_t:
				second_t = rt
				second = p
		if presser == null:
			continue
		var style = e.teams[t]["data"]["style"]
		var max_press: float = 20.0 + style["press"] * 26.0
		var owner = e.ball_owner()
		if best_t < 9.0 and (e.ball.owner_id < 0 or e.ball.pos.distance_to(presser.pos) < max_press):
			var target: Vector2
			if owner != null and owner.team != t:
				target = owner.pos + owner.vel * 0.20
				target += (e.own_goal_pos(t) - owner.pos).normalized() * 0.5
			else:
				target = _intercept_point(presser)
			target.x = clampf(target.x, 0.5, e.L - 0.5)
			target.y = clampf(target.y, 0.5, e.W - 0.5)
			presser.target = target
			presser.speed_scale = 1.0
			presser.state = "press"
		var deep: bool = e.attacking_x(t, e.ball.pos) < e.L * 0.36
		if second != null and second_t < 9.0:
			if owner != null and (deep or e.attacking_x(t, e.ball.pos) < e.L * 0.42):
				second.target = owner.pos + owner.vel * 0.16
				second.speed_scale = 1.0
				second.state = "press"
			else:
				var cover: Vector2 = e.ball.pos.lerp(e.own_goal_pos(t), 0.18)
				second.target = cover
				second.speed_scale = 0.95
		if deep:
			# Emergency: the third-closest defender also collapses on the ball.
			var third = null
			var third_t := 99.0
			for p in e.players:
				if p.team != t or p.sent_off or p.is_gk or p == presser or p == second:
					continue
				var rt: float = _ball_reach_time(p)
				if rt < third_t:
					third_t = rt
					third = p
			if third != null and third_t < 3.0:
				third.target = e.ball.pos + e.ball.vel * 0.10
				third.speed_scale = 1.0

func _ball_reach_time(p) -> float:
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

func _intercept_point(p) -> Vector2:
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

func _assign_marks() -> void:
	for t in range(2):
		var attackers = []
		for p in e.players:
			if p.team != t or p.sent_off or p.is_gk:
				continue
			attackers.append(p)
		attackers.sort_custom(func(a, b): return e.attacking_x(t, a.pos) > e.attacking_x(t, b.pos))
		var defenders = []
		for p in e.players:
			if p.team == t or p.sent_off or p.is_gk:
				continue
			if not (Attrs.is_defender(p.role) or p.role in ["RDM", "LDM", "CDM"]):
				continue
			defenders.append(p)
			p.mark_id = -1
		for a in attackers:
			var best = null
			var bd = 1e9
			for d in defenders:
				if d.mark_id >= 0:
					continue
				var dist = d.pos.distance_to(a.pos)
				if dist < bd:
					bd = dist
					best = d
			if best != null and bd < 26.0:
				best.mark_id = a.id

func _offside_line(t: int) -> float:
	# Attacking-x of the second-last defender of the opposing team.
	var xs = []
	for q in e.players:
		if q.team == t or q.sent_off:
			continue
		xs.append(e.attacking_x(t, q.pos))
	xs.sort()
	if xs.size() < 2:
		return e.L * 0.85
	return xs[xs.size() - 2]

func _defensive_line(t: int) -> Vector2:
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

func _gk_shape(gk) -> void:
	var own: Vector2 = e.own_goal_pos(gk.team)
	var ball = e.ball
	var to_ball: Vector2 = ball.pos - own
	var dist = to_ball.length()
	var target: Vector2
	# Anticipate a shot: move to the projected crossing point.
	var toward_goal: bool = ball.vel.dot(Vector2(-float(e.teams[gk.team]["dir"]), 0.0)) > 2.0
	if toward_goal and dist < 34.0 and ball.vel.length() > 9.0:
		var t_cross = (own.x - ball.pos.x) / maxf(absf(ball.vel.x), 0.1) * signf(ball.vel.x)
		if t_cross > 0.0 and t_cross < 1.6:
			var y_cross: float = ball.pos.y + ball.vel.y * t_cross
			var react: float = gk_react_at[gk.team]
			if react < 0.0 or e.clock > react:
				var reach_x: float = own.x + (0.55 if gk.team == 0 else -0.55)
				target = Vector2(reach_x, clampf(y_cross, own.y - 4.4, own.y + 4.4))
				gk.speed_scale = 1.0
				gk.state = "gk_dive"
				if absf(y_cross - gk.pos.y) > 1.2:
					gk.dive = Vector2(0, signf(y_cross - gk.pos.y) * 0.9)
					gk.dive_t = 0.35
				gk.target = target
				return
	# Otherwise hold a keeper's arc between ball and goal.
	var depth = clampf(1.2 + dist * 0.075, 1.2, 6.0)
	if dist > 55.0:
		depth = 1.6
	var guard: Vector2 = own + to_ball.normalized() * depth
	guard.y = clampf(guard.y, own.y - 5.2, own.y + 5.2)
	guard.x = clampf(guard.x, minf(own.x, own.x + (2.0 if gk.team == 0 else -2.0)), maxf(own.x, own.x + (2.0 if gk.team == 0 else -2.0)))
	# Sweeper-keeper: come and collect loose balls, and close down a clean run at goal.
	if ball.owner_id < 0 and dist < 20.0 and ball.z < 1.2:
		var opp = e.nearest_opponent(ball.pos, gk.team)
		var od: float = 99.0 if opp == null else opp.pos.distance_to(ball.pos)
		if od > gk.pos.distance_to(ball.pos) * 0.9:
			guard = ball.pos
	elif ball.owner_id >= 0 and dist < 4.0:
		var carrier = e.ball_owner()
		if carrier != null and carrier.team != gk.team:
			guard = carrier.pos.lerp(own, 0.35)
	gk.target = guard
	gk.speed_scale = 0.92
	gk.state = "gk"

func _gk_distribute(gk) -> void:
	if gk.action_t > 0.0:
		return
	gk.action_t = 0.5
	var style: Dictionary = e.teams[gk.team]["data"]["style"]
	var press: float = e.pressure_on(gk)
	if style["possession"] > 0.58 and press < 0.9 and e.rng.randf() < 0.62:
		var mate = e._best_short_outlet(gk.team, gk)
		if mate != null:
			e.pass_ball(gk, mate.pos + Vector2(e.teams[gk.team]["dir"] * 2.0, 0.0), false, mate)
			gk.state = "gk"
			return
	e.clear_ball(gk, Vector2(e.L * 0.5 + e.teams[gk.team]["dir"] * 10.0, 34.0 + e.rng.randf_range(-18.0, 18.0)))

# ---------------------------------------------------------------- on-ball ---

func _carrier_decide(p) -> void:
	var id: int = p.id
	if p.action_t > 0.0:
		return
	var cd: float = decide_cd.get(id, 0.0)
	if e.clock < cd:
		return
	var pressure: float = e.pressure_on(p)
	decide_cd[id] = e.clock + (0.55 + pressure * 0.16 + e.rng.randf_range(0.0, 0.18))
	var goal: Vector2 = e.target_goal_pos(p.team)
	var dist: float = p.pos.distance_to(goal)
	var angle: float = e.opponent_goal_angle(p)
	var style: Dictionary = e.teams[p.team]["data"]["style"]
	var own_third: bool = e.attacking_x(p.team, p.pos) < e.L * 0.34
	var final_third: bool = e.attacking_x(p.team, p.pos) > e.L * 0.66

	# --- shoot -------------------------------------------------------------
	if dist < 27.0 and angle > 0.05 and p.cooldown <= 0.0:
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
		var shoot_score: float = (p.attr["sho"] / 100.0) * 0.90 + angle * 1.15 - dist * 0.045 - pressure * 0.35 - blocked * 0.70
		if dist < 17.0:
			shoot_score += 0.45
		if dist < 11.0:
			shoot_score += 0.55
		if angle < 0.10:
			shoot_score -= 2.0
		if p.attr["sho"] < 55.0:
			shoot_score -= 0.30
		if final_third and e.rng.randf() < 0.04:
			shoot_score += 0.35
		if shoot_score > 2.05 + pressure * 0.22:
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
			return

	# Long shot from space (low xG, but it keeps defences honest).
	if dist >= 19.0 and dist < 30.0 and pressure < 0.55 and angle > 0.10 and p.cooldown <= 0.0:
		if p.attr["sho"] > 68.0 and e.rng.randf() < 0.030:
			var lside: float = 1.0 if e.rng.randf() < 0.5 else -1.0
			e.shoot_ball(p, lside * e.rng.randf_range(1.8, 3.0), e.rng.randf_range(0.4, 1.8), 1.0)
			return

	# --- pass --------------------------------------------------------------
	var best = null
	var best_s = -1e9
	var best_point: Vector2 = Vector2.ZERO
	var best_kind = "pass"
	var best_loft = false
	for q in e.teammates_of(p):
		if q.is_gk and dist > 34.0:
			continue
		var d: float = p.pos.distance_to(q.pos)
		if d < 2.6 or d > 48.0:
			continue
		var flight: float = d / 14.0
		var lead: Vector2 = q.vel * clampf(flight, 0.15, 1.1)
		var pt: Vector2 = q.pos + lead
		var lane: float = _lane_risk(p.pos, pt, p.team)
		var open: float = minf(10.0, e.nearest_opponent_dist(q.pos, p.team))
		var prog: float = (e.attacking_x(p.team, q.pos) - e.attacking_x(p.team, p.pos)) / 38.0
		var dpen: float = maxf(0.0, d - 12.0) * 0.045
		var s: float = -lane * 2.40 + open * 0.26 + prog * (0.55 + style["directness"] * 0.35) - dpen
		if d < 16.0:
			s += 0.20
		s += Attrs.role_push(q.role) * 0.18
		if prog < -0.25:
			s -= 0.35
		if d > 34.0:
			s -= 0.25
		if absf(q.pos.y - p.pos.y) > 26.0 and open > 7.0 and d < 42.0:
			s += 0.38
		# Through ball into space behind the defence (short and sharp, not a punt).
		if prog > 0.18 and Attrs.role_push(q.role) > 0.6 and d < 24.0:
			var space_behind: float = _space_behind(p.team, q)
			if space_behind > 4.0:
				var thru: Vector2 = q.pos + Vector2(e.teams[p.team]["dir"] * clampf(space_behind * 0.5, 4.0, 9.0), q.vel.y * 0.15)
				var tlane: float = _lane_risk(p.pos, thru, p.team)
				var ts: float = s + 0.20 - tlane * 1.2
				if ts > best_s:
					best_s = ts
					best = q
					best_point = thru
					best_kind = "through"
					best_loft = false
		# Cross from wide areas to a runner in the box.
		var wide: bool = absf(p.pos.y - 34.0) > 18.0
		var in_box: bool = e.attacking_x(p.team, q.pos) > e.L - 18.0 and absf(q.pos.y - 34.0) < 13.0
		if wide and in_box and d > 11.0 and d < 32.0:
			var cross_pt: Vector2 = q.pos + Vector2(e.teams[p.team]["dir"] * 2.2, 0.0)
			var cs: float = s + 0.28
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

	# --- dribble -----------------------------------------------------------
	var space: float = _space_ahead(p)
	var drib_score: float = (p.attr["dri"] / 100.0) * 1.18 + minf(space, 14.0) * 0.085 - pressure * 0.58
	drib_score += _urgency(p.team) * 0.55
	drib_score += (1.0 - style["directness"]) * 0.10
	if own_third and pressure > 1.0:
		drib_score -= 0.55

	var clear_score = -0.15
	if own_third and pressure > 0.55 and p.role != "ST":
		clear_score = 0.95 + pressure * 0.55
	var deep_own: bool = e.attacking_x(p.team, p.pos) < e.L * 0.13
	if deep_own:
		clear_score += 0.55

	# --- choose ------------------------------------------------------------
	if clear_score > drib_score and clear_score > best_s:
		var aim: Vector2 = Vector2(e.L * 0.5 + e.teams[p.team]["dir"] * 14.0, clampf(34.0 + e.rng.randf_range(-18.0, 18.0), 8.0, e.W - 8.0))
		e.clear_ball(p, aim)
		return
	if best != null and best_s > drib_score and best_s > 0.40:
		if e.verbose:
			e._vlog("  decide-pass %s score=%.2f vs dribble %.2f (%s %.0fm)" % [best.name, best_s, drib_score, best_kind, p.pos.distance_to(best.pos)])
		if chain_team != p.team:
			chain_team = p.team
			pass_chain[p.team] = []
		pass_chain[p.team].append(p.id)
		if pass_chain[p.team].size() > 3:
			pass_chain[p.team].pop_front()
		e.pass_ball(p, best_point, best_loft, best, best_kind)
		return
	# Dribble into space, steering away from the nearest opponent.
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
	# Wingers head for the byline.
	if p.role in ["RW", "LW"] and absf(p.pos.y - 34.0) > 16.0:
		dirv = (dirv + Vector2(0, signf(p.pos.y - 34.0)) * 0.15).normalized()
	p.target = p.pos + dirv * 9.0
	p.speed_scale = 1.0
	p.state = "dribble"
	# Occasional heavy touch under pressure.
	if pressure > 1.0 and e.rng.randf() < 0.012:
		var loose_dir: Vector2 = dirv.rotated(e.rng.randf_range(-0.8, 0.8))
		e.ball.owner_id = -1
		e.ball.vel = loose_dir * e.rng.randf_range(2.0, 4.5)
		e.ball.last_touch_id = p.id
		e.ball.last_touch_team = p.team
		p.has_ball = false

var last_progress := [-1.0, -1.0]
var last_progress_clock := [0.0, 0.0]

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

func _lane_risk(from: Vector2, to: Vector2, team: int) -> float:
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

func _space_ahead(p) -> float:
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

func _space_behind(team: int, q) -> float:
	var line = _offside_line(team)
	return maxf(0.0, line - e.attacking_x(team, q.pos))
