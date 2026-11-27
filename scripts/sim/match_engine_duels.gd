extends "res://scripts/sim/match_engine_presentation.gd"


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


func _stats_shot(p, xg: float, kind: String) -> void:
	p.stats["shots"] += 1
	stats[p.team]["shots"] += 1

func _header(p) -> void:
	var goal: Vector2 = target_goal_pos(p.team)
	var to_goal: Vector2 = goal - p.pos
	var attacking = false
	if ball.last_touch_team == p.team or ball.last_touch_team == -1:
		attacking = true
	p.jump_t = 0.45
	p.cooldown = 0.7
	ball.last_touch_id = p.id
	ball.last_touch_team = p.team
	ball.shot_team = -1
	ball.assist_id = -1
	ball.planned_goal = false
	ball.planned_save = false


	if (p.team == possession_team or attacking) and to_goal.length() < 18.0 \
			and absf(to_goal.x) > absf(to_goal.y) * 0.3:
		var hxg: float = 0.18 * float(xg_form[p.team])
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var ty: float = goal.y + side * minf(GOAL_W * 0.5 - 0.15, rng.randf_range(1.9, 3.2))
		if rng.randf() < clampf(hxg, 0.02, 0.86):
			ball.vel = (Vector2(goal.x, ty) - p.pos).normalized() * rng.randf_range(14.0, 18.0)
			ball.planned_goal = true
		else:
			var gkk = _gk_of(1 - p.team)
			var at_keeper: Vector2 = Vector2(goal.x, gkk.pos.y) if gkk != null else Vector2(goal.x, goal.y)
			ball.vel = (at_keeper - p.pos).normalized() * rng.randf_range(11.0, 15.0)
			ball.planned_save = true
		ball.vz = 0.4
		ball.z = maxf(ball.z, 1.1)
		_emit("header", Commentary.shot(rng, p.name, to_goal.length(), hxg, pressure_on(p), "header"), p.team, p)
		_stats_shot(p, hxg, "header")
		stats[p.team]["xg"] += hxg
	elif p.team == possession_team or attacking:

		var mate = _best_outlet(p)
		var tp: Vector2 = mate.pos if mate != null else p.pos + Vector2(teams[p.team]["dir"] * 8.0, 0.0)
		ball.vel = (tp - ball.pos).normalized() * 9.0
		ball.vz = 1.0
	else:

		var away = Vector2(teams[p.team]["dir"] * 24.0, rng.randf_range(-14.0, 14.0))
		ball.vel = away.normalized() * rng.randf_range(10.0, 16.0)
		ball.vz = 5.5
		ball.z = maxf(ball.z, 1.8)
		_emit("clearance", Commentary.clearance(rng, p.name, true), p.team, p)
		ball_kicked.emit(0.5)


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


	chance += MatchContact.tackle_bonus(style_of(d.team))
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


		foul_p *= MatchContact.foul_multiplier(style_of(d.team))
		if rng.randf() < foul_p:
			_award_foul(d, carrier)

func _award_foul(fouler, victim) -> void:
	var box = in_penalty_box(victim.pos, fouler.team)
	stats[fouler.team]["fouls"] += 1
	fouler.stats["fouls"] += 1

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

	if rng.randf() < 0.05:
		_injure(victim)


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

	manager.on_event("card", {"team": p.team, "red": card != "yellow"})

func _remove_body(p) -> void:
	p.vel = Vector2.ZERO
	p.has_ball = false
	if ball.owner_id == p.id:
		ball.owner_id = -1
	p.mark_id = -1
	_add_involvement(p, "card", "Sent off", p.pos)
