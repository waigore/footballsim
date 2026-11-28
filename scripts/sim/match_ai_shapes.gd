class_name MatchAIShapes
extends RefCounted


var brain = null
var e = null
var pq = null


func _init(owner: MatchAI) -> void:
	brain = owner
	e = owner.e
	pq = owner.pq


func update() -> void:
	var bt: int = e.possession_team
	var ball = e.ball


	var dlines := {}
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
		var style: Dictionary = e.style_of(p.team)
		var b: Vector2 = p.base
		var bn: Vector2 = e.to_norm(p.team, ball.pos)
		var attacking: bool = (p.team == bt)
		var tx = 0.0
		var ty = 0.0
		if attacking:
			tx = b.x * 0.90 + 0.115 + (bn.x - 0.5) * 0.16
			ty = 0.5 + (b.y - 0.5) * (0.82 + style["width"] * 0.42)
			tx += e.push_of(p) * 0.055
			tx += style["possession"] * 0.03
		else:
			var line: float = style["line"]
			tx = b.x * 0.88 + 0.055 + bn.x * 0.30 - 0.12 - (line - 0.5) * 0.10
			ty = 0.5 + (b.y - 0.5) * 0.78

			ty -= (bn.y - 0.5) * 0.10
		tx = clampf(tx, 0.035, 0.96)
		ty = clampf(ty, 0.035, 0.965)
		var target: Vector2 = e.to_world(p.team, Vector2(tx, ty))
		if attacking:
			target = _attack_shape(p, target)
		else:
			target = _defence_shape(p, target, dlines)
		p.target = target
		p.speed_scale = 0.86 if attacking else 0.94
	_apply_pressing()


func _attack_shape(p: Variant, fallback: Vector2) -> Vector2:
	var ball = e.ball
	var ax = e.attacking_x(p.team, ball.pos)
	var my_ax = e.attacking_x(p.team, p.pos)
	var style: Dictionary = e.style_of(p.team)
	var target = fallback

	if e.push_of(p) >= 0.7 and ax > e.L * 0.48:
		var line = pq.offside_line(p.team)
		var run_x = line - e.rng.randf_range(0.4, 2.4)
		if my_ax < run_x:
			var world_y = p.pos.y
			if p.role == "ST":
				world_y = lerpf(world_y, 34.0, 0.35)

			var world_x = e.teams[p.team]["dir"] * 1.0
			var w = Vector2(run_x if e.teams[p.team]["dir"] == 1 else e.L - run_x, world_y)
			target = w

	var owner = e.ball_owner()
	if owner != null and owner.team == p.team and owner.id != p.id:
		var d = p.pos.distance_to(owner.pos)
		if d < 16.0 and e.push_of(p) > 0.2:
			var ahead: Vector2 = target
			ahead.x += e.teams[p.team]["dir"] * 2.0
			target = target.lerp(ahead, 0.25)

	if p.role in ["RW", "LW"] and absf(ball.pos.y - 34.0) < 12.0:
		target.y = lerpf(target.y, 8.0 if p.role == "RW" else 60.0, 0.35)

	if e.push_of(p) >= 0.6:
		var line = pq.offside_line(p.team)
		var cap = line - 0.35
		var tx_att = e.attacking_x(p.team, target)
		var ball_att = e.attacking_x(p.team, ball.pos)
		if tx_att > cap and ball_att < cap:
			var capped = maxf(cap, ball_att) if ball_att > e.L * 0.5 else cap
			target.x = capped if e.teams[p.team]["dir"] == 1 else e.L - capped
	return target


func _defence_shape(p: Variant, fallback: Vector2, dlines: Dictionary = {}) -> Vector2:
	var own: Vector2 = e.own_goal_pos(p.team)
	var ball = e.ball
	var dist_to_own: float = ball.pos.distance_to(own)
	var target: Vector2 = fallback
	var is_back: bool = Attrs.is_defender(p.role)
	var is_holder: bool = p.role in ["RDM", "LDM", "CDM"]

	if dist_to_own < 21.0 and is_back:
		var axis_w: Vector2 = (ball.pos - own).normalized()
		if axis_w.length() < 0.1:
			axis_w = Vector2(1, 0)
		var perp_w: Vector2 = Vector2(-axis_w.y, axis_w.x)
		var lat: float = (p.base.y - 0.5) * 2.0
		return own + axis_w * 4.6 + perp_w * (lat * 8.5)

	if dist_to_own < 34.0 and (is_back or is_holder):
		var to_ball: Vector2 = (ball.pos - own)
		if to_ball.length() < 0.1:
			to_ball = Vector2(1, 0)
		var axis: Vector2 = to_ball.normalized()
		var perp: Vector2 = Vector2(-axis.y, axis.x)
		var lateral: float = (p.base.y - 0.5) * 2.0

		var depth: float = dist_to_own - (4.5 if is_back else 7.5)
		depth = clampf(depth, 1.6, 30.0)
		var spread: float = (8.0 if is_back else 11.0) * lateral
		target = own + axis * depth + perp * spread


	var threat = null
	if p.mark_id >= 0:
		var marked = e.by_id.get(p.mark_id, null)
		if marked != null and not marked.sent_off and marked.team != p.team:
			threat = marked
	if threat == null:
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

		if mark.distance_to(own) < dist_to_own + 2.5:
			target = mark

	if dist_to_own < 26.0 and target.distance_to(own) > dist_to_own + 3.5:
		target = own + (target - own).normalized() * (dist_to_own + 3.5)
	if is_back:
		if not dlines.has(p.team):
			dlines[p.team] = pq.defensive_line(p.team)
		var defensive_line: Vector2 = dlines[p.team]
		var ax2: float = e.attacking_x(p.team, target)
		var line_ax: float = e.attacking_x(p.team, defensive_line)
		ax2 = clampf(ax2, line_ax - 11.0, line_ax + 1.5)
		target.x = ax2 if e.teams[p.team]["dir"] == 1 else e.L - ax2
	return target


func _apply_pressing() -> void:
	var bt: int = e.possession_team


	var path: Dictionary = pq.ball_trajectory()

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
			var rt: float = pq.reach_time_on(p, path)
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
		var style: Dictionary = e.style_of(t)
		var max_press: float = 20.0 + style["press"] * 26.0 + (7.0 if style["press_trigger"] == "high" else 0.0)
		if t == e.home_team:
			max_press += 2.5
		var owner = e.ball_owner()
		if best_t < 9.0 and (e.ball.owner_id < 0 or e.ball.pos.distance_to(presser.pos) < max_press):
			var target: Vector2
			if owner != null and owner.team != t:
				target = owner.pos + owner.vel * 0.20
				target += (e.own_goal_pos(t) - owner.pos).normalized() * 0.5
			else:
				target = pq.intercept_on(presser, path)
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

			var third = null
			var third_t := 99.0
			for p in e.players:
				if p.team != t or p.sent_off or p.is_gk or p == presser or p == second:
					continue
				var rt: float = pq.reach_time_on(p, path)
				if rt < third_t:
					third_t = rt
					third = p
			if third != null and third_t < 3.0:
				third.target = e.ball.pos + e.ball.vel * 0.10
				third.speed_scale = 1.0


func assign_marks() -> void:
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


			if best != null and bd < MatchMarking.band(e.style_of(1 - t)):
				best.mark_id = a.id


func _gk_shape(gk: Variant) -> void:
	var own: Vector2 = e.own_goal_pos(gk.team)
	var ball = e.ball
	var to_ball: Vector2 = ball.pos - own
	var dist = to_ball.length()
	var target: Vector2

	var toward_goal: bool = ball.vel.dot(Vector2(-float(e.teams[gk.team]["dir"]), 0.0)) > 2.0
	if toward_goal and dist < 34.0 and ball.vel.length() > 9.0:
		var t_cross = (own.x - ball.pos.x) / maxf(absf(ball.vel.x), 0.1) * signf(ball.vel.x)
		if t_cross > 0.0 and t_cross < 1.6:
			var y_cross: float = ball.pos.y + ball.vel.y * t_cross
			var react: float = brain.gk_react_at[gk.team]
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


	var depth = clampf(5.0 - dist * 0.065, 1.2, 4.0)
	var guard: Vector2 = own + to_ball.normalized() * depth

	guard.y = clampf(guard.y, own.y - 2.8, own.y + 2.8)
	guard.x = clampf(guard.x, minf(own.x, own.x + (2.0 if gk.team == 0 else -2.0)), maxf(own.x, own.x + (2.0 if gk.team == 0 else -2.0)))

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
