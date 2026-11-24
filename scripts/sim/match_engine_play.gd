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
	# A converted chance is already a goal by the model's account: nothing may
	# touch it before the line, or it would pass a second dice the xG never paid
	# for (a block, a header in flight, a crowd squirt). Priced-out chances stay
	# live and contestable.
	if ball.planned_goal:
		return
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
	# (A converted chance never reaches this loop: see the early return above.)
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
				ball.planned_save = false
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
