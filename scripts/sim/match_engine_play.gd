extends "res://scripts/sim/match_engine_actions.gd"

## Movement, ball physics and duels.

func _move_players(dt: float) -> void:
	# Flat position arrays for the separation pass (rebuilt per tick; see the
	# squad layer). Same arithmetic, same order, fewer member lookups.
	_sep_x.resize(players.size())
	_sep_y.resize(players.size())
	var idx := 0
	for q: Player in players:
		if q.sent_off:
			continue
		_sep_x[idx] = q.pos.x
		_sep_y[idx] = q.pos.y
		q._sep_idx = idx
		idx += 1
	_sep_count = idx
	for p: Player in players:
		if p.sent_off:
			continue
		if p.cooldown > 0.0:
			p.cooldown = maxf(0.0, p.cooldown - dt)
		if p.action_t > 0.0:
			p.action_t = maxf(0.0, p.action_t - dt)
		if p.jump_t > 0.0:
			p.jump_t = maxf(0.0, p.jump_t - dt)
			p.z = sin((1.0 - p.jump_t / 0.45) * PI) * 0.55 if p.jump_t > 0.0 else 0.0
		else:
			p.z = 0.0
		if p.dive_t > 0.0:
			p.dive_t = maxf(0.0, p.dive_t - dt)
			if p.dive_t <= 0.0:
				p.dive = Vector2.ZERO
		if p.celebrate > 0.0:
			p.celebrate = maxf(0.0, p.celebrate - dt)
			continue

		var to := p.target - p.pos
		var d := to.length()
		var fat := 0.70 + 0.30 * p.stamina
		var spd_cap := p.spd_max * fat * p.speed_scale
		var acc := p.acc * fat
		if ball.owner_id == p.id:
			spd_cap = p.dri_speed * fat * p.speed_scale
			acc *= 0.86
		elif p.is_gk:
			spd_cap = minf(spd_cap, 5.6 + float(p.gk["spd"]) * 0.022)
		var desired_speed: float = spd_cap
		if d < 3.0:
			desired_speed = minf(spd_cap, d * 2.4)
		var desired_vel := Vector2.ZERO
		if d > 0.02:
			desired_vel = to / d * desired_speed
		# separation from other bodies
		desired_vel += _separation(p, p._sep_idx) * 1.4
		var dv := desired_vel - p.vel
		var max_dv := acc * dt
		if dv.length() > max_dv:
			dv = dv.normalized() * max_dv
		p.vel += dv
		# clamp overspeed caused by separation pushes
		var vl := p.vel.length()
		if vl > spd_cap * 1.25:
			p.vel = p.vel.normalized() * spd_cap * 1.25
			vl = p.vel.length()
		p.pos += p.vel * dt
		# Publish the moved position: separation for later players must read it.
		_sep_x[p._sep_idx] = p.pos.x
		_sep_y[p._sep_idx] = p.pos.y
		var moved := vl * dt
		p.stats["distance"] += moved
		if vl > 0.3:
			p.facing = p.vel.normalized()
		# Attrs.stamina_drain, inlined on the cached top speed and phy factor.
		var intensity := clampf(vl / maxf(1.0, p.spd_max), 0.0, 1.0)
		var per_sec := 0.00055 + intensity * intensity * 0.0026
		var drain: float = per_sec * dt * p.drain_phy * (0.96 if p.team == home_team else 1.02)
		p.stamina = maxf(0.25, p.stamina - drain)
		# keep bodies loosely on the field
		p.pos.x = clampf(p.pos.x, -3.0, L + 3.0)
		p.pos.y = clampf(p.pos.y, -3.0, W + 3.0)
		if p.has_ball and ball.owner_id != p.id:
			p.has_ball = false

func _separation(p: Player, self_idx: int) -> Vector2:
	var push := Vector2.ZERO
	var px: float = p.pos.x
	var py: float = p.pos.y
	for j in _sep_count:
		if j == self_idx:
			continue
		# Cheap axis reject first: a body more than 1.7m away on either axis
		# cannot be inside the separation radius, and this loop runs for every
		# player on every sim tick.
		var dx: float = px - _sep_x[j]
		if dx > 1.7 or dx < -1.7:
			continue
		var dy: float = py - _sep_y[j]
		if dy > 1.7 or dy < -1.7:
			continue
		var d2: float = dx * dx + dy * dy
		if d2 < 1.7 * 1.7 and d2 > 0.0001:
			var d := sqrt(d2)
			var w := (1.7 - d) / 1.7
			push += Vector2(dx, dy) / d * w * 0.55
	return push

func _ball_physics(dt: float, goal_mode: bool = false) -> void:
	if ball.owner_id >= 0:
		var p = by_id.get(ball.owner_id, null)
		if p == null:
			ball.owner_id = -1
		else:
			# Dribble: the ball lives just ahead of the carrier's feet.
			var lead = 0.55 + 0.18 * sin(clock * 9.0 + p.id)
			var ahead = p.facing * lead + p.vel * 0.045
			var target = p.pos + ahead
			ball.pos = ball.pos.lerp(target, clampf(dt * 16.0, 0.0, 1.0))
			ball.vel = p.vel
			ball.z = 0.0
			ball.vz = 0.0
			return
	if ball.z > 0.001 or ball.vz > 0.0:
		ball.vz -= 9.81 * dt
		ball.z += ball.vz * dt
		# magnus / swerve
		if absf(ball.spin) > 0.01:
			var perp = Vector2(-ball.vel.y, ball.vel.x).normalized()
			ball.vel += perp * ball.spin * 0.35 * dt
		ball.vel *= (1.0 - 0.055 * dt)
		if ball.z <= 0.0:
			ball.z = 0.0
			if ball.vz < -0.6:
				ball.vz = -ball.vz * 0.48
				ball.vel *= 0.88
				ball.pos += ball.vel * dt
			else:
				ball.vz = 0.0
	else:
		var sp = ball.vel.length()
		if sp > 0.01:
			var dec = 0.95 + 0.055 * sp
			var ns = maxf(0.0, sp - dec * dt)
			ball.vel = ball.vel.normalized() * ns
		else:
			ball.vel = Vector2.ZERO
		ball.spin *= (1.0 - 2.2 * dt)
	if not goal_mode:
		ball.pos += ball.vel * dt
	else:
		ball.pos += ball.vel * dt * 0.55

func _ball_interactions(dt: float) -> void:
	# Owner keeps control only while the ball is at their feet.
	if ball.owner_id >= 0:
		var own = by_id.get(ball.owner_id, null)
		if own == null or own.pos.distance_to(ball.pos) > 2.4:
			ball.owner_id = -1
		else:
			ball.loose_t = 0.0
			# Opponents can challenge the carrier.
			for q in players:
				if q.team == own.team or q.sent_off or q.is_gk or q.cooldown > 0.0:
					continue
				if q.pos.distance_to(own.pos) < 1.85:
					_attempt_tackle(q, own)
					if ball.owner_id < 0:
						break
			if ball.owner_id >= 0:
				_after_owner_checks()
				return
	else:
		ball.loose_t += dt
	var in_flight: bool = ball.shot_team >= 0 and ball.vel.length() > 14.0
	for p in players:
		if p.sent_off or p.cooldown > 0.0 or in_flight:
			continue
		if p.is_gk:
			continue
		var dx = p.pos.x - ball.pos.x
		if absf(dx) > 2.2:
			continue
		var d = p.pos.distance_to(ball.pos)
		var cr = Attrs.control_radius(p)
		if d <= cr and ball.z < 2.1:
			if ball.owner_id >= 0:
				continue
			_try_control(p, d)
	# Goalkeepers handle the ball with their hands.
	var def_team := 0
	for t in range(2):
		if (teams[t]["dir"] == 1) == (ball.pos.x < L * 0.5):
			def_team = t
	var kgk = _gk_of(def_team)
	if kgk != null and not kgk.sent_off and kgk.cooldown <= 0.0 and ball.owner_id >= 0:
		# Smother a carrier who has broken through: keepers dive on the ball.
		var carried = by_id.get(ball.owner_id, null)
		if carried != null and carried.team != kgk.team and kgk.pos.distance_to(carried.pos) < 2.1:
			_gk_claim(kgk, kgk.pos.distance_to(ball.pos))
			return
	if kgk != null and not kgk.sent_off and kgk.cooldown <= 0.0 and ball.owner_id < 0 and not in_flight:
		var gdx = absf(kgk.pos.x - ball.pos.x)
		if gdx < 2.4:
			var d = kgk.pos.distance_to(ball.pos)
			var reach = 1.75 if ball.z < 2.6 else 1.2
			if d < reach:
				_gk_claim(kgk, d)
	# Desperate blocks: defenders in the shot lane can throw a body in the way.
	if ball.shot_team >= 0 and ball.z < 1.9 and clock - ball.shot_time < 0.9:
		for q in players:
			if q.team == ball.shot_team or q.sent_off or q.is_gk or q.cooldown > 0.0:
				continue
			if q.pos.distance_to(ball.pos) < 1.75:
				# An arm in the flight path is a handball, not a block.
				if rng.randf() < HANDBALL_P:
					_award_handball(q)
					break
				var defl: Vector2 = ball.vel.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(0.25, 0.5)
				if q.pos.distance_to(own_goal_pos(q.team)) < 22.0 and defl.dot(own_goal_pos(q.team) - q.pos) > 0.0:
					defl = Vector2(teams[q.team]["dir"], rng.randf_range(-1.0, 1.0)).normalized() * defl.length()
				ball.vel = defl
				ball.vz = rng.randf_range(0.5, 2.0)
				ball.z = maxf(ball.z, 0.3)
				ball.shot_team = -1
				ball.planned_goal = false
				ball.last_touch_id = q.id
				ball.last_touch_team = q.team
				q.cooldown = 0.5
				_emit("block", Commentary.block(rng, q.name, _last_kicker_name(q.team)), q.team, q)
				_flash(0.35)
				break
	# A loose ball in a crowd eventually squirts clear.
	if ball.owner_id < 0 and ball.loose_t > 1.2:
		var crowd = 0
		for p in players:
			if not p.sent_off and p.pos.distance_to(ball.pos) < 2.6:
				crowd += 1
		if crowd >= 3:
			ball.loose_t = 0.0
			var dir_out := Vector2.from_angle(rng.randf_range(0.0, TAU))
			if ball.pos.x < 12.0:
				dir_out = Vector2(1.0, rng.randf_range(-0.8, 0.8)).normalized()
			elif ball.pos.x > L - 12.0:
				dir_out = Vector2(-1.0, rng.randf_range(-0.8, 0.8)).normalized()
			ball.vel = dir_out * rng.randf_range(5.0, 9.0)
			ball.vz = rng.randf_range(0.5, 2.5)
			ball.z = 0.3
			for p in players:
				if not p.sent_off and p.pos.distance_to(ball.pos) < 2.0:
					p.cooldown = maxf(p.cooldown, 0.3)
	# Aerial duels: headers when the ball is up around head height.
	if ball.z > 0.9 and ball.z < 3.1 and ball.owner_id < 0:
		var winner = null
		var wscore = -1.0
		for p in players:
			if p.sent_off or p.cooldown > 0.0:
				continue
			var d = p.pos.distance_to(ball.pos)
			if d < 1.35:
				var a = Attrs.aerial(p)
				if a > wscore:
					wscore = a
					winner = p
		if winner != null:
			_header(winner)

func _after_owner_checks() -> void:
	pass

func _attempt_tackle(d, carrier) -> void:
	d.cooldown = 0.52
	d.state = "tackle"
	d.action_t = 0.25
	var dist = d.pos.distance_to(carrier.pos)
	var def: float = d.attr["def"] / 100.0
	var dri: float = carrier.attr["dri"] / 100.0
	var rel: Vector2 = carrier.pos - d.pos
	var align: float = clampf(d.facing.dot(rel.normalized()) if rel.length() > 0.01 else 0.0, -1.0, 1.0)
	var speed_adv: float = clampf((carrier.vel.length() - d.vel.length()) / 8.0, -1.0, 1.0)
	var chance: float = 0.10 + def * 0.50 - dri * 0.30 + (1.0 - dist / 1.9) * 0.22 + align * 0.10 - maxf(0.0, speed_adv) * 0.14
	chance += 0.020 if d.team == home_team else -0.015
	chance = clampf(chance, 0.04, 0.60)
	if rng.randf() < chance:
		d.stats["tackles"] += 1
		stats[d.team]["tackles"] += 1
		carrier.has_ball = false
		carrier.cooldown = 0.45
		ball.owner_id = -1
		ball.last_touch_id = d.id
		ball.last_touch_team = d.team
		ball.shot_team = -1
		ball.assist_id = -1
		ball.pos = carrier.pos + (d.pos - carrier.pos).normalized() * 0.35
		var away_dir := Vector2(teams[d.team]["dir"], rng.randf_range(-0.75, 0.75)).normalized()
		ball.vel = away_dir * rng.randf_range(2.0, 4.5)
		ball.z = 0.0
		ball.vz = 0.0
		possession_team = d.team
		possession_loose = true
		_add_involvement(d, "tackle", "Tackle won", d.pos)
		_flash(0.25)
	else:
		var foul_p: float = 0.0055 + (1.0 - def) * 0.007
		if d.pos.distance_to(own_goal_pos(carrier.team)) < 30.0:
			foul_p += 0.02
		if in_penalty_box(carrier.pos, d.team):
			foul_p *= 0.40
		if rng.randf() < foul_p:
			_award_foul(d, carrier)

func _award_foul(fouler, victim) -> void:
	var box = in_penalty_box(victim.pos, fouler.team)
	stats[fouler.team]["fouls"] += 1
	fouler.stats["fouls"] += 1
	# Card decision.
	var dogso = false
	var ax = attacking_x(victim.team, victim.pos)
	if ax > L * 0.62 and not box:
		var defenders_behind = 0
		for q in players:
			if q.team == fouler.team and not q.sent_off and not q.is_gk:
				if attacking_x(victim.team, q.pos) < ax:
					defenders_behind += 1
		dogso = defenders_behind <= 1
	var card = ""
	var r = rng.randf()
	if dogso and r < 0.10:
		card = "red"
	elif r < 0.11:
		card = "yellow"
	if card == "yellow":
		fouler.yellow += 1
		stats[fouler.team]["yellow"] += 1
		if fouler.yellow >= 2:
			card = "red_second"
	elif card == "red":
		stats[fouler.team]["red"] += 1
	if card != "":
		_send_off_or_book(fouler, card)
	var spot = victim.pos
	if box:
		spot = Vector2(PEN_D if fouler.team == 1 else L - PEN_D, W * 0.5)
		_emit("foul", Commentary.foul(rng, fouler.name, victim.name, true), victim.team, victim)
		_start_restart("penalty", victim.team, spot, 3.6)
	else:
		_emit("foul", Commentary.foul(rng, fouler.name, victim.name, false), victim.team, victim)
		_start_restart("free_kick", victim.team, spot, 2.6)
	_flash(0.4)
	# A bad challenge can take the victim off as well.
	if rng.randf() < 0.05:
		_injure(victim)

## The ball struck an arm in the flight path. Restart to the attacking side:
## a penalty inside the box, a free kick anywhere else.
func _award_handball(q) -> void:
	var box: bool = in_penalty_box(q.pos, q.team)
	var attack: int = 1 - q.team
	stats[q.team]["handballs"] += 1
	q.stats["handballs"] = int(q.stats.get("handballs", 0)) + 1
	ball.shot_team = -1
	ball.last_touch_id = q.id
	ball.last_touch_team = q.team
	possession_team = attack
	_flash(0.4)
	_emit("handball", Commentary.handball(rng, q.name, box), attack, q)
	_add_involvement(q, "handball", "Handball", q.pos)
	if box:
		_start_restart("penalty", attack, q.pos, 3.6)
	else:
		_start_restart("free_kick", attack, q.pos, 2.6)

func _send_off_or_book(p, card: String) -> void:
	var line: String = Commentary.card(rng, p.name, card)
	if card == "yellow":
		_emit("card", line, p.team, p)
	elif card == "red_second":
		p.red = true
		p.sent_off = true
		_touch_squad()
		_emit("card", line, p.team, p)
		stats[p.team]["red"] += 1
		_remove_body(p)
	else:
		p.red = true
		p.sent_off = true
		_touch_squad()
		_emit("card", line, p.team, p)
		_remove_body(p)
	stoppage_events += 1
	# A card changes the picture: the dugouts weigh a response.
	manager.on_event("card", {"team": p.team, "red": card != "yellow"})

func _remove_body(p) -> void:
	p.vel = Vector2.ZERO
	p.has_ball = false
	if ball.owner_id == p.id:
		ball.owner_id = -1
	p.mark_id = -1
	_add_involvement(p, "card", "Sent off", p.pos)
